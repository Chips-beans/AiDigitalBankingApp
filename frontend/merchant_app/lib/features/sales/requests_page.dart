import 'package:flutter/material.dart';

import '../../core/merchant_strings.dart';
import '../collect/collect_view.dart';
import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import 'receipt_page.dart';

String requestLabel(BuildContext context, RequestStatus status) =>
    switch (status) {
      RequestStatus.waiting => t(context, 'Waiting', 'កំពុងរង់ចាំ'),
      RequestStatus.paid => t(context, 'Paid', 'បានបង់'),
      RequestStatus.expired => t(context, 'Expired', 'ផុតកំណត់'),
      RequestStatus.cancelled => t(context, 'Cancelled', 'បានបោះបង់'),
    };

class RequestsPage extends StatefulWidget {
  const RequestsPage({
    required this.gateway,
    required this.onWaiting,
    this.onExpired,
    super.key,
  });
  final MerchantCollectGateway gateway;
  final Future<void> Function(String) onWaiting;
  final VoidCallback? onExpired;
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  RequestStatus? status;
  final items = <RequestSummary>[];
  final scroll = ScrollController();
  String? cursor;
  ShopFailure? failure;
  bool loading = false, opening = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load(reset: true);
    scroll.addListener(_scroll);
  }

  void _scroll() {
    if (scroll.position.extentAfter < 300 &&
        failure == null &&
        cursor != null) {
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading && !reset) return;
    if (reset) {
      generation++;
      items.clear();
      cursor = null;
    }
    final g = generation;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final result = await widget.gateway.requestHistory(
        status: status,
        cursor: cursor,
      );
      if (!mounted || g != generation) return;
      setState(() {
        final seen = items.map((r) => r.id).toSet();
        items.addAll(result.items.where((r) => seen.add(r.id)));
        cursor = result.nextCursor;
      });
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

  Future<void> open(RequestSummary request) async {
    setState(() => opening = true);
    try {
      if (request.status == RequestStatus.waiting) {
        await widget.onWaiting(request.id);
        if (mounted) Navigator.of(context).pop();
      } else if (request.status == RequestStatus.paid) {
        final current = await widget.gateway.requestStatus(request.id);
        if (mounted && current.receipt != null) {
          openReceipt(
            context,
            widget.gateway,
            current.receipt!.reference,
            onExpired: widget.onExpired,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final error = e is ShopFailure
          ? e
          : const ShopFailure('INVALID_RESPONSE');
      if (error.expired) widget.onExpired?.call();
      if (mounted) setState(() => failure = error);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => HistoryScaffold(
    title: t(context, 'Requests', 'សំណើ'),
    onRefresh: () => load(reset: true),
    onScroll: scroll,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: Text(t(context, 'All', 'ទាំងអស់')),
            selected: status == null,
            onSelected: (_) {
              status = null;
              load(reset: true);
            },
          ),
          for (final s in RequestStatus.values)
            ChoiceChip(
              label: Text(requestLabel(context, s)),
              selected: status == s,
              onSelected: (_) {
                status = s;
                load(reset: true);
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (loading || opening)
        NoticeBanner(t(context, 'Loading requests…', 'កំពុងផ្ទុកសំណើ…')),
      if (failure != null)
        NoticeBanner(
          shopFailureMessage(context, failure!),
          tone: NoticeTone.error,
          action: TextButton(
            onPressed: () => load(reset: items.isEmpty),
            child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
          ),
        ),
      if (!loading && failure == null && items.isEmpty)
        NoticeBanner(
          t(
            context,
            'No requests match this filter.',
            'គ្មានសំណើត្រូវនឹងការច្រោះនេះទេ។',
          ),
        ),
      for (final r in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      shopAmount(r.amount, r.currency),
                      style: mText(context, 18, 26, weight: FontWeight.w600),
                    ),
                    StatusChip(r.status.name.toUpperCase()),
                  ],
                ),
                Text(r.reference, style: mText(context, 13, 20)),
                if (r.orderReference != null)
                  Text(r.orderReference!, style: mText(context, 13, 20)),
                Text(shortTime(r.createdAt), style: mText(context, 12, 18)),
                if (r.status == RequestStatus.waiting ||
                    r.status == RequestStatus.paid)
                  TextButton(
                    onPressed: opening ? null : () => open(r),
                    child: Text(
                      r.status == RequestStatus.waiting
                          ? t(
                              context,
                              'Open in Collect',
                              'បើកក្នុងផ្ទាំងទទួលប្រាក់',
                            )
                          : t(context, 'Open receipt', 'បើកបង្កាន់ដៃ'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (cursor != null)
        TextButton(
          onPressed: loading ? null : load,
          child: Text(t(context, 'Load more', 'ផ្ទុកបន្ថែម')),
        ),
    ],
  );
}
