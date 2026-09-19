import 'package:flutter/material.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

/// Spending against a week's budget.
///
/// Renders a bar and a line of text. The text is not decoration — it carries
/// the whole message on its own, for screen readers, for anyone who cannot
/// distinguish the colours, and for glancing at a phone in sunlight.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    required this.spentCents,
    required this.budgetCents,
    required this.isCurrentWeek,
    super.key,
  });

  final int spentCents;
  final int budgetCents;

  /// Which colour language to use.
  ///
  /// A running week gets the live one, amber included, because the 80% mark
  /// is a signal meant to change what you do next. A finished week gets its
  /// verdict instead — within budget or over — because a week that ended at
  /// 85% succeeded and should not be rendered as a near-miss.
  final bool isCurrentWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (budgetCents <= 0) {
      final message = budgetMessage(
        spentCents: spentCents,
        budgetCents: budgetCents,
      );
      return Semantics(
        label: message,
        excludeSemantics: true,
        child: Text(
          message,
          style: HarvestTheme.money(theme.textTheme.bodyMedium),
        ),
      );
    }

    final color = isCurrentWeek
        ? budgetColor(
            context,
            budgetStateFor(spentCents: spentCents, budgetCents: budgetCents),
          )
        : outcomeColor(
            context,
            weekOutcomeFor(
              isTracked: true,
              isCurrentWeek: false,
              budgetCents: budgetCents,
              spentCents: spentCents,
            ),
          );

    final message = budgetMessage(
      spentCents: spentCents,
      budgetCents: budgetCents,
    );

    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: budgetProgress(
                spentCents: spentCents,
                budgetCents: budgetCents,
              ),
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: HarvestTheme.money(theme.textTheme.bodyMedium)
                .copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The budget line as text, e.g. `$164.00 of $200 — $36.00 left`.
///
/// Pure and public so its wording is unit tested rather than asserted through
/// a rendered widget.
String budgetMessage({required int spentCents, required int budgetCents}) {
  if (budgetCents <= 0) {
    return '${formatCents(spentCents)} spent — no budget set';
  }

  final state = budgetStateFor(
    spentCents: spentCents,
    budgetCents: budgetCents,
  );
  final of = '${formatCents(spentCents)} of ${formatCentsCompact(budgetCents)}';

  switch (state) {
    case BudgetState.under:
    case BudgetState.approaching:
      final left = remainingCents(
        spentCents: spentCents,
        budgetCents: budgetCents,
      );
      return '$of — ${formatCents(left)} left';
    case BudgetState.over:
      final over = overageCents(
        spentCents: spentCents,
        budgetCents: budgetCents,
      );
      return '$of — over by ${formatCents(over)}';
  }
}

/// A small coloured pill naming a week's verdict.
class OutcomeChip extends StatelessWidget {
  const OutcomeChip({required this.outcome, super.key});

  final WeekOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = outcomeColor(context, outcome);
    final label = outcomeLabel(outcome);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
