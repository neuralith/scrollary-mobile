/// How the app assembles sync, and what that assembly is allowed to do.
///
/// `scheduler_test.dart` proves the scheduler's own rules. This file proves the
/// **wiring** — the part no lane could assert for itself, and the part that is
/// easiest to get quietly wrong:
///
/// * an unconfigured build reaches nothing and says so;
/// * a configured build a device may not use reaches nothing **and keeps
///   recording**: the outbox grows and stays, because local writes are never
///   gated (docs/DECISIONS.md V2-D7);
/// * a device that may use it drains;
/// * gaining the capability takes effect at the next opportunity, with no
///   restart;
/// * a journalled mutation wakes the scheduler;
/// * the Download-to-Mobile consumer runs **inside** an opportunity, after the
///   pull that delivered the requests and before the drain that carries the
///   answers away.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/sync/scheduler.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/status.dart';
import 'package:web_reader/sync/transport.dart';

import 'support/fake_clock.dart';
import 'support/fake_server.dart';

/// Every call that went over the wire, in order.
class _Wire implements SyncTransport {
  _Wire(this._inner);

  final SyncTransport _inner;
  final List<String> calls = <String>[];

  int get requests => calls.length;

  @override
  Future<TransportReply> getChanges({required int cursor, int limit = 200}) {
    calls.add('changes');
    return _inner.getChanges(cursor: cursor, limit: limit);
  }

  @override
  Future<TransportReply> postMutations(Map<String, Object?> body) {
    calls.add('mutations');
    return _inner.postMutations(body);
  }

  @override
  Future<TransportReply> arbitrate(Map<String, Object?> body) {
    calls.add('arbitrate');
    return _inner.arbitrate(body);
  }

  @override
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) {
    calls.add('claim');
    return _inner.claimDownloadRequest(requestId, body);
  }

  @override
  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) {
    calls.add('resolve');
    return _inner.resolveDownloadRequest(requestId, body);
  }
}

