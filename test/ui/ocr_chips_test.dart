import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/services/channel_ocr_service.dart';
import 'package:receipt_tracker/services/ocr_service.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/widgets/amount_chips.dart';

import '../helpers/fake_ocr_service.dart';
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
    documents = await Directory.systemTemp.createTemp('harvest_ocr_test');
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

  Future<void> pumpForm(WidgetTester tester, {required OcrService ocr}) async {
    // The form is a ListView, and the chips add about 64px to it. At the
    // default 800x600 surface that pushes the save button past the bottom of
    // the viewport — and a ListView does not build what is past the edge, so
    // the button is not in the tree at all. The finder reports zero widgets,
    // which reads like the button is missing rather than merely scrolled off.
    //
    // A taller surface keeps these tests about what the form does, not about
    // where it happens to have scrolled to. On a real phone the form scrolls,
    // which is what forms do.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await weekBudgets.setDefaultWeeklyCents(20000, now: now);
    await weekBudgets.ensureWeek(thisWeek, now: now);
    await pumpApp(
      tester,
      home: const ExpenseFormScreen(),
      database: database,
      documents: documents,
      now: now,
      photoSource: FakePhotoSource(),
      imageStore: store,
      ocrService: ocr,
    );
  }

  Future<void> takePhoto(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
  }

  group('chips from a readable receipt', () {
    testWidgets('appear after a photo is taken', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService());
      expect(find.byType(AmountChips), findsOneWidget);
      expect(find.text('From the receipt'), findsNothing);

      await takePhoto(tester);

      expect(find.text('From the receipt'), findsOneWidget);
    });

    testWidgets('offer the total first', (tester) async {
      // The stub receipt's decoys are a $6.25 subtotal and $10.00 cash. The
      // right answer is $7.06.
      await pumpForm(tester, ocr: FakeOcrService());
      await takePhoto(tester);

      final chips = tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .toList();
      expect(chips, isNotEmpty);
      expect(((chips.first.label as Text).data), r'$7.06');
    });

    testWidgets('tapping one fills the amount field', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService());
      await takePhoto(tester);

      await tester.tap(find.widgetWithText(ActionChip, r'$7.06'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Amount'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text, '7.06');
    });

    testWidgets('the chosen amount saves as entered', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService());
      await takePhoto(tester);

      await tester.tap(find.widgetWithText(ActionChip, r'$7.06'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      expect((await expenses.getAll()).single.amountCents, 706);
    });

    testWidgets('the recognised text is kept on the expense', (tester) async {
      // This is what lets a receipt that fools the extractor become a fixture
      // without re-photographing it.
      await pumpForm(tester, ocr: FakeOcrService());
      await takePhoto(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '7.06',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      final saved = (await expenses.getAll()).single;
      expect(saved.ocrRawText, contains('TOTAL'));
      expect(saved.ocrRawText, contains('7.06'));
    });

    testWidgets('the service is asked about the stored photo', (tester) async {
      final ocr = FakeOcrService();
      await pumpForm(tester, ocr: ocr);
      await takePhoto(tester);

      expect(ocr.calls, hasLength(1));
      expect(ocr.calls.single, contains('.jpg'));
    });
  });

  group('every unreadable case renders the same nothing', () {
    testWidgets('a receipt with no legible text', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService.findsNothing());
      await takePhoto(tester);

      expect(find.text('From the receipt'), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('a platform with no OCR', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService.unavailable());
      await takePhoto(tester);

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('a channel that cannot be reached', (tester) async {
      // An unregistered plugin is a setup error, but it is not the user's,
      // and there is nothing useful to tell them mid-expense.
      await pumpForm(tester, ocr: FakeOcrService.fails());
      await takePhoto(tester);

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('and the photo still attaches in every case', (tester) async {
      for (final ocr in <OcrService>[
        FakeOcrService.findsNothing(),
        FakeOcrService.unavailable(),
        FakeOcrService.fails(),
      ]) {
        await pumpForm(tester, ocr: ocr);
        await takePhoto(tester);
        expect(
          find.text('Tap the photo to view it full size.'),
          findsOneWidget,
        );
      }
    });

    testWidgets('a failure leaves no raw text behind', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService.fails());
      await takePhoto(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '5.00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pumpAndSettle();

      expect((await expenses.getAll()).single.ocrRawText, isNull);
    });
  });

  group('removing the photo', () {
    testWidgets('takes the chips with it', (tester) async {
      await pumpForm(tester, ocr: FakeOcrService());
      await takePhoto(tester);
      expect(find.byType(ActionChip), findsWidgets);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('From the receipt'), findsNothing);
    });
  });

  group('the channel contract', () {
    test('the Dart channel name matches the Kotlin constant', () {
      // Both sides hold this as a plain literal precisely so it can be
      // compared. A mismatch surfaces as MissingPluginException, which reads
      // like the plugin was never registered rather than like a typo.
      expect(ChannelOcrService.channelName, 'receipt_tracker/ocr');
    });

    test('the service reports availability by platform', () {
      const service = ChannelOcrService();
      expect(service.isAvailable, Platform.isAndroid);
    });
  });
}
