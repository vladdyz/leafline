import 'dart:io';

import 'package:receipt_tracker/data/image_store.dart';

/// An [ImageStore] that keeps bytes in a map.
///
/// Every method completes without touching the disk, which is the point.
/// `testWidgets` runs inside a fake clock and real `dart:io` writes complete
/// on the event loop that clock never pumps — so a widget test saving a photo
/// through the real store waits forever on a future that cannot resolve.
///
/// `fileFor` returns a path that will never exist, so a `ReceiptThumbnail`
/// backed by this store renders its placeholder rather than an image. That is
/// fine: the widget tests assert that the thumbnail is *present*, not that it
/// painted pixels. Verifying the image itself is a job for the device.
class InMemoryImageStore implements ImageStore {
  final Map<String, List<int>> _files = <String, List<int>>{};

  /// When each file was written, so the grace period can be exercised without
  /// touching a real clock or a real disk.
  final Map<String, DateTime> _writtenAt = <String, DateTime>{};

  /// Overrides the write time of the next [save]. Lets a test place a file in
  /// the past without waiting an hour.
  DateTime? nextWriteTime;

  /// Where [fileFor] pretends the photos are. Nothing is ever written here.
  static const String fakeRoot = '/in-memory-receipts';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<String> save(String id, List<int> bytes) async {
    final filename = '$id${ImageStore.extension}';
    _files[filename] = List<int>.from(bytes);
    _writtenAt[filename] = nextWriteTime ?? DateTime.now();
    return filename;
  }

  @override
  File fileFor(String filename) => File('$fakeRoot/$filename');

  @override
  bool exists(String filename) => _files.containsKey(filename);

  @override
  Future<void> delete(String filename) async {
    _files.remove(filename);
    _writtenAt.remove(filename);
  }

  @override
  Future<Set<String>> listFilenames() async => _files.keys.toSet();

  @override
  Future<Set<String>> orphans(Set<String> referenced, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(
      ImageStore.orphanGracePeriod,
    );
    return <String>{
      for (final filename in _files.keys.toSet().difference(referenced))
        if ((_writtenAt[filename] ?? DateTime(0)).isBefore(cutoff)) filename,
    };
  }

  @override
  Future<int> sweepOrphans(Set<String> referenced, {DateTime? now}) async {
    final toDelete = await orphans(referenced, now: now);
    for (final filename in toDelete) {
      _files.remove(filename);
      _writtenAt.remove(filename);
    }
    return toDelete.length;
  }

  @override
  Future<int> totalBytes() async {
    // A loop, not a fold. In an `async =>` body the expected type of the
    // expression is `FutureOr<int>`, so bare `fold` infers
    // `fold<FutureOr<int>>`, `sum` arrives as `FutureOr<int>`, and that has no
    // `+`. `fold<int>` also works, but a one-liner needing a paragraph to
    // explain is worth less than four obvious lines in a test helper.
    //
    // This regressed once already: it was fixed, and then an overlay built
    // from an older copy of this file brought the broken version back.
    var total = 0;
    for (final bytes in _files.values) {
      total += bytes.length;
    }
    return total;
  }

  @override
  Future<int> count() async => _files.length;
}
