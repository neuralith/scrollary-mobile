import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/library/collection_deletion.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'helpers/fake_browser.dart';

/// Permanent deletion of one collection.
///
/// The contract under test, and the reason it is a whole file: deletion is the
/// only action in the product that is not reversible, so what it must *not*
/// touch is as load-bearing as what it removes. Archiving still only flips a
/// lifecycle column, removing offline files still keeps every row, and a
/// second collection, a standalone entry, the browsing data and the hints the
/// user taught all survive a delete next door.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late CleanupService cleanup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_delete');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
    cleanup = CleanupService(db: db, fileStore: store);
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  CollectionDeletionService service({TaskQueueController? queue}) =>
      CollectionDeletionService(
        db: db,
        fileStore: store,
        cleanup: cleanup,
        queue: queue,
      );

  Future<void> seedCollection(
    String id, {
    String lifecycle = 'active',
    String? cleanupPreference,
    String? preferredCaptureMode,
  }) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: lifecycle,
        id: id,
        title: 'Collection $id',
        sourceUrl: 'https://x.example/guide/$id',
        host: 'x.example',
        collectionKey: '/guide/$id',
        collectionIndexUrl: 'https://x.example/guide/$id',
        cleanupPreference: cleanupPreference,
        preferredCaptureMode: preferredCaptureMode,
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    if (lifecycle == 'archived') {
      await db.setCollectionLifecycle(id, 'archived');
    }
  }

  /// A committed entry with real bytes on disk and a real reading position.
  Future<Entry> seedEntry(
    String? collectionId,
    int n, {
    String readStatus = 'inProgress',
    String saveStatus = 'complete',
  }) async {
    final id = '${collectionId ?? 'solo'}-e$n';
    final staging = await store.beginEntry(
      collectionId: collectionId,
      entryId: id,
    );
    for (var i = 1; i <= 3; i++) {
      await staging.assetFile('00$i.png').writeAsBytes(List.filled(400, 7));
    }
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: id,
        collectionId: collectionId,
        sourceUrl: 'https://x.example/guide/${collectionId ?? 'solo'}/$n',
        title: 'Entry $n',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: 3,
        assets: const [],
      ),
    );
    final entry = Entry(
      host: 'x.example',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: id,
      collectionId: collectionId,
      title: 'Entry $n',
      sourceUrl: 'https://x.example/guide/${collectionId ?? 'solo'}/$n',
      urlKey: 'https://x.example/guide/${collectionId ?? 'solo'}/$n',
      artifactFormat: 'imageSequence',
      saveStatus: saveStatus,
      contentPath: relative,
      savedAt: DateTime(2026, 7, 20),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      entryOrder: n,
      byteSize: 1200,
      entryNumber: n.toDouble(),
      sourceMarker: 'Entry $n',
      readStatus: readStatus,
      progressFraction: 0.4,
      progressPageIndex: 1,
      progressOffsetInPage: 0.25,
      firstOpenedAt: DateTime(2026, 7, 21),
      lastReadAt: DateTime(2026, 7, 22),
    );
    await db.upsertEntry(entry);
    return entry;
  }

  /// The state that belongs to the rest of the app and must outlive a delete.
  Future<void> seedSharedState() async {
    await db.upsertSavedSite(
      SavedSite(
        id: 'site1',
        url: 'https://x.example/',
        urlKey: 'https://x.example/',
        host: 'x.example',
        title: 'Example',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
        orderIndex: 0,
      ),
    );
    await db.insertVisit(
      BrowsingHistoryData(
        id: 'v1',
        url: 'https://x.example/guide/s1/1',
        urlKey: 'https://x.example/guide/s1/1',
        host: 'x.example',
        title: 'Entry 1',
        source: 'manual',
        completed: true,
        visitedAt: DateTime(2026, 7, 22),
      ),
    );
    await db.upsertHint(
      UserPageHintRow(
        id: 'h1',
        host: 'x.example',
        hintPath: '/guide/s1',
        scope: 'collection',
        kind: 'nextLink',
        locatorJson: '{}',
        sameHostOnly: true,
        createdAt: DateTime(2026, 7, 2),
        successCount: 3,
        failureCount: 0,
      ),
    );
    await db.setSetting('collection.entrySort', 'oldestFirst');
  }

  bool collectionFilesExist(String id) => Directory(
    store.resolve(FileStore.collectionRelativePath(id)),
  ).existsSync();

  // --- the delete itself ----------------------------------------------------

  group('deleting a collection', () {
    test('removes the collection row and every entry it owned', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1);
      await seedEntry('s1', 2);

      final result = await service().delete('s1');

      expect(result.ok, isTrue, reason: result.detail);
      expect(result.deletedEntries, 2);
      expect(await db.collectionById('s1'), isNull);
      expect(await db.entriesForCollection('s1'), isEmpty);
      expect(await db.allEntries(), isEmpty);
    });

    test('removes the downloaded files it owned', () async {
      await seedCollection('s1');
      final entry = await seedEntry('s1', 1);
      expect(collectionFilesExist('s1'), isTrue);
      expect(
        store.assetFile(entry.contentPath!, 'assets/001.png').existsSync(),
        isTrue,
      );

      final result = await service().delete('s1');

      expect(result.ok, isTrue);
      expect(collectionFilesExist('s1'), isFalse);
      expect(
        Directory(store.resolve(entry.contentPath!)).existsSync(),
        isFalse,
      );
      expect(result.freedBytes, 1200);
      // Nothing is parked in staging either: a delete that only moved the
      // bytes would keep occupying the space it claims to have freed.
      expect(
        Directory(p.join(root.path, FileStore.tmpFolderName)).listSync(),
        isEmpty,
      );
    });

    test('takes reading progress and continue-reading state with it', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1, readStatus: 'inProgress');
      await seedEntry('s1', 2, readStatus: 'completed');
      // The denormalised pointers on the collection are what Continue Reading
      // orders by, so they have to go with the entries rather than be left
      // naming rows that no longer exist.
      await ReadingRepository(db).rebuildCollectionPointers();
      expect((await db.collectionById('s1'))!.lastReadAt, isNotNull);
      expect(
        computeCollectionReadingState(await db.allEntries()).continueEntry,
        isNotNull,
      );

      await service().delete('s1');

      expect(await db.allEntries(), isEmpty);
      expect(
        computeCollectionReadingState(await db.allEntries()).continueEntry,
        isNull,
      );
      expect(await db.allCollections(), isEmpty);
    });

    test("takes the collection's own preferences with it", () async {
      await seedCollection(
        's1',
        cleanupPreference: 'remove',
        preferredCaptureMode: 'textOnly',
      );
      await seedEntry('s1', 1);
      expect((await db.collectionById('s1'))!.cleanupPreference, 'remove');

      await service().delete('s1');

      expect(await db.collectionById('s1'), isNull);
      expect(await db.allCollections(), isEmpty);
    });

    test(
      'removes files of an entry that was moved in from standalone',
      () async {
        // Reassignment moves the row, never the bytes: this entry still lives
        // under `standalone/`, outside the collection directory.
        await seedCollection('s1');
        final moved = await seedEntry(null, 9);
        await db.reassignEntry(moved.id, 's1');
        expect(
          Directory(store.resolve(moved.contentPath!)).existsSync(),
          isTrue,
        );

        final result = await service().delete('s1');

        expect(result.ok, isTrue);
        expect(
          Directory(store.resolve(moved.contentPath!)).existsSync(),
          isFalse,
        );
        expect(await db.entryById(moved.id), isNull);
      },
    );

    test('a pending undo cannot restore the files afterwards', () async {
      await seedCollection('s1');
      final entry = await seedEntry('s1', 1);
      // A soft removal parks the entry directory in `tmp/undo-<id>` and can
      // put it back for a few seconds. Left behind, that restore would write a
      // package back under `library/` for startup recovery to reconcile — the
      // collection would come back on the next launch.
      final removal = await cleanup.removeOffline([entry.id]);
      expect(removal.canUndo, isTrue);
      final undoDir = Directory(
        p.join(root.path, FileStore.tmpFolderName, 'undo-${entry.id}'),
      );
      expect(undoDir.existsSync(), isTrue);

      await service().delete('s1');
      await removal.undo.undo();

      expect(undoDir.existsSync(), isFalse);
      expect(collectionFilesExist('s1'), isFalse);
      expect(await db.entryById(entry.id), isNull);
      expect(await db.collectionById('s1'), isNull);
    });

    test('drops an interrupted run that was walking the collection', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1);
      final now = DateTime(2026, 7, 23);
      await db.upsertRun(
        SaveRun(
          id: 'run-s1',
          startUrl: 'https://x.example/guide/s1/1',
          currentUrl: 'https://x.example/guide/s1/2',
          requestedEntries: 5,
          completedEntries: 1,
          state: 'inspecting',
          visitedUrls: '',
          visitedCanonicals: '',
          scope: 'fixedCount',
          captureModeIsUserSet: false,
          origin: 'queue',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.upsertRun(
        SaveRun(
          id: 'run-elsewhere',
          startUrl: 'https://y.example/other/1',
          requestedEntries: 2,
          completedEntries: 0,
          state: 'inspecting',
          visitedUrls: '',
          visitedCanonicals: '',
          scope: 'fixedCount',
          captureModeIsUserSet: false,
          origin: 'queue',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await service().delete('s1');

      final remaining = await db.allRuns();
      expect(remaining.map((r) => r.id), ['run-elsewhere']);
    });
  });

  // --- what it must not touch -----------------------------------------------

  group('everything else survives', () {
    test('another collection, a standalone entry and browsing data', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1);
      await seedCollection('s2');
      final kept = await seedEntry('s2', 1);
      final solo = await seedEntry(null, 1);
      await seedSharedState();

      final result = await service().delete('s1');

      expect(result.ok, isTrue);
      expect(await db.collectionById('s2'), isNotNull);
      expect(await db.entryById(kept.id), isNotNull);
      expect(collectionFilesExist('s2'), isTrue);
      expect(await db.entryById(solo.id), isNotNull);
      expect(
        Directory(store.resolve(solo.contentPath!)).existsSync(),
        isTrue,
        reason: 'a standalone entry is a library item in its own right',
      );
      // Shared, host-level and global state: none of it belongs to one
      // collection, and the hints in particular are what make saving the same
      // source again work as well as it did the first time.
      expect(await db.allSavedSites(), hasLength(1));
      expect(await db.visits(), hasLength(1));
      expect(await db.countPageHints(), 1);
      expect(await db.setting('collection.entrySort'), 'oldestFirst');
    });

    test('an archived collection stays archived, with its files', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1);
      await seedCollection('sleeping', lifecycle: 'archived');
      await seedEntry('sleeping', 1);

      await service().delete('s1');

      final archived = (await db.collectionById('sleeping'))!;
      expect(archived.lifecycle, 'archived');
      expect(archived.archivedAt, isNotNull);
      expect(await db.entriesForCollection('sleeping'), hasLength(1));
      expect(collectionFilesExist('sleeping'), isTrue);
    });

    test(
      'archiving still only flips lifecycle after a delete next door',
      () async {
        await seedCollection('s1');
        await seedEntry('s1', 1);
        await seedCollection('s2');
        await seedEntry('s2', 1);

        await service().delete('s1');
        await CollectionRepository(db).archive('s2');

        expect((await db.collectionById('s2'))!.lifecycle, 'archived');
        expect(await db.entriesForCollection('s2'), hasLength(1));
        expect(collectionFilesExist('s2'), isTrue);
      },
    );
  });

  // --- refusals -------------------------------------------------------------

  group('it refuses rather than delete under live work', () {
    test(
      'an entry open in the reader blocks it, and nothing is touched',
      () async {
        await seedCollection('s1');
        final entry = await seedEntry('s1', 1);
        cleanup.openReaderEntryId.value = entry.id;

        final result = await service().delete('s1');

        expect(result.ok, isFalse);
        expect(result.refusal, DeleteRefusal.inUse);
        expect(result.detail, contains('open in the reader'));
        expect(await db.collectionById('s1'), isNotNull);
        expect(await db.entriesForCollection('s1'), hasLength(1));
        expect(collectionFilesExist('s1'), isTrue);
      },
    );

    test('an entry mid-save blocks it', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1, saveStatus: 'saving');

      final result = await service().delete('s1');

      expect(result.ok, isFalse);
      expect(result.refusal, DeleteRefusal.inUse);
      expect(await db.collectionById('s1'), isNotNull);
      expect(collectionFilesExist('s1'), isTrue);
    });

    test(
      'a collection that is already gone is reported, not pretended',
      () async {
        final result = await service().delete('never-existed');
        expect(result.ok, isFalse);
        expect(result.refusal, DeleteRefusal.gone);
      },
    );
  });

  // --- the queue ------------------------------------------------------------

  group('queued work', () {
    late FakeBrowser browser;
    late List<String> executed;

    TaskQueueController makeQueue() => TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(browser: browser, db: db, fileStore: store),
      checker: UpdateChecker(browser: browser, db: db),
      saveRunner: (t) async {
        executed.add(t.id);
        return const QueueOutcome.success('done');
      },
      checkRunner: (t) async {
        executed.add(t.id);
        return const QueueOutcome.success('done');
      },
    );

    setUp(() {
      browser = FakeBrowser();
      executed = [];
    });

    test('waiting and finished tasks go, and cannot run afterwards', () async {
      await seedCollection('s1');
      final entry = await seedEntry('s1', 1);
      await seedCollection('s2');
      await seedEntry('s2', 1);
      final queue = makeQueue();

      browser.automationOwner = 'hold'; // nothing drains while we set up
      final mine = await queue.enqueueSave(
        startUrl: entry.sourceUrl,
        entryLimit: 1,
        collectionId: 's1',
      );
      // A save started from the Browser carries no collection id — it is
      // attributed by its address instead, and it is exactly the row that
      // would rebuild the collection after the delete.
      final byUrl = await queue.enqueueSave(
        startUrl: 'https://x.example/guide/s1/2',
        entryLimit: 1,
      );
      final theirs = (await queue.enqueueCollectionCheck('s2'))!;
      expect(await queue.pendingTasksForCollection('s1'), hasLength(1));

      final result = await service(queue: queue).delete('s1');
      expect(result.ok, isTrue, reason: result.detail);
      expect(result.cancelledTasks, 2);

      // Release the queue and let it drain: the cancelled work must not run,
      // and nothing may put the collection back.
      browser.automationOwner = null;
      await queue.startQueuedSaves();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await db.queueTaskById(mine.id), isNull, reason: 'row deleted');
      expect((await db.queueTaskById(byUrl.id))!.state, 'cancelled');
      expect(executed, isNot(contains(mine.id)));
      expect(executed, isNot(contains(byUrl.id)));
      expect(await db.collectionById('s1'), isNull);
      expect(await db.allEntries(), hasLength(1));
      // The other collection's work is untouched by any of it.
      expect(await db.queueTaskById(theirs), isNotNull);
    });

    test('history rows naming the collection go too', () async {
      await seedCollection('s1');
      await seedEntry('s1', 1);
      final queue = makeQueue();
      await db.upsertQueueTask(
        QueueTask(
          id: 'done-s1',
          taskType: 'entrySave',
          collectionId: 's1',
          startUrl: 'https://x.example/guide/s1/1',
          captureModeIsUserSet: false,
          origin: 'direct',
          state: 'completed',
          outcome: '1 saved',
          orderIndex: 1,
          queuedAt: DateTime(2026, 7, 22),
          finishedAt: DateTime(2026, 7, 22),
        ),
      );

      await service(queue: queue).delete('s1');

      expect(await db.queueTaskById('done-s1'), isNull);
    });
  });

  // --- the source can be saved again ----------------------------------------

  test('the same source becomes a new collection afterwards', () async {
    await seedCollection('s1');
    await seedEntry('s1', 1);
    await service().delete('s1');

    final created = await CollectionRepository(db).resolveCollection(
      entryUrl: 'https://x.example/guide/s1/3',
      sequence: const SequenceShape(
        kind: SequenceKind.openEndedNext,
        ordering: OrderingBasis.detectedNextLink,
        confidence: ShapeConfidence.high,
      ),
      pageTitle: 'Collection s1 Entry 3',
    );

    expect(created, isNotNull);
    expect(created!.id, isNot('s1'), reason: 'a new local collection');
    expect(created.host, 'x.example');
    expect(await db.allCollections(), hasLength(1));
  });

  // --- the screen -----------------------------------------------------------

  group('collection screen', () {
    /// [home] is what sits under the pushed collection route.
    ///
    /// The navigation test passes a stub rather than the real library on
    /// purpose. Popping back onto a screen full of providers that were
    /// suspended while it was covered trips a `setState() during build`
    /// assertion inside Riverpod's ticker-mode handling — reproducible in this
    /// app with an ordinary write and an ordinary Back, with no deletion
    /// anywhere near it, and so not this feature's to carry. What that test is
    /// for is the *navigation*: the screen is left, and it is left safely.
    /// That the library stops listing a deleted collection is asserted
    /// separately, without a route change, in the test below it.
    Widget harness({Widget home = const LibraryScreen()}) {
      final browser = FakeBrowser();
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          fileStoreProvider.overrideWithValue(store),
          cleanupProvider.overrideWithValue(cleanup),
          updateCheckerProvider.overrideWithValue(
            UpdateChecker(browser: browser, db: db),
          ),
          saveRunProvider.overrideWithValue(
            SaveRunController(browser: browser, db: db, fileStore: store),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(path: '/', builder: (_, _) => home),
              GoRoute(
                path: '/collection/:id',
                builder: (_, state) => CollectionDetailScreen(
                  collectionId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(path: '/reader/:id', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/archived', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/activity', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/storage', builder: (_, _) => const SizedBox()),
            ],
          ),
        ),
      );
    }

    /// Seeding writes real files, and `writeAsBytes` / `rename` are genuinely
    /// asynchronous — a `testWidgets` fake clock never turns them, so awaiting
    /// one inside the test zone hangs forever. [WidgetTester.runAsync] is the
    /// only place this work can happen.
    Future<void> seedOutsideTheFakeClock(
      WidgetTester tester,
      Future<void> Function() work,
    ) async {
      await tester.runAsync(work);
    }

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('timed out waiting for $finder');
    }

    Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isEmpty) return;
      }
      fail('timed out waiting for $finder to go');
    }

    Future<void> settleDown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }

    /// The collection screen's own menu button. Scoped to the app bar because
    /// the library underneath has a button with the same tooltip on every row.
    final menuButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Collection actions'),
    );

    /// Let a route push, a sheet or a dialog finish arriving.
    ///
    /// [pumpUntil] returns the frame a widget first exists on, which for
    /// anything that slides in is a frame where it is still off to the side —
    /// and a tap aimed at it then lands outside the screen.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
    }

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.tap(menuButton);
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('deleteCollectionEntry')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('deleteCollectionEntry')));
      await pumpUntil(tester, find.text('Delete this collection?'));
      await settle(tester);
    }

    testWidgets('cancelling the confirmation leaves everything untouched', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedOutsideTheFakeClock(tester, () async {
        await seedCollection('s1');
        await seedEntry('s1', 1);
      });

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byKey(const ValueKey('collectionRow-s1')));
      await tester.tap(find.byKey(const ValueKey('collectionRow-s1')));
      await pumpUntil(tester, menuButton);
      await settle(tester);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(await db.collectionById('s1'), isNotNull);
      expect(await db.entriesForCollection('s1'), hasLength(1));
      expect(collectionFilesExist('s1'), isTrue);
      // Still on the collection, not sent anywhere.
      expect(menuButton, findsOneWidget);
      await settleDown(tester);
    });

    testWidgets('confirming deletes it and leaves the screen', (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedOutsideTheFakeClock(tester, () async {
        await seedCollection('s1');
        await seedEntry('s1', 1);
        await seedCollection('s2');
        await seedEntry('s2', 1);
      });

      await tester.pumpWidget(
        harness(
          home: const Scaffold(body: Center(child: Text('BEHIND'))),
        ),
      );
      await pumpUntil(tester, find.text('BEHIND'));
      // Straight to the collection, as the library row would.
      final router = GoRouter.of(tester.element(find.text('BEHIND')));
      router.push('/collection/s1');
      await pumpUntil(tester, menuButton);
      await settle(tester);
      await openDeleteDialog(tester);

      await tester.tap(find.byKey(const ValueKey('confirmDeleteCollection')));
      await pumpUntil(tester, find.text('BEHIND'));
      await settle(tester);

      // Off the deleted collection, and everything it owned is gone.
      expect(menuButton, findsNothing);
      expect(find.text('BEHIND'), findsOneWidget);
      expect(await db.collectionById('s1'), isNull);
      expect(await db.entriesForCollection('s1'), isEmpty);
      expect(collectionFilesExist('s1'), isFalse);
      expect(await db.collectionById('s2'), isNotNull);
      expect(collectionFilesExist('s2'), isTrue);
      await settleDown(tester);
    });

    testWidgets('the library and Continue Reading stop listing it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedOutsideTheFakeClock(tester, () async {
        await seedCollection('s1');
        await seedEntry('s1', 1);
        await seedCollection('s2');
        await seedEntry('s2', 1);
      });

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byKey(const ValueKey('collectionRow-s1')));
      expect(find.byKey(const ValueKey('continueCard-s1-e1')), findsOneWidget);

      await service().delete('s1');
      await pumpUntilGone(
        tester,
        find.byKey(const ValueKey('collectionRow-s1')),
      );

      expect(find.byKey(const ValueKey('collectionRow-s1')), findsNothing);
      expect(find.byKey(const ValueKey('continueCard-s1-e1')), findsNothing);
      expect(find.byKey(const ValueKey('collectionRow-s2')), findsOneWidget);
      expect(find.byKey(const ValueKey('continueCard-s2-e1')), findsOneWidget);
      await settleDown(tester);
    });

    testWidgets('the delete action is reachable on a phone-sized screen', (
      tester,
    ) async {
      // The collection menu has seven actions. In the default 9/16-height
      // sheet they do not fit, and what falls off the bottom is the last one
      // — the destructive one, present in the tree and impossible to tap.
      // The other tests here run on a 1600pt-tall view, which has room for
      // anything and so proves nothing about a real device.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedOutsideTheFakeClock(tester, () async {
        await seedCollection('s1');
        await seedEntry('s1', 1);
      });

      await tester.pumpWidget(
        harness(
          home: const Scaffold(body: Center(child: Text('BEHIND'))),
        ),
      );
      await pumpUntil(tester, find.text('BEHIND'));
      GoRouter.of(tester.element(find.text('BEHIND'))).push('/collection/s1');
      await pumpUntil(tester, menuButton);
      await settle(tester);

      await tester.tap(menuButton);
      final tile = find.byKey(const ValueKey('deleteCollectionEntry'));
      await pumpUntil(tester, tile);
      await settle(tester);

      // Reachable, not merely present: scroll it into view if the sheet needs
      // to, then tap it for real.
      await tester.ensureVisible(tile);
      await settle(tester);
      await tester.tap(tile);
      await pumpUntil(tester, find.text('Delete this collection?'));

      expect(find.text('Delete this collection?'), findsOneWidget);
      await settleDown(tester);
    });

    testWidgets('a standalone entry has no delete-collection action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late Entry solo;
      await seedOutsideTheFakeClock(tester, () async {
        solo = await seedEntry(null, 1);
      });

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.byKey(ValueKey('collectionRow-${solo.id}')));
      await tester.tap(find.byKey(ValueKey('collectionRow-${solo.id}')));
      await pumpUntil(tester, menuButton);
      await settle(tester);
      await tester.tap(menuButton);
      await pumpUntil(tester, find.text('Rename'));
      await settle(tester);

      expect(
        find.byKey(const ValueKey('deleteCollectionEntry')),
        findsNothing,
        reason: 'there is no collection here to delete',
      );
      await settleDown(tester);
    });
  });
}
