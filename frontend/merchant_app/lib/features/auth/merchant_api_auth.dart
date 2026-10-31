import 'dart:async';
import 'dart:convert';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../../core/merchant_config.dart';
import 'merchant_session.dart';

/// One durable journal per installation/API origin. Credentials never enter UI or links.
class MerchantApiAuth implements RestorableMerchantAuth {
  MerchantApiAuth(
    this.config, {
    HandoffApi? api,
    HandoffStore? store,
    NativeHandoff? native,
    DateTime Function()? clock,
  }) : api = api ?? HandoffApi(config.apiBaseUrl),
       store =
           store ??
           SecureHandoffStore(
             '${config.storageNamespace}|${config.environment}|auth',
           ),
       native = native ?? const NativeHandoff(),
       clock = clock ?? DateTime.now;
  final MerchantConfig config;
  final HandoffApi api;
  final HandoffStore store;
  final NativeHandoff native;
  final DateTime Function() clock;
  Map<String, dynamic> journal = {};
  bool _loaded = false, _active = false, _storageBlocked = false;
  int _generation = 0;
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    if (_loaded) return;
    final raw = await store.read('auth');
    if (raw != null) {
      journal = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
    _loaded = true;
  }

  Future<void> _save() {
    final snapshot = jsonEncode(journal);
    // A failed write remains an error to its caller; later cancellation can retry it.
    final flight = _writes.catchError((Object _) {}).then((_) async {
      try {
        await store.write('auth', snapshot);
        _storageBlocked = false;
      } catch (_) {
        _storageBlocked = true;
        rethrow;
      }
    });
    _writes = flight;
    return flight;
  }

