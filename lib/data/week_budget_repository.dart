import 'dart:async';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/models/week_budget.dart';
import 'package:receipt_tracker/util/week_math.dart';
import 'package:sqflite/sqflite.dart';

/// Owns the default weekly budget and the per-week rows derived from it.
///
/// The rules this class enforces, stated once:
///
/// 1. A week exists when it has a row. Creating that row is *materialising*
///    the week, and it happens on app start for the current week, and when an
///    expense lands in a week that has none.
/// 2. A materialised week copies the default budget at that moment and keeps
///    it. Changing the default later does not reach back.
/// 3. The one exception is the current week, while it is still running and
///    only if the user has not overridden it. An un-overridden week in
///    progress follows the default, because mid-week is not yet history.
/// 4. An overridden week ignores the default entirely, in progress or not.
///    This is the vacation week: set it to $500, and next week still starts
///    from the standing $100.
class WeekBudgetRepository {
  WeekBudgetRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Database get _db => _appDatabase.db;

  /// Emits after any change to the default or to a week row.
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ---------------------------------------------------------------- default

  /// The standing budget that newly materialised weeks inherit.
  Future<Budget> getDefault() async {
    final rows = await _db.query(
      AppDatabase.budgetsTable,
      where: 'id = ?',
      whereArgs: <Object?>[Budget.singletonId],
      limit: 1,
    );
    if (rows.isEmpty) return Budget.unset();
    return Budget.fromMap(rows.first);
  }

  /// Sets the standing budget.
  ///
  /// Also updates the current week, but only when that week is not an
  /// override. Completed weeks are never touched — that is the whole point of
  /// the table.
  Future<Budget> setDefaultWeeklyCents(int cents, {DateTime? now}) async {
    if (cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'Budget cannot be negative');
    }

    final stamp = now ?? DateTime.now();
    final budget = Budget(weeklyCents: cents, updatedAt: stamp);

    await _db.insert(
      AppDatabase.budgetsTable,
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.update(
      AppDatabase.weekBudgetsTable,
      <String, Object?>{
        'budget_cents': cents,
        'updated_at': stamp.toIso8601String(),
      },
      where: 'week_start = ? AND is_override = 0',
      whereArgs: <Object?>[isoDate(weekStart(stamp))],
    );

    _notify();
    return budget;
  }

  // ------------------------------------------------------------ week access

  /// The row for the week containing [anyDayInWeek], or null when the week
  /// was never tracked.
  Future<WeekBudget?> getWeek(DateTime anyDayInWeek) async {
    final rows = await _db.query(
      AppDatabase.weekBudgetsTable,
      where: 'week_start = ?',
      whereArgs: <Object?>[isoDate(weekStart(anyDayInWeek))],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WeekBudget.fromMap(rows.first);
  }

  /// Creates the week's row if it has none, and returns it either way.
  ///
  /// Idempotent: calling it on an existing week returns that week untouched,
  /// including its override. This is what makes it safe to call on every app
  /// start and on every expense write.
  Future<WeekBudget> ensureWeek(DateTime anyDayInWeek, {DateTime? now}) async {
    final existing = await getWeek(anyDayInWeek);
    if (existing != null) return existing;

    final stamp = now ?? DateTime.now();
    final defaultBudget = await getDefault();
    final week = WeekBudget(
      weekStart: weekStart(anyDayInWeek),
      budgetCents: defaultBudget.weeklyCents,
      createdAt: stamp,
      updatedAt: stamp,
    );

    await _db.insert(
      AppDatabase.weekBudgetsTable,
      week.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _notify();
    return week;
  }

  /// Sets a budget for one week specifically, marking it an override.
  ///
  /// Works on a future week too, which is how a known-expensive week ahead
  /// gets planned without disturbing the default.
  Future<WeekBudget> overrideWeek(
    DateTime anyDayInWeek,
    int cents, {
    DateTime? now,
  }) async {
    if (cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'Budget cannot be negative');
    }

    final stamp = now ?? DateTime.now();
    final existing = await getWeek(anyDayInWeek);
    final week = WeekBudget(
      weekStart: weekStart(anyDayInWeek),
      budgetCents: cents,
      isOverride: true,
      createdAt: existing?.createdAt ?? stamp,
      updatedAt: stamp,
    );

    await _db.insert(
      AppDatabase.weekBudgetsTable,
      week.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
    return week;
  }

  /// Drops an override, returning the week to following the default.
  ///
  /// Only meaningful for the current or a future week; a past week keeps
  /// whatever figure it ends up with.
  Future<WeekBudget> clearOverride(
    DateTime anyDayInWeek, {
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final defaultBudget = await getDefault();
    final existing = await getWeek(anyDayInWeek);

    final week = WeekBudget(
      weekStart: weekStart(anyDayInWeek),
      budgetCents: defaultBudget.weeklyCents,
      createdAt: existing?.createdAt ?? stamp,
      updatedAt: stamp,
    );

    await _db.insert(
      AppDatabase.weekBudgetsTable,
      week.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
    return week;
  }

  // ----------------------------------------------------------------- ranges

  /// Every tracked week, newest first.
  Future<List<WeekBudget>> all() async {
    final rows = await _db.query(
      AppDatabase.weekBudgetsTable,
      orderBy: 'week_start DESC',
    );
    return rows.map(WeekBudget.fromMap).toList();
  }

  /// Tracked weeks from [limit] weeks back up to and including the current
  /// week, newest first.
  ///
  /// Future weeks are excluded here even though they may exist as rows — a
  /// planned week ahead belongs in the planning UI, not at the top of the
  /// list of weeks that have happened.
  Future<List<WeekBudget>> recent({int limit = 4, DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rows = await _db.query(
      AppDatabase.weekBudgetsTable,
      where: 'week_start <= ?',
      whereArgs: <Object?>[isoDate(weekStart(today))],
      orderBy: 'week_start DESC',
      limit: limit,
    );
    return rows.map(WeekBudget.fromMap).toList();
  }

  /// Tracked weeks strictly after the current week, oldest first.
  Future<List<WeekBudget>> planned({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rows = await _db.query(
      AppDatabase.weekBudgetsTable,
      where: 'week_start > ?',
      whereArgs: <Object?>[isoDate(weekStart(today))],
      orderBy: 'week_start ASC',
    );
    return rows.map(WeekBudget.fromMap).toList();
  }

  /// How many tracked weeks exist at or before the current week.
  ///
  /// Used to decide whether the list needs a "see all weeks" affordance at
  /// all — with three weeks of history there is nothing to archive.
  Future<int> trackedCount({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${AppDatabase.weekBudgetsTable} '
      'WHERE week_start <= ?',
      <Object?>[isoDate(weekStart(today))],
    );
    return (rows.first['n']! as num).toInt();
  }

  /// The earliest tracked week, or null if the user has not started.
  ///
  /// This is the boundary the history view needs: everything before it is
  /// untracked and must render as such rather than as a run of perfect weeks.
  Future<DateTime?> firstTrackedWeek() async {
    final rows = await _db.query(
      AppDatabase.weekBudgetsTable,
      columns: <String>['week_start'],
      orderBy: 'week_start ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return parseIsoDate(rows.first['week_start']! as String);
  }
}
