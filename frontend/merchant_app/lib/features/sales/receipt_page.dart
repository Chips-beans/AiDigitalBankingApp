import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
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
    return QPage(
      title: t(context, 'Receipt', 'បង្កាន់ដៃ'),
      footer: r == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ImageActions(
                  cardKey: cardKey,
                  name: 'kesor-receipt',
                  receipt: true,
                  text: receiptShareText(context, r),
                ),
                TextButton(
                  onPressed: copy,
                  child: Text(t(context, 'Copy reference', 'ចម្លងលេខយោង')),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            NoticeBanner(
              t(context, 'Loading receipt…', 'កំពុងផ្ទុកបង្កាន់ដៃ…'),
            ),
          if (failure != null)
            NoticeBanner(
              shopFailureMessage(context, failure!),
              tone: NoticeTone.error,
              action: TextButton(
                onPressed: load,
                child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
              ),
            ),
          if (r != null)
            RepaintBoundary(
              key: cardKey,
              child: ReceiptCard(receipt: r),
            ),
        ],
      ),
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
    return ColoredBox(
      color: AppColors.of(context).background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: QIcon('923a9', darkAdaptive: false)),
          const SizedBox(height: 12),
          Text(
            r.storeName ?? 'Kesor Merchant',
            textAlign: TextAlign.center,
            style: mText(context, 17, 23, weight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            t(context, 'Payment received', 'បានទទួលការទូទាត់'),
            textAlign: TextAlign.center,
            style: mText(
              context,
              15,
              24,
              color: AppColors.of(context).disabledBackground,
            ),
          ),
          const SizedBox(height: 4),
          AmountText(
            shopAmount(r.amount, r.currency),
            textAlign: TextAlign.center,
            style: mText(context, 36, 48, weight: FontWeight.w300),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          QDetail(
            t(context, 'From', 'ពី'),
            '${r.payerName} · ${r.payerAccount}',
          ),
          if (r.converted)
            QDetail(
              t(context, 'Customer paid', 'អតិថិជនបានបង់'),
              shopAmount(r.paidAmount, r.paidCurrency),
            ),
          if (r.converted && r.exchangeRate != null)
            QDetail(
              t(context, 'Exchange rate', 'អត្រាប្ដូរប្រាក់'),
              receiptExchangeRate(context, r)!,
            ),
          if (r.orderReference != null)
            QDetail(t(context, 'Order note', 'កំណត់ចំណាំ'), r.orderReference!),
          if (r.requestReference != null)
            QDetail(t(context, 'Request', 'សំណើ'), r.requestReference!),
          QDetail(t(context, 'Transaction', 'ប្រតិបត្តិការ'), r.reference),
          if (r.walletAccountNumber != null)
            QDetail(
              t(context, 'Wallet', 'កាបូប'),
              '${r.currency} •••• ${r.walletAccountNumber!.substring(r.walletAccountNumber!.length - 4)}',
            ),
          QDetail(
            t(context, 'Time (UTC+7)', 'ពេលវេលា (UTC+7)'),
            shortTime(r.paidAt),
          ),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: children,
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }
    return Scaffold(
      appBar: AppBar(leading: const QBack(), title: Text(title)),
      body: SafeArea(
        top: false,
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
