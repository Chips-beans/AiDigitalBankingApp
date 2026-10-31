import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const usd = FavoriteRecipient('1000000002', 'USD');
  const khr = FavoriteRecipient('1000000003', 'KHR');
  test(
    'encrypted bookmarks survive store recreation and isolate owners and APIs',
    () async {
      final store = RecipientFavoritesStore(namespace: 'api|dev');
      await store.add(1, usd);
      final restored = await RecipientFavoritesStore(namespace: 'api|dev')
          .read(1);
      expect(restored.single.toJson(), usd.toJson());
      expect(await store.read(2), isEmpty);
      expect(
        await RecipientFavoritesStore(namespace: 'other|dev').read(1),
        isEmpty,
      );
      await store.remove(1, usd);
      expect(await store.read(1), isEmpty);
    },
  );
  test(
    'concurrent stores retain both recipients and deduplicate a repeated save',
    () async {
      final a = RecipientFavoritesStore(namespace: 'race');
      final b = RecipientFavoritesStore(namespace: 'race');
      await Future.wait([a.add(1, usd), b.add(1, khr), a.add(1, usd)]);
      expect((await b.read(1)).map((r) => r.number), [usd.number, khr.number]);
    },
  );
  test(
    'corrupt storage is preserved and cannot be replaced by a new favorite',
    () async {
      final store = RecipientFavoritesStore(namespace: 'corrupt');
      await store.add(1, usd);
      const storage = FlutterSecureStorage();
      final key = (await storage.readAll()).keys.single;
      await storage.write(key: key, value: '{broken');
      await expectLater(store.read(1), throwsA(isA<ApiFailure>()));
      await expectLater(store.add(1, khr), throwsA(isA<ApiFailure>()));
      expect(await storage.read(key: key), '{broken');
    },
  );
  test('manual favorites keep their custom name and stay manual after a transfer bookmark', () async {
    final store = RecipientFavoritesStore(namespace: 'names');
    await store.add(
      1,
      const FavoriteRecipient('1000000002', 'USD', name: 'Mom', manual: true),
    );
    expect(
      (await RecipientFavoritesStore(namespace: 'names').read(1)).single.name,
      'Mom',
    );
    await store.add(1, usd);
    expect((await store.read(1)).single.name, 'Mom');
    expect((await store.read(1)).single.manual, isTrue);
    await store.add(
      1,
      const FavoriteRecipient('1000000002', 'USD', name: 'Mum'),
    );
    expect((await store.read(1)).single.name, 'Mum');
    await expectLater(
      store.add(1, const FavoriteRecipient('1000000003', 'KHR', name: ' ')),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'invalid account identifiers and unsupported currencies are refused',
    () async {
      final store = RecipientFavoritesStore();
      for (final invalid in [
        const FavoriteRecipient('012345678', 'USD'),
        const FavoriteRecipient('1000000002', 'EUR'),
      ]) {
        await expectLater(store.add(1, invalid), throwsA(isA<ApiFailure>()));
      }
      expect(await store.read(1), isEmpty);
    },
  );
}
