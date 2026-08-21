import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

/// The reader against real files: restore-at-open, lifecycle flushes, the
/// no-false-completion rule, and manifest dimension repair on open.
///
/// iOS gives no callback on a hard force-quit, so the design under test is:
/// throttled writes bound the loss, lifecycle callbacks flush when they do
/// arrive, and nothing written during termination may claim a completion the
/// dwell rule did not grant.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_reader');
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

  /// Three real 800x1200 panels on disk; the manifest records
  /// [manifestWidth]x[manifestHeight] (defaults: the truth).
  Future<void> seedEntry({
    String id = 'c1',
    int manifestWidth = 800,
    int manifestHeight = 1200,
    bool verified = true,
  }) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Fixture',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: id,
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
          width: manifestWidth,
          height: manifestHeight,
          dimensionsVerified: verified,
        ),
      );
    }
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: 1,
        entryId: id,
        collectionId: 'collection-1',
        sourceUrl: 'https://x.example/guide/foo/$id',
        title: 'Foo Entry $id',
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
        id: id,
        collectionId: 'collection-1',
        title: 'Foo Entry $id',
        sourceUrl: 'https://x.example/guide/foo/$id',
        urlKey: 'https://x.example/guide/foo/$id',
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

  Widget harness({String entryId = 'c1'}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fileStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(home: ReaderScreen(entryId: entryId)),
  );

  /// Real file IO cannot complete inside the test's fake-async zone, so the
  /// load is pumped with `runAsync` windows that let the event loop turn.
  Future<void> openReader(WidgetTester tester, {String id = 'c1'}) async {
    await tester.pumpWidget(harness(entryId: id));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ListView).evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('opens at the saved anchor, not at the top', (tester) async {
    await tester.runAsync(seedEntry);
    await db.writeEntryReading(
      'c1',
      EntriesCompanion(
        readStatus: const Value('inProgress'),
        progressFraction: const Value(0.45),
        progressPageIndex: const Value(1),
        progressOffsetInPage: const Value(0.25),
        lastReadAt: Value(DateTime(2026, 7, 26)),
        progressUpdatedAt: Value(DateTime(2026, 7, 26)),
      ),
    );

    await openReader(tester);

    // Viewport width 800, panels 800x1200 → each lays out 1200 tall.
    // Anchor: panel 1 + 25% of it = 1200 + 300, plus the lead-in that keeps
    // content out from under the top chrome.
    expect(scrollPosition(tester).pixels, closeTo(kReaderTopSpacer + 1500, 1));
  });

  testWidgets('a lifecycle change flushes without waiting for the debounce', (
    tester,
  ) async {
    await tester.runAsync(seedEntry);
    await openReader(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));

    // Backgrounded well inside the 2s debounce window.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final entry = (await db.entryById('c1'))!;
    expect(
      entry.progressUpdatedAt,
      isNotNull,
      reason: 'the position was written on backgrounding, not 2s later',
    );
    expect(entry.progressFraction, greaterThan(0));
    expect(entry.readStatus, 'inProgress');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3)); // drain the debounce timer
  });

  testWidgets('termination during a fling never fakes a completion', (
    tester,
  ) async {
    await tester.runAsync(seedEntry);
    await openReader(tester);

    // Straight to the bottom…
    scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));
    // …and killed before the dwell (800ms) elapses.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final entry = (await db.entryById('c1'))!;
    expect(
      entry.readStatus,
      isNot('completed'),
      reason: 'reaching the end for an instant is not reading the entry',
    );
    expect(entry.completedAt, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('staying past the threshold for the dwell completes', (
    tester,
  ) async {
    await tester.runAsync(seedEntry);
    await openReader(tester);

    final position = scrollPosition(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));
    // The dwell measures wall-clock time, so wait for real; then a second
    // scroll event confirms the stay.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    position.jumpTo(position.maxScrollExtent - 1);
    await tester.pump(const Duration(milliseconds: 50));

    final entry = (await db.entryById('c1'))!;
    expect(entry.readStatus, 'completed');
    expect(entry.completedAt, isNotNull);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a finished entry re-read from the top stays at 100%', (
    tester,
  ) async {
    await tester.runAsync(seedEntry);
    await db.writeEntryReading(
      'c1',
      EntriesCompanion(
        readStatus: const Value('completed'),
        completedAt: Value(DateTime(2026, 7, 25)),
        progressFraction: const Value(1),
        progressPageIndex: const Value(2),
        progressOffsetInPage: const Value(0.9),
      ),
    );

    await openReader(tester);

    // Back to the beginning to read it again. The scroll is real; the
    // *completion* is not undone by it.
    final position = scrollPosition(tester);
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 3)); // let the debounce fire

    final entry = (await db.entryById('c1'))!;
    expect(entry.readStatus, 'completed');
    expect(
      entry.progressFraction,
      1,
      reason: 'finished means 100%, whatever the scroll says',
    );
    expect(
      entry.progressPageIndex,
      0,
      reason: 'the anchor still follows, so resuming lands where they are',
    );
  });

  testWidgets('progress readout is live; persistence stays debounced (M12)', (
    tester,
  ) async {
    await tester.runAsync(seedEntry);
    await openReader(tester);

    // At the top: 0%. The percentage is the whole readout — the panel counter
    // that used to sit beside it is gone.
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('panel '), findsNothing);

    // Scroll into panel 2 and give the UI a single frame — far inside the
    // 2 s persistence debounce.
    scrollPosition(tester).jumpTo(1500);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('0%'),
      findsNothing,
      reason: 'the percentage must move while scrolling, not after leaving',
    );

    // …and the database has NOT been written yet: the visible state leads,
    // the persisted state follows on the debounce.
    final beforeDebounce = (await db.entryById('c1'))!;
    expect(
      beforeDebounce.progressUpdatedAt,
      isNull,
      reason: 'DB writes stay throttled — nothing lands inside the window',
    );

    // After the debounce elapses the same value is persisted.
    await tester.pump(const Duration(seconds: 3));
    final afterDebounce = (await db.entryById('c1'))!;
    expect(afterDebounce.progressUpdatedAt, isNotNull);
    expect(afterDebounce.progressPageIndex, 1);
  });

  // The repair-on-open pass is gone: a version-1 library decodes page dimensions
  // out of the stored bytes when it saves, so there is nothing to reconcile
  // afterwards, and re-reading every file on every open to fix manifests this
  // build never wrote would be migration machinery for a shape no library has.
  //
  // What survives is the case that pass also covered: a file whose header the
  // decoder could not read. The manifest then holds the *page's own claim* about
  // the size — a layout assertion, not a pixel fact. Panels sized from it laid
  // out at the wrong aspect ratio, which is what "the saved page looks squashed"
  // was.
  testWidgets('geometry follows verified dimensions, never an unverified claim', (
    tester,
  ) async {
    // Identical manifests — three 800x4000 panels — differing only in whether
    // the save path could decode those numbers out of the bytes.
    await tester.runAsync(
      () => seedEntry(id: 'verified', manifestHeight: 4000, verified: true),
    );
    await tester.runAsync(
      () => seedEntry(id: 'claimed', manifestHeight: 4000, verified: false),
    );

    await openReader(tester, id: 'verified');
    final fromVerified = scrollPosition(tester).maxScrollExtent;
    await tester.pump(const Duration(seconds: 3));

    // Tear the first reader down before opening the second. `openReader` waits
    // for "a ListView exists", which the previous reader still satisfies — so
    // without this the second measurement is the first one again, and the test
    // passes for both a correct and a broken implementation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await openReader(tester, id: 'claimed');
    final fromClaim = scrollPosition(tester).maxScrollExtent;

    // The verified pages are 5x as tall as they are wide, so they must produce a
    // markedly taller document than the fallback box an unverifiable file gets.
    expect(
      fromVerified,
      greaterThan(fromClaim * 1.5),
      reason:
          'an unverified 4000px claim must not dictate layout, or an '
          'undecodable file decides the shape of the page '
          '(verified=$fromVerified, claimed=$fromClaim)',
    );
    await tester.pump(const Duration(seconds: 3));
  });
}
