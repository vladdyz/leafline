import 'dart:io';

/// Stores receipt photos on disk.
///
/// Takes a [Directory] rather than calling `path_provider` itself. That is
/// what makes this testable: production passes the app documents directory,
/// tests pass a temp directory, and no plugin channel is involved either way.
///
/// The database stores filenames; this class is the only thing that knows
/// where they resolve to. See `docs/decisions/0002-files-not-blobs.md`.
class ImageStore {
  ImageStore(this.directory);

  final Directory directory;

  static const String extension = '.jpg';

  /// Ensures the backing directory exists. Safe to call repeatedly.
  ///
  /// `create(recursive: true)` is already a no-op when the directory is
  /// there, so checking first would just be an extra syscall.
  Future<void> ensureReady() => directory.create(recursive: true);

  /// Writes [bytes] under [id] and returns the filename to store on the row.
  ///
  /// [id] is normally the expense's UUID, which keeps the mapping between row
  /// and file obvious when inspecting the directory by hand.
  Future<String> save(String id, List<int> bytes) async {
    await ensureReady();
    final filename = '$id$extension';
    await File('${directory.path}/$filename').writeAsBytes(bytes, flush: true);
    return filename;
  }

  /// Resolves a stored filename to a file handle.
  ///
  /// Does not check existence — callers that care should use [exists], since
  /// a missing file is an expected state after retention expiry, not an error.
  File fileFor(String filename) => File('${directory.path}/$filename');

  /// Whether a stored photo is still on disk.
  ///
  /// Synchronous on purpose. `File.exists()` is a single `stat` dispatched to
  /// the IO thread pool, which costs more than the syscall it wraps —
  /// `existsSync` is the faster call despite looking like the blunt one.
  bool exists(String filename) => fileFor(filename).existsSync();

  /// Deletes a stored photo. A file that is already gone is not an error.
  ///
  /// Deleting and catching, rather than checking then deleting, also closes
  /// the gap between the two calls where a sweep running concurrently could
  /// remove the file and turn the delete into an exception.
  Future<void> delete(String filename) async {
    try {
      await fileFor(filename).delete();
    } on FileSystemException {
      // Already gone, which is the outcome we wanted.
    }
  }

  /// Every photo filename currently on disk.
  Future<Set<String>> listFilenames() async {
    if (!directory.existsSync()) return <String>{};
    final entries = await directory.list().toList();
    return entries
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith(extension))
        .toSet();
  }

  /// Files on disk with no row pointing at them.
  ///
  /// These accumulate when the app is killed between writing a photo and
  /// saving its expense.
  Future<Set<String>> orphans(Set<String> referenced) async {
    final onDisk = await listFilenames();
    return onDisk.difference(referenced);
  }

  /// Deletes every orphan and returns how many went.
  Future<int> sweepOrphans(Set<String> referenced) async {
    final toDelete = await orphans(referenced);
    for (final filename in toDelete) {
      await delete(filename);
    }
    return toDelete.length;
  }

  /// Total bytes used by stored photos.
  ///
  /// Shown in Settings so the number is visible before it becomes a problem.
  Future<int> totalBytes() async {
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(extension)) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<int> count() async => (await listFilenames()).length;
}
