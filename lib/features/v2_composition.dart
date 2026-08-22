/// Everything the V2 stack adds to the app's composition, built once at
/// startup and torn down with it.
///
/// Three things live here, and they are here because each one is a *wiring*
/// decision that no lane may make for itself:
///
///  * **The sync stack** — one transport, one engine, one scheduler, one
///    download-intent consumer, and the one closure that decides whether this
///    device may reach the network at all.
///  * **Placement submission** — over the service when there is one, and an
///    ordinary local write when there is not (V2-D7).
///  * **Browsing history** — the V2 `history` table, which is the only one
///    there is: V1's `browsing_history` retired with the rest of that schema.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show Listenable;

import 'package:drift/drift.dart';

import '../browser/browser_url.dart' show displayHost;
import '../browser/browsing_history.dart'
    show HistoryClearRange, kHistoryMaxAge, kHistoryMaxRows;
import '../core/sync_config.dart';
import '../data/data_violations.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../library_ui/placement_models.dart';
import '../library_ui/providers.dart';
import '../recognition/history.dart';
import '../recognition/placement.dart' as placement;
import '../recognition/recognise.dart';
import '../save/queue_repository.dart';
import '../save/queue_runner.dart';
import '../sync/download_intent.dart';
import '../sync/scheduler.dart';
import '../sync/session.dart';
import '../sync/transport.dart';
import 'check_controller.dart';
import 'v2_save_flow.dart' show V2AssistController;

/// Visits closer together than this to the same page are one visit.
///
/// The rule V1 held in its own repository, kept because the reason for it is
/// unchanged: individual rows are what makes "clear the last hour" accurate,
/// but a reload loop must not stack twelve identical entries.
const Duration kVisitCollapseWindow = Duration(minutes: 30);

/// Everything the V2 stack adds to the app's composition.
class V2Services {
  V2Services({
    required this.library,
    required this.ui,
    required this.runner,
    required this.check,
    required this.recogniser,
    required this.history,
    required this.assist,
    required this.sync,
  });

  final LibraryDatabase library;
  final LibraryUiServices ui;
  final QueueRunner runner;
  final CheckController check;

  /// *Given this URL, what is it?* — asked on every completed navigation the
  /// user performed themselves.
  final Recogniser recogniser;

  /// Device-local browsing history, over the V2 table.
  final BrowsingHistoryStore history;

  /// The one user-assist host. A capture that cannot find the reading area
  /// holds here and asks; the save sheet renders the request. One per app,
  /// because two would mean a capture could hold on a controller nothing is
  /// watching.
  final V2AssistController assist;

  /// The one sync stack. Never null: an unconfigured or unentitled device has
  /// a scheduler that resolves no transport and does nothing, which is a state
  /// rather than an absence.
  final SyncComposition sync;

  /// Set by the app root once its router exists; consumed by the
  /// entry-opener/source-opener providers. Mutable because navigation cannot
  /// exist before the widget tree does.
  Future<void> Function(String entryId)? openEntry;
  Future<void> Function(String url)? openSource;

  /// Set by the shell: ensure the Browser surface, then start the runner.
  Future<void> Function()? startQueue;

  /// Set by the shell: ask the foreground gate, then run a Collection check.
  Future<void> Function(String collectionId, String collectionName)?
  checkCollection;

  Future<void> dispose() async {
    runner.dispose();
    check.dispose();
    assist.dispose();
    await sync.dispose();
    await library.close();
  }
}

// ─── sync ───────────────────────────────────────────────────────────────────

