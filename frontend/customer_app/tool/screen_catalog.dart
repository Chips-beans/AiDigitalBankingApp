// Renders every Customer App screen in light mode and English at phone size
// into `<repo>/Flutter Screen/Customer App`. Controlled fixture data only; no
// backend is contacted.
//
//   flutter test tool/screen_catalog.dart --concurrency=1
//
// Set SCREEN_ONLY=01,09 to render a subset (file-name prefixes) while iterating.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/analytics/analytics_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/presentation/app_pin_page.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/presentation/locked_home_page.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:customer_app/features/merchant/merchant_approval_screen.dart';
import 'package:customer_app/features/merchant/merchant_sessions_screen.dart';
import 'package:customer_app/features/merchant/merchant_transfer_approval_screen.dart';
import 'package:customer_app/features/qr/presentation/receive_qr_panel.dart';
import 'package:customer_app/features/qr/presentation/scan_qr_panel.dart';
import 'package:customer_app/features/qr/qr_gateway.dart' show AccountQr;
import 'package:customer_app/features/settings/settings_detail_screen.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transaction_gateway.dart'
    show PostingPage;
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/merchant_approval_test.dart'
    show ApprovalRig, requestId, handoffToken;
import '../test/merchant_transfer_test.dart'
    show TransferRig, intentId, handoff;
import '../test/qr_pairs_test.dart' show FakeQr, sampleQr;
import '../test/qr_widget_test.dart' show FakeCamera;
import '../test/settings_test.dart' show FakeSettingsPlatform, settingsSession;
import '../test/support/assistant_fakes.dart' show FakeAssistant;
import '../test/transactions_test.dart' show FakeTransactions;
import '../test/transfer_pin_exchange_test.dart' show FakeSupport;

const _size = Size(393, 852);
const _shot = 3.0;

/// One capture: the readable file name and how to bring the screen up.
class _Shot {
  const _Shot(this.name, this.show);
  final String name;
  final Future<void> Function(_Ctx c) show;
}

class _Ctx {
  _Ctx(this.tester);
  final WidgetTester tester;
  final GlobalKey boundary = GlobalKey();
  SessionController? session;
  final List<void Function()> _cleanups = [];

  void onCleanup(void Function() fn) => _cleanups.add(fn);

  Future<void> settle() async {
    await tester.pumpAndSettle();
    // Let asset images and SVGs finish decoding, then paint them.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settle();
  }

