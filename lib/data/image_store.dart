import 'dart:io';

/// Stores receipt photos.
///
/// An interface for the same reason `PhotoSource` and `OcrService` are: it is
/// a platform boundary. Real `dart:io` writes complete on the event loop,
/// which the widget-test binding's fake clock never pumps — so any widget
/// test that saves a photo would sit waiting for a future that cannot
/// resolve, and `pumpAndSettle` would time out with nothing useful to say.
///
/// Tests substitute an in-memory implementation and the timing question
/// disappears, rather than being managed with `runAsync` windows tuned to a
/// wall clock that differs between a laptop and a CI runner.
abstract interface class ImageStore {
  /// Extension every stored photo carries.
  static const String extension = '.jpg';

  /// Creates the backing location if it does not exist.
  Future<void> ensureReady();

  /// Writes [bytes] under [id] and returns the filename to store on the row.
  Future<String> save(String id, List<int> bytes);

  /// Resolves a stored filename to a file handle.
  ///
  /// Does not check existence — a missing file is an expected state after
  /// retention expiry, not an error.
  File fileFor(String filename);

  /// Whether a stored photo is still present.
  bool exists(String filename);

  /// Deletes a stored photo. A file that is already gone is not an error.
  Future<void> delete(String filename);

  /// Every stored photo filename.
  Future<Set<String>> listFilenames();

  /// How long a file is protected from the orphan sweep after being written.
  ///
  /// A photo is written when it is taken, before the expense row exists, so
  /// between the shutter and the save it is genuinely an orphan. The sweep
  /// was only ever meant to run at launch, where no form can be open — but
  /// an assumption about when code runs is not a guarantee, and this one
  /// turned out to be false.
  static const Duration orphanGracePeriod = Duration(hours: 1);

  /// Stored photos with no row pointing at them and older than
  /// [orphanGracePeriod].
  Future<Set<String>> orphans(Set<String> referenced, {DateTime? now});

  /// Deletes every orphan and returns how many went.
  Future<int> sweepOrphans(Set<String> referenced, {DateTime? now});

  /// Total bytes used by stored photos.
  Future<int> totalBytes();

  /// How many photos are stored.
  Future<int> count();
}

/// The real one: JPEGs in a directory on disk.
///
/// Takes a [Directory] rather than calling `path_provider` itself, so it can
/// be pointed at a temp directory in a test without a plugin channel.
class FileImageStore implements ImageStore {
  FileImageStore(this.directory);

  final Directory directory;

  /// Ensures the backing directory exists. Safe to call repeatedly.
  ///
  /// `create(recursive: true)` is already a no-op when the directory is
  /// there, so checking first would just be an extra syscall.
  @override
  Future<void> ensureReady() => directory.create(recursive: true);

  /// Writes [bytes] under [id] and returns the filename to store on the row.
  ///
  /// [id] is normally the expense's UUID, which keeps the mapping between row
  /// and file obvious when inspecting the directory by hand.
  @override
  Future<String> save(String id, List<int> bytes) async {
    await ensureReady();
    final filename = '$id${ImageStore.extension}';
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
    return filename;
  }

  /// Resolves a stored filename to a file handle.
  ///
  /// Does not check existence — callers that care should use [exists], since
  /// a missing file is an expected state after retention expiry, not an error.
  @override
  File fileFor(String filename) => File('${directory.path}/$filename');

  /// Whether a stored photo is still on disk.
  ///
  /// Synchronous on purpose. `File.exists()` is a single `stat` dispatched to
  /// the IO thread pool, which costs more than the syscall it wraps —
  /// `existsSync` is the faster call despite looking like the blunt one.
  @override
  bool exists(String filename) => fileFor(filename).existsSync();

  /// Deletes a stored photo. A file that is already gone is not an error.
  ///
  /// Deleting and catching, rather than checking then deleting, also closes
  /// the gap between the two calls where a sweep running concurrently could
  /// remove the file and turn the delete into an exception.
  @override
  Future<void> delete(String filename) async {
    try {
      await fileFor(filename).delete();
    } on FileSystemException {
      // Already gone, which is the outcome we wanted.
    }
  }

  /// Every photo filename currently on disk.
  @override
  Future<Set<String>> listFilenames() async {
    if (!directory.existsSync()) return <String>{};
    final entries = await directory.list().toList();
    return entries
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith(ImageStore.extension))
        .toSet();
  }

  /// Files on disk with no row pointing at them, older than the grace period.
  ///
  /// These accumulate when the app is killed between writing a photo and
  /// saving its expense.
  ///
  /// The age check is the important part. A photo is written when it is taken,
  /// before the expense row exists, so between the shutter and the save it is
  /// genuinely unreferenced — and a sweep running in that window deletes a
  /// photo the user is still in the middle of attaching.
  @override
  Future<Set<String>> orphans(Set<String> referenced, {DateTime? now}) async {
    final onDisk = await listFilenames();
    final unreferenced = onDisk.difference(referenced);
    if (unreferenced.isEmpty) return unreferenced;

    final cutoff = (now ?? DateTime.now()).subtract(
      ImageStore.orphanGracePeriod,
    );

    return <String>{
      for (final filename in unreferenced)
        if (_writtenBefore(filename, cutoff)) filename,
    };
  }

  /// Whether a file is old enough to count as abandoned.
  ///
  /// A file that vanished between listing and stat-ing counts as sweepable —
  /// deleting something already gone is a no-op.
  bool _writtenBefore(String filename, DateTime cutoff) {
    final file = fileFor(filename);
    if (!file.existsSync()) return true;
    return file.lastModifiedSync().isBefore(cutoff);
  }

  /// Deletes every orphan and returns how many went.
  @override
  Future<int> sweepOrphans(Set<String> referenced, {DateTime? now}) async {
    final toDelete = await orphans(referenced, now: now);
    for (final filename in toDelete) {
      await delete(filename);
    }
    return toDelete.length;
  }

  /// Total bytes used by stored photos.
  ///
  /// Shown in Settings so the number is visible before it becomes a problem.
  @override
  Future<int> totalBytes() async {
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(ImageStore.extension)) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  Future<int> count() async => (await listFilenames()).length;
}
