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

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// An entry whose page holds more images than one probe returns.
///
/// The bridge caps how many image records a single call serialises, because a
/// probe's cost scales with that number and the scroll loop takes one per
/// step. Before this was handled, the save simply used the first sliceful:
/// a page of 850 panels became an entry of 800, written to the library as
/// `complete` with no error and no reason. The images were not filtered out
/// and not failed by a server — they were never looked at.
///
/// The real cap is 800 and lives in JavaScript; it is verified against a live
/// WKWebView in `integration_test/capture_integrity_test.dart`. Here the
/// cap is deliberately tiny so every boundary and every failure mode is cheap
/// to state.
void main() {
  late Directory root;
  late FileStore store;
  late HttpServer server;
  late String origin;

  /// The directory the last capture filled. The engine stops at *the package
  /// is staged*, so this is where its bytes are.
  late StagingHandle staging;
  var stagingSeq = 0;

  const cap = 4;

  const cfg = SaveConfig(
    scrollDelay: Duration(milliseconds: 1),
    fastScrollDelay: Duration(milliseconds: 1),
    quietPeriod: Duration.zero,
    requiredStableChecks: 1,
    maxScrollPasses: 1,
    maxAssetWait: Duration(milliseconds: 100),
    domReadyTimeout: Duration(seconds: 2),
    downloadRetries: 0,
    downloadConcurrency: 4,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('webread_enum');
    store = FileStore(root);
    stagingSeq = 0;
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);

    final png = panelPng(entry: 1, index: 1, width: 200, height: 300);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(png);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// [count] qualifying panels, all loaded, in document order.
  PageProbe panelPage(String url, int count) => PageProbe(
    url: url,
    title: 'A long entry',
    readyState: 'complete',
    documentHeight: count * 1200,
    viewportHeight: 800,
    viewportWidth: 400,
    scrollY: count * 1200 - 800,
    atBottom: true,
    images: [
      for (var i = 0; i < count; i++)
        PageImage(
          domIndex: i,
          src: '$origin/p/$i.png',
          currentSrc: '$origin/p/$i.png',
          complete: true,
          naturalWidth: 800,
          naturalHeight: 1200,
          renderedWidth: 390,
          renderedHeight: 585,
          documentTop: i * 1200,
        ),
    ],
  );

  FakeBrowser browserFor(String url, int count, {int? sliceCap = cap}) {
    final b = FakeBrowser()..setUrl(url);
    b.addPage(url, panelPage(url, count));
    b.imageSliceCap = sliceCap;
    return b;
  }

  SaveEngine engineFor(
    FakeBrowser b, {
    required SaveResultSink sink,
    SaveConfig c = cfg,
  }) => SaveEngine(
    browser: b,
    fileStore: store,
    downloader: AssetFetcher(browser: b, config: c),
    sink: sink,
    config: c,
  );

  /// A previous capture of the same address, as the seam hands one back.
  ///
  /// Only [storedAssetCount] reaches the guard below; the rest is the minimum
  /// a [CapturedEntry] needs to exist.
  CapturedEntry priorCapture(String url, int storedAssetCount) => CapturedEntry(
    id: 'prior-entry',
    title: 'A long entry',
    sourceUrl: url,
    urlKey: url,
    host: 'x.example',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    artifactFormat: 'imageSequence',
    saveStatus: 'complete',
    savedAt: DateTime(2026, 7, 1),
    detectedAssetCount: storedAssetCount,
    storedAssetCount: storedAssetCount,
  );

  Future<EntrySaveResult> save(
    FakeBrowser b, {
    CaptureMode? mode = CaptureMode.imageSequence,
    SaveConfig c = cfg,
    bool replaceExisting = false,
    CapturedEntry? existing,
  }) async {
    staging = await store.beginEntry(
      collectionId: null,
      entryId: 'entry-${++stagingSeq}',
    );
    return engineFor(
      b,
      sink: existing == null
          ? StagedPackageSink(staging)
          : _PriorCaptureSink(staging, existing),
      c: c,
    ).saveCurrentPage(
      collectionId: null,
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: mode,
      replaceExisting: replaceExisting,
    );
  }

  group('a page within one slice is unaffected', () {
    test('below the boundary saves complete', () async {
      const url = 'https://x.example/e/below';
      final result = await save(browserFor(url, cap - 1));

      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, cap - 1);
      expect(result.manifest!.statusReason, isNull);
      expect(result.storedImages, cap - 1);
    });

    test('exactly at the boundary saves complete', () async {
      const url = 'https://x.example/e/at';
      final b = browserFor(url, cap);
      final result = await save(b);

      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, cap);
      expect(
        b.sliceOffsets,
        isEmpty,
        reason: 'a page that fits in one slice must not ask for another',
      );
    });
  });

  group('a page beyond one slice is read whole', () {
    test('one above the boundary still saves every image', () async {
      const url = 'https://x.example/e/one-above';
      final b = browserFor(url, cap + 1);
      final result = await save(b);

      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, cap + 1);
      expect(result.storedImages, cap + 1);
      expect(result.manifest!.statusReason, isNull);
      expect(b.sliceOffsets, isNotEmpty);
    });

    test('substantially above the boundary saves every image', () async {
      const url = 'https://x.example/e/far-above';
      const count = cap * 5 + 3;
      final b = browserFor(url, count);
      final result = await save(b);

      expect(result.status, SaveStatus.complete);
      expect(result.detectedImages, count);
      expect(result.manifest!.detectedAssetCount, count);
      expect(result.manifest!.storedAssetCount, count);
      expect(result.manifest!.status, SaveStatus.complete);
    });

    test('the reassembled order is document order', () async {
      const url = 'https://x.example/e/order';
      const count = cap * 3 + 1;
      final result = await save(browserFor(url, count));
      final manifest = result.manifest!;

      expect(manifest.assets.map((a) => a.index), [
        for (var i = 1; i <= count; i++) i,
      ]);
      expect(
        manifest.assets.map((a) => a.sourceUrl),
        [for (var i = 0; i < count; i++) '$origin/p/$i.png'],
        reason: 'slices must reassemble in reading order, without gaps',
      );
    });

    test('overlapping slices do not duplicate images', () async {
      // A bridge that re-serves an image already seen must not inflate the
      // entry: images are keyed by their position in the page's collection.
      const url = 'https://x.example/e/overlap';
      const count = cap * 3;
      final b = browserFor(url, count);
      b.onImageSlice = (offset) {}; // slices are built fresh from the page
      final result = await save(b);

      expect(result.detectedImages, count);
      expect(
        result.manifest!.assets.map((a) => a.sourceUrl).toSet().length,
        count,
      );
    });

    test('offsets advance strictly, so enumeration terminates', () async {
      const url = 'https://x.example/e/terminate';
      final b = browserFor(url, cap * 4);
      await save(b);

      expect(b.sliceOffsets, isNotEmpty);
      for (var i = 1; i < b.sliceOffsets.length; i++) {
        expect(b.sliceOffsets[i], greaterThan(b.sliceOffsets[i - 1]));
      }
    });
  });

  group('what cannot be read is reported, never claimed', () {
    /// A ceiling low enough that the page cannot be read whole.
    const bounded = SaveConfig(
      scrollDelay: Duration(milliseconds: 1),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(milliseconds: 100),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
      downloadConcurrency: 4,
      maxEnumeratedImages: cap * 2,
    );

    test(
      'an unreadable page is partial, with a machine-readable reason',
      () async {
        const url = 'https://x.example/e/over-ceiling';
        const count = cap * 5;
        final result = await save(browserFor(url, count), c: bounded);

        expect(result.status, SaveStatus.partial);
        expect(result.manifest!.status, SaveStatus.partial);
        expect(
          result.manifest!.statusReason,
          contains('imagesTruncated:'),
          reason: 'the shortfall has to be machine-testable, not just prose',
        );
        expect(result.manifest!.statusReason, contains('/$count'));
        expect(
          result.detectedImages,
          lessThan(count),
          reason: 'it stored what it could see',
        );
        expect(result.storedImages, result.detectedImages);
      },
    );

    test('every download succeeding does not make it complete', () async {
      // The point of the whole change: nothing failed, and it is still not a
      // complete copy of the page.
      const url = 'https://x.example/e/all-downloaded';
      final result = await save(browserFor(url, cap * 5), c: bounded);

      expect(result.storedImages, result.detectedImages);
      expect(result.status, SaveStatus.partial);
    });

    test('auto-detected capture behaves exactly as manual does', () async {
      const url = 'https://x.example/e/auto';
      final auto = await save(browserFor(url, cap * 5), mode: null, c: bounded);
      expect(auto.captureMode, CaptureMode.imageSequence);
      expect(auto.status, SaveStatus.partial);
      expect(auto.manifest!.statusReason, contains('imagesTruncated:'));
    });
  });

  group('existing saved content is never traded down', () {
    test('a truncated re-save keeps the larger saved entry', () async {
      const url = 'https://x.example/e/replace';
      const bounded = SaveConfig(
        scrollDelay: Duration(milliseconds: 1),
        fastScrollDelay: Duration(milliseconds: 1),
        quietPeriod: Duration.zero,
        requiredStableChecks: 1,
        maxScrollPasses: 1,
        maxAssetWait: Duration(milliseconds: 100),
        domReadyTimeout: Duration(seconds: 2),
        downloadRetries: 0,
        maxEnumeratedImages: cap * 2,
      );

      // A good, complete save first.
      final first = await save(browserFor(url, cap * 5));
      expect(first.manifest!.status, SaveStatus.complete);
      expect(first.manifest!.storedAssetCount, cap * 5);
      final kept = staging;

      // Now the same page, read under a ceiling that cannot see it all.
      final second = await save(
        browserFor(url, cap * 5),
        c: bounded,
        replaceExisting: true,
        existing: priorCapture(url, cap * 5),
      );

      expect(second.status, SaveStatus.failed);
      expect(second.error, contains('existing save'));

      final files = Directory(
        '${kept.dir.path}/${FileStore.assetsFolderName}',
      ).listSync().whereType<File>().length;
      expect(files, cap * 5, reason: 'and so do its files on disk');
    });

    test(
      'a truncated save over a SMALLER entry is allowed, as partial',
      () async {
        // Repair must still work: more than we had is progress, and it is
        // labelled honestly.
        const url = 'https://x.example/e/repair';
        const bounded = SaveConfig(
          scrollDelay: Duration(milliseconds: 1),
          fastScrollDelay: Duration(milliseconds: 1),
          quietPeriod: Duration.zero,
          requiredStableChecks: 1,
          maxScrollPasses: 1,
          maxAssetWait: Duration(milliseconds: 100),
          domReadyTimeout: Duration(seconds: 2),
          downloadRetries: 0,
          maxEnumeratedImages: cap * 3,
        );

        final first = await save(browserFor(url, cap), c: cfg);
        expect(first.manifest!.storedAssetCount, cap);

        final second = await save(
          browserFor(url, cap * 6),
          c: bounded,
          replaceExisting: true,
          existing: priorCapture(url, cap),
        );

        expect(second.status, SaveStatus.partial);
        expect(second.manifest!.storedAssetCount, greaterThan(cap));
        expect(second.manifest!.status, SaveStatus.partial);
      },
    );
  });

  group('the enumeration is interruptible and bounded', () {
    test('cancelling during enumeration writes nothing', () async {
      const url = 'https://x.example/e/cancel';
      final b = browserFor(url, cap * 20);
      final handle = await store.beginEntry(
        collectionId: null,
        entryId: 'entry-cancel',
      );
      final engine = engineFor(b, sink: StagedPackageSink(handle));
      b.onImageSlice = (offset) {
        if (offset >= cap * 3) engine.cancel();
      };

      final result = await engine.saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );

      expect(result.status, SaveStatus.failed);
      expect(result.error, 'cancelled');
      final lib = Directory('${root.path}/library');
      expect(
        lib.listSync().whereType<Directory>().isEmpty,
        isTrue,
        reason: 'a cancelled enumeration must leave no package behind',
      );
    });

    test('a page that GROWS mid-enumeration is not called complete', () async {
      // The count is re-read from every slice, so growth after the walk has
      // passed a region is noticed rather than papered over.
      const url = 'https://x.example/e/grow';
      final b = browserFor(url, cap * 3);
      var grown = false;
      b.onImageSlice = (offset) {
        if (!grown && offset >= cap * 2) {
          grown = true;
          b.addPage(url, panelPage(url, cap * 12));
        }
      };

      final result = await save(
        b,
        c: const SaveConfig(
          scrollDelay: Duration(milliseconds: 1),
          fastScrollDelay: Duration(milliseconds: 1),
          quietPeriod: Duration.zero,
          requiredStableChecks: 1,
          maxScrollPasses: 1,
          maxAssetWait: Duration(milliseconds: 100),
          domReadyTimeout: Duration(seconds: 2),
          downloadRetries: 0,
          maxEnumeratedImages: cap * 4,
        ),
      );

      expect(result.status, SaveStatus.partial);
      expect(result.manifest!.statusReason, contains('imagesTruncated:'));
      expect(
        result.manifest!.statusReason,
        contains('/${cap * 12}'),
        reason: 'the reason names the population the page ENDED with',
      );
    });

    test('a page that SHRINKS mid-enumeration still terminates', () async {
      const url = 'https://x.example/e/shrink';
      final b = browserFor(url, cap * 6);
      var shrunk = false;
      b.onImageSlice = (offset) {
        if (!shrunk && offset >= cap * 2) {
          shrunk = true;
          b.addPage(url, panelPage(url, cap));
        }
      };

      final result = await save(b);

      // Whatever it settled on, it stopped and reported an honest count.
      expect(result.status, isNot(SaveStatus.failed));
      expect(b.sliceOffsets.length, lessThan(20));
    });

    test('the save deadline stops enumeration honestly', () async {
      const url = 'https://x.example/e/deadline';
      const shortDeadline = SaveConfig(
        scrollDelay: Duration(milliseconds: 1),
        fastScrollDelay: Duration(milliseconds: 1),
        quietPeriod: Duration.zero,
        requiredStableChecks: 1,
        maxScrollPasses: 1,
        maxAssetWait: Duration(milliseconds: 50),
        domReadyTimeout: Duration(seconds: 2),
        downloadRetries: 0,
        maxSaveDuration: Duration(milliseconds: 250),
      );
      final b = browserFor(url, cap * 40);
      b.onImageSlice = (_) => sleep(const Duration(milliseconds: 20));

      final result = await save(b, c: shortDeadline);

      // Whatever it managed, it did not call it complete.
      expect(result.status, isNot(SaveStatus.complete));
      if (result.manifest != null) {
        expect(result.manifest!.statusReason, contains('imagesTruncated:'));
      }
    });
  });

  group('text capture is not hostage to unrelated images', () {
    test(
      'prose saves completely with far more images than one slice',
      () async {
        const url = 'https://x.example/text/1';
        final b = FakeBrowser()..setUrl(url);
        b.imageSliceCap = cap;
        b.addPage(
          url,
          PageProbe(
            url: url,
            title: 'A readable page',
            readyState: 'complete',
            documentHeight: 3000,
            viewportHeight: 800,
            viewportWidth: 400,
            atBottom: true,
            content: const PageContentSignals(
              textLength: 4200,
              paragraphCount: 12,
              headingCount: 2,
              hasArticleElement: true,
            ),
            images: [
              for (var i = 0; i < cap * 9; i++)
                PageImage(
                  domIndex: i,
                  src: '$origin/thumb/$i.png',
                  currentSrc: '$origin/thumb/$i.png',
                  complete: true,
                  naturalWidth: 60,
                  naturalHeight: 60,
                  renderedWidth: 60,
                  renderedHeight: 60,
                  documentTop: i * 10,
                ),
            ],
          ),
        );
        b.addDocument(
          url,
          RawDocument(
            title: 'A readable page',
            regionBasis: 'article element',
            blocks: [
              const RawDocumentBlock(
                kind: 'heading',
                text: 'A readable page',
                level: 1,
              ),
              for (var i = 0; i < 6; i++)
                RawDocumentBlock(
                  kind: 'paragraph',
                  text: List.filled(
                    8,
                    'The quick brown fox jumps over the lazy dog. ',
                  ).join(),
                ),
            ],
          ),
        );

        final result = await save(b, mode: CaptureMode.textOnly);

        expect(result.status, SaveStatus.complete);
        expect(result.captureMode, CaptureMode.textOnly);
        expect(
          b.sliceOffsets,
          isEmpty,
          reason: 'a text save has no reason to enumerate the page\'s images',
        );
      },
    );
  });
}

/// A [StagedPackageSink] that answers the re-save lookup with a capture that
/// already exists.
///
/// The engine's "never trade a good copy for a shorter one" guard reads
/// exactly one thing off the seam — how much the previous capture of this
/// address holds — and there is no library left in this lane to hold it. This
/// supplies that one answer and nothing else: the package still stays staged.
class _PriorCaptureSink extends StagedPackageSink {
  _PriorCaptureSink(super.staging, this.existing);

  final CapturedEntry existing;

  @override
  Future<CapturedEntry?> findExistingEntry(String urlKey) async => existing;
}
