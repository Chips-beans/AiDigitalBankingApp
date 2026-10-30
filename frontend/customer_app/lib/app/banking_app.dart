import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_preferences.dart';

import '../core/config/app_config.dart';
import '../features/auth/session_controller.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/app_pin_page.dart';
import '../features/auth/presentation/continuation_pages.dart';
import '../features/auth/data/auth_gateway.dart';
import '../features/accounts/account_gateway.dart';
import '../features/analytics/analytics_gateway.dart';
import '../features/accounts/creation_store.dart';
import '../features/accounts/pair_opening.dart';
import '../features/accounts/presentation/accounts_shell.dart';
import '../features/home/presentation/locked_home_page.dart';
import '../features/transactions/transaction_gateway.dart';
import '../features/transactions/transfer_store.dart';
import '../features/transactions/recipient_favorites.dart';
import '../features/assistant/assistant_gateway.dart';
import '../features/assistant/assistant_store.dart';
import '../core/network/api_client.dart';
import '../shared/widgets/app_states.dart';
import 'app_theme.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({
    required this.session,
    required this.config,
    this.accountGateway,
    this.analyticsGateway,
    this.creationStore,
    this.pairOpeningStore,
    this.transactionGateway,
    this.transferStore,
    this.recipientFavorites,
    this.assistantGateway,
    this.assistantStore,
    this.preferences,
    super.key,
  });
  final SessionController session;
  final AppConfig config;
  final AccountGateway? accountGateway;
  final AnalyticsGateway? analyticsGateway;
  final CreationStore? creationStore;
  final PairOpeningStore? pairOpeningStore;
  final TransactionGateway? transactionGateway;
  final TransferStore? transferStore;
  final RecipientFavoritesStore? recipientFavorites;
  final AssistantGateway? assistantGateway;
  final AssistantPendingStore? assistantStore;
  final AppPreferences? preferences;
  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  late final AccountGateway accounts;
  late final AppPreferences preferences;
  late final CreationStore creationStore;
  late final PairOpeningStore pairOpeningStore;
  late final TransactionGateway transactions;
  late final TransferStore transferStore;
  late final RecipientFavoritesStore recipientFavorites;
  late final AssistantGateway assistantGateway;
  late final AssistantPendingStore assistantStore;
  ApiClient? assistantClient;
  Timer? _idleTimer;

  /// The customer tapped a feature on the masked Home, so show the PIN pad.
  bool _pinRequested = false;
  SessionPhase? _lastPhase;
  void _phaseChanged() {
    final phase = widget.session.phase;
    if (phase != _lastPhase) {
      _lastPhase = phase;
      // Every new lock starts on the masked Home again.
      if (phase != SessionPhase.pinLocked && _pinRequested) {
        setState(() => _pinRequested = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_phaseChanged);
    _idleTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => widget.session.checkIdle(),
    );
    preferences = widget.preferences ?? AppPreferences();
    accounts =
        widget.accountGateway ??
        (widget.config.isDemo
            ? DemoAccountGateway()
            : HttpAccountGateway(
                (widget.session.gateway as HttpAuthGateway).client,
              ));
    creationStore =
        widget.creationStore ??
        (kIsWeb || widget.config.isDemo
            ? MemoryCreationStore()
            : SecureCreationStore(
                '${widget.config.apiBaseUrl}|${widget.config.mode}',
              ));
    final auth = widget.session.gateway;
    assistantGateway =
        widget.assistantGateway ??
        (!widget.config.isDemo && auth is HttpAuthGateway
            ? HttpAssistantGateway(
                assistantClient = ApiClient(
                  widget.config,
                  timeout: const Duration(seconds: 35),
                ),
              )
            : UnavailableAssistantGateway());
    assistantStore =
        widget.assistantStore ??
        AssistantPendingStore(
          namespace: kIsWeb || widget.config.isDemo || auth is! HttpAuthGateway
              ? null
              : '${widget.config.apiBaseUrl}|${widget.config.mode}',
        );
    recipientFavorites =
        widget.recipientFavorites ??
        RecipientFavoritesStore(
          namespace: kIsWeb || widget.config.isDemo || auth is! HttpAuthGateway
              ? null
              : '${widget.config.apiBaseUrl}|${widget.config.mode}',
        );
    pairOpeningStore =
        widget.pairOpeningStore ??
        PairOpeningStore(
          namespace: kIsWeb || widget.config.isDemo || auth is! HttpAuthGateway
              ? null
              : '${widget.config.apiBaseUrl}|${widget.config.mode}',
        );
    transactions =
        widget.transactionGateway ??
        (!widget.config.isDemo && auth is HttpAuthGateway
            ? HttpTransactionGateway(auth.client)
            : PreviewTransactionGateway());
    transferStore =
        widget.transferStore ??
        (kIsWeb || widget.config.isDemo || auth is! HttpAuthGateway
            ? MemoryTransferStore()
            : SecureTransferStore(
                '${widget.config.apiBaseUrl}|${widget.config.mode}',
              ));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    widget.session.removeListener(_phaseChanged);
    assistantClient?.close();
    if (widget.preferences == null) preferences.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = widget.session;
    // The privacy cover still hides balances in the app switcher; the PIN is only
    // required again after [SessionController.idleLimit] away (user decision).
    if (state == AppLifecycleState.inactive) session.coverPrivateContent();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!session.trustedImageSelection) session.markBackground();
    }
    if (state == AppLifecycleState.resumed) {
      session.markForeground();
      session.uncoverPrivateContent();
      session.expirePendingIfNeeded();
      if (session.phase == SessionPhase.signedIn &&
          !session.trustedImageSelection) {
        session.refreshProfile();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => AppPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
        title: 'Digital Banking',
        debugShowCheckedModeBanner: false,
        locale: preferences.locale,
        supportedLocales: const [Locale('en'), Locale('km')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: preferences.themeMode,
        theme: AppTheme.build(Brightness.light, locale: preferences.locale),
        darkTheme: AppTheme.build(Brightness.dark, locale: preferences.locale),
        builder: (context, child) => Column(
          children: [
            if (widget.config.isDemo)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: Text(
                        'DEMO · Sample profile, accounts and activity',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.session,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    // Any touch counts as activity for the 3-minute idle lock.
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => widget.session.noteActivity(),
                      child: ExcludeSemantics(
                        excluding: widget.session.privacyCovered,
                        child: child!,
                      ),
                    ),
                    if (widget.session.privacyCovered)
                      const Positioned.fill(
                        child: AbsorbPointer(
                          child: ColoredBox(color: Color(0xFF0B1F35)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        home: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            final session = widget.session;
            if (session.phase == SessionPhase.starting) {
              return const LoadingPage();
            }
            if (session.phase == SessionPhase.storageError) {
              return LoadingPage(
                message: session.notice,
                onRetry: session.initialize,
              );
            }
            if (session.phase == SessionPhase.pinLocked) {
              // A configured PIN that only needs entering starts on the masked Home;
              // creating, confirming or recovering a PIN goes straight to the pad.
              final enterOnly =
                  (session.pinStage == PinStage.unlock ||
                      session.pinStage == PinStage.checking) &&
                  session.pinChallenge?.recoveryRequired != true &&
                  !session.pinResetting;
              if (enterOnly && !_pinRequested) {
                return LockedHomePage(
                  onUnlock: () => setState(() => _pinRequested = true),
                );
              }
              return AppPinPage(
                session,
                onCancel: enterOnly
                    ? () => setState(() => _pinRequested = false)
                    : null,
              );
            }
            if (session.phase == SessionPhase.signedIn) {
              if (session.linkingEmail) {
                return session.screen == AuthScreen.otp
                    ? OtpPage(session, demo: widget.config.isDemo)
                    : EmailContinuePage(session);
              }
              if (!session.identity!.profileComplete) {
                return InformationPage(session);
              }
              return AccountsShell(
                session: session,
                gateway: accounts,
                analyticsGateway:
                    widget.analyticsGateway ??
                    (widget.config.isDemo
                        ? DemoAnalyticsGateway()
                        : widget.session.gateway is HttpAuthGateway
                        ? HttpAnalyticsGateway(
                            (widget.session.gateway as HttpAuthGateway).client,
                          )
                        : UnavailableAnalyticsGateway()),
                store: creationStore,
                pairOpeningStore: pairOpeningStore,
                transactions: transactions,
                transferStore: transferStore,
                recipientFavorites: recipientFavorites,
                assistantGateway: assistantGateway,
                assistantStore: assistantStore,
                designPreview: widget.config.isDemo,
                transfersEnabled:
                    !kIsWeb &&
                    !widget.config.isDemo &&
                    transactions is! PreviewTransactionGateway,
                key: ValueKey(
                  'private-${session.identity!.userId}-${session.identity!.sessionId}',
                ),
              );
            }
            final topKey = ValueKey(
              session.screen == AuthScreen.otp
                  ? 'otp'
                  : session.registering
                  ? 'register'
                  : 'login',
            );
            return PopScope(
              canPop: !session.busy && session.screen == AuthScreen.welcome,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && !session.busy) session.back();
              },
              child: Navigator(
                pages: [
                  MaterialPage(
                    key: const ValueKey('welcome'),
                    child: ContinueWelcomePage(session),
                  ),
                  if (session.screen != AuthScreen.welcome)
                    MaterialPage(
                      key: ValueKey(session.registering ? 'register' : 'login'),
                      child:
                          session.screen == AuthScreen.email ||
                              session.screen == AuthScreen.otp
                          ? EmailContinuePage(session)
                          : CredentialsPage(
                              session,
                              register: session.registering,
                            ),
                    ),
                  if (session.screen == AuthScreen.otp)
                    MaterialPage(
                      key: const ValueKey('otp'),
                      child: OtpPage(session, demo: widget.config.isDemo),
                    ),
                ],
                onDidRemovePage: (page) {
                  // Ignore pages removed because controller state already changed.
                  if (page.key == topKey &&
                      session.screen != AuthScreen.welcome &&
                      !session.busy) {
                    session.back();
                  }
                },
              ),
            );
          },
        ),
      ),
    ),
  );
}
