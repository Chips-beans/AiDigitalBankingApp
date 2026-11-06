import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../../core/platform/image_share.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import '../sales/receipt_page.dart';
import 'collect_controller.dart';
import 'merchant_collect.dart';

/// Validates amount text for the currency's precision (USD 2 places, KHR whole).
String? amountError(BuildContext context, String currency, String raw) {
  final value = raw.trim();
  final pattern = currency == 'KHR'
      ? RegExp(r'^[0-9]{1,13}$')
      : RegExp(r'^[0-9]{1,13}(\.[0-9]{1,2})?$');
  if (!pattern.hasMatch(value) || RegExp(r'^0*(\.0*)?$').hasMatch(value)) {
    return currency == 'KHR'
        ? t(context, 'Enter a whole riel amount', 'បញ្ចូលចំនួនរៀលគត់')
        : t(context, 'Enter an amount like 2.50', 'បញ្ចូលចំនួនដូចជា 2.50');
  }
  return null;
}

/// Collect tab: a fixed-amount request, or the shop's reusable QR.
class CollectView extends StatefulWidget {
  const CollectView({
    required this.controller,
    required this.gateway,
    required this.storeName,
    required this.active,
    super.key,
  });
  final CollectController controller;
  final MerchantCollectGateway gateway;
  final String storeName;
  final bool active;
  @override
  State<CollectView> createState() => _CollectViewState();
}

class _CollectViewState extends State<CollectView> {
  String currency = 'KHR';
  final amount = QMoneyController();
  final order = TextEditingController();
  String? amountProblem;

