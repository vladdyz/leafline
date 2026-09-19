import 'package:flutter_test/flutter_test.dart';

import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/util/budget_rules.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository budgets;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    budgets = WeekBudgetRepository(database);
  });

  tearDown(() async {
    await expenses.dispose();
    await budgets.dispose();
    await database.close();
  });

  group('schema', () {
    test('creates both tables', () async {
      final rows = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = rows.map((r) => r['name']! as String).toSet();
      expect(names, containsAll(<String>['expenses', 'budgets']));
    });

    test('indexes spent_on', () async {
      final rows = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final names = rows.map((r) => r['name']! as String).toSet();
      expect(names, contains('idx_expenses_spent_on'));
    });

    test('seeds the budget singleton', () async {
      final budget = await budgets.getDefault();
      expect(budget.weeklyCents, 0);
    });

    test('rejects a second budget row', () async {
      // The CHECK (id = 1) constraint is what keeps this a singleton.
      expect(
        () => database.db.insert('budgets', <String, Object?>{
          'id': 2,
          'weekly_cents': 100,
          'updated_at': DateTime(2026, 9, 17).toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('rejects a negative amount at the database level', () async {
      // Belt and braces: the model asserts, and so does the schema.
      expect(
        () => database.db.insert('expenses', <String, Object?>{
          'id': 'bad',
          'amount_cents': -500,
          'merchant': '',
          'spent_on': '2026-09-17',
          'category': 'custom',
          'created_at': '2026-09-17T00:00:00.000',
          'updated_at': '2026-09-17T00:00:00.000',
        }),
        throwsA(anything),
      );
    });
  });

  group('ExpenseRepository CRUD', () {
    test('inserts and reads back', () async {
      final expense = makeExpense(id: 'a', amountCents: 1250);
      await expenses.insert(expense);
      expect(await expenses.getById('a'), expense);
    });

    test('getById returns null for an unknown id', () async {
      expect(await expenses.getById('nope'), isNull);
    });

    test('rejects a duplicate id', () async {
      await expenses.insert(makeExpense(id: 'a'));
      expect(() => expenses.insert(makeExpense(id: 'a')), throwsA(anything));
    });

    test('updates an existing row', () async {
      await expenses.insert(makeExpense(id: 'a', amountCents: 1000));
      final stored = (await expenses.getById('a'))!;
      final changed = stored.copyWith(
        amountCents: 2000,
        now: DateTime(2026, 9, 18),
      );

      expect(await expenses.update(changed), 1);
      expect((await expenses.getById('a'))!.amountCents, 2000);
    });

    test('updating an unknown id changes nothing and reports zero', () async {
      expect(await expenses.update(makeExpense(id: 'ghost')), 0);
    });

    test('deletes a row', () async {
      await expenses.insert(makeExpense(id: 'a'));
      expect(await expenses.delete('a'), 1);
      expect(await expenses.getById('a'), isNull);
    });

    test('deleting an unknown id reports zero', () async {
      expect(await expenses.delete('ghost'), 0);
    });

    test('counts rows', () async {
      expect(await expenses.count(), 0);
      await expenses.insert(makeExpense(id: 'a'));
      await expenses.insert(makeExpense(id: 'b'));
      expect(await expenses.count(), 2);
    });
  });

  group('ExpenseRepository ordering and ranges', () {
    setUp(() async {
      await expenses.insert(
        makeExpense(id: 'mon', spentOn: DateTime(2026, 9, 14)),
      );
      await expenses.insert(
        makeExpense(id: 'wed', spentOn: DateTime(2026, 9, 16)),
      );
      await expenses.insert(
        makeExpense(id: 'sun', spentOn: DateTime(2026, 9, 20)),
      );
      await expenses.insert(
        // Next week: 2026-09-21 is the following Monday.
        makeExpense(id: 'next', spentOn: DateTime(2026, 9, 21)),
      );
    });

    test('getAll returns newest first', () async {
      final ids = (await expenses.getAll()).map((e) => e.id).toList();
      expect(ids, <String>['next', 'sun', 'wed', 'mon']);
    });

    test('betweenDates is inclusive of start', () async {
      final result = await expenses.betweenDates(
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 15),
      );
      expect(result.map((e) => e.id), <String>['mon']);
    });

    test('betweenDates is exclusive of end', () async {
      final result = await expenses.betweenDates(
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 16),
      );
      expect(result.map((e) => e.id), <String>['mon']);
    });

    test('forWeek includes Monday through Sunday', () async {
      final result = await expenses.forWeek(DateTime(2026, 9, 17));
      expect(result.map((e) => e.id).toSet(), <String>{'mon', 'wed', 'sun'});
    });

    test('forWeek excludes the following Monday', () async {
      final result = await expenses.forWeek(DateTime(2026, 9, 17));
      expect(result.map((e) => e.id), isNot(contains('next')));
    });

    test('forWeek works from any day in the week', () async {
      final fromMonday = await expenses.forWeek(DateTime(2026, 9, 14));
      final fromSunday = await expenses.forWeek(DateTime(2026, 9, 20));
      expect(
        fromMonday.map((e) => e.id).toSet(),
        fromSunday.map((e) => e.id).toSet(),
      );
    });
  });

  group('ExpenseRepository totals', () {
    test('sums a week', () async {
      await expenses.insert(
        makeExpense(id: 'a', amountCents: 1000, spentOn: DateTime(2026, 9, 14)),
      );
      await expenses.insert(
        makeExpense(id: 'b', amountCents: 2550, spentOn: DateTime(2026, 9, 20)),
      );
      expect(await expenses.totalCentsForWeek(DateTime(2026, 9, 17)), 3550);
    });

    test('an empty week totals zero rather than null', () async {
      // COALESCE matters here: SUM over no rows returns NULL in SQLite, and
      // a null cast to int is a crash rather than a zero.
      expect(await expenses.totalCentsForWeek(DateTime(2026, 9, 17)), 0);
    });

    test('excludes other weeks from the total', () async {
      await expenses.insert(
        makeExpense(
          id: 'in',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 20),
        ),
      );
      await expenses.insert(
        makeExpense(
          id: 'out',
          amountCents: 9999,
          spentOn: DateTime(2026, 9, 21),
        ),
      );
      expect(await expenses.totalCentsForWeek(DateTime(2026, 9, 17)), 1000);
    });

    test('weekTotals groups by Monday and sorts newest first', () async {
      await expenses.insert(
        makeExpense(id: 'a', amountCents: 1000, spentOn: DateTime(2026, 9, 14)),
      );
      await expenses.insert(
        makeExpense(id: 'b', amountCents: 500, spentOn: DateTime(2026, 9, 20)),
      );
      await expenses.insert(
        makeExpense(id: 'c', amountCents: 2000, spentOn: DateTime(2026, 9, 21)),
      );

      final totals = await expenses.weekTotals();
      expect(totals.length, 2);
      expect(totals[0].weekStart, DateTime(2026, 9, 21));
      expect(totals[0].totalCents, 2000);
      expect(totals[1].weekStart, DateTime(2026, 9, 14));
      expect(totals[1].totalCents, 1500);
    });

    test('weekTotals is empty with no expenses', () async {
      expect(await expenses.weekTotals(), isEmpty);
    });

    test('weekTotals spans a year boundary correctly', () async {
      // 2027-01-01 is a Friday, in the week starting 2026-12-28.
      await expenses.insert(
        makeExpense(id: 'a', amountCents: 100, spentOn: DateTime(2026, 12, 31)),
      );
      await expenses.insert(
        makeExpense(id: 'b', amountCents: 200, spentOn: DateTime(2027, 1, 1)),
      );
      final totals = await expenses.weekTotals();
      expect(totals.length, 1);
      expect(totals.single.weekStart, DateTime(2026, 12, 28));
      expect(totals.single.totalCents, 300);
    });
  });

  group('ExpenseRepository photos', () {
    test('referencedPhotoFiles collects non-null filenames', () async {
      await expenses.insert(makeExpense(id: 'a', photoFile: 'a.jpg'));
      await expenses.insert(makeExpense(id: 'b'));
      await expenses.insert(makeExpense(id: 'c', photoFile: 'c.jpg'));
      expect(await expenses.referencedPhotoFiles(), <String>{'a.jpg', 'c.jpg'});
    });

    test(
      'clearPhotosOlderThan nulls old photos and keeps the expense',
      () async {
        await expenses.insert(
          makeExpense(
            id: 'old',
            amountCents: 777,
            spentOn: DateTime(2026, 1, 5),
            photoFile: 'old.jpg',
            ocrRawText: 'TOTAL 7.77',
          ),
        );
        await expenses.insert(
          makeExpense(
            id: 'new',
            spentOn: DateTime(2026, 9, 17),
            photoFile: 'new.jpg',
          ),
        );

        final cleared = await expenses.clearPhotosOlderThan(
          DateTime(2026, 6, 1),
        );
        expect(cleared, 1);

        final old = (await expenses.getById('old'))!;
        expect(old.photoFile, isNull);
        expect(old.amountCents, 777);
        expect(old.ocrRawText, 'TOTAL 7.77');

        expect((await expenses.getById('new'))!.photoFile, 'new.jpg');
      },
    );

    test('clearPhotosOlderThan reports zero when nothing qualifies', () async {
      await expenses.insert(
        makeExpense(
          id: 'a',
          spentOn: DateTime(2026, 9, 17),
          photoFile: 'a.jpg',
        ),
      );
      expect(await expenses.clearPhotosOlderThan(DateTime(2026, 1, 1)), 0);
    });
  });

  group('ExpenseRepository change notifications', () {
    test('emits on insert', () async {
      final emissions = <void>[];
      final sub = expenses.changes.listen(emissions.add);
      await expenses.insert(makeExpense(id: 'a'));
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      await sub.cancel();
    });

    test('does not emit when an update matches nothing', () async {
      final emissions = <void>[];
      final sub = expenses.changes.listen(emissions.add);
      await expenses.update(makeExpense(id: 'ghost'));
      await Future<void>.delayed(Duration.zero);
      expect(emissions, isEmpty);
      await sub.cancel();
    });
  });

  group('integration: budget state from stored data', () {
    test('a real week resolves to the approaching state', () async {
      await budgets.setDefaultWeeklyCents(20000, now: DateTime(2026, 9, 14));
      await expenses.insert(
        makeExpense(
          id: 'a',
          amountCents: 12000,
          spentOn: DateTime(2026, 9, 15),
          category: ExpenseCategory.groceries,
        ),
      );
      await expenses.insert(
        makeExpense(
          id: 'b',
          amountCents: 4400,
          spentOn: DateTime(2026, 9, 17),
          category: ExpenseCategory.dining,
        ),
      );

      final spent = await expenses.totalCentsForWeek(DateTime(2026, 9, 17));
      final budget = await budgets.getDefault();

      expect(spent, 16400);
      expect(
        budgetStateFor(spentCents: spent, budgetCents: budget.weeklyCents),
        BudgetState.approaching,
      );
    });
  });
}
