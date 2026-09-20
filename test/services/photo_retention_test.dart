import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/settings_repository.dart';
import 'package:receipt_tracker/models/photo_retention.dart';
import 'package:receipt_tracker/services/photo_retention_sweeper.dart';
import 'package:receipt_tracker/util/bytes.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 20, 10);

  group('PhotoRetention cutoffs', () {
    test('one month back', () {
      expect(PhotoRetention.oneMonth.cutoffFrom(now), DateTime(2026, 8, 20));
    });

    test('three months back', () {
      expect(PhotoRetention.threeMonths.cutoffFrom(now), DateTime(2026, 6, 20));
    });

    test('one year back', () {
      expect(PhotoRetention.oneYear.cutoffFrom(now), DateTime(2025, 9, 20));
    });

    test('forever has no cutoff', () {
      expect(PhotoRetention.forever.cutoffFrom(now), isNull);
    });

    test('crosses a year boundary going backwards', () {
      // January minus three months is October of the previous year. Calendar
      // arithmetic, not 90 days.
      expect(
        PhotoRetention.threeMonths.cutoffFrom(DateTime(2026, 1, 15)),
        DateTime(2025, 10, 15),
      );
    });

    test('handles a day that does not exist in the target month', () {
      // 31 March minus one month. DateTime normalises rather than throwing,
      // which is the behaviour we want — the exact day matters less than
      // never crashing on one.
      final cutoff = PhotoRetention.oneMonth.cutoffFrom(DateTime(2026, 3, 31));
      expect(cutoff, isNotNull);
      expect(cutoff!.isBefore(DateTime(2026, 3, 31)), isTrue);
    });
  });

  group('PhotoRetention.fromId', () {
    test('resolves every known id', () {
      for (final option in PhotoRetention.values) {
        expect(PhotoRetention.fromId(option.id), option);
      }
    });

    test('an unknown id falls back rather than throwing', () {
      // A value written by a future version must still read.
      expect(PhotoRetention.fromId('two_weeks'), PhotoRetention.fallback);
    });

    test('a null id falls back', () {
      expect(PhotoRetention.fromId(null), PhotoRetention.fallback);
    });

    test('the fallback is three months', () {
      expect(PhotoRetention.fallback, PhotoRetention.threeMonths);
    });
  });

  group('SettingsRepository', () {
    late AppDatabase database;
    late SettingsRepository settings;

    setUp(() async {
      database = await openTestDatabase();
      settings = SettingsRepository(database);
      addTearDown(() async {
        await settings.dispose();
        await database.close();
      });
    });

    test('creates the settings table at v3', () async {
      final rows = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      expect(rows.map((r) => r['name']! as String), contains('settings'));
    });

    test('opens at schema version 3', () async {
      final rows = await database.db.rawQuery('PRAGMA user_version');
      expect(rows.first['user_version'], 3);
    });

    test('an unset preference reads as the default', () async {
      // The v3 migration seeds nothing, so this is the state right after an
      // upgrade — and it has to behave like a fresh install.
      expect(await settings.getPhotoRetention(), PhotoRetention.fallback);
    });

    test('round-trips a value', () async {
      await settings.setPhotoRetention(PhotoRetention.oneYear);
      expect(await settings.getPhotoRetention(), PhotoRetention.oneYear);
    });

    test('writing twice keeps one row', () async {
      await settings.setPhotoRetention(PhotoRetention.oneMonth);
      await settings.setPhotoRetention(PhotoRetention.forever);

      final rows = await database.db.query('settings');
      expect(rows, hasLength(1));
      expect(await settings.getPhotoRetention(), PhotoRetention.forever);
    });

    test('an unrecognised stored value reads as the default', () async {
      await database.db.insert('settings', <String, Object?>{
        'key': SettingsRepository.keyPhotoRetention,
        'value': 'two_weeks',
      });
      expect(await settings.getPhotoRetention(), PhotoRetention.fallback);
    });

    test('emits a change on write', () async {
      final emissions = <void>[];
      final sub = settings.changes.listen(emissions.add);
      await settings.setPhotoRetention(PhotoRetention.oneYear);
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      await sub.cancel();
    });
  });

  group('PhotoRetentionSweeper', () {
    late AppDatabase database;
    late ExpenseRepository expenses;
    late InMemoryImageStore store;
    late PhotoRetentionSweeper sweeper;

    setUp(() async {
      database = await openTestDatabase();
      expenses = ExpenseRepository(database);
      store = InMemoryImageStore();
      sweeper = PhotoRetentionSweeper(expenses: expenses, store: store);

      // Two old, one recent, one with no photo at all.
      // Dated so the windows form a gradient against now = 2026-09-20:
      //   one year  (cutoff 2025-09-20) removes none
      //   three mo  (cutoff 2026-06-20) removes old1, old2
      //   one month (cutoff 2026-08-20) removes those plus midRange
      for (final entry in <List<Object>>[
        <Object>['old1', DateTime(2026, 1, 5), 'old1.jpg'],
        <Object>['old2', DateTime(2026, 2, 10), 'old2.jpg'],
        <Object>['midRange', DateTime(2026, 7, 15), 'midRange.jpg'],
        <Object>['recent', DateTime(2026, 9, 1), 'recent.jpg'],
      ]) {
        await store.save(entry[0] as String, <int>[1, 2, 3]);
        await expenses.insert(
          makeExpense(
            id: entry[0] as String,
            amountCents: 777,
            spentOn: entry[1] as DateTime,
            photoFile: entry[2] as String,
            ocrRawText: 'TOTAL 7.77',
          ),
        );
      }
      await expenses.insert(
        makeExpense(id: 'nophoto', spentOn: DateTime(2026, 1, 1)),
      );

      addTearDown(() async {
        await expenses.dispose();
        await database.close();
      });
    });

    test('removes photos past the window', () async {
      final removed = await sweeper.sweep(
        retention: PhotoRetention.threeMonths,
        now: now,
      );
      expect(removed, 2);
      expect(await store.count(), 2);
      expect(store.exists('recent.jpg'), isTrue);
      expect(store.exists('midRange.jpg'), isTrue);
    });

    test('nulls the rows it cleared', () async {
      await sweeper.sweep(retention: PhotoRetention.threeMonths, now: now);
      expect((await expenses.getById('old1'))!.photoFile, isNull);
      expect((await expenses.getById('recent'))!.photoFile, 'recent.jpg');
    });

    test('never deletes an expense', () async {
      await sweeper.sweep(retention: PhotoRetention.threeMonths, now: now);
      expect(await expenses.count(), 5);
    });

    test('an expired expense keeps everything but its photo', () async {
      // The whole point of decision 0006.
      await sweeper.sweep(retention: PhotoRetention.threeMonths, now: now);

      final old = (await expenses.getById('old1'))!;
      expect(old.photoFile, isNull);
      expect(old.amountCents, 777);
      expect(old.ocrRawText, 'TOTAL 7.77');
      expect(old.spentOn, DateTime(2026, 1, 5));
    });

    test('forever removes nothing', () async {
      final removed = await sweeper.sweep(
        retention: PhotoRetention.forever,
        now: now,
      );
      expect(removed, 0);
      expect(await store.count(), 4);
    });

    test('a shorter window removes more', () async {
      final removed = await sweeper.sweep(
        retention: PhotoRetention.oneMonth,
        now: now,
      );
      expect(removed, 3);
      expect(store.exists('recent.jpg'), isTrue);
      expect(store.exists('midRange.jpg'), isFalse);
    });

    test('a longer window removes nothing here', () async {
      final removed = await sweeper.sweep(
        retention: PhotoRetention.oneYear,
        now: now,
      );
      expect(removed, 0);
      expect(await store.count(), 4);
    });

    test('is idempotent', () async {
      await sweeper.sweep(retention: PhotoRetention.threeMonths, now: now);
      final second = await sweeper.sweep(
        retention: PhotoRetention.threeMonths,
        now: now,
      );
      expect(second, 0);
    });

    test('an expense with no photo is untouched', () async {
      await sweeper.sweep(retention: PhotoRetention.oneMonth, now: now);
      expect(await expenses.getById('nophoto'), isNotNull);
    });
  });

  group('formatBytes', () {
    test('bytes below a kilobyte', () {
      expect(formatBytes(512), '512 B');
    });

    test('kilobytes are whole numbers', () {
      expect(formatBytes(2048), '2 KB');
    });

    test('megabytes carry one decimal', () {
      expect(formatBytes(1024 * 1024 * 3), '3.0 MB');
    });

    test('a realistic photo library', () {
      // 195 photos at 300KB — three months at fifteen receipts a week.
      expect(formatBytes(195 * 300 * 1024), '57.1 MB');
    });

    test('gigabytes carry two decimals', () {
      expect(formatBytes(1024 * 1024 * 1024 * 2), '2.00 GB');
    });

    test('zero', () {
      expect(formatBytes(0), '0 B');
    });

    test('a negative count does not produce a negative size', () {
      expect(formatBytes(-1), '0 KB');
    });
  });

  group('formatPhotoCount', () {
    test('none', () => expect(formatPhotoCount(0), 'No photos'));
    test('one is singular', () => expect(formatPhotoCount(1), '1 photo'));
    test('many', () => expect(formatPhotoCount(12), '12 photos'));
  });
}
