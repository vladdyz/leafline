import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';

/// Home. Expenses grouped into weeks, newest first, each with its budget bar.
class WeekListScreen extends ConsumerWidget {
  const WeekListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(weekGroupsProvider);
    final budget = ref.watch(budgetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Harvest'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ExpenseFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorView(error: error),
        data: (weeks) {
          if (weeks.isEmpty) return const _EmptyState();
          final budgetCents = budget.value?.weeklyCents ?? 0;

          return ListView.builder(
            // Clears the floating action button, which would otherwise sit on
            // top of the last expense in the list.
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: weeks.length,
            itemBuilder: (context, index) {
              final week = weeks[index];
              return _WeekSection(group: week, budgetCents: budgetCents);
            },
          );
        },
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({required this.group, required this.budgetCents});

  final WeekGroup group;
  final int budgetCents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WeekHeader(
                weekStart: group.weekStart,
                weekEndDate: group.weekEndDate,
                totalCents: group.totalCents,
              ),
              const SizedBox(height: 10),
              BudgetBar(spentCents: group.totalCents, budgetCents: budgetCents),
            ],
          ),
        ),
        for (final expense in group.expenses)
          _DismissibleExpense(expense: expense),
      ],
    );
  }
}

class _DismissibleExpense extends ConsumerWidget {
  const _DismissibleExpense({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Resolved here rather than inside the dismiss callback: Riverpod 3
    // throws if a ref is used after its element is disposed, and that
    // callback runs while this widget is being removed from the tree. The
    // repository itself is a plain object and outlives the widget safely.
    final repository = ref.watch(expenseRepositoryProvider);

    return Dismissible(
      key: ValueKey<String>('expense-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      // The deletion happens here, in confirmDismiss, and this ALWAYS returns
      // false. That reads backwards, so it is worth explaining.
      //
      // Returning true asks Dismissible to remove the widget, and Flutter
      // then requires the parent to have removed it from the tree by the next
      // build — otherwise it throws "A dismissed Dismissible widget is still
      // part of the tree". But this list is rebuilt from a provider that
      // re-queries the database, so removal is asynchronous: there is always
      // at least one frame where the widget is dismissed and the list still
      // contains it.
      //
      // Returning false instead means the row is deleted, the provider
      // invalidates, and the rebuilt list simply no longer contains this
      // expense. The snap-back animation never renders, because by the time
      // it would, the widget is gone.
      confirmDismiss: (_) async {
        // Captured before the await: using `context` afterwards would be
        // reaching across an async gap into a widget that may be gone.
        final messenger = ScaffoldMessenger.of(context);

        await repository.delete(expense.id);

        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text('Expense deleted'),
              action: SnackBarAction(
                label: 'Undo',
                // Re-inserting the original restores its id, timestamps and
                // photo reference, so undo is a true reversal rather than a
                // new expense that merely looks the same.
                onPressed: () async {
                  await repository.insert(expense);
                },
              ),
            ),
          );

        return false;
      },
      child: ExpenseTile(
        expense: expense,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExpenseFormScreen(initial: expense),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No expenses yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap Add to log your first one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Could not load expenses.\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
