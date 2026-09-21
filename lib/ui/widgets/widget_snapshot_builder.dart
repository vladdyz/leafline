import 'package:intl/intl.dart';
import 'package:receipt_tracker/services/widget_bridge.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

/// Turns a week into what the home screen should say about it.
///
/// Takes plain values rather than a `WeekView` or a `WeekSummary`. Those two
/// classes expose identical accessors for everything needed here, so binding
/// to either would tie the widget's wording to whichever provider happens to
/// feed it — and the earlier version bound to the wrong one.
///
/// Pure, and separate from the bridge, so the wording and the arithmetic can
/// be tested without a channel or a provider. Everything the widget displays
/// is decided here; Kotlin receives finished strings and an integer.
WidgetSnapshot snapshotFor({
  required DateTime weekStart,
  required DateTime weekEndDate,
  required int budgetCents,
  required int totalCents,
}) {
  final format = DateFormat.MMMd();
  final label =
      '${format.format(weekStart)} \u2013 ${format.format(weekEndDate)}';

  if (budgetCents <= 0) {
    return WidgetSnapshot(
      weekLabel: label,
      spentText: formatCents(totalCents),
      budgetText: 'no budget set',
      statusText: 'Set one in the app',
      percent: 0,
      outcome: 'noBudget',
    );
  }

  final state = budgetStateFor(
    spentCents: totalCents,
    budgetCents: budgetCents,
  );

  final status = switch (state) {
    BudgetState.over => 'over by ${formatCents(totalCents - budgetCents)}',
    _ => '${formatCents(budgetCents - totalCents)} left',
  };

  return WidgetSnapshot(
    weekLabel: label,
    spentText: formatCents(totalCents),
    budgetText: 'of ${formatCentsCompact(budgetCents)}',
    statusText: status,
    // Clamped. A week at 340% should fill the bar, not overflow it — and a
    // ProgressBar given 340 renders undefined rather than clipping.
    percent: ((totalCents / budgetCents) * 100).round().clamp(0, 100),
    outcome: state.name,
  );
}
