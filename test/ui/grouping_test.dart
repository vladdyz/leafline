import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/state/providers.dart';

import '../helpers/test_database.dart';

void main() {
  group('groupIntoWeeks', () {
    test('an empty list produces no groups', () {
      expect(groupIntoWeeks(<Expense>[]), isEmpty);
    });

    test('expenses in one week form a single group', () {
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'a', spentOn: DateTime(2026, 9, 14)),
        makeExpense(id: 'b', spentOn: DateTime(2026, 9, 20)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.weekStart, DateTime(2026, 9, 14));
      expect(groups.single.expenses, hasLength(2));
    });

    test('splits across a week boundary', () {
      // 2026-09-20 is a Sunday; 2026-09-21 is the next Monday.
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'sun', spentOn: DateTime(2026, 9, 20)),
        makeExpense(id: 'mon', spentOn: DateTime(2026, 9, 21)),
      ]);

      expect(groups, hasLength(2));
    });

    test('orders groups newest week first', () {
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'old', spentOn: DateTime(2026, 9, 9)),
        makeExpense(id: 'new', spentOn: DateTime(2026, 9, 21)),
        makeExpense(id: 'mid', spentOn: DateTime(2026, 9, 17)),
      ]);

      expect(groups.map((g) => g.weekStart).toList(), <DateTime>[
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 7),
      ]);
    });

    test('totals each group independently', () {
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'a', amountCents: 1000, spentOn: DateTime(2026, 9, 14)),
        makeExpense(id: 'b', amountCents: 500, spentOn: DateTime(2026, 9, 20)),
        makeExpense(id: 'c', amountCents: 2000, spentOn: DateTime(2026, 9, 21)),
      ]);

      expect(groups[0].totalCents, 2000);
      expect(groups[1].totalCents, 1500);
    });

    test('exposes the Sunday as the week end', () {
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'a', spentOn: DateTime(2026, 9, 17)),
      ]);

      expect(groups.single.weekEndDate, DateTime(2026, 9, 20));
    });

    test('a year boundary keeps one group', () {
      final groups = groupIntoWeeks(<Expense>[
        makeExpense(id: 'a', spentOn: DateTime(2026, 12, 31)),
        makeExpense(id: 'b', spentOn: DateTime(2027, 1, 1)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.weekStart, DateTime(2026, 12, 28));
    });
  });
}
