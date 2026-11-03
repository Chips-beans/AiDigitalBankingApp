import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/platform/image_share.dart';
import '../collect/collect_view.dart';
import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';

void openReceipt(
  BuildContext context,
  MerchantCollectGateway gateway,
  String reference, {
  VoidCallback? onExpired,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReceiptPage(
        gateway: gateway,
        reference: reference,
        onExpired: onExpired,
      ),
    ),
  );
}

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    required this.gateway,
    required this.reference,
    this.onExpired,
    super.key,
  });
  final MerchantCollectGateway gateway;
  final String reference;
  final VoidCallback? onExpired;
  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final cardKey = GlobalKey();
  ShopReceipt? receipt;
  ShopFailure? failure;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failure = null;
      receipt = null;
    });
    try {
      final result = await widget.gateway.receipt(widget.reference);
      if (mounted) setState(() => receipt = result);
    } catch (e) {
      if (!mounted) return;
      final error = e is ShopFailure
          ? e
          : const ShopFailure('INVALID_RESPONSE');
      if (error.expired) widget.onExpired?.call();
      if (mounted) setState(() => failure = error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> copy() async {
    await Clipboard.setData(ClipboardData(text: widget.reference));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(context, 'Reference copied', 'បានចម្លងលេខយោង')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return HistoryScaffold(
      title: t(context, 'Receipt', 'បង្កាន់ដៃ'),
      children: [
        if (loading)
          NoticeBanner(t(context, 'Loading receipt…', 'កំពុងផ្ទុកបង្កាន់ដៃ…')),
        if (failure != null)
          NoticeBanner(
            shopFailureMessage(context, failure!),
            tone: NoticeTone.error,
            action: TextButton(
              onPressed: load,
              child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
            ),
          ),
        if (r != null) ...[
          RepaintBoundary(
            key: cardKey,
            child: ReceiptCard(receipt: r),
          ),
          const SizedBox(height: 16),
          ImageActions(
            cardKey: cardKey,
            name: 'kesor-receipt',
            receipt: true,
            text: receiptShareText(context, r),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: copy,
            icon: const Icon(Icons.copy_outlined),
            label: Text(t(context, 'Copy reference', 'ចម្លងលេខយោង')),
          ),
        ],
      ],
    );
  }
}

/// Only snapshot identity and masked accounts enter the share card/text.
String receiptShareText(BuildContext context, ShopReceipt r) => [
  r.storeName ?? 'Kesor Merchant',
  t(context, 'Payment received', 'បានទទួលការទូទាត់'),
  shopAmount(r.amount, r.currency),
  '${t(context, 'From', 'ពី')}: ${r.payerName} · ${r.payerAccount}',
  if (r.converted)
    '${t(context, 'Customer paid', 'អតិថិជនបានបង់')}: ${shopAmount(r.paidAmount, r.paidCurrency)}',
  if (r.converted && r.exchangeRate != null) receiptExchangeRate(context, r)!,
  if (r.orderReference != null)
    '${t(context, 'Order note', 'កំណត់ចំណាំ')}: ${r.orderReference}',
  '${t(context, 'Reference', 'លេខយោង')}: ${r.reference}',
  '${shortTime(r.paidAt)} (UTC+07:00)',
].join('\n');

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({required this.receipt, super.key});
  final ShopReceipt receipt;
  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppPalette.gold200,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  r.storeName ?? 'Kesor Merchant',
                  textAlign: TextAlign.center,
                  style: mText(
                    context,
                    18,
                    28,
                    color: Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(context, 'Payment received', 'បានទទួលការទូទាត់'),
                  textAlign: TextAlign.center,
                  style: mText(context, 14, 22, color: AppPalette.gold200),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shopAmount(r.amount, r.currency),
                    style: mText(
                      context,
                      32,
                      44,
                      color: Colors.white,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ReceiptLines(receipt: r, fullReference: true),
          ),
        ],
      ),
    );
  }
}

/// Shared Customer-style page shell for receipt, requests and reports.
class HistoryScaffold extends StatelessWidget {
  const HistoryScaffold({
    required this.title,
    required this.children,
    this.onRefresh,
    this.onScroll,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? onScroll;
  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      controller: onScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            CircleAction(
              tooltip: t(context, 'Back', 'ថយក្រោយ'),
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: mText(context, 20, 28, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: list,
          ),
        ),
      ),
    );
  }
}
