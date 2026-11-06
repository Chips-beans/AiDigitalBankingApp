import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart' show HandoffFailure;

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
  appMismatch,
  unsupportedBuild,
  openFailed,
  storageUnavailable,
  serverUnavailable,
  rejected,
  invalidResponse,
}

enum MerchantAuthStage {
  unknown,
  configuration,
  storageRead,
  storageWrite,
  verifyCustomer,
  createAttempt,
  openCustomer,
  awaitApproval,
  exchange,
  identity,
  refresh,
  cancel,
  logout,
}

/// This is the only diagnostic information allowed into presentation/clipboard.
/// A closed allowlist prevents even a malicious server error string from copying
/// credentials or request data into a support report.
@immutable
class MerchantAuthDiagnostic {
  const MerchantAuthDiagnostic(this.stage, this.code, {this.httpStatus});
  final MerchantAuthStage stage;
  final String code;
  final int? httpStatus;
  static const _codes = {
    'PEER_MISSING',
    'PEER_SIGNATURE_MISMATCH',
    'HANDOFF_UNSUPPORTED_BUILD',
    'PEER_OPEN_FAILED',
    'HANDOFF_UNAVAILABLE',
    'INVALID_LINK',
    'INVALID_RESPONSE',
    'OFFLINE',
    'TIMEOUT',
    'STORAGE_UNAVAILABLE',
    'STORAGE_INVALID',
    'MERCHANT_AUTH_UNAVAILABLE',
    'MERCHANT_AUTH_EXPIRED',
    'MERCHANT_AUTH_DENIED',
    'MERCHANT_AUTH_CANCELLED',
    'MERCHANT_AUTH_INVALID',
    'MERCHANT_AUTH_USED',
    'MERCHANT_AUTH_RATE_LIMITED',
    'TOKEN_INVALID',
    'SESSION_INVALID',
    'REFRESH_REUSED',
    'ACCESS_DENIED',
    'AUTHENTICATION_FAILED',
    'INVALID_REQUEST',
    'VALIDATION_FAILED',
    'INTERNAL_ERROR',
    'AUDIT_UNAVAILABLE',
    'CONCURRENT_UPDATE',
    'REQUEST_FAILED',
    'RESOURCE_NOT_FOUND',
    'MERCHANT_SESSION_REQUIRED',
    'CUSTOMER_SESSION_REQUIRED',
    'UNKNOWN_ERROR',
    'EXCHANGE_RECOVERY_REQUIRED',
    'REFRESH_UNCERTAIN',
  };
  String get safeCode => _codes.contains(code) ? code : 'UNKNOWN_ERROR';
  String get supportText =>
      'Kesor Merchant sign-in\nStage: ${stage.name}\nCode: $safeCode'
      '${httpStatus != null && httpStatus! >= 100 && httpStatus! <= 599 ? '\nHTTP: $httpStatus' : ''}';
}

class MerchantAuthFailure implements Exception {
  const MerchantAuthFailure(this.issue, {this.diagnostic});
  final MerchantAuthIssue issue;
  final MerchantAuthDiagnostic? diagnostic;

  factory MerchantAuthFailure.fromHandoff(
    HandoffFailure error,
    MerchantAuthStage stage,
  ) {
    final issue = switch (error.code) {
      'PEER_MISSING' => MerchantAuthIssue.customerMissing,
      'PEER_SIGNATURE_MISMATCH' => MerchantAuthIssue.appMismatch,
      'HANDOFF_UNSUPPORTED_BUILD' => MerchantAuthIssue.unsupportedBuild,
      'PEER_OPEN_FAILED' ||
      'HANDOFF_UNAVAILABLE' => MerchantAuthIssue.openFailed,
      'OFFLINE' || 'TIMEOUT' => MerchantAuthIssue.offline,
      'MERCHANT_AUTH_EXPIRED' ||
      'TOKEN_INVALID' ||
      'SESSION_INVALID' ||
      'REFRESH_REUSED' => MerchantAuthIssue.expired,
      'MERCHANT_AUTH_DENIED' ||
      'MERCHANT_AUTH_CANCELLED' => MerchantAuthIssue.denied,
      'MERCHANT_AUTH_RATE_LIMITED' => MerchantAuthIssue.rateLimited,
      _ when error.status == 401 => MerchantAuthIssue.expired,
      _ when error.status == 429 => MerchantAuthIssue.rateLimited,
      _ when (error.status ?? 0) >= 500 => MerchantAuthIssue.serverUnavailable,
      'MERCHANT_AUTH_UNAVAILABLE' => MerchantAuthIssue.serverUnavailable,
      _ when (error.status ?? 0) >= 400 => MerchantAuthIssue.rejected,
      'INVALID_RESPONSE' || 'INVALID_LINK' => MerchantAuthIssue.invalidResponse,
      _ => MerchantAuthIssue.unavailable,
    };
    return MerchantAuthFailure(
      issue,
      diagnostic: MerchantAuthDiagnostic(
        stage,
        error.code,
        httpStatus: error.status,
      ),
    );
  }
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
  MerchantAuthDiagnostic? diagnostic;
  String get errorDetails =>
      (diagnostic ??
              const MerchantAuthDiagnostic(
                MerchantAuthStage.unknown,
                'UNKNOWN_ERROR',
              ))
          .supportText;

  void _failure(Object error, MerchantAuthStage stage) {
    final typed = error is MerchantAuthFailure
        ? error
        : error is HandoffFailure
        ? MerchantAuthFailure.fromHandoff(error, stage)
        : MerchantAuthFailure(
            MerchantAuthIssue.unavailable,
            diagnostic: MerchantAuthDiagnostic(stage, 'UNKNOWN_ERROR'),
          );
    failure = typed.issue;
    diagnostic =
        typed.diagnostic ?? MerchantAuthDiagnostic(stage, 'UNKNOWN_ERROR');
  }

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
    final generation = _generation;
    try {
      await (gateway as RestorableMerchantAuth).reopen();
      if (!_disposed &&
          generation == _generation &&
          phase == MerchantPhase.approving) {
        failure = null;
        diagnostic = null;
        notifyListeners();
      }
    } catch (error) {
      if (!_disposed &&
          generation == _generation &&
          phase == MerchantPhase.approving) {
        _failure(error, MerchantAuthStage.openCustomer);
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
    diagnostic = null;
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
      failure = null;
      diagnostic = null;
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
      _failure(error, MerchantAuthStage.unknown);
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
    } catch (error) {
      if (!_disposed) {
        _failure(error, MerchantAuthStage.cancel);
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
    } catch (error) {
      if (!_disposed) {
        _failure(error, MerchantAuthStage.logout);
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
    diagnostic = null;
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
