import 'package:flutter/material.dart';
import 'package:receipt_tracker/services/total_extractor.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:receipt_tracker/util/money.dart';

/// Candidate totals read off the receipt, offered as taps.
///
/// Offered, never filled in. The extractor is a heuristic and will be wrong
/// on some receipts; a wrong guess that costs one tap is a minor annoyance,
/// a wrong guess silently written into the amount field is a wrong expense.
///
/// When there are no candidates this renders nothing at all — no message, no
/// empty state. A photo of a blank wall, a failed recognition and a platform
/// with no OCR all look identical from here, which is correct: in every case
/// you type the amount, which is what you were going to do anyway.
class AmountChips extends StatelessWidget {
  const AmountChips({
    required this.candidates,
    required this.running,
    required this.onSelected,
    super.key,
  });

  final List<AmountCandidate> candidates;
  final bool running;
  final ValueChanged<AmountCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (running) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Reading the receipt\u2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (candidates.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'From the receipt',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final candidate in candidates)
                ActionChip(
                  // The line the amount came from, so two similar figures can
                  // be told apart without reopening the photo.
                  tooltip: candidate.sourceLine,
                  label: Text(
                    formatCents(candidate.cents),
                    style: HarvestTheme.money(theme.textTheme.labelLarge),
                  ),
                  onPressed: () => onSelected(candidate),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
