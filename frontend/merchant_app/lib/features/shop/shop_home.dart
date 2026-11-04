import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../collect/merchant_collect.dart';
import '../collect/wallet_page.dart' show ReceiptRow;
import 'merchant_shop.dart';
import 'shop_controller.dart';
import 'shop_widgets.dart';

class ShopHomeView extends StatelessWidget {
  const ShopHomeView({
    required this.controller,
    required this.fallbackName,
    required this.onCollect,
    required this.onSales,
    required this.onEditShop,
    this.onOpenWallet,
    this.onSeeSales,
    this.onReceipt,
    super.key,
  });
  final ShopController controller;
  final String fallbackName;
  final VoidCallback? onCollect;
  final VoidCallback onSales, onEditShop;
  final ValueChanged<ShopWallet>? onOpenWallet;
  final VoidCallback? onSeeSales;
  final ValueChanged<ShopReceipt>? onReceipt;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final profile = controller.profile, shop = controller.shop;
      final restricted = shop != null && !shop.active;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.loading) const LinearProgressIndicator(),
          if (restricted) ...[
            NoticeBanner(
              shop.status == 'PENDING'
                  ? t(
                      context,
                      'Your shop is in review. You can edit your details while you wait.',
                      'ហាងរបស់អ្នកកំពុងត្រូវបានពិនិត្យ។ អ្នកអាចកែព័ត៌មានខណៈពេលរង់ចាំ។',
                    )
                  : t(
                      context,
                      'Your shop is restricted. Collecting and transfers are paused; sales and receipts stay available.',
                      'ហាងរបស់អ្នកត្រូវបានកម្រិត។ ការទទួលប្រាក់ និងផ្ទេរត្រូវបានផ្អាក។ ការលក់ និងបង្កាន់ដៃនៅតែអាចប្រើបាន។',
                    ),
              tone: shop.status == 'PENDING'
                  ? NoticeTone.warning
                  : NoticeTone.error,
            ),
            const SizedBox(height: 24),
          ] else ...[
            TodayCard(dashboard: controller.dashboard),
            const SizedBox(height: 28),
          ],
          if (controller.failure != null) ...[
            NoticeBanner(
              shopFailureMessage(context, controller.failure!),
              tone: NoticeTone.error,
              action: TextButton(
                onPressed: controller.loading ? null : controller.refresh,
                child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SectionTitle(t(context, 'Business wallets', 'កាបូបអាជីវកម្ម')),
          if (profile != null && profile.wallets.isEmpty)
            NoticeBanner(
              t(
                context,
                'Your business wallets are not available yet.',
                'កាបូបអាជីវកម្មរបស់អ្នកមិនទាន់មាននៅឡើយ។',
              ),
            ),
          if (profile != null)
            for (final wallet in [
              ...profile.wallets,
            ]..sort((a, b) => a.currency.compareTo(b.currency)))
              WalletTile(
                wallet: wallet,
                grouped: true,
                onTap: onOpenWallet == null
                    ? null
                    : () => onOpenWallet!(wallet),
              ),
          if (restricted) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onEditShop,
                child: Text(t(context, 'Contact support', 'ទាក់ទងផ្នែកគាំទ្រ')),
              ),
            ),
          ] else if (shop != null) ...[
            const SizedBox(height: 28),
            SectionTitle(
              t(context, 'Recent payments', 'ការទូទាត់ថ្មីៗ'),
              trailing: onSeeSales == null
                  ? null
                  : TextButton(
                      onPressed: onSeeSales,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 24),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(t(context, 'See all', 'មើលទាំងអស់')),
                    ),
            ),
            if (controller.dashboard != null)
              RecentPayments(
                receipts: controller.dashboard!.recent,
                limit: 5,
                onReceipt: onReceipt,
              )
            else if (controller.failure == null)
              const LinearProgressIndicator(),
          ],
        ],
      );
    },
  );
}

