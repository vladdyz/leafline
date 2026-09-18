import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/util/money.dart';

void main() {
  group('parseAmountToCents', () {
    test('parses a whole number', () {
      expect(parseAmountToCents('12'), 1200);
    });

    test('parses two decimal places', () {
      expect(parseAmountToCents('12.40'), 1240);
    });

    test('pads a single decimal place', () {
      expect(parseAmountToCents('12.4'), 1240);
    });

    test('strips a currency symbol', () {
      expect(parseAmountToCents(r'$12.40'), 1240);
    });

    test('strips surrounding whitespace', () {
      expect(parseAmountToCents('  12.40  '), 1240);
    });

    test('handles a thousands separator', () {
      expect(parseAmountToCents('1,234.56'), 123456);
    });

    test('handles a decimal comma', () {
      expect(parseAmountToCents('12,40'), 1240);
    });

    test('handles European grouping with a decimal comma', () {
      expect(parseAmountToCents('1.234,56'), 123456);
    });

    test('parses zero', () {
      expect(parseAmountToCents('0'), 0);
    });

    test('parses a large amount', () {
      expect(parseAmountToCents('100000.00'), 10000000);
    });

    test('rejects an empty string', () {
      expect(parseAmountToCents(''), isNull);
    });

    test('rejects whitespace only', () {
      expect(parseAmountToCents('   '), isNull);
    });

    test('rejects letters', () {
      expect(parseAmountToCents('abc'), isNull);
    });

    test('rejects a bare currency symbol', () {
      expect(parseAmountToCents(r'$'), isNull);
    });

    test('rejects more than two decimal places', () {
      // Over-precise input usually means OCR picked up the wrong token.
      expect(parseAmountToCents('12.345'), isNull);
    });

    test('rejects a negative amount', () {
      // Expenses are positive by definition; a minus sign means a misread.
      expect(parseAmountToCents('-5.00'), isNull);
    });

    test('rejects a trailing decimal point', () {
      expect(parseAmountToCents('12.'), isNull);
    });
  });

  group('formatCents', () {
    test('formats a simple amount', () {
      expect(formatCents(1240), r'$12.40');
    });

    test('pads cents below ten', () {
      expect(formatCents(1204), r'$12.04');
    });

    test('formats zero', () {
      expect(formatCents(0), r'$0.00');
    });

    test('groups thousands', () {
      expect(formatCents(123456), r'$1,234.56');
    });

    test('groups millions', () {
      expect(formatCents(123456789), r'$1,234,567.89');
    });

    test('formats a negative amount', () {
      expect(formatCents(-1240), r'-$12.40');
    });

    test('omits the symbol when asked', () {
      expect(formatCents(1240, withSymbol: false), '12.40');
    });

    test('round-trips through parseAmountToCents', () {
      for (final cents in [0, 5, 99, 100, 1240, 123456, 10000000]) {
        expect(parseAmountToCents(formatCents(cents)), cents);
      }
    });
  });

  group('formatCentsCompact', () {
    test('drops zero cents', () {
      expect(formatCentsCompact(4000), r'$40');
    });

    test('keeps non-zero cents', () {
      expect(formatCentsCompact(4050), r'$40.50');
    });

    test('groups thousands', () {
      expect(formatCentsCompact(500000), r'$5,000');
    });
  });
}
