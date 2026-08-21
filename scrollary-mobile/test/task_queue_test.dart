import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// The M14 scheduler, tested with fake runners: ordering, one-at-a-time
/// serialization, restart semantics (offer, never auto-run), cancel/retry,
/// bounded history, and the clear-history-keeps-content contract.
void main() {
  late AppDatabase db;
  late FakeBrowser browser;
  late Directory root;

  /// Every executed task id, in execution order.
  late List<String> executed;

  /// Per-task gates so tests can hold a task "running".
  final gates = <String, Completer<QueueOutcome>>{};

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    browser = FakeBrowser();
    root = Directory.systemTemp.createTempSync('webread_queue');
    executed = [];
    gates.clear();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  TaskQueueController makeQueue({int historyLimit = 50}) {
    Future<QueueOutcome> run(QueueTask task) {
      executed.add(task.id);
      final gate = gates[task.id];
      return gate?.future ?? Future.value(const QueueOutcome.success('done'));
    }

    return TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
      checker: UpdateChecker(browser: browser, db: db),
      historyLimit: historyLimit,
      saveRunner: run,
      checkRunner: run,
    );
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  test('tasks run in FIFO order, one at a time', () async {
    final queue = makeQueue();

    final idA = (await queue.enqueueCollectionCheck('collection-a'))!;
    final idB = (await queue.enqueueCollectionCheck('collection-b'))!;
    final save = await queue.enqueueSave(
      startUrl: 'https://x.example/guide/foo/1',
      entryLimit: 3,
    );
    await settle();

    expect(
      executed,
      [idA, idB],
      reason: 'checks drain on their own; the save waits for Start (D46)',
    );

    await queue.startQueuedSaves();
    await settle();

    expect(executed, [idA, idB, save.id], reason: 'strict FIFO');
    final rows = await db.watchQueueTasks().first;
    expect(
      rows.map((t) => t.state).toSet(),
      {'completed'},
      reason: 'everything ran to completion, exactly once each',
    );
  });

  test(
    'only one task runs at a time — the second waits for the gate',
    () async {
      final queue = makeQueue();
      final gate = Completer<QueueOutcome>();

      // Pre-insert a gated task directly so the gate exists before the pump.
      final held = QueueTask(
        origin: 'queue',
        id: 'held',
        captureModeIsUserSet: false,
        taskType: 'collectionCheck',
        collectionId: 's1',
        state: 'queued',
        orderIndex: 1,
        queuedAt: DateTime(2026, 7, 27),
      );
      gates['held'] = gate;
      await db.upsertQueueTask(held);

      queue.resumeQueue(); // starts the pump (returns immediately)
      await settle();
      final idB = (await queue.enqueueCollectionCheck('s2'))!;
      await settle();

      expect(executed, ['held'], reason: 'B must not start while A holds');
      expect(queue.runningTaskId, 'held');

      gate.complete(const QueueOutcome.success('ok'));
      await settle();
      expect(executed, ['held', idB]);
      expect(queue.runningTaskId, isNull);
    },
  );

  test('restart offers the queue and never auto-runs it', () async {
    // What a killed app leaves behind: one running, one queued.
    await db.upsertQueueTask(
      QueueTask(
        origin: 'queue',
        id: 'was-running',
        captureModeIsUserSet: false,
        taskType: 'collectionCheck',
        collectionId: 's1',
        state: 'running',
        orderIndex: 1,
        queuedAt: DateTime(2026, 7, 27),
        startedAt: DateTime(2026, 7, 27, 10),
      ),
    );
    await db.upsertQueueTask(
      QueueTask(
        origin: 'queue',
        id: 'was-queued',
        captureModeIsUserSet: false,
        taskType: 'collectionCheck',
        collectionId: 's2',
        state: 'queued',
        orderIndex: 2,
        queuedAt: DateTime(2026, 7, 27),
      ),
    );

    final queue = makeQueue();
    await queue.restore();
    await settle();

    expect(queue.resumeOffered, isTrue);
    expect(executed, isEmpty, reason: 'nothing runs until the user says so');
    expect(
      (await db.queueTaskById('was-running'))!.state,
      'queued',
      reason: 'a kill mid-run demotes to queued — it never pretends it ran',
    );

    queue.resumeQueue();
    await settle();
    expect(executed, ['was-running', 'was-queued']);
    expect(queue.resumeOffered, isFalse);
  });

  test('cancelling a queued task ends it without running it', () async {
    final queue = makeQueue();
    final gate = Completer<QueueOutcome>();
    gates['held'] = gate;
    await db.upsertQueueTask(
      QueueTask(
        origin: 'queue',
        id: 'held',
        captureModeIsUserSet: false,
        taskType: 'collectionCheck',
        collectionId: 's1',
        state: 'queued',
        orderIndex: 1,
        queuedAt: DateTime(2026, 7, 27),
      ),
    );
    queue.resumeQueue();
    await settle();
    final idB = (await queue.enqueueCollectionCheck('s2'))!;
    await settle();

    await queue.cancelTask(idB); // still queued behind the gate
    gate.complete(const QueueOutcome.success('ok'));
    await settle();

    expect(executed, ['held'], reason: 'the cancelled task never ran');
    expect((await db.queueTaskById(idB))!.state, 'cancelled');
  });

  group('cancellation and removal (D64)', () {
    /// A queued save row, written straight to the database so tests can
    /// control ordering and state without pressing Start.
    Future<String> seedQueuedSave(String id, {int order = 1}) async {
      await db.upsertQueueTask(
        QueueTask(
          id: id,
          captureModeIsUserSet: false,
          taskType: 'entrySave',
          startUrl: 'https://x.example/guide/foo/$id',
          entryLimit: 1,
          scope: 'currentPageOnly',
          origin: 'queue',
          state: 'queued',
          orderIndex: order,
          queuedAt: DateTime(2026, 7, 30),
        ),
      );
      return id;
    }

    test('a cancelled queued save never runs, and stays gone', () async {
      final queue = makeQueue();
      await seedQueuedSave('keep', order: 1);
      await seedQueuedSave('drop', order: 2);

      expect(await queue.cancelTask('drop'), CancelResult.cancelledBeforeStart);
      expect((await db.queueTaskById('drop'))!.state, 'cancelled');

      // Start everything that is still waiting.
      await queue.startQueuedSaves();
      await settle();

      expect(executed, ['keep'], reason: 'the cancelled row was not picked up');
      expect(
        (await db.queueTaskById('keep'))!.state,
        'completed',
        reason: 'cancelling one task does not touch its neighbours',
      );
      expect((await db.queueTaskById('drop'))!.state, 'cancelled');
    });

    test('a cancelled task does not come back after a restart', () async {
      final queue = makeQueue();
      await seedQueuedSave('gone');
      await queue.cancelTask('gone');

      // A fresh controller over the same database = the relaunched app.
      final relaunched = makeQueue();
      await relaunched.restore();
      relaunched.resumeQueue();
      await settle();
      await relaunched.startQueuedSaves();
      await settle();

      expect((await db.queueTaskById('gone'))!.state, 'cancelled');
      expect(executed, isEmpty, reason: 'a relaunch is not a second chance');
      expect(
        await relaunched.queuedSaves(),
        isEmpty,
        reason: 'and it is not offered as waiting work either',
      );
    });

    test('cancelling a running task is durable across a restart', () async {
      final queue = makeQueue();
      final gate = Completer<QueueOutcome>();
      gates['held'] = gate;
      await db.upsertQueueTask(
        QueueTask(
          origin: 'queue',
          id: 'held',
          captureModeIsUserSet: false,
          taskType: 'collectionCheck',
          collectionId: 's1',
          state: 'queued',
          orderIndex: 1,
          queuedAt: DateTime(2026, 7, 30),
        ),
      );
      queue.resumeQueue();
      await settle();
      expect(queue.runningTaskId, 'held');

      expect(await queue.cancelTask('held'), CancelResult.stoppingRunning);
      expect(
        (await db.queueTaskById('held'))!.state,
        'cancelled',
        reason:
            'recorded when asked, not when the worker gets round to it — '
            'a row left `running` would be demoted back to `queued`',
      );

      // The app dies before the worker unwinds; the gate never completes.
      final relaunched = makeQueue();
      await relaunched.restore();
      relaunched.resumeQueue();
      await settle();

      expect((await db.queueTaskById('held'))!.state, 'cancelled');
      expect(executed, ['held'], reason: 'it was not run a second time');
    });

    test('a cancel racing the pump wins or loses honestly', () async {
      final queue = makeQueue();
      await seedQueuedSave('racy');

      // Cancel exactly inside the window the pump leaves open: it has read the
      // pending rows and is awaiting the Browser, but has not claimed yet.
      CancelResult? raced;
      queue.ensureBrowserVisible = ({url}) async {
        raced ??= await queue.cancelTask('racy');
        return true;
      };
      await queue.startQueuedSaves();
      await settle();

      expect(raced, CancelResult.cancelledBeforeStart);
      expect(
        executed,
        isEmpty,
        reason: 'the claim is conditional, so the pump skipped the row',
      );
      expect((await db.queueTaskById('racy'))!.state, 'cancelled');
      expect(
        (await db.queueTaskById('racy'))!.startedAt,
        isNull,
        reason: 'and it was never marked as having started',
      );
    });

    test('a failed task keeps Retry and can also be removed', () async {
      final queue = makeQueue();
      final id = (await queue.enqueueCollectionCheck('s1'))!;
      gates[id] = Completer<QueueOutcome>()
        ..complete(const QueueOutcome.failure('host unreachable'));
      await settle();
      expect((await db.queueTaskById(id))!.state, 'failed');

      // Retry is still there for a failure.
      final retried = await queue.retryTask(id);
      await settle();
      expect(retried, isNotNull);
      expect((await db.queueTaskById(retried!))!.state, 'completed');

      // And the failed entry itself can be dismissed — the row goes, nothing
      // else does.
      expect(await queue.removeTask(id), isTrue);
      expect(await db.queueTaskById(id), isNull);
      expect(
        await db.queueTaskById(retried),
        isNotNull,
        reason: 'removing one entry leaves the others alone',
      );
    });

    test('removeTask refuses anything that is still live', () async {
      final queue = makeQueue();
      await seedQueuedSave('waiting');
      expect(
        await queue.removeTask('waiting'),
        isFalse,
        reason: 'a waiting row is cancelled, never silently deleted',
      );
      expect((await db.queueTaskById('waiting'))!.state, 'queued');

      final gate = Completer<QueueOutcome>();
      gates['live'] = gate;
      await db.upsertQueueTask(
        QueueTask(
          origin: 'queue',
          id: 'live',
          captureModeIsUserSet: false,
          taskType: 'collectionCheck',
          collectionId: 's1',
          state: 'queued',
          orderIndex: 0,
          queuedAt: DateTime(2026, 7, 30),
        ),
      );
      queue.resumeQueue();
      await settle();
      expect(queue.runningTaskId, 'live');
      expect(await queue.removeTask('live'), isFalse);
      expect((await db.queueTaskById('live'))!.state, 'running');
      gate.complete(const QueueOutcome.success('ok'));
      await settle();
    });

    test('undo puts a cancelled save back in its place', () async {
      final queue = makeQueue();
      await seedQueuedSave('first', order: 1);
      await seedQueuedSave('second', order: 2);

      await queue.cancelTask('first');
      expect(await queue.restoreQueuedTask('first'), isTrue);

      final waiting = await queue.queuedSaves()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(
        waiting.map((t) => t.id),
        ['first', 'second'],
        reason: 'restored in place, not appended like a retry',
      );
      final row = (await db.queueTaskById('first'))!;
      expect(row.state, 'queued');
      expect(row.finishedAt, isNull);
      expect(row.outcome, isNull);

      // Undo is only ever an undo: a second one, or one aimed at live work,
      // must not resurrect anything.
      expect(await queue.restoreQueuedTask('first'), isFalse);
      expect(await queue.restoreQueuedTask('second'), isFalse);

      expect(
        executed,
        isEmpty,
        reason: 'a restored save still waits for a Start (D46)',
      );
    });

    test('cancelling reports what actually happened', () async {
      final queue = makeQueue();
      final done = (await queue.enqueueCollectionCheck('s1'))!;
      await settle();

      expect(await queue.cancelTask(done), CancelResult.alreadyFinished);
      expect(await queue.cancelTask('no-such-row'), CancelResult.gone);
    });

    test('clearing the waiting queue leaves running work alone', () async {
      final queue = makeQueue();
      final gate = Completer<QueueOutcome>();
      gates['running-check'] = gate;
      await db.upsertQueueTask(
        QueueTask(
          origin: 'queue',
          id: 'running-check',
          captureModeIsUserSet: false,
          taskType: 'collectionCheck',
          collectionId: 's1',
          state: 'queued',
          orderIndex: 0,
          queuedAt: DateTime(2026, 7, 30),
        ),
      );
      await seedQueuedSave('cap-a', order: 1);
      await seedQueuedSave('cap-b', order: 2);
      queue.resumeQueue();
      await settle();

      expect(await queue.clearQueuedSaves(), 2);
      expect((await db.queueTaskById('running-check'))!.state, 'running');

      gate.complete(const QueueOutcome.success('up to date'));
      await settle();
      expect(executed, ['running-check']);
      expect((await db.queueTaskById('cap-a'))!.state, 'cancelled');
      expect((await db.queueTaskById('cap-b'))!.state, 'cancelled');
    });
  });

  test('retry clones a terminal task to the back of the queue', () async {
    final queue = makeQueue();
    final id = (await queue.enqueueCollectionCheck('s1'))!;
    await settle();
    expect((await db.queueTaskById(id))!.state, 'completed');

    final retryId = await queue.retryTask(id);
    await settle();

    expect(retryId, isNotNull);
    expect(retryId, isNot(id), reason: 'a fresh entry, not a resurrection');
    expect((await db.queueTaskById(retryId!))!.state, 'completed');
    expect(executed, [id, retryId]);

    // Retrying a non-terminal task is refused.
    expect(await queue.retryTask('nonsense'), isNull);
  });

  test('history is bounded', () async {
    final queue = makeQueue(historyLimit: 3);
    for (var i = 0; i < 6; i++) {
      (await queue.enqueueCollectionCheck('s$i'))!;
      await settle();
    }

    final rows = await db.watchQueueTasks().first;
    expect(
      rows.length,
      3,
      reason: 'terminal entries beyond the cap are pruned',
    );
  });

  test('clearing history never touches saved content', () async {
    // A real saved entry with real bytes on disk.
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Foo',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 'collection-1',
        title: 'Foo 1',
        sourceUrl: 'https://x.example/guide/foo/1',
        urlKey: 'https://x.example/guide/foo/1',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/collection-1/entries/c1',
        detectedAssetCount: 1,
        storedAssetCount: 1,
        entryOrder: 1,
        byteSize: 4,
        readStatus: 'completed',
        progressFraction: 1,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
    final file = File(
      p.join(root.path, 'library/collection-1/entries/c1/assets/001.png'),
    )..createSync(recursive: true);
    file.writeAsBytesSync([1, 2, 3, 4]);

    final queue = makeQueue();
    (await queue.enqueueCollectionCheck('collection-1'))!;
    await settle();

    await queue.clearHistory();

    expect(await db.watchQueueTasks().first, isEmpty, reason: 'history gone');
    final entry = (await db.entryById('c1'))!;
    expect(entry.saveStatus, 'complete');
    expect(entry.readStatus, 'completed', reason: 'reading state intact');
    expect(file.existsSync(), isTrue, reason: 'bytes untouched');
  });

  test('the pump defers while something else owns the browser', () async {
    final queue = makeQueue();
    browser.automationOwner = 'a save run';

    (await queue.enqueueCollectionCheck('s1'))!;
    await settle();
    expect(executed, isEmpty, reason: 'one WebView, one driver');

    browser.automationOwner = null;
    queue.resumeQueue();
    await settle();
    expect(executed, hasLength(1));
  });

  test('queued work drains when the direct owner finishes (M14)', () async {
    // A directly-started run (resumed run, manual check) owns the browser;
    // work enqueued meanwhile must start when that run ends — signalled by
    // the owning controller's end-of-run notification, not by the next
    // enqueue.
    final queue = makeQueue();
    browser.automationOwner = 'a save run';

    (await queue.enqueueCollectionCheck('s1'))!;
    await settle();
    expect(executed, isEmpty);

    browser.automationOwner = null;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    queue.saveRun.notifyListeners(); // what a finishing run does last
    await settle();

    expect(executed, hasLength(1), reason: 'no enqueue needed to unstick');
  });

  test('a second check for the same collection does not stack (M14)', () async {
    final queue = makeQueue();
    browser.automationOwner = 'blocked'; // hold everything queued

    final first = (await queue.enqueueCollectionCheck('s1'))!;
    final dup = (await queue.enqueueCollectionCheck('s1'))!;
    final other = (await queue.enqueueCollectionCheck('s2'))!;
    await settle();

    expect(dup, first, reason: 'idempotent per collection while pending');
    expect(other, isNot(first));
    final rows = await db.watchQueueTasks().first;
    expect(rows.where((t) => t.collectionId == 's1'), hasLength(1));
  });

  group('check all collection (M15)', () {
    /// A collection a check could actually start from: one saved entry with a
    /// page address. A collection with none is not eligible for a library-wide
    /// check — see `library/library_check.dart`.
    Future<void> seedCollection(String id) async {
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: id,
          title: 'Collection $id',
          sourceUrl: 'https://x.example/guide/$id',
          host: 'x.example',
          collectionKey: '/guide/$id',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await db.upsertEntry(
        Entry(
          host: 'x.example',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: '$id-c1',
          collectionId: id,
          title: 'Collection $id Entry 1',
          sourceUrl: 'https://x.example/guide/$id/1',
          urlKey: 'https://x.example/guide/$id/1',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/$id/entries/$id-c1',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 1,
          storedAssetCount: 1,
          entryOrder: 1,
          byteSize: 8,
          entryNumber: 1,
          sourceMarker: 'Entry 1',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }

    test('expands to one sequential check per collection', () async {
      await seedCollection('s1');
      await seedCollection('s2');
      await seedCollection('s3');
      final queue = makeQueue();

      final ids = await queue.enqueueCheckAll();
      await settle();

      expect(ids, hasLength(3));
      expect(executed, ids, reason: 'sequential, FIFO, one WebView owner');
      final rows = await db.watchQueueTasks().first;
      expect(
        rows.map((t) => t.taskType).toSet(),
        {QueueTaskType.collectionCheck.name},
        reason: 'per-collection rows, not one opaque mega-task',
      );
    });

    test('one failing collection does not stop the rest', () async {
      await seedCollection('s1');
      await seedCollection('s2');
      await seedCollection('s3');
      final queue = makeQueue();

      // Fail the middle collection only.
      final failing = Completer<QueueOutcome>()
        ..complete(const QueueOutcome.failure('host unreachable'));
      final all = await db.allCollections();
      // Ids are minted at enqueue; gate by observing execution instead:
      // the runner consults `gates` by task id, so pre-wire after enqueue.
      browser.automationOwner = 'hold';
      final ids = await queue.enqueueCheckAll();
      gates[ids[1]] = failing;
      browser.automationOwner = null;
      queue.resumeQueue();
      await settle();

      expect(executed, ids, reason: 'the failure did not break the chain');
      final rows = await db.watchQueueTasks().first;
      final failed = rows.where((t) => t.state == 'failed').toList();
      expect(failed, hasLength(1));
      expect(failed.single.lastError, contains('host unreachable'));
      expect(rows.where((t) => t.state == 'completed'), hasLength(2));
      expect(all, hasLength(3));
    });

    test(
      'cancelQueuedChecks drops the waiting rows, not the running one',
      () async {
        await seedCollection('s1');
        await seedCollection('s2');
        await seedCollection('s3');
        final queue = makeQueue();

        browser.automationOwner = 'hold';
        final ids = await queue.enqueueCheckAll();
        // Let the first start and stay running behind a gate.
        gates[ids[0]] = Completer<QueueOutcome>();
        browser.automationOwner = null;
        queue.resumeQueue();
        await settle();
        expect(executed, [ids[0]], reason: 'first is in flight');

        final dropped = await queue.cancelQueuedChecks();
        expect(dropped, 2);

        gates[ids[0]]!.complete(const QueueOutcome.success('up to date'));
        await settle();

        final rows = await db.watchQueueTasks().first;
        expect(
          rows.firstWhere((t) => t.id == ids[0]).state,
          'completed',
          reason: 'the in-flight check finished normally',
        );
        expect(
          rows.where((t) => t.state == 'cancelled').map((t) => t.id).toSet(),
          {ids[1], ids[2]},
        );
        expect(executed, [ids[0]], reason: 'cancelled rows never ran');
      },
    );

    test('kill mid-run leaves the remainder as a restart offer', () async {
      await seedCollection('s1');
      await seedCollection('s2');
      await seedCollection('s3');
      final queue = makeQueue();

      browser.automationOwner = 'hold';
      final ids = await queue.enqueueCheckAll();
      gates[ids[0]] = Completer<QueueOutcome>(); // never completes = "killed"
      browser.automationOwner = null;
      queue.resumeQueue();
      await settle();

      // A new controller over the same database = the relaunched app.
      final relaunched = makeQueue();
      await relaunched.restore();

      expect(relaunched.resumeOffered, isTrue);
      final rows = await db.watchQueueTasks().first;
      expect(
        rows.where((t) => t.state == 'queued'),
        hasLength(3),
        reason: 'the killed running row demoted to queued, remainder intact',
      );
      expect(executed, [ids[0]], reason: 'nothing auto-ran on relaunch');
    });
  });
}
