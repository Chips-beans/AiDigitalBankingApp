import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import '../sales/receipt_page.dart';
import '../transfer/owner_transfer_controller.dart';
import '../transfer/owner_transfer_page.dart';
import 'collect_view.dart' show shortTime;
import 'merchant_collect.dart';

/// One business wallet: balance, account number and read-only activity.
class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({
    required this.gateway,
    required this.wallet,
    this.onExpired,
    this.transfer,
    this.shopActive = false,
    super.key,
  });
  final MerchantCollectGateway gateway;
  final ShopWallet wallet;
  final VoidCallback? onExpired;

  /// Owner transfers (M8); null hides the action.
  final OwnerTransferController? transfer;
  final bool shopActive;
  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage> {
  late ShopWallet wallet = widget.wallet;
  final activity = <WalletActivity>[];
  int page = 0;
  bool hasMore = false, loading = false;
  ShopFailure? failure;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final result = await widget.gateway.wallet(
        widget.wallet.accountNumber,
        page: reset ? 0 : page + 1,
      );
      if (!mounted) return;
      setState(() {
        wallet = result.wallet;
        if (reset) activity.clear();
        activity.addAll(result.activity);
        page = result.page;
        hasMore = result.hasMore;
      });
    } on ShopFailure catch (e) {
      if (e.expired) widget.onExpired?.call();
      if (mounted) setState(() => failure = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openTransfer() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OwnerTransferPage(controller: widget.transfer!, wallet: wallet),
      ),
    );
    // The balance and activity may have changed while the owner approved in Kesor Bank.
    if (mounted) await _load(reset: true);
  }

  bool get _canTransfer {
    final transfer = widget.transfer;
    if (transfer == null) return false;
    // An open transfer can always be reopened to finish or cancel it.
    if (transfer.transfer != null) return true;
    return widget.shopActive &&
        wallet.status == 'ACTIVE' &&
        moneyUnits(wallet.balance, wallet.currency) > BigInt.zero;
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
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
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
                          walletLabel(context, wallet.currency),
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
                  NavyCard(
                    key: const ValueKey('wallet-detail-card'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(
                            context,
                            'Available balance',
                            'សមតុល្យដែលអាចប្រើបាន',
                          ),
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
                            shopAmount(wallet.balance, wallet.currency),
                            key: const ValueKey('wallet-detail-balance'),
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
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                wallet.accountNumber,
                                style: mText(
                                  context,
                                  14,
                                  22,
                                  weight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t(
                                context,
                                'Copy account number',
                                'ចម្លងលេខគណនី',
                              ),
                              color: Colors.white,
                              icon: const Icon(Icons.copy_rounded, size: 20),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: wallet.accountNumber),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        t(
                                          context,
                                          'Account number copied',
                                          'បានចម្លងលេខគណនី',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.transfer != null) ...[
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: widget.transfer!,
                      builder: (context, _) => FilledButton.icon(
                        key: const ValueKey('wallet-transfer'),
                        onPressed: _canTransfer ? _openTransfer : null,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: Text(
                          widget.transfer!.waiting
                              ? t(context, 'Continue transfer', 'បន្តការផ្ទេរ')
                              : t(
                                  context,
                                  'Transfer to my wallet',
                                  'ផ្ទេរទៅកាបូបខ្ញុំ',
                                ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SectionTitle(t(context, 'Activity', 'សកម្មភាព')),
                  const SizedBox(height: 8),
                  if (failure != null) ...[
                    NoticeBanner(
                      shopFailureMessage(context, failure!),
                      tone: NoticeTone.error,
                      action: TextButton(
                        onPressed: loading
                            ? null
                            : () => _load(reset: activity.isEmpty),
                        child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (loading && activity.isEmpty)
                    const LinearProgressIndicator(),
                  if (!loading && failure == null && activity.isEmpty)
                    NoticeBanner(
                      t(
                        context,
                        'No activity yet. QR payments to this wallet will appear here.',
                        'មិនទាន់មានសកម្មភាពទេ។ ការទូទាត់ QR ចូលកាបូបនេះនឹងបង្ហាញនៅទីនេះ។',
                      ),
                    ),
                  for (final item in activity)
                    ActivityRow(
                      item,
                      onTap: item.kind == 'QR_PAYMENT'
                          ? () => openReceipt(
                              context,
                              widget.gateway,
                              item.reference,
                              onExpired: widget.onExpired,
                            )
                          : null,
                    ),
                  if (hasMore)
                    TextButton(
                      onPressed: loading ? null : _load,
                      child: Text(t(context, 'Load more', 'ផ្ទុកបន្ថែម')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityRow extends StatelessWidget {
  const ActivityRow(this.item, {this.onTap, super.key});
  final WalletActivity item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (title, icon) = switch (item.kind) {
      'QR_PAYMENT' => (
        t(context, 'QR payment', 'ការទូទាត់ QR'),
        Icons.qr_code_2_rounded,
      ),
      'DEPOSIT' => (
        t(context, 'Deposit', 'ការដាក់ប្រាក់'),
        Icons.account_balance_rounded,
      ),
      'TRANSFER_OUT' => (
        t(context, 'Transfer out', 'ផ្ទេរចេញ'),
        Icons.north_east_rounded,
      ),
      _ => (t(context, 'Transfer in', 'ផ្ទេរចូល'), Icons.south_west_rounded),
    };
    final subtitle = [
      if (item.payerName != null) '${item.payerName} · ${item.payerAccount}',
      shortTime(item.createdAt),
    ].join('\n');
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.incoming
                  ? AppPalette.semanticSuccessMuted
                  : colors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: item.incoming
                  ? AppPalette.semanticSuccess
                  : merchantNavy(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: mText(context, 14, 22, weight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: mText(
                    context,
                    12,
                    18,
                    color: colors.disabledBackground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AmountText(
              '${item.incoming ? '+' : '−'}${shopAmount(item.amount, item.currency)}',
              textAlign: TextAlign.end,
              style: mText(
                context,
                14,
                22,
                weight: FontWeight.w600,
                color: item.incoming
                    ? AppPalette.semanticSuccess
                    : colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? row
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: row),
          );
  }
}

/// A confirmed payment row for Home and Sales.
class ReceiptRow extends StatelessWidget {
  const ReceiptRow(this.receipt, {this.onTap, super.key});
  final ShopReceipt receipt;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ActivityRow(
    onTap: onTap,
    WalletActivity(
      reference: receipt.reference,
      kind: 'QR_PAYMENT',
      incoming: true,
      amount: receipt.amount,
      currency: receipt.currency,
      payerName: receipt.payerName,
      payerAccount: receipt.payerAccount,
      createdAt: receipt.paidAt,
    ),
  );
}
