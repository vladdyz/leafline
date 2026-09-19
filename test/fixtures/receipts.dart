import 'package:receipt_tracker/models/ocr_block.dart';

/// Receipt fixtures for the extractor.
///
/// These are the regression suite. Every receipt that fools the extractor in
/// real use should be added here with its correct total — the heuristic then
/// gets measurably better precisely when it fails, which is the right feedback
/// loop for something that will never be perfect.
///
/// To add one: photograph the receipt, log `ocrRawText` from the saved
/// expense, and paste the lines in.
class ReceiptFixture {
  const ReceiptFixture({
    required this.name,
    required this.lines,
    required this.expectedCents,
    this.expectedRank = 1,
    this.note,
  });

  final String name;

  /// Plain text lines, top to bottom. [blocks] lays them out.
  final List<String> lines;

  /// The amount a human would say is the total.
  final int expectedCents;

  /// Where the extractor is expected to rank it. 1 for every receipt it
  /// should get right; higher where the fixture documents a known limit
  /// rather than a requirement.
  final int expectedRank;

  final String? note;

  /// Lays the lines out as blocks, evenly spaced down a receipt.
  ///
  /// The geometry is synthetic but the proportions are what matter: the
  /// extractor only asks whether a line sits in the bottom third.
  List<OcrBlock> blocks({int lineHeight = 30, int gap = 10, int start = 30}) {
    final result = <OcrBlock>[];
    var y = start;
    for (final line in lines) {
      result.add(
        OcrBlock(text: line, left: 40, top: y, width: 400, height: lineHeight),
      );
      y += lineHeight + gap;
    }
    return result;
  }
}

const List<ReceiptFixture> receiptFixtures = <ReceiptFixture>[
  ReceiptFixture(
    name: 'corner market',
    expectedCents: 706,
    lines: <String>[
      'CORNER MARKET',
      '123 QUEEN ST W',
      'COFFEE LARGE      2.75',
      'BAGEL             3.50',
      'SUBTOTAL          6.25',
      'HST 13%           0.81',
      'TOTAL             7.06',
      'CASH             10.00',
      'CHANGE            2.94',
    ],
    note:
        'Cash tendered is larger than the total, and sits lower on the '
        'receipt. Both signals favour it; the tender penalty has to outweigh '
        'them.',
  ),
  ReceiptFixture(
    name: 'restaurant with a tip line',
    expectedCents: 6355,
    lines: <String>[
      'THE BLUE FOX',
      'TABLE 12',
      '2 MAINS          44.00',
      '1 DESSERT         9.00',
      'SUBTOTAL         53.00',
      'HST              10.55',
      'TIP               0.00',
      'TOTAL            63.55',
      r'VISA ****4417    63.55',
      'APPROVED',
    ],
    note:
        'The total is printed twice, once on a card line. Deduplicating by '
        'amount keeps the better-scoring context.',
  ),
  ReceiptFixture(
    name: 'gas station, total only',
    expectedCents: 6812,
    lines: <String>[
      'PETRO STOP',
      'PUMP 4',
      'REGULAR 41.29L',
      'TOTAL            68.12',
      'DEBIT            68.12',
    ],
    note:
        '41.29L is a volume, not money, but it parses like money. It has to '
        'lose on context alone.',
  ),
  ReceiptFixture(
    name: 'grocery with balance due',
    expectedCents: 12447,
    lines: <String>[
      'FRESHMART',
      'MILK 2L           4.99',
      'BREAD             3.49',
      'EGGS 12           6.29',
      'CHICKEN          18.75',
      'PRODUCE          62.10',
      'SUBTOTAL        110.15',
      'GST               5.51',
      'PST               8.81',
      'BALANCE DUE     124.47',
      'MASTERCARD      124.47',
    ],
    note: 'No line says "total" at all.',
  ),
  ReceiptFixture(
    name: 'cash tendered far above the total',
    expectedCents: 1899,
    lines: <String>[
      'QUICK MART',
      'SNACKS            8.99',
      'DRINK             5.50',
      'CHIPS             4.50',
      'TOTAL            18.99',
      'CASH             50.00',
      'CHANGE           31.01',
    ],
    note: 'The two largest amounts on the receipt are both decoys.',
  ),
  ReceiptFixture(
    name: 'parking, amount due',
    expectedCents: 4200,
    lines: <String>[
      'CITY PARKING',
      'LOT 7',
      '3 HOURS',
      'AMOUNT DUE       42.00',
    ],
    note: 'Only one amount on the whole receipt.',
  ),
  ReceiptFixture(
    name: 'tax rate written with decimals',
    expectedCents: 2260,
    lines: <String>[
      'CAFE NORD',
      'LATTE             5.75',
      'SANDWICH         14.25',
      'SUBTOTAL         20.00',
      'HST 13.00%        2.60',
      'TOTAL            22.60',
    ],
    note: '13.00% parses as money unless percentages are excluded.',
  ),
  ReceiptFixture(
    name: 'no total label anywhere',
    expectedCents: 1550,
    lines: <String>[
      'FARM STAND',
      'TOMATOES          4.50',
      'PEPPERS           5.00',
      'HONEY             6.00',
      '15.50',
    ],
    note:
        'A hand-written stall receipt. Nothing labels the total, so it wins '
        'only on position and magnitude — the weakest evidence the extractor '
        'has. Worth keeping as a fixture precisely because it is fragile.',
  ),
  ReceiptFixture(
    name: 'merchant name contains the word total',
    expectedCents: 2299,
    lines: <String>[
      'TOTAL WINE & MORE',
      'STORE 112',
      'RED BLEND        22.99',
      'DEBIT            22.99',
    ],
    note:
        'The header would score highly if it carried an amount. It does not, '
        'so it never becomes a candidate — which is luck rather than design, '
        'and would stop working on a receipt that printed a number beside its '
        'logo.',
  ),
];
