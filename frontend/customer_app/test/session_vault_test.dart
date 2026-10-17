import 'package:customer_app/core/storage/session_vault.dart';
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
}
