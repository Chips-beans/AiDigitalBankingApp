import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../collect/merchant_collect.dart';
import 'merchant_shop.dart';

/// A registration intent saved with its idempotency key before sending.
@immutable
class PendingRegistration {
  const PendingRegistration(this.key, this.draft);
  final String key;
  final ShopDraft draft;
}

enum ShopNotice { none, saved, conflict, uncertain }

/// Owns the shop profile, the durable registration intent and logo staging.
///
/// Registration is never re-sent automatically: an uncertain result keeps the
/// saved intent and waits for the owner to check its status explicitly.
class ShopController extends ChangeNotifier {
  ShopController(this.gateway, this.store, {this.ownerId = 0, this.onExpired});
  final MerchantShopGateway gateway;
  final HandoffStore store;
  final VoidCallback? onExpired;

  /// Saved intents are scoped to one owner and never sent for another.
  final int ownerId;
  String get _slot => 'registration-$ownerId';

  ShopProfile? profile;

  /// Today's totals and recent payments; null until the first successful load.
  ShopDashboard? dashboard;
  PendingRegistration? pending;
  ShopFailure? failure;
  ShopNotice notice = ShopNotice.none;
  bool loading = false, submitting = false, uploadingLogo = false;
  Uint8List? logoBytes;
  String? _logoFor;
  bool _disposed = false;

  ShopDetails? get shop => profile?.shop;

  Future<void> initialize() async {
    try {
      final raw = await store.read(_slot);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        pending = PendingRegistration(
          json['key'] as String,
          ShopDraft.fromJson(Map<String, dynamic>.from(json['draft'] as Map)),
        );
      }
    } catch (_) {
      await _savePending(null);
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (loading || _disposed) return;
    loading = true;
    failure = null;
    _notify();
    try {
      final loaded = await gateway.dashboard();
      dashboard = loaded;
      _accept(loaded.profile);
      if (profile?.shop != null && pending != null) await _savePending(null);
    } on ShopFailure catch (e) {
      _fail(e);
    } catch (_) {
      _fail(const ShopFailure('INVALID_RESPONSE'));
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Sends [draft], or the saved intent when one exists. Returns true on success.
  Future<bool> register(ShopDraft draft) async {
    if (submitting || _disposed) return false;
    submitting = true;
    failure = null;
    notice = ShopNotice.none;
    _notify();
    final intent = pending ?? PendingRegistration(randomCredential(), draft);
    try {
      // Persist first: a process death after sending must not lose the key.
      await _savePending(intent);
      _accept(await gateway.register(intent.key, intent.draft));
      await _savePending(null);
      notice = ShopNotice.saved;
      return true;
    } on ShopFailure catch (e) {
      if (e.uncertain) {
        notice = ShopNotice.uncertain;
      } else {
        // The server rejected the request, so nothing was created for this key.
        await _savePending(null);
        if (e.code == 'MERCHANT_ALREADY_REGISTERED') unawaited(refresh());
      }
      _fail(e);
      return false;
    } catch (_) {
      // Secure storage failed: nothing is sent without a durable intent.
      _fail(const ShopFailure('STORAGE_UNAVAILABLE'));
      return false;
    } finally {
      submitting = false;
      _notify();
    }
  }

  Future<void> discardPending() async {
    if (submitting) return;
    notice = ShopNotice.none;
    failure = null;
    await _savePending(null);
    _notify();
  }

  /// Uploads a logo and returns its staged ID (null on failure).
  Future<String?> stageLogo(Uint8List bytes, String filename) async {
    if (uploadingLogo || _disposed) return null;
    if (bytes.length > 5 * 1024 * 1024) {
      _fail(const ShopFailure('MERCHANT_LOGO_TOO_LARGE'));
      _notify();
      return null;
    }
    uploadingLogo = true;
    failure = null;
    _notify();
    try {
      return await gateway.uploadLogo(bytes, filename);
    } on ShopFailure catch (e) {
      _fail(e);
      return null;
    } finally {
      uploadingLogo = false;
      _notify();
    }
  }

  /// Applies changed fields under the last-read version.
  Future<bool> update(Map<String, Object?> changes) async {
    final current = shop;
    if (current == null || submitting || _disposed) return false;
    submitting = true;
    failure = null;
    notice = ShopNotice.none;
    _notify();
    try {
      _accept(await gateway.update(current.version, changes));
      notice = ShopNotice.saved;
      return true;
    } on ShopFailure catch (e) {
      _fail(e);
      if (e.code == 'MERCHANT_PROFILE_CONFLICT') {
        notice = ShopNotice.conflict;
        submitting = false;
        await refresh();
      }
      return false;
    } finally {
      submitting = false;
      _notify();
    }
  }

  void clearNotice() {
    if (notice == ShopNotice.none && failure == null) return;
    notice = ShopNotice.none;
    failure = null;
    _notify();
  }

  void _accept(ShopProfile value) {
    profile = value;
    final logoId = value.shop?.logoId;
    if (logoId == null) {
      logoBytes = null;
      _logoFor = null;
    } else if (logoId != _logoFor) {
      _logoFor = logoId;
      unawaited(_loadLogo(logoId));
    }
  }

  Future<void> _loadLogo(String logoId) async {
    try {
      final bytes = await gateway.logo();
      if (_disposed || _logoFor != logoId) return;
      logoBytes = bytes;
      _notify();
    } catch (_) {
      // The shop initial remains the fallback; a missing logo never blocks the shop.
    }
  }

  void _fail(ShopFailure e) {
    failure = e;
    if (e.expired) onExpired?.call();
  }

  Future<void> _savePending(PendingRegistration? value) async {
    pending = value;
    await store.write(
      _slot,
      value == null
          ? null
          : jsonEncode({'key': value.key, 'draft': value.draft.toJson()}),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