  /// Moves every vertical scroll view to its start (no pull-to-refresh gesture).
  Future<void> scrollToTop() async {
    for (final element in find.byType(Scrollable).evaluate()) {
      final state = (element as StatefulElement).state as ScrollableState;
      if (state.position.axis == Axis.vertical) state.position.jumpTo(0);
    }
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text).first);
  Future<void> tapTip(String tip) => tap(find.byTooltip(tip).first);
  Future<void> tapKey(String key) => tap(find.byKey(ValueKey(key)));
  Future<void> enter(String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  /// Mounts the real app on its sign-in flow with the demo auth gateway.
  Future<void> mountSignIn() async {
    session = SessionController(DemoAuthGateway(), MemorySessionVault());
    await session!.initialize();
    await tester.pumpWidget(
      _app(session!, FakeAccounts()..data = [], FakeTransactions(), null),
    );
    await settle();
  }

  /// Mounts the real app for a signed-in, funded customer.
  Future<void> mountMain({bool assistant = false}) async {
    session = await settingsSession();
    await tester.pumpWidget(
      _app(
        session!,
        _accounts(),
        _transactions(),
        assistant ? FakeAssistant() : null,
      ),
    );
    await settle();
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final fn in _cleanups.reversed) {
      fn();
    }
    _cleanups.clear();
    try {
      // A rig may already have disposed the session it owns.
      session?.dispose();
    } catch (_) {}
    session = null;
  }

  /// Pumps one widget on its own (screens that have no shell around them).
  Future<void> mountDirect(Widget child) async {
    final p = AppPreferences();
    onCleanup(p.dispose);
    // The boundary wraps the whole app so dialogs and sheets are captured too.
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppPreferencesScope(
          preferences: p,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('km')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.build(Brightness.light, locale: const Locale('en')),
            home: child,
          ),
        ),
      ),
    );
    await settle();
  }

  Widget _app(
    SessionController s,
    FakeAccounts accounts,
    FakeTransactions transactions,
    FakeAssistant? assistant,
  ) => RepaintBoundary(
    key: boundary,
    child: BankingApp(
      session: s,
      config: AppConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
      ),
      accountGateway: accounts,
      analyticsGateway: DemoAnalyticsGateway(),
      creationStore: MemoryCreationStore(),
      transactionGateway: transactions,
      transferStore: MemoryTransferStore(),
      assistantGateway: assistant,
      assistantStore: assistant == null ? null : AssistantPendingStore(),
    ),
  );

  /// Accounts and transfer controllers for screens mounted on their own.
  Future<(AccountsController, TransferController)> controllers() async {
    final s = session = await settingsSession();
    final accounts = AccountsController(s, _accounts(), MemoryCreationStore());
    await accounts.initialize();
    final transfers = TransferController(
      s,
      FakeTransactions(),
      MemoryTransferStore(),
    );
    await transfers.initialize();
    onCleanup(() {
      transfers.dispose();
      accounts.dispose();
    });
    return (accounts, transfers);
  }
}

BankAccount _wallet(int id, String currency, String balance) => BankAccount(
  id: id,
  number: '${1000000000 + id}',
  type: 'SAVINGS',
  balance: Money.parse(balance, currency),
  status: 'ACTIVE',
  createdAt: DateTime.utc(2026, 10, 30, 2, 15),
);

final _usd = _wallet(1, 'USD', '190.00');
final _khr = _wallet(2, 'KHR', '90000');

final _postings = <RecentPosting>[
  _posting(
    'KSR261030000101',
    null,
    _usd.number,
    '200.00',
    'USD',
    DateTime.utc(2026, 10, 30, 2, 15),
    bank: true,
  ),
  _posting(
    'KSR261030000102',
    null,
    _khr.number,
    '100000',
    'KHR',
    DateTime.utc(2026, 10, 30, 2, 16),
    bank: true,
  ),
  _posting(
    'KSR261031000117',
    _usd.number,
    '1000000003',
    '10.00',
    'USD',
    DateTime.utc(2026, 10, 31, 3, 40),
    toName: 'Sok Dara',
  ),
  _posting(
    'KSR261101000044',
    _khr.number,
    '1000000004',
    '10000',
    'KHR',
    DateTime.utc(2026, 11, 1, 5, 5),
    toName: 'Chan Sophea',
  ),
];

/// Accounts that also support opening a USD + KHR pair (as the real API does).
class _PairAccounts extends FakeAccounts implements AccountPairGateway {
  @override
  Future<OpeningPolicy> openingPolicy(String token) async =>
      OpeningPolicy(false, Money.parse('0', 'USD'), Money.parse('0', 'KHR'));

  @override
  Future<AccountPairResult> openPair(String token, String type, String key) =>
      throw UnimplementedError('The catalog never opens accounts.');
}

FakeAccounts _accounts() {
  final fake = _PairAccounts();
  fake.data = [_usd, _khr];
  fake.onRecent = (number) async => _postings
      .where((p) => p.source == number || p.destination == number)
      .toList();
  return fake;
}

/// History and detail come from [_postings]; a new transfer returns a receipt
/// with a bank-style reference and the current time.
class _Transactions extends FakeTransactions {
  _Transactions() {
    onHistory = (account, page) async => PostingPage(
      _postings
          .where((p) => p.source == account || p.destination == account)
          .toList(),
      0,
      true,
      _postings.length,
    );
    onDetail = (account, reference) async =>
        _postings.firstWhere((p) => p.reference == reference);
  }

