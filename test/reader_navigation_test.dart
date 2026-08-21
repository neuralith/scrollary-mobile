import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

/// Swiping right in the reader goes back to the collection's entry list.
///
/// The two things that make this correct rather than merely present: the
/// gesture must not fire on ordinary reading (which is vertical), and the
/// reading position must be written before the screen goes away.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_reader_nav');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seed() async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Fixture Collection',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: 'c1',
    );
    final entries = <EntryAsset>[];
    for (var i = 1; i <= 3; i++) {
      await staging
          .assetFile('00$i.png')
          .writeAsBytes(panelPng(entry: 1, index: i));
      entries.add(
        EntryAsset(
          index: i,
          sourceUrl: 'https://cdn.example/$i.png',
          status: AssetStatus.stored,
          relativePath: 'assets/00$i.png',
          width: 800,
          height: 1200,
          dimensionsVerified: true,
        ),
      );
    }
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: 1,
        entryId: 'c1',
        collectionId: 'collection-1',
        sourceUrl: 'https://x.example/guide/foo/1',
        title: 'Foo Entry 1',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: 3,
        assets: entries,
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
        title: 'Foo Entry 1',
        sourceUrl: 'https://x.example/guide/foo/1',
        urlKey: 'https://x.example/guide/foo/1',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 3,
        storedAssetCount: 3,
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

  /// The two real routes involved, so the test exercises the actual
  /// pop-or-replace decision rather than a stand-in.
  Widget harness({required String start}) {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/collection/:collectionId',
          builder: (context, state) => CollectionDetailScreen(
            collectionId: state.pathParameters['collectionId']!,
          ),
          routes: const [],
        ),
        GoRoute(
          path: '/reader/:entryId',
          builder: (context, state) =>
              ReaderScreen(entryId: state.pathParameters['entryId']!),
        ),
      ],
    );
    // The entry list reaches the update checker and the save run for its
    // own actions; both get inert instances over an unattached browser, so no
    // WebView is stood up.
    final browser = BrowserController();
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        saveRunProvider.overrideWithValue(
          SaveRunController(browser: browser, db: db, fileStore: store),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Real file IO needs the event loop to turn (`runAsync`), and route
  /// transitions need the test clock to advance (`pump(duration)`). Both.
  Future<void> settleAsync(WidgetTester tester, {int rounds = 30}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Unmount inside the body, then let the disposal timers drift's stream
  /// teardown schedules actually run — the fake clock only turns while the
  /// test body is still going.
  void navTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  Future<void> openReader(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ListView).evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  navTest('a right swipe leaves for the entry list', (tester) async {
    await tester.runAsync(seed);
    await openReader(tester, harness(start: '/reader/c1'));

    await tester.drag(find.byType(ListView), const Offset(220, 0));
    await settleAsync(tester);

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byType(CollectionDetailScreen), findsOneWidget);
  });

  navTest('the position is written before the reader goes away', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await openReader(tester, harness(start: '/reader/c1'));

    // Read a little — well inside the 2s save debounce, so nothing has been
    // persisted yet when the swipe happens.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));
    expect((await db.entryById('c1'))!.progressUpdatedAt, isNull);

    await tester.drag(find.byType(ListView), const Offset(220, 0));
    await settleAsync(tester);

    final entry = (await db.entryById('c1'))!;
    expect(entry.progressUpdatedAt, isNotNull);
    expect(entry.progressFraction, greaterThan(0));
  });

  navTest('scrolling to read never triggers it', (tester) async {
    await tester.runAsync(seed);
    await openReader(tester, harness(start: '/reader/c1'));

    // A long read scroll with the sideways wobble of a real thumb.
    await tester.drag(find.byType(ListView), const Offset(40, -600));
    await settleAsync(tester, rounds: 20);

    expect(
      find.byType(ReaderScreen),
      findsOneWidget,
      reason: 'a vertical drag belongs to the scroll view, not to navigation',
    );

    // Neither does a leftward one.
    await tester.drag(find.byType(ListView), const Offset(-220, 0));
    await settleAsync(tester, rounds: 20);
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  navTest('opened from the entry list, it pops back onto the same one', (
    tester,
  ) async {
    await tester.runAsync(seed);
    final app = harness(start: '/collection/collection-1');
    await tester.pumpWidget(app);
    await settleAsync(tester, rounds: 40);

    final router = GoRouter.of(
      tester.element(find.byType(CollectionDetailScreen)),
    );
    router.push('/reader/c1');
    final readerList = find.descendant(
      of: find.byType(ReaderScreen),
      matching: find.byType(ListView),
    );
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (readerList.evaluate().isNotEmpty) break;
    }
    expect(readerList, findsOneWidget, reason: 'the reader opened');

    await tester.drag(readerList.first, const Offset(220, 0));
    await settleAsync(tester);

    expect(find.byType(CollectionDetailScreen), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    // Popped rather than stacked: there is no second entry list underneath.
    expect(
      router.routerDelegate.currentConfiguration.matches,
      hasLength(1),
      reason: 'in-and-out must not pile up routes',
    );
  });
}
