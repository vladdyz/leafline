import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/models/week_budget.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

import '../helpers/test_database.dart';

/// Replaces `grouping_test.dart`.
///
/// That file tested `groupIntoWeeks`, a function Phase 2.5 removed: weeks are
/// no longer assembled from expenses, they come from `week_budgets` and have
/// expenses attached to them. Its ordering cases moved to SQL and are covered
/// by `WeekBudgetRepository.recent`; its week-boundary cases were always
/// really testing `weekStart` and live in `week_math_test.dart`.
///
/// What is left, and what this file covers, is the arithmetic on a week once
/// it has been built.
void main() {
  final stamp = DateTime(2026, 9, 14, 8);
  final thisWeek = DateTime(2026, 9, 14);

  WeekBudget budgetFor(DateTime week, int cents) => WeekBudget(
    weekStart: week,
    budgetCents: cents,
    createdAt: stamp,
    updatedAt: stamp,
  );

  WeekView viewOf({
    int budgetCents = 20000,
    List<Expense> expenses = const <Expense>[],
    bool isCurrentWeek = false,
  }) => WeekView(
    budget: budgetFor(thisWeek, budgetCents),
    expenses: expenses,
    isCurrentWeek: isCurrentWeek,
  );

  group('WeekView totals', () {
    test('sums its expenses', () {
      final view = viewOf(
        expenses: <Expense>[
          makeExpense(id: 'a', amountCents: 12000),
          makeExpense(id: 'b', amountCents: 4400),
        ],
      );
      expect(view.totalCents, 16400);
    });

    test('an empty week totals zero rather than being absent', () {
      // The case the expense-driven model could not express at all: a week
      // that exists, has a budget, and has nothing in it.
      expect(viewOf().totalCents, 0);
    });

    test('exposes the Sunday as the week end', () {
      expect(viewOf().weekEndDate, DateTime(2026, 9, 20));
    });

    test('carries the budget from its row', () {
      expect(viewOf(budgetCents: 15000).budgetCents, 15000);
    });
  });

  group('WeekView outcome', () {
    test('the current week is in progress regardless of spending', () {
      expect(
        viewOf(
          isCurrentWeek: true,
          expenses: <Expense>[makeExpense(id: 'a', amountCents: 50000)],
        ).outcome,
        WeekOutcome.inProgress,
      );
    });

    test('a finished week with no spending is a success', () {
      expect(viewOf().outcome, WeekOutcome.under);
    });

    test('a finished week within budget is a success', () {
      expect(
        viewOf(expenses: <Expense>[makeExpense(id: 'a', amountCents: 19999)])
            .outcome,
        WeekOutcome.under,
      );
    });

    test('a finished week over budget is over', () {
      expect(
        viewOf(expenses: <Expense>[makeExpense(id: 'a', amountCents: 20001)])
            .outcome,
        WeekOutcome.over,
      );
    });

    test('a week with no budget has no verdict', () {
      expect(
        viewOf(
          budgetCents: 0,
          expenses: <Expense>[makeExpense(id: 'a', amountCents: 5000)],
        ).outcome,
        WeekOutcome.noBudget,
      );
    });

    test('a view is never untracked — an untracked week has no row', () {
      // WeekView is only ever built from a week_budgets row, so the untracked
      // state cannot reach the list. It is the history view's business.
      for (final current in <bool>[true, false]) {
        expect(
          viewOf(isCurrentWeek: current).outcome,
          isNot(WeekOutcome.untracked),
        );
      }
    });
  });

  group('WeekSummary', () {
    WeekSummary summaryOf({
      int budgetCents = 20000,
      int totalCents = 0,
      bool isCurrentWeek = false,
    }) => WeekSummary(
      budget: budgetFor(thisWeek, budgetCents),
      totalCents: totalCents,
      isCurrentWeek: isCurrentWeek,
    );

    test('reports the same verdict as a view would', () {
      expect(summaryOf(totalCents: 30000).outcome, WeekOutcome.over);
      expect(summaryOf(totalCents: 5000).outcome, WeekOutcome.under);
      expect(
        summaryOf(isCurrentWeek: true, totalCents: 30000).outcome,
        WeekOutcome.inProgress,
      );
    });

    test('exactly at budget counts as within it', () {
      expect(summaryOf(totalCents: 20000).outcome, WeekOutcome.under);
    });
  });

  group('UpcomingWeek', () {
    test('derives its week end from its Monday', () {
      final week = UpcomingWeek(
        weekStart: DateTime(2026, 9, 21),
        budgetCents: 10000,
        isOverride: false,
      );
      expect(week.weekEndDate, DateTime(2026, 9, 27));
    });
  });
}
