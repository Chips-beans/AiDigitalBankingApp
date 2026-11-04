import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_labels.dart';
import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/figma_presentation.dart';
import 'figma_wallet_card.dart';
import '../../../shared/widgets/kesor_layout.dart';

import '../accounts_controller.dart';

/// Wallet & Accounts, opened from the Home balance card.
///
/// Presentation only: every action is delegated to the accounts shell, which
/// keeps ownership of navigation, refresh and transfer recovery.
class WalletAccountsScreen extends StatelessWidget {
  const WalletAccountsScreen({
    required this.model,
    required this.greetingName,
    required this.onBack,
    required this.onProfile,
    required this.onRefresh,
    required this.onTransfer,
    required this.onMyQr,
    required this.onOpenAccounts,
    required this.onDetails,
    required this.onActivity,
    required this.bottomBar,
    this.notices = const [],
    this.savedTransfer,
    this.balanceVisible = true,
    this.onBalanceVisibilityChanged,
    super.key,
  });

  final AccountsController model;
  final String greetingName;
  final VoidCallback onBack, onProfile, onTransfer, onMyQr;
  final VoidCallback onDetails, onActivity;

  /// Null while opening is not allowed (setup pending or an uncertain request).
  final VoidCallback? onOpenAccounts;
  final Future<void> Function() onRefresh;
  final Widget bottomBar;

  /// Error and recovery panels owned by the shell.
  final List<Widget> notices;

  /// Notice text for a saved transfer that must be reviewed first.
  final String? savedTransfer;
  final bool balanceVisible;
  final ValueChanged<bool>? onBalanceVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accounts = [...model.accounts]
      ..sort(
        (a, b) => (a.currency == 'KHR' ? 0 : 1).compareTo(
          b.currency == 'KHR' ? 0 : 1,
        ),
      );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KesorLayout.frameWidth,
              ),
              child: RefreshIndicator(
                onRefresh: onRefresh,
                child: SingleChildScrollView(
                  key: const PageStorageKey('wallet-accounts-scroll'),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CustomerPageHeader(
                        title: tr(context, 'Wallet', 'កាបូប'),
                        onBack: onBack,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr(
                                context,
                                'Your money, in the currency you need.',
                                'ប្រាក់របស់អ្នក ជារូបិយប័ណ្ណដែលអ្នកត្រូវការ។',
                              ),
                              style: customerText(
                                context,
                                12,
                                20,
                                color: colors.disabledBackground,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr(
                                      context,
                                      'All wallet accounts',
                                      'គណនីកាបូបទាំងអស់',
                                    ),
                                    style: customerText(
                                      context,
                                      14,
                                      22,
                                      weight: FontWeight.w600,
                                      color: customerNavy(context),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary50,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    tr(
                                      context,
                                      '${accounts.length + 1} wallets',
                                      '${accounts.length + 1} កាបូប',
                                    ),
                                    style: customerText(
                                      context,
                                      12,
                                      20,
                                      color: colors.primary700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (model.loading) const LinearProgressIndicator(),
                      for (final notice in notices)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: notice,
                        ),
                      if (savedTransfer != null)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: NoticePanel(savedTransfer!),
                        ),
                      if (model.notice != null)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: NoticePanel(model.notice!),
                        ),
                      for (final account in accounts)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: FigmaWalletCard(
                            account: account,
                            balanceVisible: balanceVisible,
                            onTap: () async {
                              await model.select(account);
                              if (context.mounted) onDetails();
                            },
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: FigmaWalletCard(balanceVisible: balanceVisible),
                      ),
                      if (accounts.isEmpty && !model.loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: FilledButton(
                            onPressed: onOpenAccounts,
                            child: Text(tx(context, 'Open accounts')),
                          ),
                        ),
                      if (model.hasMore)
                        TextButton(
                          onPressed: model.loadingMore ? null : model.loadMore,
                          child: Text(tx(context, 'Load more accounts')),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CustomerDesignIcon(
                              '29889',
                              size: 18,
                              color: customerNavy(context),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr(
                                  context,
                                  'Each wallet holds its own currency. Balances are shown separately in KHR and USD.',
                                  'កាបូបនីមួយៗរក្សារូបិយប័ណ្ណរបស់ខ្លួន។ សមតុល្យត្រូវបានបង្ហាញដាច់ដោយឡែកជា KHR និង USD។',
                                ),
                                style: customerText(
                                  context,
                                  12,
                                  20,
                                  color: colors.disabledBackground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (accounts.isNotEmpty)
                            TextButton(
                              onPressed: onOpenAccounts,
                              child: Text(tx(context, 'Open accounts')),
                            ),
                          Tooltip(
                            message: tx(context, 'Profile'),
                            child: TextButton(
                              onPressed: onProfile,
                              child: Text(tx(context, 'Profile')),
                            ),
                          ),
                          TextButton(
                            onPressed: onActivity,
                            child: Text(tx(context, 'View recent activity')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `$1,234.50` for USD and `12,000 ៛` for KHR, from integer minor units.
String walletAmount(BigInt minor, String currency) {
  String group(String digits) =>
      digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  if (currency != 'USD') return '${group(minor.toString())} ៛';
  final cents = (minor % BigInt.from(100)).toString().padLeft(2, '0');
  return '\$${group((minor ~/ BigInt.from(100)).toString())}.$cents';
}

String walletName(BuildContext context, String currency) =>
    tx(context, currency == 'KHR' ? 'Khmer Riel Wallet' : 'US Dollar Wallet');

String accountTypeName(BuildContext context, String type) => switch (type) {
  'SAVINGS' => tr(context, 'Savings', 'សន្សំ'),
  'CHECKING' => tr(context, 'Checking', 'ចរន្ត'),
  'PAYROLL' => tr(context, 'Payroll', 'បើកប្រាក់ខែ'),
  _ => type,
};
