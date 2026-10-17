import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/session_controller.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../shared/widgets/app_states.dart';
import 'app_theme.dart';

class BankingApp extends StatefulWidget {
  const BankingApp({required this.session, required this.config, super.key});
  final SessionController session;
  final AppConfig config;
  @override
  State<BankingApp> createState() => _BankingAppState();
}

class _BankingAppState extends State<BankingApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Digital Banking',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(Brightness.light),
    darkTheme: AppTheme.build(Brightness.dark),
    builder: (context, child) => Column(
      children: [
        if (widget.config.isDemo)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: Text('DEMO · Sample profile · No banking services'),
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
        if (session.phase == SessionPhase.starting) return const LoadingPage();
        if (session.phase == SessionPhase.storageError) {
          return LoadingPage(
            message: session.notice,
            onRetry: session.initialize,
          );
        }
        if (session.phase == SessionPhase.signedIn) {
          return SignedInPage(session, key: const ValueKey('private-session'));
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
                child: WelcomePage(session),
              ),
              if (session.screen != AuthScreen.welcome)
                MaterialPage(
                  key: ValueKey(session.registering ? 'register' : 'login'),
                  child: CredentialsPage(
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
  );
}
