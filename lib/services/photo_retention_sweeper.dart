import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/image_store.dart';
import 'package:receipt_tracker/models/photo_retention.dart';

/// Removes receipt photos that have outlived the retention window.
///
/// The expenses themselves are never touched. An expense whose photo has
/// expired keeps its amount, its date, its category and its recognised text —
/// only `photo_file` becomes null, and the tile renders a placeholder. See
/// decision 0006.
class PhotoRetentionSweeper {
  // Public fields rather than private ones with an initialiser list.
  //
  // `prefer_initializing_formals` wants `required this._expenses`, which is
  // not legal: a named parameter cannot begin with an underscore. Chasing the
  // lint therefore produced a second error, and silencing it with an ignore
  // comment left a rule fighting the language. Nothing here needed to be
  // private in the first place.
  const PhotoRetentionSweeper({required this.expenses, required this.store});

  final ExpenseRepository expenses;
  final ImageStore store;

  /// Expires photos older than [retention] as of [now]. Returns how many.
  ///
  /// The order is the whole design:
  ///
  /// 1. read the filenames, while rows still point at them
  /// 2. null the rows
  /// 3. delete the files
  ///
  /// Reversing 2 and 3 would leave a window where a row points at a file that
  /// is already gone — which renders as a broken photo rather than as no
  /// photo. Dying between them instead leaves files nobody references, and
  /// the orphan sweep at startup collects those. One failure mode is
  /// recoverable and the other is not, so the recoverable one is chosen.
  Future<int> sweep({
    required PhotoRetention retention,
    required DateTime now,
  }) async {
    final cutoff = retention.cutoffFrom(now);
    if (cutoff == null) return 0;

    final expiring = await expenses.photoFilesOlderThan(cutoff);
    if (expiring.isEmpty) return 0;

    await expenses.clearPhotosOlderThan(cutoff);

    for (final filename in expiring) {
      await store.delete(filename);
    }
    return expiring.length;
  }
}
