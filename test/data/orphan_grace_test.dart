import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/image_store.dart';

import '../helpers/in_memory_image_store.dart';

/// The sweep must be safe whenever it runs, not only at launch.
///
/// It was written on the assumption that nothing could be mid-attachment when
/// it ran, because it only ran at launch. That assumption was false: the app
/// lock unmounted and remounted the widget holding the startup tasks, so the
/// sweep fired on every unlock — including the unlock that follows a long
/// trip to the camera app, deleting the photo about to be saved.
///
/// An assumption about when code runs is not a guarantee. The grace period
/// makes the sweep correct regardless of when it fires.
void main() {
  final now = DateTime(2026, 9, 21, 14, 0);

  group('InMemoryImageStore grace period', () {
    late InMemoryImageStore store;

    setUp(() => store = InMemoryImageStore());

    Future<String> saveAt(String id, DateTime when) async {
      store.nextWriteTime = when;
      final name = await store.save(id, <int>[1, 2, 3]);
      store.nextWriteTime = null;
      return name;
    }

    test('a photo taken seconds ago is never swept', () async {
      // The bug, reduced: taken, not yet saved to a row, sweep runs.
      final name = await saveAt(
        'fresh',
        now.subtract(const Duration(seconds: 8)),
      );

      expect(await store.sweepOrphans(<String>{}, now: now), 0);
      expect(store.exists(name), isTrue);
    });

    test('a photo from ten minutes ago is still protected', () async {
      await saveAt('recent', now.subtract(const Duration(minutes: 10)));
      expect(await store.sweepOrphans(<String>{}, now: now), 0);
    });

    test('a photo from yesterday is swept', () async {
      final name = await saveAt('old', now.subtract(const Duration(days: 1)));

      expect(await store.sweepOrphans(<String>{}, now: now), 1);
      expect(store.exists(name), isFalse);
    });

    test('exactly at the grace boundary is not yet swept', () async {
      await saveAt('edge', now.subtract(ImageStore.orphanGracePeriod));
      // isBefore, not isSameOrBefore — the boundary stays protected.
      expect(await store.sweepOrphans(<String>{}, now: now), 0);
    });

    test('a referenced photo is never swept, however old', () async {
      final name = await saveAt('kept', DateTime(2020));
      expect(await store.sweepOrphans(<String>{name}, now: now), 0);
      expect(store.exists(name), isTrue);
    });

    test('old orphans still go while a fresh one stays', () async {
      final fresh = await saveAt(
        'fresh',
        now.subtract(const Duration(minutes: 1)),
      );
      final stale = await saveAt(
        'stale',
        now.subtract(const Duration(days: 3)),
      );
      final kept = await saveAt('kept', DateTime(2020));

      expect(await store.sweepOrphans(<String>{kept}, now: now), 1);
      expect(store.exists(fresh), isTrue);
      expect(store.exists(kept), isTrue);
      expect(store.exists(stale), isFalse);
    });

    test('orphans() reports the same set the sweep would delete', () async {
      await saveAt('fresh', now.subtract(const Duration(minutes: 2)));
      final stale = await saveAt(
        'stale',
        now.subtract(const Duration(days: 2)),
      );

      expect(await store.orphans(<String>{}, now: now), <String>{stale});
    });
  });

  group('FileImageStore grace period', () {
    late Directory temp;
    late FileImageStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('harvest_grace');
      store = FileImageStore(Directory('${temp.path}/receipts'));
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
    });

    test('a file just written survives a sweep', () async {
      // Real files, real mtimes — the path the device actually takes.
      final name = await store.save('fresh', <int>[1, 2, 3]);

      expect(await store.sweepOrphans(<String>{}), 0);
      expect(store.exists(name), isTrue);
    });

    test('backdating the file makes it sweepable', () async {
      final name = await store.save('old', <int>[1, 2, 3]);
      store
          .fileFor(name)
          .setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 1)),
          );

      expect(await store.sweepOrphans(<String>{}), 1);
      expect(store.exists(name), isFalse);
    });

    test('a referenced file is kept even when backdated', () async {
      final name = await store.save('kept', <int>[1, 2, 3]);
      store
          .fileFor(name)
          .setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 9)),
          );

      expect(await store.sweepOrphans(<String>{name}), 0);
      expect(store.exists(name), isTrue);
    });
  });
}
