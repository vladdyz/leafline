import 'dart:async';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/models/photo_retention.dart';
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
}
