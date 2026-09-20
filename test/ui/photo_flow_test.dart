import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
//import 'package:receipt_tracker/data/image_store.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/services/photo_source.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/widgets/receipt_photo.dart';

import '../helpers/fake_photo_source.dart';
import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;
  late InMemoryImageStore store;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_photo_test');
    // In-memory, so nothing in these tests waits on a real disk write that
    // the widget-test clock will never deliver.
    store = InMemoryImageStore();

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required PhotoSource photoSource,
  }) async {
    await weekBudgets.setDefaultWeeklyCents(20000, now: now);
    await weekBudgets.ensureWeek(thisWeek, now: now);
    await pumpApp(
      tester,
      home: const ExpenseFormScreen(),
      database: database,
      documents: documents,
      now: now,
      photoSource: photoSource,
      imageStore: store,
    );
  }

  group('the photo control', () {
    testWidgets('is offered when a source is available', (tester) async {
      await pumpForm(tester, photoSource: FakePhotoSource());
      expect(find.byType(ReceiptPhotoField), findsOneWidget);
    });

    testWidgets('is hidden when no source exists', (tester) async {
      // A platform with no camera should not be shown a camera button that
      // cannot do anything.
      await pumpForm(tester, photoSource: FakePhotoSource(available: false));
      expect(find.byType(ReceiptPhotoField), findsNothing);
    });

    testWidgets('prompts before a photo is attached', (tester) async {
      await pumpForm(tester, photoSource: FakePhotoSource());
      expect(find.text('Snap the receipt, or skip it.'), findsOneWidget);
    });
  });

  group('capturing', () {
    testWidgets('writes the file and shows a thumbnail', (tester) async {
      final source = FakePhotoSource();
      await pumpForm(tester, photoSource: source);

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      expect(source.captureCount, 1);
      expect(find.byType(ReceiptThumbnail), findsOneWidget);
      expect(find.text('Tap the photo to view it full size.'), findsOneWidget);
      expect(await store.count(), 1);
    });

    testWidgets('the gallery button uses the gallery', (tester) async {
      final source = FakePhotoSource();
      await pumpForm(tester, photoSource: source);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();

      expect(source.pickCount, 1);
      expect(source.captureCount, 0);
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      await pumpForm(tester, photoSource: FakePhotoSource(cancels: true));

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptThumbnail), findsNothing);
      expect(await store.count(), 0);
    });

    testWidgets('a refused permission explains itself and moves on', (
      tester,
    ) async {
      await pumpForm(
        tester,
        photoSource: FakePhotoSource(
          failure: const PhotoFailure(PhotoFailureKind.permissionDenied),
        ),
      );

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      // The message says what to do instead, because the amount field is the
      // point and the photo never was.
      expect(
        find.text('Camera access is off. You can still type the amount in.'),
        findsOneWidget,
      );
      expect(find.byType(ReceiptThumbnail), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('saving', () {
    testWidgets('carries the photo onto the expense', (tester) async {
      await pumpForm(tester, photoSource: FakePhotoSource());

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '12.40',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      final saved = (await expenses.getAll()).single;
      expect(saved.hasPhoto, isTrue);
      expect(store.exists(saved.photoFile!), isTrue);
    });

    testWidgets('files the photo under the expense id', (tester) async {
      // The id is generated when the form opens, not when it saves, because
      // the photo has to be filed before the row exists.
      await pumpForm(tester, photoSource: FakePhotoSource());

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '5.00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      final saved = (await expenses.getAll()).single;
      expect(saved.photoFile, '${saved.id}.jpg');
    });

    testWidgets('abandoning the form leaves an orphan for the sweep', (
      tester,
    ) async {
      await pumpForm(tester, photoSource: FakePhotoSource());

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      // Never saved.
      expect(await store.count(), 1);
      expect(await expenses.count(), 0);

      // Which is exactly what the startup sweep is for.
      final referenced = await expenses.referencedPhotoFiles();
      expect(await store.sweepOrphans(referenced), 1);
      expect(await store.count(), 0);
    });
  });

  group('removing', () {
    testWidgets('clears the field and deletes the file', (tester) async {
      await pumpForm(tester, photoSource: FakePhotoSource());

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();
      expect(await store.count(), 1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptThumbnail), findsNothing);
      expect(await store.count(), 0);
    });
  });

  group('editing an expense that has a photo', () {
    testWidgets('shows the existing photo', (tester) async {
      await weekBudgets.setDefaultWeeklyCents(20000, now: now);
      await weekBudgets.ensureWeek(thisWeek, now: now);
      final filename = await store.save('e1', tinyImageBytes);
      await expenses.insert(
        makeExpense(
          id: 'e1',
          amountCents: 1000,
          spentOn: DateTime(2026, 9, 17),
          photoFile: filename,
        ),
      );

      await pumpApp(
        tester,
        home: ExpenseFormScreen(initial: (await expenses.getById('e1'))!),
        database: database,
        documents: documents,
        now: now,
        photoSource: FakePhotoSource(),
        imageStore: store,
      );

      expect(find.byType(ReceiptThumbnail), findsOneWidget);
    });
  });

  group('PhotoFailure', () {
    test('maps image_picker error codes', () {
      expect(
        PhotoFailure.fromCode('camera_access_denied').kind,
        PhotoFailureKind.permissionDenied,
      );
      expect(
        PhotoFailure.fromCode('photo_access_denied').kind,
        PhotoFailureKind.permissionDenied,
      );
      expect(
        PhotoFailure.fromCode('camera_access_restricted').kind,
        PhotoFailureKind.permissionPermanentlyDenied,
      );
      expect(
        PhotoFailure.fromCode('no_available_camera').kind,
        PhotoFailureKind.unavailable,
      );
      expect(
        PhotoFailure.fromCode('something_new').kind,
        PhotoFailureKind.unknown,
      );
    });

    test('every kind has a message that offers a way forward', () {
      for (final kind in PhotoFailureKind.values) {
        final message = PhotoFailure(kind).userMessage;
        expect(message, isNotEmpty);
        expect(message.toLowerCase(), isNot(contains('exception')));
        expect(message.toLowerCase(), isNot(contains('_')));
      }
    });
  });

  group('UnavailablePhotoSource', () {
    test('reports unavailable and returns nothing', () async {
      const source = UnavailablePhotoSource();
      expect(source.isAvailable, isFalse);
      expect(await source.capture(), isNull);
      expect(await source.pick(), isNull);
    });
  });
}
