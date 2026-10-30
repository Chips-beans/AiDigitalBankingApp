import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/data/profile_photo.dart';
import 'package:customer_app/features/auth/presentation/continuation_pages.dart';
import 'package:customer_app/features/auth/presentation/profile_photo_card.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGklEQVR4nGM4u1j/PyWYYdSAUQNGDRguBgAAMs+eH/3OiiEAAAAASUVORK5CYII=',
);

class PendingPhotoGateway extends DemoAuthGateway {
  late final upload = Completer<ProfilePhoto>();
  int uploads = 0;
  @override
  Future<ProfilePhoto> savePhoto(String access, Uint8List bytes) {
    uploads++;
    return upload.future;
  }
}

void main() {
  late PendingPhotoGateway gateway;
  late SessionController session;

  setUp(() async {
    gateway = PendingPhotoGateway();
    session = SessionController(gateway, MemorySessionVault());
    await session.initialize();
    session.openEmail();
    await session.beginEmail('avatar@example.test');
    await session.verifyCode('123456');
  });
  tearDown(() => session.dispose());

  Widget harness(Widget child, {bool dark = false, bool khmer = false}) {
    final locale = Locale(khmer ? 'km' : 'en');
    return AppPreferencesScope(
      preferences: AppPreferences()..locale = locale,
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('km')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.build(
          dark ? Brightness.dark : Brightness.light,
          locale: locale,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  Widget card({Future<XFile?> Function()? chooseImage}) => ProfilePhotoCard(
    session,
    displayName: 'Dara',
    chooseImage:
        chooseImage ??
        () async =>
            XFile.fromData(png, name: 'photo.png', mimeType: 'image/png'),
  );

  Uint8List displayedBytes(WidgetTester tester) {
    final avatar = find.byKey(const ValueKey('profile-photo-avatar'));
    final image = tester.widget<Image>(
      find.descendant(of: avatar, matching: find.byType(Image)),
    );
    final provider = image.image as ResizeImage;
    return (provider.imageProvider as MemoryImage).bytes;
  }

  Future<void> selectPhoto(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('upload-profile-photo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  // Device regression (31 Oct): opening the gallery makes the app inactive, which
  // raises the privacy cover; the picked photo was then silently discarded.
  testWidgets('a photo picked while the privacy cover is up is still uploaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        card(
          chooseImage: () async {
            session.privacyCovered = true;
            session.uncoverPrivateContent(); // notifies listeners…
            session.privacyCovered = true; // …while the cover is still up on return
            return XFile.fromData(png, name: 'photo.png', mimeType: 'image/png');
          },
        ),
      ),
    );
    await tester.pump();
    await selectPhoto(tester);
    expect(gateway.uploads, 1);
    session.uncoverPrivateContent();
    gateway.upload.complete(ProfilePhoto(png, 'image/png'));
    await tester.pumpAndSettle();
    expect(session.profilePhoto?.bytes, png);
  });

  testWidgets('create profile initial follows name edits in both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(harness(InformationPage(session), dark: dark));
      await tester.pumpAndSettle();
      final initial = find.byKey(const ValueKey('profile-photo-initial'));
      expect(initial, findsNothing);
      await tester.enterText(find.byKey(const ValueKey('firstName')), '  dara');
      await tester.pump();
      expect(tester.widget<Text>(initial).data, 'D');
      await tester.enterText(find.byKey(const ValueKey('firstName')), 'éva');
      await tester.pump();
      expect(tester.widget<Text>(initial).data, 'É');
      await tester.enterText(find.byKey(const ValueKey('firstName')), '');
      await tester.enterText(find.byKey(const ValueKey('lastName')), 'Sok');
      await tester.pump();
      expect(tester.widget<Text>(initial).data, 'S');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Khmer initial stays readable at large text on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 667),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: InformationPage(session),
        ),
        dark: true,
        khmer: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('firstName')), 'ដារ៉ា');
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profile-photo-initial')))
          .data,
      'ដា',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected image displays while upload is still pending', (
    tester,
  ) async {
    await tester.pumpWidget(harness(card()));
    await tester.pumpAndSettle();
    await selectPhoto(tester);
    expect(gateway.uploads, 1);
    expect(session.profilePhoto, isNull);
    expect(displayedBytes(tester), png);
    expect(find.text('Uploading photo…'), findsOneWidget);
    // Decode the preview too: the visible image must not be an error fallback.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    final saved = ProfilePhoto(Uint8List.fromList(png), 'image/png');
    gateway.upload.complete(saved);
    await tester.pumpAndSettle();
    expect(displayedBytes(tester), same(saved.bytes));
    expect(find.text('Change photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final hasSavedPhoto in [false, true]) {
    testWidgets(
      'failed upload restores ${hasSavedPhoto ? 'saved photo' : 'initial'}',
      (tester) async {
        final saved = ProfilePhoto(Uint8List.fromList(png), 'image/png');
        session.photoLoaded = true;
        if (hasSavedPhoto) session.profilePhoto = saved;
        await tester.pumpWidget(harness(card()));
        await tester.pumpAndSettle();
        await selectPhoto(tester);
        expect(displayedBytes(tester), png);
        gateway.upload.completeError(
          const ApiFailure('OFFLINE', 'Cannot reach the service.'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cannot reach the service.'), findsOneWidget);
        if (hasSavedPhoto) {
          expect(displayedBytes(tester), same(saved.bytes));
        } else {
          expect(find.text('D'), findsOneWidget);
          expect(session.profilePhoto, isNull);
        }
        expect(gateway.uploads, 1);
      },
    );
  }

  testWidgets(
    'cancelled or oversized selection keeps the default without upload',
    (tester) async {
      for (final selection in <XFile?>[
        null,
        XFile.fromData(Uint8List(maxProfilePhotoBytes + 1), name: 'large.png'),
      ]) {
        await tester.pumpWidget(
          harness(card(chooseImage: () async => selection)),
        );
        await tester.pumpAndSettle();
        await selectPhoto(tester);
        await tester.pumpAndSettle();
        expect(find.text('D'), findsOneWidget);
        expect(gateway.uploads, 0);
        expect(session.trustedImageSelection, false);
      }
    },
  );

  testWidgets('logout discards preview and ignores an upload finishing late', (
    tester,
  ) async {
    await tester.pumpWidget(harness(card()));
    await tester.pumpAndSettle();
    await selectPhoto(tester);
    expect(displayedBytes(tester), png);
    await tester.runAsync(session.signOut);
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    gateway.upload.complete(ProfilePhoto(png, 'image/png'));
    await tester.pumpAndSettle();
    expect(session.profilePhoto, isNull);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout during picker prevents upload after selection returns', (
    tester,
  ) async {
    final selection = Completer<XFile?>();
    await tester.pumpWidget(harness(card(chooseImage: () => selection.future)));
    await tester.pumpAndSettle();
    await selectPhoto(tester);
    await tester.runAsync(session.signOut);
    selection.complete(XFile.fromData(png, name: 'photo.png'));
    await tester.pumpAndSettle();
    expect(gateway.uploads, 0);
    expect(find.byType(Image), findsNothing);
  });
}
