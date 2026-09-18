/// The weekly budget. Exactly one of these exists.
///
/// Modelled as a row rather than a preference so that per-category budgets
/// (deferred) can extend the table without a migration away from
/// `SharedPreferences`.
class Budget {
  const Budget({required this.weeklyCents, required this.updatedAt})
    : assert(weeklyCents >= 0, 'A budget is never negative');

  /// The state before a user has set anything. Zero means "no budget", which
  /// `budgetStateFor` treats as always-under rather than always-over.
  factory Budget.unset({DateTime? now}) =>
      Budget(weeklyCents: 0, updatedAt: now ?? DateTime.now());

  factory Budget.fromMap(Map<String, Object?> map) {
    return Budget(
      weeklyCents: map['weekly_cents']! as int,
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  /// The single row's primary key. Constrained to 1 by the schema.
  static const int singletonId = 1;

  final int weeklyCents;
  final DateTime updatedAt;

  /// True once the user has actually chosen an amount.
  bool get isSet => weeklyCents > 0;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': singletonId,
      'weekly_cents': weeklyCents,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Budget copyWith({int? weeklyCents, DateTime? now}) {
    return Budget(
      weeklyCents: weeklyCents ?? this.weeklyCents,
      updatedAt: now ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Budget &&
        other.weeklyCents == weeklyCents &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(weeklyCents, updatedAt);

  @override
  String toString() => 'Budget($weeklyCents)';
}
