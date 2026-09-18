import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// Reads and writes expenses.
///
/// Imports no Flutter. Every method here is exercised by `flutter test`
/// against an in-memory database, with no device and no widget harness.
class ExpenseRepository {
  ExpenseRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Database get _db => _appDatabase.db;

  /// Emits after every write.
  ///
  /// sqflite has no reactive queries, so rather than faking them this is a
  /// bare "something changed" signal. Listeners re-run whatever query they
  /// care about. Cheap, and it keeps the repository from needing to know who
  /// is watching what.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Releases the change stream. Call when the repository is disposed.
  Future<void> dispose() => _changes.close();

  Future<void> insert(Expense expense) async {
    await _db.insert(
      AppDatabase.expensesTable,
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _notify();
  }

  /// Replaces an existing row wholesale.
  ///
  /// Returns the number of rows changed, which is 0 when the id is unknown —
  /// worth checking rather than assuming, since a silent no-op update is a
  /// miserable bug to track down.
  Future<int> update(Expense expense) async {
    final count = await _db.update(
      AppDatabase.expensesTable,
      expense.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[expense.id],
    );
    if (count > 0) _notify();
    return count;
  }

  Future<int> delete(String id) async {
    final count = await _db.delete(
      AppDatabase.expensesTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (count > 0) _notify();
    return count;
  }

  Future<Expense?> getById(String id) async {
    final rows = await _db.query(
      AppDatabase.expensesTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Expense.fromMap(rows.first);
  }

  /// All expenses, newest spending date first.
  ///
  /// The secondary sort on `created_at` makes the order stable for several
  /// expenses logged on the same day, which matters because an unstable sort
  /// makes list animations jump.
  Future<List<Expense>> getAll() async {
    final rows = await _db.query(
      AppDatabase.expensesTable,
      orderBy: 'spent_on DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Expenses in the half-open interval `[start, endExclusive)`.
  ///
  /// Half-open avoids the classic off-by-one where an expense on the final
  /// day is excluded because the end bound was compared at midnight.
  Future<List<Expense>> betweenDates(
    DateTime start,
    DateTime endExclusive,
  ) async {
    final rows = await _db.query(
      AppDatabase.expensesTable,
      where: 'spent_on >= ? AND spent_on < ?',
      whereArgs: <Object?>[isoDate(start), isoDate(endExclusive)],
      orderBy: 'spent_on DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Every expense in the Monday-started week containing [anyDayInWeek].
  Future<List<Expense>> forWeek(DateTime anyDayInWeek) {
    return betweenDates(
      weekStart(anyDayInWeek),
      weekEndExclusive(anyDayInWeek),
    );
  }

  /// Total cents spent in the week containing [anyDayInWeek].
  ///
  /// Summed in SQL rather than by fetching rows and adding them in Dart —
  /// this is the query the budget bar runs on every rebuild.
  Future<int> totalCentsForWeek(DateTime anyDayInWeek) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount_cents), 0) AS total '
      'FROM ${AppDatabase.expensesTable} '
      'WHERE spent_on >= ? AND spent_on < ?',
      <Object?>[
        isoDate(weekStart(anyDayInWeek)),
        isoDate(weekEndExclusive(anyDayInWeek)),
      ],
    );
    return (rows.first['total']! as num).toInt();
  }

  /// Totals per week, newest week first.
  ///
  /// Grouped in Dart rather than SQL because SQLite has no ISO-week function
  /// and `strftime('%W')` uses a different week convention than this app.
  /// The query pulls two columns, so even a few thousand rows is trivial.
  Future<List<WeekTotal>> weekTotals() async {
    final rows = await _db.query(
      AppDatabase.expensesTable,
      columns: <String>['spent_on', 'amount_cents'],
    );

    final totals = <DateTime, int>{};
    for (final row in rows) {
      final week = weekStart(parseIsoDate(row['spent_on']! as String));
      totals[week] = (totals[week] ?? 0) + (row['amount_cents']! as int);
    }

    final result = totals.entries
        .map((e) => WeekTotal(weekStart: e.key, totalCents: e.value))
        .toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return result;
  }

  /// Every photo filename currently referenced by a row.
  ///
  /// Used by the orphan sweep to decide which files on disk have no owner.
  Future<Set<String>> referencedPhotoFiles() async {
    final rows = await _db.query(
      AppDatabase.expensesTable,
      columns: <String>['photo_file'],
      where: 'photo_file IS NOT NULL',
    );
    return rows.map((r) => r['photo_file']! as String).toSet();
  }

  /// Clears `photo_file` on expenses whose photo has expired, leaving every
  /// other column untouched.
  ///
  /// This is the query that makes "the expense outlives its photo" true.
  /// Phase 4 calls it from the retention sweep.
  Future<int> clearPhotosOlderThan(DateTime cutoff) async {
    final count = await _db.update(
      AppDatabase.expensesTable,
      <String, Object?>{'photo_file': null},
      where: 'photo_file IS NOT NULL AND spent_on < ?',
      whereArgs: <Object?>[isoDate(cutoff)],
    );
    if (count > 0) _notify();
    return count;
  }

  Future<int> count() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${AppDatabase.expensesTable}',
    );
    return (rows.first['n']! as num).toInt();
  }
}

/// One week's spending total.
class WeekTotal {
  const WeekTotal({required this.weekStart, required this.totalCents});

  /// The Monday of the week, at local midnight.
  final DateTime weekStart;
  final int totalCents;

  @override
  bool operator ==(Object other) =>
      other is WeekTotal &&
      other.weekStart == weekStart &&
      other.totalCents == totalCents;

  @override
  int get hashCode => Object.hash(weekStart, totalCents);

  @override
  String toString() => 'WeekTotal(${weekStart.toIso8601String()}, $totalCents)';
}
