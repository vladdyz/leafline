import 'package:receipt_tracker/models/ocr_block.dart';
import 'package:receipt_tracker/util/money.dart';

/// Ranks the amounts on a receipt by how likely each is to be the total.
///
/// This is a heuristic and it will be wrong sometimes. That is designed for
/// rather than apologised for: the UI offers the top few as tappable chips
/// instead of filling the field, so a wrong first guess costs one tap. The
/// bar is "the right answer is usually among the first three", not "the right
/// answer is always first".
///
/// Every weight below is a named constant so the scoring can be tuned in one
/// place, and every decision a candidate's score is made of is recorded on
/// the candidate itself — a heuristic you cannot inspect is one you cannot
/// improve.
class TotalExtractor {
  const TotalExtractor._();

  /// `TOTAL DUE`, `BALANCE DUE`, `GRAND TOTAL`. The least ambiguous labels a
  /// receipt offers.
  static const int scoreExplicitTotal = 5;

  /// A line mentioning "total" that is not a subtotal.
  static const int scoreTotal = 3;

  /// Subtotals are the classic wrong answer: they sit next to the total, look
  /// just like it, and are labelled with a word that contains it.
  static const int scoreSubtotal = -4;

  /// Tax lines. Small numbers, never the total.
  static const int scoreTax = -3;

  /// Cash tendered, change given, card lines. Tendered amounts are routinely
  /// larger than the total, which makes them the worst kind of decoy — they
  /// would otherwise win on the "largest value" signal.
  static const int scoreTender = -3;

  /// Tips and gratuity, which are usually written in by hand and often blank.
  static const int scoreTip = -3;

  /// Phone numbers, web addresses, store contact lines.
  ///
  /// These carry no money, and on a receipt header they sit exactly where a
  /// large number would look plausible.
  static const int scoreContactInfo = -4;

  /// Totals print near the bottom.
  static const int scoreLowOnReceipt = 1;

  /// The total is usually the largest number on a receipt — though not always,
  /// which is why this is worth one point and not five.
  static const int scoreLargest = 1;

  static final RegExp _amount = RegExp(r'\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2}');

  static final RegExp _explicitTotal = RegExp(
    r'\b(grand\s*total|total\s*due|amount\s*due|balance\s*due)\b',
    caseSensitive: false,
  );
  static final RegExp _subtotal = RegExp(
    r'\bsub[\s-]*total\b',
    caseSensitive: false,
  );
  static final RegExp _total = RegExp(r'\btotal\b', caseSensitive: false);
  static final RegExp _tax = RegExp(
    r'\b(tax|hst|gst|pst|qst|vat)\b',
    caseSensitive: false,
  );
  static final RegExp _tender = RegExp(
    r'\b(cash|change|tender(ed)?|visa|mastercard|amex|debit|credit|card|'
    r'interac|paid|payment)\b',
    caseSensitive: false,
  );
  static final RegExp _tip = RegExp(
    r'\b(tip|gratuity|service\s*charge)\b',
    caseSensitive: false,
  );
  static final RegExp _contact = RegExp(
    r'\b(tel|phone|fax|www)\b|\.(com|ca|net|org)\b',
    caseSensitive: false,
  );

