import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// Phase 0 entry point.
///
/// This screen exists to prove the toolchain works end to end: the app
/// builds, Riverpod is wired, and the pure utility layer is reachable from
/// the UI. Phase 2 replaces it entirely with the week list.
void main() {
  runApp(const ProviderScope(child: ReceiptTrackerApp()));
}

class ReceiptTrackerApp extends StatelessWidget {
  const ReceiptTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6B52)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F6B52),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _Phase0Screen(),
    );
  }
}

class _Phase0Screen extends StatelessWidget {
  const _Phase0Screen();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = weekStart(now);
    final end = weekEnd(now);

    // Placeholder figures. Phase 1 replaces these with repository queries.
    const spent = 16400;
    const budget = 20000;
    final state = budgetStateFor(spentCents: spent, budgetCents: budget);

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Week of ${isoDate(start)} to ${isoDate(end)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: budgetProgress(spentCents: spent, budgetCents: budget),
              minHeight: 10,
            ),
            const SizedBox(height: 12),
            Text(
              '${formatCents(spent)} of ${formatCentsCompact(budget)}'
              ' — ${formatCents(remainingCents(spentCents: spent, budgetCents: budget))} left',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'State: ${state.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Text(
              'Phase 0 skeleton. Figures above are hardcoded.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
