import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser/browser_controller.dart';
import 'capability/foreground_multitasking.dart';
import 'browser/browser_navigator.dart';
import 'browser/browser_presentation.dart';
import 'browser/favicon_service.dart';
import 'browser/history_repository.dart';
import 'browser/saved_sites_repository.dart';
import 'save/save_run.dart';
import 'save/page_hint_repository.dart';
import 'features/resume_point.dart';
import 'features/library_check_flow.dart';
import 'features/library_screen.dart' show LibraryCollection;
import 'library/library_sort.dart';
import 'library/collection_deletion.dart';
import 'library/collection_repository.dart';
import 'library/update_checker.dart';
import 'queue/task_queue.dart';
import 'reading/reading_repository.dart';
import 'save/page_hint.dart';
import 'storage/cleanup.dart';
import 'storage/database.dart';
import 'storage/file_store.dart';
import 'ui/theme.dart';

/// Set once during bootstrap, before `runApp`.
class AppServices {
  AppServices({
    required this.db,
    required this.fileStore,
    required this.browser,
    required this.saveRun,
    UpdateChecker? updateChecker,
    TaskQueueController? taskQueue,
    CleanupService? cleanup,
    ForegroundMultitasking? foregroundMultitasking,
  }) : foregroundMultitasking =
           foregroundMultitasking ?? ForegroundMultitasking(),
       updateChecker = updateChecker ?? UpdateChecker(browser: browser, db: db),
       cleanup =
           cleanup ??
           CleanupService(db: db, fileStore: fileStore, saveRun: saveRun) {
    this.taskQueue =
        taskQueue ??
        TaskQueueController(
          db: db,
          browser: browser,
          saveRun: saveRun,
          checker: this.updateChecker,
          cleanup: this.cleanup,
        );
  }

  final AppDatabase db;
  final FileStore fileStore;
  final BrowserController browser;
  final SaveRunController saveRun;
  final UpdateChecker updateChecker;
  final CleanupService cleanup;

  /// The one place that answers whether an operation may keep running while
  /// the user is elsewhere in the app.
  final ForegroundMultitasking foregroundMultitasking;
  late final TaskQueueController taskQueue;
}

final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(appServicesProvider).db,
);

final fileStoreProvider = Provider<FileStore>(
  (ref) => ref.watch(appServicesProvider).fileStore,
);

final browserProvider = Provider<BrowserController>(
  (ref) => ref.watch(appServicesProvider).browser,
);

final saveRunProvider = Provider<SaveRunController>(
  (ref) => ref.watch(appServicesProvider).saveRun,
);

final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => ref.watch(appServicesProvider).updateChecker,
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

/// Falls back to a locally-built service when [appServicesProvider] is not
/// overridden — widget tests override the database and file store only, and
/// nothing here needs the whole service graph.
final cleanupProvider = Provider<CleanupService>((ref) {
  try {
    return ref.watch(appServicesProvider).cleanup;
  } catch (_) {
    // Widget tests override the database and file store only; the save
    // run is genuinely absent there, and cleanup degrades to "no running
    // save" rather than demanding the whole service graph.
    return CleanupService(
      db: ref.watch(databaseProvider),
      fileStore: ref.watch(fileStoreProvider),
    );
  }
});

final taskQueueProvider = Provider<TaskQueueController>(
  (ref) => ref.watch(appServicesProvider).taskQueue,
);

/// Permanent collection deletion.
///
/// Degrades the same way [cleanupProvider] does: a widget test that overrides
/// the database and the file store only still gets a working service, and
/// without a queue there is simply no pending work for it to cancel.
final collectionDeletionProvider = Provider<CollectionDeletionService>((ref) {
  TaskQueueController? queue;
  try {
    queue = ref.watch(appServicesProvider).taskQueue;
  } catch (_) {
    queue = null;
  }
  return CollectionDeletionService(
    db: ref.watch(databaseProvider),
    fileStore: ref.watch(fileStoreProvider),
    cleanup: ref.watch(cleanupProvider),
    queue: queue,
  );
});

/// The persisted appearance preference (default: follow the system).
final appearanceProvider = StreamProvider<AppearanceMode>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(kAppearanceSettingKey)
      .map(appearanceFromName),
);

Future<void> setAppearance(WidgetRef ref, AppearanceMode mode) =>
    ref.read(databaseProvider).setSetting(kAppearanceSettingKey, mode.name);

/// The queue as the UI sees it (activity strip + manager, M14 UI).
final queueTasksProvider = StreamProvider<List<QueueTask>>(
  (ref) => ref.watch(databaseProvider).watchQueueTasks(),
);

/// Reactive library: the list updates the moment an entry commits, with no
/// manual invalidation.
final entriesStreamProvider = StreamProvider<List<Entry>>(
  (ref) => ref.watch(databaseProvider).watchAllEntries(),
);

final collectionsStreamProvider = StreamProvider<List<Collection>>(
  (ref) => ref.watch(databaseProvider).watchCollections(),
);

