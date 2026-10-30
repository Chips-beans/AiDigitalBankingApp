import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/data/app_pin_gateway.dart';

import 'dart:async';

import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/assistant/assistant_controller.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/assistant/presentation/assistant_screen.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show signedSession;
import 'transactions_test.dart' show FakeTransactions, funded;
import 'support/assistant_fakes.dart';

void main() {
  late SessionController session;
  late FakeAssistant api;
  late AssistantController model;
  late AppPreferences prefs;
  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    double scale = 1,
    String locale = 'en',
  }) async {
    session = await signedSession();
    api = FakeAssistant()..enabled = enabled;
    model = AssistantController(session, api, AssistantPendingStore());
    prefs = AppPreferences()..locale = Locale(locale);
    await tester.pumpWidget(
      AppPreferencesScope(
        preferences: prefs,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, locale: prefs.locale),
          home: MediaQuery(
            data: MediaQueryData(
              size: tester.view.physicalSize,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: AssistantScreen(
                controller: model,
                onAction: (_) {},
                bottomClearance: 104,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      session.dispose();
      prefs.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  }

  testWidgets(
    'question sends once and renders verified cards and recorded time',
    (tester) async {
      await mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('assistant-question')),
        'Show my balances',
      );
      await tap(tester, find.byKey(const ValueKey('assistant-send')));
      expect(api.requests, hasLength(1));
      expect(find.text('USD 190.00'), findsOneWidget);
      expect(find.text('KHR 90000'), findsOneWidget);
      expect(find.textContaining('Data as of'), findsOneWidget);
      expect(find.text('AI explanation'), findsOneWidget);
      await tap(tester, find.byTooltip('New conversation'));
      expect(model.messages, isEmpty);
      expect(api.requests, hasLength(1));
    },
  );
  testWidgets('history opens, renames and deletes the customer conversation', (
    tester,
  ) async {
    await mount(tester);
    await model.send('Show my balances', 'en');
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Conversation history'));
    expect(
      find.text(
        'Conversations expire after 30 days. You can delete them earlier.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.byType(PopupMenuButton<String>));
    await tap(tester, find.text('Rename conversation'));
    await tester.enterText(find.byType(TextField).last, 'My October overview');
    await tap(tester, find.text('Save'));
    expect(model.conversations.single.title, 'My October overview');
    await tap(tester, find.byTooltip('Conversation history'));
    await tap(tester, find.byType(PopupMenuButton<String>));
    await tap(tester, find.text('Delete conversation'));
    await tap(tester, find.text('Delete'));
    expect(model.conversations, isEmpty);
    expect(model.messages, isEmpty);
  });
  testWidgets('private history sheet disappears on logout', (tester) async {
    await mount(tester);
    await model.send('Show my balances', 'en');
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Conversation history'));
    await session.signOut();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Conversations expire after 30 days. You can delete them earlier.',
      ),
      findsNothing,
    );
    expect(find.text('USD 190.00'), findsNothing);
    expect(model.messages, isEmpty);
    expect(tester.takeException(), null);
  });
  testWidgets('unavailable provider is explicit and composer cannot submit', (
    tester,
  ) async {
    await mount(tester, enabled: false);
    expect(
      find.text(
        'The assistant is unavailable. Your banking services remain available.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('assistant-question')))
          .enabled,
      false,
    );
    expect(api.requests, isEmpty);
  });
  for (final size in [const Size(320, 667), const Size(812, 375)]) {
    testWidgets('large Khmer text and composer fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, scale: 2, locale: 'km');
      expect(tester.takeException(), null);
      await tester.enterText(
        find.byKey(const ValueKey('assistant-question')),
        'សូមបង្ហាញសមតុល្យ',
      );
      await tap(tester, find.byKey(const ValueKey('assistant-send')));
      expect(api.requests.single.locale, 'km');
      expect(tester.takeException(), null);
    });
  }
  testWidgets('composer and header have labelled Android touch targets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.pumpWidget(const SizedBox.shrink());
    handle.dispose();
  });
  testWidgets(
    'Home navigation connects the assistant and its account action refreshes details',
    (tester) async {
      session = await signedSession();
      api = FakeAssistant();
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
          ),
          accountGateway: FakeAccounts()..data = [funded(1, balance: '190.00')],
          creationStore: MemoryCreationStore(),
          transactionGateway: FakeTransactions(),
          transferStore: MemoryTransferStore(),
          assistantGateway: api,
          assistantStore: AssistantPendingStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('AI assistant'));
      expect(find.text('Your Kesor assistant'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('assistant-question')),
        'Show my balances',
      );
      await tap(tester, find.byKey(const ValueKey('assistant-send')));
      await tap(tester, find.text('View account').first);
      expect(find.text('Account details'), findsOneWidget);
      expect(api.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
  testWidgets(
    'keyboard clears the floating navigation and keeps the large-text composer visible',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      session = await signedSession();
      api = FakeAssistant();
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
          ),
          accountGateway: FakeAccounts()..data = [funded(1)],
          creationStore: MemoryCreationStore(),
          transactionGateway: FakeTransactions(),
          transferStore: MemoryTransferStore(),
          assistantGateway: api,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('AI assistant'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kesor-nav-capsule')), findsNothing);
      final bars = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
      );
      expect(bars.value.statusBarIconBrightness, Brightness.dark);
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('assistant-send'))).dy,
        lessThanOrEqualTo(367),
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
  testWidgets(
    'background PIN lock hides chat and unlock recovers without resending',
    (tester) async {
      final auth = DemoAuthGateway();
      final pin = DemoAppPinGateway(auth);
      session = SessionController(auth, MemorySessionVault(), pinGateway: pin);
      await session.initialize();
      session.openEmail();
      await session.beginEmail('ai-pin@example.test');
      await session.verifyCode('123456');
      await session.completeInformation('Dara', 'Sok');
      await session.submitPin('0427');
      await session.submitPin('0427');
      expect(session.phase, SessionPhase.signedIn);
      api = FakeAssistant()..sendGate = Completer<void>();
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
          ),
          accountGateway: FakeAccounts()..data = [funded(1)],
          creationStore: MemoryCreationStore(),
          transactionGateway: FakeTransactions(),
          transferStore: MemoryTransferStore(),
          assistantGateway: api,
          assistantStore: AssistantPendingStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('AI assistant'));
      await tester.enterText(
        find.byKey(const ValueKey('assistant-question')),
        'Show my balances',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assistant-send')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.requests, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(session.privacyCovered, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      api.sendGate!.complete();
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.pinLocked);
      expect(find.text('USD 190.00'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await session.submitPin('0427');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('AI assistant'));
      expect(api.requests, hasLength(1));
      expect(find.text('USD 190.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
