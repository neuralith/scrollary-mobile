/// Consuming Download-to-Mobile intents (E4, V2-D25, V2_SYNC.md §7).
///
/// The properties this file exists to hold:
///
/// 1. the claim is **single-winner** — two devices race, one wins, the loser
///    marks nothing and converges;
/// 2. a won claim becomes an ordinary save task that **waits**: no page is
///    fetched, nothing is eligible to run until the user's explicit Start;
/// 3. the requested Location is a preference, honoured when it is still one of
///    the Entry's active addresses and replaced by the Entry's own when not;
/// 4. a terminal local save is reported once, with the run's own named stop
///    condition, and reaches `/resolve` — never `/mutations`;
/// 5. **a failure never changes library membership** (I17);
/// 6. a death between the claim and the local row is recoverable, and recovery
///    never enqueues twice or captures twice;
/// 7. a request this device cannot fulfil is left for one that can.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/sync/device_label.dart';
import 'package:web_reader/sync/download_intent.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/transport.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;
  late SaveQueueRepository queue;
  late DownloadIntentConsumer consumer;

  const entryId = 'srv-entry';
  const primaryUrl = 'https://reading.example/quiet-harbour/1';
  const alternateUrl = 'https://mirror.example/quiet-harbour/1';
  final at = DateTime.utc(2026, 8, 21, 9);

  setUp(() async {
    h = await SyncHarness.start();
    queue = SaveQueueRepository(h.db, now: h.tick);
    consumer = DownloadIntentConsumer(queue, db: h.db, now: h.tick);
  });

  tearDown(() => h.stop());

  // ---- server-side fixtures (the "other client" of these tests) ------------

  void seedRoot() {
    h.backend.seed('folder', {
      'id': 'srv-root',
      'parent_id': null,
      'kind': 'root',
      'name': 'Library',
      'sort_key': 0,
    }, updatedAt: at);
  }

  void seedEntry(String id, {String title = 'Quiet Harbour'}) {
    h.backend.seed('entry', {
      'id': id,
      'collection_id': null,
      'folder_id': 'srv-root',
      'ordinal': null,
      'placement': 'placed',
      'title': title,
      'sort_key': 0,
    }, updatedAt: at);
  }

  void seedLocation(
    String id, {
    required String url,
    String entry = entryId,
    String lifecycle = 'active',
    Duration discoveredAfter = Duration.zero,
  }) {
    h.backend.seed('location', {
      'id': id,
      'entry_id': entry,
      'source_id': null,
      'url': url,
      'url_key': url,
      'source_label': '',
      'source_number': null,
      'discovered_at': at.add(discoveredAfter).toIso8601String(),
      'discovery_basis': 'listing',
      'lifecycle': lifecycle,
    }, updatedAt: at);
  }

  void seedRequest(
    String id, {
    String entry = entryId,
    String? locationId,
    String state = 'pending',
  }) {
    h.backend.seed('downloadRequest', {
      'id': id,
      'entry_id': entry,
      'location_id': locationId,
      'state': state,
      'idempotency_key': 'key-$id',
      'created_by': 'extension',
      'created_at': at.toIso8601String(),
      'claimed_by_device': '',
      'claimed_at': null,
      'resolved_at': null,
      'failure_reason': '',
    });
  }

  /// Root, one standalone Entry, one address.
  void seedLibrary() {
    seedRoot();
    seedEntry(entryId);
    seedLocation('srv-location', url: primaryUrl);
  }

  Future<String> thisDevice() => DeviceLabelStore(h.db).label();

  /// Run the save this device queued to a terminal state, as a pump would.
  Future<void> runTaskTo(
    String taskId, {
    required SaveTaskState state,
    StopReason? stopReason,
  }) async {
    await queue.claim(taskId);
    await queue.finish(taskId, state: state, stopReason: stopReason);
  }

  // ---- claiming and converting ---------------------------------------------

  test('a pending request becomes a save task that waits', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);

    final report = await consumer.consume(h.transport);

    expect(report.claimed, 1);
    expect(report.lost, 0);
    final task = await queue.openTaskFor(entryId);
    expect(task, isNotNull);
    expect(task!.entryId, entryId);
    expect(task.locationId, 'srv-location');
    expect(task.locationUrl, primaryUrl);
    // Queued work, not a record of something that ran: it is the queue's
    // origin, it is waiting, and it has not started.
    expect(task.state, SaveTaskState.queued);
    expect(task.origin, SaveTaskOrigin.queue);
    expect(task.startedAt, isNull);
    // **Nothing runs.** Save waits for the user's explicit Start, and a synced
    // intent is not one.
    expect(queue.saveStartAuthorised, isFalse);
    expect(await queue.eligible(), isEmpty);

    final row = await h.downloadRequests.byId('request-1');
    expect(row!.state, 'claimed');
    expect(row.claimedByDevice, await thisDevice());
    expect(row.localSaveTaskId, task.id);
    expect(
      h.backend.kindRows('downloadRequest')['request-1']!['state'],
      'claimed',
    );
  });

  test('the device label is minted once and reused', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    await consumer.consume(h.transport);

    final label = await thisDevice();
    expect(label, startsWith('device-'));
    // A second consumer over the same database reads the stored label rather
    // than minting a second one.
    final again = await DeviceLabelStore(h.db).label();
    expect(again, label);
    final stored = await h.db.select(h.db.localSettings).get();
    expect(
      stored.where((s) => s.key == DeviceLabelStore.settingKey),
      hasLength(1),
    );
  });

  test('the requested location is honoured', () async {
    seedRoot();
    seedEntry(entryId);
    seedLocation('srv-location', url: primaryUrl);
    seedLocation(
      'srv-location-2',
      url: alternateUrl,
      discoveredAfter: const Duration(hours: 1),
    );
    seedRequest('request-1', locationId: 'srv-location-2');
    await h.engine.syncOnce(h.transport);

    await consumer.consume(h.transport);

    final task = await queue.openTaskFor(entryId);
    expect(task!.locationId, 'srv-location-2');
    expect(task.locationUrl, alternateUrl);
  });

  test(
    'a request naming no location reads the entry at its own address',
    () async {
      seedRoot();
      seedEntry(entryId);
      // Deliberately seeded out of order: the earliest active address is the
      // Entry's own, whatever order the rows arrive in.
      seedLocation(
        'srv-location-2',
        url: alternateUrl,
        discoveredAfter: const Duration(hours: 1),
      );
      seedLocation('srv-location', url: primaryUrl);
      seedRequest('request-1');
      await h.engine.syncOnce(h.transport);

      await consumer.consume(h.transport);

      final task = await queue.openTaskFor(entryId);
      expect(task!.locationId, 'srv-location');
      expect(task.locationUrl, primaryUrl);
    },
  );

  test('a retracted preference falls back to the entry\'s address', () async {
    seedRoot();
    seedEntry(entryId);
    seedLocation('srv-location', url: primaryUrl);
    seedLocation(
      'srv-location-2',
      url: alternateUrl,
      lifecycle: 'retracted',
      discoveredAfter: const Duration(hours: 1),
    );
    seedRequest('request-1', locationId: 'srv-location-2');
    await h.engine.syncOnce(h.transport);

    await consumer.consume(h.transport);

    final task = await queue.openTaskFor(entryId);
    expect(task!.locationId, 'srv-location');
  });

  // ---- the single-winner claim ---------------------------------------------

  test('two devices race: one wins, the loser marks nothing', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);

    // A second device against the same server: its own database, its own
    // label, the same library.
    final db2 = LibraryDatabase.forTesting(NativeDatabase.memory());
    final transport2 = HttpSyncTransport(
      baseUrl: h.backend.baseUrl,
      libraryName: 'test-library',
    );
    final queue2 = SaveQueueRepository(db2);
    final consumer2 = DownloadIntentConsumer(queue2, db: db2);
    addTearDown(() async {
      transport2.close();
      await db2.close();
    });
    await SyncEngine(db2).syncOnce(transport2);

    final reports = await Future.wait([
      consumer.consume(h.transport),
      consumer2.consume(transport2),
    ]);

    // Both asked; exactly one won.
    expect(h.backend.claimRequests, ['request-1', 'request-1']);
    expect(reports.where((r) => r.claimed == 1), hasLength(1));
    expect(reports.where((r) => r.lost == 1), hasLength(1));
    expect(reports.expand((r) => r.errors), isEmpty);

    final firstWon = reports[0].claimed == 1;
    final winnerDb = firstWon ? h.db : db2;
    final loserDb = firstWon ? db2 : h.db;
    expect(
      h.backend.kindRows('downloadRequest')['request-1']!['claimed_by_device'],
      await DeviceLabelStore(winnerDb).label(),
    );
    // The winner holds the only save task in either library.
    expect(await (firstWon ? queue : queue2).all(), hasLength(1));
    expect(await (firstWon ? queue2 : queue).all(), isEmpty);
    // The loser wrote nothing: its mirror is untouched and converges on its
    // next pull.
    final loserRow = await (loserDb.select(
      loserDb.downloadRequests,
    )..where((r) => r.id.equals('request-1'))).getSingle();
    expect(loserRow.state, 'pending');
    expect(loserRow.localSaveTaskId, isNull);
  });

  test('a request the server already closed converges silently', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    // Another client cancelled it after this device mirrored it as pending.
    seedRequest('request-1', state: 'cancelled');

    final report = await consumer.consume(h.transport);

    expect(report.claimed, 0);
    expect(report.lost, 1);
    expect(report.errors, isEmpty);
    expect(await queue.all(), isEmpty);
    // Nothing was written locally by the refusal itself...
    expect((await h.downloadRequests.byId('request-1'))!.state, 'pending');
    // ...and the ordinary pull is what converges it.
    await h.engine.syncOnce(h.transport);
    expect((await h.downloadRequests.byId('request-1'))!.state, 'cancelled');
  });

  // ---- reporting the outcome -----------------------------------------------

  test('a completed save resolves the request through /resolve', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    await consumer.consume(h.transport);
    final task = (await queue.openTaskFor(entryId))!;

    await runTaskTo(task.id, state: SaveTaskState.completed);
    final report = await consumer.consume(h.transport);

    expect(report.resolved, 1);
    expect(await h.outbox.pendingCount(), 1);
    final outcome = await h.engine.syncOnce(h.transport);
    expect(outcome.succeeded, isTrue);
    expect(h.backend.resolveRequests, hasLength(1));
    expect(h.backend.resolveRequests.single.$1, 'request-1');
    expect(h.backend.resolveRequests.single.$2['state'], 'completed');
    expect(
      h.backend.kindRows('downloadRequest')['request-1']!['state'],
      'completed',
    );
    expect(await h.outbox.pendingCount(), 0);
    // Nothing about the request rode the mutation endpoint.
    final kinds = h.backend.mutationBatches
        .expand((batch) => batch)
        .map((e) => e['entity_type'])
        .toSet();
    expect(kinds, isNot(contains('downloadRequest')));
  });

  test('a failed save reports its named stop condition and leaves the library '
      'exactly as it was', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    await consumer.consume(h.transport);
    final task = (await queue.openTaskFor(entryId))!;
    final entriesBefore = await h.db.select(h.db.entries).get();
    final locationsBefore = await h.db.select(h.db.locations).get();

    await runTaskTo(
      task.id,
      state: SaveTaskState.failed,
      stopReason: StopReason.authenticationRequired,
    );
    final report = await consumer.consume(h.transport);

    expect(report.resolved, 1);
    await h.engine.syncOnce(h.transport);
    final row = h.backend.kindRows('downloadRequest')['request-1']!;
    expect(row['state'], 'failed');
    expect(row['failure_reason'], StopReason.authenticationRequired.name);
    // I17: a failure is not a removal. Every library row is untouched, and
    // this device holds no copy it did not hold before.
    expect(await h.db.select(h.db.entries).get(), entriesBefore);
    expect(await h.db.select(h.db.locations).get(), locationsBefore);
    expect(await h.db.select(h.db.offlineCopies).get(), isEmpty);
  });

  test('a cancelled save resolves as cancelled', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    await consumer.consume(h.transport);
    final task = (await queue.openTaskFor(entryId))!;

    // Cancelled before it started: the row survives, cancelled.
    expect(await queue.cancel(task.id), SaveCancelOutcome.cancelledBeforeStart);
    final report = await consumer.consume(h.transport);

    expect(report.resolved, 1);
    await h.engine.syncOnce(h.transport);
    final row = h.backend.kindRows('downloadRequest')['request-1']!;
    expect(row['state'], 'cancelled');
    expect(row['failure_reason'], '');
  });

  // ---- recovery ------------------------------------------------------------

  test('a claim whose save task vanished is enqueued exactly once', () async {
    seedLibrary();
    seedRequest('request-1');
    await h.engine.syncOnce(h.transport);
    // The claim landed on the server and was recorded here, then the task it
    // named went: cleared from Activity, or never written at all.
    final violation = await h.downloadRequests.recordLocalClaim(
      'request-1',
      device: await thisDevice(),
      localSaveTaskId: 'a-task-that-is-gone',
    );
    expect(violation, isNull);
    expect(await queue.all(), isEmpty);

    final first = await consumer.consume(h.transport);
    expect(first.requeued, 1);
    expect(await queue.all(), hasLength(1));

    // Run it again: the open task for the Entry is found, so nothing is
    // enqueued a second time.
    final second = await consumer.consume(h.transport);
    expect(second.requeued, 0);
    expect(await queue.all(), hasLength(1));
    final task = (await queue.openTaskFor(entryId))!;
    expect(task.locationUrl, primaryUrl);
    expect(task.state, SaveTaskState.queued);
  });

  test(
    'a claim whose save already finished resolves without capturing again',
    () async {
      seedLibrary();
      seedRequest('request-1');
      await h.engine.syncOnce(h.transport);
      await h.downloadRequests.recordLocalClaim(
        'request-1',
        device: await thisDevice(),
        localSaveTaskId: 'a-task-that-is-gone',
      );
      // The save this device ran for the Entry finished after the claim, and
      // the id that named it did not survive.
      final enqueued = await queue.enqueue(
        entryId: entryId,
        locationId: 'srv-location',
        locationUrl: primaryUrl,
      );
      await runTaskTo(enqueued.task!.id, state: SaveTaskState.completed);

      final report = await consumer.consume(h.transport);

      expect(report.resolved, 1);
      expect(report.requeued, 0);
      // No second capture was queued.
      expect(await queue.all(), hasLength(1));
      expect(await queue.openTaskFor(entryId), isNull);
      await h.engine.syncOnce(h.transport);
      expect(
        h.backend.kindRows('downloadRequest')['request-1']!['state'],
        'completed',
      );
    },
  );

  // ---- what this device leaves alone ---------------------------------------

  test(
    'a request for an entry this library does not hold is left unclaimed',
    () async {
      seedLibrary();
      seedRequest('request-elsewhere', entry: 'an-entry-this-device-lacks');
      await h.engine.syncOnce(h.transport);

      final report = await consumer.consume(h.transport);

      expect(report.claimed, 0);
      // Not even asked for: claiming is single-winner, and a claim this device
      // could not act on would take the request from a device that can.
      expect(h.backend.claimRequests, isEmpty);
      expect(
        h.backend.kindRows('downloadRequest')['request-elsewhere']!['state'],
        'pending',
      );
      expect(await h.db.select(h.db.downloadRequests).get(), isEmpty);
      expect(await queue.all(), isEmpty);
    },
  );

  test('a request for an entry with no address is left unclaimed', () async {
    seedRoot();
    seedEntry('srv-entry-bare', title: 'No address here');
    seedRequest('request-bare', entry: 'srv-entry-bare');
    await h.engine.syncOnce(h.transport);

    final report = await consumer.consume(h.transport);

    expect(report.skipped, 1);
    expect(report.claimed, 0);
    expect(h.backend.claimRequests, isEmpty);
    expect(await queue.all(), isEmpty);
    // The mirror is here and untouched: an Entry with no Location is an
    // ordinary library item, not a failure.
    expect((await h.downloadRequests.byId('request-bare'))!.state, 'pending');
  });
}
