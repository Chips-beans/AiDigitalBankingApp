import 'dart:async';
import 'dart:convert';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../../core/merchant_config.dart';
import 'merchant_session.dart';

/// One durable journal per installation/API origin. Credentials never enter UI or links.
class MerchantApiAuth
    implements RestorableMerchantAuth, MerchantAccess, MerchantApprovalTiming {
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
    final raw = await _storage(
      () => store.read('auth'),
      MerchantAuthStage.storageRead,
    );
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        for (final key in ['pending', 'tokens']) {
          if (decoded[key] != null && decoded[key] is! Map<String, dynamic>) {
            throw const FormatException();
          }
        }
        final pending = decoded['pending'] as Map<String, dynamic>?;
        final tokens = decoded['tokens'] as Map<String, dynamic>?;
        if ((pending != null &&
                DateTime.tryParse(
                      pending['expiresAt'] is String
                          ? pending['expiresAt']
                          : '',
                    ) ==
                    null) ||
            (tokens != null &&
                (tokens['access'] is! String ||
                    tokens['refresh'] is! String ||
                    DateTime.tryParse(
                          tokens['until'] is String ? tokens['until'] : '',
                        ) ==
                        null))) {
          throw const FormatException();
        }
        journal = decoded;
      } catch (_) {
        throw const MerchantAuthFailure(
          MerchantAuthIssue.storageUnavailable,
          diagnostic: MerchantAuthDiagnostic(
            MerchantAuthStage.storageRead,
            'STORAGE_INVALID',
          ),
        );
      }
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
        throw const MerchantAuthFailure(
          MerchantAuthIssue.storageUnavailable,
          diagnostic: MerchantAuthDiagnostic(
            MerchantAuthStage.storageWrite,
            'STORAGE_UNAVAILABLE',
          ),
        );
      }
    });
    _writes = flight;
    return flight;
  }

  Map<String, dynamic>? get _pending =>
      journal['pending'] as Map<String, dynamic>?;
  @override
  Duration? get approvalRemaining {
    final expiry = DateTime.tryParse(_pending?['expiresAt'] as String? ?? '');
    if (expiry == null) return null;
    final left = expiry.difference(clock());
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, dynamic>? get _tokens =>
      journal['tokens'] as Map<String, dynamic>?;
  bool _current(int generation) => generation == _generation;

  Future<T> _storage<T>(
    Future<T> Function() work,
    MerchantAuthStage stage,
  ) async {
    try {
      return await work();
    } catch (_) {
      throw MerchantAuthFailure(
        MerchantAuthIssue.storageUnavailable,
        diagnostic: MerchantAuthDiagnostic(stage, 'STORAGE_UNAVAILABLE'),
      );
    }
  }

  Future<T> _at<T>(MerchantAuthStage stage, Future<T> Function() work) async {
    try {
      return await work();
    } on MerchantAuthFailure {
      rethrow;
    } on HandoffFailure catch (e) {
      throw MerchantAuthFailure.fromHandoff(e, stage);
    } catch (_) {
      throw MerchantAuthFailure(
        MerchantAuthIssue.unavailable,
        diagnostic: MerchantAuthDiagnostic(stage, 'UNKNOWN_ERROR'),
      );
    }
  }

  Future<dynamic> _request(
    MerchantAuthStage stage,
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? access,
  }) => _at(stage, () => api.request(method, path, body: body, access: access));
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
      throw MerchantAuthFailure.fromHandoff(e, MerchantAuthStage.unknown);
    } catch (_) {
      throw const MerchantAuthFailure(
        MerchantAuthIssue.unavailable,
        diagnostic: MerchantAuthDiagnostic(
          MerchantAuthStage.unknown,
          'UNKNOWN_ERROR',
        ),
      );
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
        throw const MerchantAuthFailure(
          MerchantAuthIssue.uncertain,
          diagnostic: MerchantAuthDiagnostic(
            MerchantAuthStage.exchange,
            'EXCHANGE_RECOVERY_REQUIRED',
          ),
        );
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
    if (config.environment != 'dev') {
      throw const MerchantAuthFailure(
        MerchantAuthIssue.unsupportedBuild,
        diagnostic: MerchantAuthDiagnostic(
          MerchantAuthStage.configuration,
          'HANDOFF_UNSUPPORTED_BUILD',
        ),
      );
    }
    if (journal['logout'] == true) await _logout();
    if (_pending?['cancelled'] == true) await _cancelPending();
    if (_pending?['code'] != null) {
      throw const MerchantAuthFailure(
        MerchantAuthIssue.uncertain,
        diagnostic: MerchantAuthDiagnostic(
          MerchantAuthStage.exchange,
          'EXCHANGE_RECOVERY_REQUIRED',
        ),
      );
    }
    // A failed start with no ID cannot be approved or exchanged. Clear only
    // that incomplete draft; known attempts and recovery bodies stay immutable.
    if (_pending != null && _pending!['id'] == null) {
      journal.remove('pending');
      await _save();
    }
    final generation = ++_generation;
    if (_tokens != null) return _identity(generation);
    if (_pending != null) return _wait(generation);
    await _at(MerchantAuthStage.verifyCustomer, native.verify);
    _check(generation);
    var installation = await _storage(
      () => store.read('installation'),
      MerchantAuthStage.storageRead,
    );
    if (installation == null) {
      installation = randomCredential();
      await _storage(
        () => store.write('installation', installation),
        MerchantAuthStage.storageWrite,
      );
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
    try {
      final data = await _request(
        MerchantAuthStage.createAttempt,
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
          data['attemptId'] is! String ||
          !attemptId(data['attemptId']) ||
          data['customerPackage'] != customerPackage ||
          data['approvalUri'] is! String ||
          data['expiresAt'] is! String ||
          DateTime.tryParse(data['expiresAt']) == null) {
        throw MerchantAuthFailure.fromHandoff(
          const HandoffFailure('INVALID_RESPONSE'),
          MerchantAuthStage.createAttempt,
        );
      }
      final link = await _at(
        MerchantAuthStage.createAttempt,
        () async => exactLink(data['approvalUri'], approvalBase, {
          'attemptId',
          'handoffToken',
        }),
      );
      if (link['attemptId'] != data['attemptId'] ||
          !credential(link['handoffToken'])) {
        throw MerchantAuthFailure.fromHandoff(
          const HandoffFailure('INVALID_RESPONSE'),
          MerchantAuthStage.createAttempt,
        );
      }
      p['id'] = data['attemptId'];
      p['approvalUri'] = data['approvalUri'];
      final expires = DateTime.parse(data['expiresAt']);
      if (expires.isBefore(DateTime.parse(p['expiresAt']))) {
        p['expiresAt'] = expires.toIso8601String();
      }
    } catch (_) {
      if (p['id'] == null && identical(_pending, p)) {
        journal.remove('pending');
        await _save();
      }
      rethrow;
    }
    await _save();
    if (!_current(generation) || p['cancelled'] == true) {
      await _cancelPending();
      _check(generation);
    }
    try {
      await _at(
        MerchantAuthStage.openCustomer,
        () => native.open(p['approvalUri']),
      );
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
      final raw = await _at(MerchantAuthStage.awaitApproval, native.take);
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
          final status = await _request(
            MerchantAuthStage.awaitApproval,
            'POST',
            '/merchant-auth/attempts/${p['id']}/status',
            body: {'attemptSecret': p['secret']},
          );
          _check(generation);
          if (status is! Map || status['attemptId'] != p['id']) {
            throw MerchantAuthFailure.fromHandoff(
              const HandoffFailure('INVALID_RESPONSE'),
              MerchantAuthStage.awaitApproval,
            );
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
        } on MerchantAuthFailure catch (e) {
          if (e.issue != MerchantAuthIssue.offline) rethrow;
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
    late Map<String, dynamic> tokenData;
    try {
      tokenData = await _at(
        MerchantAuthStage.exchange,
        () async => _tokenResponse(
          await api.request(
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
          ),
        ),
      );
    } on MerchantAuthFailure catch (e) {
      if (e.issue == MerchantAuthIssue.offline ||
          e.issue == MerchantAuthIssue.invalidResponse ||
          (e.diagnostic?.httpStatus ?? 0) >= 500) {
        throw MerchantAuthFailure(
          MerchantAuthIssue.uncertain,
          diagnostic: e.diagnostic,
        );
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
    journal['tokens'] = tokenData;
    // One atomic vault write: save credentials and erase attempt secrets together.
    journal.remove('pending');
    await _save();
    _check(generation);
    return _identity(generation);
  }

  Map<String, dynamic> _tokenResponse(dynamic data) {
    if (data is! Map ||
        data['accessToken'] is! String ||
        data['accessToken'].isEmpty ||
        data['refreshToken'] is! String ||
        data['refreshToken'].isEmpty ||
        data['expiresInMs'] is! num ||
        !(data['expiresInMs'] as num).isFinite ||
        data['expiresInMs'] <= 0) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
    try {
      return {
        'access': data['accessToken'],
        'refresh': data['refreshToken'],
        'until': clock()
            .add(Duration(milliseconds: (data['expiresInMs'] as num).toInt()))
            .toIso8601String(),
      };
    } catch (_) {
      throw const HandoffFailure('INVALID_RESPONSE');
    }
  }

  Future<MerchantIdentity> _identity(int generation) async {
    if (_tokens == null) {
      throw const MerchantAuthFailure(MerchantAuthIssue.expired);
    }
    if (journal['refreshing'] == true) {
      // Never replay a rotating refresh whose response may have been lost.
      journal['logout'] = true;
      await _save();
      throw const MerchantAuthFailure(
        MerchantAuthIssue.expired,
        diagnostic: MerchantAuthDiagnostic(
          MerchantAuthStage.refresh,
          'REFRESH_UNCERTAIN',
        ),
      );
    }
    if (!DateTime.parse(_tokens!['until'])
        .isAfter(clock().add(const Duration(seconds: 10)))) {
      await _refresh(generation);
    }
    dynamic data;
    try {
      data = await _request(
        MerchantAuthStage.identity,
        'GET',
        '/merchant-auth/session',
        access: _tokens!['access'],
      );
    } on MerchantAuthFailure catch (e) {
      if (e.diagnostic?.httpStatus == 401) {
        journal.remove('tokens');
        await _save();
        throw MerchantAuthFailure(
          MerchantAuthIssue.expired,
          diagnostic: e.diagnostic,
        );
      }
      rethrow;
    }
    _check(generation);
    if (data is! Map ||
        data['ownerId'] is! int ||
        data['ownerId'] <= 0 ||
        data['clientId'] != merchantClient ||
        data['sessionId'] is! String ||
        !attemptId(data['sessionId'])) {
      throw MerchantAuthFailure.fromHandoff(
        const HandoffFailure('INVALID_RESPONSE'),
        MerchantAuthStage.identity,
      );
    }
    final state = data['onboardingState'];
    if (![
      'SHOP_REQUIRED',
      'READY',
      'RESTRICTED',
      'RECOVERY_REQUIRED',
    ].contains(state)) {
      throw MerchantAuthFailure.fromHandoff(
        const HandoffFailure('INVALID_RESPONSE'),
        MerchantAuthStage.identity,
      );
    }
    final shop = data['shop'];
    if (['READY', 'RESTRICTED'].contains(state) &&
        (shop is! Map ||
            shop['merchantId'] is! String ||
            shop['storeName'] is! String)) {
      throw MerchantAuthFailure.fromHandoff(
        const HandoffFailure('INVALID_RESPONSE'),
        MerchantAuthStage.identity,
      );
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
    final data = await _request(
      MerchantAuthStage.refresh,
      'POST',
      '/merchant-auth/refresh',
      body: {'refreshToken': refresh},
    );
    _check(generation);
    journal['tokens'] = await _at(
      MerchantAuthStage.refresh,
      () async => _tokenResponse(data),
    );
    journal.remove('refreshing');
    await _save();
  }

  @override
  Future<String> accessToken() async {
    // Share the single-flight guard so a rotation never races another rotation.
    for (var waited = 0; _active; waited++) {
      if (waited >= 300) throw const MerchantAuthUnavailable();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _guard(() async {
      await _load();
      if (_tokens == null ||
          journal['refreshing'] == true ||
          journal['logout'] == true ||
          _pending != null) {
        throw const MerchantAuthFailure(MerchantAuthIssue.expired);
      }
      if (!DateTime.parse(_tokens!['until'])
          .isAfter(clock().add(const Duration(seconds: 10)))) {
        await _refresh(_generation);
      }
      return _tokens!['access'] as String;
    });
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
    await _at(
      MerchantAuthStage.openCustomer,
      () => native.open(p['approvalUri']),
    );
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
        await _request(
          MerchantAuthStage.cancel,
          'POST',
          '/merchant-auth/attempts/${p['id']}/cancel',
          body: {'attemptSecret': p['secret']},
        );
      } on MerchantAuthFailure catch (e) {
        if (e.diagnostic?.safeCode != 'MERCHANT_AUTH_EXPIRED') rethrow;
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
          final response = await _request(
            MerchantAuthStage.logout,
            'POST',
            '/merchant-auth/refresh',
            body: {'refreshToken': _tokens!['refresh']},
          );
          journal['tokens'] = _tokenResponse(response);
          journal.remove('refreshing');
        } on MerchantAuthFailure catch (e) {
          if (e.diagnostic?.httpStatus != 401) rethrow;
          journal.clear();
          await _save();
          return;
        }
      }
      try {
        await _request(
          MerchantAuthStage.logout,
          'POST',
          '/merchant-auth/logout',
          access: _tokens!['access'],
        );
      } on MerchantAuthFailure catch (e) {
        if (e.diagnostic?.httpStatus != 401) rethrow;
      }
    }
    journal.clear();
    await _save();
  }
}