/// The sync stack, assembled once.
///
/// The whole of the Free/Pro boundary for cloud sync is the closure this class
/// hands the scheduler. Local writes and the outbox are untouched by it — they
/// keep accumulating whatever it answers, so nothing is lost and nothing has to
/// be replayed when the answer changes (docs/DECISIONS.md V2-D7). The gate sits
/// on the network drain and nowhere else.
class SyncComposition {
  SyncComposition({
    required LibraryDatabase db,
    required SaveQueueRepository queue,
    required this.cloudSyncAvailable,
    required this._capabilityChanges,
    required this.transport,
    SyncSchedule schedule = const SyncSchedule(),
    SyncClock clock = const SystemSyncClock(),
  }) : _db = db,
       engine = SyncEngine(db) {
    // **The app's own queue**, taken rather than built: the Start
    // authorisation lives on that instance, and a consumer holding a second
    // repository would be reasoning about a queue nobody had started.
    consumer = createDownloadIntentConsumer(db, queue);
    // The one place the consumer runs: inside an opportunity, after the pull
    // that delivered the requests and before the drain that carries the
    // answers away.
    engine.betweenPullAndPush = (t) => consumer.consume(t);
    scheduler = SyncScheduler(
      engine: engine,
      transport: resolve,
      schedule: schedule,
      clock: clock,
    );
    _wasAvailable = cloudSyncAvailable();
    _capabilityChanges.addListener(_onCapabilityChanged);
  }

  /// **May this device use the cloud service?**
  ///
  /// Handed in rather than derived. The capability layer is the one place that
  /// answers what a user has, and the composition that owns that seam supplies
  /// the answer here as a plain question — so this file wires a gate without
  /// ever being able to read what is behind it.
  final bool Function() cloudSyncAvailable;

  /// Notifies when the answer above may have changed.
  final Listenable _capabilityChanges;

  /// The one transport, built once. Null when this build carries no service
  /// address at all — see `lib/core/sync_config.dart`.
  ///
  /// Held as the interface: nothing above `lib/sync/transport.dart` opens a
  /// socket, so nothing above it can grow a second transport either.
  final SyncTransport? transport;

  final SyncEngine engine;
  final LibraryDatabase _db;

  late final DownloadIntentConsumer consumer;
  late final SyncScheduler scheduler;

  StreamSubscription<int>? _outbox;
  int _pending = 0;
  bool _wasAvailable = false;
  bool _disposed = false;

  /// **The gate.** Configured *and* permitted, asked afresh every time so a
  /// change on either side needs no restart and no second scheduler.
  SyncTransport? resolve() {
    final held = transport;
    if (held == null) return null;
    return cloudSyncAvailable() ? held : null;
  }

  /// A capability arriving is new information of exactly the kind
  /// [SyncScheduler.onConnectivityRegained] exists for: something that knows
  /// says the service is reachable now. Nudged in that direction only —
  /// losing it needs no nudge, because the resolver already answers null and
  /// the next opportunity is a no-op.
  void _onCapabilityChanged() {
    if (_disposed) return;
    final available = cloudSyncAvailable();
    if (available && !_wasAvailable) scheduler.onConnectivityRegained();
    _wasAvailable = available;
  }

  /// Begin watching for local mutations. Idempotent.
  ///
  /// Deliberately **not** in the constructor: this opens a live query stream,
  /// and a composition that opened one merely by existing would put a
  /// long-running database subscription inside every widget test that builds
  /// the V2 services. The app starts it beside [SyncScheduler.onAppLaunch],
  /// which is the moment it is true that there is an app to synchronise for.
  void start() {
    if (_disposed || _outbox != null) return;
    _watchOutbox();
  }

  /// One local mutation was journalled.
  ///
  /// `lib/data/` owns the outbox and has no notifier to hang this on, so the
  /// seam used here is the one the storage layer already publishes: drift
  /// re-runs this count whenever the table changes. Only a *rise* is a
  /// mutation — the drain's own acknowledgement lowers the count, and treating
  /// that as new work would be the scheduler waking itself up.
  void _watchOutbox() {
    final count = _db.outbox.opId.count();
    final query = _db.selectOnly(_db.outbox)..addColumns([count]);
    _outbox = query.watchSingle().map((row) => row.read(count) ?? 0).listen((
      pending,
    ) {
      final rose = pending > _pending;
      _pending = pending;
      if (rose) scheduler.onLocalMutation();
    }, onError: (Object _) {});
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _capabilityChanges.removeListener(_onCapabilityChanged);
    await _outbox?.cancel();
    scheduler.dispose();
    if (transport case final HttpSyncTransport http) http.close();
  }
}

