import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';
import 'account_gateway.dart';
import 'creation_store.dart';

class AccountsController extends ChangeNotifier {
  AccountsController(this.session, this.gateway, this.store)
    : _userId = session.identity!.userId,
      _sessionId = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final AccountGateway gateway;
  final CreationStore store;
  final int _userId;
  final String _sessionId;
  bool _disposed = false, _active = true;
  int _listRequest = 0, _selectionRequest = 0;
  int _nextPage = 0;
  List<BankAccount> accounts = [];
  BankAccount? selected;
  List<RecentPosting> activity = [];
  bool loading = false,
      loadingMore = false,
      loadingDetail = false,
      loadingActivity = false;
  bool opening = false, hasMore = false, uncertain = false, ready = false;
  bool checkedAfterUncertainty = false;
  ApiFailure? listError,
      detailError,
      activityError,
      creationError,
      storageError;
  DateTime? accountsUpdatedAt, detailUpdatedAt, activityUpdatedAt;
  String? notice;
  bool get _current =>
      !_disposed &&
      _active &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _userId &&
      session.identity?.sessionId == _sessionId;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!_current && _active) {
      _active = false;
      accounts = [];
      selected = null;
      activity = [];
      listError = detailError = activityError = creationError = storageError =
          null;
      notice = null;
      uncertain = false;
      accountsUpdatedAt = detailUpdatedAt = activityUpdatedAt = null;
      loading = loadingMore = loadingDetail = loadingActivity = opening = false;
      if (gateway is DemoAccountGateway) {
        (gateway as DemoAccountGateway).clearSession();
      }
      _listRequest++;
      _selectionRequest++;
      _emit();
    }
  }

  Future<void> initialize() async {
    try {
      final pending = await store.pending(_userId);
      if (!_current) return;
      uncertain = pending;
      storageError = null;
      ready = true;
    } catch (_) {
      if (!_current) return;
      storageError = const ApiFailure(
        'STORAGE_UNAVAILABLE',
        'Account-opening safety could not be checked. Retry secure setup before opening an account.',
      );
      ready = false;
    }
    if (!_current) return;
    _emit();
    await refresh();
  }

  Future<void> refresh() async {
    if (!_current) return;
    final request = ++_listRequest;
    loading = true;
    loadingMore = false;
    listError = null;
    _emit();
    try {
      final data = await session.authorizedRead(
        (token) => gateway.list(token, 0),
      );
      if (!_current || request != _listRequest) return;
      // Retain the selected owned account beyond page zero until detail revalidation.
      final old = selected;
      accounts = [...data];
      if (old != null && !accounts.any((a) => a.number == old.number)) {
        accounts.add(old);
      }
      _nextPage = 1;
      hasMore = data.length == 20;
      accountsUpdatedAt = DateTime.now();
      if (uncertain) checkedAfterUncertainty = true;
      final choice = old == null
          ? (data.isEmpty ? null : data.first)
          : accounts.where((a) => a.number == old.number).firstOrNull;
      if (choice == null) {
        selected = null;
        activity = [];
        _selectionRequest++;
      } else {
        await select(choice);
      }
    } on ApiFailure catch (e) {
      if (_current && request == _listRequest) listError = e;
    } finally {
      if (_current && request == _listRequest) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> loadMore() async {
    if (!_current || loading || loadingMore || !hasMore) return;
    final request = _listRequest;
    loadingMore = true;
    listError = null;
    _emit();
    try {
      final data = await session.authorizedRead(
        (token) => gateway.list(token, _nextPage),
      );
      if (!_current || request != _listRequest) return;
      final merged = {for (final a in accounts) a.number: a};
      for (final a in data) {
        merged[a.number] = a;
      }
      accounts = merged.values.toList();
      _nextPage++;
      hasMore = data.length == 20;
      accountsUpdatedAt = DateTime.now();
    } on ApiFailure catch (e) {
      if (_current && request == _listRequest) listError = e;
    } finally {
      if (_current && request == _listRequest) {
        loadingMore = false;
        _emit();
      }
    }
  }

  Future<void> select(BankAccount account) async {
    if (!_current) return;
    final request = ++_selectionRequest;
    final same = selected?.number == account.number;
    selected = account;
    if (!same) {
      activity = [];
      activityUpdatedAt = null;
      detailUpdatedAt = null;
    }
    detailError = activityError = null;
    loadingDetail = true;
    _emit();
    final activityLoad = refreshActivity();
    try {
      final detail = await session.authorizedRead(
        (token) => gateway.detail(token, account.number),
      );
      if (!_current || request != _selectionRequest) return;
      if (detail.number != account.number) throw invalidAccountData;
      selected = detail;
      accounts = accounts
          .map((a) => a.number == detail.number ? detail : a)
          .toList();
      detailUpdatedAt = DateTime.now();
    } on ApiFailure catch (e) {
      if (_current && request == _selectionRequest) {
        detailError = e;
        if (e.status == 404) {
          accounts = accounts.where((a) => a.number != account.number).toList();
          selected = null;
          activity = [];
          activityUpdatedAt = null;
          _selectionRequest++;
          loadingActivity = loadingDetail = false;
          _emit();
        }
      }
    } finally {
      if (_current && request == _selectionRequest) {
        loadingDetail = false;
        _emit();
      }
    }
    await activityLoad;
  }

  int _activityRequest = 0;
  Future<void> refreshActivity() async {
    final account = selected;
    if (!_current || account == null) return;
    final selection = _selectionRequest;
    final request = ++_activityRequest;
    loadingActivity = true;
    activityError = null;
    _emit();
    try {
      final data = await session.authorizedRead(
        (token) => gateway.recent(token, account.number),
      );
      if (!_current ||
          selection != _selectionRequest ||
          request != _activityRequest) {
        return;
      }
      if (data.any((p) => p.amount.currency != account.currency)) {
        throw invalidAccountData;
      }
      activity = data;
      activityUpdatedAt = DateTime.now();
    } on ApiFailure catch (e) {
      if (_current &&
          selection == _selectionRequest &&
          request == _activityRequest) {
        activityError = e;
      }
    } finally {
      if (_current &&
          selection == _selectionRequest &&
          request == _activityRequest) {
        loadingActivity = false;
        _emit();
      }
    }
  }

  Future<void> allowNewAccount() async {
    if (!_current || opening || !checkedAfterUncertainty) return;
    try {
      await store.setPending(_userId, false);
      if (!_current) return;
      uncertain = false;
      creationError = storageError = null;
    } catch (_) {
      if (_current) storageError = _storageFailure;
    }
    if (_current) _emit();
  }

  static const _storageFailure = ApiFailure(
    'STORAGE_UNAVAILABLE',
    'Account-opening safety could not be saved. Retry secure setup before continuing.',
  );

  Future<bool> open(String type, String currency) async {
    if (!_current || !ready || opening || uncertain || storageError != null) {
      return false;
    }
    if (!BankAccount.types.contains(type) ||
        !{'USD', 'KHR'}.contains(currency)) {
      return false;
    }
    opening = true;
    creationError = null;
    notice = null;
    _emit();
    bool sent = false;
    try {
      // Persist BEFORE sending, so process death cannot enable an unnoticed replay.
      await store.setPending(_userId, true);
      if (!_current) return false;
      uncertain = true;
      checkedAfterUncertainty = false;
      final account = await session.authorizedMutation((token) {
        sent = true;
        return gateway.open(token, type, currency);
      });
      if (!_current) return false;
      // Only the current session can resolve its pending marker.
      await store.setPending(_userId, false);
      if (!_current) return false;
      uncertain = false;
      accounts = [
        ...accounts.where((a) => a.number != account.number),
        account,
      ];
      notice = 'Account opened with ${account.balance.formatted}.';
      await select(account);
      return true;
    } on ApiFailure catch (e) {
      // Explicit 4xx rejection (excluding timeout) confirms no account was opened.
      if (!_current) return false;
      final rejected =
          !sent ||
          (e.status != null &&
              e.status! >= 400 &&
              e.status! < 500 &&
              e.status != 408);
      if (rejected) {
        try {
          await store.setPending(_userId, false);
        } catch (_) {
          if (_current) storageError = _storageFailure;
        }
      }
      if (!_current) return false;
      uncertain = !rejected || storageError != null;
      creationError = e;
      if (uncertain) await refresh();
    } catch (_) {
      if (_current) {
        storageError = _storageFailure;
        uncertain = true;
      }
    } finally {
      if (_current) {
        opening = false;
        _emit();
      }
    }
    return false;
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    _disposed = true;
    accounts = [];
    selected = null;
    activity = [];
    super.dispose();
  }
}
