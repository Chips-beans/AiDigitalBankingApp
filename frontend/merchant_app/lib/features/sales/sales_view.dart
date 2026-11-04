import 'package:kesor_design_system/kesor_design_system.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../collect/merchant_collect.dart';
import '../collect/wallet_page.dart';
import '../shop/shop_home.dart';
import '../shop/shop_widgets.dart';
import 'receipt_page.dart';
import 'reports_page.dart';
import 'sales_controller.dart';

class SalesView extends StatefulWidget {
  const SalesView({
    required this.controller,
    required this.onRequest,
    this.showHeader = true,
    super.key,
  });
  final bool showHeader;
  final SalesController controller;
  final Future<void> Function(String) onRequest;
  @override
  State<SalesView> createState() => _SalesViewState();
}

class _SalesViewState extends State<SalesView> {
  final scroll = ScrollController();
  final search = TextEditingController();
  Timer? debounce;
  String period = 'today';
  SalesController get sales => widget.controller;
  @override
  void initState() {
    super.initState();
    search.text = sales.filter.q;
    final today = businessToday(), f = sales.filter;
    final end = dateKey(today);
    final yesterday = dateKey(today.subtract(const Duration(days: 1)));
    period = f.from == end && f.to == end
        ? 'today'
        : f.from == yesterday && f.to == yesterday
        ? 'yesterday'
        : f.from == dateKey(today.subtract(const Duration(days: 6))) &&
              f.to == end
        ? 'week'
        : f.from == dateKey(DateTime.utc(today.year, today.month)) &&
              f.to == end
        ? 'month'
        : 'custom';
    unawaited(sales.refresh());
    scroll.addListener(_scroll);
  }

