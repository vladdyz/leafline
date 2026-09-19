/// Recognised text and where it sat on the receipt.
///
/// This is the shape the Kotlin side returns across the channel: text plus a
/// bounding box, and no interpretation. Deciding what any of it means happens
/// here in Dart. See `docs/decisions/0003-extraction-in-dart.md`.
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Rebuilds a block from the map the channel sends.
  ///
  /// Tolerant on purpose: a block with a missing or malformed box still
  /// carries usable text, and losing the whole receipt because one bounding
  /// box came back odd would be a poor trade.
  factory OcrBlock.fromChannel(Map<Object?, Object?> map) {
    int intOf(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.round();
      return 0;
    }

    return OcrBlock(
      text: (map['text'] as String?) ?? '',
      left: intOf('left'),
      top: intOf('top'),
      width: intOf('width'),
      height: intOf('height'),
    );
  }

  final String text;
  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  /// Vertical midpoint, used for deciding which blocks share a line.
  double get centerY => top + (height / 2);

  @override
  String toString() => 'OcrBlock("$text", $left,$top ${width}x$height)';
}

/// Blocks that sit on the same visual line, left to right.
///
/// This exists because of how recognisers actually behave. A receipt line
/// reading `TOTAL          7.06` is usually returned as two separate blocks,
/// because the gap between label and amount is wide enough to split them.
/// Scoring the raw blocks would therefore see a block saying `TOTAL` with no
/// number in it, and a block saying `7.06` with no context — and the single
/// most useful signal on the whole receipt would be invisible.
class OcrLine {
  OcrLine(this.blocks)
    : assert(blocks.isNotEmpty, 'A line needs at least one block');

  final List<OcrBlock> blocks;

  /// The line's text, blocks joined left to right by a single space.
  String get text => blocks.map((b) => b.text.trim()).join(' ').trim();

  int get top => blocks.map((b) => b.top).reduce((a, b) => a < b ? a : b);
  int get bottom => blocks.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);

  double get centerY => (top + bottom) / 2;

  @override
  String toString() => 'OcrLine("$text")';
}

/// Groups blocks into visual lines by vertical overlap.
///
/// Two blocks share a line when their vertical extents overlap by more than
/// [overlapThreshold] of the shorter one. Overlap is used rather than a fixed
/// pixel tolerance because text size varies across a receipt — a large TOTAL
/// next to a small amount should still group, and a fixed tolerance tuned for
/// one font size is wrong for the other.
List<OcrLine> groupIntoLines(
  List<OcrBlock> blocks, {
  double overlapThreshold = 0.4,
}) {
  if (blocks.isEmpty) return <OcrLine>[];

  final sorted = <OcrBlock>[...blocks]
    ..sort((a, b) => a.centerY.compareTo(b.centerY));

  final lines = <List<OcrBlock>>[];
  for (final block in sorted) {
    final current = lines.isEmpty ? null : lines.last;
    if (current != null && _sharesLine(current, block, overlapThreshold)) {
      current.add(block);
    } else {
      lines.add(<OcrBlock>[block]);
    }
  }

  return <OcrLine>[
    for (final line in lines)
      OcrLine(<OcrBlock>[...line]..sort((a, b) => a.left.compareTo(b.left))),
  ];
}

bool _sharesLine(List<OcrBlock> line, OcrBlock candidate, double threshold) {
  final top = line.map((b) => b.top).reduce((a, b) => a < b ? a : b);
  final bottom = line.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);

  final overlap =
      (bottom < candidate.bottom ? bottom : candidate.bottom) -
      (top > candidate.top ? top : candidate.top);
  if (overlap <= 0) return false;

  final shorter = (bottom - top) < candidate.height
      ? (bottom - top)
      : candidate.height;
  if (shorter <= 0) return false;

  return overlap / shorter >= threshold;
}
