import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../collect/collect_view.dart' show amountError;
import '../collect/merchant_collect.dart' show moneyUnits;
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import 'owner_transfer.dart';
import 'owner_transfer_controller.dart';

/// Moves money from one business wallet to the owner's own wallet in Kesor Bank.
///
/// Nothing is chosen here but the amount: the destination is the owner's wallet, shown masked
/// once the server has created the transfer, and the owner approves it with the PIN in Kesor Bank.
class OwnerTransferPage extends StatefulWidget {
  const OwnerTransferPage({
    required this.controller,
    required this.wallet,
    super.key,
  });
  final OwnerTransferController controller;
  final ShopWallet wallet;
  @override
  State<OwnerTransferPage> createState() => _OwnerTransferPageState();
}

class _OwnerTransferPageState extends State<OwnerTransferPage> {
  final amount = TextEditingController();
  String? amountProblem;
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
    amount.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final currency = widget.wallet.currency;
    final problem = amountError(context, currency, amount.text);
    if (problem == null && _exceeds(amount.text.trim(), currency)) {
      setState(
        () => amountProblem = t(
          context,
          'More than the wallet balance',
          'លើសសមតុល្យកាបូប',
        ),
      );
      return;
    }
    setState(() => amountProblem = problem);
    if (problem != null) return;
    final ok = await widget.controller.create(
      sourceAccountNumber: widget.wallet.accountNumber,
      amount: amount.text.trim(),
    );
    if (ok && mounted) amount.clear();
  }

  bool _exceeds(String value, String currency) {
    try {
      return moneyUnits(_padded(value, currency), currency) >
          moneyUnits(widget.wallet.balance, currency);
    } catch (_) {
      return false;
    }
  }

  static String _padded(String value, String currency) {
    if (currency == 'KHR') return value;
    final parts = value.split('.');
    return '${parts.first}.${(parts.length > 1 ? parts[1] : '').padRight(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => ListView(
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
                          t(
                            context,
                            'Transfer to my wallet',
                            'ផ្ទេរទៅកាបូបខ្ញុំ',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mText(
                            context,
                            20,
                            28,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ..._body(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final controller = widget.controller;
    final transfer = controller.transfer;
    final colors = AppColors.of(context);
    if (transfer == null) return _form(context);
    final amountText = shopAmount(transfer.amount, transfer.currency);
    final summary = NavyCard(
      key: const ValueKey('transfer-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(context, 'Amount', 'ចំនួនទឹកប្រាក់'),
            style: mText(
              context,
              14,
              22,
              weight: FontWeight.w500,
              color: AppPalette.gold200,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: AmountText(
              amountText,
              key: const ValueKey('transfer-amount'),
              style: mText(
                context,
                30,
                40,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 8),
          _line(
            context,
            t(context, 'From business wallet', 'ពីកាបូបអាជីវកម្ម'),
            transfer.sourceAccountNumber,
          ),
          _line(
            context,
            t(context, 'To your wallet', 'ទៅកាបូបរបស់អ្នក'),
            transfer.destinationAccount,
            key: const ValueKey('transfer-destination'),
          ),
        ],
      ),
    );
    switch (transfer.status) {
      case TransferStatus.pending:
        final left = controller.remaining;
        return [
          summary,
          const SizedBox(height: 16),
          NoticeBanner(
            controller.reconnecting
                ? t(
                    context,
                    'Can’t reach the server. We’ll keep checking — approve in Kesor Bank if you haven’t yet.',
                    'មិនអាចភ្ជាប់ម៉ាស៊ីនមេ។ យើងនឹងបន្តពិនិត្យ — សូមអនុម័តក្នុងធនាគារកេសរ ប្រសិនបើមិនទាន់។',
                  )
                : t(
                    context,
                    'Waiting for your approval in Kesor Bank. Nothing moves until you approve with your PIN.',
                    'កំពុងរង់ចាំការអនុម័តរបស់អ្នកក្នុងធនាគារកេសរ។ គ្មានអ្វីផ្លាស់ទីទេ រហូតដល់អ្នកអនុម័តដោយ PIN។',
                  ),
            tone: controller.reconnecting
                ? NoticeTone.warning
                : NoticeTone.info,
          ),
          const SizedBox(height: 12),
          Text(
            '${t(context, 'Expires in', 'ផុតកំណត់ក្នុង')} ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
            key: const ValueKey('transfer-countdown'),
            textAlign: TextAlign.center,
            style: mText(context, 13, 20, color: colors.disabledBackground),
          ),
          if (controller.failure != null) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              transferFailureMessage(context, controller.failure!),
              tone: NoticeTone.error,
            ),
          ],
          const SizedBox(height: 16),
          if (controller.opening || controller.cancelling)
            const LinearProgressIndicator(),
          FilledButton.icon(
            key: const ValueKey('transfer-open'),
            onPressed: controller.opening || controller.cancelling
                ? null
                : controller.openApproval,
            icon: const Icon(Icons.open_in_new),
            label: Text(
              t(context, 'Continue in Kesor Bank', 'បន្តក្នុងធនាគារកេសរ'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('transfer-cancel'),
            onPressed: controller.cancelling || controller.opening
                ? null
                : controller.cancel,
            child: Text(t(context, 'Cancel transfer', 'បោះបង់ការផ្ទេរ')),
          ),
        ];
      case TransferStatus.completed:
        return [
          NoticeBanner(
            key: const ValueKey('transfer-completed'),
            t(
              context,
              'Transferred $amountText to your wallet in Kesor Bank.',
              'បានផ្ទេរ $amountText ទៅកាបូបរបស់អ្នកក្នុងធនាគារកេសរ។',
            ),
            tone: NoticeTone.success,
          ),
          const SizedBox(height: 16),
          summary,
          if (transfer.receiptReference != null) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(context, 'Reference', 'លេខយោង'),
                          style: mText(
                            context,
                            12,
                            18,
                            color: colors.disabledBackground,
                          ),
                        ),
                        SelectableText(
                          transfer.receiptReference!,
                          key: const ValueKey('transfer-reference'),
                          style: mText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t(context, 'Copy reference', 'ចម្លងលេខយោង'),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: transfer.receiptReference!),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ..._done(context),
        ];
      default:
        final (message, tone) = switch (transfer.status) {
          TransferStatus.denied => (
            t(
              context,
              'You declined this transfer in Kesor Bank. Nothing was moved.',
              'អ្នកបានបដិសេធការផ្ទេរនេះក្នុងធនាគារកេសរ។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
            ),
            NoticeTone.warning,
          ),
          TransferStatus.cancelled => (
            t(
              context,
              'This transfer was cancelled. Nothing was moved.',
              'ការផ្ទេរនេះត្រូវបានបោះបង់។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
            ),
            NoticeTone.warning,
          ),
          TransferStatus.expired => (
            t(
              context,
              'This transfer expired before it was approved. Nothing was moved.',
              'ការផ្ទេរនេះផុតកំណត់មុនពេលអនុម័ត។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
            ),
            NoticeTone.warning,
          ),
          _ => (
            transfer.failureCode == 'INSUFFICIENT_FUNDS'
                ? t(
                    context,
                    'The business wallet balance was not enough when you approved. Nothing was moved.',
                    'សមតុល្យកាបូបអាជីវកម្មមិនគ្រប់គ្រាន់ពេលអ្នកអនុម័ត។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
                  )
                : t(
                    context,
                    'The transfer could not be completed. Nothing was moved.',
                    'មិនអាចបញ្ចប់ការផ្ទេរបានទេ។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
                  ),
            NoticeTone.error,
          ),
        };
        return [
          NoticeBanner(
            message,
            key: ValueKey('transfer-${transfer.status.name}'),
            tone: tone,
          ),
          ..._done(context),
        ];
    }
  }

  List<Widget> _done(BuildContext context) => [
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('transfer-done'),
      onPressed: () async {
        final navigator = Navigator.of(context);
        await widget.controller.reset();
        if (mounted) navigator.pop();
      },
      child: Text(t(context, 'Done', 'រួចរាល់')),
    ),
  ];

  Widget _line(BuildContext context, String label, String value, {Key? key}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: mText(context, 13, 20, color: AppPalette.gold200),
              ),
            ),
            Flexible(
              child: Text(
                value,
                key: key,
                textAlign: TextAlign.end,
                style: mText(
                  context,
                  14,
                  22,
                  weight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );

  List<Widget> _form(BuildContext context) {
    final controller = widget.controller;
    final wallet = widget.wallet;
    return [
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              walletLabel(context, wallet.currency),
              style: mText(
                context,
                14,
                20,
                weight: FontWeight.w500,
                color: merchantNavy(context),
              ),
            ),
            Text(
              '${t(context, 'Available', 'អាចប្រើបាន')}: ${shopAmount(wallet.balance, wallet.currency)}',
              style: mText(
                context,
                13,
                20,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('transfer-amount-field'),
              controller: amount,
              keyboardType: TextInputType.numberWithOptions(
                decimal: wallet.currency == 'USD',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(wallet.currency == 'USD' ? r'[0-9.]' : r'[0-9]'),
                ),
                LengthLimitingTextInputFormatter(16),
              ],
              textAlign: TextAlign.center,
              style: mText(context, 32, 40, weight: FontWeight.w600),
              onChanged: (_) {
                if (amountProblem != null) setState(() => amountProblem = null);
              },
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                hintText: wallet.currency == 'USD' ? '0.00' : '0',
                errorText: amountProblem,
                prefixText: wallet.currency == 'USD' ? r'$ ' : null,
                suffixText: wallet.currency == 'KHR' ? ' ៛' : null,
              ),
            ),
          ],
        ),
      ),
      if (controller.failure != null) ...[
        const SizedBox(height: 12),
        NoticeBanner(
          controller.failure!.uncertain
              ? t(
                  context,
                  'We couldn’t confirm the transfer was created. Try again — the same request is reused.',
                  'យើងមិនអាចបញ្ជាក់ថាការផ្ទេរត្រូវបានបង្កើតទេ។ សូមព្យាយាមម្ដងទៀត — សំណើដដែលនឹងត្រូវប្រើឡើងវិញ។',
                )
              : transferFailureMessage(context, controller.failure!),
          tone: NoticeTone.error,
        ),
      ],
      const SizedBox(height: 16),
      if (controller.creating) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        key: const ValueKey('transfer-create'),
        onPressed: controller.creating ? null : _create,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: Text(t(context, 'Continue', 'បន្ត')),
      ),
      const SizedBox(height: 12),
      Text(
        t(
          context,
          'Money goes to your own wallet in Kesor Bank in the same currency. You approve it with your PIN in Kesor Bank.',
          'ប្រាក់ទៅកាបូបផ្ទាល់ខ្លួនរបស់អ្នកក្នុងធនាគារកេសរ ជារូបិយប័ណ្ណដូចគ្នា។ អ្នកអនុម័តដោយ PIN ក្នុងធនាគារកេសរ។',
        ),
        textAlign: TextAlign.center,
        style: mText(
          context,
          12,
          18,
          color: AppColors.of(context).disabledBackground,
        ),
      ),
    ];
  }
}

