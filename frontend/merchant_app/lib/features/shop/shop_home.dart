import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import 'merchant_shop.dart';
import 'shop_controller.dart';
import 'shop_widgets.dart';

/// Home tab: shop identity card, review/restriction notices and both wallets.
class ShopHomeView extends StatelessWidget {
  const ShopHomeView({
    required this.controller,
    required this.fallbackName,
    required this.onCollect,
    required this.onSales,
    required this.onEditShop,
    super.key,
  });
  final ShopController controller;
  final String fallbackName;
  final VoidCallback? onCollect;
  final VoidCallback onSales;
  final VoidCallback onEditShop;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final profile = controller.profile;
      final shop = profile?.shop;
      final colors = AppColors.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.loading && profile == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
          _ShopCard(
            name: shop?.storeName ?? fallbackName,
            controller: controller,
            shop: shop,
          ),
          if (shop?.status == 'PENDING') ...[
            const SizedBox(height: 12),
            NoticeBanner(
              t(
                context,
                'Your shop is in review. You can edit your details while you wait.',
                'ហាងរបស់អ្នកកំពុងត្រូវបានពិនិត្យ។ អ្នកអាចកែព័ត៌មានខណៈពេលរង់ចាំ។',
              ),
              tone: NoticeTone.warning,
            ),
          ] else if (shop != null && !shop.active) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              t(
                context,
                'Shop access is restricted. Contact support for help with your shop status.',
                'ការចូលប្រើហាងត្រូវបានកម្រិត។ សូមទាក់ទងផ្នែកគាំទ្រអំពីស្ថានភាពហាង។',
              ),
              tone: NoticeTone.error,
            ),
          ],
          if (controller.failure != null && profile == null) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              shopFailureMessage(context, controller.failure!),
              tone: NoticeTone.error,
              action: TextButton(
                onPressed: controller.loading ? null : controller.refresh,
                child: Text(t(context, 'Try again', 'ព្យាយាមម្ដងទៀត')),
              ),
            ),
          ],
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ActionTile(
                    icon: Icons.qr_code_2_rounded,
                    label: t(context, 'Collect', 'ទទួលប្រាក់'),
                    highlighted: true,
                    onTap: onCollect,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ActionTile(
                    icon: Icons.receipt_long_rounded,
                    label: t(context, 'Sales', 'ការលក់'),
                    onTap: onSales,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ActionTile(
                    icon: Icons.edit_outlined,
                    label: t(context, 'Edit shop', 'កែហាង'),
                    onTap: shop == null ? null : onEditShop,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionTitle(
            t(context, 'Business wallets', 'កាបូបអាជីវកម្ម'),
            trailing: IconButton(
              tooltip: t(context, 'Refresh', 'ធ្វើបច្ចុប្បន្នភាព'),
              onPressed: controller.loading ? null : controller.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: 8),
          if (profile != null && profile.wallets.isEmpty)
            NoticeBanner(
              t(
                context,
                'Your business wallets are not available yet.',
                'កាបូបអាជីវកម្មរបស់អ្នកមិនទាន់មាននៅឡើយ។',
              ),
            ),
          for (final wallet in profile?.wallets ?? const <ShopWallet>[]) ...[
            WalletTile(wallet: wallet),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Text(
            t(
              context,
              'Business wallets are separate from your personal Kesor Bank wallets.',
              'កាបូបអាជីវកម្មដាច់ដោយឡែកពីកាបូបផ្ទាល់ខ្លួនក្នុងធនាគារកេសរ។',
            ),
            style: mText(context, 12, 18, color: colors.disabledBackground),
          ),
        ],
      );
    },
  );
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.name,
    required this.controller,
    required this.shop,
  });
  final String name;
  final ShopController controller;
  final ShopDetails? shop;
  @override
  Widget build(BuildContext context) {
    final khmer = MerchantStrings.isKhmer(context);
    final category = categoryFor(shop?.categoryCode);
    return NavyCard(
      key: const ValueKey('shop-identity-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ShopAvatar(
                name: name,
                logo: controller.logoBytes,
                size: 60,
                onDark: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mText(
                        context,
                        20,
                        28,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (category != null)
                      Text(
                        khmer ? category.km : category.en,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mText(
                          context,
                          13,
                          20,
                          color: AppPalette.gold200,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (shop != null) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white24),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(context, 'Merchant ID', 'លេខសម្គាល់ហាង'),
                        style: mText(context, 12, 18, color: Colors.white70),
                      ),
                      // The code is copied by staff; keep it on one line.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          shop!.merchantId,
                          key: const ValueKey('shop-merchant-id'),
                          maxLines: 1,
                          softWrap: false,
                          style: mText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(shop!.status, onDark: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class WalletTile extends StatelessWidget {
  const WalletTile({required this.wallet, super.key});
  final ShopWallet wallet;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SurfaceCard(
      key: ValueKey('wallet-${wallet.currency}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          CurrencyBadge(wallet.currency),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletLabel(context, wallet.currency),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: mText(context, 14, 22, weight: FontWeight.w600),
                ),
                Text(
                  wallet.accountNumber,
                  style: mText(
                    context,
                    12,
                    18,
                    color: colors.disabledBackground,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    shopAmount(wallet.balance, wallet.currency),
                    key: ValueKey('wallet-balance-${wallet.currency}'),
                    maxLines: 1,
                    softWrap: false,
                    style: mText(
                      context,
                      20,
                      28,
                      weight: FontWeight.w600,
                      color: merchantNavy(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (wallet.status != 'ACTIVE') ...[
            StatusChip(wallet.status),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: t(context, 'Copy account number', 'ចម្លងលេខគណនី'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: wallet.accountNumber),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      t(context, 'Account number copied', 'បានចម្លងលេខគណនី'),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Compact shop identity row for the More tab.
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
      final colors = AppColors.of(context);
      return Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('open-shop-profile'),
          onTap: shop == null ? null : onEdit,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: mText(context, 16, 24, weight: FontWeight.w600),
                      ),
                      Text(
                        t(context, 'Shop profile', 'ប្រវត្តិរូបហាង'),
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
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      );
    },
  );
}
