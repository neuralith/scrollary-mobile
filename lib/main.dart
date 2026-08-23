import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'browser/browser_controller.dart';
import 'capability/entitlement.dart';
import 'capability/foreground_multitasking.dart';
import 'browser/browsing_history.dart';
import 'core/device_storage.dart';
import 'core/startup.dart';
import 'features/splash_screen.dart';
import 'providers.dart';
import 'storage/file_store.dart';
import 'data/local_settings.dart';
import 'data/recognition_index.dart';
import 'data/schema.dart' show LibraryDatabase;
import 'data/reading_state_repository.dart';
import 'features/check_controller.dart';
import 'features/source_observation_browser.dart';
import 'features/v2_composition.dart';
import 'features/v2_save_flow.dart';
import 'library_ui/providers.dart' as libui;
import 'library_ui/sync_status_section.dart' show syncStatusSourceProvider;
import 'recognition/recognise.dart';
import 'save/asset_fetcher.dart';
import 'save/entry_capture.dart';
import 'save/page_capture_source.dart';
import 'save/page_hint_repository.dart';
import 'save/queue_runner.dart';
import 'save/save_engine.dart';
import 'core/config.dart';
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
              overrides: [
                appServicesProvider.overrideWithValue(services),
                v2ServicesProvider.overrideWithValue(_startup.v2),
                libui.libraryUiServicesProvider.overrideWithValue(
                  _startup.v2.ui,
                ),
                libui.fileStoreProvider.overrideWithValue(
                  _startup.v2.ui.fileStore,
                ),
                libui.entryOpenerProvider.overrideWithValue(
                  (id) async => _startup.v2.openEntry?.call(id),
                ),
                libui.sourceOpenerProvider.overrideWithValue(
                  (url) async => _startup.v2.openSource?.call(url),
                ),
                libui.saveQueueStarterProvider.overrideWithValue(
                  () async => _startup.v2.startQueue?.call(),
                ),
                libui.collectionCheckerProvider.overrideWithValue(
                  (id, name) async =>
                      _startup.v2.checkCollection?.call(id, name),
                ),
                libui.placementSubmitProvider.overrideWithValue(
                  placementSubmitFor(_startup.v2),
                ),
                // The scheduler is what `Settings → Sync` reads. Attached
                // whatever this build is configured with: an unconfigured or
                // unentitled device has a state to report, and reporting it is
                // not the same as doing anything.
                syncStatusSourceProvider.overrideWithValue(
                  _startup.v2.sync.scheduler,
                ),
                // The same controller the queue's worker holds — see
                // `AppStartup._open`.
                v2AssistProvider.overrideWithValue(_startup.v2.assist),
                // The same controller, as the narrow seam the operation
                // indicator draws *Needs you* from — so a run parked on a
                // user selection is visible from wherever the user is, not
                // only from the Browser it is parked on.
                assistHoldProvider.overrideWithValue(_startup.v2.assist),
              ],
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
  LibraryDatabase? _library;
  FileStore? _fileStore;
  AppServices? _services;
  V2Services? _v2;

  /// Available once the sequence has completed without a critical failure.
  AppServices get services => _services!;
  V2Services get v2 => _v2!;

  late final List<StartupStep> steps = [
    StartupStep(label: 'Opening your library', critical: true, run: _open),
    StartupStep(label: 'Recovering interrupted saves', run: _recover),
    StartupStep(label: 'Tidying browsing data', run: _browserData),
    StartupStep(label: 'Checking pending tasks', run: _pendingTasks),
  ];

  /// Storage, the controllers built on it, and the wiring between them.
  /// Critical: there is no app without these.
  Future<void> _open() async {
    // Reused across a retry: a second LibraryDatabase over the same file
    // would be a second connection, and the first one is already open.
    //
    // A device that ran an older build still has V1's `webread` database file
    // beside this one. Nothing opens it, nothing reads it and nothing deletes
    // it: there is no migration (V2-D26), and deleting a file this build
    // cannot interpret would be destroying data on the strength of its name.
    final library = _library ??= LibraryDatabase();
    final fileStore = _fileStore ??= await FileStore.open();

    final browser = BrowserController();
    final settings = LocalSettingsStore(library);

    // Read before the app builds, not watched: the shell decides how to
    // composite the Browser on its first frame, and a capability that arrived
    // a frame later would flip that decision under a run.
    final multitasking =
        ForegroundMultitasking(
            ForegroundMultitasking.parse(
              await settings.get(ForegroundMultitasking.settingKey),
            ),
          )
          // The internal entitlement override. Read here so it is in force
          // before the first frame decides what the shell paints; in a
          // production build nothing can ever have written it.
          ..override = EntitlementOverride.parse(
            await settings.get(ForegroundMultitasking.overrideSettingKey),
          );

    _services = AppServices(
      fileStore: fileStore,
      browser: browser,
      foregroundMultitasking: multitasking,
    );

    // The repositories over the library, the queue worker and the check
    // controller — all sharing the one Browser and FileStore.
    final ui = libui.LibraryUiServices(library, fileStore: fileStore);
    // The one assist host, built here because the queue's worker and the save
    // sheet must hold the *same* one: a capture that stops to ask has to hold
    // on the controller the sheet is watching, or the question is asked into
    // a controller nobody renders.
    final assist = V2AssistController(
      browser: browser,
      hints: PageHintRepository.forLibrary(library),
    );
    final runner = QueueRunner(
      queue: ui.queue,
      // Routed through the assist path, which is the difference between a
      // capture that cannot find the reading area *asking* and one that simply
      // fails. The order, the counters and the re-run are v2_save_flow's.
      capture: (capture, task, {shouldContinue}) => v2CaptureWithAssist(
        capture: capture,
        assist: assist,
        entryId: task.entryId,
        locationId: task.locationId,
        locationUrl: task.locationUrl,
        captureMode: task.captureMode,
        captureModeIsUserSet: task.captureModeIsUserSet,
        shouldContinue: shouldContinue,
      ),
      captureServiceFor: () => EntryCaptureService(
        entries: ui.entries,
        collections: ui.collections,
        offlineCopies: ui.offline,
        fileStore: fileStore,
        source: SaveEnginePageCaptureSource(
          browser: browser,
          engineFor: (sink) => SaveEngine(
            browser: browser,
            fileStore: fileStore,
            downloader: AssetFetcher(
              browser: browser,
              config: kDefaultSaveConfig,
            ),
            sink: sink,
          ),
        ),
      ),
    );
    final check = CheckController(
      browser: browser,
      collections: ui.collections,
      entries: ui.entries,
      index: RecognitionIndex(library),
      observations: BrowserSourceObservationSource(browser),
    );
    final recogniser = Recogniser(
      index: RecognitionIndex(library),
      collections: ui.collections,
      reading: ReadingStateRepository(library),
    );
    final history = BrowsingHistoryStore(library);
    _v2 = V2Services(
      library: library,
      ui: ui,
      runner: runner,
      check: check,
      recogniser: recogniser,
      history: history,
      assist: assist,
      sync: SyncComposition(
        db: library,
        queue: ui.queue,
        // The gate on the network drain, and the only thing the sync stack is
        // told about what this user has. Local writes and the outbox are
        // never gated (V2-D7); this closure is asked at the drain and nowhere
        // else.
        cloudSyncAvailable: () => multitasking.cloudSyncAvailable,
        capabilityChanges: multitasking,
        transport: buildSyncTransport(),
      ),
    );

    // What the user reads is how the library stays current (V2-D13, F6). The
    // controller emits every completed load; only navigation the *user*
    // performed is acted on, and nothing here creates a library row.
    browser.onVisitCompleted = (visit) => unawaited(
      recordCompletedVisit(
        _v2!,
        url: visit.url,
        title: visit.title,
        // The controller emits automation's loads too, and the source is how
        // they are told apart.
        userInitiated: visit.source == NavigationSource.manual,
        requestedUrl: visit.requestedUrl,
      ).catchError((Object e) => debugPrint('[history] record failed: $e')),
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

  /// File-level recovery, before the UI is interactive.
  ///
  /// Both halves are the FileStore's, and both are device-validated: a kill
  /// between *step the old entry aside* and *move the new one in* leaves a
  /// `.previous` directory, and an interrupted capture leaves a staging tree.
  ///
  /// What is deliberately **not** here any more is V1's row reconciliation.
  /// That pass rebuilt library rows from the packages on disk, and V2 must not
  /// do it: an Entry is a synced library fact, and a package on one device is
  /// not evidence for one (V2-D22, I14) — a rebuild here would resurrect
  /// entries another device deleted. A package with no copy row is now
  /// reported by the storage survey as space the user can free, and a copy row
  /// with no package as a record they can forget
  /// (`lib/storage/cleanup.dart`). Nothing is decided at boot.
  Future<void> _recover() async {
    final fileStore = _fileStore!;

    // A kill between "step the old entry aside" and "move the new one in"
    // leaves a `.previous` directory; put it back before anything reads.
    final restored = await fileStore.restoreInterruptedReplacements();
    if (restored > 0) {
      debugPrint('[recovery] restored $restored interrupted replacement(s)');
    }

    final swept = await fileStore.sweepStaging();
    if (swept > 0) debugPrint('[recovery] swept $swept staging dir(s)');
  }

  /// Browsing-data retention.
  ///
  /// Nothing is seeded here. The saved-sites list starts empty and stays empty
  /// until the user puts something in it: a site the developer chose would be a
  /// recommendation the app is not entitled to make, and a bundled starting
  /// point is how a neutral reader acquires a provider catalogue by accident.
  Future<void> _browserData() async {
    final pruned = await _v2!.history.prune();
    if (pruned > 0) debugPrint('[history] pruned $pruned old visit(s)');
  }

  /// Demote any V2 save rows a kill left `running` back to `queued` — a
  /// resume OFFER, exactly as before: nothing autonomous starts at launch.
  Future<void> _pendingTasks() => _v2!.ui.queue.demoteInterruptedRuns();
}
