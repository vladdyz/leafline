/// How long receipt photos are kept.
///
/// Photos expire; expenses do not. Everything here concerns files on disk —
/// the amount, the date, the category and the recognised text of an expense
/// are permanent regardless of which option is chosen. See decision 0006.
enum PhotoRetention {
  oneMonth('one_month', 'One month', 1),
  threeMonths('three_months', 'Three months', 3),
  oneYear('one_year', 'One year', 12),
  forever('forever', 'Keep forever', null);

  const PhotoRetention(this.id, this.label, this.months);

  /// Stored in the settings table. Never change these strings without a
  /// migration; change [label] instead.
  final String id;

  /// Shown in Settings.
  final String label;

  /// Null means never expire.
  final int? months;

  /// The default for a new install.
  ///
  /// Three months is long enough that a photo is still there when you go
  /// looking for it, and short enough that the library does not quietly grow
  /// past the point where Android starts suggesting the user clear app data —
  /// which would take the database with it.
  static const PhotoRetention fallback = PhotoRetention.threeMonths;

  /// Photos for expenses dated before this are removed. Null for [forever].
  ///
  /// Calendar arithmetic, not a multiple of 30 days. "Three months ago" means
  /// the same day three months back, which is what a user picking "three
  /// months" means — and `DateTime` normalises a negative month for free, so
  /// January minus three is October of the previous year.
  DateTime? cutoffFrom(DateTime now) {
    final back = months;
    if (back == null) return null;
    return DateTime(now.year, now.month - back, now.day);
  }

  /// Looks up by stored id, falling back to [fallback] for anything
  /// unrecognised — a value written by a future version still resolves to
  /// something sensible rather than crashing on read.
  static PhotoRetention fromId(String? id) {
    for (final option in PhotoRetention.values) {
      if (option.id == id) return option;
    }
    return fallback;
  }
}
