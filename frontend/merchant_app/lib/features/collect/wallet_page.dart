import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_widgets.dart';
import 'collect_view.dart' show shortTime;
import 'merchant_collect.dart';

/// One business wallet: balance, account number and read-only activity.
class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({
    required this.gateway,
    required this.wallet,
    this.onExpired,
    super.key,
  });
  final MerchantCollectGateway gateway;
  final ShopWallet wallet;
  final VoidCallback? onExpired;
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
                          child: Text(
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
                  for (final item in activity) ActivityRow(item),
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
  const ActivityRow(this.item, {super.key});
  final WalletActivity item;
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
    return Padding(
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
          Text(
            '${item.incoming ? '+' : '−'}${shopAmount(item.amount, item.currency)}',
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
        ],
      ),
    );
  }
}

/// A confirmed payment row for Home and Sales.
class ReceiptRow extends StatelessWidget {
  const ReceiptRow(this.receipt, {super.key});
  final ShopReceipt receipt;
  @override
  Widget build(BuildContext context) => ActivityRow(
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
