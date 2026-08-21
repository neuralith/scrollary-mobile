import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/document_reader.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

/// The reader against real document packages.
///
/// The image reader has its own suite; what is asserted here is that the
/// screen picks its path from the manifest's artifact discriminator, that a
/// text entry opens with nothing but local files, and that the reading
/// position survives a reopen even though a paragraph's offset cannot be known
/// until it has been laid out.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_docreader');
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

  Future<void> seedDocument({
    String id = 'doc1',
    bool withImages = false,
    ArtifactFormat artifact = ArtifactFormat.structuredDocument,
    SaveStatus status = SaveStatus.complete,
    int order = 1,
  }) async {
    await db.upsertCollection(
      Collection(
        id: 'collection-1',
        title: 'A collection',
        sourceUrl: 'https://example.com/c',
        host: 'example.com',
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    final document = buildDocument(withImages: withImages);
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: id,
    );
    await staging.documentFile.writeAsString(document.encode());

    final assets = <EntryAsset>[];
    if (withImages) {
      await staging
          .assetFile('001.png')
          .writeAsBytes(panelPng(entry: 1, index: 1));
      assets.add(
        const EntryAsset(
          index: 1,
          sourceUrl: 'https://example.com/a.png',
          status: AssetStatus.stored,
          relativePath: 'assets/001.png',
          mimeType: 'image/png',
          width: 800,
          height: 1200,
          dimensionsVerified: true,
        ),
      );
    }

    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: artifact,
        captureMode: withImages
            ? CaptureMode.textAndImages.name
            : CaptureMode.textOnly.name,
        document: DocumentRef(
          relativePath: FileStore.documentFileName,
          blockCount: document.blockCount,
          textLength: document.textLength,
        ),
        entryId: id,
        collectionId: 'collection-1',
        sourceUrl: 'https://example.com/text/$id',
        title: 'The Saved Page',
        savedAt: DateTime(2026, 7, 20),
        status: status,
        statusReason: status == SaveStatus.partial ? 'assetsFailed:1' : null,
        detectedAssetCount: withImages ? 2 : 0,
        storedAssetCount: assets.length,
        assets: assets,
      ),
    );

    await db.upsertEntry(
      Entry(
        id: id,
        collectionId: 'collection-1',
        title: 'The Saved Page',
        sourceUrl: 'https://example.com/text/$id',
        urlKey: 'https://example.com/text/$id',
        host: 'example.com',
        contentKind: 'article',
        contentKindConfidence: 'high',
        contentKindIsUserSet: false,
        artifactFormat: artifact.name,
        captureMode: withImages
            ? CaptureMode.textAndImages.name
            : CaptureMode.textOnly.name,
        saveStatus: status == SaveStatus.partial ? 'partial' : 'complete',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: withImages ? 2 : 0,
        storedAssetCount: assets.length,
        entryOrder: order,
        byteSize: 4096,
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  Widget harness({String entryId = 'doc1'}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fileStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(home: ReaderScreen(entryId: entryId)),
  );

  /// Real file IO cannot complete inside the fake-async zone, so the load is
  /// pumped with `runAsync` windows that let the event loop turn.
  Future<void> open(
    WidgetTester tester, {
    String id = 'doc1',
    Finder? until,
  }) async {
    final target = until ?? find.byType(DocumentBody);
    await tester.pumpWidget(harness(entryId: id));
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
    await tester.runAsync(() => seedDocument());
    await open(tester);

    expect(find.byType(DocumentBody), findsOneWidget);
    // The image reader's list is NOT what rendered.
    expect(find.byType(ListView), findsNothing);
    expect(find.text('The Saved Page'), findsWidgets);
    expect(find.textContaining('Paragraph 0.'), findsOneWidget);
  });

  testWidgets('a text-and-images entry renders its inline image', (
    tester,
  ) async {
    await tester.runAsync(() => seedDocument(withImages: true));
    await open(tester);

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
      expect(file.file.path, startsWith(root.path));
    }
  });

  testWidgets('an inline image that was never saved says so', (tester) async {
    await tester.runAsync(() => seedDocument(withImages: true));
    await open(tester);

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
    await tester.runAsync(() => seedDocument());
    await db.writeEntryReading(
      'doc1',
      EntriesCompanion(
        readStatus: const Value('inProgress'),
        progressFraction: const Value(0.5),
        // Block 12, halfway down it.
        progressPageIndex: const Value(12),
        progressOffsetInPage: const Value(0.5),
        lastReadAt: Value(DateTime(2026, 7, 26)),
        progressUpdatedAt: Value(DateTime(2026, 7, 26)),
      ),
    );

    await open(tester);
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
    await tester.runAsync(() => seedDocument());
    await open(tester);

    await tester.drag(find.byType(DocumentBody), const Offset(0, -1200));
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final entry = (await db.entryById('doc1'))!;
    expect(entry.progressUpdatedAt, isNotNull);
    expect(
      entry.progressPageIndex,
      greaterThan(0),
      reason: 'the anchor indexes a block, not a panel',
    );
    expect(entry.progressFraction, greaterThan(0));
  });

  testWidgets('a completed text entry still reads as finished', (tester) async {
    await tester.runAsync(() => seedDocument());
    await db.writeEntryReading(
      'doc1',
      EntriesCompanion(
        readStatus: const Value('completed'),
        progressFraction: const Value(1),
        completedAt: Value(DateTime(2026, 7, 26)),
        lastReadAt: Value(DateTime(2026, 7, 26)),
      ),
    );

    await open(tester);

    final entry = (await db.entryById('doc1'))!;
    expect(entry.readStatus, 'completed');
    // Re-opening a finished entry must not un-finish it.
    expect(entry.progressFraction, 1);
  });

  testWidgets('a partial document shows the partial banner', (tester) async {
    await tester.runAsync(
      () => seedDocument(withImages: true, status: SaveStatus.partial),
    );
    await open(tester);
    expect(find.textContaining('image'), findsWidgets);
    expect(find.byType(DocumentBody), findsOneWidget);
  });

  testWidgets('a document whose files are gone is handled, not crashed', (
    tester,
  ) async {
    await tester.runAsync(() => seedDocument());
    final entry = (await db.entryById('doc1'))!;
    Directory(store.resolve(entry.contentPath!)).deleteSync(recursive: true);

    await open(tester, until: find.textContaining('are gone'));
    expect(find.textContaining('are gone'), findsOneWidget);
  });

  testWidgets('an offline-removed document offers a re-save, not an error', (
    tester,
  ) async {
    await tester.runAsync(() => seedDocument());
    final entry = (await db.entryById('doc1'))!;
    Directory(store.resolve(entry.contentPath!)).deleteSync(recursive: true);
    await db.writeEntryReading(
      'doc1',
      EntriesCompanion(
        contentPath: const Value(null),
        offlineRemovedAt: Value(DateTime(2026, 7, 27)),
      ),
    );

    await open(tester, until: find.textContaining('save it again'));
    expect(find.textContaining('save it again'), findsOneWidget);
  });

  testWidgets('a document with an unreadable body says so', (tester) async {
    await tester.runAsync(() => seedDocument());
    final entry = (await db.entryById('doc1'))!;
    File(
      p.join(store.resolve(entry.contentPath!), FileStore.documentFileName),
    ).writeAsStringSync('{ not json');

    await open(tester, until: find.textContaining('unreadable'));
    expect(find.textContaining('unreadable'), findsOneWidget);
  });

  testWidgets('an artifact from a newer build is refused, never mis-rendered', (
    tester,
  ) async {
    await tester.runAsync(() => seedDocument());
    final entry = (await db.entryById('doc1'))!;
    final manifestFile = File(
      p.join(store.resolve(entry.contentPath!), FileStore.manifestFileName),
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

    await open(tester, until: find.textContaining('cannot open'));
    expect(find.textContaining('cannot open'), findsOneWidget);
    // And nothing tried to play, decode or parse it as one of the formats
    // this build does know.
    expect(find.byType(DocumentBody), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('moving to the next document entry starts a fresh scroll', (
    tester,
  ) async {
    // Two entries in one collection, so the reader offers "Next entry" and
    // the move goes through `_goTo` — the path where the old scroll
    // controller was being reused.
    await tester.runAsync(() => seedDocument(id: 'doc1', order: 1));
    await tester.runAsync(() => seedDocument(id: 'doc2', order: 2));
    // This test is about the scroll controller, so the transition is set up to
    // ask nothing: doc1 is already finished (no completion question) and the
    // collection already keeps its downloads (no cleanup question, and doc1's
    // files stay put). A modal over the reader would block the drags below.
    await tester.runAsync(() async {
      await db.writeEntryReading(
        'doc1',
        EntriesCompanion(
          readStatus: const Value('completed'),
          completedAt: Value(DateTime(2026, 7, 22)),
          progressFraction: const Value(1),
        ),
      );
      await db.setCollectionCleanupPreference(
        'collection-1',
        CollectionCleanupPreference.keep.name,
      );
    });

    await open(tester);
    await tester.drag(find.byType(DocumentBody), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scrollPosition(tester).pixels, greaterThan(0));

    // The end-of-entry button, not the bottom chrome's own "Next entry"
    // control: only the in-page one names its destination after a separator.
    final endOfEntryNext = find.textContaining('Next entry ·');
    await tester.scrollUntilVisible(
      endOfEntryNext,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
    await tester.tap(endOfEntryNext);

    // The move reloads from disk, so let the event loop turn.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (endOfEntryNext.evaluate().isEmpty &&
          find.byType(DocumentBody).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump();
    await tester.pump();

    expect(
      scrollPosition(tester).pixels,
      0,
      reason: 'an unread entry opens at the top, not where the last one was',
    );

    // …and the new entry's position is actually tracked. `_goTo` removes the
    // listener from the outgoing controller, so a reader that reused it would
    // still *write* on backgrounding — it would just write a position that
    // never moved. Asserting the timestamp alone would miss that entirely.
    await tester.drag(find.byType(DocumentBody), const Offset(0, -1200));
    await tester.pump(const Duration(milliseconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    final moved = (await db.entryById('doc2'))!;
    expect(moved.progressUpdatedAt, isNotNull);
    expect(
      moved.progressFraction,
      greaterThan(0),
      reason: 'the scroll listener must follow the reader to the new entry',
    );
    expect(moved.progressPageIndex, greaterThan(0));
  });
}
