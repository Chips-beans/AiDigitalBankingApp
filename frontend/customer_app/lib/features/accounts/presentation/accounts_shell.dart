import '../../home/home_unlock_target.dart';

import 'dart:async';

import '../../merchant/merchant_sessions_screen.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../app/app_labels.dart';
import '../../../core/network/api_client.dart';
import '../pair_opening.dart';
import 'pair_opening_panel.dart';
import 'wallet_accounts_screen.dart';
import 'wallet_detail_screen.dart';
import '../../transactions/presentation/transaction_detail_screen.dart';
import '../../qr/qr_gateway.dart';
import '../../qr/presentation/receive_qr_panel.dart';
import '../../qr/presentation/scan_qr_panel.dart';

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
import '../../settings/settings_screen.dart';
import '../../settings/settings_detail_screen.dart';
import '../../settings/settings_platform.dart';
import '../../home/presentation/kesor_home_screen.dart';
import '../account_gateway.dart';
import '../accounts_controller.dart';
import '../creation_store.dart';
import '../../transactions/transaction_gateway.dart';
import '../../transactions/transfer_store.dart';
import '../../transactions/transfer_controller.dart';
import '../../transactions/transfer_models.dart';
import '../../transactions/transfer_support.dart';
import '../../transactions/history_controller.dart';
import '../../transactions/presentation/kesor_transfer_screen.dart';
import '../../transactions/recipient_favorites.dart';
import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_gateway.dart';
import '../../assistant/assistant_store.dart';
import '../../assistant/assistant_models.dart';
import '../../assistant/presentation/assistant_screen.dart';

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
    this.initialTarget,
    this.onInitialTargetConsumed,
    this.analyticsGateway,
    this.pairOpeningStore,
    this.recipientFavorites,
    this.assistantGateway,
    this.assistantStore,
    super.key,
  });
  final SessionController session;
  final AccountGateway gateway;
  final CreationStore store;
  final TransactionGateway transactions;
  final TransferStore transferStore;
  final bool transfersEnabled;
  final bool designPreview;
  final HomeUnlockTarget? initialTarget;
  final VoidCallback? onInitialTargetConsumed;
  final AnalyticsGateway? analyticsGateway;
  final PairOpeningStore? pairOpeningStore;
  final RecipientFavoritesStore? recipientFavorites;
  final AssistantGateway? assistantGateway;
  final AssistantPendingStore? assistantStore;
  @override
  State<AccountsShell> createState() => _AccountsShellState();
}

class _AccountsShellState extends State<AccountsShell> {
  late final AccountsController model;
  late final AccountsController merchantModel;
  late final HistoryController merchantHistory;
  late final HomeController home;
  AnalyticsController? analytics;
  late final TransferController transfers;
  late final HistoryController history;
  late final RecipientFavoritesStore recipientFavorites;
  late final AssistantController assistant;
  PairOpeningController? pairs;
  QrGateway? qrGateway;
  RecipientDirectory? recipients;

  /// Home's Recipients section: the customer's saved favorites only.
  List<HomeRecipient> savedRecipients = const [];
  bool _savedRecipientsReady = false;
  String? _initialHomeAction;