final readingRepositoryProvider = Provider<ReadingRepository>(
  (ref) => ReadingRepository(ref.watch(databaseProvider)),
);

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => CollectionRepository(ref.watch(databaseProvider)),
);

/// The persisted All Collection sort (Q26: defaults to last-read).
final librarySortProvider = StreamProvider<LibrarySort>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(kLibrarySortSettingKey)
      .map(librarySortFromName),
);

/// Change and persist the sort; the groups provider reacts through the
/// settings stream — no imperative refresh anywhere.
Future<void> setLibrarySort(WidgetRef ref, LibrarySort sort) =>
    ref.read(databaseProvider).setSetting(kLibrarySortSettingKey, sort.name);

/// Collection groups with their entries, recomputed whenever either table
/// changes — so a save that commits mid-run shows up immediately.
/// Ordered by the persisted [LibrarySort].
/// Every collection with entries, archived included — the source both the
/// library (active) and the Archived screen filter from, so a collection can
/// never fall through the gap between them.
final allLibraryCollectionsProvider = StreamProvider<List<LibraryCollection>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final sort = ref.watch(librarySortProvider).value ?? LibrarySort.lastRead;
  // BOTH tables, genuinely. Drift invalidates per table, so watching only
  // `collections` missed entry-only writes — removing an entry's offline files
  // left the shelf and the Storage screen showing stale sizes until something
  // happened to touch a collection row.
  return _mergeTicks([db.watchCollections(), db.watchAllEntries()]).asyncMap((
    _,
  ) async {
    final collections = await db.allCollections();
    final entries = await db.allEntries();

    final byCollection = <String, List<Entry>>{};
    final standalone = <Entry>[];
    for (final entry in entries) {
      final id = entry.collectionId;
      if (id == null) {
        standalone.add(entry);
      } else {
        byCollection.putIfAbsent(id, () => []).add(entry);
      }
    }

    final shelf = <LibraryCollection>[
      for (final collection in collections)
        LibraryCollection(
          collection: collection,
          entries: byCollection[collection.id] ?? const [],
        ),
      // Standalone entries are shelf items in their own right, listed beside
      // collections rather than hidden inside one. This is the read side of the
      // nullable `entries.collection_id`.
      for (final entry in standalone) LibraryCollection(entries: [entry]),
    ]..removeWhere((g) => g.entries.isEmpty);

    return sortLibraryCollections(shelf, sort);
  });
});