/// The transport this build carries, or null when it carries none.
HttpSyncTransport? buildSyncTransport() {
  final base = syncBaseUri;
  if (base == null) return null;
  return HttpSyncTransport(baseUrl: base, libraryName: kSyncLibraryName);
}

// ─── placement ──────────────────────────────────────────────────────────────

/// How a placement leaves this device.
///
/// Two shapes, and the difference between them is not what the user may do —
/// it is whether anyone else has a say. **Placement is a local write** (V2-D7):
/// server arbitration exists because two devices placing the same Entry
/// differently is a contradiction, and with no second device there is no
/// contradiction to arbitrate. So a device with no service applies the position
/// the user typed, locally, and journals the one intent that carries it — the
/// same intent a synced device would send, waiting in the outbox for a service
/// that may never arrive.
PlacementSubmit placementSubmitFor(V2Services v2) {
  // Whether an address was compiled in is a fact about the build, so it is
  // read once. **Whether this device may use it is not** — that answer can
  // change while the app is running, so it is asked through the same closure
  // the drain asks, at the moment a placement is submitted. Placement and the
  // drain can therefore never disagree about whether this device has a
  // service.
  final base = syncBaseUri;
  if (base == null) return localPlacementSubmit;
  final service = placement.PlacementService(
    entries: v2.ui.entries,
    collections: v2.ui.collections,
    index: RecognitionIndex(v2.library),
    transport: HttpPlacementTransport(
      baseUrl: base,
      libraryName: kSyncLibraryName,
    ),
  );
  return (request) async {
    if (v2.sync.resolve() == null) return localPlacementSubmit(request);
    final placement.PlacementOutcome outcome;
    try {
      outcome = await service.place(
        entryId: request.entryId,
        ordinal: request.ordinal,
      );
    } on Object {
      // A service that cannot be reached is a refusal the dialog states, never
      // a crash and never a position quietly applied somewhere else.
      return const PlacementOutcome.refused(
        'The sync service can\'t be reached right now. Nothing was changed.',
      );
    }
    return switch (outcome) {
      placement.PlacementApplied(:final entry) => PlacementOutcome.applied(
        entry.ordinal ?? request.ordinal,
      ),
      placement.PlacementRefused(
        :final violation,
        :final currentOrdinal,
        :final currentEntryId,
      ) =>
        violation == placement.placementConflict ||
                violation == duplicateOrdinal
            ? PlacementOutcome.conflict(
                ordinal: currentOrdinal ?? request.ordinal,
                occupyingEntryId: currentEntryId,
              )
            : PlacementOutcome.refused(violation.message),
    };
  };
}

