/// The shared boot for the V2 device suites.
///
/// **Why this exists.** Every retired V1 suite built its own three-line
/// composition — `AppServices(db:, fileStore:, browser:, saveRun:)` — because
/// V1's whole engine hung off one controller. V2's does not: the running app is
/// a `LibraryDatabase` beside the V1 `AppDatabase`, the repositories over it,
/// an `EntryCaptureService` built per capture through a `PageCaptureSource`, a
/// `QueueRunner` that drains the save queue, and a `CheckController` over the
/// recognition pipeline. Eleven suites each rebuilding that by hand is eleven
/// chances to build something that is not the app.
///
/// So this file boots **the production composition**, assembled exactly as
/// `lib/main.dart`'s `AppStartup._open` assembles it, and hands the suites the
/// same object graph the user's app runs on. Nothing here is a stub, a fake or
/// a shortcut: the only differences from `main()` are the database names (so
/// suites do not share state), the file-store folder, and the two observation
/// hooks below.
///
/// **The two observation hooks are production seams, not test scaffolding.**
/// `SaveEngine` already publishes `onProgress` and `onLog`, and `main()` simply
/// passes neither. The harness passes both, which is how a device suite can
/// still assert on `SaveState.waitingForBrowser` — the hold that the whole
/// foreground-multitasking claim turns on — now that V2's queue reports only
/// *running* and *not running*. Reading a state the engine already publishes is
/// not weakening an assertion; inventing a flag in `lib/` to read it would be.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/asset_origin_repository.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/domain.dart';
import 'package:web_reader/features/check_controller.dart';
import 'package:web_reader/features/source_observation_browser.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/rendered_consent.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../../tool/fixture/fixture_site.dart';

/// The fixture's own vocabulary, so a suite naming the deliberately broken
/// entry says `kBrokenEntry` rather than `2`.
export '../../tool/fixture/fixture_site.dart'
    show
        kBrokenEntry,
        kBrokenPanel,
        kContentImagesPerEntry,
        kEntryCount,
        kMinBoxPanelPath,
        kSlowPanel;

/// Whether any widget tree has been pumped in this process yet. `pump` before
/// the first `pumpWidget` has nothing to pump.
bool _anyTreeMounted = false;

/// Unique per process: a run that is killed mid-way never uninstalls the app,
/// so a fixed name would leak rows into the next invocation.
final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

/// How many content panels one fixture entry holds. Mirrors
/// `kContentImagesPerEntry`, named here so a suite reads in its own vocabulary.
const int kFixtureImagesPerEntry = kContentImagesPerEntry;

/// The in-process fixture site, on loopback.
///
/// Served **in the app process on the device**, exactly as the retired suites
/// did, which is what makes "the source is gone" provable rather than asserted:
/// [stop] destroys the origin, and everything the reader then shows came off
/// disk.
class FixtureSite {
  FixtureSite({this.applyDelays = true, this.entryCount = kEntryCount});

  /// Panel 4 of every entry is served two seconds late while this is true —
  /// the fixture's proof that "loaded" never means "finished".
  bool applyDelays;

  /// How many entries the "site" publishes. Raised mid-test to make a source
  /// publish new entries under a check.
  int entryCount;

  HttpServer? _server;
  String _base = '';

  /// The origin, once [start] has run.
  String get base => _base;

