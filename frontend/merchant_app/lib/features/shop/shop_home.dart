import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    this.onShopQr,
    this.onReports,
    this.onRequests,
    this.onOpenWallet,
    this.onSeeSales,
    this.onReceipt,
    super.key,
  });
  final ShopController controller;
  final String fallbackName;
  final VoidCallback? onCollect;
  final VoidCallback onSales, onEditShop;
  final VoidCallback? onShopQr, onReports, onRequests;
  final ValueChanged<ShopWallet>? onOpenWallet;
  final VoidCallback? onSeeSales;
  final ValueChanged<ShopReceipt>? onReceipt;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final profile = controller.profile, shop = controller.shop;
      final restricted = shop != null && !shop.active;
      if (restricted) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + 12,
                20,
                12,
              ),
              decoration: const BoxDecoration(
                color: AppPalette.navy500,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('merchant-menu'),
                    tooltip: t(context, 'Menu', 'ម៉ឺនុយ'),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        AppPalette.navy50,
                        BlendMode.srcIn,
                      ),
                      child: QIcon('56124', darkAdaptive: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shop.storeName,
                      style: mText(context, 18, 28, color: AppPalette.navy50),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    tone: NoticeTone.warning,
                  ),
                  const SizedBox(height: 20),
                  QGroup(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.storeName,
                                style: mText(
                                  context,
                                  18,
                                  28,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                shop.merchantId,
                                style: mText(context, 12, 20),
                              ),
                            ],
                          ),
                        ),
                        Flexible(child: StatusChip(shop.status)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionTitle(
                    t(context, 'Business wallets', 'កាបូបអាជីវកម្ម'),
                  ),
                  for (final w in profile?.wallets ?? <ShopWallet>[])
                    WalletTile(
                      wallet: w,
                      onTap: onOpenWallet == null
                          ? null
                          : () => onOpenWallet!(w),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: null,
                    child: Text(t(context, 'Collect payment', 'ទទួលការទូទាត់')),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onEditShop,
                    child: Text(
                      t(context, 'Contact support', 'ទាក់ទងផ្នែកគាំទ្រ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 20,
              20,
              24,
            ),
            decoration: const BoxDecoration(
              color: AppPalette.navy500,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -50,
                  top: -24,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: .3332,
                      child: SizedBox(
                        width: 126,
                        height: 126,
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/figma-change/0bd5e.svg',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('merchant-menu'),
                          tooltip: t(context, 'Menu', 'ម៉ឺនុយ'),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: const ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              AppPalette.navy50,
                              BlendMode.srcIn,
                            ),
                            child: QIcon('56124', darkAdaptive: false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    shop?.storeName ?? fallbackName,
                                    style: mText(
                                      context,
                                      18,
                                      28,
                                      weight: FontWeight.w500,
                                      color: AppPalette.navy50,
                                    ),
                                  ),
                                  if (shop != null) StatusChip(shop.status),
                                ],
                              ),
                              Text(
                                '${categoryFor(shop?.categoryCode)?.en ?? ''} · ${shop?.merchantId ?? ''}',
                                style: mText(
                                  context,
                                  12,
                                  20,
                                  color: AppPalette.navy200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TodayCard(dashboard: controller.dashboard, prominent: true),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!restricted) ...[
                  FilledButton(
                    onPressed: onCollect,
                    child: Text(t(context, 'Receive Payment', 'ទទួលការទូទាត់')),
                  ),
                  const SizedBox(height: 18),
                  QGroup(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final items = [
                          ('5e757', t(context, 'Sales', 'ការលក់'), onSales),
                          ('cc139', t(context, 'Shop QR', 'QR ហាង'), onShopQr),
                          (
                            '8b848',
                            t(context, 'Reports', 'របាយការណ៍'),
                            onReports,
                          ),
                          ('dc524', t(context, 'Requests', 'សំណើ'), onRequests),
                        ];
                        Widget tile(int i) => InkWell(
                          onTap: items[i].$3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: AppColors.of(context).surface,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: QIcon(items[i].$1),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  items[i].$2,
                                  textAlign: TextAlign.center,
                                  style: mText(context, 12, 20),
                                ),
                              ],
                            ),
                          ),
                        );
                        return MediaQuery.textScalerOf(context).scale(12) > 18
                            ? Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                children: [
                                  for (var i = 0; i < 4; i++)
                                    SizedBox(
                                      width: (box.maxWidth - 16) / 2,
                                      child: tile(i),
                                    ),
                                ],
                              )
                            : Row(
                                children: [
                                  for (var i = 0; i < 4; i++)
                                    Expanded(child: tile(i)),
                                ],
                              );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
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
                SectionTitle(
                  t(context, 'Business wallets', 'កាបូបអាជីវកម្ម'),
                  trailing: TextButton(
                    onPressed: controller.refresh,
                    child: Text(t(context, 'Refresh', 'ធ្វើបច្ចុប្បន្នភាព')),
                  ),
                ),
                if (profile != null && profile.wallets.isEmpty)
                  NoticeBanner(
                    t(
                      context,
                      'Your business wallets are not available yet.',
                      'កាបូបអាជីវកម្មរបស់អ្នកមិនទាន់មាននៅឡើយ។',
                    ),
                  ),
                if (profile != null)
                  LayoutBuilder(
                    builder: (context, box) {
                      final wallets = [...profile.wallets]
                        ..sort((a, b) => a.currency.compareTo(b.currency));
                      Widget tile(ShopWallet w) => WalletTile(
                        wallet: w,
                        grouped: true,
                        onTap: onOpenWallet == null
                            ? null
                            : () => onOpenWallet!(w),
                      );
                      return box.maxWidth < 340 ||
                              MediaQuery.textScalerOf(context).scale(15) > 21
                          ? Column(
                              children: [
                                for (final w in wallets)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: tile(w),
                                  ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < wallets.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 12),
                                  Expanded(child: tile(wallets[i])),
                                ],
                              ],
                            );
                    },
                  ),
                if (restricted) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onEditShop,
                      child: Text(
                        t(context, 'Contact support', 'ទាក់ទងផ្នែកគាំទ្រ'),
                      ),
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
            ),
          ),
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
    final muted = prominent
        ? AppPalette.navy200
        : AppColors.of(context).disabledBackground;
    Widget lane(String currency) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountText(
          ready ? shopAmount(totals[currency]?.gross ?? '0', currency) : '—',
          key: ValueKey('today-$currency'),
          style: mText(
            context,
            24,
            36,
            weight: FontWeight.w600,
            color: prominent ? AppPalette.navy50 : null,
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
    return QGroup(
      child: Column(
        children: [
          for (final r in shown)
            ReceiptRow(
              r,
              onTap: onReceipt == null ? null : () => onReceipt!(r),
            ),
        ],
      ),
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
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: number));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(context, 'Account number copied', 'បានចម្លងលេខគណនី'),
            ),
          ),
        );
      }
    }

    return Material(
      key: ValueKey('wallet-${wallet.currency}'),
      color: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('open-wallet-${wallet.currency}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: wallet.currency == 'KHR'
                          ? AppPalette.gold100
                          : AppPalette.navy50,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      wallet.currency,
                      style: mText(context, 10, 16, color: AppPalette.navy500),
                    ),
                  ),
                  const Spacer(),
                  if (onTap != null) const QIcon('f7f78'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                walletLabel(context, wallet.currency),
                style: mText(
                  context,
                  12,
                  20,
                  color: AppColors.of(context).disabledBackground,
                ),
              ),
              const SizedBox(height: 8),
              AmountText(
                shopAmount(wallet.balance, wallet.currency),
                key: ValueKey('wallet-balance-${wallet.currency}'),
                style: mText(context, 18, 28, weight: FontWeight.w600),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      masked,
                      style: mText(
                        context,
                        12,
                        20,
                        color: AppColors.of(context).disabledBackground,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t(context, 'Copy account number', 'ចម្លងលេខគណនី'),
                    icon: const QIcon('015d6'),
                    onPressed: copy,
                  ),
                ],
              ),
              if (wallet.status != 'ACTIVE') StatusChip(wallet.status),
            ],
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          decoration: const BoxDecoration(
            color: AppPalette.navy500,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Column(
            children: [
              ShopAvatar(
                name: shop?.storeName ?? fallbackName,
                logo: controller.logoBytes,
                size: 72,
                onDark: true,
              ),
              const SizedBox(height: 12),
              Text(
                shop?.storeName ?? fallbackName,
                textAlign: TextAlign.center,
                style: mText(
                  context,
                  20,
                  30,
                  weight: FontWeight.w500,
                  color: AppPalette.navy50,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    shop?.merchantId ?? '',
                    style: mText(context, 12, 20, color: AppPalette.navy200),
                  ),
                  if (shop != null) StatusChip(shop.status),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
