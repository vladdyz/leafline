import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:receipt_tracker/data/image_store.dart';

void main() {
  late Directory temp;
  late FileImageStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('receipt_tracker_test');
    store = FileImageStore(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  final bytes = List<int>.filled(128, 7);

  group('save and resolve', () {
    test('writes a file named after the id', () async {
      final filename = await store.save('abc', bytes);
      expect(filename, 'abc.jpg');
      expect(store.exists(filename), isTrue);
    });

    test('creates the directory if it is missing', () async {
      await temp.delete(recursive: true);
      final filename = await store.save('abc', bytes);
      expect(store.exists(filename), isTrue);
    });

    test('round-trips the bytes', () async {
      final filename = await store.save('abc', bytes);
      expect(await store.fileFor(filename).readAsBytes(), bytes);
    });

    test('overwrites an existing file for the same id', () async {
      await store.save('abc', bytes);
      await store.save('abc', List<int>.filled(64, 9));
      expect(await store.fileFor('abc.jpg').length(), 64);
    });

    test('fileFor does not require the file to exist', () async {
      // Callers handle absence themselves — a missing photo is an expected
      // state after retention expiry, not an error.
      expect(store.fileFor('nothing.jpg').path, contains('nothing.jpg'));
      expect(store.exists('nothing.jpg'), isFalse);
    });
  });

  group('delete', () {
    test('removes the file', () async {
      final filename = await store.save('abc', bytes);
      await store.delete(filename);
      expect(store.exists(filename), isFalse);
    });

    test('deleting a missing file is not an error', () async {
      await expectLater(store.delete('ghost.jpg'), completes);
    });
  });

  group('listing', () {
    test('lists only jpg files', () async {
      await store.save('a', bytes);
      await store.save('b', bytes);
      await File('${temp.path}/notes.txt').writeAsString('ignore me');

      expect(await store.listFilenames(), <String>{'a.jpg', 'b.jpg'});
    });

    test('is empty when the directory does not exist', () async {
      await temp.delete(recursive: true);
      expect(await store.listFilenames(), isEmpty);
    });

    test('counts files', () async {
      await store.save('a', bytes);
      await store.save('b', bytes);
      expect(await store.count(), 2);
    });

    test('totals bytes', () async {
      await store.save('a', bytes);
      await store.save('b', bytes);
      expect(await store.totalBytes(), 256);
    });

    test('totals zero when empty', () async {
      expect(await store.totalBytes(), 0);
    });
  });

  group('orphan sweep', () {
    test('finds files with no referencing row', () async {
      await store.save('kept', bytes);
      await store.save('orphan', bytes);

      final orphans = await store.orphans(<String>{'kept.jpg'});
      expect(orphans, <String>{'orphan.jpg'});
    });

    test('finds nothing when every file is referenced', () async {
      await store.save('a', bytes);
      expect(await store.orphans(<String>{'a.jpg'}), isEmpty);
    });

    test('sweeping deletes orphans and keeps the rest', () async {
      await store.save('kept', bytes);
      await store.save('orphan', bytes);

      expect(await store.sweepOrphans(<String>{'kept.jpg'}), 1);
      expect(store.exists('kept.jpg'), isTrue);
      expect(store.exists('orphan.jpg'), isFalse);
    });

    test(
      'a referenced file that is missing from disk is not an error',
      () async {
        // The other direction of the same mismatch: a row pointing at a file
        // that is gone. The sweep must not care.
        expect(await store.sweepOrphans(<String>{'missing.jpg'}), 0);
      },
    );
  });
}
