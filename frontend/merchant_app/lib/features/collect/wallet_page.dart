import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const QBack(),
      title: Text(walletLabel(context, wallet.currency)),
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Column(
                  key: const ValueKey('wallet-detail-card'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(context, 'Available balance', 'សមតុល្យដែលអាចប្រើបាន'),
                      style: mText(
                        context,
                        15,
                        24,
                        color: AppColors.of(context).disabledBackground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AmountText(
                      shopAmount(wallet.balance, wallet.currency),
                      style: mText(context, 36, 48, weight: FontWeight.w300),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            wallet.accountNumber,
                            style: mText(context, 15, 24),
                          ),
                        ),
                        IconButton(
                          tooltip: t(
                            context,
                            'Copy account number',
                            'ចម្លងលេខគណនី',
                          ),
                          icon: const QIcon('015d6'),
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
                if (widget.transfer != null) ...[
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: widget.transfer!,
                    builder: (context, _) => FilledButton(
                      key: const ValueKey('wallet-transfer'),
                      onPressed: _canTransfer ? _openTransfer : null,
                      child: Text(
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
                const SizedBox(height: 32),
                SectionTitle(t(context, 'Activity', 'សកម្មភាព')),
                const SizedBox(height: 4),
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

class ActivityRow extends StatelessWidget {
  const ActivityRow(this.item, {this.onTap, super.key});
  final WalletActivity item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final title = item.payerName != null
        ? '${item.payerName} · ${item.payerAccount}'
        : item.kind == 'TRANSFER_OUT'
        ? t(context, 'To your wallet', 'ទៅកាបូបរបស់អ្នក')
        : t(context, 'Transfer in', 'ផ្ទេរចូល');
    final kind = item.kind == 'QR_PAYMENT'
        ? t(context, 'QR payment', 'ការទូទាត់ QR')
        : t(context, 'Owner transfer', 'ការផ្ទេររបស់ម្ចាស់');
    return _PaymentRow(
      title: title,
      detail: '$kind · ${shortTime(item.createdAt).split(' ').last}',
      amount:
          '${item.incoming ? '+' : '−'}${shopAmount(item.amount, item.currency)}',
      onTap: onTap,
    );
  }
}

class ReceiptRow extends StatelessWidget {
  const ReceiptRow(this.receipt, {this.onTap, super.key});
  final ShopReceipt receipt;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => _PaymentRow(
    title: '${receipt.payerName} · ${receipt.payerAccount}',
    detail: [
      shortTime(receipt.paidAt).split(' ').last,
      if (receipt.orderReference != null) receipt.orderReference!,
    ].join(' · '),
    amount: '+${shopAmount(receipt.amount, receipt.currency)}',
    onTap: onTap,
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.title,
    required this.detail,
    required this.amount,
    this.onTap,
  });
  final String title, detail, amount;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.of(context).border),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final amountPainter = TextPainter(
              text: TextSpan(
                text: amount,
                style: mText(context, 15, 24, weight: FontWeight.w500),
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final large =
                amountPainter.width > box.maxWidth * .45 ||
                MediaQuery.textScalerOf(context).scale(15) > 22 ||
                box.maxWidth < 280;
            final money = AmountText(
              amount,
              textAlign: large ? TextAlign.start : TextAlign.end,
              style: mText(context, 15, 24, weight: FontWeight.w500),
            );
            final words = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: large ? null : 1,
                  overflow: large ? null : TextOverflow.ellipsis,
                  style: mText(context, 15, 24),
                ),
                Text(
                  detail,
                  maxLines: large ? null : 1,
                  overflow: large ? null : TextOverflow.ellipsis,
                  style: mText(
                    context,
                    13,
                    17,
                    color: AppColors.of(context).disabledBackground,
                  ),
                ),
                if (large) ...[const SizedBox(height: 4), money],
              ],
            );
            return Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.of(context).surface,
                  ),
                  child: Text(
                    title.characters.first.toUpperCase(),
                    style: mText(
                      context,
                      14,
                      18,
                      weight: FontWeight.w500,
                      color: merchantNavy(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: words),
                if (!large) ...[const SizedBox(width: 12), money],
              ],
            );
          },
        ),
      ),
    ),
  );
}