  Map<String, dynamic>? get _pending =>
      journal['pending'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _tokens =>
      journal['tokens'] as Map<String, dynamic>?;
  bool _current(int generation) => generation == _generation;
  void _check(int generation) {
    if (!_current(generation)) {
      throw const MerchantAuthFailure(MerchantAuthIssue.denied);
    }
  }

  Future<T> _guard<T>(Future<T> Function() work) async {
    if (_active) throw const MerchantAuthUnavailable();
    _active = true;
    try {
      if (_storageBlocked) await _save();
      return await work();
    } on MerchantAuthFailure {
      rethrow;
    } on HandoffFailure catch (e) {
      throw MerchantAuthFailure(switch (e.code) {
        'PEER_MISSING' => MerchantAuthIssue.customerMissing,
        'OFFLINE' || 'TIMEOUT' => MerchantAuthIssue.offline,
        'MERCHANT_AUTH_EXPIRED' ||
        'TOKEN_INVALID' ||
        'SESSION_INVALID' ||
        'REFRESH_REUSED' => MerchantAuthIssue.expired,
        'MERCHANT_AUTH_DENIED' ||
        'MERCHANT_AUTH_CANCELLED' => MerchantAuthIssue.denied,
        'MERCHANT_AUTH_RATE_LIMITED' => MerchantAuthIssue.rateLimited,
        _ => MerchantAuthIssue.unavailable,
      });
    } catch (_) {
      throw const MerchantAuthUnavailable();
    } finally {
      _active = false;
    }
  }

  @override
  Future<MerchantIdentity?> restore() => _guard(() async {
    await _load();
    if (_pending != null) {
      if (_pending!['cancelled'] == true) {
        await _cancelPending();
        return null;
      }
      if (_pending!['code'] != null) {
        throw const MerchantAuthFailure(MerchantAuthIssue.uncertain);
      }
      return _wait(++_generation);
    }
    if (journal['logout'] == true) {
      await _logout();
      return null;
    }
    if (_tokens == null) return null;
    return _identity(++_generation);
  });

  @override
  Future<MerchantIdentity> authorize() => _guard(() async {
    await _load();
    if (config.environment != 'dev') throw const MerchantAuthUnavailable();
    if (journal['logout'] == true) await _logout();
    if (_pending?['cancelled'] == true) await _cancelPending();
    if (_pending?['code'] != null) {
      throw const MerchantAuthFailure(MerchantAuthIssue.uncertain);
    }
    final generation = ++_generation;
    if (_tokens != null) return _identity(generation);
    if (_pending != null) return _wait(generation);
    await native.verify();
    _check(generation);
    var installation = await store.read('installation');
    if (installation == null) {
      installation = randomCredential();
      await store.write('installation', installation);
    }
    _check(generation);
    final p = <String, dynamic>{
      'verifier': randomCredential(),
      'state': randomCredential(),
      'secret': randomCredential(),
      'key': randomCredential(),
      'expiresAt': clock().add(const Duration(seconds: 120)).toIso8601String(),
    };
    journal['pending'] = p;
    await _save();
    _check(generation);
    final data = await api.request(
      'POST',
      '/merchant-auth/attempts',
      body: {
        'clientId': merchantClient,
        'redirectUri': callbackBase,
        'state': p['state'],
        'codeChallenge': challenge(p['verifier']),
        'codeChallengeMethod': 'S256',
        'attemptSecretHash': secretHash(p['secret']),
        'installationId': installation,
        'deviceName': 'Android phone',
      },
    );
    if (data is! Map ||
        !attemptId(data['attemptId']) ||
        data['customerPackage'] != customerPackage) {
      throw const MerchantAuthUnavailable();
    }
    final link = exactLink(data['approvalUri'], approvalBase, {
      'attemptId',
      'handoffToken',
    });
    if (link['attemptId'] != data['attemptId'] ||
        !credential(link['handoffToken'])) {
      throw const MerchantAuthUnavailable();
    }
    p['id'] = data['attemptId'];
    p['approvalUri'] = data['approvalUri'];
    final expires = DateTime.parse(data['expiresAt']);
    if (expires.isBefore(DateTime.parse(p['expiresAt']))) {
      p['expiresAt'] = expires.toIso8601String();
    }
    await _save();
    if (!_current(generation) || p['cancelled'] == true) {
      await _cancelPending();
      _check(generation);
    }
    try {
      await native.open(p['approvalUri']);
    } catch (_) {
      p['cancelled'] = true;
      await _save();
      await _cancelPending();
      rethrow;
    }
    return _wait(generation);
  });

  Future<MerchantIdentity> _wait(int generation) async {
    final p = _pending;
    if (p == null || p['id'] == null) {
      journal.remove('pending');
      await _save();
      throw const MerchantAuthFailure(MerchantAuthIssue.expired);
    }
    var nextStatus = clock();
    while (_current(generation)) {
      if (!DateTime.parse(p['expiresAt']).isAfter(clock())) {
        p['cancelled'] = true;
        await _save();
        await _cancelPending();
        throw const MerchantAuthFailure(MerchantAuthIssue.expired);
      }
      final raw = await native.take();
      _check(generation);
      if (raw != null) {
        try {
          final uri = Uri.parse(raw);
          final denied = uri.queryParameters.containsKey('error');
          final fields = exactLink(
            raw,
            callbackBase,
            denied ? {'state', 'error'} : {'state', 'code'},
          );
          if (!secureEquals(fields['state']!, p['state'])) {
            throw const HandoffFailure('INVALID_LINK');
          }
          if (denied) {
            if (fields['error'] != 'access_denied') {
              throw const HandoffFailure('INVALID_LINK');
            }
            p['cancelled'] = true;
            await _save();
            await _cancelPending();
            throw const MerchantAuthFailure(MerchantAuthIssue.denied);
          }
          if (!credential(fields['code'])) {
            throw const HandoffFailure('INVALID_LINK');
          }
          p['code'] = fields['code'];
          // Persist before sending. A process death at any later point requires explicit recovery.
          p['recoveryUntil'] = clock()
              .add(const Duration(seconds: 60))
              .toIso8601String();
          await _save();
          return await _exchange(generation);
        } on HandoffFailure catch (e) {
          if (e.code != 'INVALID_LINK') rethrow;
        }
      }
      if (!clock().isBefore(nextStatus)) {
        nextStatus = clock().add(const Duration(seconds: 5));
        try {
          final status = await api.request(
            'POST',
            '/merchant-auth/attempts/${p['id']}/status',
            body: {'attemptSecret': p['secret']},
          );
          _check(generation);
          if (status is! Map || status['attemptId'] != p['id']) {
            throw const HandoffFailure('INVALID_RESPONSE');
          }
          if (['DENIED', 'CANCELLED', 'EXPIRED'].contains(status['status'])) {
            journal.remove('pending');
            await _save();
            throw MerchantAuthFailure(
              status['status'] == 'EXPIRED'
                  ? MerchantAuthIssue.expired
                  : MerchantAuthIssue.denied,
            );
          }
        } on HandoffFailure catch (e) {
          if (!['OFFLINE', 'TIMEOUT'].contains(e.code)) rethrow;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw const MerchantAuthFailure(MerchantAuthIssue.denied);
  }

  @override
  Future<MerchantIdentity> recover() => _guard(() async {
    await _load();
    final p = _pending;
    if (p == null || p['code'] == null || p['cancelled'] == true) {
      throw const MerchantAuthUnavailable();
    }
    if (!DateTime.parse(p['recoveryUntil']).isAfter(clock())) {
      p['cancelled'] = true;
      await _save();
      await _cancelPending();
      throw const MerchantAuthFailure(MerchantAuthIssue.expired);
    }
    return _exchange(++_generation);
  });

  Future<MerchantIdentity> _exchange(int generation) async {
    final p = _pending!;
    dynamic response;
    try {
      response = await api.request(
        'POST',
        '/merchant-auth/exchange',
        body: {
          'attemptId': p['id'],
          'code': p['code'],
          'codeVerifier': p['verifier'],
          'attemptSecret': p['secret'],
          'exchangeKey': p['key'],
          'state': p['state'],
          'clientId': merchantClient,
          'redirectUri': callbackBase,
        },
      );
    } on HandoffFailure catch (e) {
      if (['OFFLINE', 'TIMEOUT', 'INVALID_RESPONSE'].contains(e.code) ||
          (e.status ?? 0) >= 500) {
        throw const MerchantAuthFailure(MerchantAuthIssue.uncertain);
      }
      p['cancelled'] = true;
      await _save();
      await _cancelPending();
      rethrow;
    }
    if (!_current(generation) || p['cancelled'] == true) {
      await _cancelPending();
      _check(generation);
    }
    journal['tokens'] = _tokenResponse(response);
    // One atomic vault write: save credentials and erase attempt secrets together.
    journal.remove('pending');
    await _save();
    _check(generation);
    return _identity(generation);
  }

  Map<String, dynamic> _tokenResponse(dynamic data) {
    if (data is! Map ||
        data['accessToken'] is! String ||
        data['refreshToken'] is! String ||
        data['expiresInMs'] is! num ||
        data['expiresInMs'] <= 0) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    return {
      'access': data['accessToken'],
      'refresh': data['refreshToken'],
      'until': clock()
          .add(Duration(milliseconds: (data['expiresInMs'] as num).toInt()))
          .toIso8601String(),
    };
  }

  Future<MerchantIdentity> _identity(int generation) async {
    if (_tokens == null) {
      throw const MerchantAuthFailure(MerchantAuthIssue.expired);
    }
    if (journal['refreshing'] == true) {
      // Never replay a rotating refresh whose response may have been lost.
      journal['logout'] = true;
      await _save();
      throw const MerchantAuthFailure(MerchantAuthIssue.expired);
    }
    if (!DateTime.parse(_tokens!['until'])
        .isAfter(clock().add(const Duration(seconds: 10)))) {
      await _refresh(generation);
    }
    dynamic data;
    try {
      data = await api.request(
        'GET',
        '/merchant-auth/session',
        access: _tokens!['access'],
      );
    } on HandoffFailure catch (e) {
      if (e.status == 401) {
        journal.remove('tokens');
        await _save();
        throw const MerchantAuthFailure(MerchantAuthIssue.expired);
      }
      rethrow;
    }
    _check(generation);
    if (data is! Map ||
        data['ownerId'] is! int ||
        data['ownerId'] <= 0 ||
        data['clientId'] != merchantClient ||
        !attemptId(data['sessionId'])) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    final state = data['onboardingState'];
    if (![
      'SHOP_REQUIRED',
      'READY',
      'RESTRICTED',
      'RECOVERY_REQUIRED',
    ].contains(state)) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    final shop = data['shop'];
    if (['READY', 'RESTRICTED'].contains(state) &&
        (shop is! Map ||
            shop['merchantId'] is! String ||
            shop['storeName'] is! String)) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    return MerchantIdentity(
      ownerId: data['ownerId'],
      recoveryRequired: state == 'RECOVERY_REQUIRED',
      shop: shop is Map
          ? MerchantShop(
              id: shop['merchantId'],
              name: shop['storeName'],
              active: state == 'READY',
            )
          : null,
    );
  }

  Future<void> _refresh(int generation) async {
    final refresh = _tokens!['refresh'];
    journal['refreshing'] = true;
    await _save();
    _check(generation);
    final data = await api.request(
      'POST',
      '/merchant-auth/refresh',
      body: {'refreshToken': refresh},
    );
    _check(generation);
    journal['tokens'] = _tokenResponse(data);
    journal.remove('refreshing');
    await _save();
  }

  @override
  Future<MerchantIdentity?> validate() => _guard(() async {
    await _load();
    return _identity(++_generation);
  });
  @override
  Future<void> reopen() async {
    final p = _pending;
    if (p == null ||
        p['approvalUri'] == null ||
        p['cancelled'] == true ||
        p['code'] != null ||
        !DateTime.parse(p['expiresAt']).isAfter(clock())) {
      return;
    }
    await native.open(p['approvalUri']);
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    await _load();
    if (_pending != null) {
      _pending!['cancelled'] = true;
      await _cancelPending();
    } else if (_tokens != null) {
      journal['logout'] = true;
      try {
        await _save();
      } catch (_) {
        /* Still attempt server revocation. */
      }
      await _logout();
    }
  }

  Future<void> _cancelPending() async {
    final p = _pending;
    if (p == null) return;
    p['cancelled'] = true;
    try {
      await _save();
    } catch (_) {
      /* Server cancellation must still run. */
    }
    if (p['id'] == null && _active) {
      return; // Start response will finish cancellation.
    }
    if (p['id'] != null) {
      try {
        await api.request(
          'POST',
          '/merchant-auth/attempts/${p['id']}/cancel',
          body: {'attemptSecret': p['secret']},
        );
      } on HandoffFailure catch (e) {
        if (e.code != 'MERCHANT_AUTH_EXPIRED') rethrow;
      }
    }
    journal.remove('pending');
    journal.remove('tokens');
    await _save();
  }

  @override
  Future<void> signOut() async {
    ++_generation;
    await _load();
    if (_pending != null) {
      await cancel();
      return;
    }
    journal['logout'] = true;
    try {
      await _save();
    } catch (_) {
      /* Server revocation is still required. */
    }
    await _logout();
  }

  Future<void> _logout() async {
    if (_tokens != null) {
      if (journal['refreshing'] == true ||
          !DateTime.parse(_tokens!['until']).isAfter(clock())) {
        try {
          // Logout-only recovery: reuse revokes a lost rotation; a returned pair
          // is used solely to revoke. Never restore identity from this branch.
          final response = await api.request(
            'POST',
            '/merchant-auth/refresh',
            body: {'refreshToken': _tokens!['refresh']},
          );
          journal['tokens'] = _tokenResponse(response);
          journal.remove('refreshing');
        } on HandoffFailure catch (e) {
          if (e.status != 401) rethrow;
          journal.clear();
          await _save();
          return;
        }
      }
      try {
        await api.request(
          'POST',
          '/merchant-auth/logout',
          access: _tokens!['access'],
        );
      } on HandoffFailure catch (e) {
        if (e.status != 401) rethrow;
      }
    }
    journal.clear();
    await _save();
  }
}
