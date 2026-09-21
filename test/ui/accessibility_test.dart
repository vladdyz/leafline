import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/data/expense_repository.dart';
import 'package:receipt_tracker/data/week_budget_repository.dart';
import 'package:receipt_tracker/ui/screens/all_weeks_screen.dart';
import 'package:receipt_tracker/ui/screens/expense_form_screen.dart';
import 'package:receipt_tracker/ui/screens/settings_screen.dart';
import 'package:receipt_tracker/ui/screens/week_list_screen.dart';

import '../helpers/in_memory_image_store.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database.dart';

/// Accessibility checks that a machine can actually make.
///
/// Three things are verified here, and it is worth being clear about what is
/// not: nothing in this file proves the app is usable with TalkBack. Screen
/// reader behaviour needs a screen reader. What these do prove is that the
/// conditions under which it becomes unusable are absent.
///
/// 1. **Text scaling.** Android lets users set font size up to 200%, and
///    Flutter honours it. A `Row` overflows by throwing rather than wrapping,
///    and a thrown layout error fails a widget test — so rendering every
///    screen at 2.0 is a real assertion, not a smoke test. One such overflow
///    was already found at 1.0 scale in Phase 4d.
///
/// 2. **Tap targets.** `meetsGuideline(androidTapTargetGuideline)` checks the
///    48x48dp minimum that both Material and WCAG 2.2 require.
///
/// 3. **Labelled controls.** `labeledTapTargetGuideline` fails any tappable
///    with nothing for a screen reader to announce.
void main() {
  setUpAll(initTestDatabase);

  final now = DateTime(2026, 9, 17, 10);
  final thisWeek = DateTime(2026, 9, 14);

  late AppDatabase database;
  late ExpenseRepository expenses;
  late WeekBudgetRepository weekBudgets;
  late Directory documents;

  setUp(() async {
    database = await openTestDatabase();
    expenses = ExpenseRepository(database);
    weekBudgets = WeekBudgetRepository(database);
    documents = await Directory.systemTemp.createTemp('harvest_a11y');

    await weekBudgets.setDefaultWeeklyCents(20000, now: now);
    await weekBudgets.ensureWeek(thisWeek, now: now);
    for (final entry in <List<Object>>[
      <Object>['a', 4250, 'Corner Market'],
      <Object>['b', 11900, 'Grocery run with a fairly long merchant name'],
      <Object>['c', 875, 'Coffee'],
    ]) {
      await expenses.insert(
        makeExpense(
          id: entry[0] as String,
          amountCents: entry[1] as int,
          spentOn: DateTime(2026, 9, 16),
          merchant: entry[2] as String,
        ),
      );
    }

    addTearDown(() async {
      await expenses.dispose();
      await weekBudgets.dispose();
      await database.close();
      if (documents.existsSync()) {
        await documents.delete(recursive: true);
      }
    });
  });

  /// Renders [home] at [scale] on a phone-sized surface.
  ///
  /// The surface is tall because at 200% every screen is far longer than a
  /// viewport; the question here is whether anything *overflows sideways or
  /// throws*, not whether it fits without scrolling. Scrolling is a normal
  /// answer to large text.
  Future<void> pumpAt(
    WidgetTester tester,
    Widget home, {
    required double scale,
  }) async {
    await tester.binding.setSurfaceSize(Size(360, 900 * scale));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(
      tester,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: home,
      ),
      database: database,
      documents: documents,
      now: now,
      imageStore: InMemoryImageStore(),
    );
  }

  final screens = <String, Widget Function()>{
    'week list': WeekListScreen.new,
    'all weeks': AllWeeksScreen.new,
    'settings': SettingsScreen.new,
    'expense form': ExpenseFormScreen.new,
  };

  group('renders at 200% text scale', () {
    // Android's accessibility settings go to 200%. Flutter honours it, and a
    // Row that fits at 100% may well throw at 200%.
    for (final entry in screens.entries) {
      testWidgets('${entry.key} does not overflow', (tester) async {
        await pumpAt(tester, entry.value(), scale: 2.0);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('renders at 130% text scale', () {
    // The commonest non-default setting, and the one most users will be on.
    for (final entry in screens.entries) {
      testWidgets('${entry.key} does not overflow', (tester) async {
        await pumpAt(tester, entry.value(), scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('tap targets meet the 48dp minimum', () {
    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpAt(tester, entry.value(), scale: 1.0);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });
    }
  });

  group('every tappable has something to announce', () {
    // The guideline that catches an icon-only button with no tooltip — which
    // a screen reader skips in silence rather than announcing as unlabelled.
    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpAt(tester, entry.value(), scale: 1.0);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  group('text contrast', () {
    // Flutter's own check, against the rendered pixels rather than against
    // the palette. It covers Material-derived colours that no audit of my own
    // constants would reach.
    testWidgets('week list', (tester) async {
      await pumpAt(tester, const WeekListScreen(), scale: 1.0);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('settings', (tester) async {
      await pumpAt(tester, const SettingsScreen(), scale: 1.0);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });
}
