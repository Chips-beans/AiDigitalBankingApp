import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_labels.dart';
import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../home/presentation/kesor_home_screen.dart' show KesorBalanceMotif;
import '../../transactions/presentation/transfer_flow_design.dart';
import '../account_gateway.dart';
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = math.max(24.0, MediaQuery.paddingOf(context).bottom);
    final selected = model.selected;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: colors.background,
          ),
      child: Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    onRefresh: onRefresh,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('wallet-accounts-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        MediaQuery.paddingOf(context).top + 8,
                        20,
                        bottomInset + KesorBottomBar.height(context) + 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context),
                          const SizedBox(height: 16),
                          _summaryCard(context),
                          const SizedBox(height: 16),
                          _actions(context),
                          for (final notice in [
                            ...notices,
                            if (savedTransfer != null)
                              NoticePanel(savedTransfer!),
                            if (model.notice != null)
                              NoticePanel(model.notice!),
                            if (!model.loading &&
                                model.accounts.isEmpty &&
                                model.listError == null)
                              NoticePanel(
                                tr(
                                  context,
                                  'You have no accounts yet. Open accounts to get started.',
                                  'អ្នកមិនទាន់មានគណនីទេ។ សូមបើកគណនីដើម្បីចាប់ផ្ដើម។',
                                ),
                              ),
                          ]) ...[const SizedBox(height: 12), notice],
                          const SizedBox(height: 24),
                          _sectionTitle(
                            context,
                            tr(context, 'Your wallets', 'កាបូបរបស់អ្នក'),
                            trailing: model.accounts.isEmpty
                                ? null
                                : '${model.accounts.length}',
                          ),
                          const SizedBox(height: 12),
                          if (model.loading)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(
                                semanticsLabel: 'Refreshing accounts',
                              ),
                            ),
                          for (final account in model.accounts) ...[
                            _WalletTile(
                              account: account,
                              selected: selected?.number == account.number,
                              balanceVisible: balanceVisible,
                              onTap: () => model.select(account),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (model.hasMore)
                            TextButton(
                              onPressed: model.loading || model.loadingMore
                                  ? null
                                  : model.loadMore,
                              child: Text(
                                model.loadingMore
                                    ? 'Loading more…'
                                    : tx(context, 'Load more accounts'),
                              ),
                            ),
                          if (selected != null) ...[
                            const SizedBox(height: 14),
                            _sectionTitle(
                              context,
                              tr(
                                context,
                                'Selected wallet',
                                'កាបូបដែលបានជ្រើស',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _selectedCard(context, selected),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: bottomInset,
                  child: bottomBar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        _CircleButton(
          tooltip: tx(context, 'Back'),
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'Wallet & Accounts', 'កាបូប និងគណនី'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: transferText(context, 20, 28, weight: FontWeight.w600),
              ),
              if (greetingName.isNotEmpty)
                Text(
                  tr(context, 'Hello, $greetingName', 'សួស្ដី $greetingName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: transferText(
                    context,
                    13,
                    20,
                    color: colors.disabledBackground,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _CircleButton(
          tooltip: 'Refresh accounts',
          icon: Icons.refresh_rounded,
          onPressed: model.loading ? null : onRefresh,
        ),
        const SizedBox(width: 8),
        _CircleButton(
          tooltip: 'Profile',
          icon: Icons.person_outline_rounded,
          onPressed: onProfile,
        ),
      ],
    );
  }

  /// Navy card with the per-currency totals of the loaded accounts.
  Widget _summaryCard(BuildContext context) {
    BigInt total(String currency) => model.accounts
        .where((a) => a.currency == currency)
        .fold(BigInt.zero, (sum, a) => sum + a.balance.minorUnits);
    final updated = model.accountsUpdatedAt;
    final count = model.accounts.length;
    return ClipRRect(
      key: const ValueKey('wallet-summary-card'),
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppPalette.navy400,
              AppPalette.navy500,
              AppPalette.navy700,
            ],
            stops: [0, .45, 1],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              right: -60,
              top: -24,
              child: ExcludeSemantics(
                child: Opacity(opacity: .28, child: KesorBalanceMotif()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, 'Total balance', 'សមតុល្យសរុប'),
                          style: transferText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w500,
                            color: AppPalette.gold200,
                          ),
                        ),
                      ),
                      if (onBalanceVisibilityChanged != null)
                        IconButton(
                          tooltip: balanceVisible
                              ? 'Hide balance'
                              : 'Show balance',
                          onPressed: () =>
                              onBalanceVisibilityChanged!(!balanceVisible),
                          color: Colors.white,
                          icon: Icon(
                            balanceVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        )
                      else
                        const SizedBox(height: 48),
                    ],
                  ),
                  _totalLine(
                    context,
                    'KHR',
                    tr(context, 'Khmer Riel', 'ប្រាក់រៀល'),
                    total('KHR'),
                  ),
                  const SizedBox(height: 12),
                  _totalLine(
                    context,
                    'USD',
                    tr(context, 'US Dollar', 'ប្រាក់ដុល្លារ'),
                    total('USD'),
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    [
                      tr(
                        context,
                        '$count ${count == 1 ? 'wallet' : 'wallets'}',
                        'កាបូប $count',
                      ),
                      if (updated != null)
                        '${tr(context, 'Updated', 'ធ្វើបច្ចុប្បន្នភាព')} ${_time(updated)}',
                      if (model.listError != null)
                        tr(
                          context,
                          'Refresh failed',
                          'ធ្វើបច្ចុប្បន្នភាពបរាជ័យ',
                        ),
                    ].join('  ·  '),
                    style: transferText(context, 12, 18, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalLine(
    BuildContext context,
    String currency,
    String label,
    BigInt minor,
  ) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: TransferCurrencyFlag(currency, small: true),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: transferText(context, 12, 18, color: Colors.white70),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                balanceVisible
                    ? walletAmount(minor, currency)
                    : currency == 'USD'
                    ? r'$••••'
                    : '•••• ៛',
                key: ValueKey('wallet-total-$currency'),
                maxLines: 1,
                softWrap: false,
                style: transferText(
                  context,
                  24,
                  32,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _actions(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.send_rounded,
            label: savedTransfer == null
                ? tx(context, 'Transfer')
                : tr(context, 'Review saved transfer', 'ពិនិត្យការផ្ទេរ'),
            highlighted: true,
            onTap: onTransfer,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.qr_code_2_rounded,
            label: tx(context, 'My QR'),
            onTap: onMyQr,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.add_rounded,
            label: tx(context, 'Open accounts'),
            onTap: onOpenAccounts,
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(
    BuildContext context,
    String title, {
    String? trailing,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: transferText(
            context,
            16,
            24,
            weight: FontWeight.w600,
            color: transferNavy(context),
          ),
        ),
      ),
      if (trailing != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.of(context).accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            trailing,
            style: transferText(context, 12, 18, weight: FontWeight.w600),
          ),
        ),
    ],
  );

  Widget _selectedCard(BuildContext context, BankAccount account) {
    final colors = AppColors.of(context);
    final muted = transferText(
      context,
      12,
      18,
      color: colors.disabledBackground,
    );
    return Container(
      key: const ValueKey('wallet-selected-card'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (model.loadingDetail)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                semanticsLabel: 'Refreshing selected balance',
              ),
            ),
          if (model.detailError != null) ...[
            NoticePanel(model.detailError!.message, error: true),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _CurrencyBadge(account.currency),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  walletName(context, account.currency),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: transferText(context, 16, 24, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(account.status),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'Available balance', 'សមតុល្យដែលអាចប្រើបាន'),
            style: muted,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              balanceVisible
                  ? walletAmount(account.balance.minorUnits, account.currency)
                  : '••••',
              key: const ValueKey('wallet-selected-balance'),
              maxLines: 1,
              softWrap: false,
              style: transferText(context, 28, 36, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'Account number', 'លេខគណនី'),
                        style: muted,
                      ),
                      SelectableText(
                        account.number,
                        style: transferText(
                          context,
                          15,
                          22,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Copy account number', 'ចម្លងលេខគណនី'),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: account.number),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
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
          ),
          const SizedBox(height: 8),
          Text(
            [
              accountTypeName(context, account.type),
              if (model.detailUpdatedAt != null)
                '${tr(context, 'Updated', 'ធ្វើបច្ចុប្បន្នភាព')} ${_time(model.detailUpdatedAt!)}',
            ].join('  ·  '),
            style: muted,
          ),
          if (model.detailError != null)
            Text(
              tr(
                context,
                'Refresh failed. This is the last known balance.',
                'ធ្វើបច្ចុប្បន្នភាពបរាជ័យ។ នេះជាសមតុល្យចុងក្រោយដែលដឹង។',
              ),
              style: muted.copyWith(color: colors.error),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: Text(tx(context, 'View account details')),
              ),
              OutlinedButton.icon(
                onPressed: onActivity,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(tx(context, 'View recent activity')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _time(DateTime value) {
  final date = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
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

class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.account,
    required this.selected,
    required this.balanceVisible,
    required this.onTap,
  });
  final BankAccount account;
  final bool selected, balanceVisible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final number = account.number;
    final masked = number.length > 4
        ? '•••• ${number.substring(number.length - 4)}'
        : number;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? (Theme.of(context).brightness == Brightness.dark
                    ? AppPalette.gold700.withValues(alpha: .18)
                    : AppPalette.gold50)
              : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? AppPalette.gold500 : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('wallet-tile-$number'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      children: [
                        _CurrencyBadge(account.currency),
                        if (selected)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.background,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: AppPalette.gold600,
                                semanticLabel: 'Selected account',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          walletName(context, account.currency),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: transferText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${accountTypeName(context, account.type)} · $masked',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: transferText(
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            balanceVisible
                                ? walletAmount(
                                    account.balance.minorUnits,
                                    account.currency,
                                  )
                                : '••••',
                            maxLines: 1,
                            softWrap: false,
                            style: transferText(
                              context,
                              15,
                              22,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        _StatusChip(account.status, compact: true),
                      ],
                    ),
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

class _CurrencyBadge extends StatelessWidget {
  const _CurrencyBadge(this.currency);
  final String currency;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: currency == 'KHR' ? AppPalette.gold100 : AppPalette.navy50,
    ),
    alignment: Alignment.center,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: TransferCurrencyFlag(currency, small: true),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status, {this.compact = false});
  final String status;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (status) {
      'ACTIVE' => (
        tr(context, 'Active', 'សកម្ម'),
        AppPalette.semanticSuccess,
        AppPalette.semanticSuccessMuted,
      ),
      'FROZEN' => (
        tr(context, 'Frozen', 'បានបង្កក'),
        AppPalette.semanticInfo,
        AppPalette.semanticInfoMuted,
      ),
      'CLOSED' => (
        tr(context, 'Closed', 'បានបិទ'),
        AppPalette.neutralLightDisabledBackground,
        AppPalette.neutralLightDisabled,
      ),
      _ => (
        status,
        AppPalette.semanticWarning,
        AppPalette.semanticWarningMuted,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: transferText(
          context,
          compact ? 11 : 12,
          compact ? 16 : 18,
          weight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: colors.foreground,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.border),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onTap != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = enabled
        ? (highlighted && !dark ? AppPalette.navy500 : transferNavy(context))
        : colors.disabledBackground;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: highlighted
            ? (dark
                  ? AppPalette.gold700.withValues(alpha: .35)
                  : AppPalette.gold100)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: highlighted ? AppPalette.gold400 : colors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: foreground),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: transferText(
                      context,
                      13,
                      20,
                      weight: FontWeight.w600,
                      color: foreground,
                    ),
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
