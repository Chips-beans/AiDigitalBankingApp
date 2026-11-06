import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../account_gateway.dart';
import '../accounts_controller.dart';
import '../../transactions/history_controller.dart';
import 'wallet_accounts_screen.dart'
    show walletAmount, walletName, accountTypeName;

/// Customer Figma 426:877. Data remains owned by the account/history controllers.
class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({
    required this.accounts,
    required this.history,
    required this.ownerName,
    required this.onBack,
    required this.onTransaction,
    this.onMyQr,
    this.receiptBackdrop = false,
    super.key,
  });
  final AccountsController accounts;
  final HistoryController history;
  final String ownerName;
  final VoidCallback onBack;
  final ValueChanged<String> onTransaction;
  final VoidCallback? onMyQr;
  final bool receiptBackdrop;

  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  bool showInformation = false;
  AccountsController get accounts => widget.accounts;
  HistoryController get history => widget.history;
  String get ownerName => widget.ownerName;
  VoidCallback get onBack => widget.onBack;
  VoidCallback? get onMyQr => widget.onMyQr;
  ValueChanged<String> get onTransaction => widget.onTransaction;
  bool get receiptBackdrop => widget.receiptBackdrop;

  Future<void> _refresh() async {
    final selected = accounts.selected;
    if (selected != null) await accounts.select(selected);
    await history.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final account = accounts.selected;
    final items = [...history.items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rows = <Widget>[];
    String? lastDate;
    for (final posting in items) {
      final date = postingDate(context, posting.createdAt);
      if (date != lastDate) {
        lastDate = date;
        rows.add(
          Container(
            constraints: const BoxConstraints(minHeight: 36),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            color: colors.surface,
            child: Text(
              date,
              style: customerText(
                context,
                12,
                20,
                color: customerNavy(context),
              ),
            ),
          ),
        );
      }
      if (account != null) {
        rows.add(
          WalletPostingTile(
            posting: posting,
            account: account,
            ownAccounts: accounts.accounts,
            currencyCode: receiptBackdrop,
            onTap: () => onTransaction(posting.reference),
          ),
        );
      }
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppPalette.navy500,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ColoredBox(
                color: colors.background,
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    key: const PageStorageKey('wallet-detail-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _header(context, account)),
                      if (showInformation && account != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(
                                    context,
                                    'Account information',
                                    'ព័ត៌មានគណនី',
                                  ),
                                  style: customerText(
                                    context,
                                    18,
                                    28,
                                    color: customerNavy(context),
                                  ),
                                ),
                                SelectableText(account.number),
                                Text(
                                  '${tr(context, 'Currency', 'រូបិយប័ណ្ណ')}: ${account.currency}',
                                ),
                                Text(
                                  '${tr(context, 'Type', 'ប្រភេទ')}: ${accountTypeName(context, account.type)}',
                                ),
                                Text(
                                  '${tr(context, 'Status', 'ស្ថានភាព')}: ${account.status}',
                                ),
                                Text(
                                  '${tr(context, 'Created', 'បង្កើតនៅ')}: ${postingDate(context, account.createdAt)}',
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => showInformation = false),
                                  child: Text(
                                    tr(
                                      context,
                                      'Close information',
                                      'បិទព័ត៌មាន',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            if (accounts.loadingDetail || history.loading)
                              const LinearProgressIndicator(),
                            if (accounts.detailError != null)
                              _notice(context, accounts.detailError!.message),
                            if (history.error != null) ...[
                              _notice(context, history.error!.message),
                              TextButton(
                                onPressed: history.refresh,
                                child: Text(
                                  tr(
                                    context,
                                    'Retry history',
                                    'សាកល្បងប្រវត្តិម្ដងទៀត',
                                  ),
                                ),
                              ),
                            ],
                            if (account == null)
                              _notice(
                                context,
                                tr(
                                  context,
                                  'Select an available wallet.',
                                  'សូមជ្រើសរើសកាបូបដែលមាន។',
                                ),
                              ),
                            if (account != null &&
                                items.isEmpty &&
                                !history.loading &&
                                history.error == null)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  tr(
                                    context,
                                    'No activity yet for this account.',
                                    'មិនទាន់មានប្រតិបត្តិការសម្រាប់គណនីនេះទេ។',
                                  ),
                                  style: customerText(
                                    context,
                                    14,
                                    22,
                                    color: colors.disabledBackground,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SliverList.list(children: rows),
                      if (history.hasMore || history.moreLoading)
                        SliverToBoxAdapter(
                          child: TextButton(
                            onPressed: history.moreLoading
                                ? null
                                : history.loadMore,
                            child: Text(
                              tr(
                                context,
                                history.moreLoading
                                    ? 'Loading transactions…'
                                    : 'Load more transactions',
                                history.moreLoading
                                    ? 'កំពុងផ្ទុកប្រតិបត្តិការ…'
                                    : 'ផ្ទុកប្រតិបត្តិការបន្ថែម',
                              ),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.paddingOf(context).bottom + 24,
                        ),
                      ),
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: SizedBox(),
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

  Widget _notice(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: NoticePanel(message, error: true),
  );

  Widget _header(BuildContext context, BankAccount? account) {
    final balance = account == null
        ? '—'
        : walletAmount(account.balance.minorUnits, account.currency);
    final caption = customerText(context, 12, 20, color: AppPalette.navy50);
    return ColoredBox(
      color: AppPalette.navy500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: AppPalette.navy400.withValues(alpha: .42),
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const WalletAsset('0ebe3', size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    receiptBackdrop
                        ? tr(context, 'Kesor accounts', 'គណនី Kesor')
                        : tr(context, 'Wallet details', 'ព័ត៌មានកាបូប'),
                    style: customerText(
                      context,
                      20,
                      30,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ownerName,
                        style: customerText(
                          context,
                          14,
                          22,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account == null
                            ? '—'
                            : '${account.isMerchant ? tr(context, 'Merchant ${account.currency} Wallet', 'កាបូបអាជីវករ ${account.currency}') : walletName(context, account.currency)} · ${groupWalletNumber(account.number)}',
                        style: caption,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr(context, 'Account options', 'ជម្រើសគណនី'),
                  icon: const WalletAsset('3f093', size: 22),
                  onSelected: (value) async {
                    if (value == 'info') {
                      setState(() => showInformation = !showInformation);
                    }
                    if (value == 'refresh') await _refresh();
                    if (value == 'qr') onMyQr?.call();
                    if (value == 'copy' && account != null) {
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
                    }
                  },
                  itemBuilder: (context) => [
                    if (account != null)
                      PopupMenuItem(
                        value: 'info',
                        child: Text(
                          tr(context, 'Account information', 'ព័ត៌មានគណនី'),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text(
                        tr(context, 'Refresh wallet', 'ផ្ទុកកាបូបឡើងវិញ'),
                      ),
                    ),
                    if (account != null)
                      PopupMenuItem(
                        value: 'copy',
                        child: Text(
                          tr(context, 'Copy account number', 'ចម្លងលេខគណនី'),
                        ),
                      ),
                    if (account?.status == 'ACTIVE' && onMyQr != null)
                      PopupMenuItem(
                        value: 'qr',
                        child: Text(tr(context, 'My QR', 'QR របស់ខ្ញុំ')),
                      ),
                  ],
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Column(
                children: [
                  Text(
                    tr(
                      context,
                      account?.status == 'FROZEN'
                          ? 'Frozen balance'
                          : account?.status == 'CLOSED'
                          ? 'Closed wallet balance'
                          : 'Available balance',
                      account?.status == 'FROZEN'
                          ? 'សមតុល្យដែលបានបង្កក'
                          : account?.status == 'CLOSED'
                          ? 'សមតុល្យកាបូបដែលបានបិទ'
                          : 'សមតុល្យដែលអាចប្រើបាន',
                    ),
                    style: caption,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      balance,
                      key: const ValueKey('wallet-detail-balance'),
                      style: customerText(
                        context,
                        36,
                        44,
                        color: AppPalette.gold500,
                        weight: FontWeight.w500,
                      ).copyWith(fontFamily: 'Google Sans'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'Account balance', 'សមតុល្យគណនី'),
                    style: caption,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      balance,
                      textAlign: TextAlign.end,
                      style: customerText(
                        context,
                        14,
                        22,
                        weight: FontWeight.w500,
                        color: Colors.white,
                      ).copyWith(fontFamily: 'Google Sans'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WalletAsset extends StatelessWidget {
  const WalletAsset(this.name, {this.size = 24, this.color, super.key});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: SvgPicture.asset(
      'assets/wallet-details/$name.svg',
      excludeFromSemantics: true,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    ),
  );
}

String groupWalletNumber(String number) => [
  number.substring(0, number.length.clamp(0, 3)),
  ...RegExp(r'.{1,4}')
      .allMatches(number.substring(number.length.clamp(0, 3)))
      .map((m) => m[0]!),
].join(' ');

DateTime bankingDate(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 7));

String postingDate(
  BuildContext context,
  DateTime instant, {
  bool time = false,
}) {
  final date = bankingDate(instant);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = AppPreferences.maybeOf(context)?.isKhmer == true
      ? MaterialLocalizations.of(context).formatMediumDate(date)
      : '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  if (!time) return day;
  final clock = AppPreferences.maybeOf(context)?.isKhmer == true
      ? MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(date),
          alwaysUse24HourFormat: false,
        )
      : '${(date.hour % 12 == 0 ? 12 : date.hour % 12).toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
  return '$day, $clock';
}

bool postingIncoming(RecentPosting p, String number) =>
    p.destination == number && p.source != number;
bool postingMerchant(RecentPosting p) =>
    p.operation?.contains('MERCHANT') == true;
String postingAsset(RecentPosting p) => postingMerchant(p)
    ? '387f1'
    : p.operation?.contains('QR') == true
    ? 'bc97e'
    : 'dce38';

String postingName(
  BuildContext context,
  RecentPosting p,
  String number,
  List<BankAccount> own,
) {
  if (p.bankSource || p.type == 'DEPOSIT' && p.source == null) {
    return 'Kesor Bank';
  }
  final other = postingIncoming(p, number) ? p.source : p.destination;
  if (other != null && own.any((a) => a.number == other)) {
    return tr(context, 'Between your accounts', 'រវាងគណនីរបស់អ្នក');
  }
  return (postingIncoming(p, number) ? p.sourceName : p.destinationName) ??
      tr(context, 'Kesor customer', 'អតិថិជន Kesor');
}

String postingCategory(BuildContext context, RecentPosting p, String number) {
  if (postingMerchant(p)) {
    return tr(context, 'Merchant payment', 'ការទូទាត់ឱ្យអាជីវករ');
  }
  if (p.type == 'DEPOSIT') return tr(context, 'Deposit', 'ប្រាក់ដាក់ចូល');
  if (p.type == 'WITHDRAWAL') return tr(context, 'Withdrawal', 'ការដកប្រាក់');
  if (p.operation?.contains('QR') == true) {
    return postingIncoming(p, number)
        ? tr(context, 'QR payment from', 'ការទូទាត់ QR ពី')
        : tr(context, 'QR payment to', 'ការទូទាត់ QR ទៅ');
  }
  return postingIncoming(p, number)
      ? tr(context, 'Received from', 'បានទទួលពី')
      : tr(context, 'Transferred to', 'បានផ្ទេរទៅ');
}

String postingAmount(
  RecentPosting p,
  String account, {
  bool currencyCode = false,
}) {
  final amount = currencyCode
      ? '${p.amount.decimal} ${p.amount.currency}'
      : walletAmount(p.amount.minorUnits, p.amount.currency);
  return '${postingIncoming(p, account) ? '+' : '−'}$amount';
}

String postingStatus(BuildContext context, String status) => switch (status) {
  'SUCCESS' => tr(context, 'Completed', 'បានបញ្ចប់'),
  'PENDING' => tr(context, 'Pending', 'កំពុងរង់ចាំ'),
  'FAILED' => tr(context, 'Failed', 'មិនបានសម្រេច'),
  'REVERSED' => tr(context, 'Reversed', 'បានបង្វិលត្រឡប់'),
  _ => status,
};

class WalletPostingTile extends StatelessWidget {
  const WalletPostingTile({
    required this.posting,
    required this.account,
    required this.ownAccounts,
    required this.onTap,
    this.currencyCode = false,
    super.key,
  });
  final RecentPosting posting;
  final BankAccount account;
  final List<BankAccount> ownAccounts;
  final VoidCallback onTap;
  final bool currencyCode;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final incoming = postingIncoming(posting, account.number);
    final success = posting.status == 'SUCCESS';
    final compact =
        MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final amount = Text(
      postingAmount(posting, account.number, currencyCode: currencyCode),
      textAlign: TextAlign.end,
      style: customerText(
        context,
        16,
        24,
        weight: FontWeight.w500,
        color: success
            ? incoming
                  ? colors.success
                  : colors.error
            : colors.disabledBackground,
      ).copyWith(fontFamily: 'Google Sans'),
    );
    final title = postingName(context, posting, account.number, ownAccounts);
    return Material(
      color: colors.background,
      child: InkWell(
        key: ValueKey('wallet-posting-${posting.reference}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 86),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: incoming ? colors.successMuted : colors.primary50,
                  ),
                  child: WalletAsset(
                    postingAsset(posting),
                    size: 20,
                    color: incoming ? colors.success : colors.primary700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        postingCategory(context, posting, account.number),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: customerText(
                          context,
                          12,
                          20,
                          color: colors.disabledBackground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: customerText(
                          context,
                          14,
                          22,
                          weight: FontWeight.w600,
                          color: customerNavy(context),
                        ),
                      ),
                      if (!success)
                        Text(
                          postingStatus(context, posting.status),
                          style: customerText(
                            context,
                            12,
                            20,
                            color: colors.disabledBackground,
                          ),
                        ),
                      if (compact) amount,
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.sizeOf(context).width.clamp(0, 440) * .4,
                    ),
                    child: amount,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
