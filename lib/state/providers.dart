import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/image_store.dart';
import 'package:receipt_tracker/data/settings_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/models/budget_alert.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/models/photo_retention.dart';
import 'package:receipt_tracker/models/week_budget.dart';
import 'package:receipt_tracker/services/app_lock_service.dart';
import 'package:receipt_tracker/services/budget_alert_service.dart';
import 'package:receipt_tracker/services/channel_ocr_service.dart';
import 'package:receipt_tracker/services/local_notification_service.dart';
import 'package:receipt_tracker/services/notification_service.dart';
import 'package:receipt_tracker/services/ocr_service.dart';
import 'package:receipt_tracker/services/photo_retention_sweeper.dart';
import 'package:receipt_tracker/services/photo_source.dart';
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
  return FileImageStore(Directory(p.join(root.path, 'receipts')));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final repository = SettingsRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final photoRetentionSweeperProvider = Provider<PhotoRetentionSweeper>((ref) {
  return PhotoRetentionSweeper(
    expenses: ref.watch(expenseRepositoryProvider),
    store: ref.watch(imageStoreProvider),
  );
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return Platform.isAndroid || Platform.isIOS
      ? LocalAuthAppLockService()
      : const UnavailableAppLockService();
});

/// Whether the device can authenticate at all.
///
/// A device with no enrolled biometric and no PIN cannot, and neither can
/// anything below Android 6 — the toggle stays hidden rather than offering a
/// lock that could never engage.
final appLockAvailableProvider = FutureProvider<bool>((ref) {
  return ref.watch(appLockServiceProvider).isAvailable();
});

/// Whether the lock is switched on. Defaults to off.
final appLockEnabledProvider = FutureProvider<bool>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  final subscription = settings.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return settings.getAppLockEnabled();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return Platform.isAndroid || Platform.isIOS
      ? LocalNotificationService()
      : const UnavailableNotificationService();
});

final budgetAlertServiceProvider = Provider<BudgetAlertService>((ref) {
  return BudgetAlertService(
    expenses: ref.watch(expenseRepositoryProvider),
    weekBudgets: ref.watch(weekBudgetRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

/// Where receipt photos come from.
///
/// Overridden in tests with a fake, which is the whole reason it is an
/// interface — `image_picker` is a platform channel and cannot be driven from
/// a widget test.
final photoSourceProvider = Provider<PhotoSource>((ref) {
  return Platform.isAndroid || Platform.isIOS
      ? ImagePickerPhotoSource()
      : const UnavailablePhotoSource();
});

/// Reads text from a receipt photo.
///
/// On Android this is the channel to the Kotlin plugin — which, until Phase
/// 3d, answers with a hardcoded receipt rather than reading the photo. So
/// chips will appear and they will say 2.75, 3.50, 7.06 regardless of what
/// you photographed. That is the point of the step: it proves the boundary
/// works before ML Kit is in the picture to blame.
///
/// Everywhere else, the unavailable implementation. The form treats "no
/// candidates" as an ordinary outcome, so no UI code cares which is in place.
final ocrServiceProvider = Provider<OcrService>((ref) {
  return Platform.isAndroid
      ? const ChannelOcrService()
      : const UnavailableOcrService();
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

/// Whether each budget warning is switched on.
final alertEnabledProvider = FutureProvider.family<bool, BudgetAlert>((
  ref,
  alert,
) {
  final settings = ref.watch(settingsRepositoryProvider);
  final subscription = settings.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return settings.getAlertEnabled(alert);
});

/// How long photos are kept.
final photoRetentionProvider = FutureProvider<PhotoRetention>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  final subscription = settings.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return settings.getPhotoRetention();
});

/// What the photo library currently costs.
///
/// Refreshed on any expense write, because deleting an expense eventually
/// frees its photo, and on any settings write, because changing the retention
/// window runs a sweep.
final storageUsageProvider = FutureProvider<StorageUsage>((ref) async {
  _refreshOnAnyWrite(ref);
  final settings = ref.watch(settingsRepositoryProvider);
  final subscription = settings.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);

  final store = ref.watch(imageStoreProvider);
  return StorageUsage(
    photoCount: await store.count(),
    bytes: await store.totalBytes(),
  );
});

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
  // Both repositories are resolved before the first await. Reading a provider
  // after one suspends this body is how a dependency quietly goes untracked —
  // it happened to work here, but the other providers in this file all hoist
  // their reads and this one should match them.
  final weekRepository = ref.watch(weekBudgetRepositoryProvider);
  final expenseRepository = ref.watch(expenseRepositoryProvider);

  final weeks = await weekRepository.all();
  final totals = await expenseRepository.weekTotals();

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

/// One week's expenses, newest first.
///
/// A family because the week is the argument. Re-runs on any write, so an
/// expense edited from the detail screen updates it without a manual refresh.
final weekExpensesProvider = FutureProvider.family<List<Expense>, DateTime>((
  ref,
  weekStart,
) {
  _refreshOnAnyWrite(ref);
  return ref.watch(expenseRepositoryProvider).forWeek(weekStart);
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

/// What the stored photos add up to.
class StorageUsage {
  const StorageUsage({required this.photoCount, required this.bytes});

  final int photoCount;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is StorageUsage &&
      other.photoCount == photoCount &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(photoCount, bytes);
}

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
