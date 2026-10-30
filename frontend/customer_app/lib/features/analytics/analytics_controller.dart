import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';
import 'analytics_gateway.dart';

class AnalyticsController extends ChangeNotifier {
  AnalyticsController(this.session, this.gateway, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _user = session.identity!.userId,
      _session = session.identity!.sessionId {
    month = bankingMonth(_clock());
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final AnalyticsGateway gateway;
  final DateTime Function() _clock;
  final int _user;
  final String _session;
  final Map<String, AnalyticsSnapshot> _cache = {};
  late DateTime month;
  String currency = 'USD';
  bool showIncome = false, loading = false, started = false, _disposed = false;
  int _generation = 0;
  ApiFailure? error;
  AnalyticsSnapshot? snapshot;
  String get _key => '${monthKey(month)}:$currency';
  DateTime get currentMonth => bankingMonth(_clock());
  bool get canNext => month.isBefore(currentMonth);
  bool get canPrevious => month.year > 1 || month.month > 1;
  bool get _current =>
      !_disposed &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;

  void _sessionChanged() {
    if (!_current && !_disposed) {
      _generation++;
      _cache.clear();
      snapshot = null;
      error = null;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> ensureLoaded() async {
    if (!started) {
      month = currentMonth;
      await refresh();
    }
  }

  Future<void> selectMonth(int delta) async {
    if (!_current ||
        delta.abs() != 1 ||
        (delta > 0 && !canNext) ||
        (delta < 0 && !canPrevious)) {
      return;
    }
    month = DateTime.utc(month.year, month.month + delta);
    await refresh();
  }

  Future<void> showPeriod(String value, String selectedCurrency) async {
    if (!_current ||
        !{'USD', 'KHR'}.contains(selectedCurrency) ||
        !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
      return;
    }
    final parts = value.split('-').map(int.parse).toList();
    month = DateTime.utc(parts[0], parts[1]);
    currency = selectedCurrency;
    await refresh();
  }

  Future<void> selectCurrency(String value) async {
    if (!_current || !{'USD', 'KHR'}.contains(value) || value == currency) {
      return;
    }
    currency = value;
    await refresh();
  }

  void selectSeries(bool income) {
    if (!_current) return;
    showIncome = income;
    notifyListeners();
  }

  Future<void> invalidate() async {
    _cache.clear();
    snapshot = null;
    if (started) await refresh();
  }

  Future<void> refresh() async {
    if (!_current) return;
    started = true;
    final generation = ++_generation;
    final selectedMonth = month, selectedCurrency = currency, key = _key;
    snapshot = _cache[key];
    error = null;
    loading = true;
    notifyListeners();
    try {
      final result = await session.authorizedRead(
        (token) => gateway.load(token, selectedMonth, selectedCurrency),
      );
      if (!_current || generation != _generation) return;
      if (monthKey(result.month) != monthKey(selectedMonth) ||
          result.currency != selectedCurrency) {
        throw invalidAnalytics;
      }
      // Bound in-memory history, including after repeated navigation.
      if (_cache.length >= 24) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      snapshot = result;
    } on ApiFailure catch (failure) {
      if (_current && generation == _generation) error = failure;
    } catch (_) {
      if (_current && generation == _generation) error = invalidAnalytics;
    } finally {
      if (_current && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cache.clear();
    snapshot = null;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
