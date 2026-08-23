import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser/browser_controller.dart';
import 'capability/foreground_multitasking.dart';
import 'browser/browser_navigator.dart';
import 'browser/browser_presentation.dart';
import 'browser/favicon_service.dart';
import 'browser/browsing_history.dart';
import 'browser/saved_sites_repository.dart';
import 'data/local_settings.dart';
import 'data/schema.dart' show HistoryRow, SavedSiteRow;
import 'features/check_controller.dart';
import 'features/v2_composition.dart';
import 'library_ui/providers.dart'
    show libraryDatabaseProvider, libraryUiServicesProvider;
import 'save/capture_preference.dart';
import 'save/queue_runner.dart';
import 'storage/cleanup.dart';
import 'storage/file_store.dart';
import 'ui/theme.dart';

/// Set once during bootstrap, before `runApp`.
class AppServices {
  AppServices({
    required this.fileStore,
    required this.browser,
    ForegroundMultitasking? foregroundMultitasking,
  }) : foregroundMultitasking =
           foregroundMultitasking ?? ForegroundMultitasking();

  final FileStore fileStore;
  final BrowserController browser;

  /// The one place that answers whether an operation may keep running while
  /// the user is elsewhere in the app.
  final ForegroundMultitasking foregroundMultitasking;
}

final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final fileStoreProvider = Provider<FileStore>(
  (ref) => ref.watch(appServicesProvider).fileStore,
);

final browserProvider = Provider<BrowserController>(
  (ref) => ref.watch(appServicesProvider).browser,
);

final foregroundMultitaskingProvider = Provider<ForegroundMultitasking>((ref) {
  try {
    return ref.watch(appServicesProvider).foregroundMultitasking;
  } catch (_) {
    // Widget tests override the database and file store only. A capability
    // built here holds its default, which is what a screen under test should
    // see: off, and therefore no behaviour change at all.
    final capability = ForegroundMultitasking();
    ref.onDispose(capability.dispose);
    return capability;
  }
});

/// Freeing what this device is holding: the copy rows and the packages behind
/// them.
///
/// Built from the V2 services rather than held on [AppServices], because every
/// input it has — the copies, the entries, the reading state and the file
/// store — belongs to the library composition, and a second holder is a second
/// answer waiting to disagree.
final cleanupProvider = Provider<CleanupService>((ref) {
  final services = ref.watch(libraryUiServicesProvider);
  return CleanupService(
    offlineCopies: services.offline,
    entries: services.entries,
    collections: services.collections,
    reading: services.reading,
    fileStore: services.fileStore,
  );
});

/// The device's small key-value settings.
final localSettingsProvider = Provider<LocalSettingsStore>(
  (ref) => LocalSettingsStore(ref.watch(libraryDatabaseProvider)),
);

/// What each Collection is normally captured as.
///
/// Over the same settings table: a capture preference is an application fact
/// about a Collection, not a library one, and the frozen schema has no column
/// for it and needs none.
final capturePreferenceProvider = Provider<CapturePreferenceStore>(
  (ref) => CapturePreferenceStore(ref.watch(localSettingsProvider)),
);

/// What this device is holding, from the copy rows alone.
///
/// Cheap and reactive, and deliberately *not* the storage survey: the survey
/// also walks the library tree to find where the rows and the disk disagree,
/// and no screen but Storage may wait on a recursive listing to draw a line
/// of text. The two can differ, and where they do the Storage screen is the
/// one that says so.
final offlineHoldingsProvider = StreamProvider<({int bytes, int entries})>((
  ref,
) {
  final db = ref.watch(libraryDatabaseProvider);
  final query = db.select(db.offlineCopies)
    ..where((c) => c.active.equals(true));
  return query.watch().map(
    (rows) => (
      bytes: rows.fold<int>(0, (sum, row) => sum + row.byteSize),
      entries: rows.length,
    ),
  );
});

/// The persisted appearance preference (default: follow the system).
final appearanceProvider = StreamProvider<AppearanceMode>(
  (ref) => ref
      .watch(localSettingsProvider)
      .watch(kAppearanceSettingKey)
      .map(appearanceFromName),
);

Future<void> setAppearance(WidgetRef ref, AppearanceMode mode) =>
    ref.read(localSettingsProvider).set(kAppearanceSettingKey, mode.name);

/// The Browser's place in the shell's bottom bar.
///
/// Written out as a name where new code reads it; the literal `1` still
/// appears at the older call sites and means the same thing.
const int kBrowserTabIndex = 1;

