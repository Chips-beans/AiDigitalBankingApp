import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'secure vault persists only refresh and stable random installation ID',
    () async {
      final vault = SecureSessionVault('development-api');
      final id = await vault.installationId();
      expect(id, matches(RegExp(r'^[a-f0-9]{48}$')));
      await vault.writeRefreshToken('refresh-only');
      final next = SecureSessionVault('development-api');
      expect(await next.installationId(), id);
      expect(await next.readRefreshToken(), 'refresh-only');
      final values = await const FlutterSecureStorage().readAll();
      expect(values.length, 2);
      expect(values.values.toSet(), {id, 'refresh-only'});
      await next.writeRefreshToken(null);
      expect(await next.readRefreshToken(), null);
      expect(await next.installationId(), id);
    },
  );
  test('backend and mode namespaces isolate saved sessions', () async {
    final api = SecureSessionVault('api-a|api'),
        demo = SecureSessionVault('api-a|demo'),
        other = SecureSessionVault('api-b|api');
    await api.writeRefreshToken('a');
    expect(await demo.readRefreshToken(), null);
    expect(await other.readRefreshToken(), null);
    expect(await demo.installationId() == await api.installationId(), false);
  });
  test('opening uncertainty survives store recreation and isolates user/backend/mode', () async {
    final original = SecureCreationStore('api-a|api');
    await original.setPending(1, true);
    expect(await SecureCreationStore('api-a|api').pending(1), true);
    expect(await original.pending(2), false);
    expect(await SecureCreationStore('api-a|demo').pending(1), false);
    expect(await SecureCreationStore('api-b|api').pending(1), false);
    final values = await const FlutterSecureStorage().readAll();
    expect(values.values.toSet(), {'uncertain'});
    await original.setPending(1, false);
    expect(await SecureCreationStore('api-a|api').pending(1), false);
  });
  test(
    'overlapping secure marker operations stay ordered across store instances',
    () async {
      final first = SecureCreationStore('serial-api');
      final next = SecureCreationStore('serial-api');
      final write = first.setPending(1, true);
      final observed = next.pending(1);
      final clear = first.setPending(1, false);
      final afterClear = next.pending(1);
      await Future.wait([write, clear]);
      expect(await observed, true);
      expect(await afterClear, false);
    },
  );
}
