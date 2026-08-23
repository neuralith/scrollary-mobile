/// The V2 save queue's worker loop (roadmap E3).
///
/// `queue_state_machine_test.dart` holds the row-level properties; this file
/// holds the ones only the loop can break, and they are the ones V1's queue
/// tests were written for. In the order they matter:
///
/// 1. **one row at a time, in queue order** — the second task starts only
///    after the first has its terminal verdict;
/// 2. **one bad row does not discard the batch** — the rest still run, and the
///    failure keeps its own reason rather than ending the run;
/// 3. **stopping leaves the remainder queued, never cancelled** — a stop says
///    nothing about work nobody has touched yet;
/// 4. **a claim that lost is skipped, not revived**, and the loop carries on
///    to the next row;
/// 5. **draining revokes the Start** — more work later is a new decision;
/// 6. **a full disk stops the batch without condemning it** — the row that
///    could not start is named, and the rest stay queued.
///
/// The capture half is a stand-in page source, exactly as the rest of the
/// lane does it: no WebView, no network, and the real FileStore underneath.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';

import 'support/capture_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaptureHarness h;
  late _RacedQueue queue;
  late _ScriptedSource source;
  late QueueRunner runner;
  late String collectionId;
  var runnerDisposed = false;

  /// Disposing is a test action in some of these, so it has to be idempotent.
  void disposeRunner() {
    if (runnerDisposed) return;
    runnerDisposed = true;
    runner.dispose();
  }

  setUp(() async {
    h = CaptureHarness();
    queue = _RacedQueue(h.db, now: h.repos.tick);
    source = _ScriptedSource();
    runnerDisposed = false;
    runner = QueueRunner(
      queue: queue,
      captureServiceFor: () => h.captureWith(source),
    );
    collectionId = (await h.repos.seedLibrary()).collection.id;
  });

  tearDown(() async {
    disposeRunner();
    await h.close();
  });

  String urlFor(int ordinal) =>
      'https://reading.example.com/serial-alpha/part-$ordinal';

  /// A fresh Entry in the seeded collection, with a task waiting on it. One
  /// Entry per task, because an Entry has one open task by construction.
  Future<SaveTask> queueEntry(int ordinal) async {
    final (entry, violation) = await h.repos.entries.createInCollection(
      collectionId: collectionId,
      ordinal: ordinal.toDouble(),
      title: 'Part $ordinal',
    );
    expect(violation, isNull);
    final result = await queue.enqueue(
      entryId: entry!.id,
      locationUrl: urlFor(ordinal),
      captureMode: CaptureMode.imageSequence,
    );
    return result.task!;
  }

  /// Yield to the loop until [done], rather than guessing at a delay.
  Future<void> pumpUntil(bool Function() done, String what) async {
    for (var i = 0; i < 500; i++) {
      if (done()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('timed out waiting for $what');
  }

  test(
    'the batch counts what it set out to do, and how far it has got',
    () async {
      // The numbers the panel draws "Entry 3 of 10" from. V2 captures one row at
      // a time, so which entry is a fact about the loop rather than about the
      // engine — the engine only ever sees one.
      for (var i = 1; i <= 3; i++) {
        await queueEntry(i);
      }
      expect(runner.batchTotal, 0, reason: 'nothing running, nothing to count');
      expect(runner.batchPosition, 0);

      await runner.start();

      expect(runner.batchDone, 3);
      expect(
        runner.batchPosition,
        0,
        reason: 'the batch is over, so there is no entry to be on',
      );
    },
  );

  group('the queue drains one row at a time', () {
    test('the second task starts only after the first has finished', () async {
      final first = await queueEntry(102);
      final second = await queueEntry(103);
      final gate = source.holdAt(urlFor(102));

      final draining = runner.start();
      await pumpUntil(() => source.started.length == 1, 'the first capture');

      expect(source.started, [urlFor(102)]);
      expect(runner.isRunning, isTrue);
      expect(runner.activeTaskId, first.id);
      expect((await queue.byId(first.id))!.state, SaveTaskState.running);
      expect(
        (await queue.byId(second.id))!.state,
        SaveTaskState.queued,
        reason: 'one row is claimed at a time; the rest keep waiting',
      );

      gate.complete();
      await draining;

      expect(source.started, [urlFor(102), urlFor(103)]);
      final ran = await queue.byId(first.id);
      final then = await queue.byId(second.id);
      expect(ran!.state, SaveTaskState.completed);
      expect(then!.state, SaveTaskState.completed);
      expect(
        then.startedAt!.isAfter(ran.finishedAt!),
        isTrue,
        reason: 'the loop is sequential: it claims again only after a verdict',
      );
      expect(await queue.pending(), isEmpty);
    });

    test('the queue runs in queue order', () async {
      final a = await queueEntry(102);
      final b = await queueEntry(103);
      final c = await queueEntry(104);

      await runner.start();

      expect(source.started, [urlFor(102), urlFor(103), urlFor(104)]);
      for (final task in [a, b, c]) {
        expect((await queue.byId(task.id))!.state, SaveTaskState.completed);
      }
    });
  });

  group('one failure does not discard the rest of the batch', () {
    test('the rows after a failure still run, and it keeps its own '
        'verdict', () async {
      final first = await queueEntry(102);
      final failing = await queueEntry(103);
      final last = await queueEntry(104);
      source.failAt(urlFor(103), 'the surface never rendered');

      await runner.start();

      expect(source.started, [
        urlFor(102),
        urlFor(103),
        urlFor(104),
      ], reason: 'a failed row ends that row, not the batch');
      expect((await queue.byId(first.id))!.state, SaveTaskState.completed);
      expect((await queue.byId(last.id))!.state, SaveTaskState.completed);

      final failed = await queue.byId(failing.id);
      expect(failed!.state, SaveTaskState.failed);
      expect(failed.lastError, 'the surface never rendered');
      expect(failed.stopReason, StopReason.accessDenied);
      expect(failed.outcome, isNull);

      expect(await queue.pending(), isEmpty);
      expect(
        h.committedPaths(),
        hasLength(2),
        reason: 'only the two that were read committed anything',
      );
      expect(h.stagingLeftovers(), isEmpty);
    });

    test('a refused capture ends the row failed, never deleted', () async {
      final task = await queueEntry(102);
      final after = await queueEntry(103);
      source.refuseAt(urlFor(102));

      await runner.start();

      final row = await queue.byId(task.id);
      expect(row, isNotNull, reason: 'the user is owed a record of it');
      expect(row!.state, SaveTaskState.failed);
      expect(row.stopReason, StopReason.captureRestrictedForSite);
      expect(await h.repos.offline.allCopies(), hasLength(1));
      expect(h.stagingLeftovers(), isEmpty);
      expect(
        (await queue.byId(after.id))!.state,
        SaveTaskState.completed,
        reason: 'a refusal is that row\'s outcome, not the batch\'s',
      );
    });
  });

  group('stopping leaves the remainder queued, not cancelled', () {
    test('a runner disposed mid-batch leaves the untouched rows '
        'queued', () async {
      final running = await queueEntry(102);
      final untouched = await queueEntry(103);
      final gate = source.holdAt(urlFor(102));

      final draining = runner.start();
      await pumpUntil(() => source.started.length == 1, 'the first capture');

      disposeRunner();
      gate.complete();
      await draining;

      expect(source.started, [urlFor(102)], reason: 'nothing else was claimed');
      expect((await queue.byId(running.id))!.isTerminal, isTrue);
      final waiting = await queue.byId(untouched.id);
      expect(
        waiting!.state,
        SaveTaskState.queued,
        reason: 'stopping says nothing about work nobody has touched',
      );
      expect(waiting.stopReason, isNull);
      expect(waiting.finishedAt, isNull);
      expect(await queue.pending(), hasLength(1));
    });

    test('a cancel of the running row keeps its verdict and the loop '
        'carries on', () async {
      final cancelled = await queueEntry(102);
      final next = await queueEntry(103);
      final gate = source.holdAt(urlFor(102));

      final draining = runner.start();
      await pumpUntil(() => source.started.length == 1, 'the first capture');
      expect(
        await queue.cancel(cancelled.id),
        SaveCancelOutcome.stoppingRunning,
      );

      gate.complete();
      await draining;

      final row = await queue.byId(cancelled.id);
      expect(row!.state, SaveTaskState.cancelled);
      expect(row.outcome, kSaveTaskStopping);
      expect(
        (await queue.byId(next.id))!.state,
        SaveTaskState.completed,
        reason: 'stopping one row is not stopping the queue',
      );
    });
  });

  group('a claim that lost is skipped, not revived', () {
    test('a row cancelled inside the claim window is passed over', () async {
      final first = await queueEntry(102);
      final lost = await queueEntry(103);
      final last = await queueEntry(104);
      // The cancel lands between the loop reading the eligible rows and
      // claiming this one — the window the conditional UPDATE exists for.
      queue.loseClaimFor = lost.id;

      await runner.start();

      expect(source.started, [
        urlFor(102),
        urlFor(104),
      ], reason: 'the lost row is skipped and the loop carries on');
      final row = await queue.byId(lost.id);
      expect(row!.state, SaveTaskState.cancelled);
      expect(row.outcome, kSaveTaskCancelledBeforeStart);
      expect(row.startedAt, isNull, reason: 'a lost claim revives nothing');
      expect((await queue.byId(first.id))!.state, SaveTaskState.completed);
      expect((await queue.byId(last.id))!.state, SaveTaskState.completed);
      expect(await queue.pending(), isEmpty);
    });
  });

  group('draining revokes the Start', () {
    test('the authorisation lasts exactly as long as the run', () async {
      final task = await queueEntry(102);
      final gate = source.holdAt(urlFor(102));

      expect(runner.isRunning, isFalse);
      expect(runner.activeTaskId, isNull);
      expect(queue.saveStartAuthorised, isFalse);

      final draining = runner.start();
      await pumpUntil(() => source.started.length == 1, 'the capture');
      expect(queue.saveStartAuthorised, isTrue);
      expect(runner.isRunning, isTrue);
      expect(runner.needsRenderedBrowser, isTrue);
      expect(runner.activeTaskId, task.id);

      gate.complete();
      await draining;

      expect(queue.saveStartAuthorised, isFalse);
      expect(runner.isRunning, isFalse);
      expect(runner.needsRenderedBrowser, isFalse);
      expect(runner.activeTaskId, isNull);
    });

    test('work queued after the drain waits for a new Start', () async {
      await queueEntry(102);
      await runner.start();

      final later = await queueEntry(103);
      expect(
        await queue.eligible(),
        isEmpty,
        reason: 'adding more work later is a new decision',
      );
      expect((await queue.byId(later.id))!.state, SaveTaskState.queued);
    });
  });

  group('the queue order is the running order', () {
    test(
      'a row moved to the front is the one the runner takes first',
      () async {
        final a = await queueEntry(102);
        final b = await queueEntry(103);
        final c = await queueEntry(104);

        await queue.moveToFront(c.id);
        expect((await queue.pending()).map((t) => t.id), [c.id, a.id, b.id]);

        await runner.start();
        expect(
          source.started,
          [urlFor(104), urlFor(102), urlFor(103)],
          reason: 'promoting one row leaves the rest in their own order',
        );
      },
    );

    test('only a waiting row can be moved to the front', () async {
      final a = await queueEntry(102);
      final b = await queueEntry(103);
      await queue.claim(a.id);

      await queue.moveToFront(a.id);
      expect(
        (await queue.pending()).map((t) => t.id),
        [a.id, b.id],
        reason: 'a running row is not a place in the queue to rearrange',
      );
    });
  });

  group('a full disk stops the batch without condemning it', () {
    const channel = MethodChannel('webread/device_storage');

    /// A [DeviceStorage] whose platform reports [freeBytes] — null for a
    /// platform that will not say.
    DeviceStorage storageReporting(int? freeBytes) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'freeBytes');
            return freeBytes;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      return DeviceStorage(channel: channel);
    }

    QueueRunner runnerOver(DeviceStorage storage) {
      final made = QueueRunner(
        queue: queue,
        captureServiceFor: () => h.captureWith(source),
        deviceStorage: storage,
      );
      addTearDown(made.dispose);
      return made;
    }

    test('too little room names that row and leaves the rest '
        'queued', () async {
      final first = await queueEntry(102);
      final rest = await queueEntry(103);

      await runnerOver(
        storageReporting(kDefaultSaveConfig.minFreeSpaceToStart - 1),
      ).start();

      final stopped = await queue.byId(first.id);
      expect(stopped!.state, SaveTaskState.failed);
      expect(stopped.stopReason, StopReason.insufficientStorage);
      expect(
        source.started,
        isEmpty,
        reason: 'the gate is asked before anything is read or written',
      );

      final waiting = await queue.byId(rest.id);
      expect(
        waiting!.state,
        SaveTaskState.queued,
        reason: 'nothing is wrong with the rest; freeing space starts them',
      );
      expect(waiting.stopReason, isNull);
      expect(h.committedPaths(), isEmpty);
      expect(h.stagingLeftovers(), isEmpty);
    });

    test('a platform that cannot say is not a refusal', () async {
      final first = await queueEntry(102);
      final second = await queueEntry(103);

      await runnerOver(storageReporting(null)).start();

      expect(source.started, [urlFor(102), urlFor(103)]);
      expect((await queue.byId(first.id))!.state, SaveTaskState.completed);
      expect(
        (await queue.byId(second.id))!.state,
        SaveTaskState.completed,
        reason: 'unknown free space means carry on, never zero',
      );
    });
  });

  group('history is bounded, and never at the expense of live work', () {
    /// Three finished rows, one waiting and one running.
    Future<({List<SaveTask> done, SaveTask waiting, SaveTask live})>
    seedHistory() async {
      final done = <SaveTask>[];
      for (var ordinal = 201; ordinal <= 203; ordinal++) {
        final (entry, _) = await h.repos.entries.createInCollection(
          collectionId: collectionId,
          ordinal: ordinal.toDouble(),
          title: 'Part $ordinal',
        );
        done.add(
          await queue.recordDirectOutcome(
            entryId: entry!.id,
            locationUrl: urlFor(ordinal),
            state: SaveTaskState.completed,
            outcome: 'saved',
          ),
        );
      }
      final waiting = await queueEntry(102);
      final live = await queueEntry(103);
      await queue.claim(live.id);
      return (done: done, waiting: waiting, live: live);
    }

    test('pruning keeps the newest terminal rows and drops the rest', () async {
      final seeded = await seedHistory();

      expect(await queue.pruneHistory(keep: 2), 1);
      expect(
        await queue.byId(seeded.done.first.id),
        isNull,
        reason: 'the oldest goes first',
      );
      expect(await queue.byId(seeded.done[1].id), isNotNull);
      expect(await queue.byId(seeded.done.last.id), isNotNull);
      expect(
        await queue.pruneHistory(keep: 2),
        0,
        reason: 'a bounded history is already at its bound',
      );
    });

    test('pruning never touches a waiting or a running row', () async {
      final seeded = await seedHistory();

      expect(await queue.pruneHistory(keep: 0), 3);
      expect(
        (await queue.byId(seeded.waiting.id))!.state,
        SaveTaskState.queued,
      );
      expect((await queue.byId(seeded.live.id))!.state, SaveTaskState.running);
      expect(
        (await queue.pending()).map((t) => t.id),
        [seeded.waiting.id, seeded.live.id],
        reason: 'history is bounded; the queue itself is not history',
      );
      // The rows were never the content: both Entries are exactly as they were.
      expect(await h.repos.entries.byId(seeded.waiting.entryId), isNotNull);
      expect(await h.repos.entries.byId(seeded.live.entryId), isNotNull);
    });
  });
}

