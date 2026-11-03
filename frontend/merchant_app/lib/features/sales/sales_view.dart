import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/merchant_strings.dart';
import '../collect/merchant_collect.dart';
import '../collect/wallet_page.dart';
import '../shop/shop_home.dart';
import '../shop/shop_widgets.dart';
import 'receipt_page.dart';
import 'reports_page.dart';
import 'requests_page.dart';
import 'sales_controller.dart';

class SalesView extends StatefulWidget {
  const SalesView({
    required this.controller,
    required this.onRequest,
    super.key,
  });
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t(context, 'Sales', 'ការលក់'),
                    style: mText(context, 20, 28, weight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey('sales-reports'),
                  tooltip: t(context, 'Reports', 'របាយការណ៍'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportsPage(
                        gateway: sales.gateway,
                        onExpired: sales.onExpired,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.bar_chart_rounded),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('sales-requests'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RequestsPage(
                      gateway: sales.gateway,
                      onExpired: sales.onExpired,
                      onWaiting: widget.onRequest,
                    ),
                  ),
                ),
                icon: const Icon(Icons.history_rounded),
                label: Text(t(context, 'Requests', 'សំណើ')),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
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
                labelText: t(
                  context,
                  'Reference or order note',
                  'លេខយោង ឬកំណត់ចំណាំ',
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.search_rounded),
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
            Text(
              '${sales.filter.from} — ${sales.filter.to} · UTC+07:00',
              style: mText(context, 12, 18),
            ),
            const SizedBox(height: 8),
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
              SectionTitle(day.key),
              Text(
                daySummary(context, day.value),
                style: mText(context, 12, 18),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (all &&
          bounds.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20) {
        return SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 'ALL',
              label: Text(t(context, 'All', 'ទាំងអស់')),
            ),
            ButtonSegment(value: 'KHR', label: Text(t(context, 'KHR', 'រៀល'))),
            ButtonSegment(
              value: 'USD',
              label: Text(t(context, 'USD', 'ដុល្លារ')),
            ),
          ],
          selected: {value ?? 'ALL'},
          onSelectionChanged: (v) =>
              onChanged(v.first == 'ALL' ? null : v.first),
        );
      }
      // Wrapped choices preserve readable labels at narrow widths / large text.
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (all)
            ChoiceChip(
              label: Text(t(context, 'All', 'ទាំងអស់')),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
          for (final c in ['KHR', 'USD'])
            ChoiceChip(
              label: Text(
                c == 'KHR'
                    ? t(context, 'KHR', 'រៀល')
                    : t(context, 'USD', 'ដុល្លារ'),
              ),
              selected: value == c,
              onSelected: (_) => onChanged(c),
            ),
        ],
      );
    },
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