  void _scroll() {
    if (scroll.position.extentAfter < 300 && sales.failure == null) {
      unawaited(sales.more());
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  void apply({
    String? from,
    String? to,
    String? currency,
    bool setCurrency = false,
    String? q,
  }) {
    final f = sales.filter;
    unawaited(
      sales.change(
        SalesFilter(
          from: from ?? f.from,
          to: to ?? f.to,
          currency: setCurrency ? currency : f.currency,
          q: q ?? f.q,
        ),
      ),
    );
  }

  Future<void> choosePeriod(String value) async {
    final today = businessToday();
    DateTime start = today, end = today;
    if (value == 'custom') {
      final picked = await pickHistoryRange(
        context,
        from: sales.filter.from,
        to: sales.filter.to,
        maxDays: 366,
      );
      if (picked == null || !mounted) return;
      start = picked.start;
      end = picked.end;
    } else if (value == 'yesterday') {
      start = today.subtract(const Duration(days: 1));
      end = start;
    } else if (value == 'week') {
      start = today.subtract(const Duration(days: 6));
    } else if (value == 'month') {
      start = DateTime.utc(today.year, today.month);
    }
    setState(() => period = value);
    apply(from: dateKey(start), to: dateKey(end));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sales,
    builder: (context, _) {
      final grouped = <String, List<ShopReceipt>>{};
      for (final r in sales.items) {
        grouped.putIfAbsent(dateKey(businessTime(r.paidAt)), () => []).add(r);
      }
      return RefreshIndicator(
        onRefresh: sales.refresh,
        child: ListView(
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (widget.showHeader)
              Row(
                children: [
                  const QBack(),
                  Expanded(
                    child: Text(
                      t(context, 'Sales', 'ការលក់'),
                      style: AppTextStyles.of(context).titleL,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sales-reports'),
                    tooltip: t(context, 'Reports', 'របាយការណ៍'),
                    icon: const QIcon('7b0e4'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportsPage(
                          gateway: sales.gateway,
                          onExpired: sales.onExpired,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                for (final item in [
                  ('today', t(context, 'Today', 'ថ្ងៃនេះ')),
                  ('yesterday', t(context, 'Yesterday', 'ម្សិលមិញ')),
                  ('week', t(context, '7 days', '៧ ថ្ងៃ')),
                  ('month', t(context, 'This month', 'ខែនេះ')),
                  ('custom', t(context, 'Custom', 'ជ្រើសរើស')),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: period == item.$1,
                    onSelected: (_) => choosePeriod(item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            CurrencyFilter(
              value: sales.filter.currency,
              onChanged: (c) => apply(currency: c, setCurrency: true),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sales-search'),
              controller: search,
              maxLength: 50,
              decoration: InputDecoration(
                hintText: t(
                  context,
                  'Search reference or note',
                  'លេខយោង ឬកំណត់ចំណាំ',
                ),
                counterText: '',
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(14),
                  child: QIcon('32729'),
                ),
              ),
              onChanged: (v) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 400),
                  () => apply(q: v.trim()),
                );
              },
            ),
            const SizedBox(height: 16),
            TodayCard(
              title: t(
                context,
                'Filtered collections',
                'ប្រាក់ទទួលបានតាមការច្រោះ',
              ),
              dashboard: null,
              suppliedTotals:
                  sales.items.isEmpty &&
                      (sales.loading || sales.failure != null)
                  ? null
                  : sales.totals,
            ),
            const SizedBox(height: 16),
            if (sales.loading)
              NoticeBanner(
                t(context, 'Loading payments…', 'កំពុងផ្ទុកការទូទាត់…'),
              ),
            if (sales.failure != null)
              NoticeBanner(
                shopFailureMessage(context, sales.failure!),
                tone: NoticeTone.error,
                action: TextButton(
                  onPressed: sales.loading
                      ? null
                      : () =>
                            sales.failure?.code == 'CONCURRENT_UPDATE' ||
                                sales.items.isEmpty
                            ? sales.refresh()
                            : sales.more(),
                  child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
                ),
              ),
            if (!sales.loading && sales.failure == null && sales.items.isEmpty)
              NoticeBanner(
                t(
                  context,
                  'No payments match these filters.',
                  'គ្មានការទូទាត់ត្រូវនឹងការច្រោះនេះទេ។',
                ),
              ),
            for (final day in grouped.entries) ...[
              const SizedBox(height: 16),
              SectionTitle(
                merchantDateLabel(
                  context,
                  DateTime.parse(day.key),
                  today: true,
                ),
                trailing: Text(
                  t(
                    context,
                    '${day.value.length} shown',
                    'បានបង្ហាញ ${day.value.length}',
                  ),
                  style: mText(
                    context,
                    13,
                    18,
                    color: AppColors.of(context).disabledBackground,
                  ),
                ),
              ),
              for (final r in day.value)
                ReceiptRow(
                  r,
                  onTap: () => openReceipt(
                    context,
                    sales.gateway,
                    r.reference,
                    onExpired: sales.onExpired,
                  ),
                ),
            ],
            if (sales.nextCursor != null)
              TextButton(
                onPressed: sales.loading ? null : sales.more,
                child: Text(t(context, 'Load more', 'ផ្ទុកបន្ថែម')),
              ),
          ],
        ),
      );
    },
  );
}

String daySummary(BuildContext context, List<ShopReceipt> receipts) {
  final sums = <String, BigInt>{};
  for (final r in receipts) {
    sums.update(
      r.currency,
      (n) => n + moneyUnits(r.amount, r.currency),
      ifAbsent: () => moneyUnits(r.amount, r.currency),
    );
  }
  return [
    t(
      context,
      '${paymentCount(context, receipts.length)} shown',
      'បានបង្ហាញ ${paymentCount(context, receipts.length)}',
    ),
    for (final entry in sums.entries)
      shopAmount(unitsMoney(entry.value, entry.key), entry.key),
  ].join(' · ');
}

class CurrencyFilter extends StatelessWidget {
  const CurrencyFilter({
    required this.value,
    required this.onChanged,
    this.all = true,
    super.key,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool all;
  @override
  Widget build(BuildContext context) => QSegments<String>(
    values: [if (all) 'ALL', 'KHR', 'USD'],
    labels: [
      if (all) t(context, 'All', 'ទាំងអស់'),
      t(context, 'KHR', 'រៀល'),
      t(context, 'USD', 'ដុល្លារ'),
    ],
    compact: !all,
    value: value ?? 'ALL',
    onChanged: (v) => onChanged(v == 'ALL' ? null : v),
  );
}

Future<DateTimeRange?> pickHistoryRange(
  BuildContext context, {
  required String from,
  required String to,
  required int maxDays,
}) async {
  final result = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
    initialDateRange: DateTimeRange(
      start: DateTime.parse(from),
      end: DateTime.parse(to),
    ),
    helpText: t(context, 'Collection dates', 'កាលបរិច្ឆេទទទួលប្រាក់'),
    saveText: t(context, 'Apply', 'អនុវត្ត'),
  );
  if (result == null || !context.mounted) return null;
  if (result.end.difference(result.start).inDays >= maxDays) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            context,
            'Choose at most $maxDays days.',
            'សូមជ្រើសមិនលើស $maxDays ថ្ងៃ។',
          ),
        ),
      ),
    );
    return null;
  }
  return result;
}
