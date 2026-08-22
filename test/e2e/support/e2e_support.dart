/// Shared support for the real-system end-to-end suite (roadmap H2-H4).
///
/// Everything here is real: a real [LibraryDatabase] per simulated client, the
/// real [HttpSyncTransport] over loopback TCP, the real Go service, a real
/// PostgreSQL. Nothing in `test/e2e/` fakes the wire — the fake in
/// `test/sync/support/fake_server.dart` is what this lane replaces.
///
/// The suite is opt-in: with no `SCROLLARY_E2E_BASE_URL` define every file
/// skips itself with a message, so the deterministic suite stays network-free
/// and `flutter test` never depends on a backend. `tool/e2e/run.sh` starts
/// everything and passes the define.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/download_request_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/measurement_repository.dart';
import 'package:web_reader/data/offline_copy_repository.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/sync/device_label.dart';
import 'package:web_reader/sync/download_intent.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/transport.dart';

import '../../../tool/fixture/fixture_site.dart';

// ---------------------------------------------------------------------------
// The opt-in switch
// ---------------------------------------------------------------------------

/// The running service, passed by `tool/e2e/run.sh`. Empty when the suite is
/// run without it.
const String kE2EBaseUrl = String.fromEnvironment('SCROLLARY_E2E_BASE_URL');

/// The restart-persistence phase, `seed` or `verify`. Empty otherwise.
const String kE2ERestartPhase = String.fromEnvironment(
  'SCROLLARY_E2E_RESTART_PHASE',
);

/// Where the seed phase leaves what the verify phase checks.
const String kE2ERestartHandoff = String.fromEnvironment(
  'SCROLLARY_E2E_RESTART_HANDOFF',
);

bool get e2eEnabled => kE2EBaseUrl.isNotEmpty;

Uri get e2eBaseUrl => Uri.parse(kE2EBaseUrl);

const String kE2ESkipReason =
    'real-system e2e: run `bash tool/e2e/run.sh` '
    '(needs --dart-define=SCROLLARY_E2E_BASE_URL)';

/// Declares the whole file skipped when the define is absent. Returns true
/// when the caller should stop registering tests.
bool skipWithoutBackend() {
  if (e2eEnabled) return false;
  test('end-to-end suite', () {}, skip: kE2ESkipReason);
  return true;
}

// ---------------------------------------------------------------------------
// Identity of a run
// ---------------------------------------------------------------------------

int _librarySeq = 0;

/// A development library nobody else in this run addresses, so every test is
/// independent of every other (V2_SYNC.md §9).
String uniqueLibrary(String tag) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'e2e-$tag-$stamp-${_librarySeq++}';
}

/// One strictly increasing clock shared by every simulated client, so "later
/// action" always means "later merge clock" no matter which client acted.
///
/// Anchored to the wall clock rather than counted from a base: these
/// timestamps are merge clocks that the service compares against its own
/// `now()` (a central placement stamps one), so a client clock that ran ahead
/// of real time would make a later server write lose to an earlier local one.
class E2EClock {
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime now() {
    final real = DateTime.now().toUtc();
    return _last = real.isAfter(_last)
        ? real
        : _last.add(const Duration(milliseconds: 1));
  }
}

// ---------------------------------------------------------------------------
// Raw HTTP: the observer, and the "extension"
// ---------------------------------------------------------------------------

/// A reply the raw client received: status plus decoded JSON body.
class RawReply {
  const RawReply(this.status, this.body, this.raw);

  final int status;
  final Map<String, Object?> body;
  final String raw;

  bool get ok => status >= 200 && status < 300;

  String? get errorCode {
    final error = body['error'];
    return error is Map ? error['code'] as String? : null;
  }
}

/// Raw HTTP against the real service, outside the sync engine.
///
/// Two jobs: asserting what the *server* holds (H2 reads `/changes` directly
/// rather than believing a second client), and standing in for the browser
/// extension, which speaks the same contract with a User-Agent of its own and
/// no capture engine at all (V2_SYNC.md §7).
class RawApi {
  RawApi({required this.library, Uri? baseUrl, this.userAgent})
    : baseUrl = baseUrl ?? e2eBaseUrl;

  final Uri baseUrl;
  final String library;
  final String? userAgent;
  final HttpClient _client = HttpClient();

  Future<RawReply> get(String pathAndQuery) => _send('GET', pathAndQuery);

  Future<RawReply> post(String pathAndQuery, Map<String, Object?> body) =>
      _send('POST', pathAndQuery, body: body);

