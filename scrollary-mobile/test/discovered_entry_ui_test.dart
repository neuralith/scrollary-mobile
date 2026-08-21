import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// What the Collection screen says about entries the source has and this
/// device does not — including the two that are not simply "not downloaded
/// yet": one whose save has already been tried and failed, and one the user
/// wants gone.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late FakeBrowser browser;
  late UpdateChecker checker;
  late BrowserNavigator browserNavigator;
  late ValueNotifier<int?> tabRequest;

  const host = 'https://x.example';
  String entryUrl(int n) => '$host/guide/foo/$n';
  const collectionIndexUrl = '$host/guide/foo';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_discovery_ui');
    store = FileStore(root);
    browser = FakeBrowser();
    checker = UpdateChecker(
      browser: browser,
      db: db,
      config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
    );
    browserNavigator = BrowserNavigator();
    tabRequest = ValueNotifier<int?>(null);
  });

  tearDown(() async {
    browserNavigator.dispose();
    tabRequest.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection({String? withCollectionUrl}) =>
      db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 'collection-1',
          title: 'Foo',
          sourceUrl: collectionIndexUrl,
          host: 'x.example',
          collectionKey: '/guide/foo',
          collectionIndexUrl: withCollectionUrl,
          createdAt: DateTime(2026, 7, 1),
        ),
      );

  Future<void> seedCaptured(int n) async {
    Directory(
      '${root.path}/library/collection-1/entries/ch$n',
    ).createSync(recursive: true);
    await db.upsertEntry(
      Entry(
        host: 'x.example',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'ch$n',
        collectionId: 'collection-1',
        title: 'Foo Entry $n',
        sourceUrl: entryUrl(n),
        urlKey: entryUrl(n),
        artifactFormat: 'imageSequence',
        captureMode: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/collection-1/entries/ch$n',
        savedAt: DateTime(2026, 7, 10),
        detectedAssetCount: 1,
        storedAssetCount: 1,
        entryOrder: n,
        byteSize: 128,
        entryNumber: n.toDouble(),
        sourceMarker: 'Entry $n',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  Future<void> seedDiscovered(int n, {String? saveError}) => db.upsertEntry(
    Entry(
      host: 'x.example',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: 'known$n',
      collectionId: 'collection-1',
      title: 'Foo Entry $n',
      sourceUrl: entryUrl(n),
      urlKey: entryUrl(n),
      artifactFormat: 'imageSequence',
      saveStatus: 'knownRemote',
      detectedAssetCount: 0,
      storedAssetCount: 0,
      entryOrder: n,
      byteSize: 0,
      entryNumber: n.toDouble(),
      sourceMarker: 'Entry $n',
      saveError: saveError,
      readStatus: 'unread',
      progressFraction: 0,
      progressPageIndex: 0,
      progressOffsetInPage: 0,
      discoveredAt: DateTime(2026, 7, 20),
      discoveryBasis: 'entryList',
      discoveryConfidence: 'high',
    ),
  );

  void serveNumbered(List<int> numbers) => browser.addPage(
    collectionIndexUrl,
    PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: [
        for (final n in numbers)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ],
    ),
  );

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/collection/collection-1',
      routes: [
        GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              CollectionDetailScreen(collectionId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/reader/:entryId',
          builder: (_, _) => const Scaffold(body: Text('READER')),
        ),
        GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        saveRunProvider.overrideWithValue(
          SaveRunController(browser: browser, db: db, fileStore: store),
        ),
        updateCheckerProvider.overrideWithValue(checker),
        browserNavigatorProvider.overrideWithValue(browserNavigator),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        cleanupProvider.overrideWithValue(
          CleanupService(db: db, fileStore: store),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> open(WidgetTester tester, {String? waitFor}) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .textContaining(waitFor ?? 'NEW ON SOURCE')
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('the collection screen never showed ${waitFor ?? "the remote list"}');
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('a discovered entry can be forgotten', (tester) async {
    await seedCollection();
    await seedCaptured(100);
    await seedDiscovered(101);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('remoteRow-known101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forgetEntry')), findsOneWidget);
    expect(
      find.textContaining('nothing is deleted from this device'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('forgetEntry')));
    await tester.pumpAndSettle();

    expect(await db.entryById('known101'), isNull);
    expect(
      find.text(
        'Forgotten. It will come back if the source lists it '
        'again.',
      ),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('forgetting the last one empties the source list', (
    tester,
  ) async {
    await seedCollection();
    await seedCaptured(100);
    await seedDiscovered(101);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('remoteRow-known101')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forgetEntry')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('NEW ON SOURCE'),
      findsNothing,
      reason: 'the section is what offers a save, and there is nothing to save',
    );
    await drain(tester);
  });

  testWidgets('a saved entry is never offered as forgettable', (tester) async {
    await seedCollection();
    await seedCaptured(100);
    // Its files are gone from disk, so the sheet is the one that opens.
    Directory(
      '${root.path}/library/collection-1/entries/ch100',
    ).deleteSync(recursive: true);
    await open(tester, waitFor: 'Entry 100');

    await tester.tap(find.byKey(const ValueKey('entryRow-ch100')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('forgetEntry')), findsNothing);
    await drain(tester);
  });

  testWidgets('an entry whose save failed is shown and left out of the batch', (
    tester,
  ) async {
    await seedCollection();
    await seedCaptured(100);
    await seedDiscovered(101, saveError: 'the page could not be opened');
    await seedDiscovered(102);
    await open(tester);

    expect(find.text('last try failed'), findsOneWidget);
    expect(
      find.textContaining('Save 1 '),
      findsOneWidget,
      reason: 'two are listed; one has already been tried',
    );
    expect(find.textContaining('1 left out'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('when every one has failed, the batch button is gone', (
    tester,
  ) async {
    await seedCollection();
    await seedCaptured(100);
    await seedDiscovered(101, saveError: 'the page could not be opened');
    await open(tester);

    expect(find.byKey(const ValueKey('saveNewEntries')), findsNothing);
    expect(
      find.textContaining('Open one to try it again on its own'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('its sheet offers a retry and a way to forget it', (
    tester,
  ) async {
    await seedCollection();
    await seedCaptured(100);
    await seedDiscovered(101, saveError: 'the page could not be opened');
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('remoteRow-known101')));
    await tester.pumpAndSettle();

    expect(find.text('Try saving again'), findsOneWidget);
    expect(find.byKey(const ValueKey('forgetEntry')), findsOneWidget);
    expect(
      find.textContaining('The last attempt to save this did not finish'),
      findsOneWidget,
      reason: 'the reason it is out of the batch is stated, not implied',
    );
    await drain(tester);
  });

  testWidgets('a check that removed entries says so on the card', (
    tester,
  ) async {
    await seedCollection(withCollectionUrl: collectionIndexUrl);
    await seedCaptured(100);
    await seedDiscovered(101);
    await seedDiscovered(102);
    // The source now lists neither 101 nor 102, and has published two more.
    serveNumbered([104, 103, 100]);

    // Through `runAsync`: a check uses real timers, and the test body runs in
    // a fake-async zone where those never fire.
    final outcome = await tester.runAsync(() => checker.check('collection-1'));
    expect(outcome!.staleRemoved, 2);

    await open(tester, waitFor: 'no longer at the source');

    expect(find.byKey(const ValueKey('staleRemovedLine')), findsOneWidget);
    expect(
      find.textContaining('nothing was deleted from this device'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('a check that removed nothing says nothing about removals', (
    tester,
  ) async {
    await seedCollection(withCollectionUrl: collectionIndexUrl);
    await seedCaptured(100);
    serveNumbered([102, 101, 100]);

    final outcome = await tester.runAsync(() => checker.check('collection-1'));
    expect(outcome!.staleRemoved, 0);

    await open(tester);

    expect(find.byKey(const ValueKey('staleRemovedLine')), findsNothing);
    expect(find.textContaining('no longer at the source'), findsNothing);
    await drain(tester);
  });
}
