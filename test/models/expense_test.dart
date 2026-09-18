import 'package:flutter_test/flutter_test.dart';

import 'package:receipt_tracker/models/budget.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

import '../helpers/test_database.dart';

void main() {
  group('Expense.create', () {
    test('normalises spentOn to midnight', () {
      final expense = Expense.create(
        id: 'a',
        amountCents: 500,
        spentOn: DateTime(2026, 9, 17, 14, 32, 8),
      );
      expect(expense.spentOn, DateTime(2026, 9, 17));
    });

    test('stamps createdAt and updatedAt identically', () {
      final now = DateTime(2026, 9, 17, 10);
      final expense = Expense.create(
        id: 'a',
        amountCents: 500,
        spentOn: DateTime(2026, 9, 17),
        now: now,
      );
      expect(expense.createdAt, now);
      expect(expense.updatedAt, now);
    });

    test('defaults to the custom category', () {
      final expense = Expense.create(
        id: 'a',
        amountCents: 500,
        spentOn: DateTime(2026, 9, 17),
      );
      expect(expense.category, ExpenseCategory.custom);
    });

    test('rejects a negative amount', () {
      expect(
        () => Expense.create(
          id: 'a',
          amountCents: -1,
          spentOn: DateTime(2026, 9, 17),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('allows a zero amount', () {
      // A $0 expense is odd but not invalid, and rejecting it would be a
      // surprising validation failure mid-entry.
      expect(
        Expense.create(
          id: 'a',
          amountCents: 0,
          spentOn: DateTime(2026, 9, 17),
        ).amountCents,
        0,
      );
    });
  });

  group('Expense map round-trip', () {
    test('preserves every field', () {
      final original = makeExpense(
        id: 'abc',
        amountCents: 12345,
        merchant: 'Corner Market',
        category: ExpenseCategory.groceries,
        note: 'weekly shop',
        photoFile: 'abc.jpg',
        ocrRawText: 'TOTAL 123.45',
      );
      expect(Expense.fromMap(original.toMap()), original);
    });

    test('preserves nulls', () {
      final original = makeExpense(
        note: null,
        photoFile: null,
        ocrRawText: null,
      );
      final restored = Expense.fromMap(original.toMap());
      expect(restored.note, isNull);
      expect(restored.photoFile, isNull);
      expect(restored.ocrRawText, isNull);
    });

    test('stores the date without a time component', () {
      final map = makeExpense(spentOn: DateTime(2026, 9, 17)).toMap();
      expect(map['spent_on'], '2026-09-17');
    });

    test('stores the category id, not its label', () {
      final map = makeExpense(category: ExpenseCategory.dining).toMap();
      expect(map['category'], 'dining');
    });

    test('an unknown category id falls back to custom', () {
      final map = makeExpense().toMap()..['category'] = 'crypto';
      expect(Expense.fromMap(map).category, ExpenseCategory.custom);
    });
  });

  group('Expense.copyWith', () {
    test('changes one field and leaves the rest', () {
      final original = makeExpense(amountCents: 1000, merchant: 'A');
      final updated = original.copyWith(
        amountCents: 2000,
        now: DateTime(2026, 9, 18),
      );
      expect(updated.amountCents, 2000);
      expect(updated.merchant, 'A');
      expect(updated.id, original.id);
    });

    test('preserves createdAt and advances updatedAt', () {
      final original = makeExpense(stamp: DateTime(2026, 9, 17));
      final updated = original.copyWith(
        merchant: 'B',
        now: DateTime(2026, 9, 18),
      );
      expect(updated.createdAt, DateTime(2026, 9, 17));
      expect(updated.updatedAt, DateTime(2026, 9, 18));
    });

    test('clearPhoto nulls the photo without touching the rest', () {
      final original = makeExpense(
        photoFile: 'x.jpg',
        ocrRawText: 'TOTAL 10.00',
      );
      final updated = original.copyWith(
        clearPhoto: true,
        now: DateTime(2026, 9, 18),
      );
      expect(updated.photoFile, isNull);
      // The whole point of retention: the expense survives its photo.
      expect(updated.amountCents, original.amountCents);
      expect(updated.ocrRawText, 'TOTAL 10.00');
    });

    test('normalises a replacement date to midnight', () {
      final updated = makeExpense().copyWith(
        spentOn: DateTime(2026, 9, 20, 23, 59),
        now: DateTime(2026, 9, 21),
      );
      expect(updated.spentOn, DateTime(2026, 9, 20));
    });
  });

  group('Expense equality', () {
    test('two identical expenses are equal', () {
      expect(makeExpense(), makeExpense());
    });

    test('differing amounts are not equal', () {
      expect(makeExpense(amountCents: 1), isNot(makeExpense(amountCents: 2)));
    });

    test('equal expenses share a hashCode', () {
      expect(makeExpense().hashCode, makeExpense().hashCode);
    });
  });

  group('Expense.week', () {
    test('resolves to the Monday of its week', () {
      // 2026-09-20 is a Sunday.
      final expense = makeExpense(spentOn: DateTime(2026, 9, 20));
      expect(expense.week, DateTime(2026, 9, 14));
    });
  });

  group('Budget', () {
    test('unset is zero and reports isSet false', () {
      final budget = Budget.unset(now: DateTime(2026, 9, 17));
      expect(budget.weeklyCents, 0);
      expect(budget.isSet, isFalse);
    });

    test('a positive budget reports isSet true', () {
      final budget = Budget(
        weeklyCents: 20000,
        updatedAt: DateTime(2026, 9, 17),
      );
      expect(budget.isSet, isTrue);
    });

    test('round-trips through a map', () {
      final original = Budget(
        weeklyCents: 20000,
        updatedAt: DateTime(2026, 9, 17, 8, 30),
      );
      expect(Budget.fromMap(original.toMap()), original);
    });

    test('always maps to the singleton id', () {
      final map = Budget.unset(now: DateTime(2026, 9, 17)).toMap();
      expect(map['id'], Budget.singletonId);
    });

    test('rejects a negative budget', () {
      expect(
        () => Budget(weeklyCents: -1, updatedAt: DateTime(2026, 9, 17)),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
