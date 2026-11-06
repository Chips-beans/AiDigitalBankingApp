import 'dart:math' as math;

import '../../../app/app_preferences.dart';
import '../../../core/network/api_client.dart';
import '../../auth/session_controller.dart';
import '../../auth/data/auth_gateway.dart';
import '../../transactions/recipient_favorites.dart';
import '../home_unlock_target.dart';
import '../home_preview_gateway.dart';

import 'package:flutter/material.dart';

import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../home_data.dart';
import 'kesor_home_screen.dart' show KesorHomeScreen;

/// Limited ticket-authenticated Home preview. Money values never enter this view.
class LockedHomePage extends StatefulWidget {
  const LockedHomePage({
    required this.onUnlock,
    required this.session,
    required this.favorites,
    this.previewGateway,
    super.key,
  });
  final ValueChanged<HomeUnlockTarget> onUnlock;
  final SessionController session;
  final RecipientFavoritesStore favorites;
  final HomePreviewGateway? previewGateway;
  @override
  State<LockedHomePage> createState() => _LockedHomePageState();
}

class _LockedHomePageState extends State<LockedHomePage>
    with WidgetsBindingObserver {
  KesorHomeData data = masked;
  bool loading = true;
  String? error;
  int generation = 0;
  String tr(String en, String km) =>
      AppPreferences.maybeOf(context)?.isKhmer == true ? km : en;
  void unlock([
    String? page,
    int tab = 0,
    String? reference,
    String? recipient,
  ]) => widget.onUnlock(
    HomeUnlockTarget(
      page,
      tab: tab,
      reference: reference,
      recipient: recipient,
    ),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    ++generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  Future<void> refresh() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final challenge = widget.session.pinChallenge;
      if (challenge == null || widget.session.pinStage == PinStage.checking) {
        return;
      }
      final gateway = widget.session.gateway;
      final entries = <HomeTransaction>[];
      final preview =
          widget.previewGateway ??
          (gateway is HttpAuthGateway
              ? HttpHomePreviewGateway(gateway.client)
              : null);
      final rows =
          await preview?.load(challenge.ticket) ?? <HomePreviewEntry>[];
      if (!mounted || request != generation) return;
      for (final row in rows) {
        final date = row.createdAt.toLocal();
        final status = switch (row.status) {
          'SUCCESS' => '',
          'FAILED' => tr(' · Failed', ' · បរាជ័យ'),
          'PENDING' => tr(' · Pending', ' · កំពុងរង់ចាំ'),
          _ => tr(' · Reversed', ' · បានបង្វិលត្រឡប់'),
        };
        final name = row.direction == 'INTERNAL'
            ? tr('Between your accounts', 'ផ្ទេររវាងគណនីរបស់អ្នក')
            : row.name;
        entries.add(
          HomeTransaction(
            name: name + status,
            time:
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            amount: '••••',
            incoming: row.direction == 'INCOMING',
            internal: row.direction == 'INTERNAL',
            reference: row.reference,
            dateLabel:
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            previousDay: true,
          ),
        );
      }
      final favorites = await widget.favorites.read(challenge.userId);
      final seen = <String>{};
      if (!mounted ||
          request != generation ||
          widget.session.pinChallenge?.ticket != challenge.ticket) {
        return;
      }
      setState(
        () => data = KesorHomeData(
          khrBalance: '••••',
          usdBalance: r'$••••',
          transactions: entries,
          recipients: favorites
              .where((f) => f.manual && seen.add(f.number))
              .map(
                (f) => HomeRecipient(
                  f.name ?? '•••• ${f.number.substring(f.number.length - 4)}',
                  accountNumber: f.number,
                ),
              )
              .toList(),
        ),
      );
    } catch (failure) {
      if (failure is ApiFailure &&
          failure.status == 401 &&
          mounted &&
          request == generation) {
        if (mounted && request == generation) {
          setState(() => data = masked);
        }
        await widget.session.restorePinStatus();
      }
      if (mounted && request == generation) {
        setState(
          () => error = tr(
            'Preview unavailable. Pull down to retry.',
            'មិនអាចផ្ទុកបាន សូមព្យាយាមម្ដងទៀត។',
          ),
        );
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  static const masked = KesorHomeData(khrBalance: '••••', usdBalance: r'$••••');

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('locked-home'),
    backgroundColor: AppColors.of(context).background,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
        child: Stack(
          children: [
            Positioned.fill(
              child: KesorHomeScreen(
                showNavigation: false,
                balanceVisible: false,
                data: data,
                loading: loading,
                errorMessage: error,
                onRefresh: refresh,
                onProtectedInteraction: () => unlock('favorites'),
                onInbox: () => unlock('inbox'),
                onBalanceVisibilityChanged: (_) => unlock(),
                onAccounts: () => unlock('accounts'),
                onTransfer: () => unlock('transfer'),
                onMyQr: () => unlock('receiveQr'),
                onScanQr: () => unlock('scanQr'),
                onActivity: () => unlock('history'),
                onProfile: () => unlock('profile'),
                onTransaction: (entry) =>
                    unlock('transaction', 0, entry.reference),
                onRecipient: (number, _) => unlock('transfer', 0, null, number),
                onAddRecipient: () => unlock('addFavorite'),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: math.max(24, MediaQuery.paddingOf(context).bottom),
              child: KesorBottomBar(
                selectedIndex: 0,
                onSelected: (index) {
                  if (index != 0) unlock(null, index);
                },
                onAssistant: () => unlock(null, 3),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
