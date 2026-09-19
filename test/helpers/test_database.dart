import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initialises the FFI sqflite backend.
///
/// `flutter test` runs on the Dart VM, not on a device, so the normal sqflite
/// plugin has no platform to talk to. `sqflite_common_ffi` supplies a real
/// SQLite through FFI instead — the queries under test are executed by the
/// same engine that runs on the phone, not a mock.
///
/// Call once, from `setUpAll`.
void initTestDatabase() {
  sqfliteFfiInit();
}

/// Opens a fresh in-memory database.
///
/// Each call gets its own, so tests cannot leak state into one another.
///
/// Note the factory: `databaseFactoryFfiNoIsolate`, not `databaseFactoryFfi`.
/// The default runs SQLite in a background isolate, which works under plain
/// `test()` but not under `testWidgets()` — the widget-test binding controls
/// time, and replies from a real isolate never arrive, so every query hangs
/// until `pumpAndSettle` gives up. sqflite's own testing docs specify the
/// no-isolate factory for widget tests for exactly this reason.
///
/// It works for both kinds of test, so it is used for both.
Future<AppDatabase> openTestDatabase() {
  return AppDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfiNoIsolate,
  );
}

/// Builds an expense with sensible defaults, so a test only states the fields
/// it actually cares about.
///
/// Timestamps are fixed rather than `DateTime.now()` — a test asserting
/// equality on a round-tripped expense fails intermittently otherwise.
Expense makeExpense({
  String id = 'e1',
  int amountCents = 1000,
  DateTime? spentOn,
  String merchant = 'Test Merchant',
  ExpenseCategory category = ExpenseCategory.coffee,
  String? note,
  String? photoFile,
  String? ocrRawText,
  DateTime? stamp,
}) {
  final at = stamp ?? DateTime(2026, 9, 17, 12);
  final on = spentOn ?? DateTime(2026, 9, 17);
  return Expense(
    id: id,
    amountCents: amountCents,
    spentOn: DateTime(on.year, on.month, on.day),
    merchant: merchant,
    category: category,
    note: note,
    photoFile: photoFile,
    ocrRawText: ocrRawText,
    createdAt: at,
    updatedAt: at,
  );
}