  String entry(int n) => '$_base/entry/$n';

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _base = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      try {
        await for (final request in server) {
          try {
            await handleFixtureRequest(
              request,
              applyDelays: applyDelays,
              entryCount: entryCount,
            );
          } catch (_) {
            /* the client went away */
          }
        }
      } catch (_) {
        /* the server closed */
      }
    }());
    debugPrint('[fixture] serving on $_base');
  }

  /// Force, always: `/hang/…` responses are deliberately never closed, so a
  /// graceful close would wait for sockets the fixture is holding open on
  /// purpose.
  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close(force: true);
    debugPrint('[fixture] STOPPED — the source no longer exists');
  }

  /// Is the origin actually answering? Asked rather than assumed, because
  /// "offline" is the claim under test.
  Future<bool> reachable() async {
    if (_base.isEmpty) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$_base/entry/1'));
      final response = await request.close();
      await response.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

/// The V2 app, composed as `main()` composes it, plus the engine observation
/// the device suites need.
class V2App {
  V2App({
    required this.tag,
    this.multitaskingPreference = false,
    this.entitlement = EntitlementOverride.production,
    this.observationsOver,
  });

  /// Names the databases and the store folder. A suite that boots twice over
  /// the same tag is restarting the app against the same container, which is
  /// exactly what the persistence scenarios need.
  final String tag;

  /// What the user asked for. Note that this alone is not the capability:
  /// [ForegroundMultitasking.enabled] is preference **and** entitlement, so a
  /// multitasking arm also passes [EntitlementOverride.forcePro].
  final bool multitaskingPreference;

  /// The internal build's pretend entitlement. Honoured only because
  /// `kInternalBuild` is true in the debug build an integration test runs in —
  /// a Store build folds it away entirely.
  final EntitlementOverride entitlement;

  /// Wraps the check's observation source. Null — the default, and what every
  /// suite but `update_check_test.dart` uses — builds the production
  /// [BrowserSourceObservationSource] directly.
  ///
  /// It exists for exactly one reason, spelled out in that suite's header: a
  /// Source's identity is `(host, path_key)` and carries neither scheme nor
  /// port, so the production code has no way to name a loopback origin. Nothing
  /// else in this harness substitutes any part of the app.
  final SourceObservationSource Function(BrowserController browser)?
  observationsOver;

  late LibraryDatabase library;
  late FileStore fileStore;
  late BrowserController browser;
  late libui.LibraryUiServices ui;
  late QueueRunner runner;
  late CheckController check;
  late ForegroundMultitasking capability;
  late V2Services v2;
  late AppServices services;

  /// Every state the ported save engine passed through since [boot].
  ///
  /// The engine's own `onProgress`, which `main()` does not subscribe to. This
  /// is the only honest way to assert the hold: `QueueRunner.isRunning` cannot
  /// tell "reading the page" from "waiting for the app to draw it", and it
  /// deliberately does not try — the panel and the indicator read the surface
  /// flag instead.
  final Set<SaveState> engineStates = <SaveState>{};

  /// The engine's log, newest last. Dumped on teardown, because when a save
  /// assertion fails this is the only thing that explains why.
  final List<String> engineLog = <String>[];

  /// What the stood-in consent dialog answers, and how often it was shown.
  ///
  /// The count is the assertion that matters: a Source is asked **once**, and
  /// the second Entry from it reads the stored answer instead of asking again.
  bool renderedFallbackAnswer = true;
  int renderedFallbackPrompts = 0;

  SaveProgress _progress = const SaveProgress();

  /// The engine's last published progress.
  SaveProgress get progress => _progress;

  /// Did any capture since [resetObservations] have to hold for the Browser?
  bool get everHeldForBrowser =>
      engineStates.contains(SaveState.waitingForBrowser);

  void resetObservations() {
    engineStates.clear();
    engineLog.clear();
    _progress = const SaveProgress();
  }

  /// Build the whole graph and pump the real app.
  ///
  /// Not `pumpAndSettle`: the Browser tab hosts a live WebView, which never
  /// settles. Every wait in this file is on a clock or a condition.
  Future<void> boot(WidgetTester tester) async {
    // Let whatever is still up finish before this tree replaces it.
    //
    // The shell refreshes the device-capacity figure the moment work falls
    // idle, and `DeviceCapacityController.refresh` assigns `state` after an
    // await with no `ref.mounted` check
    // (lib/core/device_capacity_provider.dart:53), so a scope disposed while
    // that is in flight throws `UnmountedRefException` — on whichever case
    // happens to be next. Pumping the live tree is what gives it somewhere to
    // land.
    //
    // **One boot per case, and no relaunch inside one.** Three shapes of
    // in-test restart were tried on both platforms and none of them holds:
    //
    // * pumping an empty tree between the two apps unmounts the
    //   `InAppWebView` on its own, which trips the plugin's
    //   `AndroidFindInteractionController was used after being disposed` and
    //   takes the connection to the app down with it;
    // * closing the databases and reopening them without rebuilding the tree
    //   deadlocks — drift keys its connection by database name, and a close a
    //   live query stream is holding open leaves the next handle over the same
    //   name waiting forever;
    // * closing them *and* rebuilding the tree hangs on iOS and crashes the
    //   app on Android, for the two reasons above together.
    //
    // So durability is asserted the way it can honestly be asserted in-process:
    // through [freshLibraryReads], repositories built after the write, which
    // proves the value reached the database rather than living in the object
    // that wrote it. The process-level claim — a cold start over an existing
    // container — is what a *separate* `flutter test` invocation makes, and
    // that is where it belongs.
    //
    // The closes in [shutdown] stay bounded regardless, because a harness that
    // waits silently is the failure `device_harness.dart` exists to prevent.
    if (_anyTreeMounted) await pumpFor(tester, const Duration(seconds: 3));

    library = LibraryDatabase(name: 'it_lib_$tag');
    fileStore = await FileStore.open(folderName: 'webread_it_$tag');
    browser = BrowserController();
    ui = libui.LibraryUiServices(library, fileStore: fileStore);

    runner = QueueRunner(
      queue: ui.queue,
      captureServiceFor: () => EntryCaptureService(
        entries: ui.entries,
        collections: ui.collections,
        offlineCopies: ui.offline,
        fileStore: fileStore,
        capturePreferences: CapturePreferenceStore(library),
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
            // The same memory the app composes, so a device suite exercises
            // what the user's build actually does about a refusing host.
            assetOrigins: AssetOriginRepository(library),
            // The **real** gate, over the real store, with the shell's dialog
            // stood in for by [renderedFallbackAnswer]. A suite therefore
            // exercises what the app does — asked once, remembered, and the
            // next Entry from that Source not asked again — rather than a
            // shortcut past the question.
            renderedConsent: RenderedFallbackGate(
              index: RecognitionIndex(library),
              store: RenderedFallbackConsentStore(LocalSettingsStore(library)),
              ask: (url) async {
                renderedFallbackPrompts++;
                return renderedFallbackAnswer;
              },
            ).call,
            onProgress: _onEngineProgress,
            onLog: _onEngineLog,
          ),
        ),
      ),
    );
    check = CheckController(
      browser: browser,
      collections: ui.collections,
      entries: ui.entries,
      index: RecognitionIndex(library),
      observations:
          observationsOver?.call(browser) ??
          BrowserSourceObservationSource(browser),
    );
    capability = ForegroundMultitasking(multitaskingPreference)
      ..override = entitlement;
    services = AppServices(
      fileStore: fileStore,
      browser: browser,
      foregroundMultitasking: capability,
    );
    final recogniser = Recogniser(
      index: RecognitionIndex(library),
      collections: ui.collections,
      reading: ReadingStateRepository(library),
    );
    final assist = V2AssistController(
      browser: browser,
      hints: PageHintRepository.forLibrary(library),
    );
    v2 = V2Services(
      library: library,
      ui: ui,
      runner: runner,
      check: check,
      assist: assist,
      recogniser: recogniser,
      history: BrowsingHistoryStore(library),
      // No service in the device suites: the resolver answers null, the
      // outbox journals, nothing leaves the device.
      sync: SyncComposition(
        db: library,
        queue: ui.queue,
        cloudSyncAvailable: () => capability.cloudSyncAvailable,
        capabilityChanges: capability,
        transport: null,
      ),
    );

    // The same resume OFFER `main()` makes: a row a kill left `running` goes
    // back to `queued`, and nothing autonomous starts.
    await ui.queue.demoteInterruptedRuns();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          v2ServicesProvider.overrideWithValue(v2),
          libui.libraryUiServicesProvider.overrideWithValue(ui),
          libui.fileStoreProvider.overrideWithValue(fileStore),
          libui.entryOpenerProvider.overrideWithValue(
            (id) async => v2.openEntry?.call(id),
          ),
          libui.sourceOpenerProvider.overrideWithValue(
            (url) async => v2.openSource?.call(url),
          ),
          libui.saveQueueStarterProvider.overrideWithValue(
            ({decided}) async => v2.startQueue?.call(decided: decided),
          ),
          libui.collectionCheckerProvider.overrideWithValue(
            (id, name) async => v2.checkCollection?.call(id, name),
          ),
          libui.placementSubmitProvider.overrideWithValue(
            placementSubmitFor(v2),
          ),
        ],
        child: const WebReaderApp(),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 3));
    _anyTreeMounted = true;

    // Give the shell's unawaited work somewhere to land before the framework
    // takes the tree away.
    //
    // `_onAutomationChanged` refreshes the device-capacity figure the moment an
    // operation falls idle, and `DeviceCapacityController.refresh` assigns
    // `state` after an await with **no `ref.mounted` check**
    // (lib/core/device_capacity_provider.dart:53). A scope disposed while that
    // is in flight throws `UnmountedRefException`, which flutter_test then
    // attributes to whichever case had just finished — failing a case whose own
    // assertions all passed.
    //
    // Registered here rather than in the suite's `tearDown` because
    // `addTearDown` callbacks run *before* the binding tears the tree down,
    // which is the only window where pumping still helps. The defect is
    // reported, not hidden: this only stops it landing on an unrelated case.
    addTearDown(() => pumpFor(tester, const Duration(seconds: 3)));
  }

  void _onEngineProgress(SaveProgress Function(SaveProgress) update) {
    _progress = update(_progress);
    engineStates.add(_progress.state);
  }

  void _onEngineLog(String line) {
    engineLog.add(line);
    debugPrint('[engine] $line');
  }

  /// Stop everything that could still be driving the WebView, then close the
  /// databases.
  ///
  /// Order matters: closing a connection under a live capture throws *after*
  /// the test has already passed, which reads as a failure and is not one.
  Future<void> shutdown({bool dumpLog = true}) async {
    check.cancel();
    for (final task in await ui.queue.pending()) {
      await ui.queue.cancel(task.id);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while ((runner.isRunning || check.isRunning) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Two pieces of unawaited work have to land before the tree goes away.
    //
    // A favicon fetch kicked off by a page load writes to the database without
    // anyone awaiting it, and closing the connection under it throws *after*
    // the test has already passed — which reads as a failure and is not one.
    //
    // The shell also refreshes the device-capacity figure the moment work falls
    // idle, and `DeviceCapacityController.refresh` assigns `state` after an
    // await with no `ref.mounted` check — so replacing the widget tree while
    // that is in flight throws `UnmountedRefException`. That is a defect in
    // `lib/core/device_capacity_provider.dart:53`, reported rather than
    // swallowed; waiting here is what stops it landing on an unrelated case.
    await Future<void>.delayed(const Duration(seconds: 4));
    if (dumpLog) {
      for (final line in engineLog) {
        debugPrint('[engine] $line');
      }
    }
    await _closeQuietly(library.close, 'library');
  }

  /// Close a database, and **give up rather than hang**.
  ///
  /// Measured on both platforms: closing a drift database while the app tree is
  /// still mounted and subscribed to its query streams sometimes never returns.
  /// A harness that waits silently for that is the exact failure
  /// `device_harness.dart` exists to prevent — three device runs were lost to
  /// one — so the wait is bounded and says where it gave up. The handle is
  /// abandoned, which costs nothing: the process is about to move on to a
  /// database with a different name, or end.
  static Future<void> _closeQuietly(
    Future<void> Function() close,
    String what,
  ) async {
    try {
      await close().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[harness] !! the $what database did not close — moving on');
    } catch (_) {
      /* already closed */
    }
  }

  // --- library set-up -------------------------------------------------------

  /// Put [url] in the library as an Entry with a Location, and queue a save for
  /// it — the two halves of what the Browser's save sheet does, without needing
  /// the sheet to be on screen.
  ///
  /// Deliberately goes through the real repositories and the real queue, so the
  /// row a suite then starts is the row the app would have written. Returns the
  /// Entry id.
  Future<String> queueSaveOf(
    String url, {
    String title = '',
    String? collectionId,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    final id = await addEntry(url, title: title, collectionId: collectionId);
    final result = await ui.queue.enqueue(
      entryId: id.entryId,
      locationId: id.locationId,
      locationUrl: url,
      // Null is a real answer — "decide from the settled page" — and never a
      // default about what to take off someone else's site.
      captureMode: captureMode,
      captureModeIsUserSet: captureModeIsUserSet,
    );
    expect(
      result.refusedReason,
      isNull,
      reason: 'the fixture host must never be refused by the capture policy',
    );
    return id.entryId;
  }

  /// An Entry with one Location, standalone unless [collectionId] names a
  /// Collection.
  Future<({String entryId, String locationId})> addEntry(
    String url, {
    String title = '',
    String? collectionId,
  }) async {
    // **An address the library already holds is that Entry, not a new one.**
    // `url_key` is unique within a library (I-invariants), so a suite that
    // seeded a Collection's Locations and then asked to queue one of them was
    // refused with "url_key is unique within a library" — a harness
    // assumption, not a product rule. Reusing what is there is also what the
    // app itself does on this path.
    final held = await RecognitionIndex(library).lookupUrl(normalizeUrl(url));
    if (held != null) {
      return (entryId: held.entry.id, locationId: held.location.id);
    }
    final root = await ui.folders.ensureRoot();
    final (entry, violation) = collectionId == null
        ? await ui.entries.createStandalone(
            folderId: root.id,
            title: title.isEmpty ? url : title,
          )
        : await ui.entries.createInCollection(
            collectionId: collectionId,
            placement: Placement.unplaced,
            title: title.isEmpty ? url : title,
          );
    expect(
      entry,
      isNotNull,
      reason: 'entry not created: ${violation?.message}',
    );
    final (location, locationViolation) = await ui.entries.addLocation(
      entryId: entry!.id,
      url: url,
      urlKey: normalizeUrl(url),
      discoveryBasis: 'userSave',
    );
    expect(
      location,
      isNotNull,
      reason: 'location not added: ${locationViolation?.message}',
    );
    return (entryId: entry.id, locationId: location!.id);
  }

  // --- reads ----------------------------------------------------------------

  /// Repositories built **now**, over the same database.
  ///
  /// What a durability assertion can honestly claim in-process: a value read
  /// back through an object that did not write it came from the database, not
  /// from the writer's memory. It is weaker than a cold start and says so — see
  /// the note in [boot] for why a cold start is not reachable from inside a
  /// single `flutter test` run.
  libui.LibraryUiServices freshLibraryReads() =>
      libui.LibraryUiServices(library, fileStore: fileStore);

  /// The manifest of the Entry's active offline copy, or null when this device
  /// holds none.
  Future<EntryManifest?> manifestOf(String entryId) async {
    final copy = await ui.offline.activeCopyOf(entryId);
    if (copy == null) return null;
    return fileStore.readManifest(copy.contentPath);
  }

  /// How many images this device actually stored for the Entry. -1 when there
  /// is no copy at all, which is a different answer from 0.
  Future<int> storedImagesOf(String entryId) async {
    final manifest = await manifestOf(entryId);
    return manifest?.storedAssetCount ?? -1;
  }

  Future<SaveTask?> taskFor(String entryId) => ui.queue.openTaskFor(entryId);

  /// The newest row for an Entry, open or terminal.
  Future<SaveTask?> latestTaskFor(String entryId) async {
    final rows = [
      for (final task in await ui.queue.all())
        if (task.entryId == entryId) task,
    ];
    return rows.isEmpty ? null : rows.last;
  }
}

// --- pumping ----------------------------------------------------------------

/// Pump for a span of wall clock.
///
/// `pumpAndSettle` is never usable here: the WebView is a platform view with a
/// continuous presentation, so settling never happens and the call hangs.
Future<void> pumpFor(WidgetTester tester, Duration span) async {
  final deadline = DateTime.now().add(span);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Pump until [done], and **fail** if it never comes true.
///
/// A bounded wait that then asserts, rather than one that returns quietly: a
/// suite that carries on past an unmet precondition reports the wrong failure.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(minutes: 3),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  expect(done(), isTrue, reason: reason ?? 'timed out waiting');
}

/// Pump until [done], reporting whether it came true. For a scenario that
/// decides for itself what a false answer means.
Future<bool> pumpWhile(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  return done();
}

// --- navigation -------------------------------------------------------------

/// The bottom bar's Browser tab. Present on every shell frame, which is why it
/// is also the thing a route push is anchored to.
final Finder browserTab = find.byKey(const ValueKey('navTab-Browser'));

/// The bottom bar's Library tab.
final Finder libraryTab = find.byKey(const ValueKey('navTab-Library'));

/// Show the Browser tab.
///
/// A WKWebView that has never been painted reports zero layout metrics, so
/// every suite that measures a page does this first — exactly as a user
/// probing a page would be doing.
Future<void> showBrowser(WidgetTester tester) async {
  await tester.tap(browserTab, warnIfMissed: false);
  await pumpFor(tester, const Duration(milliseconds: 800));
}

/// Show the Library tab, answering the leave-Browser sheet if it appears.
///
/// *Pause and leave* is the one answer offered to everyone, whatever the
/// build's entitlement, so it is the one a harness may press.
Future<bool> showLibrary(WidgetTester tester) async {
  await tester.tap(libraryTab, warnIfMissed: false);
  await pumpFor(tester, const Duration(milliseconds: 800));
  final leave = find.byKey(const ValueKey('leavePauseAndLeave'));
  if (leave.evaluate().isEmpty) return false;
  await tester.tap(leave, warnIfMissed: false);
  await pumpFor(tester, const Duration(milliseconds: 800));
  return true;
}

/// A mounted element to read the router and the provider container from.
///
/// **Not the bottom bar alone.** It was chosen as "the one thing that is never
/// offstage", and that is true only while the shell is the top route: the
/// reader is pushed *over* it, and while the reader is up the tab bar is not
/// in the tree at all — so any helper anchored on it threw `Bad state: No
/// element` on exactly the assertions that are about leaving the shell. The
/// shell is preferred when it is there, and whatever is on top of it is used
/// when it is not.
Element appAnchor(WidgetTester tester) {
  for (final finder in [libraryTab, browserTab, find.byType(Navigator)]) {
    final found = finder.evaluate();
    if (found.isNotEmpty) return found.first;
  }
  // Nothing mounted at all is a real failure, and this reports it as one.
  return tester.element(libraryTab);
}

/// Push the reader over the shell, the way the app's own entry opener does.
Future<void> openReader(WidgetTester tester, String entryId) async {
  GoRouter.of(appAnchor(tester)).push('/reader/$entryId');
  await pumpFor(tester, const Duration(seconds: 3));
}

/// Pop whatever is above the shell.
Future<void> popRoute(WidgetTester tester) async {
  final router = GoRouter.of(appAnchor(tester));
  if (router.routerDelegate.currentConfiguration.matches.length <= 1) return;
  router.pop();
  await pumpFor(tester, const Duration(seconds: 2));
}

// --- starting queued work ---------------------------------------------------

/// Press Start, and answer the foreground gate with the one option every build
/// offers.
///
/// Goes through `V2Services.startQueue` — the shell's `_startQueuedDownloads`,
/// which is **the only place V2 Browser automation is authorised from**. A
/// suite that called `QueueRunner.start()` directly would be testing the worker
/// loop while skipping the authorisation that makes it legitimate, and the
/// explicit Start is the product rule, not an implementation detail.
///
/// *Start in Browser* rather than *keep using the app*: it is offered whatever
/// the entitlement, so one helper works for the Free arm and the Pro arm alike.
/// A suite that wants the multitasking start presses [startQueueKeepingApp].
Future<void> startQueue(WidgetTester tester, V2App app) async {
  final starter = app.v2.startQueue;
  expect(starter, isNotNull, reason: 'the shell wires the queue starter');
  unawaited(starter!());
  await pumpFor(tester, const Duration(seconds: 2));
  final inBrowser = find.byKey(const ValueKey('startInBrowser'));
  expect(
    inBrowser,
    findsOneWidget,
    reason: 'the start sheet offers the visible-Browser start to everyone',
  );
  await tester.tap(inBrowser, warnIfMissed: false);
  await pumpFor(tester, const Duration(seconds: 3));
}

/// Press Start and choose to keep using the app — the Pro path.
///
/// Only ever offered when the capability is available *and* the preference is
/// on; a suite that presses this without both has arranged its arm wrongly and
/// the missing key says so.
Future<void> startQueueKeepingApp(WidgetTester tester, V2App app) async {
  final starter = app.v2.startQueue;
  expect(starter, isNotNull, reason: 'the shell wires the queue starter');
  unawaited(starter!());
  await pumpFor(tester, const Duration(seconds: 2));
  final keep = find.byKey(const ValueKey('startKeepUsingApp'));
  expect(
    keep,
    findsOneWidget,
    reason:
        'the multitasking start is offered only with Pro and the preference '
        'on — check the arm this suite booted',
  );
  await tester.tap(keep, warnIfMissed: false);
  await pumpFor(tester, const Duration(seconds: 3));
}

/// Wait for the queue to drain, or fail saying it did not.
Future<void> awaitQueueIdle(
  WidgetTester tester,
  V2App app, {
  Duration timeout = const Duration(minutes: 4),
}) => pumpUntil(
  tester,
  () => !app.runner.isRunning,
  timeout: timeout,
  reason: 'the queue never fell idle',
);

/// Open [url] the way the app opens every page: through [BrowserNavigator].
///
/// **Not `BrowserController.loadAndWait`.** The Browser boots on Browser Home,
/// which is a local surface drawn *over* the still-mounted WebView — so loading
/// straight into the controller leaves the page rendering behind an overlay,
/// with the save control, the page actions and everything else reporting a page
/// the user cannot see. That is precisely the state
/// `PendingOpenDrainer.reveal` exists to prevent, and the drainer is what the
/// whole app goes through. A suite that drives the Browser's own controls has
/// to arrive the same way.
Future<void> openPage(WidgetTester tester, V2App app, String url) async {
  final container = ProviderScope.containerOf(tester.element(libraryTab));
  container.read(browserNavigatorProvider).request(url);
  container.read(shellTabRequestProvider).value = 1;
  await pumpFor(tester, const Duration(seconds: 1));
  final presentation = container.read(browserPresentationProvider);
  await pumpUntil(
    tester,
    () =>
        !presentation.hasLocalSurface &&
        !app.browser.isLoading &&
        app.browser.currentUrl.isNotEmpty,
    timeout: const Duration(seconds: 45),
    reason: 'the Browser never revealed and settled on $url',
  );
  await pumpFor(tester, const Duration(seconds: 2));
}

// --- the one substitution in this harness -----------------------------------

/// Supplies a listing origin where a Source cannot carry one.
///
/// **This stands in for a missing seam in `lib/`, and for nothing else.**
/// `BrowserSourceObservationSource.observe` reconstructs the first page of a
/// Source's listing as `'https://${source.host}${source.pathKey}'`. A Source's
/// identity is `(host, path_key)` (V2-D15) and carries neither the scheme nor
/// the port, so there is no way to name an origin that is not default-port
/// HTTPS — including this project's own in-process fixture, which is
/// `http://127.0.0.1:<port>`.
///
/// When [pageUrl] is null — the one case the production code has to invent an
/// address for — this hands the production implementation the fixture origin
/// plus the Source's own `pathKey`. Every other call, and **every judgement**,
/// is the production implementation's: the real navigation, the real
/// landed-URL policy boundary, the real settled-page probe, the real listing
/// extraction, the real ordering-confidence rule.
///
/// Delete this in the same change that lets a Source name its own origin.
class FixtureOriginObservations implements SourceObservationSource {
  FixtureOriginObservations(this._inner, this._origin, {this.beforeObserve});

  final SourceObservationSource _inner;
  final String _origin;

  /// Called at the boundary immediately before a page is read.
  ///
  /// Not a stub of anything: it is *when the user presses Stop*. A suite that
  /// wanted to cancel a check mid-reading would otherwise have to race a
  /// wall-clock delay against a page load, and a timing-dependent assertion
  /// about a cooperative stop proves nothing on a slow device. What happens
  /// after this returns is entirely the production implementation's — it asks
  /// `shouldContinue()` first thing, exactly as it does for a real Stop.
  final void Function()? beforeObserve;

  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) {
    beforeObserve?.call();
    return _inner.observe(
      source: source,
      pageUrl: pageUrl ?? '$_origin${source.pathKey}',
      shouldContinue: shouldContinue,
    );
  }
}

/// Build the check's observation source over [fixture]'s origin.
SourceObservationSource Function(BrowserController) fixtureObservations(
  FixtureSite fixture, {
  void Function()? beforeObserve,
}) =>
    (browser) => FixtureOriginObservations(
      BrowserSourceObservationSource(browser),
      fixture.base,
      beforeObserve: beforeObserve,
    );
