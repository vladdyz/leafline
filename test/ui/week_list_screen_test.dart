import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/budget_repository.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';
import 'package:receipt_tracker/ui/screens/week_list_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late BudgetRepository budgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    budgets = BudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_widget_test');
  });

  tearDown(() async {
    await expenses.dispose();
    await budgets.dispose();
    await database.close();
    if (documents.existsSync()) {
      await documents.delete(recursive: true);
    }
  });

  Future<void> pumpList(WidgetTester tester) => pumpApp(
    tester,
    home: const WeekListScreen(),
    database: database,
    documents: documents,
  );

  group('budgetMessage', () {
    // Pure function, so its wording is pinned here rather than asserted
    // through a rendered widget.
    test('under budget reports what is left', () {
      expect(
        budgetMessage(spentCents: 5000, budgetCents: 20000),
        r'$50.00 of $200 — $150.00 left',
      );
    });

    test('approaching still reports what is left', () {
      expect(
        budgetMessage(spentCents: 16400, budgetCents: 20000),
        r'$164.00 of $200 — $36.00 left',
      );
    });

    test('over reports the overage', () {
      expect(
        budgetMessage(spentCents: 25000, budgetCents: 20000),
        r'$250.00 of $200 — over by $50.00',
      );
    });

    test('no budget set says so rather than dividing by zero', () {
      expect(
        budgetMessage(spentCents: 5000, budgetCents: 0),
        r'$50.00 spent — no budget set',
      );
    });
  });

  group('WeekListScreen empty state', () {
    testWidgets('shows a prompt when there are no expenses', (tester) async {
      await pumpList(tester);

      expect(find.text('No expenses yet'), findsOneWidget);
      expect(find.text('Tap Add to log your first one.'), findsOneWidget);
    });

    testWidgets('still offers the add button', (tester) async {
      await pumpList(tester);
      expect(find.widgetWithText(FloatingActionButton, 'Add'), findsOneWidget);
    });
  });

  group('WeekListScreen with data', () {
    setUp(() async {
      await budgets.setWeeklyCents(20000, now: DateTime(2026, 9, 14));
      await expenses.insert(
        makeExpense(
          id: 'a',
          amountCents: 12000,
          spentOn: DateTime(2026, 9, 15),
          merchant: 'Corner Market',
          category: ExpenseCategory.groceries,
        ),
      );
      await expenses.insert(
        makeExpense(
          id: 'b',
          amountCents: 4400,
          spentOn: DateTime(2026, 9, 17),
          merchant: 'Cafe Diem',
          category: ExpenseCategory.coffee,
        ),
      );
      await expenses.insert(
        // Previous week, so grouping has something to separate.
        makeExpense(
          id: 'c',
          amountCents: 3000,
          spentOn: DateTime(2026, 9, 9),
          merchant: 'Old Thing',
        ),
      );
    });

    testWidgets('renders every expense', (tester) async {
      await pumpList(tester);

      expect(find.text('Corner Market'), findsOneWidget);
      expect(find.text('Cafe Diem'), findsOneWidget);
      expect(find.text('Old Thing'), findsOneWidget);
    });

    testWidgets('groups into two weeks with separate totals', (tester) async {
      await pumpList(tester);

      // Scoped to the header rather than a bare find.text: the old week has a
      // single $30 expense, so its total and its only tile render the same
      // string. A bare finder matches both and says nothing about grouping.
      Finder headerTotal(String amount) => find.descendant(
        of: find.byType(WeekHeader),
        matching: find.text(amount),
      );

      expect(headerTotal(r'$164.00'), findsOneWidget);
      expect(headerTotal(r'$30.00'), findsOneWidget);
      expect(find.byType(WeekHeader), findsNWidgets(2));
    });

    testWidgets('shows a budget bar per week', (tester) async {
      await pumpList(tester);
      expect(find.byType(BudgetBar), findsNWidgets(2));
    });

    testWidgets('budget bar reports the approaching state', (tester) async {
      await pumpList(tester);
      expect(find.text(r'$164.00 of $200 — $36.00 left'), findsOneWidget);
    });

    testWidgets('tapping an expense opens it for editing', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Cafe Diem'));
      await tester.pumpAndSettle();

      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });
  });

  group('adding an expense', () {
    testWidgets('appears in the list after saving', (tester) async {
      await pumpList(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '12.40',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Merchant (optional)'),
        'New Place',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('New Place'), findsOneWidget);
      expect(find.text(r'$12.40'), findsWidgets);
    });

    testWidgets('rejects an empty amount', (tester) async {
      await pumpList(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount'), findsOneWidget);
      // Still on the form rather than popped back to the list.
      expect(find.text('Add expense'), findsWidgets);
    });

    testWidgets('rejects an unparseable amount', (tester) async {
      await pumpList(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '1.2.3',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('Not a valid amount'), findsOneWidget);
    });
  });

  group('deleting an expense', () {
    setUp(() async {
      await expenses.insert(
        makeExpense(
          id: 'del',
          amountCents: 999,
          spentOn: DateTime(2026, 9, 17),
          merchant: 'Doomed',
        ),
      );
    });

    testWidgets('swiping removes it and offers undo', (tester) async {
      await pumpList(tester);
      expect(find.text('Doomed'), findsOneWidget);

      await tester.drag(find.text('Doomed'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Doomed'), findsNothing);
      expect(find.text('Expense deleted'), findsOneWidget);
      expect(await expenses.getById('del'), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('undo restores the original row', (tester) async {
      await pumpList(tester);

      await tester.drag(find.text('Doomed'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Doomed'), findsOneWidget);

      // A true reversal: same id, not a lookalike with a fresh one.
      final restored = await expenses.getById('del');
      expect(restored, isNotNull);
      expect(restored!.amountCents, 999);
    });
  });

  group('SettingsScreen', () {
    testWidgets('saves a budget and the list picks it up', (tester) async {
      await expenses.insert(
        makeExpense(
          id: 'a',
          amountCents: 16400,
          spentOn: DateTime(2026, 9, 17),
        ),
      );
      await pumpList(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount per week'),
        '200',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
      await tester.pumpAndSettle();

      expect((await budgets.get()).weeklyCents, 20000);

      // 'Budget saved' carries no action, so it still auto-dismisses.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('prefills the existing budget', (tester) async {
      await budgets.setWeeklyCents(15000, now: DateTime(2026, 9, 14));

      await pumpApp(
        tester,
        home: const SettingsScreen(),
        database: database,
        documents: documents,
      );

      expect(find.text('150.00'), findsOneWidget);
    });

    testWidgets('rejects an unparseable budget', (tester) async {
      await pumpApp(
        tester,
        home: const SettingsScreen(),
        database: database,
        documents: documents,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount per week'),
        '..',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
      await tester.pumpAndSettle();

      expect(find.text('Not a valid amount'), findsOneWidget);
    });
  });
}
