import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/ui/screens/all_weeks_screen.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';
import 'package:receipt_tracker/ui/screens/week_list_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  // 2026-09-14 is a Monday. "Now" is pinned to the Thursday of that week, so
  // these tests do not change behaviour depending on the day they run.
  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);
  final lastWeek = DateTime(2026, 9, 7);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_widget_test');
  });

  tearDown(() async {
    await expenses.dispose();
    await weekBudgets.dispose();
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
    now: now,
  );

  group('a tracked week with no expenses', () {
    testWidgets('still renders, with its budget bar', (tester) async {
      // The case the old expense-driven list could not show at all.
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpList(tester);

      expect(find.byType(WeekHeader), findsOneWidget);
      expect(find.byType(BudgetBar), findsOneWidget);
      expect(find.text(r'$0.00 of $200 — $200.00 left'), findsOneWidget);
      expect(find.text('Nothing logged yet this week.'), findsOneWidget);
    });

    testWidgets('a finished empty week reads as spending nothing', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(lastWeek, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpList(tester);

      expect(find.text('Nothing spent this week.'), findsOneWidget);
      expect(find.text('Nothing logged yet this week.'), findsOneWidget);
    });
  });

  group('untracked weeks', () {
    testWidgets('a week with no row does not appear', (tester) async {
      // Only this week is tracked; the weeks before it were never seen by the
      // app and must not be rendered as anything at all.
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpList(tester);

      expect(find.byType(WeekHeader), findsOneWidget);
    });
  });

  group('week list with data', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: DateTime(2026, 9, 1));
      await weekBudgets.ensureWeek(lastWeek, now: lastWeek);
      await weekBudgets.ensureWeek(thisWeek, now: now);

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
        makeExpense(
          id: 'c',
          amountCents: 3000,
          spentOn: DateTime(2026, 9, 9),
          merchant: 'Old Thing',
        ),
      );
    });

    testWidgets('renders both weeks and their expenses', (tester) async {
      await pumpList(tester);

      expect(find.byType(WeekHeader), findsNWidgets(2));
      expect(find.text('Corner Market'), findsOneWidget);
      expect(find.text('Cafe Diem'), findsOneWidget);
      expect(find.text('Old Thing'), findsOneWidget);
    });

    testWidgets('each week totals independently', (tester) async {
      await pumpList(tester);

      Finder headerTotal(String amount) => find.descendant(
        of: find.byType(WeekHeader),
        matching: find.text(amount),
      );

      expect(headerTotal(r'$164.00'), findsOneWidget);
      expect(headerTotal(r'$30.00'), findsOneWidget);
    });

    testWidgets('the current week shows its live budget line', (tester) async {
      await pumpList(tester);
      expect(find.text(r'$164.00 of $200 — $36.00 left'), findsOneWidget);
    });
  });

  group('the default does not rewrite a finished week', () {
    testWidgets('an earlier week keeps the budget it ran on', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(10000, now: DateTime(2026, 9, 1));
      await weekBudgets.ensureWeek(lastWeek, now: lastWeek);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await weekBudgets.setDefaultWeeklyCents(50000, now: now);

      await pumpList(tester);

      // Last week still reads against $100; this week followed the change.
      expect(find.text(r'$0.00 of $100 — $100.00 left'), findsOneWidget);
      expect(find.text(r'$0.00 of $500 — $500.00 left'), findsOneWidget);
    });
  });

  group('the list is capped', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      for (final monday in <DateTime>[
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 31),
        lastWeek,
        thisWeek,
      ]) {
        await weekBudgets.ensureWeek(monday, now: monday);
      }
    });

    testWidgets('shows four weeks, not six', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpList(tester);
      expect(find.byType(WeekHeader), findsNWidgets(4));
    });

    testWidgets('offers a way through to the rest', (tester) async {
      await pumpList(tester);
      expect(find.text('Earlier weeks'), findsOneWidget);
    });

    testWidgets('no archive link when everything already fits', (tester) async {
      await database.clear();
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpList(tester);
      expect(find.text('Earlier weeks'), findsNothing);
    });
  });

  group('deleting', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
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

    testWidgets('the week survives its last expense', (tester) async {
      await pumpList(tester);

      await tester.drag(find.text('Doomed'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // The week is tracked, so emptying it does not remove it.
      expect(find.byType(WeekHeader), findsOneWidget);
      expect(find.text('Nothing logged yet this week.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the edit screen has a delete button', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Doomed'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Delete expense'), findsOneWidget);
    });

    testWidgets('deleting from the edit screen asks first', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text('Doomed'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Delete expense'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this expense?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await expenses.getById('del'), isNotNull);
    });

    testWidgets('confirming deletes and returns to the list', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text('Doomed'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Delete expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await expenses.getById('del'), isNull);
      expect(find.text('Doomed'), findsNothing);
    });
  });

  group('moving an expense between weeks', () {
    testWidgets('warns before saving', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'm',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 17),
          merchant: 'Mover',
        ),
      );

      await pumpList(tester);
      await tester.tap(find.text('Mover'));
      await tester.pumpAndSettle();

      // No warning while the date is unchanged.
      expect(find.textContaining('Saving moves this expense'), findsNothing);
    });
  });

  group('AllWeeksScreen', () {
    testWidgets('lists tracked weeks with their verdicts', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: DateTime(2026, 9, 1));
      await weekBudgets.ensureWeek(lastWeek, now: lastWeek);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'over',
          amountCents: 30000,
          spentOn: DateTime(2026, 9, 9),
        ),
      );

      await pumpApp(
        tester,
        home: const AllWeeksScreen(),
        database: database,
        documents: documents,
        now: now,
      );

      expect(find.text('Over budget'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
    });

    testWidgets('a finished week with no spending is within budget', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: DateTime(2026, 9, 1));
      await weekBudgets.ensureWeek(lastWeek, now: lastWeek);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpApp(
        tester,
        home: const AllWeeksScreen(),
        database: database,
        documents: documents,
        now: now,
      );

      expect(find.text('Within budget'), findsOneWidget);
    });

    testWidgets('offers upcoming weeks for planning', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(10000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpApp(
        tester,
        home: const AllWeeksScreen(),
        database: database,
        documents: documents,
        now: now,
      );

      expect(find.text('Coming up'), findsOneWidget);
      expect(find.textContaining('(your default)'), findsWidgets);
    });
  });

  group('SettingsScreen', () {
    testWidgets('saving the default updates the current week', (tester) async {
      await weekBudgets.ensureWeek(thisWeek, now: now);

      await pumpApp(
        tester,
        home: const SettingsScreen(),
        database: database,
        documents: documents,
        now: now,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount per week'),
        '200',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
      await tester.pumpAndSettle();

      expect((await weekBudgets.getDefault()).weeklyCents, 20000);
      expect((await weekBudgets.getWeek(thisWeek))!.budgetCents, 20000);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('explains that history is not rewritten', (tester) async {
      await pumpApp(
        tester,
        home: const SettingsScreen(),
        database: database,
        documents: documents,
        now: now,
      );

      expect(
        find.textContaining('never rewrites your history'),
        findsOneWidget,
      );
    });
  });
}
