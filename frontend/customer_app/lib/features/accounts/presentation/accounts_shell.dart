import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../home/home_controller.dart';
import '../../analytics/analytics_controller.dart';
import '../../analytics/analytics_gateway.dart';
import '../../analytics/presentation/analytics_screen.dart';
import '../../home/home_gateway.dart';
import '../../auth/session_controller.dart';
import '../../profile/profile_page.dart';
import '../../home/presentation/kesor_home_screen.dart';
import '../account_gateway.dart';
import '../accounts_controller.dart';
import '../creation_store.dart';
import '../../transactions/transaction_gateway.dart';
import '../../transactions/transfer_store.dart';
import '../../transactions/transfer_controller.dart';
import '../../transactions/history_controller.dart';
import '../../transactions/presentation/transfer_panel.dart';
import '../../transactions/presentation/history_panel.dart';

String displayDate(DateTime value) {
  final date = value.toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class AccountsShell extends StatefulWidget {
  const AccountsShell({
    required this.session,
    required this.gateway,
    required this.store,
    required this.transactions,
    required this.transferStore,
    required this.transfersEnabled,
    this.designPreview = false,
    this.analyticsGateway,
    super.key,
  });
  final SessionController session;
  final AccountGateway gateway;
  final CreationStore store;
  final TransactionGateway transactions;
  final TransferStore transferStore;
  final bool transfersEnabled;
  final bool designPreview;
  final AnalyticsGateway? analyticsGateway;
  @override
  State<AccountsShell> createState() => _AccountsShellState();
}

class _AccountsShellState extends State<AccountsShell> {
  late final AccountsController model;
  late final HomeController home;
  AnalyticsController? analytics;
  late final TransferController transfers;
  late final HistoryController history;
  late final Listenable changes;
  String? transactionReference;
  String? transactionReturnPage;
  int tab = 0;
  bool _homeBalanceVisible = true;
  String? page;
  String type = 'SAVINGS', currency = 'USD';
  @override
  void initState() {
    super.initState();
    model = AccountsController(widget.session, widget.gateway, widget.store);
    home = HomeController(widget.session, AccountHomeGateway(widget.gateway));
    final analyticsGateway = widget.analyticsGateway;
    if (analyticsGateway != null) {
      analytics = AnalyticsController(widget.session, analyticsGateway);
    }
    history = HistoryController(widget.session, model, widget.transactions);
    transfers = TransferController(
      widget.session,
      widget.transactions,
      widget.transferStore,
      onSuccess: () async {
        await model.refresh();
        await history.refresh();
        await home.refresh();
        await analytics?.invalidate();
      },
    );
    changes = Listenable.merge([model, transfers, history, home, ?analytics]);
    unawaited(transfers.initialize());
    unawaited(model.initialize());
    if (!widget.designPreview) unawaited(home.refresh());
  }

  @override
  void dispose() {
    home.dispose();
    analytics?.dispose();
    transfers.dispose();
    history.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: changes,
    builder: (context, _) {
      if (page == null) return _root(context);
      final title = page == 'open'
          ? 'Open an account'
          : page == 'details'
          ? 'Account details'
          : page == 'transfer'
          ? 'Internal transfer'
          : page == 'transaction'
          ? 'Transaction details'
          : page == 'accounts'
          ? 'Your accounts'
          : page == 'history'
          ? 'Activity'
          : page == 'profile'
          ? 'Your profile'
          : ['Home', 'Analytics', 'Settings', 'AI assistant'][tab];
      return PopScope(
        canPop: page == null && tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _back();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: page != null
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _back,
                  )
                : null,
            title: Text(title),
            actions: [
              if (page != 'profile')
                IconButton(
                  tooltip: 'Profile',
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => setState(() => page = 'profile'),
                ),
              IconButton(
                tooltip: tab == 2 && page == null
                    ? 'Refresh profile'
                    : 'Refresh accounts',
                onPressed: tab == 2 && page == null
                    ? (widget.session.busy
                          ? null
                          : widget.session.refreshProfile)
                    : (model.loading ? null : _refresh),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: tab == 2 && page == null
                  ? widget.session.refreshProfile
                  : _refresh,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: page == 'open'
                            ? _opening(context)
                            : page == 'details'
                            ? _details(context)
                            : page == 'transfer'
                            ? [
                                TransferPanel(
                                  controller: transfers,
                                  accounts: model,
                                  enabled: widget.transfersEnabled,
                                ),
                              ]
                            : page == 'transaction'
                            ? [
                                TransactionDetailPanel(
                                  history,
                                  reference: transactionReference!,
                                ),
                              ]
                            : page != 'history' && page != 'profile'
                            ? _home(context)
                            : page == 'history'
                            ? [
                                HistoryPanel(
                                  history,
                                  onDetail: (reference) {
                                    setState(() {
                                      transactionReturnPage = 'history';
                                      page = 'transaction';
                                      transactionReference = reference;
                                    });
                                    unawaited(history.openDetail(reference));
                                  },
                                ),
                              ]
                            : [ProfilePage(widget.session)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: KesorBottomBar(
                    selectedIndex: tab,
                    onSelected: _selectTab,
                    onAssistant: () => _selectTab(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  void _selectTab(int index) {
    setState(() {
      if (!transfers.busy) transfers.edit();
      history.closeDetail();
      tab = index;
      page = null;
    });
    if (index == 1) unawaited(analytics?.ensureLoaded());
  }

  Widget _root(BuildContext context) {
    final prefs = AppPreferences.maybeOf(context);
    final locale = prefs?.locale ?? const Locale('en');
    final labels = locale.languageCode == 'km'
        ? ['ទំព័រដើម', 'ការវិភាគ', 'ការកំណត់', 'ជំនួយការ AI']
        : ['Home', 'Analytics', 'Settings', 'AI assistant'];
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
            child: Stack(
              children: [
                Positioned.fill(
                  child: tab == 0
                      ? KesorHomeScreen(
                          showNavigation: false,
                          balanceVisible: _homeBalanceVisible,
                          onBalanceVisibilityChanged: (visible) =>
                              setState(() => _homeBalanceVisible = visible),
                          data: widget.designPreview
                              ? KesorHomeData.designPreview
                              : home.snapshot?.presentation(locale) ??
                                    const KesorHomeData(
                                      khrBalance: '—',
                                      usdBalance: r'$—',
                                    ),
                          loading: !widget.designPreview && home.loading,
                          errorMessage: home.error == null
                              ? null
                              : tr(
                                  context,
                                  'Home could not refresh. Pull down to retry. Previously loaded values may be out of date.',
                                  'មិនអាចធ្វើបច្ចុប្បន្នភាពបាន។ អូសចុះក្រោមដើម្បីព្យាយាមម្ដងទៀត។ ទិន្នន័យមុនអាចចាស់។',
                                ),
                          onAccounts: () => setState(() => page = 'accounts'),
                          onTransfer: () => setState(() => page = 'transfer'),
                          onActivity: () => setState(() => page = 'history'),
                          onProfile: () => setState(() => page = 'profile'),
                          onRefresh: widget.designPreview
                              ? () async {}
                              : home.refresh,
                          pendingTransfer: transfers.saved != null,
                          onTransaction: (entry) async {
                            if (entry.reference == null) {
                              setState(() => page = 'history');
                              return;
                            }
                            setState(() {
                              page = 'transaction';
                              transactionReference = entry.reference;
                            });
                            if (entry.accountNumber != null &&
                                entry.accountNumber != model.selected?.number) {
                              final account = home.snapshot?.accounts
                                  .where((a) => a.number == entry.accountNumber)
                                  .firstOrNull;
                              if (account != null) {
                                await model.select(account);
                              }
                            }
                            if (mounted) {
                              unawaited(history.openDetail(entry.reference!));
                            }
                          },
                        )
                      : tab == 1 && analytics != null
                      ? AnalyticsScreen(controller: analytics!)
                      : Center(
                          child: Text(
                            labels[tab],
                            key: ValueKey('placeholder-tab-$tab'),
                          ),
                        ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: math.max(24, MediaQuery.paddingOf(context).bottom),
                  child: KesorBottomBar(
                    selectedIndex: tab,
                    onSelected: _selectTab,
                    onAssistant: () => _selectTab(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _back() {
    if (page == 'transfer' && transfers.review != null && !transfers.busy) {
      transfers.edit();
      return;
    }
    setState(() {
      if (page == 'transaction') {
        history.closeDetail();
        page = transactionReturnPage;
        transactionReturnPage = null;
      } else if (page == 'details' || page == 'open') {
        page = 'accounts';
      } else if (page != null) {
        page = null;
      } else {
        tab = 0;
      }
    });
  }

  Future<void> _refresh() async {
    if (page == 'transaction' && transactionReference != null) {
      await history.openDetail(transactionReference!);
    } else if (page == 'history') {
      await history.refresh();
    } else {
      await model.refresh();
    }
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );

  List<Widget> _errors() => [
    if (model.detailError != null && model.selected == null)
      NoticePanel(model.detailError!.message, error: true),
    if (model.storageError != null) ...[
      NoticePanel(model.storageError!.message, error: true),
      TextButton(
        onPressed: model.opening ? null : model.initialize,
        child: const Text('Retry secure setup'),
      ),
    ],
    if (model.listError != null) ...[
      NoticePanel(model.listError!.message, error: true),
      TextButton(
        onPressed: model.loading ? null : model.refresh,
        child: const Text('Retry accounts'),
      ),
    ],
    if (model.uncertain) ...[
      const NoticePanel(
        'An account-opening request may have completed. Refresh and review your accounts before deciding to open another. Restarting the app will not repeat the request.',
      ),
      TextButton(
        onPressed: model.loading || model.opening ? null : model.refresh,
        child: const Text('Refresh and review accounts'),
      ),
      if (model.checkedAfterUncertainty)
        TextButton(
          onPressed: model.opening ? null : _confirmNewDecision,
          child: const Text('I reviewed my accounts; allow a new account'),
        ),
    ],
  ];

  Future<void> _confirmNewDecision() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow another account?'),
        content: const Text(
          'The earlier request may still have created an account. Continuing allows a separate new account; it does not retry or undo that request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep checking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow new account'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await model.allowNewAccount();
  }

  List<Widget> _home(BuildContext context) => [
    _heading(
      context,
      'Hello, ${widget.session.identity?.firstName ?? widget.session.identity?.username ?? ''}',
    ),
    const Text('Your accounts'),
    const SizedBox(height: 16),
    ..._errors(),
    if (transfers.saved != null)
      NoticePanel(
        transfers.saved!.unresolved
            ? 'A saved transfer has an unknown outcome. Open Transfer to recover it before starting another.'
            : 'A saved transfer result is ready to review.',
      ),
    FilledButton.icon(
      onPressed: () => setState(() => page = 'transfer'),
      icon: const Icon(Icons.send_outlined),
      label: Text(
        transfers.saved == null ? 'Transfer' : 'Review saved transfer',
      ),
    ),
    const SizedBox(height: 16),
    if (model.notice != null) NoticePanel(model.notice!),
    if (model.loading)
      const LinearProgressIndicator(semanticsLabel: 'Refreshing accounts'),
    if (!model.loading && model.accounts.isEmpty && model.listError == null)
      const NoticePanel(
        'You have no accounts yet. Open an account to get started with a zero balance.',
      ),
    if (model.accountsUpdatedAt != null)
      Text(
        'Accounts last updated ${displayDate(model.accountsUpdatedAt!)}${model.listError == null ? '' : ' · Refresh failed'}',
      ),
    const SizedBox(height: 16),
    for (final account in model.accounts)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            selected: model.selected?.number == account.number,
            title: Text(account.label),
            subtitle: Text('${account.balance.formatted}\n${account.status}'),
            isThreeLine: true,
            trailing: model.selected?.number == account.number
                ? const Icon(
                    Icons.check_circle,
                    semanticLabel: 'Selected account',
                  )
                : null,
            onTap: () => model.select(account),
          ),
        ),
      ),
    if (model.hasMore)
      TextButton(
        onPressed: model.loading || model.loadingMore ? null : model.loadMore,
        child: Text(model.loadingMore ? 'Loading more…' : 'Load more accounts'),
      ),
    if (model.selected != null) ...[
      const SizedBox(height: 16),
      ..._balance(context),
      TextButton(
        onPressed: () => setState(() => page = 'details'),
        child: const Text('View account details'),
      ),
      TextButton(
        onPressed: () => setState(() => tab = 1),
        child: const Text('View recent activity'),
      ),
    ],
    const SizedBox(height: 24),
    FilledButton.icon(
      onPressed:
          !model.ready ||
              model.opening ||
              model.uncertain ||
              model.storageError != null
          ? null
          : () => setState(() {
              type = 'SAVINGS';
              currency = 'USD';
              page = 'open';
            }),
      icon: const Icon(Icons.add),
      label: const Text('Open account'),
    ),
  ];

  List<Widget> _balance(BuildContext context) => [
    if (model.loadingDetail)
      const LinearProgressIndicator(
        semanticsLabel: 'Refreshing selected balance',
      ),
    if (model.detailError != null)
      NoticePanel(model.detailError!.message, error: true),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SELECTED ACCOUNT BALANCE'),
            const SizedBox(height: 8),
            Text(
              model.selected!.balance.formatted,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(model.selected!.number),
            Text('Status: ${model.selected!.status}'),
            if (model.detailUpdatedAt != null)
              Text('Last updated ${displayDate(model.detailUpdatedAt!)}'),
            if (model.detailError != null)
              const Text('Refresh failed. This is the last known balance.'),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _details(BuildContext context) {
    final account = model.selected;
    if (account == null) {
      return [const NoticePanel('Select an available account from Home.')];
    }
    return [
      ..._balance(context),
      const SizedBox(height: 16),
      Text('Type: ${account.type}'),
      Text('Currency: ${account.currency}'),
      Text('Created ${displayDate(account.createdAt)}'),
      TextButton(
        onPressed: model.loadingDetail ? null : () => model.select(account),
        child: const Text('Refresh selected account'),
      ),
    ];
  }

  List<Widget> _opening(BuildContext context) => [
    const NoticePanel(
      'Your new account starts at zero. Funding is handled by bank staff.',
    ),
    ..._errors(),
    DropdownButtonFormField<String>(
      initialValue: type,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Account type'),
      items: BankAccount.types
          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
          .toList(),
      onChanged: model.opening || model.uncertain
          ? null
          : (v) => setState(() => type = v!),
    ),
    const SizedBox(height: 24),
    DropdownButtonFormField<String>(
      initialValue: currency,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Currency'),
      items: [
        'USD',
        'KHR',
      ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: model.opening || model.uncertain
          ? null
          : (v) => setState(() => currency = v!),
    ),
    const SizedBox(height: 24),
    Text('Opening balance: ${currency == 'USD' ? 'USD 0.00' : 'KHR 0'}'),
    const SizedBox(height: 24),
    if (model.creationError != null)
      NoticePanel(model.creationError!.message, error: true),
    BusyButton(
      label: 'Confirm open account',
      busy: model.opening,
      onPressed: model.uncertain || !model.ready || model.storageError != null
          ? null
          : () async {
              final success = await model.open(type, currency);
              if (success) await analytics?.invalidate();
              if (success && mounted) setState(() => page = 'accounts');
            },
    ),
  ];
}
