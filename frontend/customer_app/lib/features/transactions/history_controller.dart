import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../accounts/account_gateway.dart';
import '../accounts/accounts_controller.dart';
import '../auth/session_controller.dart';
import 'transaction_gateway.dart';

class HistoryController extends ChangeNotifier {
  HistoryController(this.session, this.accounts, this.gateway)
    : _user = session.identity!.userId,
      _session = session.identity!.sessionId {
    session.addListener(_sync);
    accounts.addListener(_sync);
    _sync();
  }
  final SessionController session;
  final AccountsController accounts;
  final TransactionGateway gateway;
  final int _user;
  final String _session;
  bool _disposed = false;
  int _generation = 0, _detailGeneration = 0, _next = 0;
  String? accountNumber, currency;
  List<RecentPosting> items = [];
  RecentPosting? detail;
  bool loading = false,
      moreLoading = false,
      hasMore = false,
      detailLoading = false;
  ApiFailure? error, detailError;
  DateTime? updatedAt, detailUpdatedAt;
  bool get _current =>
      !_disposed &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    _generation++;
    _detailGeneration++;
    items = [];
    detail = null;
    error = detailError = null;
    updatedAt = detailUpdatedAt = null;
    loading = moreLoading = hasMore = detailLoading = false;
  }

  void _sync() {
    final selected = _current ? accounts.selected : null;
    if (selected?.number == accountNumber && selected?.currency == currency) {
      return;
    }
    _clear();
    accountNumber = selected?.number;
    currency = selected?.currency;
    _emit();
    if (selected != null) unawaited(refresh());
  }

  Future<void> refresh() async {
    final number = accountNumber;
    if (!_current || number == null) return;
    final generation = ++_generation;
    loading = true;
    moreLoading = false;
    error = null;
    _emit();
    try {
      final page = await session.authorizedRead(
        (token) => gateway.history(token, number, 0),
      );
      if (!_current || generation != _generation) return;
      _validate(page, 0);
      items = page.content;
      _next = 1;
      hasMore = !page.last;
      updatedAt = DateTime.now();
    } on ApiFailure catch (e) {
      if (_current && generation == _generation) error = e;
    } finally {
      if (_current && generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  void _validate(PostingPage page, int expected) {
    if (page.page != expected ||
        page.content.any(
          (p) =>
              p.amount.currency != currency ||
              (p.source != accountNumber && p.destination != accountNumber),
        )) {
      throw invalidAccountData;
    }
  }

  Future<void> loadMore() async {
    final number = accountNumber;
    if (!_current || number == null || loading || moreLoading || !hasMore) {
      return;
    }
    final generation = _generation;
    moreLoading = true;
    error = null;
    _emit();
    try {
      final page = await session.authorizedRead(
        (token) => gateway.history(token, number, _next),
      );
      if (!_current || generation != _generation) return;
      _validate(page, _next);
      final merged = {for (final item in items) item.reference: item};
      for (final item in page.content) {
        merged[item.reference] = item;
      }
      items = merged.values.toList();
      _next++;
      hasMore = !page.last;
    } on ApiFailure catch (e) {
      if (_current && generation == _generation) error = e;
    } finally {
      if (_current && generation == _generation) {
        moreLoading = false;
        _emit();
      }
    }
  }

  Future<void> openDetail(String reference) async {
    final number = accountNumber;
    if (!_current || number == null) return;
    final generation = ++_detailGeneration;
    detail = null;
    detailError = null;
    detailUpdatedAt = null;
    detailLoading = true;
    _emit();
    try {
      final data = await session.authorizedRead(
        (token) => gateway.detail(token, number, reference),
      );
      if (!_current || generation != _detailGeneration) return;
      if (data.amount.currency != currency || data.reference != reference) {
        throw invalidAccountData;
      }
      detail = data;
      detailUpdatedAt = DateTime.now();
    } on ApiFailure catch (e) {
      if (_current && generation == _detailGeneration) detailError = e;
    } finally {
      if (_current && generation == _detailGeneration) {
        detailLoading = false;
        _emit();
      }
    }
  }

  void closeDetail() {
    _detailGeneration++;
    detail = null;
    detailError = null;
    detailUpdatedAt = null;
    detailLoading = false;
    _emit();
  }

  @override
  void dispose() {
    session.removeListener(_sync);
    accounts.removeListener(_sync);
    _disposed = true;
    _clear();
    super.dispose();
  }
}