  @override
  Future<RecentPosting> transfer(
    String token,
    SavedTransfer operation, {
    String? pinProof,
  }) async => RecentPosting(
    reference: 'KSR261104000201',
    source: operation.draft.source,
    destination: operation.draft.destination,
    amount: operation.draft.amount,
    fee: Money.parse('0', operation.draft.amount.currency),
    type: 'TRANSFER',
    status: 'SUCCESS',
    createdAt: DateTime.now().toUtc(),
    remark: operation.draft.remark,
  );
}

FakeTransactions _transactions() => _Transactions();

RecentPosting _posting(
  String reference,
  String? source,
  String destination,
  String amount,
  String currency,
  DateTime at, {
  bool bank = false,
  String? toName,
}) => RecentPosting(
  reference: reference,
  source: source,
  destination: destination,
  amount: Money.parse(amount, currency),
  fee: Money.parse('0', currency),
  type: bank ? 'DEPOSIT' : 'TRANSFER',
  status: 'SUCCESS',
  createdAt: at,
  remark: null,
  destinationName: toName,
  bankSource: bank,
  operation: bank ? 'TEST_OPENING_CREDIT' : null,
);

/// The customer's own QR: the holder is the signed-in customer, not a fixture.
class _OwnQr extends FakeQr {
  @override
  Future<AccountQr> generate(
    String token,
    BankAccount account,
    Money? amount,
  ) async => AccountQr.fromJson({
    'qrString': sampleQr,
    'qrHash': 'a' * 32,
    'accountNumber': account.number,
    'payeeName': 'Seng Sovanreach',
    'currency': account.currency,
    'qrType': amount == null ? 'STATIC' : 'DYNAMIC',
    'amount': amount?.decimal,
  });
}

Widget _pin(PinStage stage) => PinScreen(
  stage: stage,
  name: 'Sovanreach Seng',
  onNumber: (_) {},
  onClear: () {},
  onDelete: () {},
  onForgot: () {},
);

Future<void> _signUp(_Ctx c, {bool fillProfile = false}) async {
  await c.mountSignIn();
  await c.tapText('Continue with Email');
  await c.enter('email', 'sovanreach@example.com');
  await c.tapText('Send Code');
  if (!fillProfile) return;
  await c.enter('otpCode', '123456');
  await c.tapText('Verify');
  await c.enter('firstName', 'Sovanreach');
  await c.enter('lastName', 'Seng');
  await c.settle();
}

Future<void> _settingsPage(_Ctx c, String page) async {
  final s = c.session = await settingsSession();
  await c.mountDirect(
    SettingsDetailScreen(
      key: ValueKey(page),
      page: page,
      session: s,
      onBack: () {},
      onAssistant: () {},
      platform: FakeSettingsPlatform(),
    ),
  );
}

Future<void> _fillTransfer(_Ctx c) async {
  await c.mountMain();
  await c.tapText('Transfer');
  await c.enter('transfer-destination', '1000000003');
  await c.enter('transfer-amount', '10.00');
}

Widget _receive(_Ctx c, AccountsController accounts) => ReceiveQrScreen(
  background: const KesorHomeScreen(
    data: KesorHomeData.designPreview,
    showDeviceChrome: true,
  ),
  panel: ReceiveQrPanel(
    session: c.session!,
    gateway: _OwnQr(),
    accounts: accounts,
    onClose: () {},
  ),
);

