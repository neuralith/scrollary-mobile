import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/domain/offline_copy.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/features/document_reader.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'helpers/reader_harness.dart';

/// The reader against real document packages.
///
/// The image reader has its own suite; what is asserted here is that the
/// screen picks its path from the manifest's artifact discriminator, that a
/// text entry opens with nothing but local files, and that the reading
/// position survives a reopen even though a paragraph's offset cannot be known
/// until it has been laid out.
///
/// Everything arrives through the OfflineCopy: the package this device holds,
/// and the anchor inside it. There is no library row behind any of it, which
/// is why the anchor is asserted on the copy and the reading state on
/// `ReadingStateRepository` — never on a column of an Entry.
void main() {
  late ReaderHarness harness;

  setUp(() => harness = ReaderHarness());

  tearDown(() => harness.close());

  /// A document long enough to scroll, so a restore has somewhere to land.
  StructuredDocument buildDocument({required bool withImages}) {
    final blocks = <DocumentBlock>[
      const DocumentBlock(
        index: 0,
        type: DocumentBlockType.heading,
        text: 'The Saved Page',
        level: 1,
      ),
    ];
    var index = 1;
    for (var i = 0; i < 24; i++) {
      blocks.add(
        DocumentBlock(
          index: index++,
          type: DocumentBlockType.paragraph,
          text:
              'Paragraph $i. ${List.filled(12, 'Words that fill a line of prose.').join(' ')}',
        ),
      );
      if (withImages && i == 4) {
        blocks.add(
          DocumentBlock(
            index: index++,
            type: DocumentBlockType.image,
            assetIndex: 1,
            imageSourceUrl: 'https://example.com/a.png',
            alt: 'A figure',
          ),
        );
      }
      if (withImages && i == 9) {
        // An image whose bytes never arrived: the position survives, the
        // picture does not, and the reader has to say so.
        blocks.add(
          DocumentBlock(
            index: index++,
            type: DocumentBlockType.image,
            imageSourceUrl: 'https://example.com/missing.png',
            alt: 'A figure that was not saved',
          ),
        );
      }
    }
    return StructuredDocument(
      schemaVersion: StructuredDocument.currentSchemaVersion,
      title: 'The Saved Page',
      sourceUrl: 'https://example.com/text/1',
      blocks: blocks,
    );
  }

  /// An Entry with a committed document package and the OfflineCopy that ties
  /// them together — what a device that has actually saved the page holds.
  Future<({String entryId, String relativePath})> seedDocument({
    bool withImages = false,
    SaveStatus status = SaveStatus.complete,
    String? body,
    int? anchorIndex,
    double? anchorOffset,
  }) async {
    // 202, not the ordinal the harness's own seeded Entry already holds.
    final entryId = await harness.seedEntry(
      title: 'The Saved Page',
      ordinal: 202,
    );
    final relativePath = await harness.seedDocument(
      entryId: entryId,
      document: buildDocument(withImages: withImages),
      status: status,
      // Two images in the document, one of which was stored.
      detectedAssetCount: withImages ? 2 : 0,
      storedAssetCount: withImages ? 1 : 0,
      assets: withImages
          ? const [
              EntryAsset(
                index: 1,
                sourceUrl: 'https://example.com/a.png',
                status: AssetStatus.stored,
                relativePath: 'assets/001.png',
                mimeType: 'image/png',
                width: 800,
                height: 1200,
                dimensionsVerified: true,
              ),
            ]
          : const [],
      body: body,
      anchorIndex: anchorIndex,
      anchorOffset: anchorOffset,
    );
    return (entryId: entryId, relativePath: relativePath);
  }

  /// Real file IO cannot complete inside the fake-async zone, so the load is
  /// pumped with `runAsync` windows that let the event loop turn.
  Future<void> open(
    WidgetTester tester,
    String entryId, {
    Finder? until,
  }) async {
    final target = until ?? find.byType(DocumentBody);
    late OfflineReaderData data;
    // Exactly what the route resolves before it builds the screen.
    await tester.runAsync(() async => data = await harness.open(entryId));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReaderScreen(entryId: entryId, offline: data),
        ),
      ),
    );
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (target.evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('a text-only entry opens offline with its prose', (tester) async {
    late String entryId;
    await tester.runAsync(() async => entryId = (await seedDocument()).entryId);
    await open(tester, entryId);

    expect(find.byType(DocumentBody), findsOneWidget);
    // The image reader's list is NOT what rendered.
    expect(find.byType(ListView), findsNothing);
    expect(find.text('The Saved Page'), findsWidgets);
    expect(find.textContaining('Paragraph 0.'), findsOneWidget);
  });

  testWidgets('a text-and-images entry renders its inline image', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(
      () async => entryId = (await seedDocument(withImages: true)).entryId,
    );
    await open(tester, entryId);

    // `Image.file(..., cacheWidth:)` wraps the provider, so unwrap before
    // asserting on it.
    FileImage? asFile(ImageProvider provider) => switch (provider) {
      FileImage file => file,
      ResizeImage resize when resize.imageProvider is FileImage =>
        resize.imageProvider as FileImage,
      _ => null,
    };

    final files = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => asFile(i.image))
        .nonNulls
        .toList();
    expect(files, isNotEmpty, reason: 'the stored inline image should render');

    // Every path is a local file. A remote fallback would make "offline" a
    // lie that only shows up once the network is gone.
    for (final file in files) {
      expect(file.file.path, startsWith(harness.root.path));
    }
  });

  testWidgets('an inline image that was never saved says so', (tester) async {
    late String entryId;
    await tester.runAsync(
      () async => entryId = (await seedDocument(withImages: true)).entryId,
    );
    await open(tester, entryId);

    await tester.scrollUntilVisible(
      find.textContaining('This image was not saved'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    expect(find.textContaining('This image was not saved'), findsOneWidget);
  });

  testWidgets('a document restores to its saved block after layout', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(
      () async => entryId = (await seedDocument(
        // Block 12, halfway down it. The anchor lives on the copy: an index
        // into these bytes, meaningless without them.
        anchorIndex: 12,
        anchorOffset: 0.5,
      )).entryId,
    );

    await open(tester, entryId);
    // The restore lands one frame after measurement.
    await tester.pump();
    await tester.pump();

    expect(
      scrollPosition(tester).pixels,
      greaterThan(0),
      reason: 'a saved position must not open at the top',
    );
  });

  testWidgets('scrolling a document writes a block anchor back', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async => entryId = (await seedDocument()).entryId);
    await open(tester, entryId);

    await tester.drag(find.byType(DocumentBody), const Offset(0, -1200));
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    late OfflineCopy? copy;
    await tester.runAsync(
      () async => copy = await harness.repos.offline.activeCopyOf(entryId),
    );
    expect(
      copy!.anchorIndex,
      greaterThan(0),
      reason: 'the anchor indexes a block, not a panel',
    );
    expect(copy!.anchorOffset, isNotNull);
  });

  testWidgets('a completed text entry still reads as finished', (tester) async {
    late String entryId;
    await tester.runAsync(() async {
      entryId = (await seedDocument()).entryId;
      await harness.repos.reading.markRead(entryId);
    });

    await open(tester, entryId);

    late ReadingState state;
    await tester.runAsync(
      () async => state = await harness.repos.reading.stateOf(entryId),
    );
    // Re-opening a finished entry must not un-finish it.
    expect(state.status, ReadStatus.completed);
    expect(state.completedAt, isNotNull);
  });

  testWidgets('a partial document shows the partial banner', (tester) async {
    late String entryId;
    await tester.runAsync(
      () async => entryId = (await seedDocument(
        withImages: true,
        status: SaveStatus.partial,
      )).entryId,
    );
    await open(tester, entryId);
    expect(find.textContaining('image'), findsWidgets);
    expect(find.byType(DocumentBody), findsOneWidget);
  });

  testWidgets('a document whose files are gone is handled, not crashed', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async {
      final seeded = await seedDocument();
      entryId = seeded.entryId;
      await harness.deletePackage(seeded.relativePath);
    });

    await open(tester, entryId, until: find.textContaining('are gone'));
    expect(find.textContaining('are gone'), findsOneWidget);
  });

  testWidgets('an entry this device holds no copy of says so, not an error', (
    tester,
  ) async {
    // Nothing was ever saved here: the Entry is still listed, with its reading
    // history intact, and the reader says plainly that it is not downloaded
    // rather than reporting a failure.
    late String entryId;
    await tester.runAsync(
      () async => entryId = await harness.seedEntry(
        title: 'The Saved Page',
        ordinal: 202,
      ),
    );

    await open(tester, entryId, until: find.textContaining('not downloaded'));
    expect(find.textContaining('not downloaded'), findsOneWidget);
    expect(find.byType(DocumentBody), findsNothing);
  });

  testWidgets('a document with an unreadable body says so', (tester) async {
    late String entryId;
    await tester.runAsync(
      () async => entryId = (await seedDocument(body: '{ not json')).entryId,
    );

    await open(tester, entryId, until: find.textContaining('unreadable'));
    expect(find.textContaining('unreadable'), findsOneWidget);
  });

  testWidgets('an artifact from a newer build is refused, never mis-rendered', (
    tester,
  ) async {
    late String entryId;
    await tester.runAsync(() async {
      final seeded = await seedDocument();
      entryId = seeded.entryId;
      final manifestFile = File(
        p.join(
          harness.fileStore.resolve(seeded.relativePath),
          FileStore.manifestFileName,
        ),
      );
      manifestFile.writeAsStringSync(
        manifestFile
            .readAsStringSync()
            .replaceFirst('"schemaVersion": 2', '"schemaVersion": 9')
            .replaceFirst(
              '"artifact": "structuredDocument"',
              '"artifact": "somethingFromTheFuture"',
            ),
      );
    });

    await open(tester, entryId, until: find.textContaining('cannot open'));
    expect(find.textContaining('cannot open'), findsOneWidget);
    // And nothing tried to play, decode or parse it as one of the formats
    // this build does know.
    expect(find.byType(DocumentBody), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });
}
