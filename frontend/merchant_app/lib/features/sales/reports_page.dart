import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import 'receipt_page.dart';
import 'sales_view.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    required this.gateway,
    this.onExpired,
    this.initialPeriod = 'DAY',
    super.key,
  });
  final MerchantCollectGateway gateway;
  final VoidCallback? onExpired;
  final String initialPeriod;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late String period = widget.initialPeriod;
  String currency = 'KHR';
  late String from, to;
  CollectionReport? report;
  ShopFailure? failure;
  bool loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    defaults();
    load();
  }

  void defaults() {
    final now = businessToday();
    to = dateKey(now);
    from = dateKey(
      period == 'DAY'
          ? now.subtract(const Duration(days: 6))
          : DateTime.utc(now.year, now.month - 5),
    );
  }

  Future<void> load() async {
    final g = ++generation;
    setState(() {
      loading = true;
      failure = null;
      report = null;
    });
    try {
      final value = await widget.gateway.report(
        period: period,
        from: from,
        to: to,
      );
      if (mounted && g == generation) setState(() => report = value);
    } catch (e) {
      if (!mounted || g != generation) return;
      final error = e is ShopFailure
          ? e
          : const ShopFailure('INVALID_RESPONSE');
      if (error.expired) widget.onExpired?.call();
      if (mounted) setState(() => failure = error);
    } finally {
      if (mounted && g == generation) setState(() => loading = false);
    }
  }

  Future<void> range() async {
    final value = await pickHistoryRange(
      context,
      from: from,
      to: to,
      maxDays: period == 'DAY' ? 92 : 732,
    );
    if (value == null || !mounted) return;
    if (period == 'MONTH' &&
        (value.end.year - value.start.year) * 12 +
                value.end.month -
                value.start.month >=
            24) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(context, 'Choose at most 24 months.', 'សូមជ្រើសមិនលើស ២៤ ខែ។'),
          ),
        ),
      );
      return;
    }
    setState(() {
      from = dateKey(value.start);
      to = dateKey(value.end);
    });
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final buckets =
        report?.buckets.where((b) => b.currency == currency).toList() ??
        <ReportBucket>[];
    final totals = report?.totals
        .where((t) => t.currency == currency)
        .firstOrNull;
    return HistoryScaffold(
      title: t(context, 'Collections report', 'របាយការណ៍ប្រាក់ទទួល'),
      onRefresh: load,
      children: [
        QSegments(
          values: const ['DAY', 'MONTH'],
          labels: [
            t(context, 'Daily', 'ប្រចាំថ្ងៃ'),
            t(context, 'Monthly', 'ប្រចាំខែ'),
          ],
          value: period,
          onChanged: (p) {
            setState(() {
              period = p;
              defaults();
            });
            load();
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final currencyControl = CurrencyFilter(
              value: currency,
              all: false,
              onChanged: (c) => setState(() => currency = c!),
            );
            final dates = OutlinedButton(
              onPressed: range,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${merchantDateLabel(context, DateTime.parse(from))} – ${merchantDateLabel(context, DateTime.parse(to))}',
                      style: mText(context, 15, 24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const QIcon('602f1'),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [currencyControl, const SizedBox(height: 12), dates],
            );
          },
        ),
        const SizedBox(height: 16),
        if (loading)
          NoticeBanner(t(context, 'Loading report…', 'កំពុងផ្ទុករបាយការណ៍…')),
        if (failure != null)
          NoticeBanner(
            shopFailureMessage(context, failure!),
            tone: NoticeTone.error,
            action: TextButton(
              onPressed: load,
              child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
            ),
          ),
        if (totals != null) ...[
          NoticeBanner(
            t(
              context,
              'Collections are payments received, not profit.',
              'ប្រាក់ទទួលបានគឺជាការទូទាត់ដែលបានទទួល មិនមែនជាប្រាក់ចំណេញទេ។',
            ),
          ),
          const SizedBox(height: 12),
          QGroup(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(context, 'Gross collections', 'ប្រាក់ទទួលសរុប'),
                  style: mText(
                    context,
                    12,
                    20,
                    color: AppColors.of(context).disabledBackground,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AmountText(
                      shopAmount(totals.gross, currency),
                      style: mText(context, 24, 36, weight: FontWeight.w600),
                    ),
                    Text(
                      paymentCount(context, totals.count),
                      style: mText(
                        context,
                        12,
                        20,
                        color: AppColors.of(context).disabledBackground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CollectionsChart(buckets: buckets, currency: currency),
              ],
            ),
          ),
          const SizedBox(height: 16),
          QGroup(
            child: Column(
              children: [
                for (final bucket in buckets.reversed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.of(context).border),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                period == 'DAY'
                                    ? merchantDateLabel(
                                        context,
                                        DateTime.parse(bucket.bucket),
                                      )
                                    : bucket.bucket,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                paymentCount(context, bucket.count),
                                style: mText(
                                  context,
                                  13,
                                  18,
                                  color: AppColors.of(context)
                                      .disabledBackground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AmountText(
                            shopAmount(bucket.gross, bucket.currency),
                            textAlign: TextAlign.end,
                            style: mText(
                              context,
                              15,
                              24,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Gold rounded bars, navy selection and exact integer scaling, following the
/// Customer daily chart. Labels and the table expose every exact value.
class CollectionsChart extends StatefulWidget {
  const CollectionsChart({
    required this.buckets,
    required this.currency,
    super.key,
  });
  final List<ReportBucket> buckets;
  final String currency;
  @override
  State<CollectionsChart> createState() => _CollectionsChartState();
}

class _CollectionsChartState extends State<CollectionsChart> {
  int? selected;
  @override
  void didUpdateWidget(CollectionsChart old) {
    super.didUpdateWidget(old);
    selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.buckets
        .map((b) => moneyUnits(b.gross, widget.currency))
        .toList();
    final peak = values.fold<BigInt>(BigInt.one, (a, b) => a > b ? a : b);
    final active = selected != null && selected! < widget.buckets.length
        ? widget.buckets[selected!]
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active != null)
          Text(
            '${active.bucket} · ${shopAmount(active.gross, active.currency)}',
            style: mText(context, 12, 18),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final chartWidth = widget.buckets.length * 32.0 > box.maxWidth
                ? widget.buckets.length * 32.0
                : box.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 132,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < values.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          label:
                              '${widget.buckets[i].bucket} · ${shopAmount(widget.buckets[i].gross, widget.currency)}',
                          child: InkWell(
                            onTap: () => setState(() => selected = i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: 22,
                                      height: values[i] == BigInt.zero
                                          ? 2
                                          : ((values[i] *
                                                            BigInt.from(
                                                              1100000,
                                                            )) ~/
                                                        peak)
                                                    .toDouble() /
                                                10000,
                                      decoration: BoxDecoration(
                                        color:
                                            (selected ?? values.length - 1) == i
                                            ? AppPalette.gold500
                                            : Theme.of(context).brightness ==
                                                  Brightness.dark
                                            ? AppPalette.navy400
                                            : AppPalette.navy200,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.buckets[i].bucket.split('-').last,
                                  style: mText(
                                    context,
                                    11,
                                    15,
                                    color: AppColors.of(context)
                                        .disabledBackground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