final _shots = <_Shot>[
  _Shot('01_Welcome', (c) => c.mountSignIn()),
  _Shot('02_Continue_With_Email', (c) async {
    await c.mountSignIn();
    await c.tapText('Continue with Email');
  }),
  _Shot('03_Verify_Email_Code', (c) => _signUp(c)),
  _Shot('04_Create_Profile', (c) => _signUp(c, fillProfile: true)),
  _Shot('05_PIN_Create', (c) => c.mountDirect(_pin(PinStage.create))),
  _Shot('06_PIN_Confirm', (c) => c.mountDirect(_pin(PinStage.confirm))),
  _Shot('07_PIN_Enter', (c) => c.mountDirect(_pin(PinStage.unlock))),
  _Shot(
    '08_Home_Locked_Masked_Balances',
    (c) => c.mountDirect(LockedHomePage(onUnlock: () {})),
  ),
  _Shot('09_Home', (c) => c.mountMain()),
  _Shot('10_Home_Add_Favorite_Recipient', (c) async {
    await c.mountMain();
    await c.tapText('Add');
  }),
  _Shot('11_Wallet_And_Accounts', (c) async {
    await c.mountMain();
    await c.tapTip('View accounts');
  }),
  _Shot('12_Open_Accounts', (c) async {
    await c.mountMain();
    await c.tapTip('View accounts');
    await c.tapText('Open accounts');
  }),
  _Shot('13_Account_Details', (c) async {
    await c.mountMain();
    await c.tapTip('View accounts');
    await c.tapKey('wallet-tile-${_usd.number}');
  }),
  _Shot('14_Transfer_Enter_Details', (c) async {
    await c.mountMain();
    await c.tapText('Transfer');
  }),
  _Shot('15_Transfer_Review', (c) async {
    await _fillTransfer(c);
    await c.tapKey('transfer-continue');
  }),
  _Shot('15b_Transfer_Confirm_With_PIN', (c) async {
    final s = c.session = await settingsSession();
    final accounts = AccountsController(s, _accounts(), MemoryCreationStore());
    await accounts.initialize();
    final transfers = TransferController(
      s,
      FakeTransactions(),
      MemoryTransferStore(),
      support: FakeSupport(),
    );
    await transfers.initialize();
    c.onCleanup(() {
      transfers.dispose();
      accounts.dispose();
    });
    transfers.prepare(
      _usd,
      '1000000003',
      '10.00',
      '',
      destinationName: 'Sok Dara',
    );
    await c.mountDirect(
      KesorTransferScreen(
        controller: transfers,
        accounts: accounts,
        enabled: true,
        onBack: () {},
        favorites: RecipientFavoritesStore(),
      ),
    );
    await c.tapKey('transfer-confirm');
  }),
  _Shot('16_Transfer_Success_Receipt', (c) async {
    await _fillTransfer(c);
    await c.tapKey('transfer-continue');
    await c.tapKey('transfer-confirm');
  }),
  _Shot('17_Activity_History', (c) async {
    await c.mountMain();
    await c.tapTip('All transactions');
  }),
  _Shot('18_Transaction_Details', (c) async {
    await c.mountMain();
    await c.tapTip('All transactions');
    await c.tapText('View transaction details');
  }),
  _Shot('19_Analytics_Monthly_Overview', (c) async {
    await c.mountMain();
    await c.tapKey('bottom-tab-1');
  }),
  _Shot('20_Settings', (c) async {
    await c.mountMain();
    await c.tapKey('bottom-tab-2');
  }),
  _Shot('21_Settings_Profile', (c) => _settingsPage(c, 'profile')),
  _Shot('22_Settings_Change_PIN', (c) => _settingsPage(c, 'pin')),
  _Shot('23_Settings_Notifications', (c) => _settingsPage(c, 'notifications')),
  _Shot('24_Settings_Language', (c) => _settingsPage(c, 'language')),
  _Shot('25_Settings_Appearance', (c) => _settingsPage(c, 'appearance')),
  _Shot('26_Settings_Help_And_Support', (c) => _settingsPage(c, 'help')),
  _Shot('27_Settings_Terms_And_Privacy', (c) => _settingsPage(c, 'legal')),
  _Shot('28_Settings_Sign_Out', (c) => _settingsPage(c, 'signout')),
  _Shot('29_Settings_Merchant_Sessions', (c) async {
    final rig = ApprovalRig(await settingsSession());
    c.onCleanup(rig.dispose);
    c.session = rig.session;
    await c.mountDirect(
      MerchantSessionsScreen(session: rig.session, api: rig.api, onBack: () {}),
    );
  }),
  _Shot('30_AI_Assistant', (c) async {
    await c.mountMain(assistant: true);
    await c.tapTip('AI assistant');
  }),
  _Shot('31_AI_Assistant_Answer', (c) async {
    await c.mountMain(assistant: true);
    await c.tapTip('AI assistant');
    await c.enter('assistant-question', 'What is my balance?');
    await c.tapKey('assistant-send');
    await c.scrollToTop();
  }),
  _Shot('32_AI_Assistant_History', (c) async {
    await c.mountMain(assistant: true);
    await c.tapTip('AI assistant');
    await c.enter('assistant-question', 'What is my balance?');
    await c.tapKey('assistant-send');
    await c.tapTip('Conversation history');
  }),
  _Shot('33_My_QR', (c) async {
    final (accounts, _) = await c.controllers();
    await c.mountDirect(_receive(c, accounts));
  }),
  _Shot('34_My_QR_Request_Amount', (c) async {
    final (accounts, _) = await c.controllers();
    await c.mountDirect(_receive(c, accounts));
    await c.tapKey('qr-enter-amount');
    await c.enter('qr-request-amount', '10');
    await c.tapKey('qr-request-create');
  }),
  _Shot('35_Scan_QR', (c) async {
    final previous = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = FakeCamera();
    c.onCleanup(() => MobileScannerPlatform.instance = previous);
    final (accounts, transfers) = await c.controllers();
    await c.mountDirect(
      Scaffold(
        body: ScanQrPanel(
          session: c.session!,
          gateway: _OwnQr(),
          accounts: accounts,
          transfers: transfers,
          enabled: true,
          onClose: () {},
        ),
      ),
    );
  }),
  _Shot('36_Pay_Verified_Shop', (c) async {
    final (accounts, transfers) = await c.controllers();
    await c.mountDirect(
      KesorTransferScreen(
        controller: transfers,
        accounts: accounts,
        enabled: true,
        onBack: () {},
        favorites: RecipientFavoritesStore(),
        prefill: const TransferPrefill(
          '1000000009',
          name: 'Kesor Coffee',
          qrString: sampleQr,
          shop: ShopPayee(
            merchantId: 'MCH-AB23CD45',
            storeName: 'Kesor Coffee',
            currency: 'USD',
            hasLogo: false,
          ),
        ),
      ),
    );
  }),
  _Shot('37_Merchant_Sign_In_Approval', (c) async {
    final rig = ApprovalRig(await settingsSession());
    c.onCleanup(rig.dispose);
    c.session = rig.session;
    rig.model.pending = {
      'id': requestId,
      'handoff': handoffToken,
      'owner': rig.session.identity!.userId,
      'until': rig.now.add(const Duration(minutes: 2)).toIso8601String(),
    };
    rig.model.details = {
      'clientName': 'Kesor Merchant',
      'deviceName': 'Android phone',
      'status': 'PENDING',
      'expiresAt': rig.now.add(const Duration(minutes: 2)).toIso8601String(),
    };
    await c.mountDirect(
      MerchantApprovalScreen(approval: rig.model, session: rig.session),
    );
  }),
  _Shot('39_Your_Profile_Page', (c) async {
    await c.mountMain();
    await c.tapTip('View accounts');
    await c.tapTip('Profile');
  }),
  _Shot('38_Merchant_Owner_Transfer_Approval', (c) async {
    final rig = TransferRig(await settingsSession());
    c.onCleanup(rig.dispose);
    c.session = rig.session;
    rig.model.pending = {
      'id': intentId,
      'handoff': handoff,
      'owner': rig.session.identity!.userId,
      'until': rig.now.add(const Duration(minutes: 5)).toIso8601String(),
    };
    rig.model.details = {
      'intentId': intentId,
      'shopName': 'Kesor Coffee',
      'sourceAccount': '•••• 1234',
      'destinationAccount': '•••• 5678',
      'currency': 'USD',
      'amount': '12.50',
      'status': 'PENDING',
      'expiresAt': rig.now.add(const Duration(minutes: 5)).toIso8601String(),
      'serverTime': rig.now.toIso8601String(),
    };
    await c.mountDirect(
      MerchantTransferApprovalScreen(approval: rig.model, session: rig.session),
    );
  }),
];

