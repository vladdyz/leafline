import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/models/week_budget.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/screens/week_detail_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

/// The screen you reach by tapping a week in the history.
///
/// It replaced the budget sheet on that row, because a finished week's budget
/// is frozen (decision 0011) and offering to edit it was the app arguing with
/// its own design. What someone looking at a week from two months ago wants is
/// to see what they bought.
void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);
  final pastWeek = DateTime(2026, 8, 3);
  final stamp = DateTime(2026, 8, 3, 9);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_detail');

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  WeekSummary summaryFor({
    required DateTime weekStart,
    required int budgetCents,
    required int totalCents,
    required bool isCurrent,
  }) {
    return WeekSummary(
      budget: WeekBudget(
        weekStart: weekStart,
        budgetCents: budgetCents,
        isOverride: false,
        createdAt: stamp,
        updatedAt: stamp,
      ),
      totalCents: totalCents,
      isCurrentWeek: isCurrent,
    );
  }

  Future<void> pumpDetail(WidgetTester tester, WeekSummary summary) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(
      tester,
      home: WeekDetailScreen(summary: summary),
      database: database,
      documents: documents,
      now: now,
      imageStore: InMemoryImageStore(),
    );
  }

  Future<void> addExpense(
    String id,
    int cents,
    String merchant,
    DateTime on,
  ) async {
    await expenses.insert(
      makeExpense(id: id, amountCents: cents, spentOn: on, merchant: merchant),
    );
  }

  group('a past week with spending', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(pastWeek, now: stamp);
      await addExpense('a', 4250, 'Corner Market', DateTime(2026, 8, 4));
      await addExpense('b', 1175, 'Coffee', DateTime(2026, 8, 6));
    });

    testWidgets('titles itself with the week range', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      expect(find.text('Aug 3 \u2013 Aug 9'), findsWidgets);
    });

    testWidgets('lists every expense in the week', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      expect(find.byType(ExpenseTile), findsNWidgets(2));
      expect(find.text('Corner Market'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
    });

    testWidgets('shows the budget bar for that week', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      expect(find.byType(BudgetBar), findsOneWidget);
      expect(find.byType(OutcomeChip), findsOneWidget);
    });

    testWidgets('sums the expenses in its footer', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      // 4250 + 1175 = 5425
      expect(find.text(r'2 expenses, $54.25'), findsOneWidget);
    });

    testWidgets('says "Spent" rather than "This week"', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    testWidgets('tapping an expense opens it for editing', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      await tester.tap(find.text('Corner Market'));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseFormScreen), findsOneWidget);
      expect(find.text('Edit expense'), findsOneWidget);
    });

    testWidgets('an edit made here is reflected on return', (tester) async {
      // The reason the total is recomputed from the expenses on screen rather
      // than trusting the figure carried in from the list.
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 5425,
          isCurrent: false,
        ),
      );

      await tester.tap(find.text('Coffee'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20.00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      // 4250 + 2000 = 6250
      expect(find.text(r'2 expenses, $62.50'), findsOneWidget);
    });

    testWidgets('one expense is singular', (tester) async {
      await expenses.delete('b');
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 4250,
          isCurrent: false,
        ),
      );

      expect(find.text(r'1 expense, $42.50'), findsOneWidget);
    });
  });

  group('a week with nothing in it', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(pastWeek, now: stamp);
    });

    testWidgets('says nothing was spent', (tester) async {
      // A tracked week with no expenses is the week worth celebrating, and it
      // exists precisely because weeks are rows rather than groupings.
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 0,
          isCurrent: false,
        ),
      );

      expect(find.text('Nothing spent this week.'), findsOneWidget);
      expect(find.byType(ExpenseTile), findsNothing);
    });

    testWidgets('still shows the budget bar', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 0,
          isCurrent: false,
        ),
      );

      expect(find.byType(BudgetBar), findsOneWidget);
    });
  });

  group('the current week', () {
    setUp(() async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
    });

    testWidgets('says "This week"', (tester) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: thisWeek,
          budgetCents: 20000,
          totalCents: 0,
          isCurrent: true,
        ),
      );

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Spent'), findsNothing);
    });

    testWidgets('its empty state is phrased for a week still running', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        summaryFor(
          weekStart: thisWeek,
          budgetCents: 20000,
          totalCents: 0,
          isCurrent: true,
        ),
      );

      expect(find.text('Nothing logged yet this week.'), findsOneWidget);
    });
  });

  group('a week with no budget', () {
    testWidgets('renders without dividing by zero', (tester) async {
      await weekBudgets.ensureWeek(pastWeek, now: stamp);
      await addExpense('a', 4250, 'Corner Market', DateTime(2026, 8, 4));

      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 0,
          totalCents: 4250,
          isCurrent: false,
        ),
      );

      expect(find.byType(BudgetBar), findsOneWidget);
      expect(find.text('Corner Market'), findsOneWidget);
    });
  });

  group('only this week', () {
    testWidgets('expenses from other weeks are not shown', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(pastWeek, now: stamp);
      await addExpense('in', 4250, 'Inside The Week', DateTime(2026, 8, 4));
      await addExpense('before', 999, 'Week Before', DateTime(2026, 7, 30));
      await addExpense('after', 999, 'Week After', DateTime(2026, 8, 11));

      await pumpDetail(
        tester,
        summaryFor(
          weekStart: pastWeek,
          budgetCents: 20000,
          totalCents: 4250,
          isCurrent: false,
        ),
      );

      expect(find.text('Inside The Week'), findsOneWidget);
      expect(find.text('Week Before'), findsNothing);
      expect(find.text('Week After'), findsNothing);
      expect(find.text(r'1 expense, $42.50'), findsOneWidget);
    });
  });
}
