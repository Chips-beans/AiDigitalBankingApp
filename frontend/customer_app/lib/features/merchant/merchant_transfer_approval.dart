import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../auth/session_controller.dart';
import 'merchant_approval.dart' show failureCode;

/// Approves one Merchant owner transfer (M8): a shop's business wallet to the owner's own
/// wallet. It mirrors the sign-in coordinator but keeps its own link, storage slot and state, so
/// the two kinds of request can never be confused. The server picks the destination; this app
/// only shows the exact intent and sends fresh PIN digits for it.
///
/// An approval executes the transfer on the server in one step, so a lost response is resolved by
/// reloading the request: it is never approved again automatically.
class MerchantTransferApproval extends ChangeNotifier {
  MerchantTransferApproval(
    this.session,
    this.api,
    this.store, {
    NativeHandoff? native,
    DateTime Function()? clock,
    this.blocked,
  }) : native = native ?? const NativeHandoff(),
       clock = clock ?? DateTime.now;
  final SessionController session;
  final HandoffApi api;
  final HandoffStore store;
  final NativeHandoff native;
  final DateTime Function() clock;

  /// True while another request (sign-in) is active; a transfer link is then left untaken.
  final bool Function()? blocked;

  /// id, handoff, until, owner, callback, outcome.
  Map<String, dynamic>? pending, details;
  String? message;
  bool busy = false, disposed = false, _polling = false, storageBlocked = false;
  int _generation = 0;
  Timer? _timer;
  Future<void> _writes = Future.value();

  bool get hasRequest => pending != null;
  bool get unlocked =>
      session.phase == SessionPhase.signedIn &&
      session.identity?.profileComplete == true &&
      !session.privacyCovered;
  bool get canDecide =>
      unlocked &&
      details?['status'] == 'PENDING' &&
      !busy &&
      !storageBlocked &&
      pending?['callback'] == null;
  bool get canReturn =>
      pending?['callback'] != null &&
      unlocked &&
      !busy &&
      !storageBlocked &&
      pending?['owner'] == session.identity?.userId;

  /// COMPLETED, FAILED or DENIED once the server has answered; null before.
  String? get outcome => pending?['outcome'] as String?;

