import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// Queueing a save does not start it (D46), and starting one navigates to
/// the Browser before it touches a WebView (D47).
void main() {
  late AppDatabase db;
  late FakeBrowser browser;
  late Directory root;
  late List<String> executed;

  /// How many times the queue asked for the Browser, and what it was told.
  late List<String> browserAsks;
  late bool browserAvailable;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    browser = FakeBrowser();
    root = Directory.systemTemp.createTempSync('webread_save_queue');
    executed = [];
    browserAsks = [];
    browserAvailable = true;
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  TaskQueueController makeQueue() {
    final queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
      checker: UpdateChecker(browser: browser, db: db),
      saveRunner: (task) async {
        executed.add(task.startUrl ?? task.id);
        return const QueueOutcome.success('saved');
      },
      checkRunner: (task) async {
        executed.add('check:${task.collectionId}');
        return const QueueOutcome.success('checked');
      },
    );
    queue.ensureBrowserVisible = ({url}) async {
      browserAsks.add('asked');
      return browserAvailable;
    };
    return queue;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  String url(int n) => 'https://x.example/guide/foo/$n';

  Future<void> seedCollection() => db.upsertCollection(
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

  Future<Entry> seedEntry(
    double number, {
    bool offline = false,
    String? sourceUrl,
    String readStatus = 'unread',
    double progress = 0,
  }) async {
    final src = sourceUrl ?? url(number.round());
    final id = 'c$number';
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: id,
        collectionId: 'collection-1',
        title: 'Entry $number',
        sourceUrl: src,
        urlKey: '$src#$id',
        artifactFormat: 'imageSequence',
        saveStatus: offline ? 'complete' : 'complete',
        contentPath: offline ? 'library/collection-1/entries/$id' : null,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 3,
        storedAssetCount: offline ? 3 : 0,
        entryOrder: number.round(),
        byteSize: offline ? 2048 : 0,
        entryNumber: number,
        sourceMarker: 'Entry $number',
        readStatus: readStatus,
        progressFraction: progress,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        offlineRemovedAt: offline ? null : DateTime(2026, 7, 26),
      ),
    );
    return (await db.entryById(id))!;
  }

  group('queueing does not start', () {
    test('a save request waits, and touches no browser', () async {
      final queue = makeQueue();

      final result = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await settle();

      expect(result.alreadyQueued, isFalse);
      expect(executed, isEmpty, reason: 'nothing ran');
      expect(browserAsks, isEmpty, reason: 'and nothing asked for the Browser');
      expect(browser.automationOwner, isNull);

      final waiting = await queue.queuedSaves();
      expect(waiting.single.state, QueueTaskState.queued.name);
      expect(queue.saveStartAuthorised, isFalse);
    });

    test('the queued row survives a restart, still unstarted', () async {
      final first = makeQueue();
      await first.enqueueSave(startUrl: url(1), entryLimit: 1);
      await settle();

      // A new controller over the same database is what a relaunch looks
      // like from the queue's point of view.
      final second = makeQueue();
      await second.restore();
      await settle();

      expect(executed, isEmpty, reason: 'a restart never resumes save');
      expect((await second.queuedSaves()), hasLength(1));
      expect(second.saveStartAuthorised, isFalse);
    });

    test('a kill mid-save demotes the row rather than losing it', () async {
      final queue = makeQueue();
      final result = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await db.upsertQueueTask(
        (await db.queueTaskById(result.id))!.copyWith(state: 'running'),
      );

      final restarted = makeQueue();
      await restarted.restore();

      expect((await restarted.queuedSaves()), hasLength(1));
      expect(executed, isEmpty);
    });

    test('checks and cleanup still drain without a start', () async {
      final queue = makeQueue();
      await queue.enqueueCollectionCheck('collection-1');
      await settle();

      expect(executed, ['check:collection-1']);
    });

    test('a queued save does not block a check behind it', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.enqueueCollectionCheck('collection-1');
      await settle();

      expect(executed, [
        'check:collection-1',
      ], reason: 'the unstarted save is skipped, not a roadblock');
    });
  });

  group('explicit start', () {
    test('start releases the queue and asks for the Browser first', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);

      final released = await queue.startQueuedSaves();
      await settle();

      expect(released, 1);
      expect(browserAsks, hasLength(1));
      expect(executed, [url(1)]);
    });

    test('nothing starts when the Browser cannot be shown', () async {
      browserAvailable = false;
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);

      await queue.startQueuedSaves();
      await settle();

      expect(browserAsks, hasLength(1));
      expect(
        executed,
        isEmpty,
        reason: 'automation must never begin behind another screen (D47)',
      );
      expect(
        (await queue.queuedSaves()),
        hasLength(1),
        reason: 'the work stays queued for the next attempt',
      );
    });

    test('tasks process sequentially, in queue order', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.enqueueSave(startUrl: url(2), entryLimit: 1);
      await queue.enqueueSave(startUrl: url(3), entryLimit: 1);

      await queue.startQueuedSaves();
      await settle();

      expect(executed, [url(1), url(2), url(3)]);
      expect(browserAsks, hasLength(3), reason: 'one gate per task');
    });

    test('a drained queue revokes its own authorisation', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.startQueuedSaves();
      await settle();
      expect(queue.saveStartAuthorised, isFalse);

      // Adding more is a new decision, and waits again.
      await queue.enqueueSave(startUrl: url(2), entryLimit: 1);
      await settle();
      expect(executed, [url(1)]);
    });

    test('one failure does not discard the rest of the batch', () async {
      final queue = TaskQueueController(
        db: db,
        browser: browser,
        saveRun: SaveRunController(
          browser: browser,
          db: db,
          fileStore: FileStore(root),
        ),
        checker: UpdateChecker(browser: browser, db: db),
        saveRunner: (task) async {
          executed.add(task.startUrl!);
          return task.startUrl == url(2)
              ? const QueueOutcome.failure('boom')
              : const QueueOutcome.success('saved');
        },
      );
      for (final n in [1, 2, 3]) {
        await queue.enqueueSave(startUrl: url(n), entryLimit: 1);
      }

      await queue.startQueuedSaves();
      await settle();

      expect(executed, [url(1), url(2), url(3)]);
      final rows = await db.watchQueueTasks().first;
      expect(rows.where((t) => t.state == 'failed'), hasLength(1));
      expect(rows.where((t) => t.state == 'completed'), hasLength(2));
    });

    test('stopping keeps the remainder queued, not cancelled', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.enqueueSave(startUrl: url(2), entryLimit: 1);

      await queue.stopQueuedSaves();
      await settle();

      expect(executed, isEmpty);
      expect((await queue.queuedSaves()), hasLength(2));
    });
  });

  group('duplicate prevention', () {
    test('the same entry is not queued twice', () async {
      final queue = makeQueue();
      final first = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      final second = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);

      expect(second.alreadyQueued, isTrue);
      expect(second.id, first.id);
      expect((await queue.queuedSaves()), hasLength(1));
    });

    test('history does not block a fresh re-fetch', () async {
      final queue = makeQueue();
      final first = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.startQueuedSaves();
      await settle();
      expect((await db.queueTaskById(first.id))!.state, 'completed');

      final again = await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      expect(
        again.alreadyQueued,
        isFalse,
        reason: 'a completed run last week must not veto an intentional one',
      );
    });
  });

  group('batch re-download', () {
    test('queues ascending, whatever order the list was showing', () async {
      await seedCollection();
      final queue = makeQueue();
      final c488 = await seedEntry(488);
      final c489 = await seedEntry(489);
      final c490 = await seedEntry(490);

      // Newest-first, exactly as the entry list renders it.
      final result = await queue.enqueueEntries([c490, c489, c488]);

      expect(result.queued, 3);
      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.map((t) => t.startUrl), [url(488), url(489), url(490)]);
    });

    test('decimal entries keep their place', () async {
      await seedCollection();
      final queue = makeQueue();
      final a = await seedEntry(385, sourceUrl: url(385));
      final b = await seedEntry(385.5, sourceUrl: 'https://x.example/385-5');
      final c = await seedEntry(386, sourceUrl: url(386));

      await queue.enqueueEntries([c, a, b]);

      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.map((t) => t.startUrl), [
        url(385),
        'https://x.example/385-5',
        url(386),
      ]);
    });

    test('entries with no source page are reported, not dropped', () async {
      await seedCollection();
      final queue = makeQueue();
      final ok1 = await seedEntry(1);
      final ok2 = await seedEntry(2);
      final bad = await seedEntry(3, sourceUrl: '');

      final result = await queue.enqueueEntries([ok1, ok2, bad]);

      expect(result.queued, 2);
      expect(result.missingSource, hasLength(1));
      expect(result.missingSource.single.id, bad.id);
      expect(
        (await queue.queuedSaves()),
        hasLength(2),
        reason: 'one unusable entry must not fail the whole selection',
      );
    });

    test('already-queued entries are counted separately', () async {
      await seedCollection();
      final queue = makeQueue();
      final a = await seedEntry(1);
      final b = await seedEntry(2);
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);

      final result = await queue.enqueueEntries([a, b]);

      expect(result.queued, 1);
      expect(result.alreadyQueued, hasLength(1));
      expect((await queue.queuedSaves()), hasLength(2));
    });

    test('re-download reuses the row and its reading state', () async {
      await seedCollection();
      final queue = makeQueue();
      final entry = await seedEntry(7, readStatus: 'completed', progress: 1);

      await queue.enqueueEntries([entry]);

      // The queue carries a URL, never a copy of the entry — so there is
      // nothing for it to duplicate.
      expect(await db.entriesForCollection('collection-1'), hasLength(1));
      final after = (await db.entryById(entry.id))!;
      expect(after.readStatus, 'completed');
      expect(after.progressFraction, 1);
      expect(after.sourceUrl, url(7));
      expect(after.entryNumber, 7);
    });

    test(
      'a batch uses the replacing policy, so files swap atomically',
      () async {
        await seedCollection();
        final queue = makeQueue();
        final entry = await seedEntry(1, offline: true);

        await queue.enqueueEntries([entry]);

        final row = (await queue.queuedSaves()).single;
        expect(row.duplicatePolicy, DuplicatePolicy.replaceAll.name);
        expect(row.scope, SaveScope.currentPageOnly.name);
        expect(row.entryLimit, 1);
      },
    );
  });

  /// Fetching what an update check discovered. The library holds up to 73,
  /// the source has up to 91, and the 18 discovered entries must be fetched
  /// 74 → 91 — the order they are read in — whatever order they were
  /// discovered or displayed in.
  group('newly discovered entries', () {
    /// An entry an update check recorded: known on the source, no bytes.
    Future<Entry> seedDiscovered(int n) async {
      final src = url(n);
      final id = 'r$n';
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: id,
          collectionId: 'collection-1',
          title: 'Entry $n',
          sourceUrl: src,
          urlKey: src,
          artifactFormat: 'imageSequence',
          saveStatus: 'knownRemote',
          detectedAssetCount: 0,
          storedAssetCount: 0,
          entryOrder: n,
          byteSize: 0,
          entryNumber: n.toDouble(),
          sourceMarker: 'Entry $n',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
          discoveredAt: DateTime(2026, 7, 27),
          discoveryBasis: 'entryList',
          discoveryConfidence: 'high',
        ),
      );
      return (await db.entryById(id))!;
    }

    /// 74..91, in the order the caller asks for.
    Future<List<Entry>> seedRange(Iterable<int> numbers) async {
      final out = <Entry>[];
      for (final n in numbers) {
        out.add(await seedDiscovered(n));
      }
      return out;
    }

    Future<List<String?>> queuedStartUrls(TaskQueueController queue) async {
      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return rows.map((t) => t.startUrl).toList();
    }

    List<String> expected(Iterable<int> numbers) => [
      for (final n in numbers) url(n),
    ];

    test('74–91 queue oldest first, and end at the newest', () async {
      await seedCollection();
      await seedEntry(73, offline: true);
      final queue = makeQueue();
      final discovered = await seedRange([for (var n = 74; n <= 91; n++) n]);

      final result = await queue.enqueueEntries(discovered);

      expect(result.queued, 18);
      final urls = await queuedStartUrls(queue);
      expect(urls.first, url(74));
      expect(urls.last, url(91));
      expect(urls, expected([for (var n = 74; n <= 91; n++) n]));
    });

    test('a newest-first list still executes oldest first', () async {
      await seedCollection();
      await seedEntry(73, offline: true);
      final queue = makeQueue();
      // Exactly what the collection screen holds: the display order.
      final displayed = await seedRange([for (var n = 91; n >= 74; n--) n]);

      await queue.enqueueEntries(displayed);

      expect(
        await queuedStartUrls(queue),
        expected([for (var n = 74; n <= 91; n++) n]),
      );
    });

    test('a mixed discovery order is still deterministic', () async {
      await seedCollection();
      await seedEntry(73, offline: true);
      final queue = makeQueue();
      final jumbled = await seedRange([80, 74, 91, 77, 90, 75]);

      await queue.enqueueEntries(jumbled);

      expect(await queuedStartUrls(queue), expected([74, 75, 77, 80, 90, 91]));
    });

    test(
      'entries already held are excluded without shifting the rest',
      () async {
        await seedCollection();
        await seedEntry(73, offline: true);
        final queue = makeQueue();
        final discovered = await seedRange([for (var n = 74; n <= 79; n++) n]);
        // 76 is already spoken for — the batch reports it and leaves it alone.
        await queue.enqueueSave(startUrl: url(76), entryLimit: 1);

        final result = await queue.enqueueEntries(discovered);

        expect(result.alreadyQueued.map((c) => c.entryNumber), [76]);
        expect(
          await queuedStartUrls(queue),
          // 76 keeps the place it already had; the others follow in order.
          expected([76, 74, 75, 77, 78, 79]),
        );
      },
    );

    test('the worker takes the oldest first', () async {
      await seedCollection();
      await seedEntry(73, offline: true);
      final queue = makeQueue();
      await queue.enqueueEntries(
        await seedRange([for (var n = 91; n >= 74; n--) n]),
      );

      await queue.startQueuedSaves();
      await settle();

      expect(executed.first, url(74));
      expect(executed, expected([for (var n = 74; n <= 91; n++) n]));
    });

    test('the order survives a restart', () async {
      await seedCollection();
      await seedEntry(73, offline: true);
      final first = makeQueue();
      await first.enqueueEntries(
        await seedRange([for (var n = 91; n >= 74; n--) n]),
      );
      // Killed mid-batch: one row is left claimed by the pump.
      final claimed = (await first.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      await db.updateQueueTaskIfState(
        id: claimed.first.id,
        expected: [QueueTaskState.queued.name],
        values: QueueTasksCompanion(
          state: Value(QueueTaskState.running.name),
          startedAt: Value(DateTime(2026, 7, 28)),
        ),
      );

      final relaunched = makeQueue();
      await relaunched.restore();

      expect(relaunched.resumeOffered, isTrue);
      expect(executed, isEmpty, reason: 'nothing resumes itself (Q24)');
      expect(
        await queuedStartUrls(relaunched),
        expected([for (var n = 74; n <= 91; n++) n]),
        reason: 'the demoted row goes back where it was, not to the end',
      );

      await relaunched.startQueuedSaves();
      await settle();
      expect(executed, expected([for (var n = 74; n <= 91; n++) n]));
    });
  });

  group('queue management', () {
    test('reordering moves a task without touching the others', () async {
      final queue = makeQueue();
      for (final n in [1, 2, 3]) {
        await queue.enqueueSave(startUrl: url(n), entryLimit: 1);
      }

      final third = (await queue.queuedSaves()).firstWhere(
        (t) => t.startUrl == url(3),
      );
      await queue.moveQueued(third.id, -1);

      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.map((t) => t.startUrl), [url(1), url(3), url(2)]);
    });

    test('moving up from the front is a no-op, not a wrap', () async {
      final queue = makeQueue();
      for (final n in [1, 2]) {
        await queue.enqueueSave(startUrl: url(n), entryLimit: 1);
      }
      final first = (await queue.queuedSaves()).firstWhere(
        (t) => t.startUrl == url(1),
      );
      await queue.moveQueued(first.id, -1);

      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.map((t) => t.startUrl), [url(1), url(2)]);
    });

    test('starting one task moves it to the front', () async {
      final queue = makeQueue();
      for (final n in [1, 2, 3]) {
        await queue.enqueueSave(startUrl: url(n), entryLimit: 1);
      }
      final third = (await queue.queuedSaves()).firstWhere(
        (t) => t.startUrl == url(3),
      );

      await queue.startQueuedTask(third.id);
      await settle();

      expect(executed.first, url(3));
    });

    test('clearing the queue removes plans, never content', () async {
      await seedCollection();
      final queue = makeQueue();
      final entry = await seedEntry(1, offline: true);
      await queue.enqueueEntries([entry]);

      final cleared = await queue.clearQueuedSaves();

      expect(cleared, 1);
      expect(await queue.queuedSaves(), isEmpty);
      expect(executed, isEmpty);
      // The entry, its files and its metadata are all untouched.
      final after = (await db.entryById(entry.id))!;
      expect(after.contentPath, isNotNull);
      expect(after.sourceUrl, url(1));
      expect(await db.entriesForCollection('collection-1'), hasLength(1));
    });

    test('the summary counts what each section shows', () async {
      final queue = makeQueue();
      await queue.enqueueSave(startUrl: url(1), entryLimit: 1);
      await queue.enqueueSave(startUrl: url(2), entryLimit: 1);
      await queue.enqueueCollectionCheck('collection-1');
      await settle();

      final summary = QueueSummary.of(await db.watchQueueTasks().first);
      expect(summary.queuedSaves, 2);
      expect(summary.completed, 1, reason: 'the check drained by itself');
      expect(summary.hasQueuedSaves, isTrue);
    });
  });

  group('ordering helpers', () {
    test('save order is reading order, decimal-safe', () async {
      await seedCollection();
      final list = [
        await seedEntry(386),
        await seedEntry(385),
        await seedEntry(385.5, sourceUrl: 'https://x.example/385-5'),
      ];
      expect(sortEntriesForSaveOrder(list).map((c) => c.entryNumber), [
        385,
        385.5,
        386,
      ]);
    });

    test('an entry needs a real URL to be capturable', () async {
      await seedCollection();
      expect(entryHasCapturableUrl(await seedEntry(1)), isTrue);
      expect(entryHasCapturableUrl(await seedEntry(2, sourceUrl: '')), isFalse);
      expect(
        entryHasCapturableUrl(await seedEntry(3, sourceUrl: '/relative')),
        isFalse,
      );
    });
  });
}
