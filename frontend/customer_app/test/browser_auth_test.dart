import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser installation identity is stable and distinct without integer overflow', () async {
    final first = MemorySessionVault();
    final id = await first.installationId();
    expect(id, matches(RegExp(r'^browser-[0-9a-f]{48}$')));
    expect(await first.installationId(), id);
    expect(await MemorySessionVault().installationId(), isNot(id));
  });
  test('verified incomplete browser profile resumes and completes without a password', () async {
    final gateway = DemoAuthGateway();
    final vault = MemorySessionVault();
    final first = SessionController(gateway, vault, deviceType: 'WEB');
    await first.initialize();
    first.openEmail();
    expect(await first.beginEmail('browser@example.test'), true);
    expect(await first.verifyCode('123456'), true);
    expect(first.identity!.profileComplete, false);
    first.dispose();
    final restored = SessionController(gateway, vault, deviceType: 'WEB');
    await restored.initialize();
    expect(restored.identity!.profileComplete, false);
    await restored.completeInformation('Dara', 'Sok');
    expect(restored.identity!.profileComplete, true);
    await restored.signOut();
    restored.dispose();
  });
}
