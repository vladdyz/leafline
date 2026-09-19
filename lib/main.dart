import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/week_list_screen.dart';
import 'package:receipt_tracker/ui/theme.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the database and resolves the photo directory before the first
/// frame, then hands both to the provider graph as overrides.
///
/// Doing this here rather than lazily keeps every provider downstream
/// synchronous — screens deal with `AsyncValue` for queries, which genuinely
/// are async, but never for "is the database open yet".
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open(
    path: p.join(await getDatabasesPath(), 'harvest.db'),
  );
  final documents = await getApplicationDocumentsDirectory();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        documentsDirectoryProvider.overrideWithValue(documents),
      ],
      child: const HarvestApp(),
    ),
  );
}

class HarvestApp extends StatelessWidget {
  const HarvestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harvest',
      debugShowCheckedModeBanner: false,
      theme: HarvestTheme.light(),
      darkTheme: HarvestTheme.dark(),
      home: const WeekListScreen(),
    );
  }
}
