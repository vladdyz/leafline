import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/util/week_math.dart';
import 'package:sqflite/sqflite.dart';

/// Opens and owns the sqflite database.
///
/// Callers get a [Database] and nothing else; repositories build their queries
/// on top. This class exists to keep the schema, the version number and the
/// migration ladder in one file rather than scattered across repositories.
class AppDatabase {
  AppDatabase._(this.db);

  /// Bump this for every schema change, and add a matching branch to
  /// [_onUpgrade]. Never edit [_onCreate] to make a change — an existing
  /// install will never run it again.
  ///
  /// v2 added [weekBudgetsTable].
  static const int schemaVersion = 2;

  static const String expensesTable = 'expenses';
  static const String budgetsTable = 'budgets';
  static const String weekBudgetsTable = 'week_budgets';

  final Database db;

  /// Opens the database at [path].
  ///
  /// [factory] exists so tests can inject an FFI factory and open an
  /// in-memory database. Production passes nothing and gets the platform
  /// default.
  static Future<AppDatabase> open({
    required String path,
    DatabaseFactory? factory,
  }) async {
    final database = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _onConfigure(Database db) async {
    // Off by default in SQLite, and silently ignored rather than erroring if
    // you forget — so it goes here, once, rather than being assumed.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $expensesTable (
        id            TEXT PRIMARY KEY,
        amount_cents  INTEGER NOT NULL CHECK (amount_cents >= 0),
        merchant      TEXT NOT NULL DEFAULT '',
        spent_on      TEXT NOT NULL,
        category      TEXT NOT NULL DEFAULT 'custom',
        note          TEXT,
        photo_file    TEXT,
        ocr_raw_text  TEXT,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      )
    ''');

    // Every week query filters on spent_on. Without this, grouping the list
    // is a full scan on every rebuild.
    await db.execute(
      'CREATE INDEX idx_expenses_spent_on ON $expensesTable(spent_on)',
    );

    // Holds the *default* weekly budget: the standing figure new weeks
    // inherit. It is not the budget of any particular week — that lives in
    // week_budgets, frozen per week.
    await db.execute('''
      CREATE TABLE $budgetsTable (
        id            INTEGER PRIMARY KEY CHECK (id = ${Budget.singletonId}),
        weekly_cents  INTEGER NOT NULL CHECK (weekly_cents >= 0),
        updated_at    TEXT NOT NULL
      )
    ''');

    await db.insert(budgetsTable, Budget.unset().toMap());

    await _createWeekBudgets(db);
  }

  /// One row per tracked week.
  ///
  /// The presence of a row is what makes a week exist as far as the app is
  /// concerned. Weeks before the user started have no row and are reported as
  /// untracked rather than as successes.
  static Future<void> _createWeekBudgets(Database db) async {
    await db.execute('''
      CREATE TABLE $weekBudgetsTable (
        week_start    TEXT PRIMARY KEY,
        budget_cents  INTEGER NOT NULL CHECK (budget_cents >= 0),
        is_override   INTEGER NOT NULL DEFAULT 0 CHECK (is_override IN (0, 1)),
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      )
    ''');
  }

  /// The migration ladder.
  ///
  /// Each version adds a branch; none of them ever edits an earlier one,
  /// because installs in the wild have already run those. Note `<` rather
  /// than `==`: an install skipping several versions must run every
  /// intermediate step in order.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createWeekBudgets(db);
      await _backfillWeekBudgets(db);
    }
  }

  /// Materialises a week row for every week that already contains an expense.
  ///
  /// This is the one-time cost of introducing per-week budgets to a database
  /// that predates them. There is no record of what the budget was during
  /// those weeks, so the current default is the best available answer and is
  /// frozen in at that value.
  ///
  /// Weeks with no expenses get no row, which is correct: before this
  /// migration the app had no concept of a week existing without spending, so
  /// there is nothing to recover.
  static Future<void> _backfillWeekBudgets(Database db) async {
    final budgetRows = await db.query(
      budgetsTable,
      columns: <String>['weekly_cents'],
      where: 'id = ?',
      whereArgs: <Object?>[Budget.singletonId],
      limit: 1,
    );
    final defaultCents = budgetRows.isEmpty
        ? 0
        : budgetRows.first['weekly_cents']! as int;

    final expenseRows = await db.query(
      expensesTable,
      columns: <String>['spent_on'],
    );

    final weeks = <DateTime>{
      for (final row in expenseRows)
        weekStart(parseIsoDate(row['spent_on']! as String)),
    };

    final stamp = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final week in weeks) {
      batch.insert(weekBudgetsTable, <String, Object?>{
        'week_start': isoDate(week),
        'budget_cents': defaultCents,
        'is_override': 0,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();

  /// Deletes every row, keeping the schema. Test helper, and the eventual
  /// implementation of a "clear all data" settings action.
  Future<void> clear() async {
    await db.delete(expensesTable);
    await db.delete(weekBudgetsTable);
    await db.delete(budgetsTable);
    await db.insert(budgetsTable, Budget.unset().toMap());
  }
}
