import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

/// A single expense in the week list.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({required this.expense, this.onTap, super.key});

  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = expense.merchant.isEmpty
        ? expense.category.label
        : expense.merchant;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          categoryIcon(expense.category),
          size: 20,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${expense.category.label} \u00b7 '
        '${DateFormat.MMMd().format(expense.spentOn)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatCents(expense.amountCents),
        style: HarvestTheme.money(theme.textTheme.titleMedium),
      ),
    );
  }
}

/// Icon per category.
///
/// Decorative only — the category label is always rendered beside it, so an
/// icon that reads ambiguously costs nothing.
IconData categoryIcon(ExpenseCategory category) {
  switch (category) {
    case ExpenseCategory.transit:
      return Icons.directions_transit;
    case ExpenseCategory.dining:
      return Icons.restaurant;
    case ExpenseCategory.coffee:
      return Icons.local_cafe;
    case ExpenseCategory.groceries:
      return Icons.shopping_basket;
    case ExpenseCategory.shopping:
      return Icons.shopping_bag;
    case ExpenseCategory.entertainment:
      return Icons.movie;
    case ExpenseCategory.custom:
      return Icons.more_horiz;
  }
}

/// Header above each week's expenses: the date range and the week's total.
class WeekHeader extends StatelessWidget {
  const WeekHeader({
    required this.weekStart,
    required this.weekEndDate,
    required this.totalCents,
    super.key,
  });

  final DateTime weekStart;
  final DateTime weekEndDate;
  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.MMMd();
    final range =
        '${format.format(weekStart)} \u2013 '
        '${format.format(weekEndDate)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          range,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          formatCents(totalCents),
          style: HarvestTheme.money(theme.textTheme.titleMedium)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
