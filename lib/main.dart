import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receipt_tracker/data/database.dart';
import 'package:receipt_tracker/services/app_lock_service.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/screens/lock_screen.dart';
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
      title:
          'LeafLine', // renamed from Canopy -> Harvest -> LeafLine (see docs)
      debugShowCheckedModeBanner: false,
      theme: HarvestTheme.light(),
      darkTheme: HarvestTheme.dark(),
      home: const _AppLockGate(child: _StartupTasks(child: WeekListScreen())),
    );
  }
}

/// Housekeeping that has to happen on launch and on resume.
///
/// **The current week's budget row.** Leave the app open on a Sunday evening
/// and pick it up on Monday, and the current week has changed underneath a
/// process that only checked at launch. Without the resume case, Monday shows
/// last week at the top and no row for the week you are actually in.
///
/// **Orphan photos.** A photo is written the moment it is taken, before the
/// expense row exists, so abandoning a half-filled form leaves a file nothing
/// points at. Sweeping on launch keeps that from accumulating silently.
///
/// **Expired photos.** Photos older than the retention window are removed and
/// their rows' `photo_file` nulled. The expenses stay; only the pictures age
/// out.
class _StartupTasks extends ConsumerStatefulWidget {
  const _StartupTasks({required this.child});

  final Widget child;

  @override
  ConsumerState<_StartupTasks> createState() => _StartupTasksState();
}

class _StartupTasksState extends ConsumerState<_StartupTasks>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensure();
      // Retention first, then orphans. Expiring a photo deletes its file
      // directly, so running orphans afterwards is the cheaper order — it
      // sweeps a directory that is already smaller, and anything the
      // retention pass failed to delete still gets collected.
      await _sweepExpiredPhotos();
      await _sweepOrphanPhotos();
      // Creates the notification channel so Android's settings list it before
      // the first warning ever fires. Permission is NOT requested here — that
      // happens when a warning is actually due, where the ask has context.
      await ref.read(notificationServiceProvider).initialize();
    });
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

  /// Removes photos that have outlived the retention window.
  ///
  /// Launch only. The window is measured in months, so there is no case where
  /// resuming the app mid-session crosses it in a way worth acting on.
  Future<void> _sweepExpiredPhotos() async {
    final retention = await ref
        .read(settingsRepositoryProvider)
        .getPhotoRetention();
    await ref
        .read(photoRetentionSweeperProvider)
        .sweep(retention: retention, now: ref.read(nowProvider)());
  }

  /// Deletes photo files with no expense pointing at them.
  ///
  /// Launch only, not resume: it touches every file in the directory, and
  /// nothing can create an orphan while the app is in the background.
  Future<void> _sweepOrphanPhotos() async {
    final referenced = await ref
        .read(expenseRepositoryProvider)
        .referencedPhotoFiles();
    await ref.read(imageStoreProvider).sweepOrphans(referenced);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Holds the app behind a device authentication prompt.
///
/// Locks on cold start, and again on resume once the app has been away for
/// longer than [_grace]. The grace window exists because an app that
/// re-prompts every time you glance at a notification is an app whose lock
/// gets switched off.
///
/// Off by default. Decision 0004 is that there is nothing to authenticate
/// against — the database sits in the app's private sandbox either way — so
/// this guards exactly one threat from the threat model: someone picking up
/// an unlocked phone.
class _AppLockGate extends ConsumerStatefulWidget {
  const _AppLockGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<_AppLockGate>
    with WidgetsBindingObserver {
  static const Duration _grace = Duration(minutes: 2);

  DateTime? _unlockedAt;
  bool _locked = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _evaluate();
  }

  Future<void> _evaluate() async {
    final enabled = await ref
        .read(settingsRepositoryProvider)
        .getAppLockEnabled();
    final lock = shouldLock(
      enabled: enabled,
      unlockedAt: _unlockedAt,
      now: ref.read(nowProvider)(),
      grace: _grace,
    );

    if (!mounted) return;
    if (!lock) {
      if (_locked) setState(() => _locked = false);
      return;
    }

    setState(() => _locked = true);
    await _unlock();
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    setState(() => _prompting = true);

    final ok = await ref.read(appLockServiceProvider).authenticate();

    if (!mounted) return;
    setState(() {
      _prompting = false;
      if (ok) {
        _locked = false;
        _unlockedAt = ref.read(nowProvider)();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The child stays built underneath rather than being torn down, so
    // unlocking returns to exactly where the user was. It is covered, not
    // discarded.
    return _locked
        ? LockScreen(onUnlock: _unlock, busy: _prompting)
        : widget.child;
  }
}
