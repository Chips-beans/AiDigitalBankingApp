import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_system/design_system.dart';
import '../../../app/app_preferences.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../home/presentation/kesor_home_screen.dart';
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
      final dark = Theme.of(context).brightness == Brightness.dark;
      final snapshot = controller.snapshot;
      final bottom = math.max(24.0, MediaQuery.paddingOf(context).bottom);
      return ColoredBox(
        color: colors.surface,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final bannerHeight = math.max(220.0, bounds.maxHeight * 383 / 956);
            final motifScale = math.min(1.0, (bannerHeight - 110) / 187);
            return Stack(
              children: [
                Positioned.fill(
                  top: bannerHeight,
                  child: ColoredBox(color: colors.background),
                ),
                Positioned.fill(
                  bottom: bottom + KesorBottomBar.height(context) + 20,
                  child: RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('analytics-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          SizedBox(
                            height: bannerHeight,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 20,
                                  right: 20,
                                  top:
                                      (showDeviceChrome
                                          ? 54
                                          : MediaQuery.paddingOf(context).top) +
                                      10,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: Center(
                                          child: AnalyticsAsset(
                                            'logo',
                                            width: 37.3334,
                                            height: 46.6627,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: colors.border,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          _label(
                                            context,
                                            'Monthly',
                                            'ប្រចាំខែ',
                                          ),
                                          style: _text(context, 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  top: math.max(100, bannerHeight * .34),
                                  left:
                                      (bounds.maxWidth - 187) / 2 +
                                      48 * motifScale,
                                  child: ExcludeSemantics(
                                    child: Transform.scale(
                                      scale: motifScale,
                                      alignment: Alignment.topCenter,
                                      child: const KesorBalanceMotif(
                                        asset: 'assets/analytics/motif.svg',
                                      ),
                                    ),
                                  ),
                                ),
                                if (showDeviceChrome)
                                  Positioned(
                                    left: 36,
                                    top: 15,
                                    child: Text(
                                      '9:41',
                                      style: _text(
                                        context,
                                        17,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                if (showDeviceChrome)
                                  Positioned(
                                    right: 20,
                                    top: 0,
                                    child: AnalyticsAsset(
                                      'levels',
                                      width: 143.003,
                                      height: 54,
                                      tint: dark ? colors.foreground : null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            key: const ValueKey('analytics-sheet'),
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      key: const ValueKey('analytics-previous'),
                                      tooltip: _label(
                                        context,
                                        'Previous month',
                                        'ខែមុន',
                                      ),
                                      onPressed: controller.canPrevious
                                          ? () => controller.selectMonth(-1)
                                          : null,
                                      icon: Transform.flip(
                                        flipX: true,
                                        child: const AnalyticsAsset(
                                          'previous',
                                          width: 32,
                                          height: 32,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _monthLabel(context),
                                        textAlign: TextAlign.center,
                                        style: _text(
                                          context,
                                          14,
                                          color: dark
                                              ? AppPalette.gold400
                                              : AppPalette.gold700,
                                          weight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        key: const ValueKey(
                                          'analytics-currency',
                                        ),
                                        value: controller.currency,
                                        icon: RotatedBox(
                                          quarterTurns: 1,
                                          child: AnalyticsAsset(
                                            'dropdown',
                                            width: 22,
                                            height: 22,
                                            tint: dark
                                                ? AppPalette.navy200
                                                : null,
                                          ),
                                        ),
                                        style: _text(context, 12),
                                        onChanged: (value) {
                                          if (value != null) {
                                            controller.selectCurrency(value);
                                          }
                                        },
                                        items: const ['USD', 'KHR']
                                            .map(
                                              (v) => DropdownMenuItem(
                                                value: v,
                                                child: Text(v),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('analytics-next'),
                                      tooltip: _label(
                                        context,
                                        'Next month',
                                        'ខែបន្ទាប់',
                                      ),
                                      onPressed: controller.canNext
                                          ? () => controller.selectMonth(1)
                                          : null,
                                      // Gold like Previous; a future month stays disabled grey.
                                      icon: controller.canNext
                                          ? const AnalyticsAsset(
                                              'previous',
                                              width: 32,
                                              height: 32,
                                            )
                                          : const Opacity(
                                              opacity: .45,
                                              child: AnalyticsAsset(
                                                'next',
                                                width: 32,
                                                height: 32,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
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
                                    return constraints.maxWidth < 300 ||
                                            MediaQuery.textScalerOf(context)
                                                    .scale(1) >
                                                1.5
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              cards[0],
                                              const SizedBox(height: 12),
                                              cards[1],
                                            ],
                                          )
                                        : Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                  LinearProgressIndicator(
                                    key: const ValueKey('analytics-loading'),
                                    semanticsLabel: _label(
                                      context,
                                      'Loading analytics',
                                      'កំពុងផ្ទុកការវិភាគ',
                                    ),
                                  ),
                                if (controller.error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
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
                                          key: const ValueKey(
                                            'analytics-error',
                                          ),
                                          style: _text(context, 13),
                                        ),
                                        TextButton(
                                          onPressed: controller.refresh,
                                          child: Text(
                                            _label(
                                              context,
                                              'Retry',
                                              'ព្យាយាមម្ដងទៀត',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (snapshot != null)
                                  _ChartCard(
                                    snapshot: snapshot,
                                    showIncome: controller.showIncome,
                                    onSeries: controller.selectSeries,
                                  )
                                else if (controller.loading)
                                  const SizedBox(height: 264)
                                else
                                  const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showDeviceChrome)
                  Positioned(
                    bottom: 5,
                    left: (bounds.maxWidth - 134) / 2,
                    child: Container(
                      width: 134,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colors.foreground,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            );
          },
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
        color: income
            ? (dark
                  ? AppPalette.gold700.withValues(alpha: .28)
                  : AppPalette.gold100)
            : (dark ? AppPalette.navy600 : AppPalette.navy100),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: income ? 0 : math.pi,
                child: Transform.flip(
                  flipY: !income,
                  child: AnalyticsAsset(
                    income ? 'income' : 'expense',
                    width: 20,
                    height: 20,
                    tint: dark ? accent : null,
                  ),
                ),
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
