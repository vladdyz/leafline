import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/models/ocr_block.dart';
import 'package:receipt_tracker/services/ocr_service.dart';
import 'package:receipt_tracker/services/total_extractor.dart';

import '../fixtures/receipts.dart';

void main() {
  group('groupIntoLines', () {
    test('an empty list produces no lines', () {
      expect(groupIntoLines(<OcrBlock>[]), isEmpty);
    });

    test('rejoins a label and an amount split across two blocks', () {
      // The case the whole OcrLine abstraction exists for. Recognisers split
      // `TOTAL          7.06` because the gap is wide, and scoring the raw
      // blocks would see a label with no number and a number with no label.
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(
          text: 'TOTAL',
          left: 40,
          top: 350,
          width: 90,
          height: 30,
        ),
        const OcrBlock(
          text: '7.06',
          left: 300,
          top: 352,
          width: 60,
          height: 28,
        ),
      ]);

      expect(lines, hasLength(1));
      expect(lines.single.text, 'TOTAL 7.06');
    });

    test('orders blocks within a line left to right', () {
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(
          text: '7.06',
          left: 300,
          top: 350,
          width: 60,
          height: 30,
        ),
        const OcrBlock(
          text: 'TOTAL',
          left: 40,
          top: 350,
          width: 90,
          height: 30,
        ),
      ]);
      expect(lines.single.text, 'TOTAL 7.06');
    });

    test('keeps separate lines separate', () {
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(text: 'A', left: 40, top: 100, width: 50, height: 30),
        const OcrBlock(text: 'B', left: 40, top: 200, width: 50, height: 30),
      ]);
      expect(lines, hasLength(2));
    });

    test('groups by overlap, so differing text sizes still pair', () {
      // A large TOTAL beside a smaller amount. A fixed pixel tolerance tuned
      // for one size would be wrong for the other.
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(
          text: 'TOTAL',
          left: 40,
          top: 340,
          width: 120,
          height: 48,
        ),
        const OcrBlock(
          text: '7.06',
          left: 300,
          top: 355,
          width: 60,
          height: 20,
        ),
      ]);
      expect(lines, hasLength(1));
    });

    test('orders lines top to bottom regardless of input order', () {
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(text: 'LAST', left: 40, top: 300, width: 50, height: 30),
        const OcrBlock(
          text: 'FIRST',
          left: 40,
          top: 100,
          width: 50,
          height: 30,
        ),
      ]);
      expect(lines.map((l) => l.text).toList(), <String>['FIRST', 'LAST']);
    });

    test('barely-touching blocks do not group', () {
      final lines = groupIntoLines(<OcrBlock>[
        const OcrBlock(text: 'A', left: 40, top: 100, width: 50, height: 30),
        const OcrBlock(text: 'B', left: 40, top: 128, width: 50, height: 30),
      ]);
      expect(lines, hasLength(2));
    });
  });

  group('TotalExtractor against real receipt shapes', () {
    for (final fixture in receiptFixtures) {
      test(fixture.name, () {
        final candidates = TotalExtractor.extract(fixture.blocks());
        expect(
          candidates,
          isNotEmpty,
          reason: 'no candidates at all for ${fixture.name}',
        );

        final rank =
            candidates.indexWhere((c) => c.cents == fixture.expectedCents) + 1;
        expect(
          rank,
          greaterThan(0),
          reason:
              '${fixture.expectedCents} was not offered. Got '
              '${candidates.map((c) => c.cents).toList()}',
        );
        expect(
          rank,
          lessThanOrEqualTo(fixture.expectedRank),
          reason:
              '${fixture.expectedCents} ranked $rank, expected at most '
              '${fixture.expectedRank}. Scores: $candidates',
        );
      });
    }
  });

  group('TotalExtractor scoring', () {
    List<AmountCandidate> extractLines(List<String> lines) {
      var y = 30;
      final blocks = <OcrBlock>[];
      for (final line in lines) {
        blocks.add(
          OcrBlock(text: line, left: 40, top: y, width: 400, height: 30),
        );
        y += 40;
      }
      return TotalExtractor.extract(blocks);
    }

    test('an explicit total label outranks a bare total', () {
      final result = extractLines(<String>[
        'TOTAL         10.00',
        'AMOUNT DUE    12.00',
      ]);
      expect(result.first.cents, 1200);
    });

    test('a subtotal loses to the total below it', () {
      final result = extractLines(<String>[
        'SUBTOTAL      10.00',
        'TOTAL         11.30',
      ]);
      expect(result.first.cents, 1130);
    });

    test('a tendered amount larger than the total still loses', () {
      final result = extractLines(<String>[
        'TOTAL         18.99',
        'CASH          50.00',
      ]);
      expect(result.first.cents, 1899);
    });

    test('percentages are not amounts', () {
      final result = extractLines(<String>['HST 13.00%     2.60']);
      expect(result.map((c) => c.cents), isNot(contains(1300)));
      expect(result.map((c) => c.cents), contains(260));
    });

    test('a dotted phone number yields no amounts at all', () {
      // The bug this guard exists for. `905.555.0143` contains `905.55`,
      // which parses cleanly and is nowhere on the receipt.
      expect(extractLines(<String>['TEL 905.555.0143']), isEmpty);
    });

    test('a toll-free number yields no amounts', () {
      expect(extractLines(<String>['1.800.555.1234']), isEmpty);
    });

    test('an amount touching a digit on either side is rejected', () {
      expect(extractLines(<String>['416.555.9876']), isEmpty);
    });

    test('a real amount beside a phone number still parses', () {
      final result = extractLines(<String>[
        'TEL 905.555.0143',
        'TOTAL            21.00',
      ]);
      expect(result.map((c) => c.cents), <int>[2100]);
    });

    test('a contact line is penalised even if it holds an amount', () {
      final result = extractLines(<String>[
        'WWW.SHOP.COM      99.00',
        'TOTAL             21.00',
      ]);
      expect(result.first.cents, 2100);
    });

    test('zero amounts are dropped', () {
      // An unwritten tip line is not a candidate.
      final result = extractLines(<String>[
        'TIP            0.00',
        'TOTAL         20.00',
      ]);
      expect(result.map((c) => c.cents), isNot(contains(0)));
    });

    test('thousands separators parse', () {
      final result = extractLines(<String>['TOTAL      1,284.50']);
      expect(result.first.cents, 128450);
    });

    test('the same amount is offered once', () {
      final result = extractLines(<String>[
        'TOTAL         22.99',
        'DEBIT         22.99',
      ]);
      expect(result.where((c) => c.cents == 2299), hasLength(1));
    });

    test('a duplicated amount keeps its best-scoring context', () {
      // The tender penalty must not follow an amount that also appears on a
      // total line.
      final result = extractLines(<String>[
        'TOTAL         22.99',
        'DEBIT         22.99',
      ]);
      final candidate = result.firstWhere((c) => c.cents == 2299);
      expect(candidate.reasons, contains('total label'));
      expect(candidate.reasons, isNot(contains('tender line')));
    });

    test('candidates carry why they scored what they did', () {
      final result = extractLines(<String>['TOTAL          7.06']);
      expect(result.first.reasons, isNotEmpty);
      expect(result.first.sourceLine, contains('TOTAL'));
    });

    test('returns at most the requested number', () {
      final blocks = <OcrBlock>[];
      var y = 30;
      for (var i = 1; i <= 8; i++) {
        blocks.add(
          OcrBlock(
            text: 'ITEM $i        $i.00',
            left: 40,
            top: y,
            width: 400,
            height: 30,
          ),
        );
        y += 40;
      }
      expect(TotalExtractor.extract(blocks, limit: 3), hasLength(3));
    });

    test('no amounts means no candidates', () {
      final result = extractLines(<String>['THANK YOU', 'CALL AGAIN']);
      expect(result, isEmpty);
    });

    test('no blocks means no candidates', () {
      expect(TotalExtractor.extract(<OcrBlock>[]), isEmpty);
    });

    test('a single line does not divide by zero on geometry', () {
      final result = TotalExtractor.extract(<OcrBlock>[
        const OcrBlock(
          text: 'TOTAL 5.00',
          left: 0,
          top: 0,
          width: 100,
          height: 0,
        ),
      ]);
      expect(result.first.cents, 500);
    });
  });

  group('OcrService implementations', () {
    test('the unavailable service reports so and returns nothing', () async {
      const service = UnavailableOcrService();
      expect(service.isAvailable, isFalse);
      expect(await service.recognize('anything.jpg'), isEmpty);
    });

    test('the stub returns a receipt regardless of path', () async {
      const service = StubOcrService();
      expect(service.isAvailable, isTrue);
      expect(await service.recognize('nonexistent.jpg'), isNotEmpty);
    });

    test('the stub receipt ranks its own total first', () async {
      // Mirrors the Kotlin stub, so a green result here means the Dart half
      // of the pipeline is correct before a channel exists.
      const service = StubOcrService();
      final blocks = await service.recognize('x.jpg');
      final candidates = TotalExtractor.extract(blocks);
      expect(candidates.first.cents, 706);
    });
  });

  group('OcrBlock.fromChannel', () {
    test('reads a well-formed map', () {
      final block = OcrBlock.fromChannel(<Object?, Object?>{
        'text': 'TOTAL 7.06',
        'left': 40,
        'top': 350,
        'width': 400,
        'height': 34,
      });
      expect(block.text, 'TOTAL 7.06');
      expect(block.bottom, 384);
    });

    test('survives a missing bounding box', () {
      // Text with no geometry is still worth having; losing the receipt over
      // one odd box would be a poor trade.
      final block = OcrBlock.fromChannel(<Object?, Object?>{
        'text': 'TOTAL 7.06',
      });
      expect(block.text, 'TOTAL 7.06');
      expect(block.top, 0);
    });

    test('accepts doubles where ints are expected', () {
      final block = OcrBlock.fromChannel(<Object?, Object?>{
        'text': 'x',
        'left': 40.7,
        'top': 350.2,
        'width': 400.0,
        'height': 34.0,
      });
      expect(block.left, 41);
      expect(block.top, 350);
    });
  });

  group('OcrFailure', () {
    test('maps every channel error code', () {
      expect(
        OcrFailure.fromCode('FILE_NOT_FOUND').kind,
        OcrFailureKind.fileNotFound,
      );
      expect(
        OcrFailure.fromCode('DECODE_FAILED').kind,
        OcrFailureKind.decodeFailed,
      );
      expect(
        OcrFailure.fromCode('RECOGNITION_FAILED').kind,
        OcrFailureKind.recognitionFailed,
      );
      expect(OcrFailure.fromCode('SOMETHING_NEW').kind, OcrFailureKind.unknown);
      expect(OcrFailure.fromCode(null).kind, OcrFailureKind.unknown);
    });
  });
}
