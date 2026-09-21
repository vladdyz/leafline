import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/ui/widgets/week_budget_sheet.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

/// The vacation-week control: one week gets its own figure, and the week after
/// it goes back to the default without anyone having to remember.
///
/// Tested by opening the sheet directly rather than through a screen, because
/// the screens that open it already have their own tests and reaching it
/// through them would be testing navigation twice.
void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);
  final nextWeek = DateTime(2026, 9, 21);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_sheet');

    await weekBudgets.setDefaultWeeklyCents(20000, now: now);
    await weekBudgets.ensureWeek(thisWeek, now: now);

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  /// A bare screen whose only job is to open the sheet.
  Future<void> openSheet(
    WidgetTester tester, {
    required DateTime weekStart,
    required int currentCents,
    required bool isOverride,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(
      tester,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () => WeekBudgetSheet.show(
                context,
                weekStart: weekStart,
                currentCents: currentCents,
                isOverride: isOverride,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      database: database,
      documents: documents,
      now: now,
      imageStore: InMemoryImageStore(),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('what it says on opening', () {
    testWidgets('names the week it will change', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      expect(find.text('Budget for Sep 14 \u2013 Sep 20'), findsOneWidget);
    });

    testWidgets('a week following the default says so', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      expect(
        find.text('This week follows your default budget.'),
        findsOneWidget,
      );
    });

    testWidgets('an overridden week says so instead', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 35000,
        isOverride: true,
      );

      expect(find.text('This week has its own budget.'), findsOneWidget);
    });

    testWidgets('pre-fills the figure the week runs on today', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(TextField),
        ),
      );
      // No symbol: the field has a $ prefix of its own.
      expect(field.controller?.text, '200.00');
    });

    testWidgets('a week with no budget opens empty', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 0,
        isOverride: false,
      );

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text, '');
    });

    testWidgets('only an overridden week offers a way back', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );
      expect(find.text('Use my default instead'), findsNothing);
    });

    testWidgets('an overridden week offers a way back', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 35000,
        isOverride: true,
      );
      expect(find.text('Use my default instead'), findsOneWidget);
    });
  });

  group('setting an override', () {
    testWidgets('writes the figure and marks the week overridden', (
      tester,
    ) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      await tester.enterText(find.byType(TextFormField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      final week = await weekBudgets.getWeek(thisWeek);
      expect(week!.budgetCents, 35000);
      expect(week.isOverride, isTrue);
    });

    testWidgets('closes the sheet afterwards', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      await tester.enterText(find.byType(TextFormField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      expect(find.byType(WeekBudgetSheet), findsNothing);
    });

    testWidgets('leaves the standing default alone', (tester) async {
      // The whole point of decision 0012: one write path for the default, and
      // this is not it.
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      await tester.enterText(find.byType(TextFormField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      expect((await weekBudgets.getDefault()).weeklyCents, 20000);
    });

    testWidgets('a later week still starts from the default', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      await tester.enterText(find.byType(TextFormField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      await weekBudgets.ensureWeek(nextWeek, now: now);
      final next = await weekBudgets.getWeek(nextWeek);
      expect(next!.budgetCents, 20000);
      expect(next.isOverride, isFalse);
    });

    testWidgets('accepts an amount with a decimal', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 20000,
        isOverride: false,
      );

      await tester.enterText(find.byType(TextFormField), '175.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      expect((await weekBudgets.getWeek(thisWeek))!.budgetCents, 17550);
    });
  });

  group('validation', () {
    testWidgets('an empty field refuses to save', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 0,
        isOverride: false,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.byType(WeekBudgetSheet), findsOneWidget);
      expect((await weekBudgets.getWeek(thisWeek))!.isOverride, isFalse);
    });

    testWidgets('nonsense refuses to save', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 0,
        isOverride: false,
      );

      // The field filters to digits, dots and commas, so this is what a
      // determined mistype actually produces.
      await tester.enterText(find.byType(TextFormField), '...');
      await tester.tap(find.widgetWithText(FilledButton, 'Set for this week'));
      await tester.pumpAndSettle();

      expect(find.text('Not a valid amount'), findsOneWidget);
      expect((await weekBudgets.getWeek(thisWeek))!.isOverride, isFalse);
    });
  });

  group('clearing an override', () {
    setUp(() async {
      await weekBudgets.overrideWeek(thisWeek, 35000, now: now);
    });

    testWidgets('returns the week to the default', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 35000,
        isOverride: true,
      );

      await tester.tap(find.text('Use my default instead'));
      await tester.pumpAndSettle();

      final week = await weekBudgets.getWeek(thisWeek);
      expect(week!.budgetCents, 20000);
      expect(week.isOverride, isFalse);
    });

    testWidgets('closes the sheet', (tester) async {
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 35000,
        isOverride: true,
      );

      await tester.tap(find.text('Use my default instead'));
      await tester.pumpAndSettle();

      expect(find.byType(WeekBudgetSheet), findsNothing);
    });

    testWidgets('the week then follows a later default change', (tester) async {
      // Which is the difference the flag makes, and the reason it exists.
      await openSheet(
        tester,
        weekStart: thisWeek,
        currentCents: 35000,
        isOverride: true,
      );

      await tester.tap(find.text('Use my default instead'));
      await tester.pumpAndSettle();

      await weekBudgets.setDefaultWeeklyCents(25000, now: now);
      expect((await weekBudgets.getWeek(thisWeek))!.budgetCents, 25000);
    });
  });
}
