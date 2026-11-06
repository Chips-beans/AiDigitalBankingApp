import 'dart:async';
import 'dart:convert';

import 'package:customer_app/shared/widgets/figma_presentation.dart';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/design_system/design_system.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/analytics/analytics_gateway.dart';
import 'package:customer_app/features/analytics/analytics_controller.dart';
import 'package:customer_app/features/analytics/presentation/analytics_screen.dart';
import 'package:customer_app/features/analytics/presentation/daily_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

Map<String, dynamic> analyticsJson(
  DateTime month, {
  String currency = 'USD',
  String amount = '1.01',
}) {
  final zero = currency == 'USD' ? '0.00' : '0';
  return {
    'month': monthKey(month),
    'currency': currency,
    'timeZone': 'Asia/Phnom_Penh',
    'totalIncome': amount,
    'totalExpense': zero,
    'daily': List.generate(
      DateTime.utc(month.year, month.month + 1, 0).day,
      (i) => {
        'date': '${monthKey(month)}-${(i + 1).toString().padLeft(2, '0')}',
        'totalIncome': i == 0 ? amount : zero,
        'totalExpense': zero,
      },
    ),
  };
}

Future<SessionController> analyticsSession({FakeGateway? auth}) async {
  final session = SessionController(
    auth ?? (FakeGateway()..expiresInMs = 600000),
    MemorySessionVault(),
  );
  await session.initialize();
  await session.begin(
    email: 'customer@example.test',
    password: 'Password1!',
    register: false,
  );
  await session.verifyCode('123456');
  return session;
}

class ControlledAnalytics implements AnalyticsGateway {
  final calls =
      <
        ({
          String token,
          DateTime month,
          String currency,
          Completer<AnalyticsSnapshot> result,
        })
      >[];
  @override
  Future<AnalyticsSnapshot> load(
    String token,
    DateTime month,
    String currency,
  ) {
    final result = Completer<AnalyticsSnapshot>();
    calls.add((token: token, month: month, currency: currency, result: result));
    return result.future;
  }
}

Future<void> loadAnalyticsFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final family in {
      'Google Sans': [
        'GoogleSans-Regular.ttf',
        'GoogleSans-Medium.ttf',
        'GoogleSans-Bold.ttf',
      ],
      'Poppins': [
        'Poppins-Regular.ttf',
        'Poppins-Medium.ttf',
        'Poppins-SemiBold.ttf',
        'Poppins-Bold.ttf',
      ],
      'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final file in family.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
  });
}