  Future<RawReply> _send(
    String method,
    String pathAndQuery, {
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(
      method,
      baseUrl.resolve(pathAndQuery),
    );
    request.headers.set('X-Scrollary-Library', library);
    if (userAgent != null) request.headers.set('User-Agent', userAgent!);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    if (text.isNotEmpty) decoded = jsonDecode(text);
    return RawReply(
      response.statusCode,
      decoded is Map ? Map<String, Object?>.from(decoded) : const {},
      text,
    );
  }

  /// The whole change feed from [cursor], following pages to the end.
  Future<List<Map<String, Object?>>> feed({int cursor = 0}) async {
    final all = <Map<String, Object?>>[];
    var at = cursor;
    while (true) {
      final reply = await get('/changes?cursor=$at&limit=500');
      expect(reply.status, 200, reason: 'GET /changes: ${reply.raw}');
      final changes = (reply.body['changes'] as List<Object?>)
          .cast<Map<String, Object?>>();
      all.addAll(changes);
      at = (reply.body['next_cursor'] as num).toInt();
      if (reply.body['has_more'] != true) break;
    }
    return all;
  }

  /// The latest state of one entity in the feed, by wire id. Later revisions
  /// of the same row replace earlier ones, so this is what the server holds.
  Future<Map<String, Object?>?> entity(String entityType, String id) async {
    Map<String, Object?>? found;
    for (final change in await feed()) {
      if (change['type'] != 'entity') continue;
      if (change['entity_type'] != entityType) continue;
      final entity = Map<String, Object?>.from(change['entity']! as Map);
      if (_keyOf(entityType, entity) == id) found = entity;
    }
    return found;
  }

  /// Every entity of one type the server currently holds, by id.
  Future<Map<String, Map<String, Object?>>> entities(String entityType) async {
    final out = <String, Map<String, Object?>>{};
    final gone = <String>{};
    for (final change in await feed()) {
      if (change['type'] == 'tombstone') {
        final tombstone = Map<String, Object?>.from(
          change['tombstone']! as Map,
        );
        if (tombstone['kind'] == entityType) {
          gone.add(tombstone['entity_id']! as String);
        }
        continue;
      }
      if (change['entity_type'] != entityType) continue;
      final entity = Map<String, Object?>.from(change['entity']! as Map);
      final key = _keyOf(entityType, entity);
      out[key] = entity;
      gone.remove(key);
    }
    for (final id in gone) {
      out.remove(id);
    }
    return out;
  }

  /// The identity of a row in the feed. Reading state is keyed by its Entry;
  /// a measurement is keyed by `(entry, source)` and never by the Entry alone,
  /// because the scope is part of the key (I12).
  static String _keyOf(String entityType, Map<String, Object?> entity) {
    switch (entityType) {
      case 'readingState':
        return entity['entry_id']! as String;
      case 'measurement':
        return '${entity['entry_id']}|${entity['source_id']}';
      default:
        return entity['id']! as String;
    }
  }

  Future<int> latestRevision() async {
    final reply = await get('/changes?cursor=0&limit=1');
    return (reply.body['latest_revision'] as num).toInt();
  }

  void close() => _client.close(force: true);
}

// ---------------------------------------------------------------------------
// A simulated client
// ---------------------------------------------------------------------------

/// One device: its own database, its own repositories, its own transport.
class E2EClient {
  E2EClient._(this.label, this.libraryName, this.db, this.transport)
    : engine = SyncEngine(db) {
    folders = FolderRepository(db, now: E2EClock.now);
    collections = CollectionRepository(db, now: E2EClock.now);
    entries = EntryRepository(db, now: E2EClock.now);
    readingStates = ReadingStateRepository(db, now: E2EClock.now);
    measurements = MeasurementRepository(db, now: E2EClock.now);
    requests = DownloadRequestRepository(db, now: E2EClock.now);
    offline = OfflineCopyRepository(db, now: E2EClock.now);
    outbox = OutboxRepository(db);
    syncState = SyncStateStore(db);
    queue = SaveQueueRepository(db, now: E2EClock.now);
    consumer = DownloadIntentConsumer(queue, db: db, now: E2EClock.now);
    _deviceLabel = DeviceLabelStore(db);
  }

  static E2EClient start(String label, String libraryName, {Uri? baseUrl}) {
    // Every simulated client owns a separate in-memory executor, so several
    // databases in one process is the point rather than the hazard drift
    // warns about.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = LibraryDatabase.forTesting(NativeDatabase.memory());
    return E2EClient._(
      label,
      libraryName,
      db,
      HttpSyncTransport(
        baseUrl: baseUrl ?? e2eBaseUrl,
        libraryName: libraryName,
      ),
    );
  }

  final String label;
  final String libraryName;
  final LibraryDatabase db;
  final HttpSyncTransport transport;
  final SyncEngine engine;

  late final FolderRepository folders;
  late final CollectionRepository collections;
  late final EntryRepository entries;
  late final ReadingStateRepository readingStates;
  late final MeasurementRepository measurements;
  late final DownloadRequestRepository requests;
  late final OfflineCopyRepository offline;
  late final OutboxRepository outbox;
  late final SyncStateStore syncState;
  late final SaveQueueRepository queue;
  late final DownloadIntentConsumer consumer;
  late final DeviceLabelStore _deviceLabel;

  /// This device's own label, as a download-request claim names it.
  Future<String> deviceLabel() => _deviceLabel.label();