/// Emit a tick whenever ANY of [sources] emits.
///
/// A hand-rolled merge rather than `package:async`'s StreamGroup: that
/// package is only a transitive dependency here, and this is a few lines.
///
/// `sync: true` matters. Drift delivers each query stream's first value in a
/// microtask; forwarding it through an async controller adds another event-
/// loop hop, which a widget test's fake clock never turns — the library
/// screen simply never left its loading state.
Stream<void> _mergeTicks(List<Stream<Object?>> sources) {
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<void> controller;
  controller = StreamController<void>.broadcast(
    sync: true,
    onListen: () {
      for (final source in sources) {
        subscriptions.add(
          source.listen(
            (_) => controller.add(null),
            onError: controller.addError,
          ),
        );
      }
    },
    onCancel: () {
      for (final s in subscriptions) {
        unawaited(s.cancel());
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}

/// The library: active collection only (M16 — archived ones live on their own
/// screen and are excluded from checks).
final libraryCollectionsProvider =
    Provider<AsyncValue<List<LibraryCollection>>>(
      (ref) => ref
          .watch(allLibraryCollectionsProvider)
          .whenData(
            (groups) => groups.where((g) => g.lifecycle != 'archived').toList(),
          ),
    );

/// Archived collection, most recently archived first.
final archivedGroupsProvider = Provider<AsyncValue<List<LibraryCollection>>>(
  (ref) => ref
      .watch(allLibraryCollectionsProvider)
      .whenData(
        (groups) =>
            groups.where((g) => g.lifecycle == 'archived').toList()..sort(
              (a, b) => (b.archivedAt ?? DateTime(0)).compareTo(
                a.archivedAt ?? DateTime(0),
              ),
            ),
      ),
);

/// One collection's entries, deduplicated by value.
///
/// Drift invalidates streams per table, so every entry write re-emits every
/// per-collection stream; `.distinct` on row equality stops the ripple — a
/// progress write for collection A produces no new emission for collection B. This is
/// what per-collection widgets watch so one entry's change cannot rebuild the
/// whole library (M13 backend; the M17 acceptance test rides on it).
final collectionEntriesProvider = StreamProvider.family<List<Entry>, String>(
  (ref, collectionId) => ref
      .watch(databaseProvider)
      .watchEntriesForCollection(collectionId)
      .distinct(const ListEquality<Entry>().equals),
);

/// One group, derived from the same stream so the two never disagree.
/// Looks across active AND archived: the detail screen must keep working for
/// a collection the user just archived.
final libraryCollectionProvider =
    Provider.family<AsyncValue<LibraryCollection?>, String>(
      (ref, collectionId) => ref
          .watch(allLibraryCollectionsProvider)
          .whenData(
            (groups) => groups.where((g) => g.id == collectionId).firstOrNull,
          ),
    );

/// Collection with an unfinished or next-unread local entry, most recently read
/// first. Derived from the same stream as the library, so the two can never
/// disagree and a save or a page turn updates both without a restart.
final continueReadingProvider = Provider<AsyncValue<List<ResumePoint>>>(
  (ref) => ref.watch(libraryCollectionsProvider).whenData((groups) {
    final entries = <ResumePoint>[];
    for (final group in groups) {
      final state = computeCollectionReadingState(group.entries);
      final entry = state.continueEntry;
      if (entry == null) continue;
      entries.add(ResumePoint(group: group, entry: entry, state: state));
    }
    entries.sort((a, b) {
      final at = a.state.lastReadAt;
      final bt = b.state.lastReadAt;
      if (at != null && bt != null) return bt.compareTo(at);
      // Never opened sorts after anything actually read.
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.group.displayName.toLowerCase().compareTo(
        b.group.displayName.toLowerCase(),
      );
    });
    return entries;
  }),
);

/// Anything ever opened, most recent first — including collection that are fully
/// completed and so no longer appear under Continue Reading.
final recentlyReadProvider = Provider<AsyncValue<List<ResumePoint>>>(
  (ref) => ref.watch(libraryCollectionsProvider).whenData((groups) {
    final entries = <ResumePoint>[];
    for (final group in groups) {
      final state = computeCollectionReadingState(group.entries);
      if (state.lastReadAt == null) continue;
      // Reopen where they were: the entry to continue, else the last one
      // they finished.
      final entry = state.continueEntry ?? state.lastCompleted;
      if (entry == null) continue;
      entries.add(ResumePoint(group: group, entry: entry, state: state));
    }
    entries.sort((a, b) => b.state.lastReadAt!.compareTo(a.state.lastReadAt!));
    return entries;
  }),
);

final collectionReadingStateProvider =
    Provider.family<AsyncValue<CollectionReadingState>, String>(
      (ref, collectionId) => ref
          .watch(libraryCollectionProvider(collectionId))
          .whenData(
            (group) => group == null
                ? const CollectionReadingState(entries: [])
                : computeCollectionReadingState(group.entries),
          ),
    );

final pageHintsStreamProvider = StreamProvider<List<UserPageHint>>(
  (ref) => ref
      .watch(databaseProvider)
      .watchAllHints()
      .map((rows) => rows.map(PageHintRepository.toModel).toList()),
);

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

final resumableRunProvider = StreamProvider<SaveRun?>(
  (ref) => ref.watch(databaseProvider).watchResumableRun(),
);

/// The Library-wide check the user started, and what its presentation owns.
///
/// In memory on purpose. Everything the run *reports* is read back from
/// durable rows — the queue's task states, each collection's `last_check_*`
/// columns, and `discovered_at` — so the only thing a restart loses is the
/// framing of "these collections were one operation", and a schema column to
/// carry a heading is not a trade worth making. The foreground half is even
/// more clearly transient: "this run moved the user into the Browser and owes
/// them the way back" must not survive a relaunch. Nothing here authorises
/// work: the queue rows do that, and they are already visible in Activity.
final libraryCheckFlowProvider = Provider<LibraryCheckFlow>((ref) {
  final flow = LibraryCheckFlow();
  ref.onDispose(flow.dispose);
  return flow;
});

// --- browser (M18) ---------------------------------------------------------

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(databaseProvider)),
);

final savedSitesRepositoryProvider = Provider<SavedSitesRepository>(
  (ref) => SavedSitesRepository(ref.watch(databaseProvider)),
);

/// One instance per app, so the icon a list fetched is the icon every other
/// list already has.
final faviconServiceProvider = Provider<FaviconService>((ref) {
  final service = FaviconService(db: ref.watch(databaseProvider));
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
final savedSitesProvider = StreamProvider<List<SavedSite>>(
  (ref) => ref.watch(databaseProvider).watchSavedSites(),
);

/// Manual browsing history, newest first and bounded — the History screen
/// and Browser Home's "recently visited" both read this one stream, so a
/// cleared range disappears from both at once with no cache to invalidate.
final browsingHistoryProvider = StreamProvider<List<BrowsingHistoryData>>(
  (ref) => ref.watch(databaseProvider).watchVisits(limit: kHistoryStreamLimit),
);

/// How many rows the shared history stream carries.
///
/// Bounded on purpose: Browser Home shows four, the History screen pages
/// through what a person can plausibly scroll, and neither should hold ten
/// thousand rows in memory to do it (§20).
const int kHistoryStreamLimit = 500;

/// Hostnames with visit counts, derived from the same stream.
final visitedHostsProvider = Provider<AsyncValue<List<VisitedHost>>>(
  (ref) => ref
      .watch(browsingHistoryProvider)
      .whenData(HistoryRepository.groupByHost),
);
