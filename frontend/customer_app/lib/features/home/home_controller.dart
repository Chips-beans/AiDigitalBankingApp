import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';
import 'home_gateway.dart';

/// Owns the Home snapshot independently of the account selected in a detail page.
class HomeController extends ChangeNotifier {
  HomeController(this.session, this.gateway)
    : _user = session.identity!.userId,
      _session = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final HomeGateway gateway;
  final int _user;
  final String _session;
  bool _disposed = false;
  int _request = 0;
  bool loading = false;
  HomeSnapshot? snapshot;
  ApiFailure? error;

  bool get _current =>
      !_disposed &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;

  void _sessionChanged() {
    if (!_current && !_disposed) {
      _request++;
      snapshot = null;
      error = null;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!_current) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await session.authorizedRead(gateway.load);
      if (_current && request == _request) snapshot = data;
    } on ApiFailure catch (failure) {
      if (_current && request == _request) error = failure;
    } catch (_) {
      if (_current && request == _request) {
        error = const ApiFailure(
          'INVALID_RESPONSE',
          'Home information could not be read. Pull down to retry.',
        );
      }
    } finally {
      if (_current && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    session.removeListener(_sessionChanged);
    snapshot = null;
    super.dispose();
  }
}
