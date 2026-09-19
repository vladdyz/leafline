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
/// are async, but never for "is the database open yet". See decision 0010.
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
      home: const _CurrentWeekGate(child: WeekListScreen()),
    );
  }
}

/// Makes sure the current week has a budget row before anything renders, and
/// again whenever the app comes back to the foreground.
///
/// The resume case is not theoretical: leave the app open on a Sunday evening
/// and pick it up on Monday, and the current week has changed underneath a
/// process that only ever checked at launch. Without this, Monday shows last
/// week at the top and no row for the week you are actually in.
class _CurrentWeekGate extends ConsumerStatefulWidget {
  const _CurrentWeekGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_CurrentWeekGate> createState() => _CurrentWeekGateState();
}

class _CurrentWeekGateState extends ConsumerState<_CurrentWeekGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensure();
  }

  Future<void> _ensure() async {
    final now = ref.read(nowProvider)();
    // Idempotent, so calling it on every resume costs one indexed lookup and
    // leaves an existing week — override included — untouched.
    await ref.read(weekBudgetRepositoryProvider).ensureWeek(now, now: now);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
