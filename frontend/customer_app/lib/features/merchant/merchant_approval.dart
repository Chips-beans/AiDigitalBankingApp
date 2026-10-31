import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';

class MerchantApproval extends ChangeNotifier {
  MerchantApproval(
    this.session,
    this.api,
    this.store, {
    NativeHandoff? native,
    DateTime Function()? clock,
  }) : native = native ?? const NativeHandoff(),
       clock = clock ?? DateTime.now;
  final SessionController session;
  final HandoffApi api;
  final HandoffStore store;
  final NativeHandoff native;
  final DateTime Function() clock;
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
  Future<void> _save() {
    final raw = pending == null ? null : jsonEncode(pending);
    final flight = _writes.catchError((Object _) {}).then((_) async {
      try {
        await store.write('approval', raw);
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
      final raw = await store.read('approval');
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
      final raw = await native.take();
      if (disposed) return;
      if (raw != null && pending == null && !storageBlocked) {
        try {
          final fields = exactLink(raw, approvalBase, {
            'attemptId',
            'handoffToken',
          });
          if (!attemptId(fields['attemptId']) ||
              !credential(fields['handoffToken'])) {
            throw const HandoffFailure('INVALID_LINK');
          }
          pending = {
            'id': fields['attemptId'],
            'handoff': fields['handoffToken'],
            'until': clock()
                .add(const Duration(seconds: 120))
                .toIso8601String(),
          };
          ++_generation;
          details = null;
          message = null;
          await _save();
          _emit();
        } on HandoffFailure {
          /* Untrusted intents never replace active approval. */
        }
      }
      if (pending != null &&
          !DateTime.parse(pending!['until']).isAfter(clock())) {
        await discard();
        message = 'MERCHANT_AUTH_EXPIRED';
        _emit();
        return;
      }
      if (pending != null &&
          unlocked &&
          details == null &&
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

  Future<void> loadDetails() async {
    if (!unlocked || pending == null || busy) return;
    final p = pending!, generation = _generation;
    busy = true;
    message = null;
    _emit();
    try {
      if (p['owner'] != null && p['owner'] != session.identity!.userId) {
        throw const HandoffFailure('MERCHANT_AUTH_INVALID');
      }
      final data = await session.authorizedRead(
        (access) => api.request(
          'GET',
          '/merchant-auth/attempts/${p['id']}',
          access: access,
          handoff: p['handoff'],
        ),
      );
      if (disposed || generation != _generation || pending != p || !unlocked) {
        return;
      }
      if (data is! Map ||
          data['attemptId'] != p['id'] ||
          data['merchantPackage'] != merchantPackage ||
          data['clientName'] is! String ||
          data['deviceName'] is! String ||
          ![
            'PENDING',
            'APPROVED',
            'CONSUMED',
            'DENIED',
            'CANCELLED',
            'EXPIRED',
          ].contains(data['status'])) {
        throw const HandoffFailure('INVALID_RESPONSE');
      }
      details = Map<String, dynamic>.from(data);
      p['owner'] = session.identity!.userId;
      final until = DateTime.parse(data['expiresAt']);
      if (until.isBefore(DateTime.parse(p['until']))) {
        p['until'] = until.toIso8601String();
      }
      await _save();
    } catch (e) {
      if (!disposed && generation == _generation) message = failureCode(e);
    } finally {
      if (!disposed) {
        busy = false;
        _emit();
      }
    }
  }

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
          '/merchant-auth/attempts/${p['id']}/${pin == null ? 'deny' : 'approve'}',
          access: access,
          body: {'handoffToken': p['handoff'], 'pin': ?pin},
        ),
      );
      if (disposed || generation != _generation || pending != p || !unlocked) {
        return;
      }
      if (data is! Map ||
          data['merchantPackage'] != merchantPackage ||
          data['callbackUri'] is! String) {
        throw const HandoffFailure('INVALID_RESPONSE');
      }
      final fields = exactLink(
        data['callbackUri'],
        callbackBase,
        pin == null ? {'state', 'error'} : {'state', 'code'},
      );
      if (!credential(fields['state']) ||
          (pin == null
              ? fields['error'] != 'access_denied'
              : !credential(fields['code']))) {
        throw const HandoffFailure('INVALID_RESPONSE');
      }
      p['callback'] = data['callbackUri'];
      details = null;
      await _save();
      await native.open(p['callback']);
      await discard();
    } catch (e) {
      if (!disposed && generation == _generation) {
        message = failureCode(e);
        // Server PIN budget is authoritative; re-enter the existing Customer gate.
        if (message == 'PIN_RECOVERY_REQUIRED' || message == 'PIN_REQUIRED') {
          session.lockApp();
        }
        if (![
          'PIN_INVALID',
          'PEER_MISSING',
          'HANDOFF_UNAVAILABLE',
        ].contains(message)) {
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

  Future<void> returnToMerchant() async {
    if (!canReturn) return;
    busy = true;
    _emit();
    try {
      await native.open(pending!['callback']);
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

String failureCode(Object e) => e is HandoffFailure
    ? e.code
    : e is ApiFailure
    ? e.code
    : 'REQUEST_FAILED';
