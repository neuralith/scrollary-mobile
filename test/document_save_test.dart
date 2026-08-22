import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/document_extraction.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// Saving a page as text, end to end through the real engine.
///
/// A local HTTP server stands in for the images so the download path, the
/// magic-number verification and the atomic commit are all the production
/// ones — only the browser is faked, because there is no WebView here.
void main() {
  late Directory root;
  late FileStore store;
  late HttpServer server;
  late String origin;

  /// The directory the last capture filled. The engine stops at *the package
  /// is staged*, so this is where a committed entry's `contentPath` used to
  /// point.
  late StagingHandle staging;
  var stagingSeq = 0;

  /// A real PNG from the fixture generator: the asset fetcher verifies by
  /// magic number AND enforces a minimum byte count, so a 70-byte 1x1 image
  /// would be rejected as "not a usable image" and prove nothing.
  final pngBytes = panelPng(entry: 1, index: 1);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('webread_docsave');
    store = FileStore(root);
    stagingSeq = 0;
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      if (req.uri.path.startsWith('/broken')) {
        req.response.statusCode = 404;
      } else {
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(pngBytes);
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String filler([int n = 8]) =>
      List.filled(n, 'The quick brown fox jumps over the lazy dog. ').join();

  /// The probe and the extracted document describe the SAME page, so the
  /// probe has to report the figures the document carries. The engine now
  /// validates the requested mode against the settled probe, and a fixture
  /// where the two disagree would be testing an impossible page.
  PageProbe prosePage({
    String url = 'https://example.com/text/1',
    int inlineImages = 0,
  }) => PageProbe(
    url: url,
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
      contentRegionImageCount: inlineImages,
      contentRegionImagePixels: inlineImages * 640 * 420,
    ),
  );

  RawDocument rawDocument({List<String> imageUrls = const []}) => RawDocument(
    title: 'A readable page',
    regionBasis: 'article element',
    blocks: [
      RawDocumentBlock(kind: 'heading', text: 'A readable page', level: 1),
      RawDocumentBlock(kind: 'paragraph', text: filler()),
      for (final url in imageUrls)
        RawDocumentBlock(
          kind: 'image',
          src: url,
          alt: 'A figure',
          width: 640,
          height: 420,
        ),
      RawDocumentBlock(kind: 'paragraph', text: filler()),
      const RawDocumentBlock(kind: 'listItem', text: 'A point', level: 1),
    ],
  );

  SaveEngine engineFor(FakeBrowser browser, StagingHandle into) => SaveEngine(
    browser: browser,
    fileStore: store,
    downloader: AssetFetcher(browser: browser, config: kDefaultSaveConfig),
    sink: StagedPackageSink(into),
  );

  Future<EntrySaveResult> save(
    CaptureMode mode, {
    List<String> imageUrls = const [],
    RawDocument? document,
    bool provideDocument = true,
    String url = 'https://example.com/text/1',
  }) async {
    final browser = FakeBrowser()..setUrl(url);
    browser.addPage(url, prosePage(url: url, inlineImages: imageUrls.length));
    if (provideDocument) {
      browser.addDocument(url, document ?? rawDocument(imageUrls: imageUrls));
    }
    staging = await store.beginEntry(
      collectionId: null,
      entryId: 'entry-${++stagingSeq}',
    );
    return engineFor(browser, staging).saveCurrentPage(
      collectionId: null,
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: mode,
    );
  }

  /// The structured document the capture wrote into staging.
  StructuredDocument stagedDocument() =>
      StructuredDocument.decode(staging.documentFile.readAsStringSync());

  group('text only', () {
    test('produces a structured-document package with no assets', () async {
      final result = await save(CaptureMode.textOnly);

      expect(result.status, SaveStatus.complete);
      expect(result.captureMode, CaptureMode.textOnly);
      expect(result.manifest!.artifact, ArtifactFormat.structuredDocument);
      expect(result.manifest!.captureMode, 'textOnly');
      expect(result.manifest!.document, isNotNull);
      expect(result.manifest!.assets, isEmpty);

      final document = stagedDocument();
      expect(document.blockCount, 4);
      expect(document.textLength, greaterThan(0));
      expect(
        Directory(
          '${staging.dir.path}/${FileStore.assetsFolderName}',
        ).listSync(),
        isEmpty,
      );
    });

    test('does not download images even when the page has them', () async {
      final result = await save(
        CaptureMode.textOnly,
        imageUrls: ['$origin/a.png', '$origin/b.png'],
      );
      expect(result.storedImages, 0);
      expect(result.detectedImages, 0);
      final document = stagedDocument();
      expect(document.blocks.any((b) => b.isImage), isFalse);
    });

    test('fewer than three images is not a failure for a text save', () async {
      // The image pipeline's `minCandidates` floor must not reach this path:
      // an article with no pictures is a perfectly good text entry.
      final result = await save(CaptureMode.textOnly);
      expect(result.isUsable, isTrue);
      expect(result.extractionFailed, isFalse);
    });
  });

  group('text and images', () {
    test('stores the inline images and keeps their positions', () async {
      final result = await save(
        CaptureMode.textAndImages,
        imageUrls: ['$origin/a.png', '$origin/b.png'],
      );

      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, 2);
      expect(result.storedImages, 2);

      final manifest = result.manifest!;
      final document = stagedDocument();

      final images = document.blocks.where((b) => b.isImage).toList();
      expect(images, hasLength(2));
      // Between the two paragraphs, in order, with real files behind them.
      expect(document.blocks[1].type, DocumentBlockType.paragraph);
      expect(document.blocks[2].isImage, isTrue);
      for (final block in images) {
        final asset = manifest.assetByIndex(block.assetIndex!)!;
        expect(
          File('${staging.dir.path}/${asset.relativePath}').existsSync(),
          isTrue,
        );
      }
    });

    test('one failed image makes the entry partial, not failed', () async {
      final result = await save(
        CaptureMode.textAndImages,
        imageUrls: ['$origin/a.png', '$origin/broken.png'],
      );

      expect(result.status, SaveStatus.partial);
      expect(result.isUsable, isTrue);
      expect(result.storedImages, 1);

      expect(result.manifest!.status, SaveStatus.partial);
      final document = stagedDocument();
      final images = document.blocks.where((b) => b.isImage).toList();
      expect(images[0].assetIndex, isNotNull);
      // The failed one keeps its place and its source, with no asset.
      expect(images[1].assetIndex, isNull);
      expect(images[1].imageSourceUrl, contains('broken'));
    });

    test('every image failing still leaves a readable entry', () async {
      final result = await save(
        CaptureMode.textAndImages,
        imageUrls: ['$origin/broken.png', '$origin/broken2.png'],
      );

      expect(result.status, SaveStatus.partial);
      expect(result.isUsable, isTrue);
      final document = stagedDocument();
      expect(document.textLength, greaterThan(0));
      expect(document.storedImageBlocks, isEmpty);
      expect(document.missingImageBlocks, hasLength(2));
    });

    test('a page with no images is saved, not refused', () async {
      final result = await save(CaptureMode.textAndImages);
      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, 0);
      final document = stagedDocument();
      expect(document.blocks.any((b) => b.isImage), isFalse);
    });
  });

  group('failure is separated from image assistance', () {
    test(
      'an unreadable page reports a document failure, not an image one',
      () async {
        final result = await save(CaptureMode.textOnly, provideDocument: false);

        expect(result.status, SaveStatus.failed);
        expect(result.documentFailure, DocumentExtractionFailure.unreadable);
        // The flag that routes a run into "point at the reader area" must stay
        // off: that assistance hands back images and cannot help here.
        expect(result.extractionFailed, isFalse);
        expect(result.needsReaderAreaAssist, isFalse);
      },
    );

    test('a page of furniture reports having no readable content', () async {
      final result = await save(
        CaptureMode.textOnly,
        document: const RawDocument(
          title: 'Nothing here',
          blocks: [
            RawDocumentBlock(kind: 'paragraph', text: 'Home', inChrome: true),
            RawDocumentBlock(kind: 'paragraph', text: 'Hidden', hidden: true),
          ],
        ),
      );
      expect(
        result.documentFailure,
        DocumentExtractionFailure.noReadableContent,
      );
      expect(result.needsReaderAreaAssist, isFalse);
    });

    test('a failed text save writes nothing to disk', () async {
      final before = Directory('${root.path}/library').listSync().length;
      final result = await save(CaptureMode.textOnly, provideDocument: false);
      expect(result.status, SaveStatus.failed);
      expect(Directory('${root.path}/library').listSync().length, before);
      // And nothing staged behind: the directory the caller opened is still
      // as empty as it was handed over.
      expect(
        Directory(
          '${root.path}/tmp',
        ).listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    });
  });

  group('re-saving across formats', () {
    /// The previous capture of this page, as the seam hands it back — read
    /// most of the way through, in [artifactFormat].
    CapturedEntry readHalfWay(String artifactFormat) => CapturedEntry(
      id: 'entry-1',
      title: 'A readable page',
      sourceUrl: 'https://example.com/text/1',
      urlKey: 'https://example.com/text/1',
      host: 'example.com',
      contentKind: 'article',
      contentKindConfidence: 'high',
      contentKindIsUserSet: false,
      artifactFormat: artifactFormat,
      saveStatus: 'complete',
      savedAt: DateTime(2026, 7, 1),
      readStatus: 'inProgress',
      progressFraction: 0.6,
      progressPageIndex: 14,
      progressOffsetInPage: 0.5,
    );

    test('a format change keeps the fraction and resets the anchor', () {
      // Saved as text, then read halfway, then re-saved as an image sequence.
      final carried = carryReading(
        readHalfWay('structuredDocument'),
        ArtifactFormat.imageSequence,
      );

      expect(carried.anchorReset, isTrue);
      expect(carried.readStatus, 'inProgress');
      // The content-independent half survives...
      expect(carried.fraction, 0.6);
      // ...and the artifact-specific anchor does not, because block 14 means
      // nothing against a list of panels.
      expect(carried.pageIndex, 0);
      expect(carried.offsetInPage, 0);
    });

    test('re-saving in the same format keeps the exact anchor', () {
      final carried = carryReading(
        readHalfWay('structuredDocument'),
        ArtifactFormat.structuredDocument,
      );
      expect(carried.anchorReset, isFalse);
      expect(carried.pageIndex, 14);
      expect(carried.offsetInPage, 0.5);
    });
  });
}
