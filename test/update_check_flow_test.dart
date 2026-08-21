import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/browser/browser_presentation.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/features/check_panel.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';

/// Checking for new entries is a **visible foreground operation**.
///
/// Three properties, and dropping any one of them produces the same complaint
/// in a different disguise — the app moved the Browser and the user could
/// neither see what it was doing nor stop it:
///
/// 1. starting a check that needs the Browser opens the page it is about to
///    read, not merely the Browser tab;
/// 2. while it runs there is a panel that names the operation, shows its log
///    and ends it;
/// 3. ending it stops the walk, and takes nothing with it.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late FakeBrowser browser;

  const host = 'https://x.example';
  const collectionIndexUrl = '$host/guide/foo';
  String entryUrl(int n) => '$host/guide/foo/$n';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_update_check_flow');
    store = FileStore(root);
    browser = FakeBrowser();
  });

  tearDown(() async {
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

  Future<void> seedSaved(int n, {String? nextUrl}) => db.upsertEntry(
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
      saveStatus: 'complete',
      contentPath: 'library/collection-1/entries/ch$n',
      savedAt: DateTime(2026, 7, 10),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      nextSourceUrl: nextUrl,
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

  group('the Browser is sent to the page the check will read', () {
    /// What the shell was asked to show, in order. `null` is "just bring the
    /// Browser forward" — which is what a save asks for, and what a check used
    /// to ask for.
    late List<String?> shown;
    late TaskQueueController queue;
    late UpdateChecker checker;

    setUp(() {
      shown = [];
      checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );
      queue = TaskQueueController(
        db: db,
        browser: browser,
        saveRun: SaveRunController(browser: browser, db: db, fileStore: store),
        checker: checker,
        // The work itself is stubbed out: what is under test is the
        // navigation the scheduler does *before* any of it runs.
        saveRunner: (task) async => const QueueOutcome.success('saved'),
        checkRunner: (task) async => const QueueOutcome.success('up to date'),
      );
      queue.ensureBrowserVisible = ({url}) async {
        shown.add(url);
        return true;
      };
    });

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a collection check opens its collection page', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);

      await queue.enqueueCollectionCheck('collection-1');
      await settle();

      expect(shown, [
        collectionIndexUrl,
      ], reason: 'the tab alone leaves the previous page on screen');
    });

    test(
      'a check with no collection page opens the entry it starts from',
      () async {
        await seedCollection();
        await seedSaved(1, nextUrl: entryUrl(2));
        await seedSaved(2);

        await queue.enqueueCollectionCheck('collection-1');
        await settle();

        expect(shown, [entryUrl(2)]);
      },
    );

    test('a check that starts from a stored link opens that link', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2, nextUrl: entryUrl(3));

      await queue.enqueueCollectionCheck('collection-1');
      await settle();

      expect(shown, [entryUrl(3)]);
    });

    test('"check all" opens each collection\'s own page in turn', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 'collection-2',
          title: 'Bar',
          sourceUrl: '$host/guide/bar',
          host: 'x.example',
          collectionKey: '/guide/bar',
          collectionIndexUrl: '$host/guide/bar',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await db.upsertEntry(
        // The second collection needs a saved entry of its own: a collection
        // with nothing to start from takes no part in a library-wide check.
        Entry(
          host: 'x.example',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'bar1',
          collectionId: 'collection-2',
          title: 'Bar Entry 1',
          sourceUrl: '$host/guide/bar/1',
          urlKey: '$host/guide/bar/1',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/collection-2/entries/bar1',
          savedAt: DateTime(2026, 7, 10),
          detectedAssetCount: 1,
          storedAssetCount: 1,
          entryOrder: 1,
          byteSize: 32,
          entryNumber: 1,
          sourceMarker: 'Entry 1',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );

      await queue.enqueueCheckAll();
      await settle();

      expect(shown, [collectionIndexUrl, '$host/guide/bar']);
    });

    test(
      'a check with nothing to start from still shows the Browser',
      () async {
        // No entries at all: there is no page to open, and asking for one that
        // does not exist must not stop the row from being scheduled.
        await seedCollection();

        await queue.enqueueCollectionCheck('collection-1');
        await settle();

        expect(shown, [null]);
      },
    );

    test('a save is left exactly as it was', () async {
      await queue.enqueueSave(
        startUrl: entryUrl(9),
        entryLimit: 1,
        range: SaveScope.currentPageOnly,
      );
      await queue.startQueuedSaves();
      await settle();

      expect(shown, [
        null,
      ], reason: 'saves drive their own page; this change is check-only');
    });
  });

  group('a named page reaches the WebView', () {
    /// The shell hands the URL to [BrowserNavigator]; this is the other half
    /// of that contract — the part that makes the page *visible* rather than
    /// loaded behind Browser Home.
    test('draining reveals the website surface and loads the page', () {
      final navigator = BrowserNavigator();
      addTearDown(navigator.dispose);
      final presentation = BrowserPresentation();
      addTearDown(presentation.dispose);
      presentation.openHome();
      expect(presentation.isHome, isTrue);

      navigator.request(collectionIndexUrl);
      final handed = PendingOpenDrainer(
        navigator: navigator,
        presentation: presentation,
        isAttached: () => true,
        reveal: presentation.showWebsite,
        load: (url) => unawaited(browser.load(url)),
      ).drain();

      expect(handed, isTrue);
      expect(presentation.isHome, isFalse);
      expect(browser.navigations, [collectionIndexUrl]);
      expect(navigator.hasPending, isFalse, reason: 'consumed exactly once');
    });
  });

  group('the running-check panel', () {
    /// A page the Browser reports as unrendered. The checker holds on it
    /// rather than measuring a surface that is not on screen — which makes
    /// "a check that is running" a state a widget test can sit inside.
    PageProbe unrenderedPage(String url) => PageProbe(
      url: url,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 0,
    );

    Widget host(UpdateChecker checker, VoidCallback onStop) => MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: checker,
          builder: (context, _) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              UpdateCheckPanel(
                checker: checker,
                expanded: true,
                onToggle: () {},
                onStop: onStop,
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('names the operation, shows its log, and offers a stop', (
      tester,
    ) async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      browser.addPage(collectionIndexUrl, unrenderedPage(collectionIndexUrl));
      final checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );

      await tester.pumpWidget(host(checker, checker.cancel));
      expect(find.byType(UpdateCheckPanel), findsOneWidget);
      expect(find.text('CHECKING'), findsNothing, reason: 'nothing running');

      unawaited(checker.check('collection-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Named as a check, never as a save, and honest about what it is doing
      // to the user's storage while it does it.
      expect(find.text('CHECKING'), findsOneWidget);
      expect(find.textContaining('metadata only'), findsOneWidget);
      expect(find.textContaining('0 page(s) read'), findsOneWidget);
      expect(find.textContaining('depth 0/2'), findsOneWidget);
      // The log the check is already writing, in the panel rather than nowhere.
      expect(find.textContaining('checking "Foo"'), findsOneWidget);
      expect(find.text('Copy log'), findsOneWidget);
      expect(find.text('Stop check'), findsOneWidget);

      await tester.tap(find.text('Stop check'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(checker.isRunning, isFalse);
      expect(checker.state, UpdateCheckState.cancelled);
      // Gone with the operation it belonged to.
      expect(find.text('Stop check'), findsNothing);
    });

    testWidgets('stopping leaves every saved entry and its collection', (
      tester,
    ) async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      await seedSaved(2);
      browser.addPage(collectionIndexUrl, unrenderedPage(collectionIndexUrl));
      final checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );

      await tester.pumpWidget(host(checker, checker.cancel));
      unawaited(checker.check('collection-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Stop check'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      final entries = await db.entriesForCollection('collection-1');
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(entry.saveStatus, 'complete');
        expect(entry.contentPath, isNotNull);
        expect(entry.progressFraction, 0);
      }
      expect(await db.collectionById('collection-1'), isNotNull);
      // The WebView is handed back, so the next thing the user does with the
      // Browser is theirs again.
      expect(browser.automationOwner, isNull);
      expect(browser.navigationLocked, isFalse);
    });
  });

  group('stopping a queued check', () {
    testWidgets('cancels the row rather than completing it', (tester) async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      browser.addPage(
        collectionIndexUrl,
        PageProbe(
          url: collectionIndexUrl,
          title: 'Foo — all entries',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 0,
        ),
      );
      final checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );
      final queue = TaskQueueController(
        db: db,
        browser: browser,
        saveRun: SaveRunController(browser: browser, db: db, fileStore: store),
        checker: checker,
      );
      addTearDown(queue.dispose);
      queue.ensureBrowserVisible = ({url}) async => true;

      final id = (await queue.enqueueCollectionCheck('collection-1'))!;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(checker.isRunning, isTrue, reason: 'the pump claimed it');

      // The panel's Stop, through the queue: the row and the panel have to
      // agree about what happened to this work.
      await queue.stopRunningCheck();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      final row = (await db.queueTaskById(id))!;
      expect(row.state, 'cancelled');
      expect(checker.isRunning, isFalse);
      expect(
        (await db.allEntries()).where((c) => c.saveStatus == 'knownRemote'),
        isEmpty,
        reason: 'a stopped check discovered nothing',
      );
    });
  });
}