  /// Ranked candidates, best first, at most [limit] of them.
  static List<AmountCandidate> extract(List<OcrBlock> blocks, {int limit = 3}) {
    final lines = groupIntoLines(blocks);
    if (lines.isEmpty) return <AmountCandidate>[];

    final contentTop = lines.first.top;
    final contentBottom = lines.last.bottom;
    final contentHeight = contentBottom - contentTop;
    // The bottom third. Guarded because a single-line receipt has no
    // meaningful geometry and dividing by its zero height would be a crash
    // rather than a missing bonus.
    final lowWaterMark = contentHeight <= 0
        ? contentBottom.toDouble()
        : contentTop + (contentHeight * 2 / 3);

    final found = <_Found>[];
    for (final line in lines) {
      for (final match in _amount.allMatches(line.text)) {
        final before = match.start > 0 ? line.text[match.start - 1] : '';
        final after = match.end < line.text.length ? line.text[match.end] : '';

        // A percentage is not money. `HST 13.00%` would otherwise contribute
        // a candidate that looks perfectly well formed.
        if (after == '%') continue;

        // Nor is a fragment of a longer dotted run. A phone number written
        // as `905.555.0143` contains `905.55`, which is shaped exactly like
        // money, lands in a receipt header where a large figure looks
        // plausible, and appears nowhere a human would look for it.
        //
        // Found in the wild on a real receipt: the top-ranked candidate was
        // an amount over $100 that was not printed anywhere on the paper.
        if (before == '.' || _isDigit(before)) continue;
        if (after == '.' || _isDigit(after)) continue;

        final cents = parseAmountToCents(match.group(0)!);
        if (cents == null || cents == 0) continue;
        found.add(_Found(cents: cents, line: line));
      }
    }
    if (found.isEmpty) return <AmountCandidate>[];

    final largest = found.map((f) => f.cents).reduce((a, b) => a > b ? a : b);

    final candidates = <AmountCandidate>[];
    for (final item in found) {
      final text = item.line.text;
      final reasons = <String>[];
      var score = 0;

      if (_explicitTotal.hasMatch(text)) {
        score += scoreExplicitTotal;
        reasons.add('explicit total label');
      } else if (_subtotal.hasMatch(text)) {
        score += scoreSubtotal;
        reasons.add('subtotal');
      } else if (_total.hasMatch(text)) {
        score += scoreTotal;
        reasons.add('total label');
      }

      if (_tax.hasMatch(text)) {
        score += scoreTax;
        reasons.add('tax line');
      }
      if (_tender.hasMatch(text)) {
        score += scoreTender;
        reasons.add('tender line');
      }
      if (_tip.hasMatch(text)) {
        score += scoreTip;
        reasons.add('tip line');
      }
      if (_contact.hasMatch(text)) {
        score += scoreContactInfo;
        reasons.add('contact line');
      }
      if (item.line.centerY >= lowWaterMark) {
        score += scoreLowOnReceipt;
        reasons.add('low on receipt');
      }
      if (item.cents == largest) {
        score += scoreLargest;
        reasons.add('largest amount');
      }

      candidates.add(
        AmountCandidate(
          cents: item.cents,
          sourceLine: text,
          score: score,
          reasons: reasons,
        ),
      );
    }

    // Keep the best-scoring instance of each distinct amount. A receipt that
    // prints its total twice should offer it once.
    final best = <int, AmountCandidate>{};
    for (final candidate in candidates) {
      final existing = best[candidate.cents];
      if (existing == null || candidate.score > existing.score) {
        best[candidate.cents] = candidate;
      }
    }

    final ranked = best.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        // Ties break toward the larger amount. Where the evidence is equal,
        // a receipt's total is more often the bigger of two numbers than the
        // smaller, and guessing high is the friendlier error: an amount that
        // is too large is obvious on sight, one that is too small is not.
        return byScore != 0 ? byScore : b.cents.compareTo(a.cents);
      });

    return ranked.take(limit).toList();
  }
}

/// One amount found on a receipt, with why it scored what it did.
class AmountCandidate {
  const AmountCandidate({
    required this.cents,
    required this.sourceLine,
    required this.score,
    required this.reasons,
  });

  final int cents;

  /// The whole line this amount came from, shown under the chip so the user
  /// can tell two similar amounts apart without reopening the photo.
  final String sourceLine;

  final int score;

  /// The signals that produced [score], in the order they were applied.
  /// Not shown in the UI; it is what makes a wrong guess diagnosable.
  final List<String> reasons;

  @override
  bool operator ==(Object other) =>
      other is AmountCandidate &&
      other.cents == cents &&
      other.sourceLine == sourceLine &&
      other.score == score;

  @override
  int get hashCode => Object.hash(cents, sourceLine, score);

  @override
  String toString() =>
      'AmountCandidate($cents, score $score, "${reasons.join(', ')}")';
}

bool _isDigit(String character) {
  if (character.isEmpty) return false;
  final code = character.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

class _Found {
  const _Found({required this.cents, required this.line});
  final int cents;
  final OcrLine line;
}
