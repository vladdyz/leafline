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

/// The colour for a budget state.
///
/// "Approaching" has no good slot in a Material 3 scheme — `tertiary` is
/// derived from the seed and lands somewhere arbitrary — so it is specified
/// directly, with a lighter variant for dark mode to keep contrast usable.
///
/// Colour is never the only signal: [budgetMessage] carries the same
/// information as text, and both are always shown together.
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
