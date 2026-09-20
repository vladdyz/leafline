import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/settings_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/models/budget_alert.dart';
import 'package:receipt_tracker/services/budget_alert_service.dart';

import '../helpers/fake_notification_service.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  // 2026-09-14 is a Monday; "now" is the Thursday of that week.
  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);
  final lastWeek = DateTime(2026, 9, 7);
  const budget = 20000; // $200.00

  group('pendingBudgetAlert', () {
    BudgetAlert? alert({
      required int spent,
      int budgetCents = budget,
      DateTime? approachingFiredFor,
      DateTime? overFiredFor,
      bool approachingEnabled = true,
      bool overEnabled = true,
    }) {
      return pendingBudgetAlert(
        spentCents: spent,
        budgetCents: budgetCents,
        currentWeek: thisWeek,
        approachingFiredFor: approachingFiredFor,
        overFiredFor: overFiredFor,
        approachingEnabled: approachingEnabled,
        overEnabled: overEnabled,
      );
    }

    test('nothing below the threshold', () {
      expect(alert(spent: 15999), isNull);
    });

    test('approaching exactly at 80%', () {
      expect(alert(spent: 16000), BudgetAlert.approaching);
    });

    test('over exactly at the budget', () {
      expect(alert(spent: budget), BudgetAlert.over);
    });

    test('over above the budget', () {
      expect(alert(spent: 25000), BudgetAlert.over);
    });

    test('no budget means no warning', () {
      expect(alert(spent: 99999, budgetCents: 0), isNull);
    });

    group('at most once per week', () {
      test('approaching does not repeat within the week', () {
        expect(alert(spent: 17000, approachingFiredFor: thisWeek), isNull);
      });

      test('over does not repeat within the week', () {
        expect(alert(spent: 25000, overFiredFor: thisWeek), isNull);
      });

      test('a flag from last week does not suppress this week', () {
        // The reset, and it happens without anything cleaning up — the stored
        // week simply stops matching.
        expect(
          alert(spent: 17000, approachingFiredFor: lastWeek),
          BudgetAlert.approaching,
        );
      });

      test('having fired approaching does not block over', () {
        expect(
          alert(spent: 25000, approachingFiredFor: thisWeek),
          BudgetAlert.over,
        );
      });

      test('having fired over does not block a later approaching', () {
        // Reaching this band after being over means an expense was deleted,
        // and being told you are near the limit is then accurate.
        expect(
          alert(spent: 17000, overFiredFor: thisWeek),
          BudgetAlert.approaching,
        );
      });
    });

    group('switched off', () {
      test('approaching disabled', () {
        expect(alert(spent: 17000, approachingEnabled: false), isNull);
      });

      test('over disabled', () {
        expect(alert(spent: 25000, overEnabled: false), isNull);
      });

      test('disabling one does not disable the other', () {
        expect(
          alert(spent: 25000, approachingEnabled: false),
          BudgetAlert.over,
        );
      });
    });
  });

  group('SettingsRepository alert preferences', () {
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

    test('both alerts default to on', () async {
      for (final alert in BudgetAlert.values) {
        expect(await settings.getAlertEnabled(alert), isTrue);
      }
    });

    test('an alert can be switched off and back on', () async {
      await settings.setAlertEnabled(BudgetAlert.over, enabled: false);
      expect(await settings.getAlertEnabled(BudgetAlert.over), isFalse);
      expect(await settings.getAlertEnabled(BudgetAlert.approaching), isTrue);

      await settings.setAlertEnabled(BudgetAlert.over, enabled: true);
      expect(await settings.getAlertEnabled(BudgetAlert.over), isTrue);
    });

    test('no fired week until one is recorded', () async {
      expect(await settings.getAlertFiredFor(BudgetAlert.over), isNull);
    });

    test('a fired week round-trips', () async {
      await settings.setAlertFiredFor(BudgetAlert.over, thisWeek);
      expect(await settings.getAlertFiredFor(BudgetAlert.over), thisWeek);
    });

    test('the two alerts track separately', () async {
      await settings.setAlertFiredFor(BudgetAlert.over, thisWeek);
      expect(await settings.getAlertFiredFor(BudgetAlert.approaching), isNull);
    });

    test('a malformed stored week reads as never fired', () async {
      await database.db.insert('settings', <String, Object?>{
        'key': 'alert_over_week',
        'value': 'sometime last spring',
      });
      expect(await settings.getAlertFiredFor(BudgetAlert.over), isNull);
    });
  });

  group('BudgetAlertService', () {
    late AppDatabase database;
    late ExpenseRepository expenses;
    late WeekBudgetRepository weekBudgets;
    late SettingsRepository settings;
    late FakeNotificationService notifications;
    late BudgetAlertService service;

    setUp(() async {
      database = await openTestDatabase();
      expenses = ExpenseRepository(database);
      weekBudgets = WeekBudgetRepository(database);
      settings = SettingsRepository(database);
      notifications = FakeNotificationService();
      service = BudgetAlertService(
        expenses: expenses,
        weekBudgets: weekBudgets,
        settings: settings,
        notifications: notifications,
      );

      await weekBudgets.setDefaultWeeklyCents(budget, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);

      addTearDown(() async {
        await expenses.dispose();
        await weekBudgets.dispose();
        await settings.dispose();
        await database.close();
      });
    });

    Future<void> spend(String id, int cents) => expenses.insert(
      makeExpense(id: id, amountCents: cents, spentOn: DateTime(2026, 9, 16)),
    );

    test('says nothing while under the threshold', () async {
      await spend('a', 5000);
      expect(await service.checkAndNotify(now: now), isNull);
      expect(notifications.shown, isEmpty);
    });

    test('warns on the expense that crosses 80%', () async {
      await spend('a', 16000);
      expect(await service.checkAndNotify(now: now), BudgetAlert.approaching);
      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, 'Getting close this week');
      expect(notifications.shown.single.body, contains(r'$40.00 left'));
    });

    test('warns on the expense that passes the budget', () async {
      await spend('a', 25000);
      expect(await service.checkAndNotify(now: now), BudgetAlert.over);
      expect(notifications.shown.single.title, 'Over your weekly budget');
      expect(notifications.shown.single.body, contains(r'over by $50.00'));
    });

    test('does not warn twice in the same week', () async {
      await spend('a', 17000);
      expect(await service.checkAndNotify(now: now), BudgetAlert.approaching);

      await spend('b', 500);
      expect(await service.checkAndNotify(now: now), isNull);
      expect(notifications.shown, hasLength(1));
    });

    test('crossing straight past records both thresholds', () async {
      // So that deleting back into the 80-99% band does not then produce an
      // "approaching" warning about a limit already crossed.
      await spend('a', 25000);
      await service.checkAndNotify(now: now);

      expect(
        await settings.getAlertFiredFor(BudgetAlert.approaching),
        thisWeek,
      );
      expect(await settings.getAlertFiredFor(BudgetAlert.over), thisWeek);
    });

    test('both warnings can fire in one week', () async {
      await spend('a', 17000);
      expect(await service.checkAndNotify(now: now), BudgetAlert.approaching);

      await spend('b', 5000);
      expect(await service.checkAndNotify(now: now), BudgetAlert.over);
      expect(notifications.shown, hasLength(2));
    });

    test('reuses one notification id so warnings replace each other', () async {
      await spend('a', 17000);
      await service.checkAndNotify(now: now);
      await spend('b', 5000);
      await service.checkAndNotify(now: now);

      expect(notifications.shown.map((n) => n.id).toSet(), <int>{
        BudgetAlertService.notificationId,
      });
    });

    test('says nothing when the week has no budget', () async {
      await weekBudgets.overrideWeek(thisWeek, 0, now: now);
      await spend('a', 50000);
      expect(await service.checkAndNotify(now: now), isNull);
    });

    test('says nothing when the platform cannot notify', () async {
      notifications.supported = false;
      await spend('a', 25000);
      expect(await service.checkAndNotify(now: now), isNull);
    });

    test('a refused permission shows nothing but still records', () async {
      // Recorded before showing, so a denied permission does not mean being
      // asked again on the very next expense.
      notifications.permissionGranted = false;
      await spend('a', 25000);

      expect(await service.checkAndNotify(now: now), isNull);
      expect(notifications.shown, isEmpty);
      expect(await settings.getAlertFiredFor(BudgetAlert.over), thisWeek);
    });

    test('respects the switch being off', () async {
      await settings.setAlertEnabled(BudgetAlert.over, enabled: false);
      await spend('a', 25000);

      expect(await service.checkAndNotify(now: now), isNull);
      expect(notifications.shown, isEmpty);
    });

    test('only counts the current week', () async {
      await weekBudgets.ensureWeek(lastWeek, now: lastWeek);
      await expenses.insert(
        makeExpense(
          id: 'old',
          amountCents: 50000,
          spentOn: DateTime(2026, 9, 8),
        ),
      );
      expect(await service.checkAndNotify(now: now), isNull);
    });
  });
}
