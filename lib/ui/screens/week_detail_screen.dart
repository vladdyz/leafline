import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';
import 'package:receipt_tracker/util/money.dart';

/// One week, in full: what it was budgeted, what was spent, and on what.
///
/// This is what tapping a week in the history opens. It used to open the
/// budget sheet, which was wrong twice over — a finished week's budget is
/// frozen by decision 0011, so the app was offering to edit something it had
/// already decided was immutable, and what someone looking at a week from two
/// months ago actually wants is to see what they bought.
class WeekDetailScreen extends ConsumerWidget {
  const WeekDetailScreen({required this.summary, super.key});

  final WeekSummary summary;

  static Future<void> open(BuildContext context, WeekSummary summary) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WeekDetailScreen(summary: summary),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = DateFormat.MMMd();
    final range =
        '${format.format(summary.weekStart)} \u2013 '
        '${format.format(summary.weekEndDate)}';

    final expenses = ref.watch(weekExpensesProvider(summary.weekStart));

    return Scaffold(
      appBar: AppBar(title: Text(range)),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Could not load this week.\n$error'),
          ),
        ),
        data: (items) {
          final spent = items.fold<int>(
            0,
            (sum, expense) => sum + expense.amountCents,
          );

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          summary.isCurrentWeek ? 'This week' : 'Spent',
                          style: theme.textTheme.titleMedium,
                        ),
                        OutcomeChip(outcome: summary.outcome),
                      ],
                    ),
                    const SizedBox(height: 12),
                    BudgetBar(
                      // Recomputed from the expenses actually on screen rather
                      // than trusting the total carried in from the list, so
                      // an edit made from here is reflected immediately.
                      spentCents: spent,
                      budgetCents: summary.budgetCents,
                      isCurrentWeek: summary.isCurrentWeek,
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    summary.isCurrentWeek
                        ? 'Nothing logged yet this week.'
                        : 'Nothing spent this week.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else ...<Widget>[
                const Divider(height: 1),
                for (final expense in items)
                  ExpenseTile(
                    expense: expense,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExpenseFormScreen(initial: expense),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${items.length} '
                    '${items.length == 1 ? 'expense' : 'expenses'}, '
                    '${formatCents(spent)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
