import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_system/design_system.dart';
import '../../../app/app_preferences.dart';
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
      final dark = Theme.of(context).brightness == Brightness.dark;
      return ColoredBox(
        color: colors.surface,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: LayoutBuilder(
                builder: (context, box) {
                  final footer =
                      math.max(32.0, MediaQuery.paddingOf(context).bottom) +
                      64 +
                      20;
                  final top = showDeviceChrome ? 48.0 : 0.0;
                  // Allocate the lower panel first; decoration yields space before data.
                  final available = math.max(0.0, box.maxHeight - top - footer);
                  final scale = (available / 792).clamp(.22, 1.0);
                  final upper = math.max(
                    box.maxHeight - top - 577,
                    math.min(331.0, math.max(68.0, available * .418)),
                  );
                  final lower = box.maxHeight - top - upper;
                  final gap = 20 * scale;
                  final summaryHeight = 101 * scale;
                  Widget fitted(
                    String text,
                    double size,
                    double line, {
                    Color? color,
                    FontWeight weight = FontWeight.w400,
                  }) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      style: customerText(
                        context,
                        size,
                        line,
                        color: color,
                        weight: weight,
                      ),
                    ),
                  );
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      textScaler: TextScaler.linear(
                        math.min(media.textScaler.scale(1), 1.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        if (showDeviceChrome)
                          SizedBox(
                            height: 48,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 36),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '9:41',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SvgPicture.asset(
                                    'assets/analytics/figma-levels.svg',
                                    width: 143,
                                    height: 54,
                                    excludeFromSemantics: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(
                          height: upper,
                          child: Column(
                            children: [
                              SizedBox(
                                height: math.min(94, upper * .45),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    10 * scale,
                                    20,
                                    12 * scale,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: Tooltip(
                                                message: _label(
                                                  context,
                                                  'Refresh',
                                                  'ធ្វើបច្ចុប្បន្នភាព',
                                                ),
                                                child: InkWell(
                                                  key: const ValueKey(
                                                    'analytics-refresh',
                                                  ),
                                                  onTap: controller.loading
                                                      ? null
                                                      : controller.refresh,
                                                  child: fitted(
                                                    _label(
                                                      context,
                                                      'Analytic',
                                                      'ការវិភាគ',
                                                    ),
                                                    24,
                                                    36,
                                                    color: customerNavy(
                                                      context,
                                                    ),
                                                    weight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 4 * scale),
                                            Flexible(
                                              child: fitted(
                                                _label(
                                                  context,
                                                  'Track and Manage Your Money',
                                                  'តាមដាន និងគ្រប់គ្រងប្រាក់របស់អ្នក',
                                                ),
                                                12,
                                                20,
                                                color:
                                                    colors.disabledBackground,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: math.min(
                                          162,
                                          (box.maxWidth - 40) * .405,
                                        ),
                                        child: Row(
                                          key: const ValueKey(
                                            'analytics-currency',
                                          ),
                                          children: [
                                            for (final currency in [
                                              'KHR',
                                              'USD',
                                            ])
                                              Expanded(
                                                child: SizedBox(
                                                  height: 48,
                                                  child: TextButton(
                                                    key: ValueKey(
                                                      'analytics-currency-$currency',
                                                    ),
                                                    onPressed: () => controller
                                                        .selectCurrency(
                                                          currency,
                                                        ),
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      foregroundColor:
                                                          controller.currency ==
                                                              currency
                                                          ? Colors.white
                                                          : colors.foreground,
                                                    ),
                                                    child: Container(
                                                      height: 36,
                                                      width: double.infinity,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            controller
                                                                    .currency ==
                                                                currency
                                                            ? AppPalette.navy500
                                                            : Colors
                                                                  .transparent,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: FittedBox(
                                                        child: Text(
                                                          currency,
                                                          style:
                                                              const TextStyle(
                                                                fontFamily:
                                                                    'Poppins',
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.zero,
                                    child: Image.asset(
                                      'assets/analytics/figma-money-overview.png',
                                      key: const ValueKey(
                                        'analytics-illustration',
                                      ),
                                      width: 236,
                                      height: 157,
                                      fit: BoxFit.contain,
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: lower,
                          child: Container(
                            key: const ValueKey('analytics-panel'),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(36),
                              ),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              16 * scale,
                              20,
                              footer,
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 48 * scale,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        key: const ValueKey(
                                          'analytics-previous',
                                        ),
                                        tooltip: _label(
                                          context,
                                          'Previous month',
                                          'ខែមុន',
                                        ),
                                        onPressed: controller.canPrevious
                                            ? () => controller.selectMonth(-1)
                                            : null,
                                        padding: EdgeInsets.zero,
                                        alignment: Alignment.centerLeft,
                                        icon: Transform.flip(
                                          flipX: true,
                                          child: const CustomerDesignIcon(
                                            '16298',
                                            size: 32,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: fitted(
                                            _monthLabel(context),
                                            14,
                                            22,
                                            color: dark
                                                ? AppPalette.gold200
                                                : AppPalette.gold700,
                                            weight: FontWeight.w500,
                                          ),
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
                                        padding: EdgeInsets.zero,
                                        alignment: Alignment.centerRight,
                                        icon: CustomerDesignIcon(
                                          controller.canNext
                                              ? '16298'
                                              : '205d9',
                                          size: 32,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12 * scale),
                                SizedBox(
                                  height: summaryHeight,
                                  child: Row(
                                    children: [
                                      for (final income in [true, false]) ...[
                                        if (!income) const SizedBox(width: 16),
                                        Expanded(
                                          child: _SummaryCard(
                                            income: income,
                                            amount: snapshot == null
                                                ? null
                                                : analyticsMoney(
                                                    income
                                                        ? snapshot.income
                                                        : snapshot.expense,
                                                    snapshot.currency,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(height: gap),
                                if (controller.loading)
                                  const LinearProgressIndicator(
                                    key: ValueKey('analytics-loading'),
                                  ),
                                if (controller.error != null)
                                  SizedBox(
                                    height: 48 * scale,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: fitted(
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
                                            12,
                                            20,
                                          ),
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
                                  Expanded(
                                    child: _ChartCard(
                                      snapshot: snapshot,
                                      showIncome: controller.showIncome,
                                      onSeries: controller.selectSeries,
                                    ),
                                  ),
                                if (snapshot == null)
                                  Expanded(
                                    child: Center(
                                      child: IconButton(
                                        tooltip: _label(
                                          context,
                                          'Refresh',
                                          'ធ្វើបច្ចុប្បន្នភាព',
                                        ),
                                        onPressed: controller.loading
                                            ? null
                                            : controller.refresh,
                                        icon: const Icon(Icons.refresh),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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

      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Padding(
          padding: EdgeInsets.symmetric(
            vertical: math.min(13, box.maxHeight * .13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomerDesignIcon(
                        income ? 'c35b5' : '9e3ed',
                        size: 20,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        income
                            ? _label(context, 'Income', 'ផ្ទេរចូល')
                            : _label(context, 'Expense', 'ផ្ទេរចេញ'),
                        style: _text(context, 15, color: accent),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amount ?? '—',
                    key: ValueKey(
                      income ? 'analytics-income' : 'analytics-expense',
                    ),
                    style: _text(context, 20, weight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          widthFactor: 1,
          heightFactor: 1,
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
                    'dropdown-413',
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
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = (bounds.maxHeight / 264).clamp(.2, 1.0);
        return Container(
          key: const ValueKey('analytics-chart-card'),
          padding: EdgeInsets.all(18 * compact),
          decoration: BoxDecoration(
            color: colors.background,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48 * compact,
                child: LayoutBuilder(
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
                              _label(
                                context,
                                'Overview Trends',
                                'ទិដ្ឋភាពទូទៅ',
                              ),
                              style: _text(context, 16, weight: FontWeight.w500)
                                  .copyWith(
                                    fontFamily:
                                        _label(context, 'en', 'km') == 'en'
                                        ? 'Poppins'
                                        : 'Google Sans',
                                  ),
                            ),
                          ),
                        ),
                      ),
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 180, child: title),
                          ),
                        ),
                        SizedBox(
                          width: math.min(124, bounds.maxWidth * .45),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: selector,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: 9 * compact),
              Expanded(
                child: DailyAnalyticsChart(
                  height: double.infinity,
                  snapshot: snapshot,
                  showIncome: showIncome,
                  seriesLabel: showIncome
                      ? _label(context, 'Income', 'ផ្ទេរចូល')
                      : _label(context, 'Expense', 'ផ្ទេរចេញ'),
                ),
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
      },
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
