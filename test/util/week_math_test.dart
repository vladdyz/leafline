import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/util/week_math.dart';

void main() {
  group('weekStart', () {
    test('a Monday is its own week start', () {
      // 2026-09-14 is a Monday.
      expect(weekStart(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
    });

    test('a Sunday belongs to the week that began six days earlier', () {
      // 2026-09-20 is a Sunday.
      expect(weekStart(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
    });

    test('a mid-week day resolves to its Monday', () {
      expect(weekStart(DateTime(2026, 9, 17)), DateTime(2026, 9, 14));
    });

    test('normalises the time component to midnight', () {
      expect(
        weekStart(DateTime(2026, 9, 17, 23, 59, 59)),
        DateTime(2026, 9, 14),
      );
    });

    test('crosses a month boundary', () {
      // 2026-10-01 is a Thursday; its Monday is in September.
      expect(weekStart(DateTime(2026, 10, 1)), DateTime(2026, 9, 28));
    });

    test('crosses a year boundary', () {
      // 2027-01-01 is a Friday; its Monday is 2026-12-28.
      expect(weekStart(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('handles a leap day', () {
      // 2028-02-29 is a Tuesday.
      expect(weekStart(DateTime(2028, 2, 29)), DateTime(2028, 2, 28));
    });

    test('survives a spring-forward DST transition', () {
      // In most of North America clocks jump forward on 2027-03-14, a Sunday.
      // Duration-based arithmetic lands on the wrong day here; calendar
      // arithmetic does not.
      final result = weekStart(DateTime(2027, 3, 14));
      expect(result, DateTime(2027, 3, 8));
      expect(result.hour, 0);
    });

    test('survives a fall-back DST transition', () {
      // Clocks go back on 2027-11-07, a Sunday.
      final result = weekStart(DateTime(2027, 11, 7));
      expect(result, DateTime(2027, 11, 1));
      expect(result.hour, 0);
    });
  });

  group('weekEnd and weekEndExclusive', () {
    test('week end is the Sunday', () {
      expect(weekEnd(DateTime(2026, 9, 17)), DateTime(2026, 9, 20));
    });

    test('exclusive end is the following Monday', () {
      expect(weekEndExclusive(DateTime(2026, 9, 17)), DateTime(2026, 9, 21));
    });

    test('a week spans exactly seven days', () {
      final start = weekStart(DateTime(2026, 9, 17));
      final end = weekEndExclusive(DateTime(2026, 9, 17));
      expect(end.difference(start).inDays, 7);
    });
  });

  group('sameWeek', () {
    test('Monday and the following Sunday are the same week', () {
      expect(sameWeek(DateTime(2026, 9, 14), DateTime(2026, 9, 20)), isTrue);
    });

    test('Sunday and the next Monday are different weeks', () {
      expect(sameWeek(DateTime(2026, 9, 20), DateTime(2026, 9, 21)), isFalse);
    });
  });

  group('weeksAgo', () {
    test('zero returns the current week start', () {
      expect(weeksAgo(DateTime(2026, 9, 17), 0), DateTime(2026, 9, 14));
    });

    test('counts back across a month boundary', () {
      expect(weeksAgo(DateTime(2026, 9, 17), 3), DateTime(2026, 8, 24));
    });
  });

  group('isoDate', () {
    test('pads month and day', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('omits any time component', () {
      expect(isoDate(DateTime(2026, 9, 17, 14, 30)), '2026-09-17');
    });

    test('round-trips through parseIsoDate', () {
      final original = DateTime(2026, 9, 17);
      expect(parseIsoDate(isoDate(original)), original);
    });

    test('sorts lexicographically in date order', () {
      // This is what lets SQL BETWEEN work on the stored strings.
      final dates = [
        isoDate(DateTime(2026, 10, 1)),
        isoDate(DateTime(2026, 9, 30)),
        isoDate(DateTime(2027, 1, 1)),
      ]..sort();
      expect(dates, ['2026-09-30', '2026-10-01', '2027-01-01']);
    });
  });

  group('parseIsoDate', () {
    test('rejects a malformed string', () {
      expect(() => parseIsoDate('17/09/2026'), throwsFormatException);
    });

    test('rejects an ISO string carrying a time', () {
      expect(() => parseIsoDate('2026-09-17T00:00:00'), throwsFormatException);
    });
  });
}
