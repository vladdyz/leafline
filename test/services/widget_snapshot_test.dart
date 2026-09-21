import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/services/widget_bridge.dart';
import 'package:receipt_tracker/ui/widgets/widget_snapshot_builder.dart';

/// The home screen widget shows finished strings, so this is where its
/// wording is decided — and therefore where it can be tested without a
/// channel, an emulator, or a home screen.
void main() {
  final monday = DateTime(2026, 9, 14);
  final sunday = DateTime(2026, 9, 20);

  WidgetSnapshot week({required int budgetCents, required int totalCents}) {
    return snapshotFor(
      weekStart: monday,
      weekEndDate: sunday,
      budgetCents: budgetCents,
      totalCents: totalCents,
    );
  }

  group('the week label', () {
    test('spans start to end', () {
      final snapshot = week(budgetCents: 20000, totalCents: 5000);
      expect(snapshot.weekLabel, 'Sep 14 \u2013 Sep 20');
    });
  });

  group('under budget', () {
    test('shows what is left', () {
      final snapshot = week(budgetCents: 20000, totalCents: 5000);
      expect(snapshot.spentText, r'$50.00');
      expect(snapshot.budgetText, r'of $200');
      expect(snapshot.statusText, r'$150.00 left');
      expect(snapshot.outcome, 'under');
      expect(snapshot.percent, 25);
    });

    test('a week with nothing spent', () {
      final snapshot = week(budgetCents: 20000, totalCents: 0);
      expect(snapshot.spentText, r'$0.00');
      expect(snapshot.statusText, r'$200.00 left');
      expect(snapshot.percent, 0);
    });
  });

  group('approaching', () {
    test('at exactly 80 per cent', () {
      final snapshot = week(budgetCents: 20000, totalCents: 16000);
      expect(snapshot.outcome, 'approaching');
      expect(snapshot.statusText, r'$40.00 left');
      expect(snapshot.percent, 80);
    });
  });

  group('over budget', () {
    test('says by how much', () {
      final snapshot = week(budgetCents: 20000, totalCents: 25000);
      expect(snapshot.outcome, 'over');
      expect(snapshot.statusText, r'over by $50.00');
    });

    test('exactly at the budget counts as over while live', () {
      final snapshot = week(budgetCents: 20000, totalCents: 20000);
      expect(snapshot.outcome, 'over');
      expect(snapshot.statusText, r'over by $0.00');
      expect(snapshot.percent, 100);
    });

    test('a wild overspend clamps the bar rather than overflowing it', () {
      // A ProgressBar handed 340 renders undefined, so the clamp is not
      // cosmetic.
      final snapshot = week(budgetCents: 10000, totalCents: 34000);
      expect(snapshot.percent, 100);
      expect(snapshot.statusText, r'over by $240.00');
    });
  });

  group('no budget', () {
    test('says so rather than dividing by zero', () {
      final snapshot = week(budgetCents: 0, totalCents: 4200);
      expect(snapshot.outcome, 'noBudget');
      expect(snapshot.spentText, r'$42.00');
      expect(snapshot.budgetText, 'no budget set');
      expect(snapshot.statusText, 'Set one in the app');
      expect(snapshot.percent, 0);
    });

    test('with nothing spent either', () {
      final snapshot = week(budgetCents: 0, totalCents: 0);
      expect(snapshot.percent, 0);
      expect(snapshot.outcome, 'noBudget');
    });
  });

  group('the channel payload', () {
    test('carries exactly the six keys Kotlin reads', () {
      final payload = week(budgetCents: 20000, totalCents: 5000).toChannel();

      expect(payload.keys.toSet(), <String>{
        'weekLabel',
        'spentText',
        'budgetText',
        'statusText',
        'percent',
        'outcome',
      });
    });

    test('percent crosses as an int, everything else as a string', () {
      // The Kotlin side reads percent with call.argument<Int>. A double here
      // would arrive as null and silently render an empty bar.
      final payload = week(budgetCents: 20000, totalCents: 16000).toChannel();

      expect(payload['percent'], isA<int>());
      for (final key in <String>[
        'weekLabel',
        'spentText',
        'budgetText',
        'statusText',
        'outcome',
      ]) {
        expect(payload[key], isA<String>(), reason: key);
      }
    });
  });

  group('equality', () {
    test('two snapshots of the same week match', () {
      expect(
        week(budgetCents: 20000, totalCents: 5000),
        week(budgetCents: 20000, totalCents: 5000),
      );
    });

    test('a changed total does not', () {
      expect(
        week(budgetCents: 20000, totalCents: 5000),
        isNot(week(budgetCents: 20000, totalCents: 5100)),
      );
    });
  });
}
