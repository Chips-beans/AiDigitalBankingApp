import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/accounts/pair_opening.dart';
import 'package:customer_app/features/accounts/presentation/pair_opening_panel.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/qr/presentation/receive_qr_panel.dart';
import 'package:customer_app/features/qr/presentation/scan_qr_panel.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show FakePairs, FakeQr, signedSession, sampleQr;
import 'transactions_test.dart' show funded, FakeTransactions;

class FakeCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  int starts = 0, stops = 0, analyses = 0;
  bool denied = false;
  BarcodeCapture? imageResult = const BarcodeCapture(
    barcodes: [Barcode(rawValue: sampleQr, format: BarcodeFormat.qrCode)],
  );
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> pause() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Widget buildCameraView() => const ColoredBox(color: Color(0xff111111));
  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async {
    analyses++;
    return imageResult;
  }
}

Widget harness(
  Widget child, {
  bool khmer = false,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) {
  final prefs = AppPreferences()..locale = Locale(khmer ? 'km' : 'en');
  return AppPreferencesScope(
    preferences: prefs,
    child: MaterialApp(
      locale: prefs.locale,
      supportedLocales: const [Locale('en'), Locale('km')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.build(brightness, locale: prefs.locale),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late SessionController session;
  late AccountsController accounts;
  late TransferController transfers;
  late FakeQr gateway;
  late FakeCamera camera;
  late MobileScannerPlatform previous;
  setUp(() async {
    previous = MobileScannerPlatform.instance;
    MobileScannerController.resetPlatformSessionOwner();
    camera = FakeCamera();
    MobileScannerPlatform.instance = camera;
    session = await signedSession();
    accounts = AccountsController(
      session,
      FakeAccounts()
        ..data = [
          funded(1, balance: '200'),
          funded(3, currency: 'KHR', balance: '100000'),
        ],
      MemoryCreationStore(),
    );
    await accounts.initialize();
    transfers = TransferController(
      session,
      FakeTransactions(),
      MemoryTransferStore(),
    );
    await transfers.initialize();
    gateway = FakeQr();
  });
  tearDown(() async {
    accounts.dispose();
    transfers.dispose();
    session.dispose();
    await camera.captures.close();
    MobileScannerPlatform.instance = previous;
    MobileScannerController.resetPlatformSessionOwner();
  });
  testWidgets(
    'camera detection stops capture, suppresses duplicates and opens verified review',
    (tester) async {
      await tester.pumpWidget(
        harness(
          ScanQrPanel(
            session: session,
            gateway: gateway,
            accounts: accounts,
            transfers: transfers,
            enabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(camera.starts, 1);
      camera.captures.add(camera.imageResult);
      camera.captures.add(camera.imageResult);
      await tester.pumpAndSettle();
      expect(gateway.scans, 1);
      expect(camera.stops, greaterThanOrEqualTo(1));
      expect(find.text('Sok Dara'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('qr-transfer-amount')),
        '10',
      );
      await tester.ensureVisible(find.text('Review transfer'));
      await tester.tap(find.text('Review transfer'));
      await tester.pumpAndSettle();
      expect(transfers.review!.qrString, sampleQr);
      expect(find.text('Sok Dara'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm and send'));
      await tester.tap(find.text('Confirm and send'));
      await tester.pumpAndSettle();
      expect(find.text('Transfer confirmed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('permission denial retains image import and camera retry', (
    tester,
  ) async {
    camera.denied = true;
    await tester.pumpWidget(
      harness(
        ScanQrPanel(
          session: session,
          gateway: gateway,
          accounts: accounts,
          transfers: transfers,
          enabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera access is denied.'), findsWidgets);
    expect(find.text('Choose QR image'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'image cancellation ends the handoff without contacting the backend',
    (tester) async {
      await tester.pumpWidget(
        harness(
          ScanQrPanel(
            session: session,
            gateway: gateway,
            accounts: accounts,
            transfers: transfers,
            enabled: true,
            chooseImage: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose QR image'));
      await tester.pumpAndSettle();
      expect(session.trustedImageSelection, false);
      expect(gateway.scans, 0);
      expect(camera.analyses, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('QR image is decoded locally before showing the recipient', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5f8AAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      harness(
        ScanQrPanel(
          session: session,
          gateway: gateway,
          accounts: accounts,
          transfers: transfers,
          enabled: true,
          chooseImage: () async => XFile.fromData(
            png,
            name: 'qr.png',
            mimeType: 'image/png',
            path: '/fixture/qr.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Choose QR image'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(camera.analyses, 1);
    expect(gateway.scans, 1);
    expect(find.text('Sok Dara'), findsOneWidget);
    expect(session.trustedImageSelection, false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('oversized QR images are rejected before native decoding', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ScanQrPanel(
          session: session,
          gateway: gateway,
          accounts: accounts,
          transfers: transfers,
          enabled: true,
          chooseImage: () async =>
              XFile.fromData(Uint8List(5 * 1024 * 1024 + 1), name: 'large.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose QR image'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a JPG or PNG containing one QR code, up to 5 MB.'),
      findsOneWidget,
    );
    expect(camera.analyses, 0);
    expect(gateway.scans, 0);
    expect(session.trustedImageSelection, false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'an image without a QR shows recovery and never contacts the backend',
    (tester) async {
      camera.imageResult = null;
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5f8AAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        harness(
          ScanQrPanel(
            session: session,
            gateway: gateway,
            accounts: accounts,
            transfers: transfers,
            enabled: true,
            chooseImage: () async => XFile.fromData(
              png,
              name: 'no-qr.png',
              path: '/fixture/no-qr.png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose QR image'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        find.text('No QR code was found. Choose another image.'),
        findsOneWidget,
      );
      expect(gateway.scans, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('camera stops when inactive and no capture reaches the backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ScanQrPanel(
          session: session,
          gateway: gateway,
          accounts: accounts,
          transfers: transfers,
          enabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    camera.captures.add(camera.imageResult);
    await tester.pump();
    expect(camera.stops, greaterThanOrEqualTo(1));
    expect(gateway.scans, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('receive and paired opening adapt to Khmer dark large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      harness(
        ReceiveQrPanel(session: session, gateway: gateway, accounts: accounts),
        khmer: true,
        brightness: Brightness.dark,
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.text('Sok Dara'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final pairs = PairOpeningController(
      session,
      FakePairs(),
      PairOpeningStore(),
      onSuccess: () async {},
    );
    await tester.pumpWidget(
      harness(
        PairOpeningPanel(model: pairs, legacyPending: false, onOpened: () {}),
        khmer: true,
        brightness: Brightness.dark,
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.text('USD 200.00'), findsOneWidget);
    expect(find.text('KHR 100,000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pairs.dispose();
  });
  testWidgets(
    'receive removes an account QR when refresh makes its account inactive',
    (tester) async {
      await tester.pumpWidget(
        harness(
          ReceiveQrPanel(
            session: session,
            gateway: gateway,
            accounts: accounts,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sok Dara'), findsOneWidget);
      (accounts.gateway as FakeAccounts).data = [
        funded(1, status: 'FROZEN'),
        funded(3, currency: 'KHR', balance: '100000'),
      ];
      await accounts.refresh();
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.text('Sok Dara'), findsNothing);
      expect(
        find.text('Choose an active account to receive money.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('legacy uncertain opening blocks pair confirmation', (
    tester,
  ) async {
    final pairs = PairOpeningController(
      session,
      FakePairs(),
      PairOpeningStore(),
      onSuccess: () async {},
    );
    await tester.pumpWidget(
      harness(
        PairOpeningPanel(model: pairs, legacyPending: true, onOpened: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm open accounts'),
    );
    expect(button.onPressed, null);
    await tester.pumpWidget(const SizedBox.shrink());
    pairs.dispose();
  });
}
