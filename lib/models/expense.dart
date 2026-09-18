import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// A single logged expense.
///
/// Immutable. Every mutation goes through [copyWith], which is what lets the
/// repository treat an update as a whole-row replace and lets equality be a
/// simple field comparison.
///
/// Note what is *not* here: no week field. Weeks are derived from [spentOn]
/// via `weekStart`, because a stored week would go stale the moment a date is
/// edited.
class Expense {
  const Expense({
    required this.id,
    required this.amountCents,
    required this.spentOn,
    required this.createdAt,
    required this.updatedAt,
    this.merchant = '',
    this.category = ExpenseCategory.custom,
    this.note,
    this.photoFile,
    this.ocrRawText,
  }) : assert(amountCents >= 0, 'Expenses are never negative');

  /// Builds a new expense, stamping [createdAt] and [updatedAt] to now.
  ///
  /// [id] must be supplied by the caller rather than generated here, so this
  /// stays a pure function and tests can pin it.
  factory Expense.create({
    required String id,
    required int amountCents,
    required DateTime spentOn,
    String merchant = '',
    ExpenseCategory category = ExpenseCategory.custom,
    String? note,
    String? photoFile,
    String? ocrRawText,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    return Expense(
      id: id,
      amountCents: amountCents,
      // Normalised to local midnight: the time of day an expense was logged
      // is not information anyone wants, and keeping it would break equality
      // between two expenses on the same day.
      spentOn: DateTime(spentOn.year, spentOn.month, spentOn.day),
      merchant: merchant,
      category: category,
      note: note,
      photoFile: photoFile,
      ocrRawText: ocrRawText,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  /// Reconstructs an expense from a database row.
  factory Expense.fromMap(Map<String, Object?> map) {
    return Expense(
      id: map['id']! as String,
      amountCents: map['amount_cents']! as int,
      spentOn: parseIsoDate(map['spent_on']! as String),
      merchant: (map['merchant'] as String?) ?? '',
      category: ExpenseCategory.fromId(
        (map['category'] as String?) ?? ExpenseCategory.custom.id,
      ),
      note: map['note'] as String?,
      photoFile: map['photo_file'] as String?,
      ocrRawText: map['ocr_raw_text'] as String?,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  /// UUID v4, assigned once and never changed.
  final String id;

  /// Amount in integer cents. See `docs/decisions/0001-integer-cents.md`.
  final int amountCents;

  /// Where the money went. May be empty — a quick entry needs only an amount.
  final String merchant;

  /// The date the money was spent, at local midnight.
  final DateTime spentOn;

  /// Which habit this belongs to.
  final ExpenseCategory category;

  /// Free-text note. Null when unused, never empty string.
  final String? note;

  /// Filename of the receipt photo, or null.
  ///
  /// A filename, not a path — the documents directory moves across
  /// reinstalls. Null also means "photo expired under the retention policy",
  /// which is why the expense survives its own photo.
  final String? photoFile;

  /// Raw recognised text from the receipt, kept for debugging the extractor.
  final String? ocrRawText;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The Monday of the week this expense falls in.
  DateTime get week => weekStart(spentOn);

  /// True when a photo is attached and has not expired.
  bool get hasPhoto => photoFile != null;

  /// Serialises to a database row.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'amount_cents': amountCents,
      'merchant': merchant,
      'spent_on': isoDate(spentOn),
      'category': category.id,
      'note': note,
      'photo_file': photoFile,
      'ocr_raw_text': ocrRawText,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Returns a copy with the given fields replaced and [updatedAt] restamped.
  ///
  /// Nullable fields take a sentinel-free approach: pass `clearNote: true` to
  /// set a field back to null, since passing `null` is indistinguishable from
  /// omitting the argument.
  Expense copyWith({
    int? amountCents,
    String? merchant,
    DateTime? spentOn,
    ExpenseCategory? category,
    String? note,
    String? photoFile,
    String? ocrRawText,
    bool clearNote = false,
    bool clearPhoto = false,
    bool clearOcrText = false,
    DateTime? now,
  }) {
    return Expense(
      id: id,
      amountCents: amountCents ?? this.amountCents,
      merchant: merchant ?? this.merchant,
      spentOn: spentOn == null
          ? this.spentOn
          : DateTime(spentOn.year, spentOn.month, spentOn.day),
      category: category ?? this.category,
      note: clearNote ? null : (note ?? this.note),
      photoFile: clearPhoto ? null : (photoFile ?? this.photoFile),
      ocrRawText: clearOcrText ? null : (ocrRawText ?? this.ocrRawText),
      createdAt: createdAt,
      updatedAt: now ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Expense &&
        other.id == id &&
        other.amountCents == amountCents &&
        other.merchant == merchant &&
        other.spentOn == spentOn &&
        other.category == category &&
        other.note == note &&
        other.photoFile == photoFile &&
        other.ocrRawText == ocrRawText &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    amountCents,
    merchant,
    spentOn,
    category,
    note,
    photoFile,
    ocrRawText,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Expense($id, $amountCents, ${isoDate(spentOn)}, ${category.id})';
}
