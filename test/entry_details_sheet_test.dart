import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/connectivity.dart';
import 'package:web_reader/features/entry_actions.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// Tap reads; long press explains. The two must never both fire.
class _FakeConnectivity implements Connectivity {
  @override
  Duration get timeout => const Duration(seconds: 1);
  @override
  Future<bool> canReach(String host) async => true;
}

void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late BrowserController browser;
  String? lastRoute;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_details');
    store = FileStore(root);
    browser = BrowserController();
    lastRoute = null;
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seed({
    bool offline = true,
    double? number = 487,
    String? label = 'Part 487',
    String sourceUrl = 'https://x.example/guide/foo/487',
  }) async {
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
    if (offline) {
      Directory(
        '${root.path}/library/collection-1/entries/c1',
      ).createSync(recursive: true);
    }
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 'collection-1',
        title: 'Foo Part 487 Oku',
        sourceUrl: sourceUrl,
        urlKey: sourceUrl,
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: offline ? 'library/collection-1/entries/c1' : null,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 6,
        storedAssetCount: 6,
        entryOrder: 487,
        byteSize: 1536 * 1024,
        entryNumber: number,
        sourceMarker: label,
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

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
          builder: (context, state) {
            lastRoute = state.uri.toString();
            return const Scaffold(body: Text('READER'));
          },
        ),
        GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        connectivityProvider.overrideWithValue(_FakeConnectivity()),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        cleanupProvider.overrideWithValue(
          CleanupService(db: db, fileStore: store),
        ),
        taskQueueProvider.overrideWithValue(
          TaskQueueController(
            db: db,
            browser: browser,
            saveRun: SaveRunController(
              browser: browser,
              db: db,
              fileStore: store,
            ),
            checker: UpdateChecker(browser: browser, db: db),
            saveRunner: (_) async => const QueueOutcome.success('x'),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// 320 pt: the narrowest phone the app targets.
  Future<void> open(WidgetTester tester, {double width = 320}) async {
    // Tall enough that the row is built; the WIDTH is what the layout
    // requirement is about.
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const ValueKey('entryRow-c1')).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('the entry row never appeared');
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  final row = find.byKey(const ValueKey('entryRow-c1'));

  testWidgets('a tap opens the reader and no sheet', (tester) async {
    await seed();
    await open(tester);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(lastRoute, '/reader/c1');
    expect(find.text('Open entry'), findsNothing);
    await drain(tester);
  });

  testWidgets('a long press opens details and does NOT open the reader', (
    tester,
  ) async {
    await seed();
    await open(tester);

    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(
      lastRoute,
      isNull,
      reason: 'a long press must not also fire the tap',
    );
    expect(find.text('Open entry'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow at 320pt');
    await drain(tester);
  });

  testWidgets('the details show the facts the row cannot', (tester) async {
    await seed();
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    // Scoped to the sheet: the host and the label also appear on the screen
    // behind it, and this is an assertion about the sheet.
    Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );

    // The heading is the display label. This entry has no detected shape, so
    // the label falls back to the marker the source wrote — the app does not
    // print a noun of its own over content it could not classify. The sheet
    // then shows that string once: it lists the raw marker separately only when
    // it differs from the heading, because repeating it is noise.
    expect(inSheet('Part 487'), findsOneWidget);
    expect(inSheet('Not started'), findsOneWidget);
    expect(inSheet('Available · 1.5 MB'), findsOneWidget);
    expect(inSheet('6 images'), findsOneWidget);
    expect(
      inSheet('x.example'),
      findsNWidgets(2),
      reason: 'the Source fact, and the Open-on-website subtitle',
    );
    expect(inSheet('https://x.example/guide/foo/487'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('mark as read moves the row, from inside the sheet', (
    tester,
  ) async {
    await seed();
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();

    expect((await db.entryById('c1'))!.readStatus, 'completed');
    // The sheet re-reads the live row, so it now offers the opposite.
    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a part-read entry reports its progress', (tester) async {
    await seed();
    await ReadingRepository(
      db,
    ).saveProgress('c1', const ReadingPosition(fraction: 0.42, anchorIndex: 2));
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('42% read'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an offline-removed entry offers save, not removal', (
    tester,
  ) async {
    await seed(offline: false);
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('Open entry'), findsNothing);
    expect(find.text('Remove offline files'), findsNothing);
    expect(find.text('Add to save queue'), findsOneWidget);
    expect(find.text('Not downloaded'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('re-fetch is offered for an available entry', (tester) async {
    await seed();
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('Re-fetch'), findsOneWidget);
    expect(find.text('Remove offline files'), findsOneWidget);
    expect(
      find.text('Delete entry'),
      findsNothing,
      reason: 'permanent metadata deletion does not exist in this product',
    );
    await drain(tester);
  });

  testWidgets('an entry with no URL cannot be re-fetched or opened on web', (
    tester,
  ) async {
    await seed(sourceUrl: '');
    await open(tester);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('Re-fetch'), findsNothing);
    expect(
      find.text('The original page is unknown for this entry'),
      findsOneWidget,
    );
    expect(find.text('Unknown'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an unnumbered entry keeps its own name', (tester) async {
    await seed(number: null, label: 'Prologue');
    await open(tester);

    expect(find.text('Prologue'), findsWidgets);
    expect(find.textContaining('Entry null'), findsNothing);
    await drain(tester);
  });

  testWidgets('the sort toggle flips the list and persists', (tester) async {
    await seed();
    await db.upsertEntry(
      (await db.entryById('c1'))!.copyWith(
        id: 'c2',
        entryNumber: const Value(488),
        sourceMarker: const Value('Part 488'),
        urlKey: 'https://x.example/guide/foo/488',
        entryOrder: 488,
      ),
    );
    await open(tester, width: 430);

    List<String> order() => [
      for (final w in tester.widgetList<InkWell>(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('entryRow-'),
        ),
      ))
        (w.key! as ValueKey<String>).value,
    ];

    expect(order(), ['entryRow-c2', 'entryRow-c1']);

    await tester.tap(find.byKey(const ValueKey('entrySortToggle')));
    await tester.pumpAndSettle();

    expect(order(), ['entryRow-c1', 'entryRow-c2']);
    expect(
      await db.setting(kEntrySortKey),
      EntrySort.oldestFirst.name,
      reason: 'the choice is remembered, not just applied',
    );
    await drain(tester);
  });

  testWidgets('the First entry action is gone', (tester) async {
    await seed();
    await open(tester);

    expect(find.text('First'), findsNothing);
    expect(
      find.widgetWithText(TextButton, 'Part 487'),
      findsNothing,
      reason: 'the marker is a fact on the sheet, never an action',
    );
    // The primary action survives it.
    expect(find.textContaining('Read ·'), findsOneWidget);
    await drain(tester);
  });

  group('batch re-download from selection mode', () {
    Future<void> seedTwoRemoved(WidgetTester tester) async {
      await seed(offline: false);
      // A second removed entry, plus one with no source page at all.
      final base = (await db.entryById('c1'))!;
      await db.upsertEntry(
        base.copyWith(
          id: 'c2',
          urlKey: 'https://x.example/guide/foo/488',
          sourceUrl: 'https://x.example/guide/foo/488',
          entryNumber: const Value(488),
          sourceMarker: const Value('Part 488'),
          entryOrder: 488,
        ),
      );
      await db.upsertEntry(
        base.copyWith(
          id: 'c3',
          urlKey: 'orphan',
          sourceUrl: '',
          entryNumber: const Value(486),
          sourceMarker: const Value('Part 486'),
          entryOrder: 486,
        ),
      );
    }

    testWidgets('entries without files can be selected and queued', (
      tester,
    ) async {
      await seedTwoRemoved(tester);
      await open(tester, width: 430);

      // Enter selection mode through the collection menu.
      await tester.tap(find.byTooltip('Collection actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage downloads'));
      await tester.pumpAndSettle();

      // Quick-select everything this device does not hold.
      await tester.tap(find.byTooltip('Select…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not downloaded'));
      await tester.pumpAndSettle();

      // The app bar and the selection bar both say it; the counts breakdown
      // is the selection bar's own line.
      expect(find.text('3 selected'), findsNWidgets(2));
      expect(find.textContaining('2 can be queued'), findsOneWidget);
      expect(find.textContaining('1 have no source page'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('queueSelectionButton')));
      await tester.pumpAndSettle();

      // The confirmation spells out the split before anything is queued.
      expect(find.text('Add to save queue'), findsWidgets);
      expect(find.text('3 entries'), findsOneWidget);
      expect(
        find.textContaining('cannot be saved automatically'),
        findsOneWidget,
      );

      await tester.tap(find.text('Queue 2 for re-download'));
      await tester.pumpAndSettle();

      // A plain future, not `watchQueueTasks().first`: awaiting a drift
      // stream inside testWidgets deadlocks against the fake clock.
      final rows = await db.pendingQueueTasks();
      expect(rows, hasLength(2), reason: 'the orphan is reported, not queued');
      // Ascending reading order, though the list showed newest first.
      final ordered = [...rows]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(ordered.map((t) => t.startUrl), [
        'https://x.example/guide/foo/487',
        'https://x.example/guide/foo/488',
      ]);
      expect(
        ordered.every((t) => t.state == 'queued'),
        isTrue,
        reason: 'queued, not started — nothing took the browser (D46)',
      );
      expect(browser.automationOwner, isNull);
      // And the user never left the collection screen.
      expect(find.byType(CollectionDetailScreen), findsOneWidget);
      await drain(tester);
    });
  });
}
