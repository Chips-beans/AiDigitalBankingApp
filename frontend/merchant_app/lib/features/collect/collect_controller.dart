import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../shop/merchant_shop.dart';
import 'merchant_collect.dart';

/// One fixed-amount request at a time.
///
/// Only the server decides that money arrived: the screen shows PAID solely from a
/// server status. Lost responses keep the same idempotency key, and the active
/// request ID is saved so a restarted app resumes watching it instead of losing a
/// payment confirmation.
class CollectController extends ChangeNotifier {
  CollectController(
    this.gateway,
    this.store, {
    this.ownerId = 0,
    this.onPaid,
    this.onExpired,
    this.pollEvery = const Duration(seconds: 2),
    Stopwatch Function()? stopwatch,
  }) : _stopwatch = (stopwatch ?? Stopwatch.new)();

  final MerchantCollectGateway gateway;
  final HandoffStore store;
  final int ownerId;
  final VoidCallback? onPaid, onExpired;
  final Duration pollEvery;

  PaymentRequest? request;
  ShopFailure? failure;
  bool creating = false, cancelling = false;

  /// Offline or uncertain while waiting; the request may still be paid.
  bool reconnecting = false;

  String? _pendingKey;
  String? _pendingBody;
  Timer? _poll;
  final Stopwatch _stopwatch;
  Duration _remainingAtFetch = Duration.zero;
  bool _disposed = false, _polling = false;

  String get _slot => 'collect-$ownerId';

  /// Time left on the server's clock, counted down locally since the last fetch.
  Duration get remaining {
    final left = _remainingAtFetch - _stopwatch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  bool get waiting => request?.status == RequestStatus.waiting;

  Future<void> resume() async {
    try {
      final id = await store.read(_slot);
      if (id == null || request != null) return;
      _accept(await gateway.requestStatus(id));
    } on ShopFailure catch (e) {
      if (e.status == 404) await store.write(_slot, null);
    } catch (_) {
      // Nothing to resume; a new request can be created.
    }
    _notify();
  }

  /// Creates a request. A retry of the same amount after a lost response reuses
  /// its key, so at most one request exists for that intent.
  Future<bool> create({
    required String currency,
    required String amount,
    String? orderReference,
  }) async {
    if (creating || waiting || _disposed) return false;
    creating = true;
    failure = null;
    _notify();
    final body = jsonEncode([currency, amount, orderReference ?? '']);
    if (_pendingBody != body) {
      _pendingKey = randomCredential();
      _pendingBody = body;
    }
    try {
      final created = await gateway.createRequest(
        _pendingKey!,
        currency: currency,
        amount: amount,
        orderReference: orderReference,
      );
      _pendingKey = null;
      _pendingBody = null;
      _accept(created);
      return true;
    } on ShopFailure catch (e) {
      _fail(e);
      // A definite rejection frees the key; an uncertain one keeps it for retry.
      if (!e.uncertain) {
        _pendingKey = null;
        _pendingBody = null;
      }
      return false;
    } finally {
      creating = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    final current = request;
    if (current == null || !waiting || cancelling) return;
    cancelling = true;
    failure = null;
    _notify();
    try {
      // The answer can be PAID: a payment that won the race is shown, never hidden.
      _accept(await gateway.cancelRequest(current.id));
    } on ShopFailure catch (e) {
      _fail(e);
    } finally {
      cancelling = false;
      _notify();
    }
  }

  Future<void> refresh() => _check();

  /// History can reopen any request; status is revalidated before showing it.
  Future<void> openRequest(String id) async {
    if (creating || cancelling || _disposed) {
      throw const ShopFailure('REQUEST_BUSY');
    }
    final value = await gateway.requestStatus(id);
    if (_disposed) return;
    _accept(value);
  }

  /// Clears a finished request so the next one can start.
  Future<void> reset() async {
    if (waiting) return;
    _poll?.cancel();
    request = null;
    failure = null;
    reconnecting = false;
    await store.write(_slot, null);
    _notify();
  }

  void _accept(PaymentRequest value) {
    final before = request?.status;
    request = value;
    reconnecting = false;
    _remainingAtFetch = value.remainingAtFetch;
    _stopwatch
      ..reset()
      ..start();
    if (value.status == RequestStatus.waiting) {
      unawaited(store.write(_slot, value.id));
      _poll?.cancel();
      _poll = Timer.periodic(pollEvery, (_) => _check());
    } else {
      _poll?.cancel();
      unawaited(store.write(_slot, null));
      if (value.status == RequestStatus.paid && before != RequestStatus.paid) {
        onPaid?.call();
      }
    }
    _notify();
  }

  Future<void> _check() async {
    final current = request;
    if (current == null || _polling || _disposed) return;
    _polling = true;
    try {
      final value = await gateway.requestStatus(current.id);
      if (_disposed || request?.id != current.id) return;
      _accept(value);
    } on ShopFailure catch (e) {
      if (_disposed || request?.id != current.id) return;
      if (e.expired) {
        _poll?.cancel();
        onExpired?.call();
      } else {
        reconnecting = true;
        _notify();
      }
    } finally {
      _polling = false;
    }
  }

  void _fail(ShopFailure e) {
    failure = e;
    if (e.expired) onExpired?.call();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
