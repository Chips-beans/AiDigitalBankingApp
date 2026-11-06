import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../collect/collect_view.dart' show amountError, shortTime;
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
  final amount = QMoneyController();
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

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    await widget.controller.reset();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller, transfer = controller.transfer;
      final wallet = widget.wallet, colors = AppColors.of(context);
      if (transfer == null) {
        return QPage(
          title: t(context, 'Transfer to my wallet', 'ផ្ទេរទៅកាបូបខ្ញុំ'),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.creating) const LinearProgressIndicator(),
              FilledButton(
                key: const ValueKey('transfer-create'),
                onPressed: controller.creating ? null : _create,
                child: Text(t(context, 'Continue', 'បន្ត')),
              ),
              QNumberPad(
                controller: amount,
                decimal: wallet.currency == 'USD',
                onChanged: () => setState(() => amountProblem = null),
              ),
              const SizedBox(height: 12),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              QGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t(context, 'From', 'ពី'),
                            style: mText(
                              context,
                              13,
                              18,
                              color: colors.disabledBackground,
                            ),
                          ),
                        ),
                        Flexible(
                          child: AmountText(
                            '${shopAmount(wallet.balance, wallet.currency)} ${t(context, 'available', 'អាចប្រើបាន')}',
                            textAlign: TextAlign.end,
                            style: mText(
                              context,
                              13,
                              18,
                              color: colors.disabledBackground,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      walletLabel(context, wallet.currency),
                      style: mText(context, 15, 24),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      t(context, 'To', 'ទៅ'),
                      style: mText(
                        context,
                        13,
                        18,
                        color: colors.disabledBackground,
                      ),
                    ),
                    Text(
                      t(
                        context,
                        'Your Kesor Bank wallet',
                        'កាបូបធនាគារកេសររបស់អ្នក',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                label: t(context, 'Amount', 'ចំនួនទឹកប្រាក់'),
                child: QAmountField(
                  controller: amount,
                  currency: wallet.currency,
                  fieldKey: const ValueKey('transfer-amount-field'),
                  error: amountProblem,
                  onChanged: (_) => setState(() => amountProblem = null),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  context,
                  'You’ll approve it with your PIN in Kesor Bank.',
                  'អ្នកនឹងអនុម័តដោយ PIN ក្នុងធនាគារកេសរ។',
                ),
                textAlign: TextAlign.center,
                style: mText(context, 13, 18, color: colors.disabledBackground),
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
            ],
          ),
        );
      }
      final waiting = transfer.waiting,
          completed = transfer.status == TransferStatus.completed;
      final amountText = shopAmount(transfer.amount, transfer.currency);
      final left = controller.remaining;
      final title = switch (transfer.status) {
        TransferStatus.pending => t(
          context,
          'Approve in Kesor Bank',
          'អនុម័តក្នុងធនាគារកេសរ',
        ),
        TransferStatus.completed => t(
          context,
          'Transfer completed',
          'ការផ្ទេរបានបញ្ចប់',
        ),
        TransferStatus.denied => t(
          context,
          'Transfer declined',
          'ការផ្ទេរត្រូវបានបដិសេធ',
        ),
        TransferStatus.cancelled => t(
          context,
          'Transfer cancelled',
          'ការផ្ទេរត្រូវបានបោះបង់',
        ),
        TransferStatus.expired => t(
          context,
          'Transfer expired',
          'ការផ្ទេរផុតកំណត់',
        ),
        TransferStatus.failed => t(
          context,
          'Transfer not completed',
          'ការផ្ទេរមិនបានបញ្ចប់',
        ),
      };
      return QPage(
        title: t(context, 'Transfer to my wallet', 'ផ្ទេរទៅកាបូបខ្ញុំ'),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (waiting) ...[
              if (controller.opening || controller.cancelling)
                const LinearProgressIndicator(),
              FilledButton(
                key: const ValueKey('transfer-open'),
                onPressed: controller.opening || controller.cancelling
                    ? null
                    : controller.openApproval,
                child: Text(
                  t(context, 'Continue in Kesor Bank', 'បន្តក្នុងធនាគារកេសរ'),
                  textAlign: TextAlign.center,
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
            ] else
              FilledButton(
                key: const ValueKey('transfer-done'),
                onPressed: _finish,
                child: Text(t(context, 'Done', 'រួចរាល់')),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QStatusIcon(
                completed
                    ? '1e3d7'
                    : waiting
                    ? 'e33d1'
                    : '00600',
                tone: completed
                    ? 'success'
                    : waiting
                    ? 'info'
                    : 'error',
              ),
              const SizedBox(height: 12),
              Text(
                title,
                key: ValueKey('transfer-${transfer.status.name}'),
                textAlign: TextAlign.center,
                style: mText(context, 20, 27, weight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              AmountText(
                amountText,
                key: const ValueKey('transfer-amount'),
                textAlign: TextAlign.center,
                style: mText(context, 28, 40, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (waiting) ...[
                Text(
                  t(
                    context,
                    'From your ${transfer.currency == 'USD' ? 'US Dollar' : 'Khmer Riel'} business wallet to your wallet ${transfer.destinationAccount}',
                    'ពីកាបូបអាជីវកម្មទៅកាបូបរបស់អ្នក ${transfer.destinationAccount}',
                  ),
                  key: const ValueKey('transfer-destination'),
                  textAlign: TextAlign.center,
                  style: mText(
                    context,
                    15,
                    24,
                    color: colors.disabledBackground,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${t(context, 'Expires in', 'ផុតកំណត់ក្នុង')} ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                  key: const ValueKey('transfer-countdown'),
                  textAlign: TextAlign.center,
                  style: mText(
                    context,
                    13,
                    18,
                    weight: FontWeight.w500,
                    color: merchantNavy(context),
                  ),
                ),
                const SizedBox(height: 16),
                QGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final step in [
                        t(
                          context,
                          '1  Kesor Bank opens on this phone',
                          '១  ធនាគារកេសរបើកលើទូរស័ព្ទនេះ',
                        ),
                        t(
                          context,
                          '2  Check the exact amount',
                          '២  ពិនិត្យចំនួនប្រាក់',
                        ),
                        t(
                          context,
                          '3  Approve with your PIN',
                          '៣  អនុម័តដោយ PIN របស់អ្នក',
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(step, style: mText(context, 14, 22)),
                        ),
                    ],
                  ),
                ),
                if (controller.reconnecting) ...[
                  const SizedBox(height: 12),
                  NoticeBanner(
                    t(
                      context,
                      'Can’t reach the server. We’ll keep checking — approve in Kesor Bank if you haven’t yet.',
                      'មិនអាចភ្ជាប់ម៉ាស៊ីនមេ។ យើងនឹងបន្តពិនិត្យ — សូមអនុម័តក្នុងធនាគារកេសរ ប្រសិនបើមិនទាន់។',
                    ),
                    tone: NoticeTone.warning,
                  ),
                ],
              ] else if (completed)
                QGroup(
                  key: const ValueKey('transfer-summary'),
                  child: Column(
                    children: [
                      QDetail(
                        t(context, 'From', 'ពី'),
                        '${transfer.currency} ${t(context, 'wallet', 'កាបូប')} •••• ${transfer.sourceAccountNumber.substring(transfer.sourceAccountNumber.length - 4)}',
                      ),
                      QDetail(
                        t(context, 'To', 'ទៅ'),
                        '${t(context, 'Your wallet', 'កាបូបរបស់អ្នក')} ${transfer.destinationAccount}',
                        valueKey: const ValueKey('transfer-destination'),
                      ),
                      if (transfer.receiptReference != null)
                        QDetail(
                          t(context, 'Reference', 'លេខយោង'),
                          transfer.receiptReference!,
                          valueKey: const ValueKey('transfer-reference'),
                        ),
                      if (transfer.completedAt != null)
                        QDetail(
                          t(context, 'Time', 'ពេលវេលា'),
                          shortTime(transfer.completedAt!),
                        ),
                    ],
                  ),
                )
              else
                Text(
                  switch (transfer.status) {
                    TransferStatus.denied => t(
                      context,
                      'You declined this transfer in Kesor Bank. Nothing was moved.',
                      'អ្នកបានបដិសេធការផ្ទេរនេះក្នុងធនាគារកេសរ។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
                    ),
                    TransferStatus.cancelled => t(
                      context,
                      'This transfer was cancelled. Nothing was moved.',
                      'ការផ្ទេរនេះត្រូវបានបោះបង់។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
                    ),
                    TransferStatus.expired => t(
                      context,
                      'This transfer expired before it was approved. Nothing was moved.',
                      'ការផ្ទេរនេះផុតកំណត់មុនពេលអនុម័ត។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
                    ),
                    _ =>
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
                  },
                  textAlign: TextAlign.center,
                  style: mText(
                    context,
                    15,
                    24,
                    color: colors.disabledBackground,
                  ),
                ),
              if (controller.failure != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(
                  transferFailureMessage(context, controller.failure!),
                  tone: NoticeTone.error,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
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
