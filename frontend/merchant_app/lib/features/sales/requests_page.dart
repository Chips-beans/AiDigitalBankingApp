import 'package:flutter/material.dart';

import '../../core/merchant_strings.dart';

import 'package:kesor_design_system/kesor_design_system.dart';

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
    title: t(context, 'Payment requests', 'សំណើទូទាត់'),
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
        InkWell(
          onTap:
              opening ||
                  !(r.status == RequestStatus.waiting ||
                      r.status == RequestStatus.paid)
              ? null
              : () => open(r),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.of(context).background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AmountText(
                        shopAmount(r.amount, r.currency),
                        style: mText(context, 15, 24, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${r.reference} · ${shortTime(r.createdAt)}',
                        style: mText(
                          context,
                          13,
                          18,
                          color: AppColors.of(context).disabledBackground,
                        ),
                      ),
                      if (r.status == RequestStatus.paid ||
                          r.status == RequestStatus.waiting)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            r.status == RequestStatus.paid
                                ? t(context, 'Open receipt ›', 'បើកបង្កាន់ដៃ ›')
                                : t(
                                    context,
                                    'Open in Collect ›',
                                    'បើកក្នុងផ្ទាំងទទួលប្រាក់ ›',
                                  ),
                            style: mText(
                              context,
                              12,
                              20,
                              weight: FontWeight.w500,
                              color: merchantNavy(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: StatusChip(r.status.name.toUpperCase())),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      Text(
        t(
          context,
          'Unpaid requests never count as sales.',
          'សំណើដែលមិនទាន់បង់ប្រាក់មិនរាប់ជាការលក់ទេ។',
        ),
        style: mText(
          context,
          13,
          18,
          color: AppColors.of(context).disabledBackground,
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
