import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../accounts/account_gateway.dart';
import '../auth/session_controller.dart';
import 'transaction_gateway.dart';
import 'transfer_models.dart';
import 'transfer_store.dart';
import 'transfer_support.dart';

class TransferController extends ChangeNotifier {
  TransferController(
    this.session,
    this.gateway,
    this.store, {
    this.onSuccess,
    this.support,
  }) : _user = session.identity!.userId,
       _session = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final TransactionGateway gateway;
  final TransferStore store;
  final Future<void> Function()? onSuccess;

  /// Lookup, quotes and PIN proofs. When present, every send asks for the PIN.
  final TransferSupportGateway? support;
  bool get requiresPin => support != null;
  TransferQuote? quote;
  bool quoting = false;
  final int _user;
  final String _session;
  bool _disposed = false, _active = true;
  bool ready = false, busy = false;
  TransferDraft? review;
  SavedTransfer? saved;
  RecentPosting? receipt;
  ApiFailure? error, storageError, refreshError;
  bool get _current =>
      !_disposed &&
      _active &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!_current && _active) {
      _active = false;
      review = null;
      saved = null;
      receipt = null;
      error = storageError = refreshError = null;
      busy = ready = false;
      _emit();
    }
  }

  static const storageFailure = ApiFailure(
    'TRANSFER_STORAGE',
    'The transfer safety record could not be read or saved. Sending is blocked. Retry secure setup.',
  );

  Future<void> initialize() async {
    if (!_current || busy) return;
    busy = true;
    ready = false;
    storageError = null;
    _emit();
    try {
      final record = await store.read(_user);
      if (!_current) return;
      saved = record;
      review = null;
      receipt = null;
      error = null;
      ready = true;
      if (record?.outcome == 'success') {
        try {
          final data = await session.authorizedRead(
            (token) =>
                gateway.detail(token, record!.draft.source, record.reference!),
          );
          HttpTransactionGateway.validateReceipt(data, record!);
          if (_current) receipt = data;
        } on ApiFailure catch (e) {
          if (_current) error = e;
        }
      }
    } catch (e) {
      if (_current) {
        storageError = e is ApiFailure && e.code == 'INVALID_TRANSFER'
            ? e
            : storageFailure;
      }
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  bool prepare(
    BankAccount source,
    String destination,
    String amount,
    String remark, {
    String? qrString,
    String? destinationName,
    bool qrFixed = false,
  }) {
    if (!_current || !ready || busy || saved != null || storageError != null) {
      return false;
    }
    error = refreshError = null;
    quote = null;
    try {
      review = TransferDraft.validate(source, destination, amount, remark);
      if (qrString != null || destinationName != null) {
        if (qrString != null &&
            (qrString.isEmpty ||
                qrString.length > 4096 ||
                destinationName == null ||
                destinationName.isEmpty)) {
          throw invalidTransfer;
        }
        review = TransferDraft(
          review!.source,
          review!.destination,
          review!.amount,
          review!.remark,
          qrString: qrString,
          destinationName: destinationName,
          qrFixed: qrString != null && qrFixed,
        );
      }
    } on ApiFailure catch (e) {
      error = e;
      review = null;
    }
    _emit();
    if (review != null) unawaited(_quote(review!));
    return review != null;
  }

  /// Shows the exact credited amount (including conversion) on the review screen.
  Future<void> _quote(TransferDraft draft) async {
    final gateway = support;
    if (gateway == null) return;
    quoting = true;
    _emit();
    try {
      final result = await session.authorizedRead(
        (token) =>
            gateway.quote(token, draft.source, draft.destination, draft.amount),
      );
      if (_current && identical(review, draft)) {
        if (result.debit.minorUnits != draft.amount.minorUnits ||
            result.debit.currency != draft.amount.currency) {
          throw invalidTransfer;
        }
        quote = result;
      }
    } on ApiFailure catch (e) {
      if (_current && identical(review, draft)) error = e;
    } catch (_) {
      if (_current && identical(review, draft)) error = invalidTransfer;
    } finally {
      if (_current) {
        quoting = false;
        _emit();
      }
    }
  }

  void edit() {
    if (_current && !busy && saved == null) {
      review = null;
      quote = null;
      error = null;
      _emit();
    }
  }

  /// Exchanges the PIN for a one-time proof. Returns null (with [error] set) on rejection.
  Future<String?> _proof(String? pin) async {
    final gateway = support;
    if (gateway == null) return null;
    if (pin == null || !RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      error = const ApiFailure('PIN_REQUIRED', 'Enter your 4-digit PIN to confirm.');
      return null;
    }
    try {
      return await session.authorizedMutation(
        (token) => gateway.transferProof(token, pin),
      );
    } on ApiFailure catch (e) {
      if (_current) error = e;
      return null;
    } catch (_) {
      // Never surfaces as a storage failure: nothing was claimed or sent.
      if (_current) {
        error = const ApiFailure(
          'PIN_UNAVAILABLE',
          'PIN confirmation is unavailable. Nothing was sent. Try again.',
        );
      }
      return null;
    }
  }

  Future<void> confirm({String? pin}) async {
    final draft = review;
    if (!_current ||
        !ready ||
        busy ||
        saved != null ||
        draft == null ||
        storageError != null) {
      return;
    }
    busy = true;
    error = null;
    _emit();
    try {
      final proof = await _proof(pin);
      if (!_current || (requiresPin && proof == null)) return;
      final record = SavedTransfer.confirmed(draft);
      await store.claim(_user, record);
      if (!_current) return;
      saved = record;
      review = null;
      await _send(record, proof: proof);
    } catch (e) {
      if (_current) {
        storageError = e is ApiFailure && e.code == 'TRANSFER_PENDING'
            ? e
            : storageFailure;
        ready = false;
      }
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  /// User-triggered only. Never revalidates an already-debited balance or makes a new key.
  Future<void> retry({String? pin}) async {
    if (!_current ||
        !ready ||
        busy ||
        saved == null ||
        !saved!.unresolved ||
        storageError != null) {
      return;
    }
    busy = true;
    error = null;
    refreshError = null;
    _emit();
    try {
      final persisted = await store.read(_user);
      if (!_current) return;
      if (persisted == null || persisted.key != saved!.key) {
        throw invalidTransfer;
      }
      saved = persisted;
      if (persisted.unresolved) {
        // A request the server already completed replays without consuming the proof.
        final proof = await _proof(pin);
        if (!_current || (requiresPin && proof == null)) return;
        await _send(persisted, proof: proof);
      }
    } catch (_) {
      if (_current) {
        storageError = storageFailure;
        ready = false;
      }
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> _send(SavedTransfer record, {String? proof}) async {
    SavedTransfer? resolution;
    RecentPosting? result;
    try {
      final received = await session.authorizedMutation<RecentPosting>(
        (token) => gateway.transfer(token, record, pinProof: proof),
      );
      result = received;
      HttpTransactionGateway.validateReceipt(received, record);
      resolution = record.resolve(reference: received.reference);
    } on ApiFailure catch (e) {
      if (!_current) return;
      error = e;
      // Only documented transactional rejections resolve the intent. Timeouts,
      // authentication failures, conflicts and unexpected responses remain unresolved.
      if (e.status != null &&
          e.status! >= 400 &&
          e.status! < 500 &&
          SavedTransfer.definiteRejections.contains(e.code)) {
        resolution = record.resolve(rejectionCode: e.code);
      }
    } catch (_) {
      if (_current) {
        error = const ApiFailure(
          'UNKNOWN_OUTCOME',
          'The transfer outcome could not be confirmed.',
        );
      }
    }
    if (!_current || resolution == null) return;
    try {
      await store.resolve(_user, resolution);
    } catch (_) {
      if (_current) {
        storageError = storageFailure;
        ready = false;
      }
      return;
    }
    if (!_current) return;
    saved = resolution;
    receipt = result;
    if (result != null) {
      error = null;
      try {
        await onSuccess?.call();
      } catch (_) {
        if (_current) {
          refreshError = const ApiFailure(
            'REFRESH_FAILED',
            'Transfer confirmed. Refresh accounts and activity to obtain current balances.',
          );
        }
      }
    }
  }

  Future<void> dismiss() async {
    final record = saved;
    if (!_current ||
        busy ||
        record == null ||
        record.unresolved ||
        storageError != null) {
      return;
    }
    busy = true;
    _emit();
    try {
      await store.dismiss(_user, record.key);
      if (!_current) return;
      saved = null;
      receipt = null;
      review = null;
      error = refreshError = null;
    } catch (_) {
      if (_current) {
        storageError = storageFailure;
        ready = false;
      }
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    _disposed = true;
    saved = null;
    receipt = null;
    review = null;
    super.dispose();
  }
}