/// A repository whose claim of [loseClaimFor] arrives a moment too late.
///
/// The runner reads the eligible rows and then claims one; a cancel landing
/// inside that window is precisely what `claim` returns null for, and the only
/// way to sit a test inside a window that small is to put the cancel there.
class _RacedQueue extends SaveQueueRepository {
  _RacedQueue(super.db, {super.now});

  /// The row a cancel beats, once.
  String? loseClaimFor;

  @override
  Future<SaveTask?> claim(String id) async {
    if (id == loseClaimFor) {
      loseClaimFor = null;
      await cancel(id);
    }
    return super.claim(id);
  }
}

/// A [PageCaptureSource] scripted per address, which can be held open.
///
/// Captures delegate to the lane's own [FakePageCaptureSource], so the bytes,
/// the manifest and the commit are the real ones; what this adds is the
/// ordering the loop is judged on and a gate to hold a run open while a test
/// looks at the world mid-batch.
class _ScriptedSource implements PageCaptureSource {
  final Map<String, String> _failures = {};
  final Set<String> _refusals = {};
  final Map<String, Completer<void>> _gates = {};

  /// Every address a capture was opened for, in order.
  final List<String> started = <String>[];

  /// Hold the capture of [url] open until the returned completer is completed.
  Completer<void> holdAt(String url) => _gates[url] = Completer<void>();

  void failAt(String url, String error) => _failures[url] = error;

  void refuseAt(String url) => _refusals.add(url);

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) async {
    started.add(url);
    final gate = _gates[url];
    if (gate != null) await gate.future;

    // Asked at the boundary a real implementation asks it at: between the
    // navigation and anything being stored.
    if (!shouldContinue()) {
      return PageCaptureOutcome.failed(
        pageUrl: url,
        error: 'stopped at the next safe point',
        stopReason: StopReason.cancelledByUser,
      );
    }
    if (_refusals.contains(url)) {
      return PageCaptureOutcome.refused(pageUrl: url);
    }
    final failure = _failures[url];
    if (failure != null) {
      return PageCaptureOutcome.failed(
        pageUrl: url,
        error: failure,
        stopReason: StopReason.accessDenied,
      );
    }
    return FakePageCaptureSource.images(pageCount: 1).capturePage(
      url: url,
      staging: staging,
      requestedMode: requestedMode,
      shouldContinue: shouldContinue,
    );
  }
}
