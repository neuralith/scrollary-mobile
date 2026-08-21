import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// Where the restricted-site policy stops: **a page is a capture source, an
/// asset is not.**
///
/// The policy exists to answer "may this app capture this page". An image `src`
/// is part of a page that has already been judged, and ordinary sites deliver
/// their pictures through CDNs owned by large commercial platforms. Testing an
/// asset's host against the list refused images on entries the user was
/// perfectly entitled to keep and marked those entries `partial` for a reason
/// that had nothing to do with them.
///
/// Nothing here touches a real commercial service: every request is answered by
/// a fake Dio adapter, which is also what makes "was this host ever requested"
/// an assertable fact.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  final pngBytes = panelPng(entry: 1, index: 1);

  /// Asset URLs on hosts the policy genuinely covers: a subdomain of a
  /// restricted domain, the apex of one, and an exact-host entry. If the policy
  /// were still applied to assets, each of these would fail.
  const restrictedSubdomainAsset = 'https://images.amazon.com/img/a.jpg';
  const restrictedApexAsset = 'https://googlevideo.com/thumbnail.jpg';
  const restrictedExactHostAsset = 'https://books.google.com/covers/1.png';

  /// Real CDNs that merely *look* related to a restricted platform. They are
  /// separate registrable domains and were never on the list — asserted below,
  /// because "it worked" for that reason would prove nothing about the change.
  const lookalikeCdn = 'https://images-na.ssl-images-amazon.com/img/a.jpg';
  const vimeoCdn = 'https://i.vimeocdn.com/image.jpg';

  const allowedPage = 'https://x.example/collection/entry-12';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_asset_policy');
    store = FileStore(root);
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Answers every request from a fixture, and records what was asked for.
  ///
  /// A fake adapter rather than a local socket, because the whole point is to
  /// exercise URLs on restricted hosts — which must never leave the machine.
  late _RecordingAdapter adapter;

  AssetFetcher fetcher({
    SaveConfig config = const SaveConfig(downloadRetries: 0),
  }) {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
    )..httpClientAdapter = adapter;
    return AssetFetcher(browser: FakeBrowser(), config: config, dio: dio);
  }

  Future<EntryAsset> fetchOne(String url, {int index = 1}) async {
    final staging = await store.beginEntry(collectionId: 'c1', entryId: 'e1');
    return fetcher().download(
      entry: EntryAsset(
        index: index,
        sourceUrl: url,
        status: AssetStatus.pending,
      ),
      staging: staging,
      refererUrl: allowedPage,
    );
  }

  setUp(() => adapter = _RecordingAdapter(pngBytes));

  // --- 1. an asset host is not a capture source ----------------------------

  group('an allowed entry fetches its images wherever they are served from', () {
    test('these three really are hosts the policy covers as pages', () {
      // The guard on the guard. Without it, the cases below would pass just as
      // happily against hosts that were never on the list, and would prove
      // nothing about the check having been removed.
      expect(isCaptureRestricted(restrictedSubdomainAsset), isTrue);
      expect(isCaptureRestricted(restrictedApexAsset), isTrue);
      expect(isCaptureRestricted(restrictedExactHostAsset), isTrue);
    });

    test('a subdomain of a restricted domain', () async {
      final asset = await fetchOne(restrictedSubdomainAsset);

      expect(asset.status, AssetStatus.stored);
      expect(asset.mimeType, 'image/png');
      expect(
        adapter.requested,
        contains(restrictedSubdomainAsset),
        reason: 'the request was made, not refused before it left',
      );
    });

    test('the apex of a restricted domain, serving an image', () async {
      expect((await fetchOne(restrictedApexAsset)).status, AssetStatus.stored);
    });

    test('a host in the exact-host list', () async {
      expect(
        (await fetchOne(restrictedExactHostAsset)).status,
        AssetStatus.stored,
      );
    });

    test('a platform CDN on its own registrable domain', () async {
      // Never on the list in the first place — these are separate domains, and
      // the policy's suffix rule is what keeps them off it.
      expect(isCaptureRestricted(lookalikeCdn), isFalse);
      expect(isCaptureRestricted(vimeoCdn), isFalse);
      expect((await fetchOne(lookalikeCdn)).status, AssetStatus.stored);
      expect((await fetchOne(vimeoCdn)).status, AssetStatus.stored);
    });

    test('an asset that redirects onto a restricted host', () async {
      // The request begins somewhere ordinary and is redirected to a
      // restricted CDN. An *asset* redirect is not a document navigation, and
      // must not end the capture.
      adapter.redirectTo = Uri.parse(restrictedSubdomainAsset);
      final asset = await fetchOne('https://cdn.x.example/img/9.jpg');

      expect(asset.status, AssetStatus.stored);
      expect(asset.mimeType, 'image/png');
    });
  });

  // --- 2. audio and video are still refused, from any host ------------------

  group('the media allow-list is untouched', () {
    /// Bytes long enough to clear the size floor, so the refusal is the
    /// magic-number check and not the length check.
    Uint8List padded(List<int> head) =>
        Uint8List.fromList([...head, ...List.filled(4096, 0)]);

    final mp4 = padded([
      0, 0, 0, 0x20, // box length
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x69, 0x73, 0x6f, 0x6d, // brand 'isom'
    ]);
    final mp3 = padded([0x49, 0x44, 0x33, 0x03, 0, 0]); // 'ID3'
    final wav = padded([
      0x52, 0x49, 0x46, 0x46, // 'RIFF'
      0, 0, 0, 0,
      0x57, 0x41, 0x56, 0x45, // 'WAVE' — deliberately not 'WEBP'
    ]);

    test('video bytes are refused from an ordinary host', () async {
      adapter = _RecordingAdapter(mp4);
      final asset = await fetchOne('https://cdn.x.example/clip.mp4');
      expect(asset.status, AssetStatus.failed);
      expect(asset.error, contains('not a recognised image format'));
    });

    test('video bytes are refused from a restricted host too', () async {
      adapter = _RecordingAdapter(mp4);
      expect((await fetchOne(restrictedApexAsset)).status, AssetStatus.failed);
    });

    test('audio bytes are refused whatever the extension claims', () async {
      adapter = _RecordingAdapter(mp3);
      expect(
        (await fetchOne('https://cdn.x.example/track.png')).status,
        AssetStatus.failed,
      );
      adapter = _RecordingAdapter(wav);
      expect(
        (await fetchOne('https://cdn.x.example/voice.jpg')).status,
        AssetStatus.failed,
      );
    });

    test('the sniffer itself still rejects media containers', () {
      expect(detectImageMime(mp4), isNull);
      expect(detectImageMime(mp3), isNull);
      expect(detectImageMime(wav), isNull);
      expect(detectImageMime(Uint8List.fromList(pngBytes)), 'image/png');
    });
  });

  // --- 3. through the real engine ------------------------------------------

  group('an allowed page with images on restricted CDNs', () {
    PageProbe imagePage(String url, List<String> imageUrls) => PageProbe(
      url: url,
      title: 'Entry 12',
      readyState: 'complete',
      documentHeight: 4000,
      viewportHeight: 800,
      scrollY: 3200,
      atBottom: true,
      images: [
        for (final (i, src) in imageUrls.indexed)
          PageImage(
            domIndex: i,
            src: src,
            currentSrc: src,
            complete: true,
            naturalWidth: 800,
            naturalHeight: 1200,
            renderedWidth: 390,
            renderedHeight: 585,
            documentTop: i * 1200,
          ),
      ],
    );

    const config = SaveConfig(
      scrollDelay: Duration.zero,
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollIterations: 2,
      maxScrollPasses: 1,
      domReadyTimeout: Duration(seconds: 2),
      maxAssetWait: Duration(seconds: 1),
      downloadRetries: 0,
    );

    test('saves complete, not partial', () async {
      const images = [
        restrictedSubdomainAsset,
        restrictedApexAsset,
        restrictedExactHostAsset,
        lookalikeCdn,
        vimeoCdn,
      ];
      final browser = FakeBrowser()..setUrl(allowedPage);
      browser.addPage(allowedPage, imagePage(allowedPage, images));

      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      )..httpClientAdapter = adapter;

      final result =
          await SaveEngine(
            browser: browser,
            db: db,
            fileStore: store,
            config: config,
            downloader: AssetFetcher(
              browser: browser,
              config: config,
              dio: dio,
            ),
          ).saveCurrentPage(
            collectionId: null,
            entryOrder: 1,
            visitedNormalized: {},
            captureMode: CaptureMode.imageSequence,
          );

      expect(result.status, SaveStatus.complete);
      expect(
        result.storedImages,
        images.length,
        reason: 'no image was dropped for the host that delivered it',
      );
      expect(result.detectedImages, images.length);
      expect(adapter.requested, containsAll(images));

      final entry = (await db.allEntries()).single;
      expect(entry.saveStatus, 'complete');
      expect(entry.saveError, isNull);
      expect(entry.storedAssetCount, images.length);
    });

    test('the page itself is still what the policy judged', () async {
      // The same engine, the same CDNs — but the *page* is restricted. It is
      // refused before a staging directory exists, so no asset is ever
      // requested. This is the property that lets the asset layer stay out of
      // the policy: the question is answered upstream, once.
      const restrictedPage = 'https://www.amazon.com/dp/B000000000';
      final browser = FakeBrowser()..setUrl(restrictedPage);
      browser.addPage(
        restrictedPage,
        imagePage(restrictedPage, const [lookalikeCdn]),
      );

      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      )..httpClientAdapter = adapter;

      final result =
          await SaveEngine(
            browser: browser,
            db: db,
            fileStore: store,
            config: config,
            downloader: AssetFetcher(
              browser: browser,
              config: config,
              dio: dio,
            ),
          ).saveCurrentPage(
            collectionId: null,
            entryOrder: 1,
            visitedNormalized: {},
            captureMode: CaptureMode.imageSequence,
          );

      expect(result.status, SaveStatus.failed);
      expect(result.nothingToSave, isTrue);
      expect(result.error, kCaptureRestrictedMessage);
      expect(
        adapter.requested,
        isEmpty,
        reason: 'a refused page never reaches the download loop',
      );
      expect(await db.allEntries(), isEmpty);
      expect(
        Directory('${root.path}/tmp').listSync(),
        isEmpty,
        reason: 'and never opens a staging directory either',
      );
    });
  });

  // --- 4. the top-level boundary is unchanged -------------------------------

  group('a restricted host used as the page source is still refused', () {
    test('the policy still covers these hosts as pages', () {
      // The same hosts that are fine to fetch an image from are still refused
      // as a page to capture. That asymmetry is the whole point.
      expect(isCaptureRestricted('https://www.amazon.com/dp/X'), isTrue);
      expect(isCaptureRestricted('https://read.amazon.com/reader'), isTrue);
      expect(isCaptureRestricted('https://youtube.com/watch?v=1'), isTrue);
      expect(isCaptureRestricted('https://tv.apple.com/show/1'), isTrue);
      expect(isCaptureRestricted('https://webtoons.com/en/1'), isTrue);
      expect(isCaptureRestricted(restrictedExactHostAsset), isTrue);
      expect(isCaptureRestricted(restrictedSubdomainAsset), isTrue);
    });

    test(
      'direct capture and enqueue of an asset host as the source is refused',
      () async {
        final browser = FakeBrowser();
        final queue = TaskQueueController(
          db: db,
          browser: browser,
          saveRun: SaveRunController(
            browser: browser,
            db: db,
            fileStore: store,
          ),
          checker: UpdateChecker(browser: browser, db: db),
          saveRunner: (_) async => const QueueOutcome.success('saved'),
          checkRunner: (_) async => const QueueOutcome.success('checked'),
        );

        // Someone points the *page* at what is normally an asset host. It is a
        // page URL here, so the policy applies exactly as anywhere else. The
        // decision follows the role the URL plays, not the file it names.
        expect(
          await queue.startDirectSave(
            startUrl: restrictedExactHostAsset,
            entryLimit: 1,
          ),
          DirectStartResult.restrictedSite,
        );
        final enqueued = await queue.enqueueSave(
          startUrl: restrictedSubdomainAsset,
          entryLimit: 1,
        );
        expect(enqueued.restricted, isTrue);
        expect(await db.pendingQueueTasks(), isEmpty);
      },
    );
  });
}

/// A Dio adapter that answers from a fixture and remembers what was asked for.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.bytes);

  final List<int> bytes;
  final List<String> requested = [];

  /// When set, the response reports having been redirected here — an *asset*
  /// redirect, which must not be treated as a document navigation.
  Uri? redirectTo;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    final to = redirectTo;
    // The full constructor rather than `fromBytes`, because only this one can
    // report a redirect chain — which is what an asset redirected onto a
    // restricted CDN actually looks like coming back out of Dio.
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      200,
      isRedirect: to != null,
      redirects: to == null ? const [] : [RedirectRecord(302, 'GET', to)],
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
