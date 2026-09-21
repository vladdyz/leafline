import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receipt_tracker/main.dart' as app;

/// The one test that runs the real app on a real device.
///
/// Everything else in this suite substitutes something: an in-memory database,
/// a fake photo source, a fake OCR service, a pinned clock. That is what makes
/// those tests fast and deterministic, and it is also what they cannot prove.
///
/// This proves the parts that only exist on a device:
///
/// - `path_provider` returns somewhere writable and `getDatabasesPath` works
/// - the migration ladder runs against a real sqflite, not the FFI one
/// - startup completes — week materialisation, retention sweep, orphan sweep,
///   notification channel — without throwing
/// - navigation and a real write work end to end
///
/// It deliberately makes no assumption about what is already on the device. It
/// adds an expense under a merchant name unique to this run and looks for that,
/// so it passes on an empty install and on one with a year of history.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches, adds an expense, and shows it in the week list', (
    tester,
  ) async {
    final merchant = 'IT ${DateTime.now().microsecondsSinceEpoch}';

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Startup got as far as drawing the list. On a device that means the
    // database opened, migrated and materialised the current week.
    expect(find.text('LeafLine'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '4.25',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Merchant (optional)'),
      merchant,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text(merchant), findsOneWidget);
  });

  testWidgets('settings opens and reports storage', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Default weekly budget'), findsOneWidget);
    expect(find.text('Receipt photos'), findsOneWidget);

    // The storage line reads the real documents directory. Either figure is
    // fine; what matters is that it resolved rather than staying on the
    // loading text.
    expect(find.text('Checking storage\u2026'), findsNothing);
  });
}