void main() {
  late LibraryDatabase db;
  late FakeBackend backend;
  late HttpSyncTransport http;
  late _Wire wire;
  late ForegroundMultitasking capability;
  late FakeSyncClock clock;
  late FolderRepository folders;
  late OutboxRepository outbox;
  SyncComposition? composition;

  setUp(() async {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    backend = FakeBackend();
    await backend.start();
    http = HttpSyncTransport(baseUrl: backend.baseUrl, libraryName: 'wiring');
    wire = _Wire(http);
    capability = ForegroundMultitasking();
    clock = FakeSyncClock();
    folders = FolderRepository(db);
    outbox = OutboxRepository(db);
  });

  tearDown(() async {
    await composition?.dispose();
    capability.dispose();
    http.close();
    await backend.stop();
    await db.close();
  });

  /// The composition as the app builds it, with the two knobs a build actually
  /// has: whether an address was compiled in, and what the user is entitled to.
  SyncComposition build({required bool configured}) {
    final built = SyncComposition(
      db: db,
      queue: SaveQueueRepository(db),
      cloudSyncAvailable: () => capability.cloudSyncAvailable,
      capabilityChanges: capability,
      transport: configured ? wire : null,
      schedule: const SyncSchedule(
        startJitter: Duration(seconds: 1),
        mutationDebounce: Duration(seconds: 2),
      ),
      clock: clock,
    );
    composition = built;
    return built;
  }

  void grantCloudSync() => capability.override = EntitlementOverride.forcePro;

  /// Journal one ordinary local mutation, and give the outbox watch a real
  /// turn of the event loop to notice it.
  Future<void> mutateLocally(String name) async {
    final (row, violation) = await folders.create(name);
    expect(violation, isNull, reason: 'a local write is never gated');
    expect(row, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// Launch, then run every opportunity the next [by] would produce.
  Future<void> live(
    SyncComposition c, {
    Duration by = const Duration(minutes: 1),
  }) async {
    c.start();
    c.scheduler.onAppLaunch();
    await clock.advance(by, settle: c.scheduler.whenIdle);
    await c.scheduler.whenIdle();
  }

  group('what the build is configured with', () {
    test('an unconfigured build resolves nothing and stays quiet', () async {
      grantCloudSync();
      final c = build(configured: false);

      expect(c.resolve(), isNull, reason: 'there is no address to reach');
      await mutateLocally('Reading');
      await live(c);

      expect(wire.requests, 0);
      expect(
        c.scheduler.status.phase,
        SyncPhase.neverConfigured,
        reason: 'a state, not an error, and never an alert',
      );
      expect(
        await outbox.pendingCount(),
        1,
        reason: 'the journal is written whatever the device can reach',
      );
    });

    test('a configured build a device may not use reaches nothing', () async {
      final c = build(configured: true);

      expect(
        c.resolve(),
        isNull,
        reason: 'configured is half the question; permitted is the other half',
      );
      await mutateLocally('Reading');
      await mutateLocally('Later');
      await live(c);

      expect(
        wire.requests,
        0,
        reason: 'the gate is the network drain, and nothing walks past it',
      );
      expect(
        await outbox.pendingCount(),
        2,
        reason:
            'local writes are never gated, so nothing is lost and nothing has '
            'to be replayed when the answer changes',
      );
      expect(c.scheduler.status.phase, SyncPhase.neverConfigured);
    });

    test('a configured build a device may use drains', () async {
      grantCloudSync();
      final c = build(configured: true);

      expect(c.resolve(), isNotNull);
      await mutateLocally('Reading');
      await live(c);

      expect(wire.calls, contains('changes'));
      expect(wire.calls, contains('mutations'));
      expect(
        await outbox.pendingCount(),
        0,
        reason: 'an acknowledged intent leaves the journal',
      );
      expect(backend.kindRows('folder'), isNotEmpty);
    });
  });

  group('what changes without a restart', () {
    test('gaining the capability is taken at the next opportunity', () async {
      final c = build(configured: true);
      await mutateLocally('Reading');
      await live(c);
      expect(wire.requests, 0, reason: 'Free: nothing left the device');

      // The one thing that changed. No new scheduler, no second transport, and
      // nothing restarted.
      grantCloudSync();
      await clock.advance(
        const Duration(minutes: 1),
        settle: c.scheduler.whenIdle,
      );
      await c.scheduler.whenIdle();

      expect(wire.calls, contains('mutations'));
      expect(
        await outbox.pendingCount(),
        0,
        reason: 'the change that was waiting is the change that went',
      );
    });

    test('a journalled mutation wakes the scheduler', () async {
      grantCloudSync();
      final c = build(configured: true);
      await live(c);
      final afterLaunch = wire.requests;

      // The seam under test: nothing calls onLocalMutation by hand here — the
      // append itself is what the composition notices.
      await mutateLocally('Reading');
      await clock.advance(
        const Duration(seconds: 30),
        settle: c.scheduler.whenIdle,
      );
      await c.scheduler.whenIdle();

      expect(
        wire.requests,
        greaterThan(afterLaunch),
        reason: 'a local change is an opportunity',
      );
      expect(await outbox.pendingCount(), 0);
    });

    test('the drain acknowledging its own rows is not new work', () async {
      grantCloudSync();
      final c = build(configured: true);
      await mutateLocally('Reading');
      await live(c);
      final settled = wire.requests;

      // Nothing was written after the drain, so the count falling as rows are
      // acknowledged must not read as a mutation and start the loop again.
      await clock.advance(
        const Duration(minutes: 5),
        settle: c.scheduler.whenIdle,
      );
      await c.scheduler.whenIdle();
      expect(wire.requests, settled);
    });
  });

  group('the download-intent consumer', () {
    test('runs inside an opportunity, after the pull and before the '
        'push', () async {
      grantCloudSync();
      final c = build(configured: true);

      // A request the server is offering, for an Entry this library holds at
      // an address it can reach — so the consumer has something to claim.
      final at = DateTime.utc(2026, 8, 21, 9);
      backend.seed('folder', {
        'id': 'srv-root',
        'parent_id': null,
        'kind': 'root',
        'name': 'Library',
        'sort_key': 0,
      }, updatedAt: at);
      backend.seed('entry', {
        'id': 'srv-entry',
        'collection_id': null,
        'folder_id': 'srv-root',
        'ordinal': null,
        'placement': 'placed',
        'title': 'Quiet Harbour',
        'sort_key': 0,
      }, updatedAt: at);
      backend.seed('location', {
        'id': 'srv-location',
        'entry_id': 'srv-entry',
        'source_id': null,
        'url': 'https://reading.example/quiet-harbour/1',
        'url_key': 'https://reading.example/quiet-harbour/1',
        'source_label': '',
        'source_number': null,
        'discovered_at': at.toIso8601String(),
        'discovery_basis': 'listing',
        'lifecycle': 'active',
      }, updatedAt: at);
      backend.seed('downloadRequest', {
        'id': 'request-1',
        'entry_id': 'srv-entry',
        'location_id': 'srv-location',
        'state': 'pending',
        'idempotency_key': 'key-request-1',
        'created_by': 'extension',
        'created_at': at.toIso8601String(),
        'claimed_by_device': '',
        'claimed_at': null,
        'resolved_at': null,
        'failure_reason': '',
      });

      // One local change too, so the drain has something to carry: the point
      // is the *order*, and an empty outbox would make no call to place.
      await mutateLocally('Reading');
      await live(c);

      final claim = wire.calls.indexOf('claim');
      expect(claim, greaterThanOrEqualTo(0), reason: 'the claim was attempted');
      expect(
        wire.calls.indexOf('changes'),
        lessThan(claim),
        reason: 'the pull is what delivered the request',
      );
      expect(
        wire.calls.sublist(claim).contains('mutations'),
        isTrue,
        reason:
            'the drain follows, so an answer decided here leaves on the same '
            'opportunity',
      );
      // And what it produced is an ordinary waiting save — nothing ran.
      final task = await SaveQueueRepository(db).openTaskFor('srv-entry');
      expect(task, isNotNull);
      expect(task!.state, SaveTaskState.queued);
    });

    test('an engine with no hook behaves exactly as it did', () async {
      // The hook is additive: nothing that does not attach one can tell it
      // exists.
      final engine = SyncEngine(db);
      expect(engine.betweenPullAndPush, isNull);
      final outcome = await engine.syncOnce(wire);
      expect(outcome.succeeded, isTrue);
    });

    test('the hook records itself between the two, in one order', () async {
      // The hook writes into the same list the wire does, so the position is
      // asserted rather than inferred.
      final engine = SyncEngine(db)
        ..betweenPullAndPush = (transport) async => wire.calls.add('hook');
      await mutateLocally('Reading');
      wire.calls.clear();
      await engine.syncOnce(wire);

      expect(
        wire.calls,
        ['changes', 'hook', 'mutations', 'changes'],
        reason:
            'pull, then the consumer, then the drain — and the trailing pull '
            'that collects what the push produced',
      );
    });
  });
}
