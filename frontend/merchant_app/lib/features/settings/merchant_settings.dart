import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_preferences.dart';
import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../feed/payment_banner.dart';
import '../shop/merchant_shop.dart';
import '../shop/shop_controller.dart';
import '../shop/shop_home.dart';

String themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
  ThemeMode.system => t(context, 'System theme', 'រូបរាងប្រព័ន្ធ'),
  ThemeMode.light => t(context, 'Light', 'ភ្លឺ'),
  ThemeMode.dark => t(context, 'Dark', 'ងងឹត'),
};

class MerchantMoreView extends StatelessWidget {
  const MerchantMoreView({
    required this.preferences,
    required this.controller,
    required this.fallbackName,
    required this.onProfile,
    required this.onSignOut,
    super.key,
  });
  final MerchantPreferences preferences;
  final ShopController? controller;
  final String fallbackName;
  final VoidCallback onProfile, onSignOut;
  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
    children: [
      if (controller != null)
        ShopProfileCard(
          controller: controller!,
          fallbackName: fallbackName,
          onEdit: onProfile,
        ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          label: t(context, 'Shop profile', 'ប្រវត្តិរូបហាង'),
          value: t(context, 'Edit', 'កែប្រែ'),
          asset: 'b8ce6',
          onTap: onProfile,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          key: const ValueKey('more-language'),
          label: t(context, 'Language', 'ភាសា'),
          asset: '72888',
          value: preferences.isKhmer ? 'ខ្មែរ' : 'English',
          onTap: () =>
              _open(context, MerchantAppearancePage(preferences: preferences)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          label: t(context, 'Appearance', 'រូបរាង'),
          asset: '00519',
          value: preferences.themeMode == ThemeMode.system
              ? t(context, 'System', 'ប្រព័ន្ធ')
              : themeLabel(context, preferences.themeMode),
          onTap: () =>
              _open(context, MerchantAppearancePage(preferences: preferences)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          key: const ValueKey('more-alerts'),
          label: t(context, 'Payment alerts', 'ការជូនដំណឹងការទូទាត់'),
          asset: '72592',
          value: preferences.alertSound || preferences.alertVibration
              ? t(context, 'On', 'បើក')
              : t(context, 'Off', 'បិទ'),
          onTap: () =>
              _open(context, MerchantAlertsPage(preferences: preferences)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          label: t(context, 'Help & support', 'ជំនួយ និងគាំទ្រ'),
          asset: 'e82c5',
          onTap: () => _open(context, const MerchantSupportPage()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: QMenuRow(
          key: const ValueKey('more-signout'),
          label: t(context, 'Sign out', 'ចាកចេញ'),
          asset: '64959',
          destructive: true,
          divider: false,
          onTap: () => showMerchantSignOut(context, onSignOut),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        t(
          context,
          'Signing out ends only your Merchant session.',
          'ការចាកចេញបញ្ចប់តែវគ្គប្រើប្រាស់ Merchant របស់អ្នក។',
        ),
        style: mText(
          context,
          13,
          18,
          color: AppColors.of(context).disabledBackground,
        ),
      ),
    ],
  );
}

Future<void> showMerchantSignOut(
  BuildContext context,
  VoidCallback signOut,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.of(context).background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (context) => SingleChildScrollView(
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const QStatusIcon('64959', tone: 'error'),
            const SizedBox(height: 12),
            Text(
              t(
                context,
                'Sign out of Kesor Merchant?',
                'ចាកចេញពី Kesor Merchant?',
              ),
              textAlign: TextAlign.center,
              style: mText(context, 20, 27, weight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                context,
                'Your shop and sales stay safe. Kesor Bank stays signed in.',
                'ហាង និងការលក់របស់អ្នកនៅតែមានសុវត្ថិភាព។ ធនាគារកេសរនៅតែចូលប្រើ។',
              ),
              textAlign: TextAlign.center,
              style: mText(
                context,
                15,
                24,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.semanticErrorMuted,
                foregroundColor: AppPalette.semanticError,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                signOut();
              },
              child: Text(t(context, 'Sign out', 'ចាកចេញ')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t(context, 'Cancel', 'បោះបង់')),
            ),
          ],
        ),
      ),
    ),
  ),
);

class MerchantAppearancePage extends StatelessWidget {
  const MerchantAppearancePage({required this.preferences, super.key});
  final MerchantPreferences preferences;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => QPage(
      title: t(context, 'Language & appearance', 'ភាសា និងរូបរាង'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(context, 'Language', 'ភាសា'),
            style: AppTextStyles.of(context).titleM,
          ),
          for (final lang in ['en', 'km'])
            _RadioRow(
              label: lang == 'en' ? 'English' : 'ខ្មែរ',
              selected: preferences.locale.languageCode == lang,
              onTap: () => preferences.setLanguage(lang),
            ),
          const SizedBox(height: 28),
          Text(
            t(context, 'Appearance', 'រូបរាង'),
            style: AppTextStyles.of(context).titleM,
          ),
          for (final mode in ThemeMode.values)
            _RadioRow(
              label: mode == ThemeMode.system
                  ? t(context, 'System', 'ប្រព័ន្ធ')
                  : themeLabel(context, mode),
              selected: preferences.themeMode == mode,
              onTap: () => preferences.setTheme(mode),
            ),
        ],
      ),
    ),
  );
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 53),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.of(context).background,
          border: Border(
            bottom: BorderSide(color: AppColors.of(context).border),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            if (selected)
              const QIcon('c9889')
            else
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.of(context).disabledBackground,
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class MerchantAlertsPage extends StatelessWidget {
  const MerchantAlertsPage({required this.preferences, super.key});
  final MerchantPreferences preferences;
  @override
  Widget build(BuildContext context) => QPage(
    title: t(context, 'Payment alerts', 'ការជូនដំណឹងការទូទាត់'),
    child: PaymentAlertSettings(preferences: preferences),
  );
}

class MerchantSupportPage extends StatelessWidget {
  const MerchantSupportPage({super.key});
  @override
  Widget build(BuildContext context) => QPage(
    title: t(context, 'Help & support', 'ជំនួយ និងគាំទ្រ'),
    child: const MerchantSupportCard(),
  );
}

class MerchantSupportCard extends StatelessWidget {
  const MerchantSupportCard({super.key});
  @override
  Widget build(BuildContext context) => QGroup(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(context, 'Support', 'ជំនួយ'),
                style: mText(
                  context,
                  13,
                  18,
                  color: AppColors.of(context).disabledBackground,
                ),
              ),
              const Text('reachsteav2@gmail.com'),
            ],
          ),
        ),
        IconButton(
          tooltip: t(context, 'Copy support address', 'ចម្លងអាសយដ្ឋានជំនួយ'),
          icon: const QIcon('4a0ca'),
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: 'reachsteav2@gmail.com'),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    t(
                      context,
                      'Support address copied',
                      'បានចម្លងអាសយដ្ឋានជំនួយ',
                    ),
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

class MerchantWalletsPage extends StatelessWidget {
  const MerchantWalletsPage({
    required this.controller,
    required this.onOpen,
    super.key,
  });
  final ShopController? controller;
  final ValueChanged<ShopWallet> onOpen;
  @override
  Widget build(BuildContext context) => QPage(
    title: t(context, 'Business wallets', 'កាបូបអាជីវកម្ម'),
    child: Column(
      children: [
        for (final wallet in controller?.profile?.wallets ?? <ShopWallet>[])
          WalletTile(wallet: wallet, onTap: () => onOpen(wallet)),
      ],
    ),
  );
}