void main() {
  final month = DateTime.utc(2026, 10);
  test(
    'HTTP uses owner-scoped endpoint and exact strings beyond posting limits',
    () async {
      final client = ApiClient(
        AppConfig(apiBaseUrl: 'http://localhost/api/v1', environment: 'dev'),
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/analytics/monthly-overview');
          expect(request.headers['Authorization'], 'Bearer private-token');
          expect(request.url.queryParameters, {
            'year': '2026',
            'month': '10',
            'currency': 'USD',
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'data': analyticsJson(month, amount: '19999999999999999.99'),
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final result = await HttpAnalyticsGateway(client)
          .load('private-token', month, 'USD');
      expect(result.income, BigInt.parse('1999999999999999999'));
      expect(
        analyticsMoney(result.income, 'USD'),
        r'$19,999,999,999,999,999.99',
      );
    },
  );

  test(
    'rejects inconsistent, unordered, incomplete, mismatched or inexact data',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['currency'] = 'KHR',
        (d) => d['month'] = '2026-09',
        (d) => d['timeZone'] = 'UTC',
        (d) => d['totalIncome'] = '2.02',
        (d) => d['totalIncome'] = 1.01,
        (d) => (d['daily'] as List).removeLast(),
        (d) => (d['daily'] as List)[0]['date'] = '2026-10-02',
        (d) => (d['daily'] as List)[0]['totalIncome'] = '-1.01',
        (d) => (d['daily'] as List)[0]['totalExpense'] = '0.001',
      ]) {
        final data = analyticsJson(month);
        change(data);
        expect(
          () => AnalyticsSnapshot.fromJson(data, month, 'USD'),
          throwsA(isA<ApiFailure>()),
        );
      }
      final feb = DateTime.utc(2024, 2);
      expect(
        AnalyticsSnapshot.fromJson(
          analyticsJson(feb, currency: 'KHR', amount: '4000'),
          feb,
          'KHR',
        ).daily.length,
        29,
      );
      expect(() => analyticsUnits('1.50', 'KHR'), throwsA(isA<ApiFailure>()));
    },
  );

  test('Phnom Penh calendar rolls at 17:00 UTC, not the host timezone', () {
    expect(
      monthKey(bankingMonth(DateTime.utc(2026, 9, 30, 16, 59))),
      '2026-09',
    );
    expect(monthKey(bankingMonth(DateTime.utc(2026, 9, 30, 17))), '2026-10');
  });

  test('latest selection wins, same-selection stale cache, no cross-currency fallback', () async {
    final session = await analyticsSession();
    addTearDown(session.dispose);
    final gateway = ControlledAnalytics();
    final model = AnalyticsController(session, gateway, clock: () => month);
    addTearDown(model.dispose);
    expect(model.started, isFalse);
    expect(gateway.calls, isEmpty);
    final first = model.ensureLoaded();
    await Future<void>.delayed(Duration.zero);
    final switchCurrency = model.selectCurrency('KHR');
    await Future<void>.delayed(Duration.zero);
    gateway.calls[1].result.complete(sampleAnalytics(month, 'KHR'));
    await switchCurrency;
    gateway.calls[0].result.complete(sampleAnalytics(month, 'USD'));
    await first;
    expect(model.snapshot!.currency, 'KHR');
    final refresh = model.refresh();
    await Future<void>.delayed(Duration.zero);
    gateway.calls[2].result.completeError(
      const ApiFailure('UNAVAILABLE', 'offline'),
    );
    await refresh;
    expect(model.snapshot!.currency, 'KHR');
    expect(model.error, isNotNull);
    final usd = model.selectCurrency('USD');
    await Future<void>.delayed(Duration.zero);
    expect(model.snapshot, isNull);
    gateway.calls[3].result.completeError(
      const ApiFailure('UNAVAILABLE', 'offline'),
    );
    await usd;
    expect(model.snapshot, isNull);
  });

  test(
    'logout and disposal discard private snapshots and pending responses',
    () async {
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final gateway = ControlledAnalytics();
      final model = AnalyticsController(session, gateway, clock: () => month);
      final pending = model.refresh();
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      gateway.calls.single.result.complete(sampleAnalytics(month, 'USD'));
      await pending;
      expect(model.snapshot, isNull);
      expect(model.loading, isFalse);
      model.dispose();
      final another = await analyticsSession();
      addTearDown(another.dispose);
      final g = ControlledAnalytics();
      final disposed = AnalyticsController(another, g, clock: () => month);
      final load = disposed.refresh();
      await Future<void>.delayed(Duration.zero);
      disposed.dispose();
      g.calls.single.result.complete(sampleAnalytics(month, 'USD'));
      await load;
      expect(disposed.snapshot, isNull);
    },
  );

  test('read token renewal, first-entry loading, navigation and financial invalidation', () async {
    final auth = FakeGateway()..expiresInMs = 600000;
    final session = await analyticsSession(auth: auth);
    addTearDown(session.dispose);
    final gateway = ControlledAnalytics();
    final model = AnalyticsController(session, gateway, clock: () => month);
    addTearDown(model.dispose);
    final load = model.refresh();
    await Future<void>.delayed(Duration.zero);
    gateway.calls[0].result.completeError(
      const ApiFailure('TOKEN_INVALID', 'expired', status: 401),
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.calls[1].token, startsWith('access-rotated'));
    gateway.calls[1].result.complete(sampleAnalytics(month, 'USD'));
    await load;
    await model.ensureLoaded();
    expect(gateway.calls.length, 2);
    await model.selectMonth(1);
    expect(gateway.calls.length, 2);
    expect(model.canNext, isFalse);
    final previous = model.selectMonth(-1);
    await Future<void>.delayed(Duration.zero);
    gateway.calls.last.result.complete(
      sampleAnalytics(DateTime.utc(2026, 9), 'USD'),
    );
    await previous;
    model.selectSeries(true);
    final invalidate = model.invalidate();
    await Future<void>.delayed(Duration.zero);
    expect(model.snapshot, isNull);
    gateway.calls.last.result.complete(
      sampleAnalytics(DateTime.utc(2026, 9), 'USD'),
    );
    await invalidate;
    expect(model.showIncome, isTrue);
    expect(model.snapshot, isNotNull);
  });

  test(
    'chart scale is finite, zero based, shared and handles enormous totals',
    () {
      for (final amount in [
        '0.00',
        '0.01',
        '999999999999999999999999999999999999.99',
      ]) {
        final snapshot = AnalyticsSnapshot.fromJson(
          analyticsJson(month, amount: amount),
          month,
          'USD',
        );
        final scale = AnalyticsScale(snapshot);
        expect(scale.ratio(BigInt.zero), 0);
        expect(scale.ratio(snapshot.income), inInclusiveRange(0.0, 1.0));
        expect(scale.maximum >= snapshot.income, isTrue);
      }
    },
  );

  test(
    'first entry rechecks the banking month and rejects unsupported jumps',
    () async {
      final session = await analyticsSession();
      addTearDown(session.dispose);
      var clock = DateTime.utc(2026, 9, 30, 16, 59);
      final model = AnalyticsController(
        session,
        DemoAnalyticsGateway(),
        clock: () => clock,
      );
      addTearDown(model.dispose);
      expect(monthKey(model.month), '2026-09');
      clock = DateTime.utc(2026, 9, 30, 17);
      await model.ensureLoaded();
      expect(monthKey(model.month), '2026-10');
      await model.selectMonth(2);
      expect(monthKey(model.month), '2026-10');
    },
  );

  testWidgets('loading, unavailable, empty and stale states stay distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await analyticsSession();
    addTearDown(session.dispose);
    final gateway = ControlledAnalytics();
    final model = AnalyticsController(session, gateway, clock: () => month);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: AnalyticsScreen(controller: model)),
      ),
    );
    final first = model.refresh();
    await tester.pump();
    expect(find.byKey(const ValueKey('analytics-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-chart')), findsNothing);
    gateway.calls.last.result.completeError(
      const ApiFailure('UNAVAILABLE', 'offline'),
    );
    await first;
    await tester.pump();
    expect(
      find.text('Analytics could not load. Please retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('DEMO'), findsNothing);
    final retry = model.refresh();
    await tester.pump();
    gateway.calls.last.result.complete(
      AnalyticsSnapshot.fromJson(
        analyticsJson(month, amount: '0.00'),
        month,
        'USD',
      ),
    );
    await retry;
    await tester.pumpAndSettle();
    expect(find.text('No activity this month'), findsOneWidget);
    final refresh = model.refresh();
    await tester.pump();
    gateway.calls.last.result.completeError(
      const ApiFailure('UNAVAILABLE', 'offline'),
    );
    await refresh;
    await tester.pumpAndSettle();
    expect(
      find.text('Showing previously loaded values. Refresh failed.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('analytics-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '375px, landscape and tablet with large text and reduced motion',
    (tester) async {
      await loadAnalyticsFonts(tester);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final model = AnalyticsController(
        session,
        DemoAnalyticsGateway(),
        clock: () => month,
      );
      addTearDown(model.dispose);
      await model.refresh();
      for (final size in [
        const Size(375, 812),
        const Size(667, 375),
        const Size(1024, 768),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
                padding: const EdgeInsets.only(top: 24, bottom: 34),
              ),
              child: Scaffold(
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AnalyticsScreen(controller: model),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsNothing);
        final chart = tester.getRect(
          find.byKey(const ValueKey('analytics-chart-card')),
        );
        final panel = tester.getRect(
          find.byKey(const ValueKey('analytics-panel')),
        );
        expect(chart.top, greaterThanOrEqualTo(panel.top));
        expect(chart.bottom, lessThanOrEqualTo(size.height - 34 - 64 - 20));
        final income = tester.getRect(
          find.byKey(const ValueKey('analytics-income-card')),
        );
        final expense = tester.getRect(
          find.byKey(const ValueKey('analytics-expense-card')),
        );
        expect(income.top, expense.top);
        expect(income.right, lessThan(expense.left));
        expect(tester.takeException(), isNull, reason: '$size');
      }
    },
  );

  testWidgets(
    'screen selectors, exact tooltips, keyboard and daily values sheet',
    (tester) async {
      await loadAnalyticsFonts(tester);
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final model = AnalyticsController(
        session,
        DemoAnalyticsGateway(),
        clock: () => month,
      );
      addTearDown(model.dispose);
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: AnalyticsScreen(controller: model, showDeviceChrome: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('analytics-income-card')))
            .height,
        101,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('analytics-next')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('analytics-series')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income').last);
      await tester.pumpAndSettle();
      expect(model.showIncome, isTrue);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('analytics-chart'))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('analytics-tooltip')), findsOneWidget);
      final focus = tester.widget<Focus>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('analytics-chart')),
              matching: find.byType(Focus),
            )
            .first,
      );
      focus.onKeyEvent!(
        FocusNode(),
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('analytics-tooltip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('analytics-daily-values')));
      await tester.pumpAndSettle();
      expect(find.text('Daily values'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('analytics-currency-KHR')),
      );
      await tester.tap(find.byKey(const ValueKey('analytics-currency-KHR')));
      await tester.pumpAndSettle();
      expect(model.currency, 'KHR');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Income is gold, Expense is blue, and Next turns gold only when available',
    (tester) async {
      await loadAnalyticsFonts(tester);
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final model = AnalyticsController(
        session,
        DemoAnalyticsGateway(),
        clock: () => month,
      );
      addTearDown(model.dispose);
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(body: AnalyticsScreen(controller: model)),
        ),
      );
      await tester.pumpAndSettle();
      Color? dot() => tester
          .widget<AnalyticsAsset>(
            find.byKey(const ValueKey('analytics-series-dot')),
          )
          .tint;
      String nextIcon() => tester
          .widget<CustomerDesignIcon>(
            find.descendant(
              of: find.byKey(const ValueKey('analytics-next')),
              matching: find.byType(CustomerDesignIcon),
            ),
          )
          .asset;

      expect(model.showIncome, isFalse);
      expect(dot(), AppPalette.navy500);
      expect(nextIcon(), '205d9', reason: 'The future month stays disabled');

      model.selectSeries(true);
      await model.selectMonth(-1);
      await tester.pumpAndSettle();
      expect(dot(), AppPalette.gold500);
      expect(nextIcon(), '16298', reason: 'Gold chevron, like Previous');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow large-text Khmer dark screen fits without scrolling or reflow',
    (tester) async {
      await loadAnalyticsFonts(tester);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final model = AnalyticsController(
        session,
        DemoAnalyticsGateway(),
        clock: () => month,
      );
      addTearDown(model.dispose);
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('km'),
          supportedLocales: const [Locale('km')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.build(Brightness.dark, locale: const Locale('km')),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: AnalyticsScreen(controller: model)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('analytics-chart-card')))
            .bottom,
        lessThanOrEqualTo(568 - 64 - 32 - 20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'banking navigation preserves analytics selection and balance visibility',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await analyticsSession();
      addTearDown(session.dispose);
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      await tester.pumpWidget(
        BankingApp(
          session: session,
          preferences: prefs,
          config: AppConfig(
            apiBaseUrl: 'http://localhost/api/v1',
            environment: 'dev',
            mode: 'demo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bottom-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analytics-previous')));
      await tester.pumpAndSettle();
      final screen = tester.widget<AnalyticsScreen>(
        find.byType(AnalyticsScreen),
      );
      final selected = screen.controller.month;
      await tester.tap(find.byKey(const ValueKey('bottom-tab-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bottom-tab-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnalyticsScreen>(find.byType(AnalyticsScreen))
            .controller
            .month,
        selected,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
