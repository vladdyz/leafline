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
  const PhotoRetentionSweeper({
    required ExpenseRepository expenses,
    required ImageStore store,
  // ignore: prefer_initializing_formals
  }) : _expenses = expenses,
       // ignore: prefer_initializing_formals
       _store = store;

  final ExpenseRepository _expenses;
  final ImageStore _store;

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

    final expiring = await _expenses.photoFilesOlderThan(cutoff);
    if (expiring.isEmpty) return 0;

    await _expenses.clearPhotosOlderThan(cutoff);

    for (final filename in expiring) {
      await _store.delete(filename);
    }
    return expiring.length;
  }
}
