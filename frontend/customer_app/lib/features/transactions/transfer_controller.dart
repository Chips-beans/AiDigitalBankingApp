import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../accounts/account_gateway.dart';
import '../auth/session_controller.dart';
import 'transaction_gateway.dart';
import 'transfer_models.dart';
import 'transfer_store.dart';

class TransferController extends ChangeNotifier {
  TransferController(this.session, this.gateway, this.store, {this.onSuccess})
    : _user = session.identity!.userId,
      _session = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final TransactionGateway gateway;
  final TransferStore store;
  final Future<void> Function()? onSuccess;
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
  }) {
    if (!_current || !ready || busy || saved != null || storageError != null) {
      return false;
    }
    error = refreshError = null;
    try {
      review = TransferDraft.validate(source, destination, amount, remark);
      if (qrString != null) {
        if (qrString.isEmpty ||
            qrString.length > 4096 ||
            destinationName == null ||
            destinationName.isEmpty) {
          throw invalidTransfer;
        }
        review = TransferDraft(
          review!.source,
          review!.destination,
          review!.amount,
          review!.remark,
          qrString: qrString,
          destinationName: destinationName,
        );
      }
    } on ApiFailure catch (e) {
      error = e;
      review = null;
    }
    _emit();
    return review != null;
  }

  void edit() {
    if (_current && !busy && saved == null) {
      review = null;
      error = null;
      _emit();
    }
  }

  Future<void> confirm() async {
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
      final record = SavedTransfer.confirmed(draft);
      await store.claim(_user, record);
      if (!_current) return;
      saved = record;
      review = null;
      await _send(record);
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
  Future<void> retry() async {
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
      if (persisted.unresolved) await _send(persisted);
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

  Future<void> _send(SavedTransfer record) async {
    SavedTransfer? resolution;
    RecentPosting? result;
    try {
      final received = await session.authorizedMutation<RecentPosting>(
        (token) => gateway.transfer(token, record),
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