  /// Receiver handed to the transfer screen by Home or a QR scan.
  TransferPrefill? transferPrefill;
  late final Listenable changes;
  String? transactionReference;
  String? transactionReturnPage;
  int tab = 0;
  bool _homeBalanceVisible = true;
  String? page;
  @override
  void initState() {
    super.initState();
    model = AccountsController(widget.session, widget.gateway, widget.store);
    // No account-opening journal or personal selection is shared with this
    // read-only view. Refresh starts when the Wallets screen is entered.
    merchantModel = AccountsController(
      widget.session,
      MerchantWalletGateway(widget.gateway),
      MemoryCreationStore(),
    );
    merchantHistory = HistoryController(
      widget.session,
      merchantModel,
      widget.transactions,
    );
    assistant = AssistantController(
      widget.session,
      widget.assistantGateway ?? UnavailableAssistantGateway(),
      widget.assistantStore ?? AssistantPendingStore(),
    );
    recipientFavorites = widget.recipientFavorites ?? RecipientFavoritesStore();
    final target = widget.initialTarget;
    if (target != null) {
      _initialHomeAction = target.page;
      tab = target.tab;
      page = {'favorites', 'addFavorite', 'inbox'}.contains(target.page)
          ? null
          : target.page;
      transactionReference = target.reference;
      if (target.recipient != null) {
        transferPrefill = TransferPrefill(target.recipient!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onInitialTargetConsumed?.call();
        if (target.page == 'history') {
          history.refresh();
        }
        if (target.tab == 1) {
          analytics?.ensureLoaded();
        }
        assistant.setVisible(target.tab == 3);
      });
    }

    home = HomeController(widget.session, AccountHomeGateway(widget.gateway));
    final analyticsGateway = widget.analyticsGateway;
    if (analyticsGateway != null) {
      analytics = AnalyticsController(widget.session, analyticsGateway);
    }
    history = HistoryController(widget.session, model, widget.transactions);
    final api = widget.gateway;
    // The real API resolves receivers, quotes conversions and requires a PIN per transfer.
    final support = api is HttpAccountGateway
        ? HttpTransferSupportGateway(api.client)
        : null;
    if (support != null) {
      recipients = RecipientDirectory(widget.session, support);
    }
    transfers = TransferController(
      widget.session,
      widget.transactions,
      widget.transferStore,
      support: support,
      onSuccess: () async {
        await model.refresh();
        await history.refresh();
        await home.refresh();
        await analytics?.invalidate();
        await _activityAlert();
      },
    );
    final gateway = widget.gateway;
    if (gateway is AccountPairGateway) {
      pairs = PairOpeningController(
        widget.session,
        gateway as AccountPairGateway,
        widget.pairOpeningStore ??
            PairOpeningStore(
              namespace: !kIsWeb && gateway is HttpAccountGateway
                  ? '${gateway.client.config.apiBaseUrl}|${gateway.client.config.mode}'
                  : null,
            ),
        onSuccess: () async {
          await model.refresh();
          await home.refresh();
          await history.refresh();
          await analytics?.invalidate();
          await _activityAlert();
        },
      );
    }
    if (gateway is HttpAccountGateway) {
      qrGateway = HttpQrGateway(gateway.client);
    }
    changes = Listenable.merge([
      model,
      merchantModel,
      merchantHistory,
      transfers,
      history,
      home,
      ?analytics,
      ?pairs,
    ]);
    unawaited(transfers.initialize());
    unawaited(_loadAccountsAndInitialReceipt(widget.initialTarget?.reference));
    if (!widget.designPreview) {
      unawaited(_loadSavedRecipients());
    }
  }

  /// A PIN continuation can arrive before owned accounts have loaded. Resolve
  /// its wallet from the freshly authorized Home snapshot before requesting the
  /// receipt, including when the posting belongs to the non-default currency.
  Future<void> _loadAccountsAndInitialReceipt(String? reference) async {
    await Future.wait([
      model.initialize(),
      if (!widget.designPreview) home.refresh(),
    ]);
    bool current() =>
        mounted &&
        widget.session.phase == SessionPhase.signedIn &&
        page == 'transaction' &&
        transactionReference == reference;
    if (reference == null || !current()) return;
    final posting = home.snapshot?.postings
        .where((p) => p.reference == reference)
        .firstOrNull;
    if (posting != null) {
      final account = home.snapshot!.accounts
          .where(
            (a) =>
                (a.number == posting.source ||
                    a.number == posting.destination) &&
                a.currency == posting.amount.currency,
          )
          .firstOrNull;
      if (account != null && account.number != model.selected?.number) {
        await model.select(account);
      }
    }
    if (current()) await history.openDetail(reference);
  }

  Future<void> _loadSavedRecipients() async {
    final user = widget.session.identity?.userId;
    if (widget.designPreview || user == null) return;
    final List<FavoriteRecipient> saved;
    try {
      // Only people added through the form; one entry per account number.
      final seen = <String>{};
      saved = (await recipientFavorites.read(user))
          .where((r) => r.manual && seen.add(r.number))
          .toList();
    } catch (_) {
      return;
    }
    final people = await Future.wait(
      saved.map((favorite) async {
        String? known;
        try {
          known = (await recipients?.lookup(favorite.number))?.name;
        } catch (_) {}
        return HomeRecipient(
          favorite.name ?? known ?? favorite.number,
          accountNumber: favorite.number,
          knownName: known,
        );
      }),
    );
    if (mounted && widget.session.identity?.userId == user) {
      setState(() {
        savedRecipients = people;
        _savedRecipientsReady = true;
      });
    }
  }

