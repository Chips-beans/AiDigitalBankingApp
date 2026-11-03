import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';

/// Sound and vibration for a new payment. Replaceable so tests stay silent.
abstract interface class AlertEffects {
  void chime();
  void vibrate();
}

class SystemAlertEffects implements AlertEffects {
  const SystemAlertEffects();
  @override
  void chime() => unawaited(SystemSound.play(SystemSoundType.alert));
  @override
  void vibrate() => unawaited(HapticFeedback.mediumImpact());
}

/// Payments the owner has not seen yet, shown as one in-app banner.
@immutable
class FeedBanner {
  const FeedBanner(this.sequence, this.payments);

  /// Increases with every banner so a late auto-dismiss never closes a newer one.
  final int sequence;

  /// Newest first.
  final List<ShopReceipt> payments;
}

/// Watches the shop dashboard while the app is open and reports new payments.
///
/// This is deliberately not push: nothing runs while the app is paused, covered or
/// signed out. Payments that arrive meanwhile are reported when the app resumes.
/// The first successful load only records what already exists, so history never
/// alerts. Lost or failed polls change nothing about money; the server is the source
/// of truth and the next poll simply asks again.
class PaymentFeedController extends ChangeNotifier {
  PaymentFeedController(
    this.gateway, {
    this.onNewPayments,
    this.onExpired,
    this.effects = const SystemAlertEffects(),
    this.soundEnabled = _on,
    this.vibrationEnabled = _on,
    this.interval = const Duration(seconds: 10),
    this.slowInterval = const Duration(seconds: 30),
    this.failuresBeforeSlowdown = 3,
  });

  static bool _on() => true;
  static const _remembered = 300;

  final MerchantCollectGateway gateway;
  final void Function(List<ShopReceipt> payments)? onNewPayments;
  final VoidCallback? onExpired;
  final AlertEffects effects;
  final bool Function() soundEnabled, vibrationEnabled;
  final Duration interval, slowInterval;
  final int failuresBeforeSlowdown;

  FeedBanner? banner;

  final _seen = <String>{};
  Timer? _timer;
  bool _running = false, _seeded = false, _polling = false, _disposed = false;
  int _failures = 0, _generation = 0, _sequence = 0;

  bool get running => _running;
  int get failures => _failures;

  /// The wait before the next poll: slower after repeated failures.
  Duration get delay =>
      _failures >= failuresBeforeSlowdown ? slowInterval : interval;

  /// Starts or stops watching. Stopping drops any poll still in flight.
  set running(bool value) {
    if (_disposed || value == _running) return;
    _running = value;
    _generation++;
    _timer?.cancel();
    if (value) unawaited(poll());
  }

  /// A payment already shown elsewhere (the Collect screen) must not alert again.
  void markSeen(String reference) => _remember(reference);

  void dismiss([int? sequence]) {
    if (banner == null || (sequence != null && banner!.sequence != sequence)) {
      return;
    }
    banner = null;
    _notify();
  }

  Future<void> poll() async {
    if (_polling || _disposed || !_running) return;
    _polling = true;
    final generation = _generation;
    try {
      final dashboard = await gateway.dashboard();
      if (_disposed || generation != _generation) return;
      _failures = 0;
      final fresh = [
        for (final receipt in dashboard.recent)
          if (!_seen.contains(receipt.reference)) receipt,
      ];
      final first = !_seeded;
      _seeded = true;
      for (final receipt in dashboard.recent) {
        _remember(receipt.reference);
      }
      if (!first && fresh.isNotEmpty) _announce(fresh);
    } on ShopFailure catch (e) {
      if (_disposed || generation != _generation) return;
      if (e.expired) {
        _running = false;
        onExpired?.call();
        return;
      }
      _failures++;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _failures++;
    } finally {
      _polling = false;
      if (!_disposed && _running) {
        // A poll that finished after a stop and a quick restart was dropped as stale, and the
        // restart's own poll was skipped while it was in flight: ask again at once.
        _timer?.cancel();
        _timer = Timer(
          generation == _generation ? delay : Duration.zero,
          () => unawaited(poll()),
        );
      }
    }
  }

  void _announce(List<ShopReceipt> fresh) {
    banner = FeedBanner(++_sequence, fresh);
    if (soundEnabled()) effects.chime();
    if (vibrationEnabled()) effects.vibrate();
    onNewPayments?.call(fresh);
    _notify();
  }

  void _remember(String reference) {
    _seen.remove(reference);
    _seen.add(reference);
    while (_seen.length > _remembered) {
      _seen.remove(_seen.first);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _seen.clear();
    super.dispose();
  }
}
