import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_system/design_system.dart';
import '../../../app/app_preferences.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../analytics_controller.dart';
import '../analytics_gateway.dart';
import 'daily_chart.dart';

String _label(BuildContext context, String en, String km) =>
    (AppPreferences.maybeOf(context)?.locale ?? Localizations.localeOf(context))
            .languageCode ==
        'km'
    ? km
    : en;

TextStyle _text(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'Google Sans',
  fontFamilyFallback: const ['Noto Sans Khmer'],
  fontSize: size,
  height: 1.4,
  fontWeight: weight,
  color: color ?? AppColors.of(context).foreground,
);

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
    required this.controller,
    this.showDeviceChrome = false,
    super.key,
  });
  final AnalyticsController controller;
  final bool showDeviceChrome;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = AppColors.of(context);
      final snapshot = controller.snapshot;
      return ColoredBox(
        color: colors.background,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              key: const PageStorageKey('analytics-scroll'),
              padding: EdgeInsets.fromLTRB(
                20,
                showDeviceChrome ? 61 : 7,
                20,
                math.max(24, MediaQuery.paddingOf(context).bottom) +
                    KesorBottomBar.height(context) +
                    32,
              ),
              children: [
                LayoutBuilder(
                  builder: (context, bounds) {
                    final heading = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(context, 'Analytic', 'ការវិភាគ'),
                          style: customerText(
                            context,
                            24,
                            36,
                            color: customerNavy(context),
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _label(
                            context,
                            'Track and Manage Your Money',
                            'តាមដាន និងគ្រប់គ្រងប្រាក់របស់អ្នក',
                          ),
                          style: customerText(
                            context,
                            12,
                            20,
                            color: colors.disabledBackground,
                          ),
                        ),
                      ],
                    );
                    final currencies = Container(
                      key: const ValueKey('analytics-currency'),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final currency in ['KHR', 'USD'])
                            TextButton(
                              onPressed: () =>
                                  controller.selectCurrency(currency),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(68, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                backgroundColor: controller.currency == currency
                                    ? colors.primary100
                                    : Colors.transparent,
                                foregroundColor: colors.foreground,
                              ),
                              child: Text(
                                currency == 'KHR' ? '៛ KHR' : r'$ USD',
                                style: customerText(
                                  context,
                                  12,
                                  20,
                                  weight: FontWeight.w600,
                                ).copyWith(fontFamily: 'Google Sans'),
                              ),
                            ),
                        ],
                      ),
                    );
                    return bounds.maxWidth < 370 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              heading,
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: currencies,
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(child: heading),
                              currencies,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('analytics-previous'),
                      tooltip: _label(context, 'Previous month', 'ខែមុន'),
                      onPressed: controller.canPrevious
                          ? () => controller.selectMonth(-1)
                          : null,
                      icon: Transform.flip(
                        flipX: true,
                        child: const CustomerDesignIcon('16298', size: 32),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _monthLabel(context),
                        textAlign: TextAlign.center,
                        style: customerText(
                          context,
                          14,
                          22,
                          color: colors.primary700,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('analytics-next'),
                      tooltip: _label(context, 'Next month', 'ខែបន្ទាប់'),
                      onPressed: controller.canNext
                          ? () => controller.selectMonth(1)
                          : null,
                      icon: controller.canNext
                          ? const CustomerDesignIcon('16298', size: 32)
                          : const Opacity(
                              opacity: .45,
                              child: CustomerDesignIcon('205d9', size: 32),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, bounds) {
                    final cards = [
                      _SummaryCard(
                        income: true,
                        amount: snapshot == null
                            ? null
                            : analyticsMoney(
                                snapshot.income,
                                snapshot.currency,
                              ),
                      ),
                      _SummaryCard(
                        income: false,
                        amount: snapshot == null
                            ? null
                            : analyticsMoney(
                                snapshot.expense,
                                snapshot.currency,
                              ),
                      ),
                    ];
                    return bounds.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.5
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cards[0],
                              const SizedBox(height: 12),
                              cards[1],
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: cards[0]),
                              const SizedBox(width: 16),
                              Expanded(child: cards[1]),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                if (controller.loading)
                  const LinearProgressIndicator(
                    key: ValueKey('analytics-loading'),
                  ),
                if (controller.error != null) ...[
                  Text(
                    snapshot == null
                        ? _label(
                            context,
                            'Analytics could not load. Please retry.',
                            'មិនអាចផ្ទុកការវិភាគបានទេ។ សូមព្យាយាមម្ដងទៀត។',
                          )
                        : _label(
                            context,
                            'Showing previously loaded values. Refresh failed.',
                            'កំពុងបង្ហាញទិន្នន័យមុន។ មិនអាចធ្វើបច្ចុប្បន្នភាពបានទេ។',
                          ),
                    key: const ValueKey('analytics-error'),
                  ),
                  TextButton(
                    onPressed: controller.refresh,
                    child: Text(_label(context, 'Retry', 'ព្យាយាមម្ដងទៀត')),
                  ),
                ],
                if (snapshot != null) ...[
                  _ChartCard(
                    snapshot: snapshot,
                    showIncome: controller.showIncome,
                    onSeries: controller.selectSeries,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _label(context, 'Cash flow breakdown', 'ចំណូល និងចំណាយ'),
                    style: customerText(
                      context,
                      17,
                      28,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final income in [true, false])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: AppPalette.navy500,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: CustomerDesignIcon(
                              income ? 'c35b5' : '9e3ed',
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              income
                                  ? _label(context, 'Income', 'ផ្ទេរចូល')
                                  : _label(context, 'Expense', 'ផ្ទេរចេញ'),
                              style: customerText(context, 15, 24),
                            ),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                analyticsMoney(
                                  income ? snapshot.income : snapshot.expense,
                                  snapshot.currency,
                                ),
                                style: customerText(
                                  context,
                                  17,
                                  28,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  String _monthLabel(BuildContext context) {
    const en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const km = [
      'មករា',
      'កុម្ភៈ',
      'មីនា',
      'មេសា',
      'ឧសភា',
      'មិថុនា',
      'កក្កដា',
      'សីហា',
      'កញ្ញា',
      'តុលា',
      'វិច្ឆិកា',
      'ធ្នូ',
    ];
    return '${_label(context, en[controller.month.month - 1], km[controller.month.month - 1])}, ${controller.month.year}';
  }
}

class AnalyticsAsset extends StatelessWidget {
  const AnalyticsAsset(
    this.name, {
    required this.width,
    required this.height,
    this.tint,
    super.key,
  });
  final String name;
  final double width, height;
  final Color? tint;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: SvgPicture.asset(
      'assets/analytics/$name.svg',
      excludeFromSemantics: true,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint!, BlendMode.srcIn),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.income, required this.amount});
  final bool income;
  final String? amount;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = income
        ? (dark ? AppPalette.gold400 : AppPalette.gold700)
        : (dark ? AppPalette.navy100 : AppPalette.navy500);
    return Container(
      key: ValueKey(
        income ? 'analytics-income-card' : 'analytics-expense-card',
      ),
      constraints: const BoxConstraints(minHeight: 101),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomerDesignIcon(
                income ? 'c35b5' : '9e3ed',
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  income
                      ? _label(context, 'Income', 'ផ្ទេរចូល')
                      : _label(context, 'Expense', 'ផ្ទេរចេញ'),
                  style: _text(context, 15, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 23),
          Text(
            amount ?? '—',
            key: ValueKey(income ? 'analytics-income' : 'analytics-expense'),
            style: _text(context, 20, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.snapshot,
    required this.showIncome,
    required this.onSeries,
  });
  final AnalyticsSnapshot snapshot;
  final bool showIncome;
  final ValueChanged<bool> onSeries;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selector = PopupMenuButton<bool>(
      key: const ValueKey('analytics-series'),
      tooltip: _label(context, 'Choose chart series', 'ជ្រើសរើសប្រភេទទិន្នន័យ'),
      initialValue: showIncome,
      onSelected: onSeries,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          child: Text(_label(context, 'Income', 'ផ្ទេរចូល')),
        ),
        PopupMenuItem(
          value: false,
          child: Text(_label(context, 'Expense', 'ផ្ទេរចេញ')),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnalyticsAsset(
                  'series-dot',
                  key: const ValueKey('analytics-series-dot'),
                  width: 8,
                  height: 8,
                  tint: analyticsSeriesColor(context, income: showIncome),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    showIncome
                        ? _label(context, 'Income', 'ផ្ទេរចូល')
                        : _label(context, 'Expense', 'ផ្ទេរចេញ'),
                    style: _text(context, 12),
                  ),
                ),
                RotatedBox(
                  quarterTurns: 1,
                  child: AnalyticsAsset(
                    'dropdown',
                    width: 22,
                    height: 22,
                    tint: Theme.of(context).brightness == Brightness.dark
                        ? AppPalette.navy200
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('analytics-chart-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, bounds) {
              final title = Tooltip(
                message: _label(
                  context,
                  'View daily values',
                  'មើលទិន្នន័យប្រចាំថ្ងៃ',
                ),
                child: InkWell(
                  key: const ValueKey('analytics-daily-values'),
                  onTap: () => _dailySheet(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _label(context, 'Overview Trends', 'ទិដ្ឋភាពទូទៅ'),
                        style: _text(context, 16, weight: FontWeight.w500)
                            .copyWith(
                              fontFamily: _label(context, 'en', 'km') == 'en'
                                  ? 'Poppins'
                                  : 'Google Sans',
                            ),
                      ),
                    ),
                  ),
                ),
              );
              return bounds.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.4
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        Align(
                          alignment: Alignment.centerRight,
                          child: selector,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        selector,
                      ],
                    );
            },
          ),
          const SizedBox(height: 9),
          DailyAnalyticsChart(
            snapshot: snapshot,
            showIncome: showIncome,
            seriesLabel: showIncome
                ? _label(context, 'Income', 'ផ្ទេរចូល')
                : _label(context, 'Expense', 'ផ្ទេរចេញ'),
          ),
          if (snapshot.empty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _label(
                  context,
                  'No activity this month',
                  'មិនមានប្រតិបត្តិការក្នុងខែនេះទេ',
                ),
                style: _text(context, 12),
              ),
            ),
        ],
      ),
    );
  }

  void _dailySheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _label(context, 'Daily values', 'ទិន្នន័យប្រចាំថ្ងៃ'),
                      style: _text(context, 18, weight: FontWeight.w500),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: snapshot.daily.length,
                itemBuilder: (context, index) {
                  final day = snapshot.daily[index];
                  return ListTile(
                    title: Text(
                      '${monthKey(snapshot.month)}-${day.date.day.toString().padLeft(2, '0')}',
                    ),
                    subtitle: Text(
                      '${_label(context, 'Income', 'ផ្ទេរចូល')}: ${analyticsMoney(day.income, snapshot.currency)}\n'
                      '${_label(context, 'Expense', 'ផ្ទេរចេញ')}: ${analyticsMoney(day.expense, snapshot.currency)}',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
