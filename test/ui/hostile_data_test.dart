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
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

/// Data chosen to break layouts rather than to be realistic.
///
/// Every one of these renders a `Row`, a `ListTile` or a `Text` that was
/// written against ordinary input. A `Row` overflows by **throwing**, and a
/// thrown layout error reaches `FlutterError.onError`, which a widget test
/// treats as a failure — so these tests genuinely catch overflow rather than
/// just exercising code.
void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;
  late InMemoryImageStore store;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_hostile');
    store = InMemoryImageStore();

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      home: home,
      database: database,
      documents: documents,
      now: now,
      imageStore: store,
    );
  }

  group('absurd amounts', () {
    testWidgets('a week totalling nearly a million renders', (tester) async {
      // The case that motivated making WeekHeader overflow-safe: a narrow
      // phone, a long date range and an eleven-character figure in the same
      // unconstrained Row.
      await weekBudgets.setDefaultWeeklyCents(100000000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'huge',
          amountCents: 99999999,
          spentOn: DateTime(2026, 9, 16),
          merchant: 'Big Purchase',
        ),
      );

      await pump(tester, const WeekListScreen());

      expect(find.text(r'$999,999.99'), findsWidgets);
    });

    testWidgets('a zero-amount expense is allowed and renders', (tester) async {
      // Odd but not invalid. Rejecting it would be a surprising validation
      // failure mid-entry.
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'zero',
          amountCents: 0,
          spentOn: DateTime(2026, 9, 16),
          merchant: 'Free Sample',
        ),
      );

      await pump(tester, const WeekListScreen());

      expect(find.text('Free Sample'), findsOneWidget);
      expect(find.text(r'$0.00'), findsWidgets);
    });

    testWidgets('spending with no budget set does not divide by zero', (
      tester,
    ) async {
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'a',
          amountCents: 50000,
          spentOn: DateTime(2026, 9, 16),
        ),
      );

      await pump(tester, const WeekListScreen());

      expect(find.byType(BudgetBar), findsOneWidget);
      expect(find.textContaining('no budget set'), findsOneWidget);
    });
  });

  group('absurd text', () {
    testWidgets('a merchant name of 500 characters does not overflow', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'long',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 16),
          merchant: 'A' * 500,
        ),
      );

      await pump(tester, const WeekListScreen());

      // The tile ellipses it; the assertion that matters is that pumping
      // completed without a layout exception.
      expect(find.byType(WeekListScreen), findsOneWidget);
    });

    testWidgets('a merchant name with no spaces does not overflow', (
      tester,
    ) async {
      // Worse than a long name: nothing to wrap at.
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'nospace',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 16),
          merchant: 'Xy' * 120,
        ),
      );

      await pump(tester, const WeekListScreen());
      expect(find.byType(WeekListScreen), findsOneWidget);
    });

    testWidgets('emoji and non-Latin text render', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'emoji',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 16),
          merchant:
              '\u2615 Caf\u00e9 \u4e2d\u6587 \u0645\u0631\u062d\u0628\u0627',
        ),
      );

      await pump(tester, const WeekListScreen());
      expect(find.byType(WeekListScreen), findsOneWidget);
    });

    testWidgets('a very long note does not break the form', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'note',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 16),
          merchant: 'Wordy',
          note: 'lorem ipsum ' * 400,
        ),
      );

      await pump(tester, const WeekListScreen());
      await tester.tap(find.text('Wordy'));
      await tester.pumpAndSettle();

      expect(find.text('Edit expense'), findsOneWidget);
    });
  });

  group('volume', () {
    testWidgets('a week holding 100 expenses renders and totals', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(1000000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      for (var i = 0; i < 100; i++) {
        await expenses.insert(
          makeExpense(
            id: 'e$i',
            amountCents: 199,
            spentOn: DateTime(2026, 9, 16),
            merchant: 'Item $i',
          ),
        );
      }

      await pump(tester, const WeekListScreen());

      expect(await expenses.totalCentsForWeek(now), 19900);
      expect(find.byType(WeekListScreen), findsOneWidget);
    });

    testWidgets('a year of tracked weeks renders in the history', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      for (var i = 0; i < 52; i++) {
        await weekBudgets.ensureWeek(DateTime(2026, 9, 14 - (7 * i)), now: now);
      }

      await pump(tester, const AllWeeksScreen());

      expect(await weekBudgets.trackedCount(now: now), 52);
      expect(find.byType(AllWeeksScreen), findsOneWidget);
    });
  });

  group('boundaries that have bitten before', () {
    testWidgets('exactly at the budget reads as over while live', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await expenses.insert(
        makeExpense(
          id: 'exact',
          amountCents: 20000,
          spentOn: DateTime(2026, 9, 16),
        ),
      );

      await pump(tester, const WeekListScreen());

      // Live, hitting the number means the next purchase puts you over.
      expect(find.textContaining('over by'), findsOneWidget);
      expect(
        budgetStateFor(spentCents: 20000, budgetCents: 20000),
        BudgetState.over,
      );
    });

    testWidgets('a week spanning a year boundary groups as one', (
      tester,
    ) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: DateTime(2027, 1, 1));
      await weekBudgets.ensureWeek(
        DateTime(2026, 12, 28),
        now: DateTime(2026, 12, 28),
      );
      for (final day in <DateTime>[
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
      ]) {
        await expenses.insert(
          makeExpense(id: 'd${day.day}', amountCents: 1000, spentOn: day),
        );
      }

      await pumpApp(
        tester,
        home: const WeekListScreen(),
        database: database,
        documents: documents,
        now: DateTime(2027, 1, 1, 10),
        imageStore: store,
      );

      expect(find.text(r'$20.00'), findsWidgets);
    });
  });

  group('settings with extreme values', () {
    testWidgets('a very large budget saves and renders', (tester) async {
      await weekBudgets.ensureWeek(thisWeek, now: now);
      await pump(tester, const SettingsScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount per week'),
        '999999',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
      await tester.pumpAndSettle();

      expect((await weekBudgets.getDefault()).weeklyCents, 99999900);
      expect(formatCents(99999900), r'$999,999.00');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
