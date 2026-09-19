import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/image_store.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/models/week_budget.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// The open database.
///
/// Deliberately has no default. `main()` opens the database before `runApp`
/// and supplies it through a `ProviderScope` override; tests supply an
/// in-memory one the same way. See decision 0010.
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

/// The clock.
///
/// Every "is this the current week" question routes through here so tests can
/// pin a date instead of depending on the day they happen to run. Without it,
/// a suite that passes on Wednesday fails on Monday.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final repository = ExpenseRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final weekBudgetRepositoryProvider = Provider<WeekBudgetRepository>((ref) {
  final repository = WeekBudgetRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final imageStoreProvider = Provider<ImageStore>((ref) {
  final root = ref.watch(documentsDirectoryProvider);
  return ImageStore(Directory(p.join(root.path, 'receipts')));
});

/// Subscribes to both repositories so any write refreshes the caller.
void _refreshOnAnyWrite(Ref ref) {
  final expenses = ref.watch(expenseRepositoryProvider);
  final weeks = ref.watch(weekBudgetRepositoryProvider);
  final subscriptions = <StreamSubscription<void>>[
    expenses.changes.listen((_) => ref.invalidateSelf()),
    weeks.changes.listen((_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  });
}

/// The standing default budget that new weeks inherit.
final defaultBudgetProvider = FutureProvider<Budget>((ref) async {
  _refreshOnAnyWrite(ref);
  return ref.watch(weekBudgetRepositoryProvider).getDefault();
});

/// The most recent tracked weeks, newest first, with their expenses.
///
/// Built from `week_budgets`, not from expenses. A tracked week with no
/// spending appears here in full — which is the entire point of Phase 2.5.
final recentWeeksProvider = FutureProvider<List<WeekView>>((ref) async {
  _refreshOnAnyWrite(ref);

  final now = ref.watch(nowProvider)();
  final weekRepository = ref.watch(weekBudgetRepositoryProvider);
  final expenseRepository = ref.watch(expenseRepositoryProvider);

  final weeks = await weekRepository.recent(limit: kRecentWeekCount, now: now);
  if (weeks.isEmpty) return <WeekView>[];

  // One query spanning every week on screen, rather than one per week.
  final expenses = await expenseRepository.betweenDates(
    weeks.last.weekStart,
    weekEndExclusive(weeks.first.weekStart),
  );

  final byWeek = <DateTime, List<Expense>>{};
  for (final expense in expenses) {
    byWeek.putIfAbsent(expense.week, () => <Expense>[]).add(expense);
  }

  final currentWeek = weekStart(now);
  return <WeekView>[
    for (final week in weeks)
      WeekView(
        budget: week,
        expenses: byWeek[week.weekStart] ?? const <Expense>[],
        isCurrentWeek: week.weekStart == currentWeek,
      ),
  ];
});

/// How many tracked weeks exist up to and including the current one.
///
/// Drives whether the list offers a way through to the full history — with
/// three weeks on record there is nothing archived to go and look at.
final trackedWeekCountProvider = FutureProvider<int>((ref) async {
  _refreshOnAnyWrite(ref);
  final now = ref.watch(nowProvider)();
  return ref.watch(weekBudgetRepositoryProvider).trackedCount(now: now);
});

/// Every tracked week up to the current one, newest first, as summaries.
final weekHistoryProvider = FutureProvider<List<WeekSummary>>((ref) async {
  _refreshOnAnyWrite(ref);

  final now = ref.watch(nowProvider)();
  final currentWeek = weekStart(now);
  final weeks = await ref.watch(weekBudgetRepositoryProvider).all();
  final totals = await ref.watch(expenseRepositoryProvider).weekTotals();

  final totalByWeek = <DateTime, int>{
    for (final total in totals) total.weekStart: total.totalCents,
  };

  return <WeekSummary>[
    for (final week in weeks)
      if (!week.weekStart.isAfter(currentWeek))
        WeekSummary(
          budget: week,
          totalCents: totalByWeek[week.weekStart] ?? 0,
          isCurrentWeek: week.weekStart == currentWeek,
        ),
  ];
});

/// The next few weeks, whether or not they have been materialised yet.
///
/// A week with no row still appears, showing the default it would inherit, so
/// a known-expensive week ahead can be given its own figure before it starts.
final upcomingWeeksProvider = FutureProvider<List<UpcomingWeek>>((ref) async {
  _refreshOnAnyWrite(ref);

  final now = ref.watch(nowProvider)();
  final weekRepository = ref.watch(weekBudgetRepositoryProvider);
  final planned = await weekRepository.planned(now: now);
  final defaultBudget = await weekRepository.getDefault();

  final plannedByWeek = <DateTime, WeekBudget>{
    for (final week in planned) week.weekStart: week,
  };

  final current = weekStart(now);
  final upcoming = <UpcomingWeek>[];
  for (var offset = 1; offset <= kUpcomingWeekCount; offset++) {
    // Calendar arithmetic rather than Duration, for the same DST reason
    // week_math gives.
    final monday = DateTime(
      current.year,
      current.month,
      current.day + (7 * offset),
    );
    final existing = plannedByWeek[monday];
    upcoming.add(
      UpcomingWeek(
        weekStart: monday,
        budgetCents: existing?.budgetCents ?? defaultBudget.weeklyCents,
        isOverride: existing?.isOverride ?? false,
      ),
    );
  }
  return upcoming;
});

/// How many weeks the main list shows before sending you to the history view.
const int kRecentWeekCount = 4;

/// How many weeks ahead the planning list offers.
const int kUpcomingWeekCount = 4;

/// One week with everything the main list needs to draw it.
class WeekView {
  const WeekView({
    required this.budget,
    required this.expenses,
    required this.isCurrentWeek,
  });

  final WeekBudget budget;
  final List<Expense> expenses;
  final bool isCurrentWeek;

  DateTime get weekStart => budget.weekStart;
  DateTime get weekEndDate => budget.weekEndDate;
  int get budgetCents => budget.budgetCents;

  int get totalCents =>
      expenses.fold(0, (sum, expense) => sum + expense.amountCents);

  /// Always tracked: an untracked week has no row and so never becomes a view.
  WeekOutcome get outcome => weekOutcomeFor(
    isTracked: true,
    isCurrentWeek: isCurrentWeek,
    budgetCents: budgetCents,
    spentCents: totalCents,
  );
}

/// One week reduced to its verdict, for the history list.
class WeekSummary {
  const WeekSummary({
    required this.budget,
    required this.totalCents,
    required this.isCurrentWeek,
  });

  final WeekBudget budget;
  final int totalCents;
  final bool isCurrentWeek;

  DateTime get weekStart => budget.weekStart;
  DateTime get weekEndDate => budget.weekEndDate;
  int get budgetCents => budget.budgetCents;

  WeekOutcome get outcome => weekOutcomeFor(
    isTracked: true,
    isCurrentWeek: isCurrentWeek,
    budgetCents: budgetCents,
    spentCents: totalCents,
  );
}

/// A future week, real or merely prospective.
class UpcomingWeek {
  const UpcomingWeek({
    required this.weekStart,
    required this.budgetCents,
    required this.isOverride,
  });

  final DateTime weekStart;

  /// The figure this week will run on — its own if set, otherwise the default
  /// it would inherit on materialisation.
  final int budgetCents;

  /// Whether that figure was chosen for this week specifically.
  final bool isOverride;

  DateTime get weekEndDate => weekEnd(weekStart);
}
