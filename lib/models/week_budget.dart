import 'package:receipt_tracker/util/week_math.dart';

/// The budget that applied to one specific week.
///
/// The existence of this row is what makes a week *tracked*. That is the
/// central idea of the week model, and it is worth stating plainly because
/// everything else follows from it:
///
/// - A week with a row and no expenses is a tracked week where nothing was
///   spent — the best possible outcome, and it renders as such.
/// - A week with no row was never tracked. It is not a success and not a
///   failure; the app simply was not in use. It renders as neither.
///
/// Deriving "does this week exist" from expenses instead would invert both:
/// a perfect week would vanish, and every week since the dawn of the calendar
/// would look identical to one the user never saw.
class WeekBudget {
  const WeekBudget({
    required this.weekStart,
    required this.budgetCents,
    required this.createdAt,
    required this.updatedAt,
    this.isOverride = false,
  }) : assert(budgetCents >= 0, 'A budget is never negative');

  factory WeekBudget.fromMap(Map<String, Object?> map) {
    return WeekBudget(
      weekStart: parseIsoDate(map['week_start']! as String),
      budgetCents: map['budget_cents']! as int,
      isOverride: (map['is_override']! as int) == 1,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  /// The Monday of the week, at local midnight. Primary key.
  final DateTime weekStart;

  /// The budget in cents, frozen for this week.
  final int budgetCents;

  /// Whether the user set this week's budget deliberately.
  ///
  /// `false` means the week inherited the standing default when it was
  /// created. While such a week is still in progress it keeps following the
  /// default, so changing the default mid-week updates it. Once the week is
  /// over, nothing touches it again.
  ///
  /// `true` means the user chose a figure for this week specifically — the
  /// vacation-week case. The default never overwrites it, in progress or not.
  final bool isOverride;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The Sunday of this week.
  DateTime get weekEndDate => weekEnd(weekStart);

  /// Whether a budget figure was actually set, as opposed to zero.
  bool get hasBudget => budgetCents > 0;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'week_start': isoDate(weekStart),
      'budget_cents': budgetCents,
      'is_override': isOverride ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WeekBudget copyWith({int? budgetCents, bool? isOverride, DateTime? now}) {
    return WeekBudget(
      weekStart: weekStart,
      budgetCents: budgetCents ?? this.budgetCents,
      isOverride: isOverride ?? this.isOverride,
      createdAt: createdAt,
      updatedAt: now ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeekBudget &&
        other.weekStart == weekStart &&
        other.budgetCents == budgetCents &&
        other.isOverride == isOverride &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(weekStart, budgetCents, isOverride, createdAt, updatedAt);

  @override
  String toString() =>
      'WeekBudget(${isoDate(weekStart)}, $budgetCents, '
      'override: $isOverride)';
}
