import 'package:flutter/material.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

/// Spending against the weekly budget.
///
/// Renders a bar and a line of text. The text is not decoration — it carries
/// the whole message on its own, for screen readers, for anyone who cannot
/// distinguish the colours, and for glancing at a phone in sunlight.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    required this.spentCents,
    required this.budgetCents,
    super.key,
  });

  final int spentCents;
  final int budgetCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (budgetCents <= 0) {
      return Semantics(
        label: '${formatCents(spentCents)} spent, no budget set',
        excludeSemantics: true,
        child: Text(
          '${formatCents(spentCents)} spent — no budget set',
          style: HarvestTheme.money(theme.textTheme.bodyMedium),
        ),
      );
    }

    final state = budgetStateFor(
      spentCents: spentCents,
      budgetCents: budgetCents,
    );
    final color = budgetColor(context, state);
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
