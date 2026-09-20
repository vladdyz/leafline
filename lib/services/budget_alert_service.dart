import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/settings_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/models/budget_alert.dart';
import 'package:receipt_tracker/services/notification_service.dart';
import 'package:receipt_tracker/util/money.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// Decides whether this week's spending warrants a warning, and sends it.
///
/// Called after an expense is written — that being the only moment spending
/// crosses a line. Deleting an expense lowers the total and never warns, and
/// changing a budget deliberately does not warn either: someone in Settings
/// choosing a smaller number already knows what they are doing, and a system
/// notification about a screen you are looking at is noise.
class BudgetAlertService {
  const BudgetAlertService({
    required this.expenses,
    required this.weekBudgets,
    required this.settings,
    required this.notifications,
  });

  /// One id for both alerts, so the second replaces the first rather than
  /// stacking beside it. Two warnings about the same week on screen at once
  /// would be the app talking over itself.
  static const int notificationId = 1;

  final ExpenseRepository expenses;
  final WeekBudgetRepository weekBudgets;
  final SettingsRepository settings;
  final NotificationService notifications;

  /// Evaluates the current week and notifies if warranted.
  ///
  /// Returns what was sent, or null. Recording happens before the
  /// notification is shown: a warning that fires twice is worse than one that
  /// silently fails, and a user who denies the permission should not be asked
  /// again on the very next expense.
  Future<BudgetAlert?> checkAndNotify({required DateTime now}) async {
    if (!notifications.isSupported) return null;

    final week = await weekBudgets.getWeek(now);
    if (week == null || !week.hasBudget) return null;

    final spent = await expenses.totalCentsForWeek(now);
    final currentWeek = weekStart(now);

    final alert = pendingBudgetAlert(
      spentCents: spent,
      budgetCents: week.budgetCents,
      currentWeek: currentWeek,
      approachingFiredFor: await settings.getAlertFiredFor(
        BudgetAlert.approaching,
      ),
      overFiredFor: await settings.getAlertFiredFor(BudgetAlert.over),
      approachingEnabled: await settings.getAlertEnabled(
        BudgetAlert.approaching,
      ),
      overEnabled: await settings.getAlertEnabled(BudgetAlert.over),
    );
    if (alert == null) return null;

    await settings.setAlertFiredFor(alert, currentWeek);
    if (alert == BudgetAlert.over) {
      // Going straight past the budget in one purchase records both, so
      // deleting back into the 80-99% band afterwards does not produce a
      // "you are approaching" warning about a limit already crossed once.
      await settings.setAlertFiredFor(BudgetAlert.approaching, currentWeek);
    }

    if (!await notifications.ensurePermission()) return null;

    await notifications.show(
      id: notificationId,
      title: alert == BudgetAlert.over
          ? 'Over your weekly budget'
          : 'Getting close this week',
      body: _bodyFor(
        alert: alert,
        spentCents: spent,
        budgetCents: week.budgetCents,
      ),
    );
    return alert;
  }

  static String _bodyFor({
    required BudgetAlert alert,
    required int spentCents,
    required int budgetCents,
  }) {
    final of =
        '${formatCents(spentCents)} of ${formatCentsCompact(budgetCents)}';
    if (alert == BudgetAlert.over) {
      final over = spentCents - budgetCents;
      return '$of — over by ${formatCents(over)}.';
    }
    final left = budgetCents - spentCents;
    return '$of — ${formatCents(left)} left.';
  }
}
