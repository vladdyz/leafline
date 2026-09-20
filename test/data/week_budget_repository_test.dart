import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/util/week_math.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  late AppDatabase database;
  late WeekBudgetRepository weeks;

  // 2026-09-14 is a Monday. "Now" for these tests is the Thursday of that
  // week, so the current week is 2026-09-14 and 2026-09-07 is history.
  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);
  final lastWeek = DateTime(2026, 9, 7);
  final nextWeek = DateTime(2026, 9, 21);

  setUp(() async {
    database = await openTestDatabase();
    weeks = WeekBudgetRepository(database);
  });

  tearDown(() async {
    await weeks.dispose();
    await database.close();
  });

  group('schema', () {
    test('creates week_budgets on a fresh database', () async {
      final rows = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = rows.map((r) => r['name']! as String).toSet();
      expect(names, contains('week_budgets'));
    });

    test('opens at schema version 3', () async {
      // PRAGMA rather than Database.getVersion(): sqflite's Database does not
      // expose that method here, and the pragma is what openDatabase(version:)
      // writes and what onUpgrade compares against anyway
      final rows = await database.db.rawQuery('PRAGMA user_version');
      expect(rows.first['user_version'], 3);
    });

    test('rejects a negative week budget', () async {
      expect(
        () => database.db.insert('week_budgets', <String, Object?>{
          'week_start': '2026-09-14',
          'budget_cents': -1,
          'is_override': 0,
          'created_at': 'x',
          'updated_at': 'x',
        }),
        throwsA(anything),
      );
    });

    test('rejects an is_override outside 0 and 1', () async {
      expect(
        () => database.db.insert('week_budgets', <String, Object?>{
          'week_start': '2026-09-14',
          'budget_cents': 100,
          'is_override': 2,
          'created_at': 'x',
          'updated_at': 'x',
        }),
        throwsA(anything),
      );
    });
  });

  group('untracked weeks', () {
    test('a week with no row reads as null, not as zero', () async {
      // This is the distinction the whole history view rests on: "never
      // tracked" must be answerable separately from "budget of nothing".
      expect(await weeks.getWeek(lastWeek), isNull);
    });

    test('firstTrackedWeek is null before anything is tracked', () async {
      expect(await weeks.firstTrackedWeek(), isNull);
    });

    test('firstTrackedWeek marks the boundary of history', () async {
      await weeks.ensureWeek(lastWeek, now: now);
      await weeks.ensureWeek(thisWeek, now: now);
      expect(await weeks.firstTrackedWeek(), lastWeek);
    });
  });

  group('ensureWeek', () {
    test('creates a row carrying the current default', () async {
      await weeks.setDefaultWeeklyCents(20000, now: now);
      final week = await weeks.ensureWeek(thisWeek, now: now);

      expect(week.weekStart, thisWeek);
      expect(week.budgetCents, 20000);
      expect(week.isOverride, isFalse);
    });

    test('normalises any day in the week to its Monday', () async {
      final week = await weeks.ensureWeek(DateTime(2026, 9, 20), now: now);
      expect(week.weekStart, thisWeek);
    });

    test('is idempotent', () async {
      await weeks.setDefaultWeeklyCents(20000, now: now);
      await weeks.ensureWeek(thisWeek, now: now);
      await weeks.setDefaultWeeklyCents(50000, now: DateTime(2026, 10, 1));
      await weeks.ensureWeek(thisWeek, now: now);

      final rows = await database.db.query('week_budgets');
      expect(rows, hasLength(1));
    });

    test('does not overwrite an override', () async {
      await weeks.overrideWeek(thisWeek, 50000, now: now);
      final week = await weeks.ensureWeek(thisWeek, now: now);
      expect(week.budgetCents, 50000);
      expect(week.isOverride, isTrue);
    });

    test('a week created with no default set has a zero budget', () async {
      final week = await weeks.ensureWeek(thisWeek, now: now);
      expect(week.budgetCents, 0);
      expect(week.hasBudget, isFalse);
    });
  });

  group('the default does not rewrite history', () {
    setUp(() async {
      await weeks.setDefaultWeeklyCents(10000, now: DateTime(2026, 9, 1));
      await weeks.ensureWeek(lastWeek, now: DateTime(2026, 9, 7));
      await weeks.ensureWeek(thisWeek, now: now);
    });

    test(
      'a completed week keeps its figure when the default changes',
      () async {
        await weeks.setDefaultWeeklyCents(15000, now: now);
        expect((await weeks.getWeek(lastWeek))!.budgetCents, 10000);
      },
    );

    test('the current week follows the default while it is running', () async {
      await weeks.setDefaultWeeklyCents(15000, now: now);
      expect((await weeks.getWeek(thisWeek))!.budgetCents, 15000);
    });

    test('an overridden current week ignores the default', () async {
      // Jim's vacation week.
      await weeks.overrideWeek(thisWeek, 50000, now: now);
      await weeks.setDefaultWeeklyCents(15000, now: now);

      expect((await weeks.getWeek(thisWeek))!.budgetCents, 50000);
    });

    test('the week after an override starts from the default again', () async {
      await weeks.overrideWeek(thisWeek, 50000, now: now);
      final next = await weeks.ensureWeek(nextWeek, now: DateTime(2026, 9, 21));

      expect(next.budgetCents, 10000);
      expect(next.isOverride, isFalse);
    });
  });

  group('override', () {
    test('marks the week and sets the figure', () async {
      final week = await weeks.overrideWeek(thisWeek, 50000, now: now);
      expect(week.budgetCents, 50000);
      expect(week.isOverride, isTrue);
    });

    test('works on a week that has no row yet', () async {
      await weeks.overrideWeek(nextWeek, 50000, now: now);
      expect((await weeks.getWeek(nextWeek))!.isOverride, isTrue);
    });

    test('preserves createdAt when replacing an existing row', () async {
      final created = DateTime(2026, 9, 14, 8);
      await weeks.ensureWeek(thisWeek, now: created);
      final week = await weeks.overrideWeek(thisWeek, 50000, now: now);
      expect(week.createdAt, created);
    });

    test('rejects a negative amount', () async {
      expect(
        () => weeks.overrideWeek(thisWeek, -1, now: now),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('clearOverride returns the week to the default', () async {
      await weeks.setDefaultWeeklyCents(10000, now: now);
      await weeks.overrideWeek(thisWeek, 50000, now: now);

      final cleared = await weeks.clearOverride(thisWeek, now: now);
      expect(cleared.budgetCents, 10000);
      expect(cleared.isOverride, isFalse);
    });
  });

  group('ranges', () {
    setUp(() async {
      await weeks.setDefaultWeeklyCents(20000, now: now);
      for (final monday in <DateTime>[
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 31),
        lastWeek,
        thisWeek,
        nextWeek,
      ]) {
        await weeks.ensureWeek(monday, now: monday);
      }
    });

    test('recent returns the newest four up to the current week', () async {
      final result = await weeks.recent(now: now);
      expect(result.map((w) => w.weekStart).toList(), <DateTime>[
        thisWeek,
        lastWeek,
        DateTime(2026, 8, 31),
        DateTime(2026, 8, 24),
      ]);
    });

    test('recent excludes future weeks even though they exist', () async {
      // A planned week sits in the table but must not head the list of weeks
      // that have actually happened.
      final result = await weeks.recent(now: now);
      expect(result.map((w) => w.weekStart), isNot(contains(nextWeek)));
    });

    test('planned returns only future weeks, oldest first', () async {
      final result = await weeks.planned(now: now);
      expect(result.map((w) => w.weekStart).toList(), <DateTime>[nextWeek]);
    });

    test('trackedCount excludes future weeks', () async {
      expect(await weeks.trackedCount(now: now), 6);
    });

    test('all returns every week including planned ones', () async {
      expect(await weeks.all(), hasLength(7));
    });
  });

  group('change notifications', () {
    test('ensureWeek emits when it creates a row', () async {
      final emissions = <void>[];
      final sub = weeks.changes.listen(emissions.add);
      await weeks.ensureWeek(thisWeek, now: now);
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      await sub.cancel();
    });

    test('setting the default emits', () async {
      final emissions = <void>[];
      final sub = weeks.changes.listen(emissions.add);
      await weeks.setDefaultWeeklyCents(20000, now: now);
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      await sub.cancel();
    });
  });

  group('week_math still agrees', () {
    test('every ensured week start is a Monday', () async {
      for (final day in <DateTime>[
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 17),
        DateTime(2026, 9, 20),
        DateTime(2027, 1, 1),
      ]) {
        final week = await weeks.ensureWeek(day, now: now);
        expect(week.weekStart.weekday, DateTime.monday);
        expect(week.weekStart, weekStart(day));
      }
    });
  });
}
