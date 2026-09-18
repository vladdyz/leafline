/// Budget thresholds and the category list.
///
/// Both live here so they can be tuned in one place. The thresholds in
/// particular will want adjusting once there is a week of real data.
library;

/// Percent of the weekly budget at which the "approaching" warning starts.
///
/// Expressed as an integer percentage rather than a fraction so the threshold
/// comparison stays in integer arithmetic. `spent >= budget * 0.80` is a
/// float multiply, and while it happens to be exact for every budget value
/// tested, "happens to be exact" is not a property worth depending on in a
/// codebase whose first rule is that money never touches a `double`.
const int kApproachingPercent = 80;

/// Spending state for one week.
enum BudgetState { under, approaching, over }

/// Classifies [spentCents] against [budgetCents].
///
/// A budget of zero or less means "no budget set" and always reports
/// [BudgetState.under]. Guarding here rather than at each call site is what
/// keeps a division by zero out of the UI.
BudgetState budgetStateFor({
  required int spentCents,
  required int budgetCents,
}) {
  if (budgetCents <= 0) return BudgetState.under;
  if (spentCents >= budgetCents) return BudgetState.over;
  // Cross-multiplied to stay in integers: spent/budget >= 80/100.
  if (spentCents * 100 >= budgetCents * kApproachingPercent) {
    return BudgetState.approaching;
  }
  return BudgetState.under;
}

/// Fraction of budget spent, clamped to `[0, 1]` for progress bar rendering.
///
/// Callers that need the true overspend ratio should compute it directly;
/// this exists so a progress indicator never receives a value above 1.0.
double budgetProgress({required int spentCents, required int budgetCents}) {
  if (budgetCents <= 0) return 0;
  final ratio = spentCents / budgetCents;
  return ratio.clamp(0.0, 1.0);
}

/// Cents remaining before the budget is reached. Zero once it is passed.
int remainingCents({required int spentCents, required int budgetCents}) {
  final remaining = budgetCents - spentCents;
  return remaining > 0 ? remaining : 0;
}

/// Cents spent beyond the budget. Zero while still under it.
int overageCents({required int spentCents, required int budgetCents}) {
  if (budgetCents <= 0) return 0;
  final over = spentCents - budgetCents;
  return over > 0 ? over : 0;
}

/// The fixed category list.
///
/// Chosen to name the habits this app exists to make visible — small
/// recurring discretionary spending — rather than to mirror an accounting
/// chart. Fixed monthly obligations (rent, mortgage, car payments) are
/// deliberately absent: they are known and already budgeted, and including
/// them would swamp the weekly number.
///
/// [custom] is the catch-all for anything that fits nowhere else.
enum ExpenseCategory {
  transit('transit', 'Transit'),
  dining('dining', 'Dining out'),
  coffee('coffee', 'Coffee'),
  groceries('groceries', 'Groceries'),
  shopping('shopping', 'Shopping'),
  entertainment('entertainment', 'Entertainment'),
  custom('custom', 'Other');

  const ExpenseCategory(this.id, this.label);

  /// Stable identifier written to the database. Never change these strings
  /// without a migration — the display [label] is what you change instead.
  final String id;

  /// Human-readable name shown in the UI.
  final String label;

  /// Looks up a category by its stored [id], falling back to [custom] for
  /// unknown values so a row written by a future version still renders.
  static ExpenseCategory fromId(String id) {
    for (final category in ExpenseCategory.values) {
      if (category.id == id) return category;
    }
    return ExpenseCategory.custom;
  }
}
