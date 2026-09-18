import 'dart:async';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/budget.dart';
import 'package:sqflite/sqflite.dart';

/// Reads and writes the single weekly budget row.
class BudgetRepository {
  BudgetRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Database get _db => _appDatabase.db;

  /// Emits after the budget changes.
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  /// Reads the budget.
  ///
  /// The schema seeds the singleton row on create, so this should always find
  /// one. It falls back to [Budget.unset] anyway rather than throwing — a
  /// missing budget row is not worth crashing the app over, and zero is a
  /// meaningful value that the rest of the code already handles.
  Future<Budget> get() async {
    final rows = await _db.query(
      AppDatabase.budgetsTable,
      where: 'id = ?',
      whereArgs: <Object?>[Budget.singletonId],
      limit: 1,
    );
    if (rows.isEmpty) return Budget.unset();
    return Budget.fromMap(rows.first);
  }

  /// Sets the weekly budget.
  ///
  /// Uses `insert ... ON CONFLICT REPLACE` rather than update, so it works
  /// whether or not the seeded row is present. That makes the method safe to
  /// call against a database created by an older version that did not seed.
  Future<Budget> setWeeklyCents(int cents, {DateTime? now}) async {
    if (cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'Budget cannot be negative');
    }

    final budget = Budget(weeklyCents: cents, updatedAt: now ?? DateTime.now());

    await _db.insert(
      AppDatabase.budgetsTable,
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (!_changes.isClosed) _changes.add(null);
    return budget;
  }

  /// Clears the budget back to unset.
  Future<Budget> clear({DateTime? now}) => setWeeklyCents(0, now: now);
}
