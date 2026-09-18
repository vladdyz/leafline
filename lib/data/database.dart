import 'package:receipt_tracker/models/budget.dart';
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
  static const int schemaVersion = 1;

  static const String expensesTable = 'expenses';
  static const String budgetsTable = 'budgets';

  final Database db;

  /// Opens the database at [path].
  ///
  /// [factory] exists so tests can inject `databaseFactoryFfi` and open an
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

    await db.execute('''
      CREATE TABLE $budgetsTable (
        id            INTEGER PRIMARY KEY CHECK (id = ${Budget.singletonId}),
        weekly_cents  INTEGER NOT NULL CHECK (weekly_cents >= 0),
        updated_at    TEXT NOT NULL
      )
    ''');

    // Seed the singleton so every read has a row to find and no caller needs
    // to handle "budget table is empty" as a separate case from "budget is
    // zero".
    await db.insert(budgetsTable, Budget.unset().toMap());
  }

  /// The migration ladder.
  ///
  /// Written now, while it does nothing, so the mechanism exists before it is
  /// first needed — which will be at the worst possible moment otherwise.
  /// Each future version adds a branch; none of them ever edits an earlier
  /// one, because installs in the wild have already run those.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Example of the shape this takes, for version 2:
    //
    // if (oldVersion < 2) {
    //   await db.execute(
    //     'ALTER TABLE $expensesTable ADD COLUMN tags TEXT',
    //   );
    // }
    //
    // Note the `<` rather than `==`: an install skipping several versions
    // must run every intermediate step in order.
  }

  Future<void> close() => db.close();

  /// Deletes every row, keeping the schema. Test helper, and the eventual
  /// implementation of a "clear all data" settings action.
  Future<void> clear() async {
    await db.delete(expensesTable);
    await db.delete(budgetsTable);
    await db.insert(budgetsTable, Budget.unset().toMap());
  }
}
