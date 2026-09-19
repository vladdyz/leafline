import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:receipt_tracker/data/budget_repository.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/image_store.dart';
import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// The open database.
///
/// Deliberately has no default. `main()` opens the database before `runApp`
/// and supplies it through a `ProviderScope` override; tests supply an
/// in-memory one the same way.
///
/// The alternative — a `FutureProvider` that opens it lazily — would make
/// every downstream provider asynchronous and force an `AsyncValue` wrapper
/// around screens that have nothing async about them. Opening once at startup
/// costs a few milliseconds and keeps the rest of the graph synchronous.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError(
    'appDatabaseProvider must be overridden — see main() or test_app.dart',
  ),
);

/// The directory receipt photos live in. Overridden the same way.
final documentsDirectoryProvider = Provider<Directory>(
  (ref) => throw StateError(
    'documentsDirectoryProvider must be overridden — see main()',
  ),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final repository = ExpenseRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final repository = BudgetRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final imageStoreProvider = Provider<ImageStore>((ref) {
  final root = ref.watch(documentsDirectoryProvider);
  return ImageStore(Directory(p.join(root.path, 'receipts')));
});

/// The current weekly budget, refreshed whenever it is written.
final budgetProvider = FutureProvider<Budget>((ref) async {
  final repository = ref.watch(budgetRepositoryProvider);
  final subscription = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository.get();
});

/// Every expense grouped into weeks, newest week first.
///
/// One query feeds the whole list screen: the grouping and per-week totals are
/// computed here rather than by a second round trip, and re-runs on any write.
final weekGroupsProvider = FutureProvider<List<WeekGroup>>((ref) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final subscription = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  final all = await repository.getAll();
  return groupIntoWeeks(all);
});

/// Groups expenses by their Monday, newest first.
///
/// Public and pure so it can be unit tested without a database or a widget.
List<WeekGroup> groupIntoWeeks(List<Expense> expenses) {
  final byWeek = <DateTime, List<Expense>>{};
  for (final expense in expenses) {
    byWeek.putIfAbsent(expense.week, () => <Expense>[]).add(expense);
  }

  final groups =
      byWeek.entries
          .map(
            (entry) => WeekGroup(weekStart: entry.key, expenses: entry.value),
          )
          .toList()
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
  return groups;
}

/// One week's expenses and their total.
class WeekGroup {
  WeekGroup({required this.weekStart, required this.expenses});

  /// The Monday of this week, at local midnight.
  final DateTime weekStart;

  /// Expenses in the week, in the order the repository returned them
  /// (newest spending date first).
  final List<Expense> expenses;

  /// The Sunday of this week.
  DateTime get weekEndDate => weekEnd(weekStart);

  int get totalCents =>
      expenses.fold(0, (sum, expense) => sum + expense.amountCents);
}
