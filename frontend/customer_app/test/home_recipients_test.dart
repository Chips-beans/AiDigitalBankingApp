import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(440, 999),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  const empty = KesorHomeData(khrBalance: '0', usdBalance: r'$0.00');

  testWidgets('without favorites Home invites saving people, not history', (
    tester,
  ) async {
    await show(
      tester,
      const KesorHomeScreen(
        data: KesorHomeData(
          khrBalance: '0',
          usdBalance: r'$0.00',
          transactions: [
            HomeTransaction(
              name: 'History Person',
              time: '9:00 AM',
              amount: r'-$1',
              incoming: false,
            ),
          ],
        ),
      ),
    );
    final card = find.byKey(const ValueKey('home-recipients-card'));
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('home-recipients-empty')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('History Person')),
      findsNothing,
    );
    await show(
      tester,
      const KesorHomeScreen(data: empty),
      size: const Size(320, 568),
      scale: 2,
    );
    expect(find.byKey(const ValueKey('home-recipients-empty')), findsOneWidget);
  });

  testWidgets(
    'Add to favorites requires only the number and accepts a custom name',
    (tester) async {
      final saves = <(String, String?)>[];
      String? reply = 'No Kesor account uses this number.';
      await show(
        tester,
        KesorHomeScreen(
          data: empty,
          onSaveRecipient: (number, name) async {
            saves.add((number, name));
            return reply;
          },
        ),
      );
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('home-add-recipient-save'));
      final number = find.byKey(const ValueKey('home-add-recipient-number'));
      final name = find.byKey(const ValueKey('home-add-recipient-name'));

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saves, isEmpty, reason: 'The number is required');

      await tester.enterText(number, '12ab34');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saves, isEmpty, reason: 'Numbers need 10 to 20 digits');

      await tester.enterText(number, '1000000002');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saves.single, ('1000000002', null));
      expect(
        find.byKey(const ValueKey('home-add-recipient-error')),
        findsOneWidget,
      );

      reply = null;
      await tester.enterText(name, '  Mom  ');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saves.last, ('1000000002', 'Mom'));
      expect(find.byKey(const ValueKey('home-add-recipient')), findsNothing);
    },
  );

  testWidgets('saved favorites show their names and open a transfer', (
    tester,
  ) async {
    final opened = <String>[];
    final removed = <String?>[];
    await show(
      tester,
      KesorHomeScreen(
        data: empty.withRecipients(const [
          HomeRecipient('Mom', accountNumber: '1000000002', knownName: 'Dara'),
        ]),
        onRecipient: (number, _) => opened.add(number),
        onRemoveRecipient: (person) async => removed.add(person.accountNumber),
      ),
    );
    expect(find.byKey(const ValueKey('home-recipients-empty')), findsNothing);
    await tester.tap(find.byTooltip('Mom'));
    expect(opened, ['1000000002']);

    await tester.tap(find.byTooltip('All favorite recipients'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('home-saved-recipient-1000000002'));
    expect(row, findsOneWidget);
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();
    expect(removed, ['1000000002']);
  });
}
