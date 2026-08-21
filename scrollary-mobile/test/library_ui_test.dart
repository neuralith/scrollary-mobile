import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/core/device_capacity_provider.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/features/storage_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/ui/status_style.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// The grouped library and collection detail, driven as widgets.
///
/// The offline reader is not built here (it needs a real FileStore), but the
/// route an entry tile pushes is asserted — the reader must stay reachable
/// through the new screens.
void main() {
  late AppDatabase db;
  late Directory harnessRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    harnessRoot = Directory.systemTemp.createTempSync('webread_ui');
  });
  tearDown(() async {
    await db.close();
    if (harnessRoot.existsSync()) harnessRoot.deleteSync(recursive: true);
  });

  const collection = 'https://a.example/guide/the-long-guide';

  Future<String> seedCollection({
    String host = 'a.example',
    String collectionIndexUrl = collection,
    List<int> entries = const [883, 884, 885],
    String status = 'complete',
  }) async {
    final repo = CollectionRepository(db);
    String? groupId;
    for (final n in entries) {
      final url = '$collectionIndexUrl/part-$n';
      final title = 'The Long Guide $n. part - Oku';
      final group = (await repo.resolveCollection(
        sequence: const SequenceShape(
          kind: SequenceKind.explicitNextPrev,
          confidence: ShapeConfidence.high,
        ),
        entryUrl: url,
        pageTitle: title,
      ))!;
      groupId = group.id;
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'c$n-$host',
          collectionId: group.id,
          title: title,
          sourceUrl: url,
          urlKey: url,
          artifactFormat: 'imageSequence',
          saveStatus: n == entries.last ? status : 'complete',
          contentPath: 'library/${group.id}/entries/c$n-$host',
          savedAt: DateTime(2026, 7, 20).add(Duration(days: n - 883)),
          detectedAssetCount: 6,
          storedAssetCount: status == 'partial' && n == entries.last ? 5 : 6,
          entryOrder: n - 882,
          byteSize: 2048,
          entryNumber: n.toDouble(),
          sourceMarker: '$n. part',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }
    return groupId!;
  }

  String? lastPushedRoute;

  /// Pump until the widget under test has data.
  ///
  /// Not `pumpAndSettle`: while the stream provider is still loading, the
  /// screen shows a CircularProgressIndicator, which animates forever and
  /// makes `pumpAndSettle` hang until it times out.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('timed out waiting for $finder');
  }

  /// The queue the screens under test enqueue into; rebuilt by [harness] so a
  /// test can read back what a tap actually queued, and in which order.
  late TaskQueueController queue;

  Widget harness(Widget child) {
    lastPushedRoute = null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => child),
        GoRoute(
          path: '/collection/:id',
          builder: (context, state) {
            lastPushedRoute = state.uri.toString();
            return CollectionDetailScreen(
              collectionId: state.pathParameters['id']!,
            );
          },
        ),
        GoRoute(
          path: '/reader/:entryId',
          builder: (context, state) {
            lastPushedRoute = state.uri.toString();
            return const Scaffold(body: Text('READER'));
          },
        ),
        GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
      ],
    );
    // The collection detail screen reaches the update checker and the save
    // run (for the check/save actions); both get inert instances over an
    // unattached browser, so no WebView is ever stood up.
    final browser = BrowserController();
    final checker = UpdateChecker(browser: browser, db: db);
    final saveRun = SaveRunController(
      browser: browser,
      db: db,
      fileStore: FileStore(harnessRoot),
    );
    // Real scheduler, stubbed work: queueing, ordering and history are the
    // real thing, and no WebView is ever asked for.
    queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: saveRun,
      checker: checker,
      saveRunner: (_) async => const QueueOutcome.success('saved'),
      checkRunner: (_) async => const QueueOutcome.success('checked'),
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        updateCheckerProvider.overrideWithValue(checker),
        saveRunProvider.overrideWithValue(saveRun),
        taskQueueProvider.overrideWithValue(queue),
        // A known device reading, so the header's storage entry renders a
        // real number instead of waiting on a platform channel.
        deviceStorageProvider.overrideWithValue(_FixedDeviceStorage()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  final collectionRows = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('collectionRow-'),
  );

  group('grouped library screen', () {
    screenTest('shows one row per collection, not one row per entry', (
      tester,
    ) async {
      await seedCollection();
      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.text('The Long Guide'));

      // The name also appears on the Continue card, so count the collection rows
      // instead: exactly one in All Collection.
      expect(collectionRows, findsOneWidget);
      expect(find.textContaining('3 unread'), findsOneWidget);
      // The entry labels belong on the detail screen, not the library list.
      expect(find.text('884. part'), findsNothing);
    });

    screenTest('two collection on one host appear as two rows', (tester) async {
      await seedCollection();
      await seedCollection(
        collectionIndexUrl: 'https://a.example/guide/another-guide',
        entries: const [1, 2],
        host: 'other',
      );

      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, collectionRows);

      expect(collectionRows, findsNWidgets(2));
    });

    screenTest('flags a collection containing a partial entry', (tester) async {
      await seedCollection(status: 'partial');
      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.textContaining('1 saved item partial'));

      expect(find.textContaining('1 saved item partial'), findsOneWidget);
    });

    screenTest('opens the collection detail screen on tap', (tester) async {
      final id = await seedCollection();
      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, collectionRows);

      await tester.tap(
        find
            .descendant(
              of: collectionRows.first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      await pumpUntil(tester, find.text('883. part'));

      expect(lastPushedRoute, '/collection/$id');
      expect(find.text('883. part'), findsOneWidget);
    });
  });

  group('continue reading', _continueReadingTests);
  group('library header alignment', _headerAlignmentTests);

  /// The progress ring for one entry row, so the read state is asserted on
  /// the real value rather than on which icon happened to be picked.
  EntryProgressRing readRing(String entryId, WidgetTester tester) => tester
      .widget<EntryProgressRing>(find.byKey(ValueKey('progressRing-$entryId')));

  final entryRows = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('entryRow-'),
  );

  group('collection detail screen', () {
    screenTest('lists entries newest first by default', (tester) async {
      final id = await seedCollection();
      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, entryRows);

      final labels = [
        for (final row in tester.widgetList<InkWell>(entryRows))
          ((row.key! as ValueKey<String>).value),
      ];
      expect(labels, [
        'entryRow-c885-a.example',
        'entryRow-c884-a.example',
        'entryRow-c883-a.example',
      ], reason: 'a reader who is up to date cares about the newest end');
    });

    screenTest('shows stored counts and save status', (tester) async {
      final id = await seedCollection(status: 'partial');
      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.textContaining('5/6 images'));

      expect(find.textContaining('5/6 images'), findsOneWidget);
      expect(find.textContaining('6/6 images'), findsNWidgets(2));
    });

    screenTest('an entry tile opens the offline reader', (tester) async {
      final id = await seedCollection();
      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.text('884. part'));

      await tester.tap(find.text('884. part'));
      await pumpUntil(tester, find.text('READER'));

      expect(lastPushedRoute, '/reader/c884-a.example');
      expect(find.text('READER'), findsOneWidget);
    });

    screenTest('renaming changes the heading, not the identity', (
      tester,
    ) async {
      final id = await seedCollection();
      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.byTooltip('Collection actions'));

      final before = (await db.collectionById(id))!;

      await tester.tap(find.byTooltip('Collection actions'));
      await pumpUntil(tester, find.text('Rename'));
      // The sheet slides in; tapping mid-animation lands off-screen.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Rename'));
      await pumpUntil(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'My Shelf Name');
      await tester.tap(find.text('Save'));
      await pumpUntil(tester, find.text('My Shelf Name'));

      expect(find.text('My Shelf Name'), findsWidgets);

      final after = (await db.collectionById(id))!;
      expect(after.userTitle, 'My Shelf Name');
      expect(after.collectionKey, before.collectionKey);
      expect(after.title, before.title);
      expect(after.sourceUrl, before.sourceUrl);
    });

    screenTest('an entry with no local files offers its source instead', (
      tester,
    ) async {
      final id = await seedCollection(entries: const [883]);
      await db.markEntryContentMissing('c883-a.example');

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, entryRows);

      await tester.tap(entryRows);
      await tester.pumpAndSettle();

      expect(
        lastPushedRoute,
        isNull,
        reason: 'there is nothing to read, so the reader must not open',
      );
      expect(find.text('Open on website'), findsOneWidget);
      expect(find.text('Add to save queue'), findsOneWidget);
    });
  });

  group('read vs saved are separate states (P0.2)', () {
    screenTest('a saved, unread entry never shows a checkmark', (tester) async {
      final id = await seedCollection(); // three complete, all unread

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.text('884. part'));

      expect(
        find.byIcon(Icons.download_for_offline),
        findsWidgets,
        reason: 'save-complete uses the download/offline vocabulary',
      );
      expect(
        find.descendant(
          of: entryRows,
          matching: find.byIcon(Icons.download_for_offline),
        ),
        findsNWidgets(3),
        reason: 'save-complete uses the download/offline vocabulary',
      );
      expect(
        readRing('c883-a.example', tester).completed,
        isFalse,
        reason: 'an unread entry must never render as finished',
      );
      expect(readRing('c883-a.example', tester).fraction, 0);
    });

    screenTest('reading an entry moves only the read indicator', (
      tester,
    ) async {
      final id = await seedCollection();
      await ReadingRepository(db).markRead('c883-a.example');

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, entryRows);

      expect(readRing('c883-a.example', tester).completed, isTrue);
      expect(readRing('c884-a.example', tester).completed, isFalse);
      expect(
        find.descendant(
          of: entryRows,
          matching: find.byIcon(Icons.download_for_offline),
        ),
        findsNWidgets(3),
        reason: 'save state is untouched by reading',
      );
    });

    screenTest('an in-progress entry shows its percentage, not a check', (
      tester,
    ) async {
      final id = await seedCollection();
      await ReadingRepository(db).saveProgress(
        'c884-a.example',
        const ReadingPosition(fraction: 0.42, anchorIndex: 2),
      );

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.text('42%'));

      expect(find.text('42%'), findsOneWidget);
      expect(readRing('c884-a.example', tester).completed, isFalse);
      expect(
        readRing('c884-a.example', tester).fraction,
        closeTo(0.42, 0.01),
        reason: 'the ring shows the real value, not a bucketed icon',
      );
    });

    screenTest('the collection card counts unread offline entries', (
      tester,
    ) async {
      final id = await seedCollection();
      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.textContaining('3 unread'));
      expect(find.textContaining('3 unread'), findsOneWidget);

      await ReadingRepository(db).markRead('c883-a.example');
      await pumpUntil(tester, find.textContaining('2 unread'));
      expect(find.textContaining('3 unread'), findsNothing);
      expect(id, isNotEmpty);
    });

    screenTest('an entry row inserted with no reading fields is unread', (
      tester,
    ) async {
      // The database default is the last line of defence: a bare insert (as
      // a migration or an old code path would produce) must come out unread.
      final id = await seedCollection(entries: const [883]);
      await db
          .into(db.entries)
          .insert(
            EntriesCompanion.insert(
              id: 'bare',
              collectionId: Value(id),
              title: 'The Long Guide 990. part',
              sourceUrl: '$collection/part-990',
              urlKey: '$collection/part-990',
              saveStatus: 'complete',
              contentPath: const Value('library/x/entries/bare'),
              entryNumber: const Value(990),
              sourceMarker: const Value('990. part'),
            ),
          );

      expect((await db.entryById('bare'))!.readStatus, 'unread');

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.text('990. part'));
      expect(readRing('bare', tester).completed, isFalse);
      expect(readRing('bare', tester).fraction, 0);
    });
  });

  group('new entries (M8)', () {
    /// An entry an update check discovered: known on the source, no bytes.
    Future<void> seedKnownRemote(String groupId, int n) => db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'r$n',
        collectionId: groupId,
        title: 'The Long Guide $n. part',
        sourceUrl: '$collection/part-$n',
        urlKey: '$collection/part-$n',
        artifactFormat: 'imageSequence',
        saveStatus: 'knownRemote',
        detectedAssetCount: 0,
        storedAssetCount: 0,
        entryOrder: n - 882,
        byteSize: 0,
        entryNumber: n.toDouble(),
        sourceMarker: '$n. part',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        discoveredAt: DateTime(2026, 7, 27),
        discoveryBasis: 'nextChain',
        discoveryConfidence: 'high',
      ),
    );

    screenTest('discovered entries show as a count on the collection row', (
      tester,
    ) async {
      final id = await seedCollection();
      await seedKnownRemote(id, 886);
      await seedKnownRemote(id, 887);
      await db.writeCollectionCheck(
        id,
        CollectionsCompanion(
          lastCheckAt: Value(DateTime(2026, 7, 27, 10)),
          lastCheckSuccessAt: Value(DateTime(2026, 7, 27, 10)),
          lastCheckResult: const Value('updatesAvailable'),
        ),
      );

      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.text('2 new'));

      expect(find.text('2 new'), findsOneWidget);
      // Discovered entries must not leak into the offline count: three are
      // on the device, two only on the source.
      expect(find.text('3'), findsOneWidget);
    });

    screenTest('never checked reads as "not checked yet", not zero', (
      tester,
    ) async {
      await seedCollection();
      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.text('Not checked yet'));

      expect(find.text('Not checked yet'), findsOneWidget);
      // No count of new entries anywhere: "never asked" must not render as
      // "asked, found nothing". (Scoped to a count — the Library-updates card
      // legitimately contains the words "new entries" in its own label.)
      expect(find.textContaining(RegExp(r'\d+ new')), findsNothing);
    });

    screenTest('a failed check is shown on the row, not hidden', (
      tester,
    ) async {
      final id = await seedCollection();
      await seedKnownRemote(id, 886);
      await db.writeCollectionCheck(
        id,
        CollectionsCompanion(
          lastCheckAt: Value(DateTime(2026, 7, 27, 10)),
          lastCheckError: const Value('source unreachable'),
          lastCheckResult: const Value('failed'),
        ),
      );

      await tester.pumpWidget(harness(const LibraryScreen()));
      await pumpUntil(tester, find.text('Check failed'));

      expect(find.text('Check failed'), findsOneWidget);
    });

    screenTest('the detail screen separates known-remote from saved', (
      tester,
    ) async {
      final id = await seedCollection();
      await seedKnownRemote(id, 886);

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.textContaining('NEW ON SOURCE'));

      expect(find.textContaining('SAVED · 3'), findsOneWidget);
      expect(find.text('886. part'), findsOneWidget);
      expect(find.textContaining('Save 1 saved item'), findsOneWidget);
      // The per-collection action names its own scope: this collection, not
      // the library.
      expect(find.text('Check this collection'), findsOneWidget);
      expect(
        find.textContaining('Checks this collection only'),
        findsOneWidget,
      );

      // The known-remote row is not an entry row: there is nothing local to
      // read, so it never becomes tappable into the reader.
      expect(find.byKey(const ValueKey('remoteRow-r886')), findsOneWidget);
      expect(find.byKey(const ValueKey('entryRow-r886')), findsNothing);
    });

    screenTest('saving the new entries starts at the oldest, not the newest', (
      tester,
    ) async {
      // The library holds up to 885; the source has 886–890. The list is
      // *shown* newest-first, and that display order used to become the
      // execution order — the fetch started at 890.
      final id = await seedCollection();
      for (var n = 886; n <= 890; n++) {
        await seedKnownRemote(id, n);
      }

      await tester.pumpWidget(
        harness(CollectionDetailScreen(collectionId: id)),
      );
      await pumpUntil(tester, find.textContaining('NEW ON SOURCE'));
      // Newest first on screen — deliberate, and left alone.
      expect(
        tester.getRect(find.text('890. part')).top,
        lessThan(tester.getRect(find.text('886. part')).top),
      );

      await tester.tap(find.textContaining('Save 5 saved items'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.map((t) => t.startUrl), [
        for (var n = 886; n <= 890; n++) '$collection/part-$n',
      ]);
      // Nothing started: queueing is never a start (D46).
      expect(queue.saveStartAuthorised, isFalse);
    });
  });
}

