import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../home_data.dart' show KesorHomeData;
import 'kesor_home_screen.dart' show KesorHomeScreen;

/// Home before the first PIN entry (user decision, 31 Oct 2026). The server issues
/// no access token until the PIN is verified, so this shows the Home frame with
/// masked balances and no accounts, recipients or transactions. Any feature tap asks
/// for the PIN via [onUnlock].
class LockedHomePage extends StatelessWidget {
  const LockedHomePage({required this.onUnlock, super.key});
  final VoidCallback onUnlock;

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
                data: masked,
                onBalanceVisibilityChanged: (_) => onUnlock(),
                onAccounts: onUnlock,
                onTransfer: onUnlock,
                onMyQr: onUnlock,
                onScanQr: onUnlock,
                onActivity: onUnlock,
                onProfile: onUnlock,
                onTransaction: (_) => onUnlock(),
                onRecipient: (_, _) => onUnlock(),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: math.max(24, MediaQuery.paddingOf(context).bottom),
              child: KesorBottomBar(
                selectedIndex: 0,
                onSelected: (index) {
                  if (index != 0) onUnlock();
                },
                onAssistant: onUnlock,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