void main() {
  testWidgets('Customer screen catalog (light, English, phone)', (
    tester,
  ) async {
    final only = (Platform.environment['SCREEN_ONLY'] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toList();
    final out = Directory(
      '${Directory.current.absolute.parent.parent.path}/Flutter Screen/Customer App',
    )..createSync(recursive: true);
    if (only.isEmpty) {
      for (final f in out.listSync().whereType<File>()) {
        if (f.path.endsWith('.png')) f.deleteSync();
      }
    }
    // Real shadows, like a device. Restored at the end.
    debugDisableShadows = false;
    await tester.runAsync(() async {
      for (final entry in {
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
        'Poppins': [
          'Poppins-Light.ttf',
          'Poppins-Regular.ttf',
          'Poppins-Medium.ttf',
          'Poppins-SemiBold.ttf',
          'Poppins-Bold.ttf',
        ],
        'Google Sans': [
          'GoogleSans-Regular.ttf',
          'GoogleSans-Medium.ttf',
          'GoogleSans-Bold.ttf',
        ],
        'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final file in entry.value) {
          loader.addFont(
            rootBundle.load(
              entry.key == 'MaterialIcons' ? file : 'assets/fonts/$file',
            ),
          );
        }
        await loader.load();
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _size;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 20);

    final written = <String>[];
    final failures = <String>[];
    for (final shot in _shots) {
      if (only.isNotEmpty && !only.any(shot.name.startsWith)) continue;
      final c = _Ctx(tester);
      try {
        await shot.show(c);
        expect(tester.takeException(), isNull, reason: shot.name);
        written.add((await _write(tester, c.boundary, out, shot.name))!);
        // Content below the fold gets a second, scrolled capture.
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          final position = tester
              .state<ScrollableState>(scrollables.first)
              .position;
          if (position.axis == Axis.vertical && position.maxScrollExtent > 60) {
            position.jumpTo(position.maxScrollExtent);
            await c.settle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${shot.name} scrolled',
            );
            final second = await _write(
              tester,
              c.boundary,
              out,
              '${shot.name}_2_Scrolled',
              sameAs: '${out.path}/${shot.name}.png',
            );
            if (second != null) written.add(second);
          }
        }
      } catch (error) {
        failures.add('${shot.name}: ${error.toString().split("\n").first}');
        tester.takeException();
      }
      await c.unmount();
    }
    debugDisableShadows = true;
    // ignore: avoid_print
    print('Wrote ${written.length} screenshots to ${out.path}');
    expect(failures, isEmpty, reason: failures.join("\n"));
  });
}

/// Writes the PNG, or returns null when it would equal [sameAs].
Future<String?> _write(
  WidgetTester tester,
  GlobalKey key,
  Directory out,
  String name, {
  String? sameAs,
}) async {
  final path = '${out.path}/$name.png';
  var skipped = false;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _shot);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      if (sameAs != null && await File(sameAs).exists()) {
        final previous = await File(sameAs).readAsBytes();
        if (previous.length == bytes.length &&
            Iterable<int>.generate(bytes.length)
                .every((i) => previous[i] == bytes[i])) {
          skipped = true;
          return;
        }
      }
      await File(path).writeAsBytes(bytes);
    } finally {
      image.dispose();
    }
  });
  return skipped ? null : path;
}
