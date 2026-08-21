/// The save engine's one seam: where a finished capture goes.
///
/// The engine's final phase used to open staging, commit the package and write
/// four V1 rows itself. It now asks a [SaveResultSink], and the default sink is
/// those same calls. Two properties, and the seam is worth nothing without
/// both:
///
/// 1. **the V1 path is the V1 path** — a save built the way every existing
///    caller builds it writes the same row, in the same order, with the same
///    values, as one built over an explicitly constructed
///    [LibrarySaveResultSink]; and
/// 2. **the V2 path touches no V1 database** — a capture over
///    [StagedPackageSink] reaches the database not once, commits nothing, and
///    leaves the package staged for the pipeline that owns the commit.
///
/// The engine is driven over the same faked browser the save suites use: what
/// is being tested is the tail, and nothing above it moved.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../helpers/fake_browser.dart';

/// An [AppDatabase] that says which of the four library calls it was asked
/// for, and then answers them for real.
///
/// Counting rather than throwing: the engine catches everything, so a database
/// that threw would be reported as a failed save and the test would be reading
/// the wrong signal.
class _RecordingDatabase extends AppDatabase {
  _RecordingDatabase() : super.forTesting(NativeDatabase.memory());

  final List<String> calls = <String>[];

  @override
  Future<Entry?> findEntryByUrlKeyAnywhere(String urlKey) {
    calls.add('findEntryByUrlKeyAnywhere');
    return super.findEntryByUrlKeyAnywhere(urlKey);
  }

  @override
  Future<void> upsertEntry(Entry entry) {
    calls.add('upsertEntry');
    return super.upsertEntry(entry);
  }

  @override
  Future<void> clearOfflineRemovedMark(String id) {
    calls.add('clearOfflineRemovedMark');
    return super.clearOfflineRemovedMark(id);
  }

  @override
  Future<void> markCollectionSaved(String id, DateTime at) {
    calls.add('markCollectionSaved');
    return super.markCollectionSaved(id, at);
  }
}

/// Everything a save needs, twice over: the two cases below have to be built
/// separately so their rows can be compared without one overwriting the other.
class _Case {
  _Case() {
    db = _RecordingDatabase();
    root = Directory.systemTemp.createTempSync('scrollary_sink_seam');
    store = FileStore(root);
    Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
    Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
  }

  late final _RecordingDatabase db;
  late final Directory root;
  late final FileStore store;

  static const url = 'https://reading.example.com/serial-alpha/part-101';

  FakeBrowser browser() {
    final browser = FakeBrowser()..setUrl(url);
    browser.addPage(url, _prosePage());
    browser.addDocument(url, _rawDocument());
    return browser;
  }

  /// A collection for the entry to join, so the collection stamp has a row to
  /// land on.
  Future<void> seedCollection() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 'collection-1',
      title: 'Fixture',
      sourceUrl: 'https://reading.example.com/serial-alpha',
      host: 'reading.example.com',
      collectionKey: '/serial-alpha',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  /// [sink] null means "built the way every existing caller builds it".
  Future<EntrySaveResult> save({SaveResultSink? sink, String? collectionId}) {
    final browser = this.browser();
    return SaveEngine(
      browser: browser,
      db: sink == null ? db : null,
      fileStore: store,
      downloader: AssetFetcher(browser: browser, config: kDefaultSaveConfig),
      sink: sink,
    ).saveCurrentPage(
      collectionId: collectionId,
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: CaptureMode.textOnly,
    );
  }