  /// Verifies the number belongs to another active Kesor account, then saves it.
  Future<String?> _saveRecipient(String number, String? name) async {
    final unavailable = tr(
      context,
      'Recipients cannot be verified right now. Try again later.',
      'មិនអាចផ្ទៀងផ្ទាត់អ្នកទទួលបានទេឥឡូវនេះ។ សូមព្យាយាមម្ដងទៀតពេលក្រោយ។',
    );
    final notFound = tr(
      context,
      'No Kesor account uses this number.',
      'គ្មានគណនី Kesor ណាប្រើលេខនេះទេ។',
    );
    final own = tr(
      context,
      'This is your own account.',
      'នេះជាគណនីរបស់អ្នកផ្ទាល់។',
    );
    final user = widget.session.identity?.userId;
    final directory = recipients;
    if (user == null || directory == null) return unavailable;
    if (model.accounts.any((a) => a.number == number)) return own;
    final Recipient? found;
    try {
      found = await directory.lookup(number);
    } on ApiFailure catch (e) {
      return e.message;
    } catch (_) {
      return unavailable;
    }
    if (found == null) return notFound;
    try {
      await recipientFavorites.add(
        user,
        FavoriteRecipient(number, found.currency, name: name, manual: true),
      );
    } catch (_) {
      return FavoriteRecipient.unavailable.message;
    }
    await _loadSavedRecipients();
    return null;
  }

  Future<void> _removeSavedRecipient(HomeRecipient person) async {
    final user = widget.session.identity?.userId;
    if (user == null) return;
    try {
      for (final favorite in await recipientFavorites.read(user)) {
        if (favorite.number == person.accountNumber) {
          await recipientFavorites.remove(user, favorite);
        }
      }
    } catch (_) {}
    await _loadSavedRecipients();
  }