/// `testWidgets`, but the widget tree is torn down inside the test body.
///
/// Drift schedules a zero-duration timer when its query streams are disposed.
/// Left to the framework's own teardown that lands after the test has ended,
/// and every test fails with "pending timers" despite passing its assertions.
/// The Library header is one row: one centre line, one glyph size, and a
/// title that stays on one line at the narrowest width the app supports.
///
/// Written after the header shipped misaligned three ways at once — the
/// storage entry 4pt below every icon, its glyph at 15pt against their 22pt,
/// and "Library" wrapping to three lines at 320pt.
void _headerAlignmentTests() {
  late AppDatabase db;
  late Directory harnessRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    harnessRoot = Directory.systemTemp.createTempSync('webread_header');
  });
  tearDown(() async {
    await db.close();
    if (harnessRoot.existsSync()) harnessRoot.deleteSync(recursive: true);
  });

  Widget harness() {
    final browser = BrowserController();
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(FileStore(harnessRoot)),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        saveRunProvider.overrideWithValue(
          SaveRunController(
            browser: browser,
            db: db,
            fileStore: FileStore(harnessRoot),
          ),
        ),
        deviceStorageProvider.overrideWithValue(_FixedDeviceStorage()),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
            GoRoute(path: '/storage', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/archived', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
          ],
        ),
      ),
    );
  }

  Future<void> show(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('72%').evaluate().isNotEmpty) break;
    }
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  for (final width in [320.0, 430.0]) {
    testWidgets('every header action shares one centre line at $width', (
      tester,
    ) async {
      await show(tester, width);

      final centres = <double>[
        // Navigation only. Checking every collection left this row for a
        // labelled card in the list — a bare glyph could not say what it did.
        for (final icon in [Icons.inventory_2, Icons.settings])
          tester.getRect(find.byIcon(icon)).center.dy,
        tester.getRect(find.byType(StoragePill)).center.dy,
        tester.getRect(find.text('Library')).center.dy,
      ];
      for (final c in centres) {
        expect(
          c,
          closeTo(centres.first, 0.51),
          reason: 'the row must have ONE centre line, not one per widget',
        );
      }
      await drain(tester);
    });

    testWidgets('the storage glyph matches its neighbours at $width', (
      tester,
    ) async {
      await show(tester, width);

      final storage = tester.getRect(
        find.descendant(
          of: find.byType(StoragePill),
          matching: find.byIcon(Icons.storage),
        ),
      );
      expect(storage.width, kHeaderIconSize);
      expect(storage.height, kHeaderIconSize);
      // Same box height as every other action, which is what puts them on
      // the same centre line in the first place.
      expect(
        tester.getRect(find.byType(StoragePill)).height,
        kHeaderActionSize,
      );
      await drain(tester);
    });
  }

  testWidgets('the title stays on one line at 320pt', (tester) async {
    await show(tester, 320);

    final title = tester.getRect(find.text('Library'));
    expect(
      title.height,
      lessThan(40),
      reason: 'a wrapped title drags the whole header out of shape',
    );
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    await drain(tester);
  });

  testWidgets('the actions fit inside the screen at 320pt', (tester) async {
    await show(tester, 320);

    final settings = tester.getRect(find.byIcon(Icons.settings));
    expect(settings.right, lessThanOrEqualTo(320.01));
    // And the title is not squeezed to nothing to achieve it.
    expect(tester.getRect(find.text('Library')).width, greaterThan(80));
    await drain(tester);
  });
}

