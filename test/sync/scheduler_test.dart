/// When sync runs, what stops it, and what it does after a failure
/// (roadmap G5, G6).
///
/// The engine's own kill-safety is `pull_test.dart` and `push_test.dart`. What
/// this file is responsible for is that the *scheduler* adds no hazard on top
/// of it: no two opportunities at once, nothing while the app is not in front,
/// nothing without a transport, a wait that grows after a failure, and no
/// state of its own that a restart would need.
///
/// Time is a [FakeSyncClock], so every duration here is exact and no test
/// sleeps. The network is the real loopback fake backend the rest of the sync
/// tests use, behind a wire that can be held open, cut, or counted.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/sync/retry.dart';
import 'package:web_reader/sync/scheduler.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/status.dart';
import 'package:web_reader/sync/transport.dart';

import 'support/fake_clock.dart';
import 'support/fake_server.dart';

/// The transport, with three knobs: hold an opportunity open, cut the
/// connection, and count what went over the wire.
class _Wire implements SyncTransport {
  _Wire(this._inner);

  final SyncTransport _inner;

  /// One `getChanges` per opportunity while the library is empty — the push
  /// makes no call when the outbox is, and no trailing pull happens when the
  /// push acknowledged nothing.
  int changesCalls = 0;
  int mutationCalls = 0;

  bool reachable = true;

  /// While set, every call waits. Lets a test fire triggers at an opportunity
  /// that is genuinely in flight.
  Completer<void>? gate;

  Future<T> _pass<T>(Future<T> Function() call) async {
    final held = gate;
    if (held != null) await held.future;
    if (!reachable) throw const SyncTransportException('offline');
    return call();
  }

  void release() {
    gate?.complete();
    gate = null;
  }

  // Counted before the gate, not behind it: a test that holds an opportunity
  // open needs to know it is open.
  @override
  Future<TransportReply> getChanges({required int cursor, int limit = 200}) {
    changesCalls += 1;
    return _pass(() => _inner.getChanges(cursor: cursor, limit: limit));
  }

  @override
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) {
    return _pass(() => _inner.claimDownloadRequest(requestId, body));
  }

  @override
  Future<TransportReply> postMutations(Map<String, Object?> body) {
    mutationCalls += 1;
    return _pass(() => _inner.postMutations(body));
  }

  @override
  Future<TransportReply> arbitrate(Map<String, Object?> body) =>
      _pass(() => _inner.arbitrate(body));

  @override
  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _pass(() => _inner.resolveDownloadRequest(requestId, body));
}

class _Harness {
  _Harness._(this.db, this.backend, this._http, this.wire);

  static Future<_Harness> start({bool configured = true}) async {
    final db = LibraryDatabase.forTesting(NativeDatabase.memory());
    final backend = FakeBackend();
    await backend.start();
    final http = HttpSyncTransport(
      baseUrl: backend.baseUrl,
      libraryName: 'scheduler-test',
    );
    final harness = _Harness._(db, backend, http, _Wire(http));
    harness.configured = configured;
    return harness;
  }

  final LibraryDatabase db;
  final FakeBackend backend;
  final HttpSyncTransport _http;
  final _Wire wire;

  /// Whether this device has a transport at all. Flipped by the tests that
  /// care; the resolver is asked afresh every time, as the real one is.
  bool configured = true;

  final FakeSyncClock clock = FakeSyncClock();
  final SyncSchedule schedule = const SyncSchedule();

  late final SyncScheduler scheduler = build();

  SyncScheduler build() => SyncScheduler(
    engine: SyncEngine(db),
    transport: () => configured ? wire : null,
    schedule: schedule,
    clock: clock,
    random: math.Random(20260821),
  );

  late final folders = FolderRepository(db);
  late final collections = CollectionRepository(db);
  late final outbox = OutboxRepository(db);
  late final syncState = SyncStateStore(db);

  /// Moves time forward and lets whatever it started finish.
  Future<void> advance(Duration by) =>
      clock.advance(by, settle: scheduler.whenIdle);

  /// Moves time forward without waiting — for the tests that hold the wire
  /// open on purpose and would otherwise wait forever.
  Future<void> advanceOnly(Duration by) async {
    await clock.advance(by);
    await pumpEventQueue();
  }

  /// A collection to send. Returns its id; how many intents that is, is the
  /// repositories' business and never asserted as a literal here.
  Future<String> seedMutations() async {
    final root = await folders.ensureRoot();
    final (collection, violation) = await collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(violation, isNull);
    return collection!.id;
  }

