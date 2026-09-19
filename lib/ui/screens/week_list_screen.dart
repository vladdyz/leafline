import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/all_weeks_screen.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/expense_tile.dart';
import 'package:receipt_tracker/ui/widgets/week_budget_sheet.dart';

/// Home. The last few tracked weeks, newest first.
///
/// Every tracked week appears, spending or not. A week with a budget and no
/// expenses is the best outcome the app can report, and it now renders as one
/// rather than vanishing.
class WeekListScreen extends ConsumerWidget {
  const WeekListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeks = ref.watch(recentWeeksProvider);
    final trackedCount = ref.watch(trackedWeekCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Harvest'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'All weeks',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AllWeeksScreen()),
            ),
          ),
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
      body: weeks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorView(error: error),
        data: (views) {
          if (views.isEmpty) return const _NotStartedYet();

          final hasArchive = (trackedCount.value ?? 0) > views.length;

          return ListView.builder(
            // Clears the floating action button, which would otherwise sit on
            // top of the last row.
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: views.length + (hasArchive ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == views.length) {
                return const _ArchiveLink();
              }
              return _WeekSection(view: views[index]);
            },
          );
        },
      ),
    );
  }
}

class _WeekSection extends ConsumerWidget {
  const _WeekSection({required this.view});

  final WeekView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    WeekHeader(
                      weekStart: view.weekStart,
                      weekEndDate: view.weekEndDate,
                      totalCents: view.totalCents,
                    ),
                    const SizedBox(height: 10),
                    BudgetBar(
                      spentCents: view.totalCents,
                      budgetCents: view.budgetCents,
                      isCurrentWeek: view.isCurrentWeek,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                tooltip: 'Budget for this week',
                onPressed: () => WeekBudgetSheet.show(
                  context,
                  weekStart: view.weekStart,
                  currentCents: view.budgetCents,
                  isOverride: view.budget.isOverride,
                ),
              ),
            ],
          ),
        ),
        if (view.expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              view.isCurrentWeek
                  ? 'Nothing logged yet this week.'
                  : 'Nothing spent this week.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final expense in view.expenses)
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
    // Resolved here rather than inside the dismiss callback: Riverpod 3 throws
    // if a ref is used after its element is disposed, and that callback runs
    // while this widget is being removed from the tree. The repository itself
    // is a plain object and outlives the widget safely.
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
      // Returning true asks Dismissible to remove the widget, and Flutter then
      // requires the parent to have removed it from the tree by the next
      // build — otherwise it throws "A dismissed Dismissible widget is still
      // part of the tree". But this list is rebuilt from a provider that
      // re-queries the database, so removal is asynchronous: there is always
      // at least one frame where the widget is dismissed and the list still
      // contains it.
      //
      // Returning false instead means the row is deleted, the provider
      // invalidates, and the rebuilt list simply no longer contains this
      // expense. The snap-back animation never renders, because by the time it
      // would, the widget is gone.
      confirmDismiss: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        await repository.delete(expense.id);

        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text('Expense deleted'),
              action: SnackBarAction(
                label: 'Undo',
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

class _ArchiveLink extends StatelessWidget {
  const _ArchiveLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AllWeeksScreen())),
        icon: const Icon(Icons.history),
        label: const Text('Earlier weeks'),
      ),
    );
  }
}

/// Shown only before the very first week is tracked.
///
/// In practice this is almost never seen: the app materialises the current
/// week at startup, so by the time a screen renders there is a week to show —
/// with a budget bar, from day one, before anything has been logged.
class _NotStartedYet extends StatelessWidget {
  const _NotStartedYet();

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
            Text('Getting your week ready', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Set a weekly budget in Settings to get started.',
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
          'Could not load your weeks.\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
