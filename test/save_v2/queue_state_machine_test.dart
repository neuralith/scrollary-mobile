/// The V2 save queue's state machine (roadmap E3).
///
/// The properties this file exists to hold, in the order they matter:
///
/// 1. **exactly one winner.** Every claim and every cancel is one conditional
///    `UPDATE`; when two race, one lands and the loser is told so it can act
///    on the truth instead of on what it read a moment ago;
/// 2. **cancelling preserves the row, dismissing deletes it** — and dismissing
///    refuses anything still live;
/// 3. **an Undo puts a waiting row back where it was**, keeping its
///    `order_index` rather than sending it to the end of the queue;
/// 4. **a killed run is demoted, never resurrected** — which is why a
///    cancellation is written the instant it is asked for;
/// 5. **nothing starts without an explicit Start**, and that authorisation is
///    never on disk.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';

import 'support/capture_harness.dart';

void main() {
  late CaptureHarness h;
  late SaveQueueRepository queue;

  setUp(() {
    h = CaptureHarness();
    queue = h.queue;
  });
  tearDown(() => h.close());

  /// One Entry with one Location, and a task waiting on it.
  Future<({String entryId, String locationId, String url, SaveTask task})>
  seedTask() async {
    final seeded = await h.repos.seedLibrary();
    final result = await queue.enqueue(
      entryId: seeded.entry.id,
      locationId: seeded.location.id,
      locationUrl: seeded.location.url,
      captureMode: CaptureMode.imageSequence,
    );
    return (
      entryId: seeded.entry.id,
      locationId: seeded.location.id,
      url: seeded.location.url,
      task: result.task!,
    );
  }

  group('the unit of work is (Entry, Location)', () {
    test('a queued task names both, and carries the address as a value', () {
      return seedTask().then((s) {
        expect(s.task.entryId, s.entryId);
        expect(s.task.locationId, s.locationId);
        expect(s.task.locationUrl, s.url);
        expect(s.task.state, SaveTaskState.queued);
        expect(s.task.origin, SaveTaskOrigin.queue);
        expect(s.task.captureMode, CaptureMode.imageSequence);
      });
    });

    test('a retracted Location leaves the task with its address', () async {
      final s = await seedTask();
      final seeded = await h.repos.entries.locationById(s.locationId);
      expect(seeded, isNotNull);

      // Simulate the Location row going: the FK is ON DELETE SET NULL, so the
      // pointer clears and the address — which is what the task is about —
      // stays.
      await (h.db.delete(
        h.db.locations,
      )..where((l) => l.id.equals(s.locationId))).go();

      final task = await queue.byId(s.task.id);
      expect(task!.locationId, isNull);
      expect(task.locationUrl, s.url, reason: 'the task still knows where');
    });

    test('a second request for the same Entry is the same request', () async {
      final s = await seedTask();
      final again = await queue.enqueue(
        entryId: s.entryId,
        locationId: s.locationId,
        locationUrl: s.url,
        captureMode: CaptureMode.imageSequence,
      );
      expect(again.alreadyQueued, isTrue);
      expect(again.task!.id, s.task.id);
      expect(await queue.all(), hasLength(1));
    });
  });

  group('single winner', () {
    test('two claims race and exactly one takes the row', () async {
      final s = await seedTask();
      final results = await Future.wait([
        queue.claim(s.task.id),
        queue.claim(s.task.id),
      ]);
      expect(
        results.where((t) => t != null),
        hasLength(1),
        reason: 'one conditional UPDATE lands; the loser is told with null',
      );
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.running);
    });

    test('a claim and a cancel race, and the loser is told', () async {
      final s = await seedTask();
      final results = await Future.wait<Object?>([
        queue.claim(s.task.id),
        queue.cancel(s.task.id),
      ]);
      final claimed = results[0] as SaveTask?;
      final cancelled = results[1] as SaveCancelOutcome;

      // Exactly one of the two conditional updates against `queued` succeeded.
      expect(
        (claimed == null) ==
            (cancelled == SaveCancelOutcome.cancelledBeforeStart),
        isTrue,
        reason:
            'either the claim won and the cancel fell through to stopping a '
            'running row, or the cancel won and the claim returned null',
      );
      // Either way the user asked for it to stop, and it stopped.
      final row = await queue.byId(s.task.id);
      expect(row!.state, SaveTaskState.cancelled);
      expect(
        cancelled,
        anyOf(
          SaveCancelOutcome.cancelledBeforeStart,
          SaveCancelOutcome.stoppingRunning,
        ),
      );
    });

    test('a claim that lost skips the row rather than reviving it', () async {
      final s = await seedTask();
      expect(
        await queue.cancel(s.task.id),
        SaveCancelOutcome.cancelledBeforeStart,
      );
      expect(await queue.claim(s.task.id), isNull);
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.cancelled);
    });

    test('the conditional update is the only writer, and it reports', () async {
      final s = await seedTask();
      expect(
        await queue.updateIfState(
          id: s.task.id,
          expected: [SaveTaskState.running],
          values: SaveQueueCompanion(
            state: Value(SaveTaskState.completed.name),
          ),
        ),
        isFalse,
        reason: 'the row is queued, not running',
      );
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.queued);
    });

    test(
      'a finish cannot overwrite a cancellation that landed first',
      () async {
        final s = await seedTask();
        await queue.claim(s.task.id);
        expect(
          await queue.cancel(s.task.id),
          SaveCancelOutcome.stoppingRunning,
        );

        // The worker unwinds and tries to write its own verdict.
        expect(
          await queue.finish(s.task.id, state: SaveTaskState.completed),
          isFalse,
        );
        final row = await queue.byId(s.task.id);
        expect(row!.state, SaveTaskState.cancelled);
        expect(row.outcome, kSaveTaskStopping);
      },
    );
  });

  group('cancelling preserves the row; dismissing deletes it', () {
    test('a cancelled row is history, not a deletion', () async {
      final s = await seedTask();
      await queue.cancel(s.task.id);
      final row = await queue.byId(s.task.id);
      expect(row, isNotNull);
      expect(row!.state, SaveTaskState.cancelled);
      expect(row.outcome, kSaveTaskCancelledBeforeStart);
      expect(row.stopReason, StopReason.cancelledByUser);
    });

    test('there is no sixth state', () {
      expect(SaveTaskState.values, hasLength(5));
      expect(SaveTaskState.values.map((s) => s.name), [
        'queued',
        'running',
        'completed',
        'failed',
        'cancelled',
      ]);
    });

    test('Remove from Activity refuses a waiting row', () async {
      final s = await seedTask();
      expect(await queue.removeTerminal(s.task.id), isFalse);
      expect(await queue.byId(s.task.id), isNotNull);
    });

    test('Remove from Activity refuses a running row', () async {
      final s = await seedTask();
      await queue.claim(s.task.id);
      expect(await queue.removeTerminal(s.task.id), isFalse);
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.running);
    });

    test('Remove from Activity takes a terminal row', () async {
      final s = await seedTask();
      await queue.cancel(s.task.id);
      expect(await queue.removeTerminal(s.task.id), isTrue);
      expect(await queue.byId(s.task.id), isNull);
      // The row was never the content: the Entry is exactly as it was.
      expect(await h.repos.entries.byId(s.entryId), isNotNull);
    });
  });

  group('Undo restores the place in the queue', () {
    test('a restored row keeps its order index, not the back', () async {
      final seeded = await h.repos.seedLibrary();
      final second = await h.repos.entries.createInCollection(
        collectionId: seeded.collection.id,
        ordinal: 102,
        title: 'Part 102',
      );
      final third = await h.repos.entries.createInCollection(
        collectionId: seeded.collection.id,
        ordinal: 103,
        title: 'Part 103',
      );

      final a = (await queue.enqueue(
        entryId: seeded.entry.id,
        locationUrl: seeded.location.url,
      )).task!;
      final b = (await queue.enqueue(
        entryId: second.$1!.id,
        locationUrl: 'https://reading.example.com/serial-alpha/part-102',
      )).task!;
      final c = (await queue.enqueue(
        entryId: third.$1!.id,
        locationUrl: 'https://reading.example.com/serial-alpha/part-103',
      )).task!;

      expect(await queue.cancel(b.id), SaveCancelOutcome.cancelledBeforeStart);
      expect(await queue.restoreQueued(b.id), isTrue);

      final pending = await queue.pending();
      expect(
        pending.map((t) => t.id),
        [a.id, b.id, c.id],
        reason: 'an accidental tap must not reorder the queue',
      );
      final restored = await queue.byId(b.id);
      expect(restored!.orderIndex, b.orderIndex);
      expect(restored.state, SaveTaskState.queued);
      expect(restored.outcome, isNull);
      expect(restored.finishedAt, isNull);
    });

    test('only a cancelled row can be restored', () async {
      final s = await seedTask();
      expect(await queue.restoreQueued(s.task.id), isFalse);
      await queue.claim(s.task.id);
      expect(await queue.restoreQueued(s.task.id), isFalse);
      await queue.finish(s.task.id, state: SaveTaskState.completed);
      expect(
        await queue.restoreQueued(s.task.id),
        isFalse,
        reason: 'an undo racing a history clear resurrects nothing',
      );
    });
  });

  group('a killed run is demoted, never resurrected', () {
    test('a row left running is demoted to queued', () async {
      final s = await seedTask();
      await queue.claim(s.task.id);
      expect((await queue.byId(s.task.id))!.startedAt, isNotNull);

      expect(await queue.demoteInterruptedRuns(), 1);
      final row = await queue.byId(s.task.id);
      expect(row!.state, SaveTaskState.queued);
      expect(
        row.startedAt,
        isNull,
        reason: 'it never ran to completion and must not pretend it did',
      );
    });

    test('a cancellation survives the kill', () async {
      final s = await seedTask();
      await queue.claim(s.task.id);
      await queue.cancel(s.task.id);

      // The process dies here. On the next start:
      expect(await queue.demoteInterruptedRuns(), 0);
      expect(
        (await queue.byId(s.task.id))!.state,
        SaveTaskState.cancelled,
        reason:
            'the row moved to cancelled the moment it was asked for, so the '
            'demotion cannot hand the work back',
      );
    });
  });

  group('cooperative stopping', () {
    test(
      'a running cancel asks the worker to stop at its next safe point',
      () async {
        final s = await seedTask();
        await queue.claim(s.task.id);
        expect(queue.shouldContinue(s.task.id), isTrue);

        expect(
          await queue.cancel(s.task.id),
          SaveCancelOutcome.stoppingRunning,
        );
        expect(
          queue.shouldContinue(s.task.id),
          isFalse,
          reason: 'nothing is killed mid-write; the worker asks and stops',
        );
        expect(queue.takeStopRequest(s.task.id), isTrue);
        expect(queue.takeStopRequest(s.task.id), isFalse);
      },
    );

    test('a flag is never raised for a task that already finished', () async {
      final s = await seedTask();
      await queue.claim(s.task.id);
      await queue.finish(s.task.id, state: SaveTaskState.completed);
      expect(await queue.cancel(s.task.id), SaveCancelOutcome.alreadyFinished);
      expect(queue.shouldContinue(s.task.id), isTrue);
    });

    test('cancelling something that is gone says so', () async {
      expect(await queue.cancel('no-such-row'), SaveCancelOutcome.gone);
    });
  });

  group('nothing starts without an explicit Start', () {
    test('a queued save is not eligible until Start is pressed', () async {
      final s = await seedTask();
      expect(await queue.eligible(), isEmpty);
      expect(queue.saveStartAuthorised, isFalse);

      queue.authoriseStart();
      expect(await queue.eligible(), hasLength(1));
      expect((await queue.eligible()).single.id, s.task.id);

      queue.revokeStart();
      expect(await queue.eligible(), isEmpty);
    });

    test('the authorisation is not persisted', () async {
      await seedTask();
      queue.authoriseStart();

      // A relaunch: a second repository over the same database.
      final relaunched = SaveQueueRepository(h.db, now: h.repos.tick);
      expect(relaunched.saveStartAuthorised, isFalse);
      expect(
        await relaunched.eligible(),
        isEmpty,
        reason: 'queued rows survive a restart; permission does not',
      );
      expect(await relaunched.pending(), hasLength(1));
    });
  });

  group('the restricted-site policy, at the queue boundary', () {
    test('an enqueue of a restricted address writes no row at all', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await queue.enqueue(
        entryId: seeded.entry.id,
        locationUrl: restrictedUrl(),
      );
      expect(result.restricted, isTrue);
      expect(result.refusedReason, kCaptureRestrictedMessage);
      expect(result.task, isNull);
      expect(await queue.all(), isEmpty);
    });

    test(
      'a stale queued row is settled as a terminal failure, not deleted',
      () async {
        final seeded = await h.repos.seedLibrary();
        // A row written when the host was still permitted.
        final permitted = (await queue.enqueue(
          entryId: seeded.entry.id,
          locationUrl: seeded.location.url,
        )).task!;
        await (h.db.update(h.db.saveQueue)
              ..where((t) => t.id.equals(permitted.id)))
            .write(SaveQueueCompanion(locationUrl: Value(restrictedUrl())));

        final stale = (await queue.byId(permitted.id))!;
        expect(await queue.settleIfRestricted(stale), isTrue);

        final row = await queue.byId(permitted.id);
        expect(row, isNotNull, reason: 'never silently deleted');
        expect(row!.state, SaveTaskState.failed);
        expect(row.stopReason, StopReason.captureRestrictedForSite);
        expect(row.outcome, kCaptureRestrictedMessage);
        expect(row.lastError, kCaptureRestrictedMessage);
      },
    );

    test('a permitted task is left alone', () async {
      final s = await seedTask();
      expect(await queue.settleIfRestricted(s.task), isFalse);
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.queued);
    });

    test(
      'a retry cannot turn a restricted history row back into work',
      () async {
        final seeded = await h.repos.seedLibrary();
        final task = (await queue.enqueue(
          entryId: seeded.entry.id,
          locationUrl: seeded.location.url,
        )).task!;
        await (h.db.update(h.db.saveQueue)..where((t) => t.id.equals(task.id)))
            .write(SaveQueueCompanion(locationUrl: Value(restrictedUrl())));
        await queue.settleIfRestricted((await queue.byId(task.id))!);

        expect(await queue.retry(task.id), isNull);
        expect(await queue.pending(), isEmpty);
      },
    );

    test(
      'a retry of an ordinary failure goes to the back of the queue',
      () async {
        final s = await seedTask();
        await queue.claim(s.task.id);
        await queue.finish(
          s.task.id,
          state: SaveTaskState.failed,
          lastError: 'the connection dropped',
        );
        final retried = await queue.retry(s.task.id);
        expect(retried, isNotNull);
        expect(retried!.id, isNot(s.task.id));
        expect(retried.state, SaveTaskState.queued);
        expect(retried.orderIndex, greaterThan(s.task.orderIndex));
      },
    );
  });

  group('history is bounded and is never the content', () {
    test('a direct row is written terminal', () async {
      final seeded = await h.repos.seedLibrary();
      final row = await queue.recordDirectOutcome(
        entryId: seeded.entry.id,
        locationUrl: seeded.location.url,
        state: SaveTaskState.completed,
        outcome: 'saved',
      );
      expect(row.origin, SaveTaskOrigin.direct);
      expect(row.isTerminal, isTrue);
      expect(
        await queue.pending(),
        isEmpty,
        reason: 'a direct save created no pending work to release',
      );
    });

    test('clearing history spares live rows', () async {
      final s = await seedTask();
      final seeded2 = await h.repos.entries.createStandalone(
        folderId: (await h.repos.folders.ensureRoot()).id,
        title: 'Loose page',
      );
      final done = (await queue.enqueue(
        entryId: seeded2.$1!.id,
        locationUrl: 'https://reading.example.com/loose',
      )).task!;
      await queue.claim(done.id);
      await queue.finish(done.id, state: SaveTaskState.completed);

      expect(await queue.clearHistory(), 1);
      expect(await queue.byId(done.id), isNull);
      expect((await queue.byId(s.task.id))!.state, SaveTaskState.queued);
    });
  });
}