String transferFailureMessage(BuildContext context, ShopFailure failure) =>
    switch (failure.code) {
      'OWNER_WALLET_REQUIRED' => t(
        context,
        'Open a wallet in this currency in Kesor Bank first, then try again.',
        'សូមបើកកាបូបរូបិយប័ណ្ណនេះក្នុងធនាគារកេសរជាមុន រួចព្យាយាមម្ដងទៀត។',
      ),
      'INSUFFICIENT_FUNDS' => t(
        context,
        'The business wallet balance is not enough for this amount.',
        'សមតុល្យកាបូបអាជីវកម្មមិនគ្រប់គ្រាន់សម្រាប់ចំនួននេះ។',
      ),
      'OWNER_TRANSFER_IN_PROGRESS' => t(
        context,
        'You already have an open transfer. Finish it in Kesor Bank or wait for it to expire.',
        'អ្នកមានការផ្ទេរមួយកំពុងបើក។ សូមបញ្ចប់វាក្នុងធនាគារកេសរ ឬរង់ចាំឲ្យវាផុតកំណត់។',
      ),
      'MERCHANT_INACTIVE' => t(
        context,
        'This shop can’t transfer money right now. Contact support.',
        'ហាងនេះមិនអាចផ្ទេរប្រាក់បានឥឡូវនេះទេ។ សូមទាក់ទងផ្នែកគាំទ្រ។',
      ),
      'MERCHANT_TRANSFER_UNAVAILABLE' => t(
        context,
        'Transfers to your wallet are not available yet.',
        'ការផ្ទេរទៅកាបូបរបស់អ្នកមិនទាន់អាចប្រើបានទេ។',
      ),
      'PEER_MISSING' => t(
        context,
        'Install Kesor Bank on this device to approve the transfer.',
        'សូមដំឡើងធនាគារកេសរលើឧបករណ៍នេះ ដើម្បីអនុម័តការផ្ទេរ។',
      ),
      'HANDOFF_UNAVAILABLE' => t(
        context,
        'Kesor Bank could not be verified or opened.',
        'មិនអាចផ្ទៀងផ្ទាត់ ឬបើកធនាគារកេសរបានទេ។',
      ),
      _ => shopFailureMessage(context, failure),
    };
