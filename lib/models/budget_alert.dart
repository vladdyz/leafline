import 'package:receipt_tracker/util/budget_rules.dart';

/// A warning worth interrupting someone for.
enum BudgetAlert {
  /// Spending has reached [kApproachingPercent] of the weekly budget.
  ///
  /// The one that can actually change behaviour. By the time the other fires,
  /// the money is gone.
  approaching,

  /// Spending has passed the weekly budget.
  over,
}

/// Which alert, if any, this week's spending warrants right now.
///
/// Pure. The storage, the notification and the recording of what has already
/// fired all happen elsewhere, so the rule itself can be tested exhaustively
/// without a database or a platform channel.
///
/// The `FiredFor` arguments hold the week each alert last fired in, or null
/// if it never has. Comparing them against [currentWeek] is what enforces
/// "at most once per week" — and it resets on its own every Monday, because
/// the week changes rather than because anything cleans up.
BudgetAlert? pendingBudgetAlert({
  required int spentCents,
  required int budgetCents,
  required DateTime currentWeek,
  required DateTime? approachingFiredFor,
  required DateTime? overFiredFor,
  bool approachingEnabled = true,
  bool overEnabled = true,
}) {
  if (budgetCents <= 0) return null;

  final state = budgetStateFor(
    spentCents: spentCents,
    budgetCents: budgetCents,
  );

  switch (state) {
    case BudgetState.over:
      if (!overEnabled) return null;
      return overFiredFor == currentWeek ? null : BudgetAlert.over;

    case BudgetState.approaching:
      if (!approachingEnabled) return null;
      // Note what is absent: no check against overFiredFor. Reaching the
      // approaching band after having already been over means spending came
      // back down, which only happens by deleting an expense — and being told
      // you are near the limit at that point is accurate.
      return approachingFiredFor == currentWeek
          ? null
          : BudgetAlert.approaching;

    case BudgetState.under:
      return null;
  }
}
