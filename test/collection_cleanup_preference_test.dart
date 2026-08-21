import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// Collection detail › Downloaded entries: where a collection's cleanup decision is
/// changed and reset (D37). The reader asks once; this is the only other place
/// the value can move, and it moves for exactly one collection.
void main() {
  late AppDatabase db;
  late Directory root;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_collection_cleanup');
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

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
        host: '',
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
        detectedAssetCount: 6,
        storedAssetCount: 6,
        entryOrder: 1,
        byteSize: 1024,
        entryNumber: 1,
        sourceMarker: 'Entry 1',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  Widget harness(String collectionId) {
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
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  CollectionDetailScreen(collectionId: collectionId),
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

  final entry = find.byKey(const ValueKey('collectionCleanupPrefEntry'));

  /// Open Collection actions → Downloaded entries.
  ///
  /// Each sheet is let settle before it is tapped: a row that exists in the
  /// tree is still sliding up, and a tap at its final position misses.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Collection actions'));
    await pumpUntil(tester, entry);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(entry);
    // The sheet's own option rows, not the menu row's title — that text is
    // still in the tree while the menu pops.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('collectionCleanupPreference-ask')),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<CollectionCleanupPreference?> prefOf(String id) async =>
      collectionCleanupFromName(
        (await db.collectionById(id))!.cleanupPreference,
      );

  Future<void> tapOption(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('collectionCleanupPreference-$name')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('the menu row states the collection decision', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedCollection('s1');
    await tester.pumpWidget(harness('s1'));
    await pumpUntil(tester, find.text('Collection s1'));

    await tester.tap(find.byTooltip('Collection actions'));
    await pumpUntil(tester, entry);
    expect(
      find.text('Not set · asked when you finish an entry'),
      findsOneWidget,
    );
    await settleDown(tester);
  });

  testWidgets('choosing an option writes it to this collection only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedCollection('s1');
    await seedCollection('s2');
    await tester.pumpWidget(harness('s1'));
    await pumpUntil(tester, find.text('Collection s1'));
    await openSheet(tester);

    await tapOption(tester, 'keep');
    expect(await prefOf('s1'), CollectionCleanupPreference.keep);
    expect(
      await prefOf('s2'),
      isNull,
      reason: 'the sheet writes to the collection it was opened from',
    );

    await tapOption(tester, 'remove');
    expect(await prefOf('s1'), CollectionCleanupPreference.remove);
    expect(await prefOf('s2'), isNull);
    await settleDown(tester);
  });

  testWidgets('Ask again next time clears the stored decision', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedCollection('s1');
    await seedCollection('s2');
    await db.setCollectionCleanupPreference(
      's1',
      CollectionCleanupPreference.remove.name,
    );
    await db.setCollectionCleanupPreference(
      's2',
      CollectionCleanupPreference.remove.name,
    );

    await tester.pumpWidget(harness('s1'));
    await pumpUntil(tester, find.text('Collection s1'));
    await openSheet(tester);

    expect(
      find.text('Ask again next time'),
      findsOneWidget,
      reason:
          'the reset is offered by name — there is no global to fall back '
          'to',
    );
    expect(find.textContaining('global'), findsNothing);

    await tapOption(tester, 'ask');
    expect(await prefOf('s1'), isNull);
    expect(
      await prefOf('s2'),
      CollectionCleanupPreference.remove,
      reason: 'resetting one collection leaves every other one alone',
    );
    await settleDown(tester);
  });

  testWidgets('the sheet never touches files', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedCollection('s1');
    await tester.pumpWidget(harness('s1'));
    await pumpUntil(tester, find.text('Collection s1'));
    await openSheet(tester);
    await tapOption(tester, 'remove');

    final entry = (await db.entryById('s1-c1'))!;
    expect(entry.contentPath, isNotNull);
    expect(entry.offlineRemovedAt, isNull);
    await settleDown(tester);
  });
}