/// One placement submission over HTTP.
///
/// Wire shape from `contracts/openapi.yaml` `/entries/{entry_id}/placement`.
/// Separate from [HttpSyncTransport] because placement is not one of the five
/// operations metadata sync performs: it is a synchronous domain question, not
/// a mutation that can ride the outbox.
class HttpPlacementTransport implements placement.PlacementTransport {
  HttpPlacementTransport({
    required this.baseUrl,
    required this.libraryName,
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final Uri baseUrl;
  final String libraryName;
  final HttpClient _client;
  final Duration timeout;

  @override
  Future<placement.PlacementResponse> submitPlacement({
    required String entryId,
    required double ordinal,
    required String mutationId,
  }) async {
    final request = await _client
        .postUrl(baseUrl.resolve('/entries/$entryId/placement'))
        .timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Scrollary-Library', libraryName);
    request.add(
      utf8.encode(jsonEncode({'ordinal': ordinal, 'mutation_id': mutationId})),
    );
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    final decoded = text.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;

    switch (response.statusCode) {
      case 200:
        return placement.PlacementAccepted(
          entry: _entryFrom(decoded['entry'] as Map<String, Object?>? ?? {}),
        );
      case 409:
        final error = decoded['error'] as Map<String, Object?>? ?? const {};
        final details = error['details'] as Map<String, Object?>? ?? const {};
        if (error['code'] == 'placement_conflict') {
          return placement.PlacementConflicted(
            currentEntryId: details['current_entry_id'] as String?,
            currentOrdinal: (details['current_ordinal'] as num?)?.toDouble(),
          );
        }
        return const placement.PlacementInvalid();
      case 404:
        return const placement.PlacementUnknownEntity();
      default:
        throw SyncTransportException('placement: HTTP ${response.statusCode}');
    }
  }

  placement.RemoteEntry _entryFrom(Map<String, Object?> row) =>
      placement.RemoteEntry(
        id: row['id'] as String? ?? '',
        serverId: row['server_id'] as String?,
        collectionId: row['collection_id'] as String?,
        folderId: row['folder_id'] as String?,
        ordinal: (row['ordinal'] as num?)?.toDouble(),
        placement: row['placement'] as String? ?? 'userPlaced',
        title: row['title'] as String? ?? '',
        sortKey: (row['sort_key'] as num?)?.toInt() ?? 0,
        revision: (row['revision'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse(row['updated_at'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
      );

  void close() => _client.close(force: true);
}

// ─── what a completed navigation means ──────────────────────────────────────

/// One completed navigation: recognise it, then record it in the one place
/// that is right for what it turned out to be (roadmap F6).
///
/// * A Location this library holds, whose Collection is **followed** — or a
///   standalone Entry, which is in the library by construction — records
///   **access** and nothing else. Never completion: on a website there is no
///   position to measure, so no progress figure is invented (I16, V2-D9).
/// * Everything else is device-local history (I11). A page on a Source the
///   library knows but has stopped following is *everything else*: reading an
///   unfollowed Collection must not quietly expand the synced library, because
///   following is the authorising act (V2-D13).
///
/// Nothing here creates a Collection, an Entry or a Location. Promotion out of
/// history is a tap the user makes.
///
/// [userInitiated] is the whole gate, and it is the caller's fact to state:
/// save automation and update checks move the same browser, and inferring who
/// moved it from anything else is how automation ends up in someone's history.
Future<void> recordCompletedVisit(
  V2Services v2, {
  required String url,
  required String title,
  required bool userInitiated,
  String requestedUrl = '',
  bool completed = true,
}) async {
  if (!userInitiated || !completed) return;
  final result = await v2.recogniser.recognise(url, pageTitle: title);
  if (await v2.recogniser.recordAccess(result) != null) return;
  await v2.history.recordVisit(
    landedUrl: url,
    requestedUrl: requestedUrl,
    urlKey: result.keys.urlKey,
    title: title,
    userInitiated: true,
  );
}

// ─── browsing history ───────────────────────────────────────────────────────

/// The browser's history, over the V2 `history` table.
///
/// One table, read by the recognition pipeline and by the History screen
/// alike: two tables holding the same fact is how they come to disagree, which
/// is why V1's `browsing_history` retired rather than being kept in step.
///
/// Device-local either way. History is never synced (I11) and no intent about
/// it can be expressed — the outbox's own CHECK constraint refuses the
/// spelling.
class BrowsingHistoryStore {
  BrowsingHistoryStore(this._db) : _store = HistoryStore(_db);

  final LibraryDatabase _db;
  final HistoryStore _store;

  /// Record one completed navigation the user performed themselves.
  ///
  /// [userInitiated] is the whole gate and is passed straight through to
  /// [HistoryStore], which refuses without it. Two things sit in front of it
  /// and both are browser-surface behaviour, which is why they are here rather
  /// than there: the collapse window, and the title fallback — a page that
  /// never reported a title reads better as its host than as an empty row the
  /// user cannot identify.
  Future<void> recordVisit({
    required String landedUrl,
    required String title,
    required bool userInitiated,
    String requestedUrl = '',
    bool completed = true,

    /// The key recognition already derived for this page. Passed in on the hot
    /// path so one navigation normalises its URL once; derived here when a
    /// caller has not.
    String? urlKey,
    DateTime? at,
  }) async {
    if (!userInitiated || !completed) return;
    final when = (at ?? DateTime.now()).toUtc();
    final redirected = requestedUrl.isNotEmpty && requestedUrl != landedUrl;
    final trimmed = title.trim();
    final label = trimmed.isEmpty ? displayHost(landedUrl) : trimmed;
    final key = urlKey ?? RecognitionKeys.of(landedUrl).urlKey;
    final recent = await _recentVisitTo(key, when);
    if (recent != null) {
      // Refresh the row rather than stacking another: the same page, again,
      // inside the window is one visit.
      await (_db.update(
        _db.history,
      )..where((h) => h.id.equals(recent.id))).write(
        HistoryCompanion(
          visitedAt: Value(when),
          title: label.isEmpty ? const Value.absent() : Value(label),
        ),
      );
      return;
    }
    await _store.recordVisit(
      url: redirected ? requestedUrl : landedUrl,
      finalUrl: redirected ? landedUrl : null,
      title: label,
      userInitiated: true,
      at: when,
    );
  }

  Future<HistoryRow?> _recentVisitTo(String urlKey, DateTime now) async {
    final since = now.subtract(kVisitCollapseWindow);
    final rows =
        await (_db.select(_db.history)
              ..where(
                (h) =>
                    h.urlKey.equals(urlKey) &
                    h.visitedAt.isBiggerThanValue(since),
              )
              ..orderBy([(h) => OrderingTerm.desc(h.visitedAt)])
              ..limit(1))
            .get();
    return rows.firstOrNull;
  }

  /// Newest first, bounded — the one stream the History screen and Browser
  /// Home's *recently visited* both read.
  Stream<List<HistoryRow>> watchRecent({int limit = 200}) {
    final query = _db.select(_db.history)
      ..orderBy([(h) => OrderingTerm.desc(h.visitedAt)])
      ..limit(limit);
    return query.watch();
  }

  Future<List<HistoryRow>> recent({int limit = 200}) {
    final query = _db.select(_db.history)
      ..orderBy([(h) => OrderingTerm.desc(h.visitedAt)])
      ..limit(limit);
    return query.get();
  }

  Future<int> removeVisit(String id) =>
      (_db.delete(_db.history)..where((h) => h.id.equals(id))).go();

  Future<int> removeHost(String host) => (_db.delete(
    _db.history,
  )..where((h) => h.host.equals(host.toLowerCase()))).go();

  /// How many rows [range] would remove, counted before the user confirms.
  Future<int> countIn(HistoryClearRange range, {DateTime? now}) async {
    final since = range.since(now ?? DateTime.now())?.toUtc();
    final count = _db.history.id.count();
    final query = _db.selectOnly(_db.history)..addColumns([count]);
    if (since != null) {
      query.where(_db.history.visitedAt.isBiggerOrEqualValue(since));
    }
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Clear a range. Touches `history` and nothing else: the library, saved
  /// files, reading state, saved sites and queue rows all live in other tables
  /// and are never referenced here.
  Future<int> clear(HistoryClearRange range, {DateTime? now}) {
    final since = range.since(now ?? DateTime.now())?.toUtc();
    final delete = _db.delete(_db.history);
    if (since != null) {
      delete.where((h) => h.visitedAt.isBiggerOrEqualValue(since));
    }
    return delete.go();
  }

  /// Apply the retention bounds. Cheap enough to run at boot; deliberately not
  /// run on every write, where it would turn one insert into a scan.
  Future<int> prune({DateTime? now}) async {
    final before = (now ?? DateTime.now()).toUtc().subtract(kHistoryMaxAge);
    var removed = await (_db.delete(
      _db.history,
    )..where((h) => h.visitedAt.isSmallerThanValue(before))).go();
    final survivors =
        await (_db.select(_db.history)
              ..orderBy([(h) => OrderingTerm.desc(h.visitedAt)])
              ..limit(1, offset: kHistoryMaxRows))
            .get();
    if (survivors.isNotEmpty) {
      removed +=
          await (_db.delete(_db.history)..where(
                (h) => h.visitedAt.isSmallerOrEqualValue(
                  survivors.first.visitedAt,
                ),
              ))
              .go();
    }
    return removed;
  }
}
