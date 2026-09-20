import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/week_detail_screen.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:receipt_tracker/ui/widgets/budget_bar.dart';
import 'package:receipt_tracker/ui/widgets/week_budget_sheet.dart';
import 'package:receipt_tracker/util/money.dart';

/// Every tracked week, plus the next few that can be planned.
///
/// Weeks before the user started tracking do not appear at all. That absence
/// is the point: there is no row for them, so the app makes no claim about
/// them in either direction. A history that stretched backwards marking
/// untouched weeks as successes would be inventing a record.
class AllWeeksScreen extends ConsumerWidget {
  const AllWeeksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(weekHistoryProvider);
    final upcoming = ref.watch(upcomingWeeksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All weeks')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Could not load your weeks.\n$error'),
          ),
        ),
        data: (weeks) {
          final planned = upcoming.value ?? const <UpcomingWeek>[];

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              if (planned.isNotEmpty) ...<Widget>[
                const _SectionHeader(
                  title: 'Coming up',
                  subtitle:
                      'Give a single week its own budget without changing '
                      'your default.',
                ),
                for (final week in planned) _UpcomingRow(week: week),
                const Divider(height: 32),
              ],
              const _SectionHeader(
                title: 'History',
                subtitle:
                    'Tap a week to see what you spent. Only weeks you '
                    'were tracking appear here.',
              ),
              if (weeks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No weeks tracked yet.'),
                )
              else
                for (final week in weeks) _HistoryRow(summary: week),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.summary});

  final WeekSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.MMMd();
    final range =
        '${format.format(summary.weekStart)} \u2013 '
        '${format.format(summary.weekEndDate)}';

    final spent = formatCents(summary.totalCents);
    final of = summary.budgetCents > 0
        ? ' of ${formatCentsCompact(summary.budgetCents)}'
        : '';

    return ListTile(
      // Opens the week, not its budget. A finished week's budget is frozen
      // (decision 0011), so offering to edit it was the app contradicting its
      // own design — and someone looking at a week from two months ago wants
      // to see what they bought, not to re-plan it.
      onTap: () => WeekDetailScreen.open(context, summary),
      leading: Container(
        width: 6,
        height: 40,
        decoration: BoxDecoration(
          color: outcomeColor(context, summary.outcome),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(range),
      subtitle: Text(
        '$spent$of',
        style: HarvestTheme.money(theme.textTheme.bodySmall),
      ),
      trailing: OutcomeChip(outcome: summary.outcome),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.week});

  final UpcomingWeek week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.MMMd();
    final range =
        '${format.format(week.weekStart)} \u2013 '
        '${format.format(week.weekEndDate)}';

    return ListTile(
      onTap: () => WeekBudgetSheet.show(
        context,
        weekStart: week.weekStart,
        currentCents: week.budgetCents,
        isOverride: week.isOverride,
      ),
      leading: Icon(
        week.isOverride ? Icons.push_pin_outlined : Icons.event_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(range),
      subtitle: Text(
        _subtitleFor(week),
        style: HarvestTheme.money(theme.textTheme.bodySmall),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  static String _subtitleFor(UpcomingWeek week) {
    if (week.budgetCents <= 0) return 'No budget set';
    final amount = formatCents(week.budgetCents);
    return week.isOverride ? amount : '$amount (your default)';
  }
}