/// A device that always reports 72% used, so header layout assertions do not
/// depend on a platform channel.
class _FixedDeviceStorage implements DeviceStorage {
  @override
  Future<DeviceCapacity> capacity() async => const DeviceCapacity(
    totalBytes: 100 * 1024 * 1024 * 1024,
    freeBytes: 28 * 1024 * 1024 * 1024,
  );

  @override
  Future<int?> freeBytes() async => 28 * 1024 * 1024 * 1024;

  @override
  Future<bool> excludeFromBackup(String absolutePath) async => false;
}

void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    usePhoneSurface(tester);
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// The default 800×600 test window is wider and much shorter than any phone:
/// list rows fall off the bottom and bottom sheets open outside the tree, so
/// finders miss widgets that are perfectly visible on a real device.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Continue Reading and Recently Read, driven through the real library screen.
void _continueReadingTests() {
  late AppDatabase db;
  late ReadingRepository reading;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    reading = ReadingRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed({int entries = 3, String collectionId = 's1'}) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: collectionId,
        title: 'Collection $collectionId',
        sourceUrl: 'https://x.example/guide/$collectionId',
        host: 'x.example',
        collectionKey: '/guide/$collectionId',
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
          id: '$collectionId-c$n',
          collectionId: collectionId,
          title: 'Collection $collectionId Entry $n',
          sourceUrl: 'https://x.example/guide/$collectionId/$n',
          urlKey: 'https://x.example/guide/$collectionId/$n',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/$collectionId/entries/$collectionId-c$n',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 6,
          storedAssetCount: 6,
          entryOrder: n,
          byteSize: 1024,
          entryNumber: n.toDouble(),
          sourceMarker: 'Part $n',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }
  }

  // The library rows watch the update checker (for the live "Checking" chip)
  // and the strip watches the save run (for the waiting-for-browser
  // banner), so the harness gives them inert instances over an unattached
  // browser.
  Widget harness() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      updateCheckerProvider.overrideWithValue(
        UpdateChecker(browser: BrowserController(), db: db),
      ),
      saveRunProvider.overrideWithValue(
        SaveRunController(
          browser: BrowserController(),
          db: db,
          fileStore: FileStore(Directory.systemTemp.createTempSync('wr_cr')),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
          GoRoute(
            path: '/reader/:id',
            builder: (context, state) =>
                Scaffold(body: Text('READER ${state.pathParameters['id']}')),
          ),
          GoRoute(path: '/collection/:id', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
        ],
      ),
    ),
  );

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

  /// The card's progress line is a `Text.rich`, so it is found by its plain
  /// text rather than by a `Text.data`.
  Finder progressLine(String text) => find.text(text, findRichText: true);

  testWidgets('a partly read entry puts the collection in Continue Reading', (
    tester,
  ) async {
    await seed();
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.45));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    // Percentage and what is left after this entry — never a total, and
    // never a bar.
    expect(progressLine('45% • 2 saved items remaining'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Part 1'), findsOneWidget);

    final ring = tester.widget<EntryProgressRing>(
      find.byKey(const ValueKey('continueRing-s1-c1')),
    );
    expect(ring.fraction, closeTo(0.45, 0.001));
    expect(ring.completed, isFalse);
    await settleDown(tester);
  });

  testWidgets('the last readable entry says so instead of "0 remaining"', (
    tester,
  ) async {
    await seed(entries: 2);
    await reading.markRead('s1-c1');
    await reading.saveProgress('s1-c2', const ReadingPosition(fraction: 0.68));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(progressLine('68% • Latest saved item available'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('one later entry is singular', (tester) async {
    await seed(entries: 2);
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.1));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(progressLine('10% • 1 saved item remaining'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('the remaining count ignores entries that are not readable', (
    tester,
  ) async {
    await seed(entries: 3);
    // Discovered by an update check but never saved, and one whose files
    // were removed: neither is something the user can open next.
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 's1-c4',
        collectionId: 's1',
        title: 'Collection s1 Entry 4',
        sourceUrl: 'https://x.example/guide/s1/4',
        urlKey: 'https://x.example/guide/s1/4',
        artifactFormat: 'imageSequence',
        saveStatus: 'knownRemote',
        detectedAssetCount: 0,
        storedAssetCount: 0,
        entryOrder: 4,
        byteSize: 0,
        entryNumber: 4,
        sourceMarker: '4. part',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
    await db.writeEntryReading(
      's1-c3',
      EntriesCompanion(
        contentPath: const Value(null),
        byteSize: const Value(0),
        offlineRemovedAt: Value(DateTime(2026, 7, 26)),
      ),
    );
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.2));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(progressLine('20% • 1 saved item remaining'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('tapping a Continue card opens that entry', (tester) async {
    await seed();
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.45));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.byKey(const ValueKey('continueCard-s1-c1')));
    await tester.tap(find.byKey(const ValueKey('continueCard-s1-c1')));
    await pumpUntil(tester, find.textContaining('READER'));

    expect(find.text('READER s1-c1'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('completing an entry advances Continue to the next unread', (
    tester,
  ) async {
    await seed();
    await reading.markRead('s1-c1');

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(find.text('Part 2'), findsOneWidget);
    expect(progressLine('0% • 1 saved item remaining'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('a fully read collection says so rather than showing nothing', (
    tester,
  ) async {
    await seed(entries: 2);
    await reading.markRead('s1-c1');
    await reading.markRead('s1-c2');

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.textContaining('up to date'));

    expect(find.textContaining('finished every entry'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('marking an entry unread makes it continuable again', (
    tester,
  ) async {
    await seed(entries: 2);
    await reading.markRead('s1-c1');
    await reading.markRead('s1-c2');
    await reading.markUnread('s1-c1');

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(find.text('Part 1'), findsOneWidget);
    expect(find.textContaining('finished every entry'), findsNothing);
    await settleDown(tester);
  });

  testWidgets('Continue Reading orders by most recently read', (tester) async {
    await seed(collectionId: 's1', entries: 1);
    await seed(collectionId: 's2', entries: 1);
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.3));
    await reading.saveProgress('s2-c1', const ReadingPosition(fraction: 0.6));

    // Explicit timestamps, not a real delay: `Future.delayed` inside a widget
    // test never completes until the fake clock is pumped, so waiting on wall
    // time here deadlocks before the first pump.
    await db.writeEntryReading(
      's1-c1',
      EntriesCompanion(lastReadAt: Value(DateTime(2026, 7, 20))),
    );
    await db.writeEntryReading(
      's2-c1',
      EntriesCompanion(lastReadAt: Value(DateTime(2026, 7, 25))),
    );
    await reading.rebuildCollectionPointers();

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    final cards = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('continueCard-'),
    );
    expect(cards, findsNWidgets(2));
    // The most recently read collection comes first.
    expect(
      find.descendant(
        of: cards.first,
        matching: find.textContaining('Collection s2'),
      ),
      findsOneWidget,
    );
    await settleDown(tester);
  });

  testWidgets('one card per collection, never duplicated within a section', (
    tester,
  ) async {
    await seed(entries: 3);
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.2));
    await reading.saveProgress('s1-c2', const ReadingPosition(fraction: 0.4));

    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('continueCard-'),
      ),
      findsOneWidget,
    );
    await settleDown(tester);
  });

  testWidgets('reading progress updates the section without a restart', (
    tester,
  ) async {
    await seed();
    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));
    expect(progressLine('0% • 2 saved items remaining'), findsOneWidget);

    // Same app instance, no rebuild triggered by hand.
    await reading.saveProgress('s1-c1', const ReadingPosition(fraction: 0.5));
    await pumpUntil(tester, progressLine('50% • 2 saved items remaining'));

    expect(progressLine('50% • 2 saved items remaining'), findsOneWidget);
    await settleDown(tester);
  });

  testWidgets('saved but never opened says so rather than showing nothing', (
    tester,
  ) async {
    await seed();
    usePhoneSurface(tester);
    await tester.pumpWidget(harness());
    await pumpUntil(tester, find.text('CONTINUE READING'));

    // Never-opened collection still offer their first entry.
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Recently Read'), findsNothing);
    await settleDown(tester);
  });

  testWidgets(
    'a collection with no readable entries gives a useful empty state',
    (tester) async {
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 's9',
          title: 'Broken Collection',
          sourceUrl: 'https://x.example/guide/s9',
          host: 'x.example',
          collectionKey: '/guide/s9',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 's9-c1',
          collectionId: 's9',
          title: 'Broken Entry',
          sourceUrl: 'https://x.example/guide/s9/1',
          urlKey: 'https://x.example/guide/s9/1',
          artifactFormat: 'imageSequence',
          saveStatus: 'failed',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 6,
          storedAssetCount: 0,
          entryOrder: 1,
          byteSize: 0,
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );

      usePhoneSurface(tester);
      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.text('CONTINUE READING'));

      expect(find.text('Nothing readable yet'), findsOneWidget);
      await settleDown(tester);
    },
  );
}