  /// Time left to approve, by the server's expiry carried onto this device's clock.
  Duration get remaining {
    final until = pending == null ? null : DateTime.tryParse(pending!['until']);
    if (until == null) return Duration.zero;
    final left = until.difference(clock());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _save() {
    final raw = pending == null ? null : jsonEncode(pending);
    final flight = _writes.catchError((Object _) {}).then((_) async {
      try {
        await store.write('transfer-approval', raw);
        storageBlocked = false;
      } catch (_) {
        storageBlocked = true;
        rethrow;
      }
    });
    _writes = flight;
    return flight;
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final raw = await store.read('transfer-approval');
      if (raw != null) {
        pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {
      message = 'STORAGE_UNAVAILABLE';
      storageBlocked = true;
    }
    if (disposed) return;
    session.addListener(_sessionChanged);
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(poll()),
    );
    await poll();
  }

  void _sessionChanged() {
    if (!unlocked) {
      // A lock/background invalidates visible details and fresh PIN work, not the request.
      details = null;
      if (!busy) ++_generation;
    }
    if (pending?['owner'] != null && session.phase == SessionPhase.signedOut) {
      unawaited(discard());
    }
    _emit();
  }

  Future<void> poll() async {
    if (_polling || disposed) return;
    _polling = true;
    try {
      // A request that is already active, or a sign-in in progress, is never replaced.
      if (pending == null && !storageBlocked && blocked?.call() != true) {
        final raw = await native.takeTransfer();
        if (disposed) return;
        if (raw != null) await _accept(raw);
      }
      if (pending != null &&
          !DateTime.parse(pending!['until']).isAfter(clock())) {
        final answered = pending!['callback'] != null;
        await discard();
        if (!answered) message = 'OWNER_TRANSFER_EXPIRED';
        _emit();
        return;
      }
      if (pending != null &&
          unlocked &&
          details == null &&
          pending!['callback'] == null &&
          !busy &&
          message == null) {
        await loadDetails();
      }
    } catch (_) {
      if (!disposed) {
        message = 'STORAGE_UNAVAILABLE';
        _emit();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _accept(String raw) async {
    try {
      final fields = exactLink(raw, transferApprovalBase, {
        'intentId',
        'handoffToken',
      });
      if (!attemptId(fields['intentId']) ||
          !credential(fields['handoffToken'])) {
        throw const HandoffFailure('INVALID_LINK');
      }
      pending = {
        'id': fields['intentId'],
        'handoff': fields['handoffToken'],
        // Refined to the server's own expiry once the details load.
        'until': clock().add(const Duration(minutes: 15)).toIso8601String(),
      };
      ++_generation;
      details = null;
      message = null;
      await _save();
      _emit();
    } on HandoffFailure {
      /* Untrusted links never become a request. */
    }
  }

  Future<void> loadDetails() async {
    if (!unlocked || pending == null || busy) return;
    final p = pending!, generation = _generation;
    busy = true;
    message = null;
    _emit();
    try {
      if (p['owner'] != null && p['owner'] != session.identity!.userId) {
        throw const HandoffFailure('OWNER_TRANSFER_INVALID');
      }
      final data = await session.authorizedRead(
        (access) => api.request(
          'GET',
          '/merchant-transfers/${p['id']}',
          access: access,
          handoff: p['handoff'],
        ),
      );
      if (disposed || generation != _generation || pending != p || !unlocked) {
        return;
      }
      if (!_validDetails(data, p['id'])) {
        throw const HandoffFailure('INVALID_RESPONSE');
      }
      details = Map<String, dynamic>.from(data as Map);
      p['owner'] = session.identity!.userId;
      final left = DateTime.parse(data['expiresAt'])
          .difference(DateTime.parse(data['serverTime']));
      final until = clock().add(left);
      if (until.isBefore(DateTime.parse(p['until']))) {
        p['until'] = until.toIso8601String();
      }
      await _save();
    } catch (e) {
      if (!disposed && generation == _generation) {
        message = failureCode(e);
        // The request itself is over; there is nothing left to approve.
        if (const {
          'OWNER_TRANSFER_EXPIRED',
          'OWNER_TRANSFER_CANCELLED',
          'OWNER_TRANSFER_DENIED',
          'OWNER_TRANSFER_FAILED',
          'OWNER_TRANSFER_COMPLETED',
        }.contains(message)) {
          details = null;
        }
      }
    } finally {
      if (!disposed) {
        busy = false;
        _emit();
      }
    }
  }

  static final _masked = RegExp(r'^•••• [0-9]{4}$');
  static bool _validDetails(dynamic data, String id) =>
      data is Map &&
      data['intentId'] == id &&
      data['merchantPackage'] == merchantPackage &&
      data['shopName'] is String &&
      data['sourceAccount'] is String &&
      _masked.hasMatch(data['sourceAccount']) &&
      data['destinationAccount'] is String &&
      _masked.hasMatch(data['destinationAccount']) &&
      (data['currency'] == 'KHR' || data['currency'] == 'USD') &&
      data['amount'] is String &&
      RegExp(r'^[0-9]+(\.[0-9]{2})?$').hasMatch(data['amount']) &&
      data['status'] == 'PENDING' &&
      DateTime.tryParse('${data['expiresAt']}') != null &&
      DateTime.tryParse('${data['serverTime']}') != null;

  /// Approves with fresh [pin] digits, or declines when [pin] is null.
  Future<void> decide({String? pin}) async {
    if (!canDecide || (pin != null && !RegExp(r'^[0-9]{4}$').hasMatch(pin))) {
      return;
    }
    final p = pending!, generation = _generation;
    busy = true;
    message = null;
    _emit();
    try {
      await native.verify();
      if (generation != _generation || !unlocked) return;
      final data = await session.authorizedMutation(
        (access) => api.request(
          'POST',
          '/merchant-transfers/${p['id']}/${pin == null ? 'deny' : 'approve'}',
          access: access,
          body: {'handoffToken': p['handoff'], 'pin': ?pin},
        ),
      );
      if (disposed || generation != _generation || pending != p || !unlocked) {
        return;
      }
      final status = _checkedOutcome(data, p['id'], approving: pin != null);
      p['callback'] = data['callbackUri'];
      p['outcome'] = status;
      details = null;
      await _save();
      // A finished transfer returns to the shop at once; a failed one waits for the owner.
      if (status != 'FAILED') {
        await native.openTransfer(p['callback']);
        await discard();
      }
    } catch (e) {
      if (!disposed && generation == _generation) {
        message = failureCode(e);
        // The server PIN budget is authoritative; re-enter the existing Customer gate.
        if (message == 'PIN_RECOVERY_REQUIRED' || message == 'PIN_REQUIRED') {
          session.lockApp();
        }
        if (!const {
          'PIN_INVALID',
          'PEER_MISSING',
          'HANDOFF_UNAVAILABLE',
          'OFFLINE',
          'TIMEOUT',
        }.contains(message)) {
          details = null;
        }
        // A lost response may still have posted; the owner reloads the request to find out.
        if (message == 'OFFLINE' || message == 'TIMEOUT') details = null;
      }
    } finally {
      if (!disposed) {
        busy = false;
        _emit();
      }
    }
  }

  String _checkedOutcome(dynamic data, String id, {required bool approving}) {
    if (data is! Map ||
        data['intentId'] != id ||
        data['merchantPackage'] != merchantPackage ||
        data['callbackUri'] is! String) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    final status = data['status'];
    final allowed = approving
        ? const ['COMPLETED', 'FAILED']
        : const ['DENIED'];
    if (!allowed.contains(status)) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    final fields = exactLink(
      data['callbackUri'],
      transferCallbackBase,
      status == 'COMPLETED'
          ? {'intentId', 'state'}
          : {'intentId', 'state', 'error'},
    );
    if (fields['intentId'] != id ||
        !credential(fields['state']) ||
        (status == 'DENIED' && fields['error'] != 'access_denied') ||
        (status == 'FAILED' && fields['error'] != 'failed')) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    return status as String;
  }

  Future<void> returnToMerchant() async {
    if (!canReturn) return;
    busy = true;
    _emit();
    try {
      await native.openTransfer(pending!['callback']);
      await discard();
    } catch (e) {
      message = failureCode(e);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> discard() async {
    ++_generation;
    pending = null;
    details = null;
    message = null;
    try {
      await _save();
    } catch (_) {
      message = 'STORAGE_UNAVAILABLE';
    }
    _emit();
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    ++_generation;
    _timer?.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
