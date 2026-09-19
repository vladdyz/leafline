import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

void main() {
  const budget = 20000; // $200.00

  WeekOutcome outcome({
    bool isTracked = true,
    bool isCurrentWeek = false,
    int budgetCents = budget,
    int spentCents = 0,
  }) {
    return weekOutcomeFor(
      isTracked: isTracked,
      isCurrentWeek: isCurrentWeek,
      budgetCents: budgetCents,
      spentCents: spentCents,
    );
  }

  group('untracked', () {
    test('a week the app never saw is untracked, not a success', () {
      // The whole point: without this, every week back to the start of the
      // calendar would render as a perfect week the user never lived.
      expect(outcome(isTracked: false), WeekOutcome.untracked);
    });

    test('untracked wins even over a current week', () {
      expect(
        outcome(isTracked: false, isCurrentWeek: true),
        WeekOutcome.untracked,
      );
    });

    test('untracked wins even with spending recorded', () {
      expect(
        outcome(isTracked: false, spentCents: 99999),
        WeekOutcome.untracked,
      );
    });
  });

  group('in progress', () {
    test('the current week has no verdict yet', () {
      expect(outcome(isCurrentWeek: true), WeekOutcome.inProgress);
    });

    test('a current week under budget is still only in progress', () {
      // Painting it green on Tuesday would announce a win in a race that is
      // still being run.
      expect(
        outcome(isCurrentWeek: true, spentCents: 5000),
        WeekOutcome.inProgress,
      );
    });

    test('a current week already over budget is still in progress', () {
      expect(
        outcome(isCurrentWeek: true, spentCents: 30000),
        WeekOutcome.inProgress,
      );
    });
  });

  group('finished weeks', () {
    test('tracked with nothing spent is a success', () {
      // The case the old expense-driven model made invisible.
      expect(outcome(spentCents: 0), WeekOutcome.under);
    });

    test('well under budget', () {
      expect(outcome(spentCents: 5000), WeekOutcome.under);
    });

    test('exactly at the budget stayed within it', () {
      expect(outcome(spentCents: budget), WeekOutcome.under);
    });

    test('one cent over is over', () {
      expect(outcome(spentCents: budget + 1), WeekOutcome.over);
    });

    test('well over budget', () {
      expect(outcome(spentCents: 50000), WeekOutcome.over);
    });
  });

  group('no budget set', () {
    test('a tracked week with a zero budget has no verdict', () {
      expect(outcome(budgetCents: 0, spentCents: 5000), WeekOutcome.noBudget);
    });

    test('and does not divide by zero on the way there', () {
      expect(outcome(budgetCents: 0, spentCents: 0), WeekOutcome.noBudget);
    });
  });

  group('the live bar and the history verdict deliberately disagree', () {
    test('spending exactly the budget warns live but passes in history', () {
      // Live, hitting the number means the next purchase puts you over, which
      // is worth flagging. Finished, hitting the number means you made it.
      expect(
        budgetStateFor(spentCents: budget, budgetCents: budget),
        BudgetState.over,
      );
      expect(outcome(spentCents: budget), WeekOutcome.under);
    });

    test('there is no approaching outcome in history', () {
      // A week that ended at 85% was a success, not a near-miss.
      expect(outcome(spentCents: 17000), WeekOutcome.under);
      expect(
        budgetStateFor(spentCents: 17000, budgetCents: budget),
        BudgetState.approaching,
      );
    });
  });

  group('weekStayedWithinBudget', () {
    test('under passes', () {
      expect(
        weekStayedWithinBudget(budgetCents: budget, spentCents: 5000),
        isTrue,
      );
    });

    test('exactly at the budget passes', () {
      expect(
        weekStayedWithinBudget(budgetCents: budget, spentCents: budget),
        isTrue,
      );
    });

    test('over fails', () {
      expect(
        weekStayedWithinBudget(budgetCents: budget, spentCents: budget + 1),
        isFalse,
      );
    });

    test('no budget cannot be exceeded', () {
      expect(weekStayedWithinBudget(budgetCents: 0, spentCents: 99999), isTrue);
    });
  });
}
