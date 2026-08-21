import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'browser/browser_controller.dart';
import 'capability/entitlement.dart';
import 'capability/foreground_multitasking.dart';
import 'browser/history_repository.dart';
import 'save/save_run.dart';
import 'core/device_storage.dart';
import 'core/startup.dart';
import 'features/splash_screen.dart';
import 'providers.dart';
import 'storage/database.dart';
import 'storage/file_store.dart';
import 'storage/recovery.dart';
import 'ui/palette.dart';

/// Renders on the first frame. The startup work then runs *inside* the tree,
/// under the splash, rather than before `runApp` behind a blank window — which
/// is what makes a slow boot legible instead of looking like a hang.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBoot());
}

/// Holds the startup sequence and swaps the app in when it finishes.
class AppBoot extends StatefulWidget {
  const AppBoot({super.key});

  @override
  State<AppBoot> createState() => _AppBootState();
}

class _AppBootState extends State<AppBoot> with WidgetsBindingObserver {
  /// How long the splash is shown at minimum. Startup is usually far quicker
  /// than this; the floor exists so launching does not flash a half-drawn
  /// screen at the user, and so the sequence stays readable when it matters.
  static const _minimumSplash = Duration(milliseconds: 850);
  static const _fadeOut = Duration(milliseconds: 340);

  late AppStartup _startup;
  late StartupController _controller;

