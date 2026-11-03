import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../shop/merchant_shop.dart';
import 'owner_transfer.dart';

/// One owner transfer at a time.
///
/// Money moves only when the owner approves in Kesor Bank, and only the server's status says
/// so: a callback link merely prompts an immediate status check. A lost create response keeps
/// its idempotency key for an explicit retry; the active transfer and the data to replay it are
/// saved per owner, so a restarted app resumes watching instead of losing the result.
class OwnerTransferController extends ChangeNotifier {
  OwnerTransferController(
    this.gateway,
    this.store, {
    this.ownerId = 0,
    NativeHandoff? native,
    this.onCompleted,
    this.onExpired,
    this.pollEvery = const Duration(seconds: 2),
    Stopwatch Function()? stopwatch,
  }) : native = native ?? const NativeHandoff(),
       _stopwatch = (stopwatch ?? Stopwatch.new)();

  final OwnerTransferGateway gateway;
  final HandoffStore store;
  final NativeHandoff native;
  final int ownerId;
  final VoidCallback? onCompleted, onExpired;
  final Duration pollEvery;

  OwnerTransfer? transfer;
  ShopFailure? failure;
  bool creating = false, cancelling = false, opening = false;

  /// Offline or uncertain while waiting; the transfer may already be approved.
  bool reconnecting = false;

  String? _pendingKey, _pendingBody;
  // The saved intent: replaying its key returns a fresh approval link after a restart.
  String? _key, _source, _amount, _state;
  Timer? _poll;
  final Stopwatch _stopwatch;
  Duration _remainingAtFetch = Duration.zero;
  bool _disposed = false, _polling = false;

  String get _slot => 'owner-transfer-$ownerId';

  bool get waiting => transfer?.waiting == true;

  /// Time left on the server's clock, counted down locally since the last fetch.
  Duration get remaining {
    final left = _remainingAtFetch - _stopwatch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> resume() async {
    try {
      final raw = await store.read(_slot);
      if (raw == null || transfer != null) return;
      final saved = jsonDecode(raw) as Map;
      _key = saved['key'] as String;
      _source = saved['source'] as String;
      _amount = saved['amount'] as String;
      _state = saved['state'] as String;
      _accept(await gateway.ownerTransferStatus(saved['id'] as String));
    } on ShopFailure catch (e) {
      if (e.status == 404) await store.write(_slot, null);
    } catch (_) {
      await store.write(_slot, null);
    }
    _notify();
  }

  /// Creates the transfer. A retry of the same transfer after a lost response reuses its key.
  Future<bool> create({
    required String sourceAccountNumber,
    required String amount,
  }) async {
    if (creating || waiting || _disposed) return false;
    creating = true;
    failure = null;
    _notify();
    final body = jsonEncode([sourceAccountNumber, amount]);
    if (_pendingBody != body) {
      _pendingKey = randomCredential();
      _pendingBody = body;
    }
    final key = _pendingKey!;
    try {
      final created = await gateway.createOwnerTransfer(
        key,
        sourceAccountNumber: sourceAccountNumber,
        amount: amount,
      );
      _pendingKey = null;
      _pendingBody = null;
      _key = key;
      _source = sourceAccountNumber;
      _amount = amount;
      _state = created.state;
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

  /// Opens the approval in Kesor Bank. After a restart the link is no longer known, so the same
  /// create is replayed: the server answers with the same transfer and a fresh link.
  Future<void> openApproval() async {
    final current = transfer;
    if (current == null || !waiting || opening || _disposed) return;
    opening = true;
    failure = null;
    _notify();
    try {
      var link = current.approvalUri;
      if (link == null) {
        final replayed = await gateway.createOwnerTransfer(
          _key!,
          sourceAccountNumber: _source!,
          amount: _amount!,
        );
        if (replayed.id != current.id) {
          throw const ShopFailure('INVALID_RESPONSE');
        }
        _state = replayed.state;
        _accept(replayed);
        link = replayed.approvalUri;
      }
      if (link == null) return;
      await native.openTransfer(link);
    } on ShopFailure catch (e) {
      _fail(e);
    } on HandoffFailure catch (e) {
      failure = ShopFailure(e.code);
    } finally {
      opening = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    final current = transfer;
    if (current == null || !waiting || cancelling) return;
    cancelling = true;
    failure = null;
    _notify();
    try {
      // The answer can be COMPLETED: an approval that won the race is shown, never hidden.
      _accept(await gateway.cancelOwnerTransfer(current.id));
    } on ShopFailure catch (e) {
      _fail(e);
    } finally {
      cancelling = false;
      _notify();
    }
  }

  Future<void> refresh() => _check();

  /// Clears a finished transfer so the next one can start.
  Future<void> reset() async {
    if (waiting) return;
    _poll?.cancel();
    transfer = null;
    failure = null;
    reconnecting = false;
    _key = _source = _amount = _state = null;
    await store.write(_slot, null);
    _notify();
  }

  void _accept(OwnerTransfer value) {
    final before = transfer?.status;
    transfer = value;
    reconnecting = false;
    _remainingAtFetch = value.remainingAtFetch;
    _stopwatch
      ..reset()
      ..start();
    if (value.waiting) {
      unawaited(
        store.write(
          _slot,
          jsonEncode({
            'id': value.id,
            'key': _key,
            'source': _source,
            'amount': _amount,
            'state': _state,
          }),
        ),
      );
      _poll?.cancel();
      _poll = Timer.periodic(pollEvery, (_) => _check());
    } else {
      _poll?.cancel();
      unawaited(store.write(_slot, null));
      if (value.status == TransferStatus.completed &&
          before != TransferStatus.completed) {
        onCompleted?.call();
      }
    }
    _notify();
  }

  /// A return link is only a nudge: it must match this transfer and its saved state, and the
  /// answer still comes from the server.
  Future<void> _takeCallback() async {
    final raw = await native.takeTransfer();
    if (raw == null || _state == null) return;
    for (final keys in [
      {'intentId', 'state'},
      {'intentId', 'state', 'error'},
    ]) {
      try {
        final fields = exactLink(raw, transferCallbackBase, keys);
        if (fields['intentId'] == transfer?.id &&
            secureEquals(fields['state']!, _state!)) {
          return;
        }
      } on HandoffFailure {
        /* Try the other exact shape. */
      }
    }
  }

  Future<void> _check() async {
    final current = transfer;
    if (current == null || _polling || _disposed) return;
    _polling = true;
    try {
      await _takeCallback();
      final value = await gateway.ownerTransferStatus(current.id);
      if (_disposed || transfer?.id != current.id) return;
      _accept(value);
    } on ShopFailure catch (e) {
      if (_disposed || transfer?.id != current.id) return;
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
