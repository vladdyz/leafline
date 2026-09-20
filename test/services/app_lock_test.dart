import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/settings_repository.dart';
import 'package:receipt_tracker/models/budget_alert.dart';
import 'package:receipt_tracker/services/app_lock_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 20, 14, 0);
  const grace = Duration(minutes: 2);

  group('shouldLock', () {
    bool lock({bool enabled = true, DateTime? unlockedAt, DateTime? at}) {
      return shouldLock(
        enabled: enabled,
        unlockedAt: unlockedAt,
        now: at ?? now,
        grace: grace,
      );
    }

    test('switched off, never locks', () {
      expect(lock(enabled: false), isFalse);
    });

    test('switched off stays unlocked even after a long absence', () {
      expect(lock(enabled: false, unlockedAt: DateTime(2020, 1, 1)), isFalse);
    });

    test('cold start locks', () {
      // Never unlocked in this process.
      expect(lock(), isTrue);
    });

    test('just unlocked stays unlocked', () {
      expect(lock(unlockedAt: now), isFalse);
    });

    test('inside the grace window stays unlocked', () {
      // Glancing at a notification and coming back should not re-prompt.
      expect(
        lock(unlockedAt: now.subtract(const Duration(seconds: 90))),
        isFalse,
      );
    });

    test('exactly at the grace window locks', () {
      expect(lock(unlockedAt: now.subtract(grace)), isTrue);
    });

    test('past the grace window locks', () {
      expect(
        lock(unlockedAt: now.subtract(const Duration(minutes: 5))),
        isTrue,
      );
    });

    test('a clock that moved backwards does not lock', () {
      // now earlier than unlockedAt gives a negative difference, which must
      // not be read as "a long time ago".
      expect(lock(unlockedAt: now.add(const Duration(minutes: 10))), isFalse);
    });
  });

  group('UnavailableAppLockService', () {
    test('reports unavailable and never authenticates', () async {
      const service = UnavailableAppLockService();
      expect(await service.isAvailable(), isFalse);
      expect(await service.authenticate(), isFalse);
    });
  });

  group('app lock preference', () {
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

    test('defaults to off', () async {
      // Decision 0004: there is nothing to authenticate against, so this is
      // offered rather than imposed.
      expect(await settings.getAppLockEnabled(), isFalse);
    });

    test('round-trips', () async {
      await settings.setAppLockEnabled(enabled: true);
      expect(await settings.getAppLockEnabled(), isTrue);

      await settings.setAppLockEnabled(enabled: false);
      expect(await settings.getAppLockEnabled(), isFalse);
    });
  });

  group('resetAlertHistory', () {
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

    test('forgets both fired weeks', () async {
      await settings.setAlertFiredFor(BudgetAlert.approaching, now);
      await settings.setAlertFiredFor(BudgetAlert.over, now);

      await settings.resetAlertHistory();

      for (final alert in BudgetAlert.values) {
        expect(await settings.getAlertFiredFor(alert), isNull);
      }
    });

    test('leaves other preferences alone', () async {
      // It clears the fired record, not the switches — resetting for a test
      // should not silently re-enable something the user turned off.
      await settings.setAlertEnabled(BudgetAlert.over, enabled: false);
      await settings.setAppLockEnabled(enabled: true);
      await settings.setAlertFiredFor(BudgetAlert.over, now);

      await settings.resetAlertHistory();

      expect(await settings.getAlertEnabled(BudgetAlert.over), isFalse);
      expect(await settings.getAppLockEnabled(), isTrue);
    });

    test('is safe to call when nothing has fired', () async {
      await expectLater(settings.resetAlertHistory(), completes);
    });
  });
}
