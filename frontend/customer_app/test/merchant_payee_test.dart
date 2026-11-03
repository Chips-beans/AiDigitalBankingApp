import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/qr/qr_gateway.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show sampleQr, signedSession;
import 'transactions_test.dart' show FakeTransactions, funded;

Map<String, Object?> scan({Map<String, Object?>? merchant, String name = 'Kesor Coffee'}) => {
  'valid': true,
  'qrString': sampleQr,
  'qrHash': 'a' * 32,
  'destinationAccountNumber': '1000000009',
  'destinationAccountName': name,
  'currency': 'USD',
  'isDynamic': false,
  'isAlreadyPaid': false,
  'amount': null,
  'remark': null,
  'merchant': merchant,
  'expiresAt': null,
};

const shop = {
  'merchantId': 'MCH-AB23CD45',
  'storeName': 'Kesor Coffee',
  'categoryCode': 'FOOD_DRINK',
  'hasLogo': false,
  'verified': true,
};

void main() {
  test('a verified Merchant QR carries the shop; people stay plain', () {
    final preview = QrPreview.fromJson(scan(merchant: shop));
    expect(preview.shop!.storeName, 'Kesor Coffee');
    expect(preview.shop!.merchantId, 'MCH-AB23CD45');
    expect(QrPreview.fromJson(scan(name: 'Sok Dara')).shop, isNull);
  });

  test('an inconsistent or unverified shop is rejected', () {
    for (final bad in [
      {...shop, 'verified': false},
      {...shop, 'merchantId': '../other'},
      {...shop, 'storeName': 'Another Shop'},
      {...shop, 'storeName': ''},
    ]) {
      expect(() => QrPreview.fromJson(scan(merchant: bad)), throwsA(anything), reason: '$bad');
    }
  });

  testWidgets('a scanned shop shows as a verified shop without a person lookup', (tester) async {
    final session = await signedSession();
    final accounts = AccountsController(
      session,
      FakeAccounts()..data = [funded(1)],
      MemoryCreationStore(),
    );
    await accounts.initialize();
    final transfers = TransferController(session, FakeTransactions(), MemoryTransferStore());
    await transfers.initialize();
    final prefs = AppPreferences();
    await tester.pumpWidget(
      AppPreferencesScope(
        preferences: prefs,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: KesorTransferScreen(
            controller: transfers,
            accounts: accounts,
            enabled: true,
            onBack: () {},
            favorites: RecipientFavoritesStore(),
            prefill: const TransferPrefill(
              '1000000009',
              name: 'Kesor Coffee',
              qrString: sampleQr,
              shop: ShopPayee(
                merchantId: 'MCH-AB23CD45',
                storeName: 'Kesor Coffee',
                currency: 'USD',
                hasLogo: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-verified-shop')), findsOneWidget);
    expect(find.text('Kesor Coffee'), findsWidgets);
    expect(find.text('No active Kesor account uses this number.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    transfers.dispose();
    accounts.dispose();
    session.dispose();
    prefs.dispose();
  });
}
