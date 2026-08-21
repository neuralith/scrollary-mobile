import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/features/archived_screen.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// M16: archive/restore. The contract under test: archiving changes
/// visibility and checking — never entries, files, or reading state.
void main() {
  late AppDatabase db;
  late Directory root;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_archive');
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection(String id, {int entries = 2}) async {
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
    for (var n = 1; n <= entries; n++) {
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: '$id-c$n',
          collectionId: id,
          title: 'Collection $id Entry $n',
          sourceUrl: 'https://x.example/guide/$id/$n',
          urlKey: 'https://x.example/guide/$id/$n',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/$id/entries/$id-c$n',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 6,
          storedAssetCount: 6,
          entryOrder: n,
          byteSize: 1024,
          entryNumber: n.toDouble(),
          sourceMarker: 'Entry $n',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }
  }

  group('lifecycle column (schema v7)', () {
    test(
      'fresh collection come out active with no archived timestamp',
      () async {
        await seedCollection('s1');
        final item = (await db.collectionById('s1'))!;
        expect(item.lifecycle, 'active');
        expect(item.archivedAt, isNull);
      },
    );

    test('archive/restore round-trip touches only lifecycle fields', () async {
      await seedCollection('s1');
      final repo = CollectionRepository(db);
      final before = (await db.collectionById('s1'))!;

      await repo.archive('s1');
      final archived = (await db.collectionById('s1'))!;
      expect(archived.lifecycle, 'archived');
      expect(archived.archivedAt, isNotNull);
      expect(
        await db.entriesForCollection('s1'),
        hasLength(2),
        reason: 'entries untouched',
      );

      await repo.restore('s1');
      final restored = (await db.collectionById('s1'))!;
      expect(restored.lifecycle, 'active');
      expect(restored.archivedAt, isNull, reason: 'timestamp cleared');
      expect(restored.title, before.title);
      expect(restored.collectionKey, before.collectionKey);
      final entries = await db.entriesForCollection('s1');
      expect(entries.map((c) => c.readStatus).toSet(), {'unread'});
      expect(entries.map((c) => c.contentPath), everyElement(isNotNull));
    });
  });

  group('queue integration', () {
    late FakeBrowser browser;
    late List<String> executed;

    setUp(() {
      browser = FakeBrowser();
      executed = [];
    });

    TaskQueueController makeQueue() => TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
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

    test('check-all skips archived collection', () async {
      await seedCollection('active-1');
      await seedCollection('active-2');
      await seedCollection('sleeping');
      await CollectionRepository(db).archive('sleeping');
      final queue = makeQueue();

      final ids = await queue.enqueueCheckAll();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(ids, hasLength(2), reason: 'archived collection not checked');
      final rows = await db.watchQueueTasks().first;
      expect(rows.map((t) => t.collectionId).toSet(), {'active-1', 'active-2'});
    });

    test('archiving cancels the collection’ pending tasks (Q25)', () async {
      await seedCollection('s1');
      await seedCollection('s2');
      final queue = makeQueue();

      browser.automationOwner = 'hold'; // keep everything queued
      await queue.enqueueCollectionCheck('s1');
      await queue.enqueueCollectionCheck('s2');
      expect(await queue.pendingTasksForCollection('s1'), hasLength(1));

      final cancelled = await queue.cancelTasksForCollection('s1');
      await CollectionRepository(db).archive('s1');

      expect(cancelled, 1);
      final rows = await db.watchQueueTasks().first;
      expect(rows.firstWhere((t) => t.collectionId == 's1').state, 'cancelled');
      expect(
        rows.firstWhere((t) => t.collectionId == 's2').state,
        'queued',
        reason: 'the other collection’ work is untouched',
      );
    });
  });

  group('screens', () {
    Widget harness(Widget child) {
      final browser = BrowserController();
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          updateCheckerProvider.overrideWithValue(
            UpdateChecker(browser: browser, db: db),
          ),
          saveRunProvider.overrideWithValue(
            SaveRunController(
              browser: browser,
              db: db,
              fileStore: FileStore(root),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(path: '/', builder: (_, _) => child),
              GoRoute(
                path: '/collection/:id',
                builder: (_, state) => CollectionDetailScreen(
                  collectionId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/archived',
                builder: (_, _) => const ArchivedScreen(),
              ),
              GoRoute(path: '/reader/:id', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
            ],
          ),
        ),
      );
    }

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('timed out waiting for $finder');
    }

    Future<void> settleDown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('an archived collection leaves the library list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedCollection('s1');
      await seedCollection('s2');
      await CollectionRepository(db).archive('s2');

      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.text('Collection s1'));

      expect(find.text('Collection s1'), findsWidgets);
      expect(find.text('Collection s2'), findsNothing);
      await settleDown(tester);
    });

    testWidgets('the Archived screen lists and restores', (tester) async {
      await seedCollection('s1');
      await CollectionRepository(db).archive('s1');

      await tester.pumpWidget(harness(const ArchivedScreen()));
      await pumpUntil(tester, find.text('Collection s1'));

      // The row counts in the collection's own vocabulary. This fixture has no
      // detected shape, so the honest noun is the generic one — an unclassified
      // collection must not be given a specific noun it never earned.
      expect(find.textContaining('2 saved items offline'), findsOneWidget);
      expect(find.textContaining('archived'), findsWidgets);

      await tester.tap(find.text('Restore'));
      await pumpUntil(tester, find.text('Nothing archived'));

      expect((await db.collectionById('s1'))!.lifecycle, 'active');
      await settleDown(tester);
    });

    testWidgets('detail of an archived collection offers restore, not checks', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedCollection('s1');
      await CollectionRepository(db).archive('s1');

      await tester.pumpWidget(
        harness(const CollectionDetailScreen(collectionId: 's1')),
      );
      await pumpUntil(tester, find.text('Archived'));

      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Check this collection'), findsNothing);
      expect(
        find.byKey(const ValueKey('checkThisCollectionButton')),
        findsNothing,
      );

      await tester.tap(find.text('Restore'));
      await pumpUntil(tester, find.text('Check this collection'));

      expect((await db.collectionById('s1'))!.lifecycle, 'active');
      await settleDown(tester);
    });
  });
}
