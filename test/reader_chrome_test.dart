import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/features/document_reader.dart';
import 'package:web_reader/features/operation_indicator.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

/// What shows and hides the reader's overlaid chrome.
///
/// The rule under test is one sentence: **the chrome toggles only for a brief,
/// stationary, single-pointer contact that began while the content was at
/// rest.** Everything else here is a way that sentence can be violated.
///
/// It needs saying in tests because Flutter's default answer is the opposite
/// one. The scroll view's drag recogniser rejects itself on pointer-up when it
/// never cleared the touch slop, which leaves the tap recogniser alone in the
/// arena — so *every* pointer sequence the scroll view declines is promoted to
/// a tap. A finger put down to stop a fling, a thumb resting on the page and a
/// small back-and-forth shuffle all used to fade the bars back in mid-read.
///
/// The one case deliberately left alone is a single sub-slop movement. It is
/// indistinguishable from a jittery tap by any measurement, and both platforms
/// treat that contact as a tap; the reader follows the platform rather than
/// inventing an arbiter for it.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  /// The flag the reader publishes its bar visibility on. Built here rather
  /// than by the provider so a test can still read it after the reader has
  /// gone — which is exactly what "leaving restores it" has to check.
  late ReaderChromeVisibility chromeFlag;
  late int detailsOpened;
  late int browserOpened;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_reader_chrome');
    store = FileStore(root);
    chromeFlag = ReaderChromeVisibility();
    detailsOpened = 0;
    browserOpened = 0;
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
  });

  tearDown(() async {
    chromeFlag.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection() => db.upsertCollection(
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

  /// A tall image entry, so there is always somewhere to scroll to.
  ///
  /// [entryId] and [order] are parameters only so a second entry can be seeded
  /// beside the first — entry-to-entry navigation needs somewhere to go.
  Future<void> seedImages({
    double progressFraction = 0,
    int progressPageIndex = 0,
    String entryId = 'c1',
    int order = 1,
  }) async {
    await seedCollection();
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: entryId,
    );
    final assets = <EntryAsset>[];
    for (var i = 1; i <= 12; i++) {
      await staging
          .assetFile('0$i.png')
          .writeAsBytes(panelPng(entry: 1, index: i));
      assets.add(
        EntryAsset(
          index: i,
          sourceUrl: 'https://cdn.example/$i.png',
          status: AssetStatus.stored,
          relativePath: 'assets/0$i.png',
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
        entryId: entryId,
        collectionId: 'collection-1',
        sourceUrl: 'https://x.example/guide/foo/$order',
        title: 'Foo Entry $order',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 12,
        storedAssetCount: 12,
        assets: assets,
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: entryId,
        collectionId: 'collection-1',
        title: 'Foo Entry $order',
        sourceUrl: 'https://x.example/guide/foo/$order',
        urlKey: 'https://x.example/guide/foo/$order',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 12,
        storedAssetCount: 12,
        entryOrder: order,
        byteSize: 1024,
        entryNumber: order.toDouble(),
        sourceMarker: 'Entry $order',
        readStatus: 'unread',
        progressFraction: progressFraction,
        progressPageIndex: progressPageIndex,
        progressOffsetInPage: 0,
      ),
    );
  }

  /// The same screen over a structured document, to prove the policy is
  /// written once rather than per artifact.
  Future<void> seedDocument() async {
    await seedCollection();
    final blocks = <DocumentBlock>[
      const DocumentBlock(
        index: 0,
        type: DocumentBlockType.heading,
        text: 'The Saved Page',
        level: 1,
      ),
    ];
    for (var i = 1; i <= 30; i++) {
      blocks.add(
        DocumentBlock(
          index: i,
          type: DocumentBlockType.paragraph,
          text:
              'Paragraph $i. '
              '${List.filled(12, 'Words that fill a line of prose.').join(' ')}',
        ),
      );
    }
    final document = StructuredDocument(
      schemaVersion: StructuredDocument.currentSchemaVersion,
      title: 'The Saved Page',
      sourceUrl: 'https://x.example/guide/foo/1',
      blocks: blocks,
    );
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: 'c1',
    );
    await staging.documentFile.writeAsString(document.encode());
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.structuredDocument,
        document: DocumentRef(
          relativePath: FileStore.documentFileName,
          blockCount: document.blockCount,
          textLength: document.textLength,
        ),
        entryId: 'c1',
        collectionId: 'collection-1',
        sourceUrl: 'https://x.example/guide/foo/1',
        title: 'The Saved Page',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 0,
        storedAssetCount: 0,
        assets: const [],
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'article',
        contentKindConfidence: 'high',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 'collection-1',
        title: 'The Saved Page',
        sourceUrl: 'https://x.example/guide/foo/1',
        urlKey: 'https://x.example/guide/foo/1',
        artifactFormat: 'structuredDocument',
        saveStatus: 'complete',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 0,
        storedAssetCount: 0,
        entryOrder: 1,
        byteSize: 4096,
        entryNumber: 1,
        sourceMarker: 'Entry 1',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  Widget harness({String start = '/reader/c1'}) {
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
        readerChromeVisibleProvider.overrideWithValue(chromeFlag),
      ],
      child: MaterialApp.router(
        // The app's own placement: above the router, so the pill is over the
        // reader rather than inside it — which is what makes "the bars and the
        // indicator leave together" something to prove rather than assume.
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            ?child,
            OperationIndicator(
              onOpenDetails: () => detailsOpened++,
              onOpenBrowser: () => browserOpened++,
            ),
          ],
        ),
        routerConfig: GoRouter(
          initialLocation: start,
          routes: [
            GoRoute(
              path: '/collection/:collectionId',
              builder: (context, state) => CollectionDetailScreen(
                collectionId: state.pathParameters['collectionId']!,
              ),
            ),
            GoRoute(
              path: '/reader/:entryId',
              builder: (context, state) =>
                  ReaderScreen(entryId: state.pathParameters['entryId']!),
            ),
          ],
        ),
      ),
    );
  }

  /// Real file IO needs the event loop to turn, so the load is pumped with
  /// `runAsync` windows until the body appears.
  Future<void> openReader(WidgetTester tester, Finder body) async {
    await tester.pumpWidget(harness());
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (body.evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  /// Whether the chrome is on screen, read from the fade that draws it.
  ///
  /// The opacity *target* rather than its animated value, so no test has to
  /// wait out a transition to know what the reader decided.
  bool chromeVisible(WidgetTester tester) {
    final fade = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byTooltip('Back'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    return fade.opacity == 1.0;
  }

  /// Let any in-flight momentum and the chrome fade finish, on the fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Unmount inside the body, then let the disposal timers that drift's stream
  /// teardown schedules actually run — the fake clock only turns while the test
  /// body is still going. Same reason `reader_navigation_test.dart` does it.
  void readerTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  /// The scenarios that must hold for every reader body, run against each.
  void sharedScenarios({
    required String mode,
    required Future<void> Function() seed,
    required Finder Function() body,
  }) {
    Future<void> open(WidgetTester tester) async {
      await tester.runAsync(seed);
      await openReader(tester, body());
    }

    /// Hide the chrome the way a reader does — one deliberate tap.
    Future<void> hideChrome(WidgetTester tester) async {
      await tester.tap(body());
      await tester.pump();
      expect(chromeVisible(tester), isFalse, reason: 'setup: chrome hidden');
    }

    group('$mode reader', () {
      readerTest('opens with the chrome showing', (tester) async {
        await open(tester);
        expect(
          chromeVisible(tester),
          isTrue,
          reason: 'the way out must never start hidden',
        );
      });

      readerTest('a clean tap hides it, and a second shows it again', (
        tester,
      ) async {
        await open(tester);
        await tester.tap(body());
        await tester.pump();
        expect(chromeVisible(tester), isFalse);

        await tester.tap(body());
        await tester.pump();
        expect(chromeVisible(tester), isTrue);
      });

      readerTest('reading scroll leaves it alone', (tester) async {
        await open(tester);
        await hideChrome(tester);

        await tester.drag(body(), const Offset(0, -600));
        await settle(tester);
        expect(chromeVisible(tester), isFalse);
      });

      readerTest('a fast flick leaves it alone', (tester) async {
        await open(tester);
        await hideChrome(tester);

        await tester.fling(body(), const Offset(0, -400), 3000);
        await settle(tester);
        expect(chromeVisible(tester), isFalse);
      });

      readerTest('stopping momentum is a stop, not a toggle', (tester) async {
        await open(tester);
        await hideChrome(tester);

        await tester.fling(body(), const Offset(0, -400), 3000);
        await tester.pump(const Duration(milliseconds: 60));
        // The finger lands while the content is still coasting.
        await tester.tap(body());
        await settle(tester);
        expect(
          chromeVisible(tester),
          isFalse,
          reason: 'a touch that arrests a fling asked for nothing else',
        );
      });

      readerTest('a resting thumb is not a tap', (tester) async {
        await open(tester);
        await hideChrome(tester);

        final gesture = await tester.startGesture(tester.getCenter(body()));
        await tester.pump(const Duration(seconds: 3));
        // Synthetic pointers default every timestamp to zero, so the contact
        // duration has to be stated; real events carry the platform's own.
        await gesture.up(timeStamp: const Duration(seconds: 3));
        await settle(tester);
        expect(chromeVisible(tester), isFalse);
      });

      readerTest('a back-and-forth shuffle is not a tap, however small', (
        tester,
      ) async {
        await open(tester);
        await hideChrome(tester);

        // Ends 0px from where it started, but travels 72px getting there —
        // which is exactly the gesture the scroll view's signed accumulation
        // cannot see, and the reason total path is what gets measured.
        final gesture = await tester.startGesture(tester.getCenter(body()));
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(Offset(0, i.isEven ? -6 : 6));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await gesture.up();
        await settle(tester);
        expect(chromeVisible(tester), isFalse);
      });

      readerTest('one small movement still counts as a tap', (tester) async {
        await open(tester);
        await hideChrome(tester);

        // Below the touch slop, so the content never moves and both platforms
        // would call this a tap. The reader agrees with them rather than
        // inventing a threshold of its own.
        final gesture = await tester.startGesture(tester.getCenter(body()));
        await gesture.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.up();
        await settle(tester);
        expect(chromeVisible(tester), isTrue);
      });

      readerTest('a second finger cancels the toggle', (tester) async {
        await open(tester);
        await hideChrome(tester);

        final centre = tester.getCenter(body());
        final first = await tester.startGesture(centre);
        await tester.pump(const Duration(milliseconds: 20));
        final second = await tester.startGesture(centre + const Offset(60, 0));
        await tester.pump(const Duration(milliseconds: 20));
        await first.up();
        await second.up();
        await settle(tester);
        expect(chromeVisible(tester), isFalse);
      });

      readerTest('a cancelled touch leaves nothing behind', (tester) async {
        await open(tester);
        await hideChrome(tester);

        final gesture = await tester.startGesture(tester.getCenter(body()));
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.cancel();
        await settle(tester);
        expect(
          chromeVisible(tester),
          isFalse,
          reason: 'a cancel toggles nothing',
        );

        // …and the next tap is judged on its own merits.
        await tester.tap(body());
        await tester.pump();
        expect(chromeVisible(tester), isTrue);
      });

      readerTest('a tap still works after a suppressed gesture', (
        tester,
      ) async {
        await open(tester);
        await hideChrome(tester);

        await tester.drag(body(), const Offset(0, -600));
        await settle(tester);
        expect(chromeVisible(tester), isFalse);

        await tester.tap(body());
        await tester.pump();
        expect(
          chromeVisible(tester),
          isTrue,
          reason: 'suppression lasts one gesture, not until the next reload',
        );
      });

      readerTest('assistive activation is never judged by someone\'s thumb', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await open(tester);
        await hideChrome(tester);

        // A gesture that leaves a "not a tap" verdict behind, and which the
        // tap recogniser never gets to consume because the scroll view won.
        await tester.drag(body(), const Offset(0, -600));
        await settle(tester);
        expect(chromeVisible(tester), isFalse);

        // The semantics action itself, not a synthetic touch — this is the
        // path assistive technology actually takes into the body.
        final node = tester.getSemantics(
          find
              .ancestor(of: body(), matching: find.byType(GestureDetector))
              .first,
        );
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(
          chromeVisible(tester),
          isTrue,
          reason: 'a screen reader carries no pointer history to be blamed for',
        );
        semantics.dispose();
      });
    });
  }

  sharedScenarios(
    mode: 'image',
    seed: () => seedImages(),
    body: () => find.byType(ListView),
  );

  sharedScenarios(
    mode: 'document',
    seed: seedDocument,
    body: () => find.byType(DocumentBody),
  );

  // --- the background-activity indicator over the reader -------------------

  /// One waiting save, so there is something for the indicator to report.
  Future<void> queueWork() => db.upsertQueueTask(
    QueueTask(
      id: 'waiting-1',
      taskType: QueueTaskType.entrySave.name,
      startUrl: 'https://x.example/guide/foo/9',
      captureModeIsUserSet: false,
      state: QueueTaskState.queued.name,
      origin: kQueueOriginQueue,
      orderIndex: 0,
      queuedAt: DateTime(2026, 8, 1),
    ),
  );

  final pill = find.byKey(const ValueKey('operationIndicator'));

  group('the activity indicator follows the chrome', () {
    readerTest('it is there while the bars are, and goes with them', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedImages();
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await settle(tester);

      expect(pill, findsOneWidget, reason: 'work is outstanding');
      expect(chromeFlag.value, isTrue);

      await tester.tap(find.byType(ListView));
      await settle(tester);

      expect(chromeVisible(tester), isFalse);
      expect(
        pill,
        findsNothing,
        reason: 'nothing may float over a page being read',
      );
      expect(chromeFlag.value, isFalse);
    });

    readerTest('bringing the bars back brings it back', (tester) async {
      await tester.runAsync(() async {
        await seedImages();
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await settle(tester);

      await tester.tap(find.byType(ListView));
      await settle(tester);
      expect(pill, findsNothing);

      await tester.tap(find.byType(ListView));
      await settle(tester);

      expect(chromeVisible(tester), isTrue);
      expect(pill, findsOneWidget);
    });

    readerTest('a reading scroll disturbs neither', (tester) async {
      await tester.runAsync(() async {
        await seedImages();
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await settle(tester);

      final before = tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .offset;
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await settle(tester);
      final after = tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .offset;

      expect(after, greaterThan(before), reason: 'the page still scrolls');
      expect(
        pill,
        findsOneWidget,
        reason: 'a scroll is not a tap, and the chrome did not move',
      );
      expect(chromeVisible(tester), isTrue);
    });

    readerTest('it survives a move to the next entry', (tester) async {
      await tester.runAsync(() async {
        await seedImages();
        await seedImages(entryId: 'c2', order: 2);
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await settle(tester);
      expect(pill, findsOneWidget);

      // The move is made from the chrome, so it is made with the bars up.
      await tester.tap(find.text('Next entry'));
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(find.text('Entry 2'), findsWidgets, reason: 'setup: it moved');
      expect(
        pill,
        findsOneWidget,
        reason: 'one State spans both entries; the flag is not reset by a move',
      );

      // …and the pair still agree on the entry it arrived at. The reader keeps
      // its own `_chromeVisible` across the transition, so a stale published
      // flag would show up here as a pill that no longer follows the bars.
      await tester.tap(find.byType(ListView));
      await settle(tester);
      expect(chromeVisible(tester), isFalse);
      expect(pill, findsNothing);

      await tester.tap(find.byType(ListView));
      await settle(tester);
      expect(pill, findsOneWidget);
    });

    readerTest('it takes only its own box, and the page keeps the rest', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedImages();
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await settle(tester);

      // Directly beneath the pill, still in the top-right corner: the page,
      // not the indicator. A tap there toggles the chrome as any body tap does.
      final box = tester.getRect(pill);
      await tester.tapAt(Offset(box.center.dx, box.bottom + 24));
      await settle(tester);

      expect(
        chromeVisible(tester),
        isFalse,
        reason: 'the tap reached the reader body, not the pill',
      );
      expect(detailsOpened, 0);
      expect(browserOpened, 0);
    });

    readerTest('leaving the reader hands the indicator back', (tester) async {
      await tester.runAsync(() async {
        await seedImages();
        await queueWork();
      });
      await openReader(tester, find.byType(ListView));
      await tester.tap(find.byType(ListView));
      await settle(tester);
      expect(chromeFlag.value, isFalse, reason: 'setup: the bars are hidden');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        chromeFlag.value,
        isTrue,
        reason: 'a reader that is gone hides nothing',
      );
    });
  });

  // --- everything the fix must not have disturbed --------------------------

  group('unchanged behaviour', () {
    readerTest('the jump chip still follows the chrome', (tester) async {
      // Restored well into the entry, so wandering away earns the chip.
      await tester.runAsync(() => seedImages(progressFraction: 0.35));
      await openReader(tester, find.byType(ListView));

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
      expect(
        find.textContaining('Continue ·'),
        findsOneWidget,
        reason: 'the reader has drifted from where it was restored',
      );

      // Hiding the chrome takes the chip with it…
      await tester.tap(find.byType(ListView));
      await tester.pump();
      expect(chromeVisible(tester), isFalse);
      expect(find.textContaining('Continue ·'), findsNothing);

      // …and showing it brings the chip back.
      await tester.tap(find.byType(ListView));
      await tester.pump();
      expect(find.textContaining('Continue ·'), findsOneWidget);
    });

    readerTest('a right swipe still leaves for the entry list', (tester) async {
      await tester.runAsync(() => seedImages());
      await openReader(tester, find.byType(ListView));

      await tester.drag(find.byType(ListView), const Offset(220, 0));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byType(CollectionDetailScreen), findsOneWidget);
    });

    readerTest('reading progress still tracks the scroll', (tester) async {
      await tester.runAsync(() => seedImages());
      await openReader(tester, find.byType(ListView));

      final percent = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('%') ?? false),
      );
      expect(tester.widget<Text>(percent).data, '0%');

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await settle(tester);

      final after = int.parse(
        tester.widget<Text>(percent).data!.replaceAll('%', ''),
      );
      expect(
        after,
        greaterThan(0),
        reason: 'the readout moves while the reader scrolls',
      );
    });
  });
}
