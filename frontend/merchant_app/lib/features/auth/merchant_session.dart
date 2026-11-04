import 'package:flutter/foundation.dart';

enum MerchantPhase {
  signedOut,
  approving,
  shopRequired,
  ready,
  restricted,
  recoveryRequired,
}

@immutable
class MerchantShop {
  const MerchantShop({
    required this.id,
    required this.name,
    this.active = true,
  });
  final String id, name;
  final bool active;
}

@immutable
class MerchantIdentity {
  const MerchantIdentity({
    required this.ownerId,
    this.shop,
    this.recoveryRequired = false,
  });
  final int ownerId;
  final MerchantShop? shop;
  final bool recoveryRequired;
}

abstract interface class MerchantAuthGateway {
  Future<MerchantIdentity> authorize();
  Future<void> cancel();
  Future<void> signOut();
}

abstract interface class RestorableMerchantAuth implements MerchantAuthGateway {
  Future<MerchantIdentity?> restore();
  Future<MerchantIdentity> recover();
  Future<MerchantIdentity?> validate();
  Future<void> reopen();
}

/// Read-only approval timing for presentation; the server still enforces expiry.
abstract interface class MerchantApprovalTiming {
  Duration? get approvalRemaining;
}

/// Supplies the current Merchant access token to shop APIs, rotating it first
/// when it is about to expire. Never exposes refresh credentials.
abstract interface class MerchantAccess {
  Future<String> accessToken();
}

enum MerchantAuthIssue {
  unavailable,
  offline,
  expired,
  denied,
  customerMissing,
  uncertain,
  rateLimited,
}

class MerchantAuthFailure implements Exception {
  const MerchantAuthFailure(this.issue);
  final MerchantAuthIssue issue;
}

class MerchantAuthUnavailable extends MerchantAuthFailure {
  const MerchantAuthUnavailable() : super(MerchantAuthIssue.unavailable);
}

/// Fail closed until the audited M2/M3 backend and Android handoff are connected.
/// There is deliberately no local/demo sign-in or manufactured shop/token.
class UnavailableMerchantAuth implements MerchantAuthGateway {
  @override
  Future<MerchantIdentity> authorize() async =>
      throw const MerchantAuthUnavailable();
  @override
  Future<void> cancel() async {}
  @override
  Future<void> signOut() async {}
}

class MerchantSession extends ChangeNotifier {
  MerchantSession(this.gateway);
  final MerchantAuthGateway gateway;
  MerchantPhase phase = MerchantPhase.signedOut;
  MerchantIdentity? identity;
  MerchantAuthIssue? failure;
  Duration? get approvalRemaining => gateway is MerchantApprovalTiming
      ? (gateway as MerchantApprovalTiming).approvalRemaining
      : null;
  bool get unavailable => failure == MerchantAuthIssue.unavailable;
  int _generation = 0;
  bool _disposed = false, _running = false, _ending = false;
  bool get busy => _running || _ending;

  Future<void> initialize() async {
    if (gateway is! RestorableMerchantAuth) return;
    await _run(() => (gateway as RestorableMerchantAuth).restore());
  }

  Future<void> recover() async {
    if (gateway is RestorableMerchantAuth && phase == MerchantPhase.signedOut) {
      await _run(() => (gateway as RestorableMerchantAuth).recover());
    }
  }

  Future<void> validate() async {
    if (gateway is! RestorableMerchantAuth || identity == null || _disposed) {
      return;
    }
    await _run(
      () => (gateway as RestorableMerchantAuth).validate(),
      waiting: false,
    );
  }

  Future<void> reopen() async {
    if (gateway is! RestorableMerchantAuth ||
        phase != MerchantPhase.approving) {
      return;
    }
    try {
      await (gateway as RestorableMerchantAuth).reopen();
    } catch (_) {
      if (!_disposed) {
        failure = MerchantAuthIssue.unavailable;
        notifyListeners();
      }
    }
  }

  Future<void> signIn() async {
    if (phase != MerchantPhase.signedOut || _disposed) return;
    await _run(gateway.authorize);
  }

  Future<void> _run(
    Future<MerchantIdentity?> Function() action, {
    bool waiting = true,
  }) async {
    if (busy || _disposed) return;
    _running = true;
    final generation = ++_generation;
    failure = null;
    if (waiting) phase = MerchantPhase.approving;
    notifyListeners();
    try {
      final result = await action();
      if (_disposed || generation != _generation) return;
      if (result == null) {
        phase = MerchantPhase.signedOut;
        notifyListeners();
        return;
      }
      if (result.ownerId <= 0 ||
          (result.shop != null &&
              (result.shop!.id.isEmpty || result.shop!.name.trim().isEmpty))) {
        throw const MerchantAuthUnavailable();
      }
      identity = result;
      phase = result.recoveryRequired
          ? MerchantPhase.recoveryRequired
          : result.shop == null
          ? MerchantPhase.shopRequired
          : result.shop!.active
          ? MerchantPhase.ready
          : MerchantPhase.restricted;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      identity = null;
      failure = error is MerchantAuthFailure
          ? error.issue
          : MerchantAuthIssue.unavailable;
      phase = MerchantPhase.signedOut;
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  Future<void> cancel() async {
    if (_disposed || _ending) return;
    _ending = true;
    _clear();
    try {
      await gateway.cancel();
    } catch (_) {
      if (!_disposed) {
        failure = MerchantAuthIssue.offline;
        notifyListeners();
      }
    } finally {
      _ending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_disposed || _ending) return;
    _ending = true;
    _clear();
    try {
      await gateway.signOut();
    } catch (_) {
      if (!_disposed) {
        failure = MerchantAuthIssue.offline;
        notifyListeners();
      }
    } finally {
      _ending = false;
      if (!_disposed) notifyListeners();
    }
  }

  void expire() {
    if (_disposed) return;
    _clear(MerchantAuthIssue.expired);
  }

  void _clear([MerchantAuthIssue? issue]) {
    _generation++;
    identity = null;
    phase = MerchantPhase.signedOut;
    failure = issue;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    identity = null;
    super.dispose();
  }
}
