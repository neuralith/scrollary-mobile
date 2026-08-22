/// The save engine's one seam: where a finished capture goes.
///
/// The engine's final phase used to open staging, commit the package and write
/// four V1 rows itself. It now asks a [SaveResultSink], and with the V1 library
/// retired [StagedPackageSink] is the only implementation left — so what this
/// file states is the one property that seam still has to have:
///
/// **a capture over [StagedPackageSink] commits nothing** — it fills the
/// staging directory the caller opened, writes not a byte outside `tmp/`, and
/// leaves the package there for the pipeline that owns the commit, with the
/// manifest it built on the settled page describing what it holds.
///
/// The engine is driven over the same faked browser the save suites use: what
/// is being tested is the tail, and nothing above it moved.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../helpers/fake_browser.dart';

/// Everything a save needs: a real store over a temp directory and a browser
/// serving one readable page.
class _Case {
  _Case() {
    root = Directory.systemTemp.createTempSync('scrollary_sink_seam');
    store = FileStore(root);
    Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
    Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
  }

  late final Directory root;
  late final FileStore store;

  static const url = 'https://reading.example.com/serial-alpha/part-101';

  FakeBrowser browser() {
    final browser = FakeBrowser()..setUrl(url);
    browser.addPage(url, _prosePage());
    browser.addDocument(url, _rawDocument());
    return browser;
  }

  Future<void> close() async {
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

void main() {
  group('a sink that keeps the package staged', () {
    late _Case host;

    setUp(() => host = _Case());
    tearDown(() => host.close());

    test('reaches no V1 database and commits nothing', () async {
      final staging = await host.store.beginEntry(
        collectionId: null,
        entryId: 'entry-1',
      );

      final browser = host.browser();
      final result =
          await SaveEngine(
            browser: browser,
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