  /// One sync opportunity. Fails the test on a transport-level error unless
  /// [expectError] says the opportunity was meant to end early.
  Future<SyncOutcome> sync({
    int pullLimit = 200,
    SyncTransport? via,
    bool expectError = false,
  }) async {
    final outcome = await engine.syncOnce(
      via ?? transport,
      pullLimit: pullLimit,
    );
    if (!expectError) {
      expect(
        outcome.error,
        isNull,
        reason: '$label: sync opportunity failed: ${outcome.error}',
      );
    }
    return outcome;
  }

  Future<void> stop() async {
    transport.close();
    await db.close();
  }
}

// ---------------------------------------------------------------------------
// Transports that misbehave on purpose
// ---------------------------------------------------------------------------

/// Delegates everything, and kills the pull after [pages] committed pages —
/// the interrupted-pull case, where the process dies between pages.
class InterruptingTransport implements SyncTransport {
  InterruptingTransport(this._inner, {required this.pages});

  final SyncTransport _inner;
  final int pages;
  int served = 0;

  @override
  Future<TransportReply> getChanges({required int cursor, int limit = 200}) {
    if (served >= pages) {
      throw const SyncTransportException('pull interrupted (simulated kill)');
    }
    served += 1;
    return _inner.getChanges(cursor: cursor, limit: limit);
  }

  @override
  Future<TransportReply> postMutations(Map<String, Object?> body) =>
      _inner.postMutations(body);

  @override
  Future<TransportReply> arbitrate(Map<String, Object?> body) =>
      _inner.arbitrate(body);

  @override
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _inner.claimDownloadRequest(requestId, body);

  @override
  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _inner.resolveDownloadRequest(requestId, body);
}

/// Delegates everything and keeps the exact `/mutations` bodies it carried, so
/// a batch can be replayed byte for byte against the real ledger.
class RecordingTransport implements SyncTransport {
  RecordingTransport(this._inner);

  final SyncTransport _inner;
  final List<Map<String, Object?>> batches = [];
  final List<TransportReply> replies = [];

  @override
  Future<TransportReply> postMutations(Map<String, Object?> body) async {
    batches.add(body);
    final reply = await _inner.postMutations(body);
    replies.add(reply);
    return reply;
  }

  @override
  Future<TransportReply> getChanges({required int cursor, int limit = 200}) =>
      _inner.getChanges(cursor: cursor, limit: limit);

  @override
  Future<TransportReply> arbitrate(Map<String, Object?> body) =>
      _inner.arbitrate(body);

  @override
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _inner.claimDownloadRequest(requestId, body);

  @override
  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _inner.resolveDownloadRequest(requestId, body);
}

/// A port nothing listens on: the offline case, spelled as a real refused
/// connection rather than a flag inside the engine.
Future<Uri> unreachableBaseUrl() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return Uri.parse('http://127.0.0.1:$port');
}

// ---------------------------------------------------------------------------
// The source sites
// ---------------------------------------------------------------------------

/// One request the simulated source sites received.
class FixtureHit {
  const FixtureHit({
    required this.method,
    required this.path,
    required this.userAgent,
    required this.remote,
  });

  final String method;
  final String path;
  final String userAgent;
  final String remote;

  @override
  String toString() => '$method $path  ua="$userAgent"  from=$remote';
}

/// The in-process fixture site (`tool/fixture/`), serving the addresses this
/// suite uses as evidence and Locations, and recording every request it ever
/// received.
///
/// The backend never fetches a page (V2_SYNC.md §6.2), so the count these
/// sites report at the end of a run is zero. It is the positive half of the
/// H4 invariant: `tool/e2e/run.sh` proves the service opened no outbound
/// connection, and this proves nobody reached the sources by any other route.
class FixtureSite {
  FixtureSite._(this._server);

  static Future<FixtureSite> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = FixtureSite._(server);
    server.listen((request) async {
      site.hits.add(
        FixtureHit(
          method: request.method,
          path: request.uri.path,
          userAgent: request.headers.value(HttpHeaders.userAgentHeader) ?? '',
          remote: '${request.connectionInfo?.remoteAddress.address}',
        ),
      );
      try {
        await handleFixtureRequest(request, applyDelays: false);
      } on Exception {
        // A source that fails is the source's business; the hit is recorded.
      }
    }, onError: (Object _) {});
    return site;
  }

  final HttpServer _server;
  final List<FixtureHit> hits = [];

  String get origin => 'http://127.0.0.1:${_server.port}';

  /// The address one simulated site publishes part [n] at.
  String partUrl(String siteId, num n) => '$origin/s/$siteId/part/$n';

  /// Prints the tally `tool/e2e/run.sh` reads back, and asserts the invariant.
  void expectNothingFetched(String scenario) {
    stdout.writeln('FIXTURE HITS: ${hits.length}  [$scenario]');
    expect(
      hits,
      isEmpty,
      reason:
          'the source sites were fetched during "$scenario" — the backend '
          'never fetches a third-party page (V2_SYNC.md §6.2) and nothing '
          'else in this suite reads one either:\n'
          '${hits.join('\n')}',
    );
  }

  Future<void> stop() => _server.close(force: true);
}
