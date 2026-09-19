import 'package:flutter/material.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

/// Colour and type decisions, in one place.
///
/// Material 3 from a single seed. The growing-canopy visual identity replaces
/// the budget bar in a later phase; until then this is plain and legible, and
/// deliberately not a custom design system.
class HarvestTheme {
  const HarvestTheme._();

  /// A muted green. The canopy metaphor starts here even though the
  /// illustration does not exist yet.
  static const Color seed = Color(0xFF3F6B52);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Amounts use tabular figures so digits line up down a column.
  ///
  /// The difference between a list of numbers you can scan and one you cannot
  /// is almost entirely this.
  static TextStyle money(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

/// The colour for a live budget state, used while a week is still running.
///
/// "Approaching" has no good slot in a Material 3 scheme — `tertiary` is
/// derived from the seed and lands somewhere arbitrary — so it is specified
/// directly, with a lighter variant for dark mode to keep contrast usable.
///
/// Colour is never the only signal: the bar always carries its figures as
/// text beside it.
Color budgetColor(BuildContext context, BudgetState state) {
  final scheme = Theme.of(context).colorScheme;
  switch (state) {
    case BudgetState.under:
      return scheme.primary;
    case BudgetState.approaching:
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFB74D)
          : const Color(0xFF9A6100);
    case BudgetState.over:
      return scheme.error;
  }
}

/// The colour for a finished week's verdict.
///
/// Note there is no amber here, and that is deliberate. The 80% warning is a
/// live signal meant to change what you do next; a week that finished at 85%
/// stayed within its budget and reads as a success.
Color outcomeColor(BuildContext context, WeekOutcome outcome) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  switch (outcome) {
    case WeekOutcome.untracked:
    case WeekOutcome.noBudget:
      return scheme.outlineVariant;
    case WeekOutcome.inProgress:
      return scheme.primary;
    case WeekOutcome.under:
      return theme.brightness == Brightness.dark
          ? const Color(0xFF7DC98F)
          : const Color(0xFF2E7D4F);
    case WeekOutcome.over:
      return scheme.error;
  }
}

/// A short label for a week's verdict, shown beside its colour.
String outcomeLabel(WeekOutcome outcome) {
  switch (outcome) {
    case WeekOutcome.untracked:
      return 'Not tracked';
    case WeekOutcome.noBudget:
      return 'No budget';
    case WeekOutcome.inProgress:
      return 'In progress';
    case WeekOutcome.under:
      return 'Within budget';
    case WeekOutcome.over:
      return 'Over budget';
  }
}
