/// Week boundaries for the app. Weeks start Monday (ISO 8601).
///
/// Weeks are always derived, never stored. A `week` column in the database
/// would go stale the moment an expense's date is edited.
///
/// Every function here uses the `DateTime(y, m, d)` constructor rather than
/// `Duration` arithmetic. That matters: adding or subtracting a `Duration` of
/// days across a daylight-saving boundary shifts the wall-clock time by an
/// hour and can land on the wrong calendar day. The constructor normalises
/// out-of-range day values using calendar rules and always returns local
/// midnight, which is what "the start of a week" means to a user.
library;

/// The Monday at or before [date], at local midnight.
DateTime weekStart(DateTime date) {
  final offset = date.weekday - DateTime.monday;
  return DateTime(date.year, date.month, date.day - offset);
}

/// The Sunday at or after [date], at local midnight.
///
/// This is the last *day* of the week, not the last instant. For range
/// queries prefer [weekEndExclusive], which avoids off-by-one-second bugs.
DateTime weekEnd(DateTime date) {
  final start = weekStart(date);
  return DateTime(start.year, start.month, start.day + 6);
}

/// The Monday of the following week, at local midnight.
///
/// Use with a half-open interval: `start <= spentOn < endExclusive`.
DateTime weekEndExclusive(DateTime date) {
  final start = weekStart(date);
  return DateTime(start.year, start.month, start.day + 7);
}

/// True when [a] and [b] fall in the same Monday-started week.
bool sameWeek(DateTime a, DateTime b) => weekStart(a) == weekStart(b);

/// The Monday of the week [count] weeks before the week containing [date].
DateTime weeksAgo(DateTime date, int count) {
  final start = weekStart(date);
  return DateTime(start.year, start.month, start.day - (7 * count));
}

/// Formats a date as `YYYY-MM-DD`, the storage format for `expenses.spent_on`.
///
/// Deliberately not `toIso8601String()`, which appends a time component and
/// would break string comparison in SQL date-range queries.
String isoDate(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

/// Parses a `YYYY-MM-DD` string back into a local-midnight [DateTime].
///
/// Throws [FormatException] on anything else, rather than returning a
/// silently wrong date.
DateTime parseIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('Expected YYYY-MM-DD', value);
  }
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}