/// Exact, independent currency totals; only presentation differs from the ledger.
class TodayCard extends StatelessWidget {
  const TodayCard({
    required this.dashboard,
    this.title,
    this.suppliedTotals,
    this.prominent = false,
    super.key,
  });
  final ShopDashboard? dashboard;
  final String? title;
  final List<CurrencyTotal>? suppliedTotals;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final totals = {
      for (final item
          in suppliedTotals ?? dashboard?.today ?? const <CurrencyTotal>[])
        item.currency: item,
    };
    final ready = dashboard != null || suppliedTotals != null;
    final muted = AppColors.of(context).disabledBackground;
    Widget lane(String currency) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountText(
          ready ? shopAmount(totals[currency]?.gross ?? '0', currency) : '—',
          key: ValueKey('today-$currency'),
          style: mText(
            context,
            title == null ? 28 : 24,
            title == null ? 38 : 32,
            weight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ready
              ? paymentCount(context, totals[currency]?.count ?? 0)
              : t(context, 'Payments', 'ការទូទាត់'),
          style: mText(context, 13, 18, color: muted),
        ),
      ],
    );
    return Column(
      key: const ValueKey('today-collections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title == null ||
            title !=
                t(
                  context,
                  'Filtered collections',
                  'ប្រាក់ទទួលបានតាមការច្រោះ',
                )) ...[
          Text(
            title ?? t(context, 'Today’s collections', 'ប្រាក់ទទួលបានថ្ងៃនេះ'),
            style: mText(context, 15, 24, color: muted),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, box) =>
              MediaQuery.textScalerOf(context).scale(26) > 34 ||
                  box.maxWidth < 300
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    lane('KHR'),
                    const SizedBox(height: 12),
                    lane('USD'),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lane('KHR')),
                    const SizedBox(width: 16),
                    Expanded(child: lane('USD')),
                  ],
                ),
        ),
      ],
    );
  }
}

class RecentPayments extends StatelessWidget {
  const RecentPayments({
    required this.receipts,
    this.limit,
    this.onReceipt,
    super.key,
  });
  final List<ShopReceipt> receipts;
  final int? limit;
  final ValueChanged<ShopReceipt>? onReceipt;
  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) {
      return NoticeBanner(
        t(
          context,
          'No payments yet. Show your QR from Collect to get paid.',
          'មិនទាន់មានការទូទាត់ទេ។ បង្ហាញ QR ពីផ្ទាំងទទួលប្រាក់ដើម្បីទទួលការទូទាត់។',
        ),
      );
    }
    final shown = limit == null ? receipts : receipts.take(limit!).toList();
    return Column(
      children: [
        for (final r in shown)
          ReceiptRow(r, onTap: onReceipt == null ? null : () => onReceipt!(r)),
      ],
    );
  }
}

class WalletTile extends StatelessWidget {
  const WalletTile({
    required this.wallet,
    this.onTap,
    this.grouped = false,
    super.key,
  });
  final ShopWallet wallet;
  final VoidCallback? onTap;
  final bool grouped;
  @override
  Widget build(BuildContext context) {
    final number = wallet.accountNumber;
    final masked =
        '•••• ${number.length > 4 ? number.substring(number.length - 4) : number}';
    final amount = AmountText(
      shopAmount(wallet.balance, wallet.currency),
      key: ValueKey('wallet-balance-${wallet.currency}'),
      style: mText(context, 15, 24, weight: FontWeight.w500),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          walletLabel(context, wallet.currency),
          style: mText(context, 15, 24),
        ),
        const SizedBox(height: 2),
        Text(
          masked,
          style: mText(
            context,
            13,
            18,
            color: AppColors.of(context).disabledBackground,
          ),
        ),
        if (wallet.status != 'ACTIVE') StatusChip(wallet.status),
      ],
    );
    return Material(
      key: ValueKey('wallet-${wallet.currency}'),
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('open-wallet-${wallet.currency}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.of(context).border),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final large =
                  MediaQuery.textScalerOf(context).scale(15) > 22 ||
                  box.maxWidth < 280;
              return Row(
                children: [
                  Expanded(
                    child: large
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              label,
                              const SizedBox(height: 8),
                              amount,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: label),
                              const SizedBox(width: 8),
                              amount,
                            ],
                          ),
                  ),
                  if (!grouped)
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
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    const QIcon('f7f78'),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ShopProfileCard extends StatelessWidget {
  const ShopProfileCard({
    required this.controller,
    required this.fallbackName,
    required this.onEdit,
    super.key,
  });
  final ShopController controller;
  final String fallbackName;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final shop = controller.shop;
      return InkWell(
        key: const ValueKey('open-shop-profile'),
        onTap: shop == null ? null : onEdit,
        child: Row(
          children: [
            ShopAvatar(
              name: shop?.storeName ?? fallbackName,
              logo: controller.logoBytes,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop?.storeName ?? fallbackName,
                    style: mText(context, 17, 23, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const QIcon('a542c', darkAdaptive: false),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${shop?.active == true ? t(context, 'Active', 'សកម្ម') : t(context, 'Restricted', 'បានកម្រិត')} · ${shop?.merchantId ?? ''}',
                          style: mText(
                            context,
                            13,
                            18,
                            color: AppColors.of(context).disabledBackground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
