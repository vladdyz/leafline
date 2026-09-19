import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/theme.dart';

/// Wraps [home] in the same app shell and provider graph the real app uses,
/// but with an in-memory database, a temp photo directory and a pinned clock.
///
/// The repositories are real. Widget tests therefore exercise the actual SQL
/// the screens depend on, which is where the interesting bugs live — a mocked
/// repository would happily return rows that the real query never would.
///
/// [now] matters more than it looks. Half of this app's behaviour turns on
/// which week is the current one, so a suite that used the wall clock would
/// pass on a Thursday and fail on a Monday.
Widget testApp({
  required Widget home,
  required AppDatabase database,
  required Directory documents,
  DateTime? now,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      documentsDirectoryProvider.overrideWithValue(documents),
      if (now != null) nowProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp(theme: HarvestTheme.light(), home: home),
  );
}

/// Pumps [home] and settles, which the async providers need before anything
/// is on screen.
Future<void> pumpApp(
  WidgetTester tester, {
  required Widget home,
  required AppDatabase database,
  required Directory documents,
  DateTime? now,
}) async {
  await tester.pumpWidget(
    testApp(home: home, database: database, documents: documents, now: now),
  );
  await tester.pumpAndSettle();
}