  @override
  void dispose() {
    assistant.dispose();
    pairs?.dispose();
    home.dispose();
    analytics?.dispose();
    transfers.dispose();
    history.dispose();
    merchantHistory.dispose();
    merchantModel.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: changes,
    builder: (context, _) {
      if (page == null) return _root(context);
      if (page!.startsWith('settings:')) {
        if (page == 'settings:merchant-sessions') {
          return MerchantSessionsScreen(session: widget.session, onBack: _back);
        }
        return SettingsDetailScreen(
          key: ValueKey(page),
          page: page!.substring(9),
          session: widget.session,
          onBack: _back,
          onAssistant: () => _selectTab(3),
        );
      }
      if (page == 'transfer') {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: KesorTransferScreen(
            key: ValueKey(transferPrefill),
            controller: transfers,
            accounts: model,
            enabled: widget.transfersEnabled,
            onBack: _back,
            favorites: recipientFavorites,
            prefill: transferPrefill,
            directory: recipients,
          ),
        );
      }
      if (page == 'receiveQr' && qrGateway != null) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: ReceiveQrScreen(
            background: KesorHomeScreen(
              data: widget.designPreview
                  ? KesorHomeData.designPreview
                  : (home.snapshot?.presentation(
                              AppPreferences.of(context).locale,
                            ) ??
                            const KesorHomeData(
                              khrBalance: '—',
                              usdBalance: r'$—',
                            ))
                        .withRecipients(savedRecipients),
              balanceVisible: _homeBalanceVisible,
              showNavigation: true,
            ),
            panel: ReceiveQrPanel(
              session: widget.session,
              gateway: qrGateway!,
              accounts: model,
              onClose: _back,
              onPaid: () async {
                await model.refresh();
                await home.refresh();
                await history.refresh();
                await analytics?.invalidate();
              },
            ),
          ),
        );
      }
      if (page == 'scanQr' && qrGateway != null) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            body: ScanQrPanel(
              session: widget.session,
              gateway: qrGateway!,
              accounts: model,
              transfers: transfers,
              enabled: widget.transfersEnabled,
              onClose: _back,
              onScanned: (preview) => _openTransfer(
                TransferPrefill(
                  preview.destination,
                  name: preview.name,
                  qrString: preview.payload,
                  fixedAmount: preview.dynamic ? preview.amount : null,
                  qrRemark: preview.remark,
                  shop: preview.shop,
                ),
              ),
            ),
          ),
        );
      }
      if (page == 'accounts') {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: _wallet(context),
        );
      }
      if (page == 'details' ||
          page == 'history' ||
          page == 'transaction' ||
          page == 'merchantDetails' ||
          page == 'merchantTransaction') {
        final merchant =
            page == 'merchantDetails' || page == 'merchantTransaction';
        final detailAccounts = merchant ? merchantModel : model;
        final detailHistory = merchant ? merchantHistory : history;
        final identity = widget.session.identity;
        final owner = [
          identity?.firstName,
          identity?.lastName,
        ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: page == 'transaction' || page == 'merchantTransaction'
              ? TransactionDetailScreen(
                  accounts: detailAccounts,
                  history: detailHistory,
                  reference: transactionReference!,
                  ownerName: owner.isEmpty ? identity?.username ?? '' : owner,
                  onBack: _back,
                )
              : WalletDetailScreen(
                  key: ValueKey(
                    merchant ? 'merchant-details' : 'personal-details',
                  ),
                  accounts: detailAccounts,
                  history: detailHistory,
                  ownerName: owner.isEmpty ? identity?.username ?? '' : owner,
                  onBack: _back,
                  onMyQr: merchant
                      ? null
                      : () => setState(() => page = 'receiveQr'),
                  onTransaction: (reference) {
                    setState(() {
                      transactionReturnPage = page;
                      page = merchant ? 'merchantTransaction' : 'transaction';
                      transactionReference = reference;
                    });
                    unawaited(detailHistory.openDetail(reference));
                  },
                ),
        );
      }
      final title = page == 'receiveQr'
          ? 'My QR'
          : page == 'scanQr'
          ? 'Scan QR'
          : page == 'open'
          ? 'Open accounts'
          : page == 'details'
          ? 'Account details'
          : page == 'transfer'
          ? 'Internal transfer'
          : page == 'transaction'
          ? 'Transaction details'
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
            title: Text(tx(context, title)),
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
                      constraints: BoxConstraints(
                        maxWidth: {'receiveQr', 'scanQr', 'open'}.contains(page)
                            ? KesorLayout.frameWidth
                            : 640,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: page == 'receiveQr' || page == 'scanQr'
                            ? [
                                NoticePanel(
                                  tx(
                                    context,
                                    'QR features require the API app.',
                                  ),
                                ),
                              ]
                            : page == 'open'
                            ? _opening(context)
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

  /// A pending transfer keeps priority: its safety record must be resolved first.
  void _openTransfer(TransferPrefill? prefill) {
    setState(() {
      if (transfers.saved == null && !transfers.busy) {
        transfers.edit();
        transferPrefill = prefill;
      }
      page = 'transfer';
    });
  }

  void _selectTab(int index) {
    setState(() {
      if (!transfers.busy) transfers.edit();
      history.closeDetail();
      tab = index;
      page = null;
    });
    if (index == 1) unawaited(analytics?.ensureLoaded());
    assistant.setVisible(index == 3);
  }

  Future<void> _activityAlert() async {
    if (!mounted ||
        AppPreferences.maybeOf(context)?.activityAlerts != true ||
        widget.session.phase != SessionPhase.signedIn) {
      return;
    }
    try {
      await SettingsPlatform().activityAlert();
    } catch (_) {
      /* Alerts cannot alter a confirmed banking result. */
    }
  }

  Future<void> _assistantAction(AiAction action) async {
    if (!assistant.current || !mounted) return;
    assistant.setVisible(false);
    if (action.type == 'ANALYTICS') {
      final controller = analytics;
      if (controller != null) {
        setState(() {
          tab = 1;
          page = null;
        });
        await controller.showPeriod(action.month!, action.currency!);
      }
      return;
    }
    if (action.type == 'ACCOUNT' || action.type == 'TRANSACTION') {
      // Re-read through existing authorized services before exposing details.
      final number = action.accountNumber!;
      final account = await widget.session.authorizedRead(
        (token) => widget.gateway.detail(token, number),
      );
      if (!mounted || !assistant.current) return;
      await model.select(account);
      if (!mounted || !assistant.current) return;
      if (action.type == 'ACCOUNT') {
        setState(() => page = 'details');
      } else {
        setState(() {
          page = 'transaction';
          transactionReturnPage = null;
          transactionReference = action.value;
        });
        await history.openDetail(action.value!);
      }
      return;
    }
    final target = action.type == 'ACCOUNTS' ? 'ACCOUNTS' : action.value;
    final destination = switch (target) {
      'ACCOUNTS' => 'accounts',
      'TRANSFER' => 'transfer',
      'MY_QR' => 'receiveQr',
      'SCAN_QR' => 'scanQr',
      _ => null,
    };
    if (destination != null) setState(() => page = destination);
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
                          initialAction:
                              _initialHomeAction == 'favorites' &&
                                  !_savedRecipientsReady
                              ? null
                              : _initialHomeAction,
                          showNavigation: false,
                          balanceVisible: _homeBalanceVisible,
                          onBalanceVisibilityChanged: (visible) =>
                              setState(() => _homeBalanceVisible = visible),
                          data: widget.designPreview
                              ? KesorHomeData.designPreview
                              : (home.snapshot?.presentation(locale) ??
                                        const KesorHomeData(
                                          khrBalance: '—',
                                          usdBalance: r'$—',
                                        ))
                                    .withRecipients(savedRecipients),
                          loading: !widget.designPreview && home.loading,
                          errorMessage: home.error == null
                              ? null
                              : tr(
                                  context,
                                  'Home could not refresh. Pull down to retry. Previously loaded values may be out of date.',
                                  'មិនអាចធ្វើបច្ចុប្បន្នភាពបាន។ អូសចុះក្រោមដើម្បីព្យាយាមម្ដងទៀត។ ទិន្នន័យមុនអាចចាស់។',
                                ),
                          onAccounts: () => setState(() => page = 'accounts'),
                          onTransfer: () => _openTransfer(null),
                          onRecipient: (number, name) => _openTransfer(
                            TransferPrefill(number, name: name),
                          ),
                          onSaveRecipient: widget.designPreview
                              ? null
                              : _saveRecipient,
                          onRemoveRecipient: _removeSavedRecipient,
                          directory: recipients,
                          onMyQr: () => setState(() => page = 'receiveQr'),
                          onScanQr: () => setState(() => page = 'scanQr'),
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
                      : tab == 3
                      ? AssistantScreen(
                          controller: assistant,
                          keyboardVisible:
                              MediaQuery.viewInsetsOf(context).bottom > 0,
                          onAction: (action) async {
                            try {
                              await _assistantAction(action);
                            } catch (_) {
                              if (mounted && assistant.current) {
                                assistant.navigationFailure();
                              }
                            }
                          },
                          onBack: () => _selectTab(0),
                          bottomClearance: 0,
                        )
                      : tab == 2
                      ? SettingsScreen(
                          session: widget.session,
                          onOpen: (target) =>
                              setState(() => page = 'settings:$target'),
                        )
                      : Center(
                          child: Text(
                            labels[tab],
                            key: ValueKey('placeholder-tab-$tab'),
                          ),
                        ),
                ),
                if (tab != 3)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: math.max(
                      tab == 1 ? 32 : 24,
                      MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: tab == 1 ? 400 : double.infinity,
                        ),
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: tab == 1 ? 1.3 : double.infinity,
                          child: KesorBottomBar(
                            selectedIndex: tab,
                            onSelected: _selectTab,
                            onAssistant: () => _selectTab(3),
                          ),
                        ),
                      ),
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
      if (page == 'transaction' || page == 'merchantTransaction') {
        (page == 'merchantTransaction' ? merchantHistory : history)
            .closeDetail();
        page = transactionReturnPage;
        transactionReturnPage = null;
      } else if (page == 'details' ||
          page == 'merchantDetails' ||
          page == 'open') {
        page = 'accounts';
      } else if (page != null) {
        // A transfer may have bookmarked its recipient.
        if (page == 'transfer') unawaited(_loadSavedRecipients());
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
      await Future.wait([
        model.refresh(),
        if (page == 'accounts') merchantModel.refresh(),
      ]);
    }
  }

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

  Widget _wallet(BuildContext context) => WalletAccountsScreen(
    model: model,
    merchantModel: merchantModel,
    onMerchantDetails: () => setState(() => page = 'merchantDetails'),
    greetingName:
        widget.session.identity?.firstName ??
        widget.session.identity?.username ??
        '',
    notices: _errors(),
    savedTransfer: transfers.saved == null
        ? null
        : transfers.saved!.unresolved
        ? 'A saved transfer has an unknown outcome. Open Transfer to recover it before starting another.'
        : 'A saved transfer result is ready to review.',
    balanceVisible: _homeBalanceVisible,
    onBalanceVisibilityChanged: (visible) =>
        setState(() => _homeBalanceVisible = visible),
    onBack: _back,
    onProfile: () => setState(() => page = 'profile'),
    onRefresh: _refresh,
    onTransfer: () => _openTransfer(null),
    onMyQr: () => setState(() => page = 'receiveQr'),
    onOpenAccounts:
        !model.ready ||
            model.opening ||
            model.uncertain ||
            model.storageError != null
        ? null
        : () => setState(() => page = 'open'),
    onDetails: () => setState(() => page = 'details'),
    onActivity: () => setState(() => page = 'history'),
    bottomBar: KesorBottomBar(
      selectedIndex: tab,
      onSelected: _selectTab,
      onAssistant: () => _selectTab(3),
    ),
  );

  List<Widget> _opening(BuildContext context) => [
    ..._errors(),
    if (pairs != null)
      PairOpeningPanel(
        model: pairs!,
        legacyPending:
            model.uncertain || !model.ready || model.storageError != null,
        onOpened: () {
          if (mounted) {
            setState(() {
              model.notice = tx(context, 'Accounts opened');
              page = 'accounts';
            });
          }
        },
      )
    else
      NoticePanel(
        tx(context, 'Account opening is unavailable. Try again later.'),
        error: true,
      ),
  ];
}
