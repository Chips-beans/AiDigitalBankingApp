import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/merchant_strings.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import 'collect_controller.dart';
import 'merchant_collect.dart';

// Same QR card palette as the Customer App's My QR.
const _qrSurface = Color(0xFF1F1F21);
const _qrMuted = Color(0xFFA1A1A6);
const _qrRed = AppPalette.semanticError;

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
  bool shopQr = false;
  String currency = 'KHR';
  final amount = TextEditingController();
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            key: const ValueKey('collect-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.dialpad_rounded),
                label: Text(t(context, 'Enter amount', 'បញ្ចូលចំនួន')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(t(context, 'Shop QR', 'QR ហាង')),
              ),
            ],
            selected: {shopQr},
            onSelectionChanged: (v) => setState(() => shopQr = v.first),
          ),
          const SizedBox(height: 16),
          _CurrencyPicker(
            value: currency,
            onChanged: (v) => setState(() {
              currency = v;
              amountProblem = null;
            }),
          ),
          const SizedBox(height: 16),
          if (shopQr)
            ShopQrPanel(
              key: ValueKey('shop-qr-$currency'),
              gateway: widget.gateway,
              currency: currency,
            )
          else ...[
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(context, 'Amount', 'ចំនួនទឹកប្រាក់'),
                    style: mText(
                      context,
                      14,
                      20,
                      weight: FontWeight.w500,
                      color: merchantNavy(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('collect-amount'),
                    controller: amount,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: currency == 'USD',
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(currency == 'USD' ? r'[0-9.]' : r'[0-9]'),
                      ),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    textAlign: TextAlign.center,
                    style: mText(context, 32, 40, weight: FontWeight.w600),
                    onChanged: (_) {
                      if (amountProblem != null) {
                        setState(() => amountProblem = null);
                      }
                    },
                    onSubmitted: (_) => _create(),
                    decoration: InputDecoration(
                      hintText: currency == 'USD' ? '0.00' : '0',
                      errorText: amountProblem,
                      prefixText: currency == 'USD' ? r'$ ' : null,
                      suffixText: currency == 'KHR' ? ' ៛' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('collect-order'),
                    controller: order,
                    maxLength: 50,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: t(
                        context,
                        'Order note (optional)',
                        'កំណត់ចំណាំការបញ្ជាទិញ (ស្រេចចិត្ត)',
                      ),
                      hintText: t(context, 'e.g. Table 4', 'ឧ. តុលេខ ៤'),
                      prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                ],
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
            const SizedBox(height: 16),
            if (collect.creating) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: const ValueKey('collect-create'),
              onPressed: collect.creating ? null : _create,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(t(context, 'Show payment QR', 'បង្ហាញ QR ទូទាត់')),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                context,
                'The QR is valid for a few minutes and can be paid once. You’ll see the payment here the moment it’s confirmed.',
                'QR មានសុពលភាពប៉ុន្មាននាទី ហើយអាចបង់បានតែម្ដង។ អ្នកនឹងឃើញការទូទាត់នៅទីនេះភ្លាមៗពេលត្រូវបានបញ្ជាក់។',
              ),
              textAlign: TextAlign.center,
              style: mText(
                context,
                12,
                18,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    key: const ValueKey('collect-currency'),
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: 'KHR', label: Text(t(context, 'KHR ៛', 'រៀល ៛'))),
      ButtonSegment(
        value: 'USD',
        label: Text(t(context, r'USD $', r'ដុល្លារ $')),
      ),
    ],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
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
    final collect = widget.controller;
    final request = collect.request!;
    final colors = AppColors.of(context);
    final amount = shopAmount(request.amount, request.currency);
    switch (request.status) {
      case RequestStatus.waiting:
        final left = collect.remaining;
        final total = request.expiresAt.difference(request.serverTime);
        final minutes = left.inMinutes, seconds = left.inSeconds % 60;
        return Column(
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
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
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
                              'កំពុងរង់ចាំការទូទាត់',
                            ),
                      style: mText(context, 14, 22, weight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    key: const ValueKey('request-countdown'),
                    style: mText(
                      context,
                      14,
                      22,
                      weight: FontWeight.w600,
                      color: left.inSeconds < 30
                          ? colors.error
                          : merchantNavy(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total.inSeconds <= 0
                    ? 0
                    : left.inSeconds / total.inSeconds,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${t(context, 'Reference', 'លេខយោង')} ${request.reference}',
              textAlign: TextAlign.center,
              style: mText(context, 12, 18, color: colors.disabledBackground),
            ),
            if (collect.failure != null) ...[
              const SizedBox(height: 12),
              NoticeBanner(
                shopFailureMessage(context, collect.failure!),
                tone: NoticeTone.error,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('request-cancel'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 52),
                foregroundColor: colors.error,
                side: BorderSide(color: colors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: collect.cancelling ? null : collect.cancel,
              icon: const Icon(Icons.close_rounded),
              label: Text(t(context, 'Cancel request', 'បោះបង់សំណើ')),
            ),
          ],
        );
      case RequestStatus.paid:
        final receipt = request.receipt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfaceCard(
              key: const ValueKey('request-paid'),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppPalette.semanticSuccessMuted,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 40,
                      color: AppPalette.semanticSuccess,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t(context, 'Payment received', 'បានទទួលការទូទាត់'),
                      style: mText(context, 18, 26, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      amount,
                      style: mText(
                        context,
                        32,
                        40,
                        weight: FontWeight.w700,
                        color: merchantNavy(context),
                      ),
                    ),
                  ),
                  if (receipt != null) ...[
                    const SizedBox(height: 16),
                    ReceiptLines(receipt: receipt),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('request-new'),
              onPressed: collect.reset,
              icon: const Icon(Icons.add_rounded),
              label: Text(t(context, 'New payment', 'ការទូទាត់ថ្មី')),
            ),
          ],
        );
      case RequestStatus.expired:
      case RequestStatus.cancelled:
        final expired = request.status == RequestStatus.expired;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfaceCard(
              key: const ValueKey('request-closed'),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Icon(
                    expired ? Icons.timer_off_outlined : Icons.cancel_outlined,
                    size: 48,
                    color: colors.disabledBackground,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    expired
                        ? t(context, 'QR expired', 'QR ផុតកំណត់')
                        : t(context, 'Request cancelled', 'សំណើត្រូវបានបោះបង់'),
                    style: mText(context, 18, 26, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$amount · ${t(context, 'No money was received', 'មិនបានទទួលប្រាក់ទេ')}',
                    textAlign: TextAlign.center,
                    style: mText(
                      context,
                      13,
                      20,
                      color: colors.disabledBackground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('request-new'),
              onPressed: collect.reset,
              icon: const Icon(Icons.add_rounded),
              label: Text(t(context, 'New payment', 'ការទូទាត់ថ្មី')),
            ),
          ],
        );
    }
  }
}

