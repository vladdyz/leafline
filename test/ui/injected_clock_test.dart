import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

/// Proves the UI writes against the injected clock rather than the wall clock.
///
/// The dates here are deliberately far from any plausible real one. The test
/// this replaces used a pinned clock in the same calendar week as the day it
/// was written, so a write that ignored `nowProvider` still landed on the
/// right row — it passed for two months by coincidence, and failed the first
/// time CI ran after 8pm Toronto time, when UTC had already rolled into the
/// next week.
///
/// A test that can only pass when the machine's clock cooperates is not
/// testing the thing it claims to.
void main() {
  setUpAll(initTestDatabase);

  // A Wednesday in 2031. No real clock will ever agree with it.
  final now = DateTime(2031, 5, 14, 9);
  final pinnedWeek = DateTime(2031, 5, 12); // the Monday
  final otherWeek = DateTime(2031, 5, 19);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_clock');

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      home: const SettingsScreen(),
      database: database,
      documents: documents,
      now: now,
      imageStore: InMemoryImageStore(),
    );
  }

  Future<void> saveBudget(WidgetTester tester, String amount) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount per week'),
      amount,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save budget'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving the default updates the pinned week, not today', (
    tester,
  ) async {
    await weekBudgets.ensureWeek(pinnedWeek, now: now);
    await pumpSettings(tester);

    await saveBudget(tester, '200');

    expect((await weekBudgets.getDefault()).weeklyCents, 20000);
    // The assertion that would have caught the bug: the row belonging to the
    // clock the test injected, not the one the machine is living in.
    expect((await weekBudgets.getWeek(pinnedWeek))!.budgetCents, 20000);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a week other than the pinned one is untouched', (tester) async {
    await weekBudgets.ensureWeek(pinnedWeek, now: now);
    await weekBudgets.ensureWeek(otherWeek, now: now);
    await weekBudgets.overrideWeek(otherWeek, 5000, now: now);

    await pumpSettings(tester);
    await saveBudget(tester, '200');

    expect((await weekBudgets.getWeek(pinnedWeek))!.budgetCents, 20000);
    expect((await weekBudgets.getWeek(otherWeek))!.budgetCents, 5000);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an overridden current week ignores the new default', (
    tester,
  ) async {
    // Decision 0012, now verified against a clock that cannot coincide.
    await weekBudgets.ensureWeek(pinnedWeek, now: now);
    await weekBudgets.overrideWeek(pinnedWeek, 7500, now: now);

    await pumpSettings(tester);
    await saveBudget(tester, '200');

    expect((await weekBudgets.getDefault()).weeklyCents, 20000);
    expect((await weekBudgets.getWeek(pinnedWeek))!.budgetCents, 7500);
    expect((await weekBudgets.getWeek(pinnedWeek))!.isOverride, isTrue);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