  Future<void> close() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

PageProbe _prosePage() => const PageProbe(
  url: _Case.url,
  title: 'A readable page',
  readyState: 'complete',
  documentHeight: 3000,
  viewportHeight: 800,
  viewportWidth: 400,
  atBottom: true,
  content: PageContentSignals(
    textLength: 4200,
    paragraphCount: 12,
    headingCount: 2,
    hasArticleElement: true,
  ),
);

String _filler([int n = 8]) =>
    List.filled(n, 'The quick brown fox jumps over the lazy dog. ').join();

RawDocument _rawDocument() => RawDocument(
  title: 'A readable page',
  regionBasis: 'article element',
  blocks: [
    const RawDocumentBlock(kind: 'heading', text: 'A readable page', level: 1),
    RawDocumentBlock(kind: 'paragraph', text: _filler()),
    RawDocumentBlock(kind: 'paragraph', text: _filler()),
    const RawDocumentBlock(kind: 'listItem', text: 'A point', level: 1),
  ],
);

/// The row, minus what cannot be equal between two independent saves: the
/// minted id, the path it puts in, the moment it happened, and the byte count
/// of a manifest that carries all three.
Map<String, Object?> _comparableRow(Entry entry) {
  final json = entry.toJson()
    ..remove('id')
    ..remove('contentPath')
    ..remove('savedAt')
    // The manifest inside the package carries both of the above, and an
    // ISO-8601 stamp is not a fixed width.
    ..remove('byteSize');
  return json;
}

void main() {
  group('the default sink is the V1 library, unchanged', () {
    late _Case fromDb;
    late _Case fromSink;

    setUp(() {
      fromDb = _Case();
      fromSink = _Case();
    });

    tearDown(() async {
      await fromDb.close();
      await fromSink.close();
    });

    test('writes the row every caller has always got', () async {
      await fromDb.seedCollection();
      final result = await fromDb.save(collectionId: 'collection-1');

      expect(result.status, SaveStatus.complete);
      expect(result.manifest!.artifact, ArtifactFormat.structuredDocument);

      final entry = (await fromDb.db.entryById(result.entryId))!;
      expect(entry.artifactFormat, 'structuredDocument');
      expect(entry.captureMode, 'textOnly');
      expect(entry.saveStatus, 'complete');
      expect(entry.collectionId, 'collection-1');
      expect(entry.contentPath, isNotNull);
      expect(entry.byteSize, greaterThan(0));
      expect(entry.offlineRemovedAt, isNull);

      // The package is committed, readable, and describes itself.
      final document = await fromDb.store.readDocument(entry.contentPath!);
      expect(document!.blockCount, 4);
      final manifest = await fromDb.store.readManifest(entry.contentPath!);
      expect(manifest!.artifact, ArtifactFormat.structuredDocument);

      // …and the collection was stamped, which is the fourth call.
      final collection = await fromDb.db.collectionById('collection-1');
      expect(collection!.lastSavedAt, isNotNull);
    });

    test('asks for exactly the four library calls, in order', () async {
      await fromDb.seedCollection();
      await fromDb.save(collectionId: 'collection-1');

      expect(fromDb.db.calls, [
        'findEntryByUrlKeyAnywhere',
        'upsertEntry',
        'clearOfflineRemovedMark',
        'markCollectionSaved',
      ]);
    });

    test('a standalone entry stamps no collection', () async {
      await fromDb.save();

      expect(fromDb.db.calls, [
        'findEntryByUrlKeyAnywhere',
        'upsertEntry',
        'clearOfflineRemovedMark',
      ]);
      final entry = (await fromDb.db.entryById(
        (await fromDb.db.allEntries()).first.id,
      ))!;
      expect(entry.collectionId, isNull);
    });

    test(
      'an explicitly built LibrarySaveResultSink writes the same row',
      () async {
        await fromDb.seedCollection();
        await fromSink.seedCollection();

        final byDb = await fromDb.save(collectionId: 'collection-1');
        final bySink = await fromSink.save(
          collectionId: 'collection-1',
          sink: LibrarySaveResultSink(
            db: fromSink.db,
            fileStore: fromSink.store,
          ),
        );

        final rowA = (await fromDb.db.entryById(byDb.entryId))!;
        final rowB = (await fromSink.db.entryById(bySink.entryId))!;
        expect(
          _comparableRow(rowB),
          _comparableRow(rowA),
          reason:
              'the default sink is the explicit one: passing `db:` must build '
              'exactly the library sink, not something like it',
        );
        expect(fromSink.db.calls, fromDb.db.calls);
      },
    );

    test('the re-save lookup still finds the row across collections', () async {
      await fromDb.seedCollection();
      final first = await fromDb.save(collectionId: 'collection-1');

      // A single-page re-save resolves no collection. The lookup is by URL
      // alone, so it must still land on the row that already exists inside
      // one — not mint a second entry for the same page.
      final second = await fromDb.save();

      expect(second.entryId, first.entryId);
      final entries = await fromDb.db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.single.collectionId, 'collection-1');
    });
  });

  group('a sink that keeps the package staged', () {
    late _Case host;

    setUp(() => host = _Case());
    tearDown(() => host.close());

    test('reaches no V1 database and commits nothing', () async {
      final staging = await host.store.beginEntry(
        collectionId: null,
        entryId: 'entry-1',
      );

      // The database is handed over *as well as* the sink, so "nothing was
      // written" is a fact about the engine rather than about what it was
      // given: if any of the four calls survived the seam, this records it.
      final browser = host.browser();
      final result =
          await SaveEngine(
            browser: browser,
            db: host.db,
            fileStore: host.store,
            downloader: AssetFetcher(
              browser: browser,
              config: kDefaultSaveConfig,
            ),
            sink: StagedPackageSink(staging),
          ).saveCurrentPage(
            collectionId: null,
            entryOrder: 1,
            visitedNormalized: {},
            captureMode: CaptureMode.textOnly,
          );

      expect(result.status, SaveStatus.complete);
      expect(host.db.calls, isEmpty);
      expect(await host.db.allEntries(), isEmpty);

      // Nothing was committed: the library is empty and the package is still
      // in staging, where the pipeline's own policy gate and commit will find
      // it.
      expect(host.store.listCommittedEntryPaths(), isEmpty);
      expect(staging.dir.existsSync(), isTrue);
      expect(staging.documentFile.existsSync(), isTrue);

      // …and what it holds is described by the manifest the engine built on
      // the settled page, which is the whole point of ending here.
      final manifest = result.manifest!;
      expect(manifest.artifact, ArtifactFormat.structuredDocument);
      expect(manifest.document!.blockCount, 4);
      expect(manifest.sourceUrl, _Case.url);
    });

    test('fills the staging directory the caller opened', () async {
      final staging = await host.store.beginEntry(
        collectionId: 'collection-1',
        entryId: 'entry-1',
      );
      final browser = host.browser();
      await SaveEngine(
        browser: browser,
        fileStore: host.store,
        downloader: AssetFetcher(browser: browser, config: kDefaultSaveConfig),
        sink: StagedPackageSink(staging),
      ).saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.textOnly,
      );

      // The engine minted its own entry id and was handed a directory named
      // for the caller's. The bytes are in the caller's, because that is the
      // one the commit will look for.
      expect(staging.documentFile.existsSync(), isTrue);
      expect(
        Directory('${host.root.path}/${FileStore.tmpFolderName}').listSync(),
        hasLength(1),
      );
    });
  });
}