  @override
  void dispose() {
    amount.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final problem = amountError(context, currency, amount.text);
    setState(() => amountProblem = problem);
    if (problem != null) return;
    final ok = await widget.controller.create(
      currency: currency,
      amount: amount.text.trim(),
      orderReference: order.text.trim().isEmpty ? null : order.text.trim(),
    );
    if (ok && mounted) {
      amount.clear();
      order.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final collect = widget.controller;
      if (!widget.active) {
        return NoticeBanner(
          t(
            context,
            'This shop can’t collect payments right now. Contact support.',
            'ហាងនេះមិនអាចទទួលការទូទាត់បានទេឥឡូវនេះ។ សូមទាក់ទងផ្នែកគាំទ្រ។',
          ),
          tone: NoticeTone.error,
        );
      }
      if (collect.request != null) {
        return RequestView(controller: collect, storeName: widget.storeName);
      }
      return QStage(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (collect.creating) const LinearProgressIndicator(),
            QNumberPad(
              controller: amount,
              decimal: currency == 'USD',
              onChanged: () => setState(() => amountProblem = null),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('collect-create'),
              onPressed: collect.creating ? null : _create,
              child: ValueListenableBuilder(
                valueListenable: amount,
                builder: (context, _, child) => Text(
                  '${t(context, 'Show QR', 'បង្ហាញ QR')}${amount.text.isEmpty ? '' : ' · ${shopAmount(amount.text, currency)}'}',
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QSegments<bool>(
              key: const ValueKey('collect-mode'),
              values: const [false, true],
              labels: [
                t(context, 'Enter amount', 'បញ្ចូលចំនួន'),
                t(context, 'Shop QR', 'QR ហាង'),
              ],
              value: false,
              onChanged: (mode) {
                if (mode) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MerchantShopQrPage(gateway: widget.gateway),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: QSegments<String>(
                key: const ValueKey('collect-currency'),
                values: const ['KHR', 'USD'],
                labels: const ['KHR', 'USD'],
                compact: false,
                value: currency,
                onChanged: (v) => setState(() {
                  currency = v;
                  amount.clear();
                  amountProblem = null;
                }),
              ),
            ),
            const SizedBox(height: 8),
            ...[
              Text(
                t(context, 'Amount to receive', 'ចំនួនប្រាក់ទទួល'),
                textAlign: TextAlign.center,
                style: mText(
                  context,
                  12,
                  20,
                  color: AppColors.of(context).disabledBackground,
                ),
              ),
              Semantics(
                label: t(context, 'Amount', 'ចំនួនទឹកប្រាក់'),
                child: QAmountField(
                  controller: amount,
                  currency: currency,
                  fieldKey: const ValueKey('collect-amount'),
                  error: amountProblem,
                  onChanged: (_) => setState(() => amountProblem = null),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                label: t(
                  context,
                  'Order note (optional)',
                  'កំណត់ចំណាំការបញ្ជាទិញ (ស្រេចចិត្ត)',
                ),
                child: TextField(
                  key: const ValueKey('collect-order'),
                  controller: order,
                  maxLength: 50,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: t(
                      context,
                      'Add an order note',
                      'បន្ថែមកំណត់ចំណាំ',
                    ),
                    counterText: '',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(14),
                      child: QIcon('1409f'),
                    ),
                  ),
                ),
              ),
              if (collect.failure != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(
                  collect.failure!.uncertain
                      ? t(
                          context,
                          'We couldn’t confirm the QR was created. Try again — the same request is reused.',
                          'យើងមិនអាចបញ្ជាក់ថា QR ត្រូវបានបង្កើតទេ។ សូមព្យាយាមម្ដងទៀត — សំណើដដែលនឹងត្រូវប្រើឡើងវិញ។',
                        )
                      : shopFailureMessage(context, collect.failure!),
                  tone: NoticeTone.error,
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

/// The live request: QR and countdown while waiting, then the server's outcome.
class RequestView extends StatefulWidget {
  const RequestView({
    required this.controller,
    required this.storeName,
    super.key,
  });
  final CollectController controller;
  final String storeName;
  @override
  State<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<RequestView> {
  Timer? tick;

  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.waiting) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collect = widget.controller, request = widget.controller.request!;
    final amount = shopAmount(request.amount, request.currency);
    final colors = AppColors.of(context);
    Widget newPayment() => FilledButton(
      key: const ValueKey('request-new'),
      onPressed: collect.reset,
      child: Text(t(context, 'New payment', 'ការទូទាត់ថ្មី')),
    );
    switch (request.status) {
      case RequestStatus.waiting:
        final left = collect.remaining,
            total = request.expiresAt.difference(request.serverTime);
        return QStage(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          footer: OutlinedButton(
            key: const ValueKey('request-cancel'),
            onPressed: collect.cancelling ? null : collect.cancel,
            child: Text(t(context, 'Cancel request', 'បោះបង់សំណើ')),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KesorQrCard(
                key: const ValueKey('request-qr'),
                title: widget.storeName,
                qrString: request.qrString ?? '',
                headline: amount,
                caption: request.orderReference,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      collect.reconnecting
                          ? t(
                              context,
                              'Reconnecting… the payment can still arrive',
                              'កំពុងភ្ជាប់ឡើងវិញ… ការទូទាត់នៅតែអាចមកដល់',
                            )
                          : t(
                              context,
                              'Waiting for payment',
                              'កំពុងរង់ចាំអតិថិជន',
                            ),
                      key: const ValueKey('request-payment-status'),
                      style: mText(
                        context,
                        15,
                        24,
                        color: colors.disabledBackground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                    key: const ValueKey('request-countdown'),
                    style: mText(
                      context,
                      15,
                      24,
                      weight: FontWeight.w500,
                      color: merchantNavy(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: total.inSeconds <= 0
                    ? 0
                    : (left.inSeconds / total.inSeconds).clamp(0, 1),
                minHeight: 6,
                color: AppPalette.gold500,
                backgroundColor: colors.surface,
              ),
              const SizedBox(height: 12),
              Text(
                '${t(context, 'Reference', 'លេខយោង')} ${request.reference}',
                textAlign: TextAlign.center,
                style: mText(context, 13, 18, color: colors.disabledBackground),
              ),
              if (collect.failure != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(
                  shopFailureMessage(context, collect.failure!),
                  tone: NoticeTone.error,
                ),
              ],
            ],
          ),
        );
      case RequestStatus.paid:
        final receipt = request.receipt;
        return QStage(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          footer: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (receipt != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => openReceipt(
                      context,
                      collect.gateway,
                      receipt.reference,
                      onExpired: collect.onExpired,
                    ),
                    child: Text(
                      t(context, 'View receipt', 'មើលបង្កាន់ដៃ'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: newPayment()),
            ],
          ),
          child: Column(
            key: const ValueKey('request-paid'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const QStatusIcon('1e3d7', tone: 'success'),
              const SizedBox(height: 12),
              Text(
                t(context, 'Payment received', 'បានទទួលការទូទាត់'),
                textAlign: TextAlign.center,
                style: mText(context, 20, 27, weight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              AmountText(
                amount,
                textAlign: TextAlign.center,
                style: mText(context, 28, 40, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (receipt != null)
                QGroup(
                  child: Column(
                    children: [
                      QDetail(
                        t(context, 'From', 'ពី'),
                        '${receipt.payerName} · ${receipt.payerAccount}',
                      ),
                      if (receipt.converted)
                        QDetail(
                          t(context, 'Customer paid', 'អតិថិជនបានបង់'),
                          shopAmount(receipt.paidAmount, receipt.paidCurrency),
                        ),
                      if (receipt.converted && receipt.exchangeRate != null)
                        QDetail(
                          t(context, 'Exchange rate', 'អត្រាប្ដូរប្រាក់'),
                          receiptExchangeRate(context, receipt)!,
                        ),
                      QDetail(
                        t(context, 'Time', 'ពេលវេលា'),
                        shortTime(receipt.paidAt),
                      ),
                      if (receipt.orderReference != null)
                        QDetail(
                          t(context, 'Order note', 'កំណត់ចំណាំ'),
                          receipt.orderReference!,
                        ),
                      QDetail(
                        t(context, 'Reference', 'លេខយោង'),
                        receipt.reference,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case RequestStatus.expired:
      case RequestStatus.cancelled:
        final expired = request.status == RequestStatus.expired;
        return QStage(
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
          footer: newPayment(),
          child: Column(
            key: const ValueKey('request-closed'),
            children: [
              const QStatusIcon('08603'),
              const SizedBox(height: 12),
              Text(
                expired
                    ? t(context, 'Request expired', 'សំណើផុតកំណត់')
                    : t(context, 'Request cancelled', 'សំណើត្រូវបានបោះបង់'),
                textAlign: TextAlign.center,
                style: mText(context, 20, 27, weight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              AmountText(
                '$amount · ${t(context, 'No money was received', 'មិនបានទទួលប្រាក់ទេ')}',
                textAlign: TextAlign.center,
                style: mText(context, 15, 24, color: colors.disabledBackground),
              ),
            ],
          ),
        );
    }
  }
}

/// Payer, conversion, reference and time lines of a confirmed payment.
class ReceiptLines extends StatelessWidget {
  const ReceiptLines({
    required this.receipt,
    this.fullReference = false,
    super.key,
  });
  final ShopReceipt receipt;
  final bool fullReference;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: mText(context, 13, 20, color: colors.disabledBackground),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: mText(context, 13, 20, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        Container(height: 1, color: colors.border),
        const SizedBox(height: 8),
        line(
          t(context, 'From', 'ពី'),
          '${receipt.payerName} · ${receipt.payerAccount}',
        ),
        if (receipt.converted)
          line(
            t(context, 'Customer paid', 'អតិថិជនបានបង់'),
            shopAmount(receipt.paidAmount, receipt.paidCurrency),
          ),
        if (receipt.orderReference != null)
          line(t(context, 'Order note', 'កំណត់ចំណាំ'), receipt.orderReference!),
        line(
          t(context, 'Transaction', 'ប្រតិបត្តិការ'),
          !fullReference && receipt.reference.length > 16
              ? '…${receipt.reference.substring(receipt.reference.length - 12)}'
              : receipt.reference,
        ),
        line(t(context, 'Time', 'ពេលវេលា'), shortTime(receipt.paidAt)),
        if (fullReference && receipt.requestReference != null)
          line(
            t(context, 'Request reference', 'លេខយោងសំណើ'),
            receipt.requestReference!,
          ),
        if (fullReference && receipt.exchangeRate != null && receipt.converted)
          line(
            t(context, 'Exchange rate', 'អត្រាប្ដូរប្រាក់'),
            receiptExchangeRate(context, receipt)!,
          ),
        if (fullReference && receipt.walletAccountNumber != null)
          line(
            t(context, 'Receiving wallet', 'កាបូបទទួល'),
            '${receipt.currency} · •••• ${receipt.walletAccountNumber!.substring(receipt.walletAccountNumber!.length - 4)}',
          ),
        if (fullReference) Text('UTC+07:00', style: mText(context, 12, 18)),
      ],
    );
  }
}

String shortTime(DateTime at) {
  final local = businessTime(at);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

/// The server's canonical rate is KHR per USD in both conversion directions.
/// Format its exact decimal text; never derive a rate from payment amounts.
String? receiptExchangeRate(BuildContext context, ShopReceipt receipt) {
  if (!receipt.converted || receipt.exchangeRate == null) return null;
  final parts = receipt.exchangeRate!.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 1
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  final rate = '$whole${fraction.isEmpty ? '' : '.$fraction'}';
  return '${t(context, '1 USD', '1 ដុល្លារ')} = $rate ៛';
}

/// The shop's reusable QR for one currency; customers type the amount.
class ShopQrPanel extends StatefulWidget {
  const ShopQrPanel({required this.gateway, required this.currency, super.key});
  final MerchantCollectGateway gateway;
  final String currency;
  @override
  State<ShopQrPanel> createState() => _ShopQrPanelState();
}

class _ShopQrPanelState extends State<ShopQrPanel> {
  late Future<ShopQr> qr = widget.gateway.shopQr(widget.currency);
  final cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) => FutureBuilder<ShopQr>(
    future: qr,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final error = snapshot.error;
        return NoticeBanner(
          error is ShopFailure
              ? shopFailureMessage(context, error)
              : t(
                  context,
                  'The shop QR could not be loaded.',
                  'មិនអាចផ្ទុក QR ហាងបានទេ។',
                ),
          tone: NoticeTone.error,
          action: TextButton(
            onPressed: () =>
                setState(() => qr = widget.gateway.shopQr(widget.currency)),
            child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
          ),
        );
      }
      final data = snapshot.data;
      if (data == null) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return QStage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(
              key: cardKey,
              child: KesorQrCard(
                key: const ValueKey('shop-qr'),
                title: data.storeName,
                qrString: data.qrString,
                headline: '',
                caption:
                    '${walletLabel(context, data.currency)} · •••• ${data.accountNumber.substring(data.accountNumber.length > 4 ? data.accountNumber.length - 4 : 0)}',
              ),
            ),
            const SizedBox(height: 20),
            ImageActions(
              cardKey: cardKey,
              name: 'kesor-shop-qr',
              text: '${data.storeName}\n${data.currency}',
            ),
            const SizedBox(height: 20),
            Text(
              t(
                context,
                'Check each payment on Home before handing over goods.',
                'សូមពិនិត្យការទូទាត់នីមួយៗនៅទំព័រដើម មុនប្រគល់ទំនិញ។',
              ),
              textAlign: TextAlign.center,
              style: mText(
                context,
                13,
                18,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The QR payload is always live server data, never the Figma sample code.
class KesorQrCard extends StatelessWidget {
  const KesorQrCard({
    required this.title,
    required this.qrString,
    required this.headline,
    this.caption,
    super.key,
  });
  final String title, qrString, headline;
  final String? caption;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 313),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppPalette.neutralLightBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: const Color(0xffd50032),
              child: Text(
                'Kesor Merchant QR',
                style: mText(
                  context,
                  14,
                  22,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: mText(
                      context,
                      15,
                      24,
                      weight: FontWeight.w500,
                      color: AppPalette.neutralLightForegroundAndBase,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    image: true,
                    label: t(context, 'Payment QR', 'QR ទូទាត់'),
                    child: LayoutBuilder(
                      builder: (context, box) => Center(
                        child: QrImageView(
                          data: qrString,
                          size: box.maxWidth.clamp(0, 200),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppPalette.navy700,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppPalette.navy700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (headline.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    AmountText(
                      headline,
                      key: const ValueKey('qr-headline'),
                      textAlign: TextAlign.center,
                      style: mText(
                        context,
                        24,
                        36,
                        weight: FontWeight.w600,
                        color: AppPalette.neutralLightForegroundAndBase,
                      ),
                    ),
                  ],
                  if (caption?.isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    Text(
                      caption!,
                      textAlign: TextAlign.center,
                      style: mText(
                        context,
                        12,
                        20,
                        color: AppPalette.neutralLightDisabledBackground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MerchantShopQrPage extends StatefulWidget {
  const MerchantShopQrPage({required this.gateway, super.key});
  final MerchantCollectGateway gateway;
  @override
  State<MerchantShopQrPage> createState() => _MerchantShopQrPageState();
}

class _MerchantShopQrPageState extends State<MerchantShopQrPage> {
  String currency = 'KHR';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: merchantAppBar(
      context,
      leadingWidth: 52,
      leading: const QBack(),
      title: Text(t(context, 'Shop QR', 'QR ហាង')),
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: QSegments(
                  values: const ['KHR', 'USD'],
                  labels: const ['KHR', 'USD'],
                  compact: false,
                  value: currency,
                  onChanged: (v) => setState(() => currency = v),
                ),
              ),
              Expanded(
                child: ShopQrPanel(
                  key: ValueKey(currency),
                  gateway: widget.gateway,
                  currency: currency,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
