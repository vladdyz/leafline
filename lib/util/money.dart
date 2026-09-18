/// Money handling. Amounts are integer cents everywhere in the app.
///
/// No `double`, ever. Floating point produces totals that are off by a cent
/// and impossible to explain to the person looking at them. Parse at the
/// input edge, format at the display edge, and keep `int` in between.
library;

/// Parses user- or OCR-supplied text into cents.
///
/// Returns `null` for anything it cannot read confidently, which the caller
/// should treat as "ask the user" rather than guessing.
///
/// Handles: `12`, `12.4`, `12.40`, `$12.40`, `1,234.56`, `12,40`,
/// and surrounding whitespace. Rejects: empty strings, negatives, letters,
/// and more than two decimal places.
///
/// The comma is ambiguous — `12,40` is a decimal comma while `1,234` is a
/// thousands separator. The rule used here is that a comma followed by
/// exactly two digits at the end of the string is decimal; anything else is
/// a group separator. Thousands separators always precede three digits, so
/// the two cases do not overlap.
int? parseAmountToCents(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;

  // Strip currency symbols and internal whitespace.
  s = s.replaceAll(RegExp(r'[$\s\u00A0]'), '');
  if (s.isEmpty) return null;

  final decimalComma = RegExp(r'^\d{1,3}(\.\d{3})*,\d{2}$');
  if (decimalComma.hasMatch(s)) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else {
    s = s.replaceAll(',', '');
  }

  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;

  final parts = s.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null) return null;

  var cents = 0;
  if (parts.length == 2) {
    final frac = int.tryParse(parts[1].padRight(2, '0'));
    if (frac == null) return null;
    cents = frac;
  }

  return whole * 100 + cents;
}

/// Renders cents as a display string, e.g. `1234056` becomes `$12,340.56`.
String formatCents(int cents, {bool withSymbol = true}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = _group(abs ~/ 100);
  final frac = (abs % 100).toString().padLeft(2, '0');
  final symbol = withSymbol ? r'$' : '';
  return '${negative ? '-' : ''}$symbol$whole.$frac';
}

/// Renders cents without cents when they are zero, e.g. `$40` not `$40.00`.
///
/// Used in tight spaces such as the budget bar label and the home screen
/// widget, where the decimals cost more room than they convey.
String formatCentsCompact(int cents) {
  if (cents % 100 == 0) {
    final negative = cents < 0;
    return '${negative ? '-' : ''}\$${_group(cents.abs() ~/ 100)}';
  }
  return formatCents(cents);
}

String _group(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
