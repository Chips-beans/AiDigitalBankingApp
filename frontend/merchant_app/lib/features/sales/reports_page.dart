import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
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
      title: t(context, 'Reports', 'របាយការណ៍'),
      onRefresh: load,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in ['DAY', 'MONTH'])
              ChoiceChip(
                key: ValueKey('report-$p'),
                label: Text(
                  p == 'DAY'
                      ? t(context, 'Daily', 'ប្រចាំថ្ងៃ')
                      : t(context, 'Monthly', 'ប្រចាំខែ'),
                ),
                selected: period == p,
                onSelected: (_) {
                  setState(() {
                    period = p;
                    defaults();
                  });
                  load();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        CurrencyFilter(
          value: currency,
          all: false,
          onChanged: (c) => setState(() => currency = c!),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: range,
          icon: const Icon(Icons.date_range_outlined),
          label: Text('$from — $to', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        NoticeBanner(
          t(
            context,
            'Collections are payments received, not profit.',
            'ប្រាក់ទទួលបានគឺជាការទូទាត់ដែលបានទទួល មិនមែនជាប្រាក់ចំណេញទេ។',
          ),
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
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(context, 'Gross collections', 'ប្រាក់ទទួលបានសរុប'),
                  style: mText(context, 14, 22),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AmountText(
                    shopAmount(totals.gross, currency),
                    style: mText(context, 28, 38, weight: FontWeight.w600),
                  ),
                ),
                Text(
                  paymentCount(context, totals.count),
                  style: mText(context, 12, 18),
                ),
                const SizedBox(height: 16),
                CollectionsChart(buckets: buckets, currency: currency),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionTitle(
            t(
              context,
              'Count and gross by period',
              'ចំនួន និងប្រាក់ទទួលតាមពេល',
            ),
          ),
          const SizedBox(height: 8),
          for (final b in buckets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.bucket,
                          style: mText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          paymentCount(context, b.count),
                          style: mText(context, 12, 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: AmountText(
                      shopAmount(b.gross, b.currency),
                      textAlign: TextAlign.end,
                      style: mText(context, 14, 22, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Text('UTC+07:00', style: mText(context, 12, 18)),
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
        SizedBox(
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
                    child: Tooltip(
                      message:
                          '${widget.buckets[i].bucket}: ${shopAmount(widget.buckets[i].gross, widget.currency)}',
                      child: InkWell(
                        onTap: () => setState(() => selected = i),
                        child: SizedBox(
                          height: 132,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 8,
                              height: values[i] == BigInt.zero
                                  ? 1
                                  : ((values[i] * BigInt.from(1200000)) ~/ peak)
                                            .toDouble() /
                                        10000,
                              decoration: BoxDecoration(
                                color: selected == i
                                    ? merchantNavy(context)
                                    : AppPalette.gold500,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
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
        Container(height: 1, color: AppColors.of(context).border),
        const SizedBox(height: 8),
        if (widget.buckets.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.buckets.first.bucket,
                  style: mText(context, 11, 18),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.buckets.last.bucket,
                  textAlign: TextAlign.end,
                  style: mText(context, 11, 18),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