/// One-shot requests to switch the shell's bottom tab (0 = Library,
/// 1 = Browser). Written by widgets that live inside a tab (the activity
/// strip's "Open Browser" action for a save holding on a hidden WebView);
/// consumed by the shell, which owns the index.
final shellTabRequestProvider = Provider<ValueNotifier<int?>>((ref) {
  final notifier = ValueNotifier<int?>(null);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Which tab the shell is showing, published by the shell itself.
///
/// The read side of [shellTabRequestProvider]: a request says "go here", this
/// says "you are here". The Library-check foreground flow needs the second to
/// record where the user was when they started — so "the run brought the
/// Browser forward" is something it knows rather than assumes. Defaults to
/// the Library, which is where the shell starts and what a test without a
/// shell should see.
final shellTabProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// True while the app must keep painting the Browser's WebView even though
/// the user is looking at something else.
///
/// Written by exactly one owner — the app root, which is the only thing that
/// can see the capability, the running operations, the shell's tab and the
/// route stack at once. Read by the shell (what to draw) and by every route
/// pushed above it (whether to be opaque). Defaults to false, which is
/// the behaviour that shipped before this existed.
final keepBrowserPaintedProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier<bool>(false);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// A multitasking start has asked for the Browser surface, and the operation
/// that asked does not exist yet.
///
/// The gap is real and unavoidable: the shell has to bring the WebView up
/// *before* the queue claims a task, and until that claim happens nothing owns
/// the Browser — so the ownership test the surface rule runs would say no and
/// the page would never be drawn. Counted as ownership for exactly as long as
/// the start takes, then released by the first real owner (or by the shell's
/// fallback timer, so a start that never happens cannot hold it).
final pendingSurfaceClaimProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier<bool>(false);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// True when the Browser is what the user is looking at — its tab is selected
/// and nothing is stacked over the shell.
///
/// Written by the same owner as [keepBrowserPaintedProvider]. Read by the
/// running-operation indicator, which stays out of the Browser's way because
/// the Browser already reports the same run in full.
final browserOnScreenProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier<bool>(false);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// True when the app is actually compositing the WebView.
///
/// The same value the shell publishes to [BrowserController.surfaceIsPainted],
/// exposed here as well because it is what *held* means: the ported engine's
/// render guards stop a capture the moment its surface stops painting and
/// resume when it returns, so there is no pause flag to read and deliberately
/// should not be one. Written by the same owner as [keepBrowserPaintedProvider]
/// and read by the running-operation indicator, which floats above the router
/// and must not reach into `AppServices` to answer a question the shell has
/// already answered.
final browserSurfacePaintedProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier<bool>(true);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// True unless the Reader is hiding its chrome.
///
/// The Reader is the one writer: it publishes its own bar visibility here and
/// restores `true` on the way out. Read by the running-operation indicator,
/// which floats above the router and therefore cannot see the Reader's state
/// any other way — the bars and the indicator hide and return together, on the
/// Reader's own tap, rather than each keeping a timer and disagreeing.
///
/// Starts true, which is the honest answer on every screen that is not a
/// Reader and what a test without one should see.
class ReaderChromeVisibility extends ValueNotifier<bool> {
  ReaderChromeVisibility() : super(true);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Write the flag.
  ///
  /// Safe from a lifecycle edge, which is the whole reason it exists rather
  /// than a bare setter: an unchanged value notifies nobody, and a Reader
  /// leaving restores this one frame later — by which time the container may
  /// already be gone, which is exactly what a widget test does on teardown.
  void publish(bool visible) {
    if (_disposed || value == visible) return;
    value = visible;
  }
}

final readerChromeVisibleProvider = Provider<ReaderChromeVisibility>((ref) {
  final notifier = ReaderChromeVisibility();
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The Library-wide check the user started, and what its presentation owns.
///
// --- browser (M18) ---------------------------------------------------------

/// Browsing history: the V2 `history` table, which is the one the recognition
/// pipeline reads too. There is no second one.
final historyRepositoryProvider = Provider<BrowsingHistoryStore>(
  (ref) => ref.watch(v2ServicesProvider).history,
);

final savedSitesRepositoryProvider = Provider<SavedSitesRepository>(
  (ref) => SavedSitesRepository(ref.watch(libraryDatabaseProvider)),
);

/// One instance per app, so the icon a list fetched is the icon every other
/// list already has.
final faviconServiceProvider = Provider<FaviconService>((ref) {
  final service = FaviconService(db: ref.watch(libraryDatabaseProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Which local surface the Browser is showing. Outside the widget because
/// Settings → Saved sites opens Browser Home from another route entirely.
final browserPresentationProvider = Provider<BrowserPresentation>((ref) {
  final presentation = BrowserPresentation();
  ref.onDispose(presentation.dispose);
  return presentation;
});

/// The hand-off for "open this page in the Browser", from anywhere.
///
/// Long-lived and outside the widget tree on purpose: the request has to
/// survive the route pop and tab switch that happen between asking and the
/// Browser being on screen.
final browserNavigatorProvider = Provider<BrowserNavigator>((ref) {
  final navigator = BrowserNavigator();
  ref.onDispose(navigator.dispose);
  return navigator;
});

/// The saved-site grid, hand-ordered.
final savedSitesProvider = StreamProvider<List<SavedSiteRow>>(
  (ref) => ref.watch(savedSitesRepositoryProvider).watchAll(),
);

/// Manual browsing history, newest first and bounded — the History screen
/// and Browser Home's "recently visited" both read this one stream, so a
/// cleared range disappears from both at once with no cache to invalidate.
final browsingHistoryProvider = StreamProvider<List<HistoryRow>>(
  (ref) => ref
      .watch(historyRepositoryProvider)
      .watchRecent(limit: kHistoryStreamLimit),
);

/// How many rows the shared history stream carries.
///
/// Bounded on purpose: Browser Home shows four, the History screen pages
/// through what a person can plausibly scroll, and neither should hold ten
/// thousand rows in memory to do it (§20).
const int kHistoryStreamLimit = 500;

/// Hostnames with visit counts, derived from the same stream.
final visitedHostsProvider = Provider<AsyncValue<List<VisitedHost>>>(
  (ref) => ref.watch(browsingHistoryProvider).whenData(groupVisitsByHost),
);

// --- V2 composition --------------------------------------------------------

/// The V2 stack, built once at startup beside [AppServices]. Overridden in
/// `main()`; widget tests that never touch V2 surfaces simply do not read it.
final v2ServicesProvider = Provider<V2Services>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final queueRunnerProvider = Provider<QueueRunner>(
  (ref) => ref.watch(v2ServicesProvider).runner,
);

final checkControllerProvider = Provider<CheckController>(
  (ref) => ref.watch(v2ServicesProvider).check,
);
