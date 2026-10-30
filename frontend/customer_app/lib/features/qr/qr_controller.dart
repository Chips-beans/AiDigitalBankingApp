import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../shared/money.dart';
import '../accounts/account_gateway.dart';
import '../auth/session_controller.dart';
import 'qr_gateway.dart';

class QrController extends ChangeNotifier {
  QrController(
    this.session,
    this.gateway, {
    this.pollInterval = const Duration(seconds: 3),
    this.onPaid,
  }) : _user = session.identity!.userId,
       _session = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final QrGateway gateway;
  final Duration pollInterval;
  final Future<void> Function()? onPaid;
  final int _user;
  final String _session;
  bool _disposed = false,
      _active = true,
      _visible = true,
      busy = false,
      isPaid = false,
      _polling = false;
  int _generation = 0;
  Timer? _timer;
  AccountQr? code;
  QrPreview? preview;
  ApiFailure? error;
  bool get current =>
      !_disposed &&
      _active &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!current && _active) {
      _active = false;
      _generation++;
      _timer?.cancel();
      code = null;
      preview = null;
      error = null;
      busy = false;
      _emit();
    }
  }

  void setVisible(bool visible) {
    _visible = visible;
    _timer?.cancel();
    if (visible && current && code?.dynamic == true && !isPaid) _schedule();
  }

  Future<void> generate(BankAccount account, Money? amount) async {
    if (!current || busy) return;
    final generation = ++_generation;
    busy = true;
    code = null;
    error = null;
    isPaid = false;
    _timer?.cancel();
    _emit();
    try {
      final next = await session.authorizedMutation(
        (token) => gateway.generate(token, account, amount),
      );
      if (!current || generation != _generation) return;
      code = next;
      if (_visible && next.dynamic) _schedule();
    } catch (e) {
      if (current && generation == _generation) {
        error = e is ApiFailure
            ? e
            : const ApiFailure(
                'QR_UNAVAILABLE',
                'QR could not be loaded. Try again.',
              );
      }
    } finally {
      if (current && generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> scan(String payload) async {
    if (!current || busy || preview != null) return false;
    final generation = ++_generation;
    busy = true;
    error = null;
    _emit();
    try {
      final next = await session.authorizedRead(
        (token) => gateway.preview(token, payload),
      );
      if (!current || generation != _generation) return false;
      if (next.paid) {
        throw const ApiFailure(
          'PAYMENT_ALREADY_COMPLETED',
          'This request has already been paid.',
        );
      }
      preview = next;
      return true;
    } catch (e) {
      if (current && generation == _generation) {
        error = e is ApiFailure
            ? e
            : const ApiFailure(
                'UNSUPPORTED_QR',
                'Only registered Kesor QR codes are supported.',
              );
      }
      return false;
    } finally {
      if (current && generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  void clearPreview() {
    _generation++;
    preview = null;
    error = null;
    _emit();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(pollInterval, _poll);
  }

  Future<void> _poll() async {
    final code = this.code, generation = _generation;
    if (!current || !_visible || code == null || !code.dynamic || isPaid) {
      return;
    }
    if (_polling) {
      _schedule();
      return;
    }
    _polling = true;
    try {
      final paid = await session.authorizedRead(
        (token) => gateway.paid(token, code.hash),
      );
      if (current && _visible && generation == _generation) {
        isPaid = paid;
        error = null;
        _emit();
        if (paid) await onPaid?.call();
      }
    } catch (e) {
      if (current && _visible && generation == _generation) {
        error = e is ApiFailure
            ? e
            : const ApiFailure(
                'QR_UNAVAILABLE',
                'Payment status could not refresh.',
              );
        _emit();
      }
    } finally {
      _polling = false;
      if (current && _visible && generation == _generation && !isPaid) {
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
