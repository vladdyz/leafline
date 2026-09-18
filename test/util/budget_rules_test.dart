import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

void main() {
  const budget = 20000; // $200.00

  group('budgetStateFor', () {
    test('well under budget', () {
      expect(
        budgetStateFor(spentCents: 5000, budgetCents: budget),
        BudgetState.under,
      );
    });

    test('just below the approaching threshold', () {
      // 79.995% of $200.00
      expect(
        budgetStateFor(spentCents: 15999, budgetCents: budget),
        BudgetState.under,
      );
    });

    test('exactly at the approaching threshold', () {
      // 80.0% of $200.00
      expect(
        budgetStateFor(spentCents: 16000, budgetCents: budget),
        BudgetState.approaching,
      );
    });

    test('just below the budget', () {
      expect(
        budgetStateFor(spentCents: 19999, budgetCents: budget),
        BudgetState.approaching,
      );
    });

    test('exactly at the budget counts as over', () {
      expect(
        budgetStateFor(spentCents: 20000, budgetCents: budget),
        BudgetState.over,
      );
    });

    test('above the budget', () {
      expect(
        budgetStateFor(spentCents: 25000, budgetCents: budget),
        BudgetState.over,
      );
    });

    test('a zero budget never reports over', () {
      // No budget set. This is the divide-by-zero case.
      expect(
        budgetStateFor(spentCents: 50000, budgetCents: 0),
        BudgetState.under,
      );
    });

    test('a negative budget is treated as unset', () {
      expect(
        budgetStateFor(spentCents: 100, budgetCents: -1),
        BudgetState.under,
      );
    });

    test('nothing spent is under', () {
      expect(
        budgetStateFor(spentCents: 0, budgetCents: budget),
        BudgetState.under,
      );
    });
  });

  group('budgetProgress', () {
    test('reports a fraction', () {
      expect(budgetProgress(spentCents: 10000, budgetCents: budget), 0.5);
    });

    test('clamps above the budget', () {
      expect(budgetProgress(spentCents: 40000, budgetCents: budget), 1.0);
    });

    test('returns zero for an unset budget', () {
      expect(budgetProgress(spentCents: 10000, budgetCents: 0), 0.0);
    });
  });

  group('remainingCents', () {
    test('counts down to the budget', () {
      expect(remainingCents(spentCents: 15000, budgetCents: budget), 5000);
    });

    test('never goes negative', () {
      expect(remainingCents(spentCents: 25000, budgetCents: budget), 0);
    });
  });

  group('overageCents', () {
    test('is zero while under', () {
      expect(overageCents(spentCents: 15000, budgetCents: budget), 0);
    });

    test('reports the overspend', () {
      expect(overageCents(spentCents: 25000, budgetCents: budget), 5000);
    });

    test('is zero when no budget is set', () {
      expect(overageCents(spentCents: 25000, budgetCents: 0), 0);
    });
  });

  group('ExpenseCategory', () {
    test('every category has a unique id', () {
      final ids = ExpenseCategory.values.map((c) => c.id).toSet();
      expect(ids.length, ExpenseCategory.values.length);
    });

    test('looks up a known id', () {
      expect(ExpenseCategory.fromId('coffee'), ExpenseCategory.coffee);
    });

    test('falls back to custom for an unknown id', () {
      // A row written by a future version must still render.
      expect(ExpenseCategory.fromId('crypto'), ExpenseCategory.custom);
    });
  });
}