  Future<void> stop() async {
    scheduler.dispose();
    _http.close();
    await backend.stop();
    await db.close();
  }
}

void main() {
  group('the backoff itself', () {
    const policy = RetryPolicy();

    test('doubles from thirty seconds and stops at the cap', () {
      expect(policy.nominalDelay(1), const Duration(seconds: 30));
      expect(policy.nominalDelay(2), const Duration(minutes: 1));
      expect(policy.nominalDelay(3), const Duration(minutes: 2));
      expect(policy.nominalDelay(4), const Duration(minutes: 4));
      expect(policy.nominalDelay(5), const Duration(minutes: 8));
      expect(policy.nominalDelay(6), const Duration(minutes: 16));
      expect(policy.nominalDelay(7), const Duration(minutes: 30));
      // A week of failing is still half an hour, never longer.
      expect(policy.nominalDelay(200), const Duration(minutes: 30));
    });

    test('jitter only ever shortens, and never past the fifth', () {
      final random = math.Random(4);
      for (var failure = 1; failure <= 12; failure++) {
        final nominal = policy.nominalDelay(failure);
        for (var i = 0; i < 50; i++) {
          final delay = policy.delayAfter(failure, random.nextDouble());
          expect(delay, lessThanOrEqualTo(nominal));
          expect(
            delay.inMilliseconds,
            greaterThanOrEqualTo((nominal.inMilliseconds * 0.8).floor()),
          );
        }
      }
      // Neither end of the roll leaves the band.
      expect(policy.delayAfter(1, 0), const Duration(seconds: 30));
      expect(policy.delayAfter(1, 0.999).inMilliseconds, closeTo(24000, 10));
    });
  });

  group('triggers', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start());
    tearDown(() => h.stop());

    test(
      'a launch waits out a jittered start before it touches anything',
      () async {
        h.scheduler.onAppLaunch();

        expect(
          h.wire.changesCalls,
          0,
          reason: 'nothing runs at the instant of launch',
        );
        final wake = h.clock.nextDelay!;
        expect(wake, lessThan(h.schedule.startJitter));

        await h.advance(h.schedule.startJitter);
        expect(h.wire.changesCalls, 1);
        expect(h.scheduler.status.phase, SyncPhase.idle);
      },
    );

    test(
      'everything that arrives during a run becomes one follow-up',
      () async {
        h.wire.gate = Completer<void>();
        h.scheduler.onAppLaunch();
        await h.advanceOnly(h.schedule.startJitter);
        expect(h.wire.changesCalls, 1, reason: 'one opportunity, held open');

        h.scheduler.onLocalMutation();
        h.scheduler.onLocalMutation();
        h.scheduler.onLocalMutation();
        h.scheduler.onConnectivityRegained();
        final manual = h.scheduler.syncNow();

        h.wire.release();
        await h.scheduler.whenIdle();
        await manual;

        expect(
          h.wire.changesCalls,
          2,
          reason: 'five triggers during one run buy exactly one more run',
        );
      },
    );

    test('a Sync now during a run waits for the run it asked for', () async {
      h.wire.gate = Completer<void>();
      h.scheduler.onAppLaunch();
      await h.advanceOnly(h.schedule.startJitter);

      var settled = false;
      final manual = h.scheduler.syncNow().then((_) => settled = true);
      h.wire.release();
      await pumpEventQueue();
      // The opportunity that was already going is not the one they asked for.
      await h.scheduler.whenIdle();
      await manual;
      expect(settled, isTrue);
      expect(h.wire.changesCalls, 2);
    });

    test(
      'a trigger during the follow-up waits for a timer, not the loop',
      () async {
        h.wire.gate = Completer<void>();
        h.scheduler.onAppLaunch();
        await h.advanceOnly(h.schedule.startJitter);
        expect(h.wire.changesCalls, 1);

        h.scheduler.onLocalMutation();
        final first = h.wire.gate!;
        h.wire.gate = Completer<void>();
        first.complete();
        await pumpEventQueue();
        expect(h.wire.changesCalls, 2, reason: 'the follow-up, held open');

        // A third wave, arriving during the one follow-up the run is allowed.
        h.scheduler.onLocalMutation();
        final second = h.wire.gate!;
        h.wire.gate = null;
        second.complete();
        await h.scheduler.whenIdle();

        expect(
          h.wire.changesCalls,
          2,
          reason: 'the bound holds: no third run inside the same pump',
        );
        expect(
          h.clock.nextDelay,
          lessThanOrEqualTo(h.schedule.mutationDebounce),
        );

        await h.advance(h.schedule.mutationDebounce);
        expect(h.wire.changesCalls, 3, reason: 'and it is not lost either');
      },
    );

    test('the foreground tick keeps taking opportunities', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      expect(h.wire.changesCalls, 1);

      await h.advance(h.schedule.foregroundInterval + h.schedule.startJitter);
      expect(h.wire.changesCalls, 2);
      await h.advance(h.schedule.foregroundInterval + h.schedule.startJitter);
      expect(h.wire.changesCalls, 3);
    });

    test('a burst of local mutations is one push', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      expect(h.wire.mutationCalls, 0, reason: 'an empty outbox pushes nothing');

      await h.seedMutations();
      h.scheduler.onLocalMutation();
      h.scheduler.onLocalMutation();
      h.scheduler.onLocalMutation();

      final wake = h.clock.nextDelay!;
      expect(wake, lessThanOrEqualTo(h.schedule.mutationDebounce));

      await h.advance(h.schedule.mutationDebounce);
      expect(h.wire.mutationCalls, 1, reason: 'three writes, one push');
      expect(await h.outbox.pendingCount(), 0);
    });

    test(
      'the first mutation of a burst fixes the moment; later ones join it',
      () async {
        h.scheduler.onAppLaunch();
        await h.advance(h.schedule.startJitter);
        final before = h.wire.changesCalls;

        h.scheduler.onLocalMutation();
        await h.advance(const Duration(seconds: 3));
        expect(h.wire.changesCalls, before, reason: 'still inside the window');

        h.scheduler.onLocalMutation();
        h.scheduler.onLocalMutation();
        expect(
          h.clock.nextDelay,
          const Duration(seconds: 2),
          reason: 'a later mutation must not push the window out',
        );

        await h.advance(const Duration(seconds: 2));
        expect(h.wire.changesCalls, before + 1);
      },
    );
  });

  group('the app leaving the foreground', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start());
    tearDown(() => h.stop());

    test('the step in flight finishes and nothing else starts', () async {
      h.wire.gate = Completer<void>();
      h.scheduler.onAppLaunch();
      await h.advanceOnly(h.schedule.startJitter);
      expect(h.wire.changesCalls, 1);

      h.scheduler.onLocalMutation();
      h.scheduler.onAppPaused();
      h.wire.release();
      await h.scheduler.whenIdle();

      expect(
        h.wire.changesCalls,
        1,
        reason: 'the absorbed follow-up does not run in the background',
      );
      expect(
        h.clock.pendingAlarms,
        0,
        reason: 'every timer is cancelled when the app is not in front',
      );

      await h.advance(const Duration(hours: 3));
      expect(h.wire.changesCalls, 1, reason: 'and it stays that way');
    });

    test('a trigger while it is away schedules nothing at all', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      h.scheduler.onAppPaused();

      h.scheduler.onLocalMutation();
      h.scheduler.onConnectivityRegained();
      expect(h.clock.pendingAlarms, 0);

      await h.advance(const Duration(hours: 1));
      expect(h.wire.changesCalls, 1);
    });

    test('coming back takes an opportunity', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      h.scheduler.onAppPaused();
      await h.advance(
        h.schedule.minimumResumeInterval + const Duration(minutes: 1),
      );

      h.scheduler.onAppResumed();
      await h.advance(h.schedule.startJitter);
      expect(h.wire.changesCalls, 2);
      expect(h.clock.pendingAlarms, 1, reason: 'the foreground tick, re-armed');
    });

    test('coming straight back does not', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      h.scheduler.onAppPaused();
      await h.advance(const Duration(seconds: 20));

      h.scheduler.onAppResumed();
      expect(
        h.clock.pendingAlarms,
        1,
        reason: 'the tick only — a twenty-second detour is not new information',
      );
      await h.advance(h.schedule.startJitter);
      expect(h.wire.changesCalls, 1);
    });
  });

  group('a failure', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start());
    tearDown(() => h.stop());

    Future<void> failOnce() async {
      final before = h.wire.changesCalls;
      await h.advance(const Duration(minutes: 31));
      expect(h.wire.changesCalls, greaterThan(before));
    }

    test('waits longer each time, and never longer than the cap', () async {
      h.wire.reachable = false;
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);

      expect(h.wire.changesCalls, 1, reason: 'it tried; the wire was cut');
      expect(h.scheduler.status.phase, SyncPhase.retrying);
      expect(h.scheduler.status.nextRetryAt, isNotNull);

      // Measured from the moment the opportunity ran, which is the moment the
      // wait was armed — not from wherever the test has advanced to since.
      void expectBand(Duration nominal) {
        final wait = h.scheduler.status.nextRetryAt!.difference(
          h.clock.lastFiredAt!,
        );
        expect(wait, lessThanOrEqualTo(nominal));
        expect(
          wait.inMilliseconds,
          greaterThanOrEqualTo((nominal.inMilliseconds * 0.8).floor()),
        );
      }

      expectBand(const Duration(seconds: 30));
      await h.advance(const Duration(seconds: 31));
      expectBand(const Duration(minutes: 1));
      await h.advance(const Duration(minutes: 2));
      expectBand(const Duration(minutes: 2));

      for (var i = 0; i < 8; i++) {
        await failOnce();
      }
      expectBand(const Duration(minutes: 30));
    });

    test('a local mutation does not walk through the wait', () async {
      h.wire.reachable = false;
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);

      h.scheduler.onLocalMutation();
      expect(
        h.clock.nextDelay,
        greaterThan(h.schedule.mutationDebounce),
        reason: 'the retry time is a floor, not a candidate',
      );
    });

    test('asking, or a reconnection, clears the wait immediately', () async {
      h.wire.reachable = false;
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      expect(h.scheduler.status.phase, SyncPhase.retrying);

      h.scheduler.onConnectivityRegained();
      expect(h.scheduler.status.phase, isNot(SyncPhase.retrying));
      expect(h.clock.nextDelay, lessThan(h.schedule.startJitter));

      h.wire.reachable = true;
      final manual = h.scheduler.syncNow();
      expect(h.clock.nextDelay, Duration.zero);
      await h.advance(Duration.zero);
      await manual;

      expect(h.scheduler.status.phase, SyncPhase.idle);
      expect(h.scheduler.status.nextRetryAt, isNull);
      expect(h.scheduler.status.lastSuccessAt, isNotNull);
    });

    test('a success puts the wait back to the beginning', () async {
      h.wire.reachable = false;
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      await h.advance(const Duration(seconds: 31));
      await h.advance(const Duration(minutes: 2));

      h.wire.reachable = true;
      await h.advance(const Duration(minutes: 5));
      expect(h.scheduler.status.phase, SyncPhase.idle);

      // A resume rather than a tick, so exactly one opportunity happens and
      // the ladder cannot climb inside the window this test advances through.
      h.wire.reachable = false;
      h.scheduler.onAppPaused();
      await h.advance(
        h.schedule.minimumResumeInterval + const Duration(minutes: 1),
      );
      h.scheduler.onAppResumed();
      await h.advance(h.schedule.startJitter);

      expect(h.scheduler.status.phase, SyncPhase.retrying);
      expect(
        h.scheduler.status.nextRetryAt!.difference(h.clock.lastFiredAt!),
        lessThanOrEqualTo(const Duration(seconds: 30)),
        reason: 'the count resets, so the next wait is the first one again',
      );
    });
  });

  group('interruption', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start());
    tearDown(() => h.stop());

    test('a pull cut off leaves everything for the next opportunity', () async {
      final collectionId = await h.seedMutations();
      final seeded = await h.outbox.pendingCount();
      expect(seeded, greaterThan(0));
      h.backend.dieOnChangesRequest = 1;

      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);

      expect(
        await h.outbox.pendingCount(),
        seeded,
        reason: 'nothing acknowledged',
      );
      expect(await h.syncState.cursor(), 0);
      expect(h.scheduler.status.phase, SyncPhase.retrying);

      await h.advance(const Duration(seconds: 31));
      expect(await h.outbox.pendingCount(), 0);
      expect(h.backend.kindRows('collection'), contains(collectionId));
      expect(h.scheduler.status.phase, SyncPhase.idle);
    });

    test('a cut between two steps keeps what the earlier one landed', () async {
      final collectionId = await h.seedMutations();
      // Request 1 is the opening pull; request 2 is the pull that follows a
      // push that landed. Dying there is a kill between two steps.
      h.backend.dieOnChangesRequest = 2;

      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);

      expect(
        await h.outbox.pendingCount(),
        0,
        reason: 'the push acknowledged before the connection went',
      );
      expect(h.backend.kindRows('collection'), contains(collectionId));
      expect(h.scheduler.status.phase, SyncPhase.retrying);

      await h.advance(const Duration(seconds: 31));
      expect(h.scheduler.status.phase, SyncPhase.idle);
      expect(await h.syncState.cursor(), greaterThan(0));
    });

    test(
      'a scheduler that never comes back leaves nothing for the next',
      () async {
        await h.seedMutations();
        final seeded = await h.outbox.pendingCount();
        expect(seeded, greaterThan(0));
        h.backend.failMutationsTimes = 1;

        h.scheduler.onAppLaunch();
        await h.advance(h.schedule.startJitter);
        expect(await h.outbox.pendingCount(), seeded);

        h.scheduler.dispose();
        expect(h.clock.pendingAlarms, 0);

        // A cold launch: a new scheduler over the same database, which is all
        // the state there is.
        final next = h.build();
        next.onAppLaunch();
        await h.clock.advance(h.schedule.startJitter, settle: next.whenIdle);

        expect(await h.outbox.pendingCount(), 0);
        expect(next.status.phase, SyncPhase.idle);
        next.dispose();
      },
    );
  });

  group('a device with no transport', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start(configured: false));
    tearDown(() => h.stop());

    test('does nothing, says so, and calls it no error', () async {
      expect(h.scheduler.status.phase, SyncPhase.neverConfigured);

      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      await h.advance(h.schedule.foregroundInterval * 3);

      expect(h.wire.changesCalls, 0);
      expect(
        (await h.syncState.current()).lastAttemptAt,
        isNull,
        reason: 'an unconfigured device never records an attempt',
      );
      expect(h.scheduler.status.phase, SyncPhase.neverConfigured);
      expect(h.scheduler.status.nextRetryAt, isNull);
    });

    test('Sync now returns quietly rather than failing', () async {
      final manual = h.scheduler.syncNow();
      await h.advance(Duration.zero);
      await manual;
      expect(h.scheduler.status.phase, SyncPhase.neverConfigured);
      expect(h.wire.changesCalls, 0);
    });

    test('and starts working the moment one appears', () async {
      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);
      expect(h.wire.changesCalls, 0);

      h.configured = true;
      await h.advance(h.schedule.foregroundInterval + h.schedule.startJitter);
      expect(h.wire.changesCalls, 1);
      expect(h.scheduler.status.phase, SyncPhase.idle);
    });
  });

  group('what it publishes', () {
    late _Harness h;

    setUp(() async => h = await _Harness.start());
    tearDown(() => h.stop());

    test(
      'a healthy opportunity says syncing, then quiet, and no more',
      () async {
        final seen = <SyncPhase>[];
        final subscription = h.scheduler.statusChanges.listen(
          (view) => seen.add(view.phase),
        );
        addTearDown(subscription.cancel);

        h.scheduler.onAppLaunch();
        await h.advance(h.schedule.startJitter);
        await pumpEventQueue();

        expect(seen, [SyncPhase.syncing, SyncPhase.idle]);
        expect(h.scheduler.status.isHealthy, isTrue);
        expect(h.scheduler.status.problemCount, 0);
      },
    );

    test('a refused change is counted and asks for attention', () async {
      final root = await h.folders.ensureRoot();
      // An intent the backend refuses deterministically, journalled the way an
      // older version of the app might have left one behind.
      await h.db
          .into(h.db.outbox)
          .insert(
            OutboxCompanion.insert(
              mutationId: 'poisoned-mutation',
              entityKind: 'folder',
              entityId: 'poisoned-folder',
              op: 'upsert',
              payload: jsonEncode({
                'parent_id': root.id,
                'kind': 'user',
                'name': 'Poison',
                'sort_key': 0,
                FakeBackend.rejectMarker: true,
              }),
              createdAt: DateTime.utc(2026, 8, 21),
            ),
          );
      await h.seedMutations();

      h.scheduler.onAppLaunch();
      await h.advance(h.schedule.startJitter);

      expect(h.scheduler.status.problemCount, 1);
      expect(h.scheduler.status.pendingCount, 0, reason: 'the rest still went');
      expect(h.scheduler.status.phase, SyncPhase.attention);
      expect(h.scheduler.status.isHealthy, isFalse);
    });

    test(
      'disposing cancels every timer and stops answering triggers',
      () async {
        h.scheduler.onAppLaunch();
        await h.advance(h.schedule.startJitter);
        expect(h.clock.pendingAlarms, greaterThan(0));

        h.scheduler.dispose();
        expect(h.clock.pendingAlarms, 0);

        h.scheduler.onAppLaunch();
        h.scheduler.onAppResumed();
        h.scheduler.onLocalMutation();
        h.scheduler.onConnectivityRegained();
        await h.scheduler.syncNow();
        expect(h.clock.pendingAlarms, 0);

        final before = h.wire.changesCalls;
        await h.clock.advance(const Duration(hours: 2));
        expect(h.wire.changesCalls, before);
      },
    );
  });
}
