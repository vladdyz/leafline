import 'dart:async';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/budget_alert.dart';
import 'package:receipt_tracker/models/photo_retention.dart';
import 'package:receipt_tracker/util/week_math.dart';
import 'package:sqflite/sqflite.dart';

/// App preferences, stored as strings in the `settings` table.
///
/// Every getter has a default and never throws on a missing or unrecognised
/// value. A preference that fails to read should fall back, not take the
/// screen down with it — and an absent key is the normal state right after an
/// upgrade, because the v3 migration seeds nothing.
class SettingsRepository {
  SettingsRepository(this._appDatabase);

  static const String keyPhotoRetention = 'photo_retention';
  static const String keyAppLock = 'app_lock_enabled';

  static String _enabledKey(BudgetAlert alert) => 'alert_${alert.name}_enabled';
  static String _firedKey(BudgetAlert alert) => 'alert_${alert.name}_week';

  final AppDatabase _appDatabase;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Database get _db => _appDatabase.db;

  /// Emits after any preference is written.
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  Future<String?> _read(String key) async {
    final rows = await _db.query(
      AppDatabase.settingsTable,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _write(String key, String value) async {
    await _db.insert(AppDatabase.settingsTable, <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!_changes.isClosed) _changes.add(null);
  }

  /// How long photos are kept. Defaults to [PhotoRetention.fallback].
  Future<PhotoRetention> getPhotoRetention() async =>
      PhotoRetention.fromId(await _read(keyPhotoRetention));

  Future<void> setPhotoRetention(PhotoRetention retention) =>
      _write(keyPhotoRetention, retention.id);

  /// Whether an alert is switched on. Both default to on.
  ///
  /// The thresholds are the app's reason for existing — a budget you are not
  /// told about is a number in a database. Someone who finds them intrusive
  /// can turn them off; nobody has to turn them on to get the point.
  Future<bool> getAlertEnabled(BudgetAlert alert) async {
    final value = await _read(_enabledKey(alert));
    return value == null ? true : value == 'true';
  }

  Future<void> setAlertEnabled(BudgetAlert alert, {required bool enabled}) =>
      _write(_enabledKey(alert), enabled ? 'true' : 'false');

  /// The Monday of the week this alert last fired in, or null.
  ///
  /// Storing the week rather than a counter is what makes "once per week"
  /// reset without any cleanup: come Monday the stored value simply stops
  /// matching the current week.
  Future<DateTime?> getAlertFiredFor(BudgetAlert alert) async {
    final value = await _read(_firedKey(alert));
    if (value == null) return null;
    try {
      return parseIsoDate(value);
    } on FormatException {
      // A malformed value means the alert fires once more. Harmless, and
      // better than throwing on a screen that only wanted to save an expense.
      return null;
    }
  }

  Future<void> setAlertFiredFor(BudgetAlert alert, DateTime week) =>
      _write(_firedKey(alert), isoDate(week));

  /// Forgets which warnings have already fired this week.
  ///
  /// Exists for manual testing: without it, confirming that a warning fires
  /// means waiting until Monday. Reached only from a debug build.
  Future<void> resetAlertHistory() async {
    for (final alert in BudgetAlert.values) {
      await _db.delete(
        AppDatabase.settingsTable,
        where: 'key = ?',
        whereArgs: <Object?>[_firedKey(alert)],
      );
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Whether the app asks for identity before showing anything.
  ///
  /// Defaults to **off**. Decision 0004 is that there is nothing to
  /// authenticate against — the data lives in the app's sandbox either way —
  /// so this guards exactly one threat: someone picking up an unlocked
  /// phone. Worth offering, not worth imposing.
  Future<bool> getAppLockEnabled() async => await _read(keyAppLock) == 'true';

  Future<void> setAppLockEnabled({required bool enabled}) =>
      _write(keyAppLock, enabled ? 'true' : 'false');
}
