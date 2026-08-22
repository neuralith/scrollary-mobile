import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/reader_harness.dart';

/// The reader against real files: restore-at-open, lifecycle flushes, the
/// no-false-completion rule, and geometry from verified dimensions only.
///
/// iOS gives no callback on a hard force-quit, so the design under test is:
/// throttled writes bound the loss, lifecycle callbacks flush when they do
/// arrive, and nothing written during termination may claim a completion the
/// dwell rule did not grant.
///
/// The writes land where V2 keeps them: the anchor on the Entry's OfflineCopy
/// (device state, indexing these bytes), the read status through
/// `ReadingStateRepository`. There is no stored fraction to assert on — a
/// fraction would have to name the rendering it was measured against — so
/// "how far" is the anchor and "finished" is the reading state.
void main() {
  late ReaderHarness h;

  setUp(() => h = ReaderHarness());
  tearDown(() => h.close());

  Widget app(OfflineReaderData offline, String entryId) => ProviderScope(
    child: MaterialApp(
      home: ReaderScreen(entryId: entryId, offline: offline),
    ),
  );

  /// Three real 800x1200 panels, committed and recorded as this device's copy,
  /// with the reading anchor the test wants already on it.
  Future<String> seedEntry({int? anchorIndex, double? anchorOffset}) async {
    // Ordinal 201: the harness's own seeded library already holds 101, and an
    // ordinal is unique within its collection.
    final entryId = await h.seedEntry(title: 'Foo Entry', ordinal: 201);
    await h.seedImages(
      entryId: entryId,
      pages: 3,
      anchorIndex: anchorIndex,
      anchorOffset: anchorOffset,
    );
    return entryId;
  }

  /// The same three panels on disk, but with a manifest that *claims*
  /// [height] for each — the one thing [ReaderHarness.seedImages] cannot
  /// express, and the whole subject of the last test in this file.
  Future<String> seedClaiming({
    required int height,
    required bool verified,
    required double ordinal,
  }) async {
    final entryId = await h.seedEntry(title: 'Foo Entry', ordinal: ordinal);
    final collectionId = await h.collectionId();
    final staging = await h.fileStore.beginEntry(
      collectionId: collectionId,
      entryId: entryId,
    );
    final assets = <EntryAsset>[];
    for (var i = 1; i <= 3; i++) {
      final name = '00$i.png';
      await staging.assetFile(name).writeAsBytes(panelPng(entry: 1, index: i));
      assets.add(
        EntryAsset(
          index: i,
          sourceUrl: 'https://cdn.example/$i.png',
          status: AssetStatus.stored,
          relativePath: StagingHandle.assetRelativePath(name),
          mimeType: 'image/png',
          width: 800,
          height: height,
          dimensionsVerified: verified,
        ),
      );
    }
    const url = 'https://reading.example.com/serial-alpha/part-101';
    final relative = await h.fileStore.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: entryId,
        collectionId: collectionId,
        sourceUrl: url,
        title: 'Foo Entry',
        sourceMarker: 'Entry 1',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: 3,
        assets: assets,
      ),
    );
    await h.repos.offline.recordCopy(
      entryId: entryId,
      locationUrl: url,
      artifactFormat: ArtifactFormat.imageSequence.name,
      contentPath: relative,
      byteSize: await h.fileStore.entryByteSize(relative),
    );
    return entryId;
  }

  /// Real file IO cannot complete inside the test's fake-async zone, so the
  /// package is resolved in a `runAsync` window and the load is pumped with
  /// more of them, letting the event loop turn.
  Future<void> openReader(WidgetTester tester, String entryId) async {
    late OfflineReaderData offline;
    await tester.runAsync(() async => offline = await h.open(entryId));
    await tester.pumpWidget(app(offline, entryId));
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
    late String entryId;
    await tester.runAsync(
      () async => entryId = await seedEntry(anchorIndex: 1, anchorOffset: 0.25),
    );

    await openReader(tester, entryId);

    // Viewport width 800, panels 800x1200 → each lays out 1200 tall.
    // Anchor: panel 1 + 25% of it = 1200 + 300, plus the lead-in that keeps
    // content out from under the top chrome.
    expect(scrollPosition(tester).pixels, closeTo(kReaderTopSpacer + 1500, 1));
  });

  testWidgets('a lifecycle change flushes without waiting for the debounce', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async => entryId = await seedEntry());
    await openReader(tester, entryId);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));

    // Backgrounded well inside the 2s debounce window.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final copy = (await h.repos.offline.activeCopyOf(entryId))!;
    expect(
      copy.anchorOffset,
      isNotNull,
      reason: 'the position was written on backgrounding, not 2s later',
    );
    expect(copy.anchorOffset, greaterThan(0));
    expect((await h.repos.reading.stateOf(entryId)).status, ReadStatus.reading);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3)); // drain the debounce timer
  });

  testWidgets('termination during a fling never fakes a completion', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async => entryId = await seedEntry());
    await openReader(tester, entryId);

    // Straight to the bottom…
    scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));
    // …and killed before the dwell (800ms) elapses.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final state = await h.repos.reading.stateOf(entryId);
    expect(
      state.status,
      isNot(ReadStatus.completed),
      reason: 'reaching the end for an instant is not reading the entry',
    );
    expect(state.completedAt, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('staying past the threshold for the dwell completes', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async => entryId = await seedEntry());
    await openReader(tester, entryId);

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

    final state = await h.repos.reading.stateOf(entryId);
    expect(state.status, ReadStatus.completed);
    expect(state.completedAt, isNotNull);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a finished entry re-read from the top stays at 100%', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async {
      entryId = await seedEntry(anchorIndex: 2, anchorOffset: 0.9);
      await h.repos.reading.markRead(entryId);
    });

    await openReader(tester, entryId);

    // Back to the beginning to read it again. The scroll is real; the
    // *completion* is not undone by it.
    final position = scrollPosition(tester);
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 3)); // let the debounce fire

    expect(
      (await h.repos.reading.stateOf(entryId)).status,
      ReadStatus.completed,
    );
    // There is no stored fraction to contradict the status, so the rule shows
    // up where a reader can see it: the readout says finished, not 0%.
    expect(
      find.text('Completed'),
      findsOneWidget,
      reason: 'finished means 100%, whatever the scroll says',
    );
    expect(
      (await h.repos.offline.activeCopyOf(entryId))!.anchorIndex,
      0,
      reason: 'the anchor still follows, so resuming lands where they are',
    );
  });

  testWidgets('progress readout is live; persistence stays debounced (M12)', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async => entryId = await seedEntry());
    await openReader(tester, entryId);

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

    // …and the copy has NOT been written yet: the visible state leads, the
    // persisted anchor follows on the debounce.
    final beforeDebounce = (await h.repos.offline.activeCopyOf(entryId))!;
    expect(
      beforeDebounce.anchorIndex,
      isNull,
      reason: 'DB writes stay throttled — nothing lands inside the window',
    );

    // After the debounce elapses the same value is persisted.
    await tester.pump(const Duration(seconds: 3));
    final afterDebounce = (await h.repos.offline.activeCopyOf(entryId))!;
    expect(afterDebounce.anchorIndex, 1);
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
    late String verifiedId;
    late String claimedId;
    await tester.runAsync(() async {
      verifiedId = await seedClaiming(
        height: 4000,
        verified: true,
        ordinal: 201,
      );
      claimedId = await seedClaiming(
        height: 4000,
        verified: false,
        ordinal: 202,
      );
    });

    await openReader(tester, verifiedId);
    final fromVerified = scrollPosition(tester).maxScrollExtent;
    await tester.pump(const Duration(seconds: 3));

    // Tear the first reader down before opening the second. `openReader` waits
    // for "a ListView exists", which the previous reader still satisfies — so
    // without this the second measurement is the first one again, and the test
    // passes for both a correct and a broken implementation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await openReader(tester, claimedId);
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