  AppServices? _services;
  bool _splashVisible = true;
  double _splashOpacity = 1;
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    // The splash follows the system appearance, like the native launch screen
    // it continues; the persisted preference applies once the app is up.
    WidgetsBinding.instance.addObserver(this);
    _begin();
  }

  @override
  void didChangePlatformBrightness() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (next != _brightness) setState(() => _brightness = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _begin() {
    _startup = AppStartup();
    _controller = StartupController(
      _startup.steps,
      // Paces the *report*, not the work: five steps that each take four
      // milliseconds would otherwise be one unreadable flicker.
      minStepDuration: const Duration(milliseconds: 130),
    )..addListener(_onProgress);
    unawaited(_finishWhenReady(_controller.run()));
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  /// Runs the sequence, then reveals the app — never before [_minimumSplash].
  Future<void> _finishWhenReady(Future<void> running) async {
    final startedAt = DateTime.now();
    await running;
    if (!mounted || _controller.value.hasFailed) return;

    for (final warning in _controller.value.warnings) {
      debugPrint('[startup] continued past: $warning');
    }

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _minimumSplash) {
      await Future<void>.delayed(_minimumSplash - elapsed);
    }
    if (!mounted) return;

    // Mount the app under the splash, then fade the splash off it. Both trees
    // are alive for the length of the fade, so the first frame of the library
    // is already painted by the time it becomes visible.
    setState(() => _services = _startup.services);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _splashOpacity = 0);
    });
  }

  void _retry() {
    _controller.removeListener(_onProgress);
    _controller.dispose();
    setState(_begin);
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final palette = _brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (services != null)
            ProviderScope(
              overrides: [appServicesProvider.overrideWithValue(services)],
              child: const WebReaderApp(),
            ),
          if (_splashVisible)
            IgnorePointer(
              // Only once it is on its way out: the failure screen's retry
              // has to stay tappable.
              ignoring: _splashOpacity == 0,
              child: AnimatedOpacity(
                opacity: _splashOpacity,
                duration: _fadeOut,
                curve: Curves.easeInOut,
                onEnd: () {
                  if (_splashOpacity == 0 && mounted) {
                    setState(() => _splashVisible = false);
                  }
                },
                child: StartupSplash(
                  palette: palette,
                  run: _controller.value,
                  onRetry: _controller.value.hasFailed ? _retry : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The app's actual startup sequence.
///
/// Every step here used to be a `try`/`catch` block in `main()`, in this order
/// and with these semantics — only the first is fatal, and the rest are
/// best-effort maintenance that must never keep the user out of their library.
class AppStartup {
  AppDatabase? _db;
  FileStore? _fileStore;
  AppServices? _services;

  /// Available once the sequence has completed without a critical failure.
  AppServices get services => _services!;

  late final List<StartupStep> steps = [
    StartupStep(label: 'Opening your library', critical: true, run: _open),
    StartupStep(label: 'Recovering interrupted saves', run: _recover),
    StartupStep(label: 'Tidying browsing data', run: _browserData),
    StartupStep(label: 'Checking pending tasks', run: _pendingTasks),
  ];

  /// Storage, the controllers built on it, and the wiring between them.
  /// Critical: there is no app without these.
  Future<void> _open() async {
    // Reused across a retry: a second AppDatabase over the same file would be
    // a second connection, and the first one is already open.
    final db = _db ??= AppDatabase();
    final fileStore = _fileStore ??= await FileStore.open();

    final browser = BrowserController();
    final saveRun = SaveRunController(
      browser: browser,
      db: db,
      fileStore: fileStore,
      // The Browser renders `CollectionNamePanel`, so this is the one place a
      // run has somebody to ask before it names a group on their behalf.
      asksForCollectionName: true,
    );

    // Browsing history (M18). The controller emits every completed load; the
    // repository decides which of them was a page the *user* visited, so the
    // filtering rule lives in one place rather than at every call site (D53).
    final history = HistoryRepository(db);
    browser.onVisitCompleted = (visit) => unawaited(
      history
          .recordVisit(
            url: visit.url,
            title: visit.title,
            source: visit.source,
            finalUrl: visit.wasRedirected ? visit.url : null,
          )
          .catchError((Object e) {
            debugPrint('[history] record failed: $e');
            return null;
          }),
    );

    // Read before the app builds, not watched: the shell decides how to
    // composite the Browser on its first frame, and a capability that arrived
    // a frame later would flip that decision under a run.
    final multitasking =
        ForegroundMultitasking(
            ForegroundMultitasking.parse(
              await db.setting(ForegroundMultitasking.settingKey),
            ),
          )
          // The internal entitlement override. Read here so it is in force
          // before the first frame decides what the shell paints; in a
          // production build nothing can ever have written it.
          ..override = EntitlementOverride.parse(
            await db.setting(ForegroundMultitasking.overrideSettingKey),
          );

    _services = AppServices(
      db: db,
      fileStore: fileStore,
      browser: browser,
      saveRun: saveRun,
      foregroundMultitasking: multitasking,
    );

    // Entry assets are re-downloadable; a multi-GB library must not ride
    // along in every iCloud backup. Only the asset tree is excluded — the
    // database (reading state, rules, settings) stays backed up. Idempotent;
    // Android reports unsupported and that is fine. Not worth failing a boot
    // over, so it is caught here rather than taking the critical step down.
    try {
      final excluded = await DeviceStorage().excludeFromBackup(
        fileStore.rootDir.path,
      );
      debugPrint(
        '[storage] backup exclusion: ${excluded ? 'set' : 'unsupported'}',
      );
    } catch (e) {
      debugPrint('[storage] backup exclusion failed: $e');
    }
  }

  /// Startup recovery, before the UI is interactive.
  ///
  /// The invariant this protects: an entry is never promoted to `complete` by
  /// recovery. Anything left mid-flight is reset and re-capturable; anything
  /// whose files vanished is demoted, keeping its row.
  Future<void> _recover() async {
    final db = _db!;
    final fileStore = _fileStore!;

    // A kill between "step the old entry aside" and "move the new one in"
    // leaves a `.previous` directory; put it back before anything reads.
    final restored = await fileStore.restoreInterruptedReplacements();
    if (restored > 0) {
      debugPrint('[recovery] restored $restored interrupted replacement(s)');
    }

    final swept = await fileStore.sweepStaging();
    if (swept > 0) debugPrint('[recovery] swept $swept staging dir(s)');

    final reset = await db.resetInFlightEntries();
    if (reset > 0) debugPrint('[recovery] reset $reset in-flight entry(s)');

    // Files on disk with no usable database row: finish the record from the
    // manifest, which describes itself.
    for (final relative in fileStore.listCommittedEntryPaths()) {
      final manifest = await fileStore.readManifest(relative);
      if (manifest == null) continue;
      final existing = await db.entryById(manifest.entryId);
      if (existing != null && existing.contentPath != null) continue;
      if (!isRecoverable(manifest)) continue;
      debugPrint('[recovery] reconciling ${manifest.entryId} from manifest');
      await db.upsertEntry(
        entryFromManifest(
          manifest: manifest,
          relativePath: relative,
          byteSize: await fileStore.entryByteSize(relative),
          prior: existing,
        ),
      );
    }
  }

  /// Browsing-data retention.
  ///
  /// Nothing is seeded here. The saved-sites list starts empty and stays empty
  /// until the user puts something in it: a site the developer chose would be a
  /// recommendation the app is not entitled to make, and a bundled starting
  /// point is how a neutral reader acquires a provider catalogue by accident.
  Future<void> _browserData() async {
    final db = _db!;
    final pruned = await HistoryRepository(db).prune();
    if (pruned > 0) debugPrint('[history] pruned $pruned old visit(s)');
  }

  /// Turn any queue rows a kill left behind into a resume OFFER — nothing
  /// autonomous starts at launch (Q24).
  Future<void> _pendingTasks() => _services!.taskQueue.restore();
}
