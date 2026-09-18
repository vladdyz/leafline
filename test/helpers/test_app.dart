import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/theme.dart';

/// Wraps [home] in the same app shell and provider graph the real app uses,
/// but with an in-memory database and a temp photo directory.
///
/// The repositories are real. Widget tests therefore exercise the actual SQL
/// the screens depend on, which is where the interesting bugs live — a mocked
/// repository would happily return rows that the real query never would.
Widget testApp({
  required Widget home,
  required AppDatabase database,
  required Directory documents,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      documentsDirectoryProvider.overrideWithValue(documents),
    ],
    child: MaterialApp(
      theme: HarvestTheme.light(),
      home: home,
    ),
  );
}

/// Pumps [home] and settles, which the async providers need before anything
/// is on screen.
Future<void> pumpApp(
  WidgetTester tester, {
  required Widget home,
  required AppDatabase database,
  required Directory documents,
}) async {
  await tester.pumpWidget(
    testApp(home: home, database: database, documents: documents),
  );
  await tester.pumpAndSettle();
}