/// Payer, conversion, reference and time lines of a confirmed payment.
class ReceiptLines extends StatelessWidget {
  const ReceiptLines({required this.receipt, super.key});
  final ShopReceipt receipt;
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
          receipt.reference.length > 16
              ? '…${receipt.reference.substring(receipt.reference.length - 12)}'
              : receipt.reference,
        ),
        line(t(context, 'Time', 'ពេលវេលា'), shortTime(receipt.paidAt)),
      ],
    );
  }
}

String shortTime(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KesorQrCard(
            key: const ValueKey('shop-qr'),
            title: data.storeName,
            qrString: data.qrString,
            headline: walletLabel(context, data.currency),
            caption: data.accountNumber,
          ),
          const SizedBox(height: 12),
          Text(
            t(
              context,
              'Customers scan this QR and enter the amount themselves. Check each payment on Home before handing over goods.',
              'អតិថិជនស្កេន QR នេះ ហើយបញ្ចូលចំនួនដោយខ្លួនឯង។ សូមពិនិត្យការទូទាត់នីមួយៗនៅទំព័រដើម មុនប្រគល់ទំនិញ។',
            ),
            textAlign: TextAlign.center,
            style: mText(
              context,
              12,
              18,
              color: AppColors.of(context).disabledBackground,
            ),
          ),
        ],
      );
    },
  );
}

/// Dark QR card matching the Customer App, with dark modules on white for scanners.
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
  Widget build(BuildContext context) {
    TextStyle text(
      double size, {
      Color color = Colors.white,
      FontWeight? weight,
    }) => mText(
      context,
      size,
      size * 1.4,
      color: color,
      weight: weight ?? FontWeight.w400,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: _qrSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: _qrRed,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Text(
                    t(context, 'Kesor Merchant QR', 'QR អាជីវករកេសរ'),
                    style: text(17, weight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text(15, color: _qrMuted),
                  ),
                ),
                const Divider(height: 1, color: Color(0x22FFFFFF)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  child: Center(
                    child: Semantics(
                      image: true,
                      label: t(context, 'Payment QR', 'QR ទូទាត់'),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: LayoutBuilder(
                          builder: (context, box) => QrImageView(
                            data: qrString,
                            size: box.maxWidth.clamp(140, 220),
                            padding: const EdgeInsets.all(6),
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          headline,
                          key: const ValueKey('qr-headline'),
                          style: text(22, weight: FontWeight.w600),
                        ),
                      ),
                      if (caption != null && caption!.isNotEmpty)
                        Text(
                          caption!,
                          textAlign: TextAlign.center,
                          style: text(13, color: _qrMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
