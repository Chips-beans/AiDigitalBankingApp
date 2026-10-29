import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_preferences.dart';

import '../core/config/app_config.dart';
import '../features/auth/session_controller.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/continuation_pages.dart';
import '../features/auth/data/auth_gateway.dart';
import '../features/accounts/account_gateway.dart';
import '../features/accounts/creation_store.dart';
import '../features/accounts/presentation/accounts_shell.dart';
import '../features/transactions/transaction_gateway.dart';
import '../features/transactions/transfer_store.dart';
import '../shared/widgets/app_states.dart';
import 'app_theme.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({
    required this.session,
    required this.config,
    this.accountGateway,
    this.creationStore,
    this.transactionGateway,
    this.transferStore,
    this.preferences,
    super.key,
  });
  final SessionController session;
  final AppConfig config;
  final AccountGateway? accountGateway;
  final CreationStore? creationStore;
  final TransactionGateway? transactionGateway;
  final TransferStore? transferStore;
  final AppPreferences? preferences;
  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  late final AccountGateway accounts;
  late final AppPreferences preferences;
  late final CreationStore creationStore;
  late final TransactionGateway transactions;
  late final TransferStore transferStore;
  @override
  void initState() {
    super.initState();
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
    if (widget.preferences == null) preferences.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.expirePendingIfNeeded();
      if (widget.session.phase == SessionPhase.signedIn) {
        widget.session.refreshProfile();
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
            Expanded(child: child!),
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
                store: creationStore,
                transactions: transactions,
                transferStore: transferStore,
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
