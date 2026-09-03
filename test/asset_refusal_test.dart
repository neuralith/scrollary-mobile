import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// **A refusal is an answer, not a bad moment.**
///
/// Measured on a real reading site: the panels render at full size in the
/// WebView, and every one of them is answered with a human-verification page
/// when asked for separately. The pipeline read that as 132 ordinary download
/// failures — retried each one, made 396 requests of a host that had already
/// said no, then committed the two files that *did* arrive as a `partial`
/// entry and reported the task completed. Three things were wrong with that,
/// and each is pinned below: it asked again after being told no, it produced a
/// two-image entry that was not a copy of anything, and it never said what had
/// happened.
///
/// Nothing here reaches the network: every response comes from a fake adapter,
/// which is also what makes "how many times was this asked" assertable.
void main() {
  late Directory root;
  late FileStore store;

  final pngBytes = panelPng(entry: 1, index: 1, width: 400, height: 600);

  /// What a verification interstitial actually looks like coming back: a web
  /// page, served where a picture was asked for.
  Uint8List markup(String title) => Uint8List.fromList(
    '<!DOCTYPE html><html><head><title>$title</title></head>'
            '<body>${'.' * 4096}</body></html>'
        .codeUnits,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('webread_refusal');
    store = FileStore(root);
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  // --- what counts as a page where a picture was asked for -----------------

  group('recognising a document served instead of an image', () {
    test('the shapes a served page arrives in', () {
      expect(looksLikeMarkup(markup('Just a moment')), isTrue);
      expect(
        looksLikeMarkup(Uint8List.fromList('   \n\t<html>'.codeUnits)),
        isTrue,
        reason: 'leading whitespace is not a format',
      );
      expect(
        looksLikeMarkup(
          Uint8List.fromList([0xef, 0xbb, 0xbf, ...'<!doctype html'.codeUnits]),
        ),
        isTrue,
        reason: 'a byte-order mark is not a format either',
      );
      expect(
        looksLikeMarkup(Uint8List.fromList('<?xml version="1.0"'.codeUnits)),
        isTrue,
      );
    });

    test('real image bytes are never mistaken for a page', () {
      expect(looksLikeMarkup(pngBytes), isFalse);
      expect(
        looksLikeMarkup(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0])),
        isFalse,
      );
      expect(looksLikeMarkup(Uint8List(0)), isFalse);
    });
  });

  // --- the host is asked once ----------------------------------------------

  group('a refusal is not asked again', () {
    late _ScriptedAdapter adapter;

    AssetFetcher fetcher({
      FakeBrowser? browser,
      SaveConfig config = const SaveConfig(downloadRetries: 2),
    }) => AssetFetcher(
      browser: browser ?? FakeBrowser(),
      config: config,
      dio: Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      )..httpClientAdapter = adapter,
    );

    Future<AssetDownload> fetchOne({FakeBrowser? browser}) async {
      final staging = await store.beginEntry(
        collectionId: 'c1',
        entryId: 'e${DateTime.now().microsecondsSinceEpoch}',
      );
      return fetcher(browser: browser).download(
        entry: const EntryAsset(
          index: 1,
          sourceUrl: 'https://cdn.example.com/panel/1.jpg',
          status: AssetStatus.pending,
        ),
        staging: staging,
        refererUrl: 'https://reading.example.com/entry/1',
      );
    }

    test(
      'a 403 is asked exactly once, however many retries are configured',
      () async {
        adapter = _ScriptedAdapter(status: 403, body: markup('Just a moment'));
        final result = await fetchOne();

        expect(result.failure, AssetFailure.refused);
        expect(result.asset.status, AssetStatus.failed);
        expect(
          adapter.requested,
          hasLength(1),
          reason: 'three attempts at a settled answer is three refusals',
        );
      },
    );

    test('a rate limit is a refusal, never a wait-and-retry', () async {
      // Waiting out a rate limit is named in this project's rules as something
      // the app does not do, so 429 stops like any other refusal.
      adapter = _ScriptedAdapter(status: 429, body: Uint8List(0));
      final result = await fetchOne();

      expect(result.failure, AssetFailure.refused);
      expect(adapter.requested, hasLength(1));
    });

    test('a page served with a 200 is still a refusal', () async {
      // Not every host answers a challenge with an error status. The body is
      // what gives it away, and the magic-number check already had to look.
      adapter = _ScriptedAdapter(status: 200, body: markup('Attention'));
      final result = await fetchOne();

      expect(result.failure, AssetFailure.refused);
      expect(adapter.requested, hasLength(1));
      expect(result.asset.error, contains('web page'));
    });

    test('a server error is still retried — it might go differently', () async {
      adapter = _ScriptedAdapter(status: 503, body: Uint8List(0));
      final result = await fetchOne();

      expect(result.failure, AssetFailure.transient);
      expect(
        adapter.requested,
        hasLength(3),
        reason: 'downloadRetries: 2 means three attempts at an unsettled one',
      );
    });

    test("the page's own session is still tried after a refusal", () async {
      // The one path that can legitimately succeed where a separate client is
      // refused: it runs inside the browsing context the user established.
      adapter = _ScriptedAdapter(status: 403, body: markup('Just a moment'));
      final result = await fetchOne(browser: _InPageBrowser(pngBytes));

      expect(result.asset.status, AssetStatus.stored);
      expect(result.failure, isNull);
      expect(
        adapter.requested,
        hasLength(1),
        reason: 'the refusal short-circuits to the page, it does not retry',
      );
    });
  });

  // --- and the entry is not written ----------------------------------------

  group('a refused reading does not become an entry', () {
    late _ScriptedAdapter adapter;

    const cfg = SaveConfig(
      scrollDelay: Duration(milliseconds: 1),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(milliseconds: 50),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
      downloadConcurrency: 4,
    );

    const pageUrl = 'https://reading.example.com/entry/1';

    /// A settled page of [count] panels, all loaded and all from one host.
    FakeBrowser browserOf(int count) {
      final probe = PageProbe(
        url: pageUrl,
        title: 'An entry',
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
              src: 'https://cdn.example.com/panel/$i.jpg',
              currentSrc: 'https://cdn.example.com/panel/$i.jpg',
              complete: true,
              naturalWidth: 800,
              naturalHeight: 1200,
              renderedWidth: 390,
              renderedHeight: 585,
              documentTop: i * 1200,
            ),
        ],
      );
      return FakeBrowser()
        ..setUrl(pageUrl)
        ..addPage(pageUrl, probe);
    }

    Future<EntrySaveResult> save(FakeBrowser browser) async {
      final staging = await store.beginEntry(
        collectionId: null,
        entryId: 'refused-entry',
      );
      return SaveEngine(
        browser: browser,
        fileStore: store,
        downloader: AssetFetcher(
          browser: browser,
          config: cfg,
          dio: Dio(
            BaseOptions(
              responseType: ResponseType.bytes,
              validateStatus: (s) => s != null && s >= 200 && s < 400,
            ),
          )..httpClientAdapter = adapter,
        ),
        sink: StagedPackageSink(staging),
        config: cfg,
      ).saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );
    }

    test(
      'the whole reading refused stops, named, with nothing written',
      () async {
        adapter = _ScriptedAdapter(status: 403, body: markup('Just a moment'));
        final result = await save(browserOf(12));

        expect(result.status, SaveStatus.failed);
        expect(result.stopReason, StopReason.assetsRefusedBySource);
        expect(result.manifest, isNull);
        expect(
          result.error,
          StopReason.assetsRefusedBySource.message,
          reason: 'the user gets the sentence, not a count of failures',
        );
        // Nothing staged survives a stop.
        expect(
          Directory('${root.path}/tmp').listSync(),
          isEmpty,
          reason: 'a refused capture leaves no half-written package behind',
        );
      },
    );

    test('it stops asking once refusals have decided the outcome', () async {
      // The caller stops on `refused > stored`, and `stored` can never exceed
      // what is left — so past halfway the answer is already known and every
      // further request is one a host that said no has to answer again. The
      // real page had 134 panels; this is what kept it from making 134 of them.
      adapter = _ScriptedAdapter(status: 403, body: markup('Just a moment'));
      final result = await save(browserOf(40));

      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(
        adapter.requested.length,
        lessThan(40),
        reason:
            'asked ${adapter.requested.length} of 40 after the outcome was '
            'settled',
      );
      expect(
        adapter.requested.length,
        greaterThan(20),
        reason: 'and it must not give up before the outcome IS settled',
      );
    });

    test('the site stopping us is not the same outcome as finishing', () {
      // The column value, not a log line: `isAccessGate` is what separates
      // "the site said no" from "this is the end of the content".
      expect(StopReason.assetsRefusedBySource.isAccessGate, isTrue);
      expect(StopReason.assetsRefusedBySource.isSuccess, isFalse);
    });

    test('one dead panel among many good ones is still an entry', () async {
      // The other side of the rule. A refusal that did not prevent the reading
      // from being saved is a broken asset, and the entry is worth keeping —
      // so the comparison is against what was actually stored.
      adapter = _ScriptedAdapter(
        status: 200,
        body: pngBytes,
        refuseUrls: {'https://cdn.example.com/panel/3.jpg'},
        refusalBody: markup('Just a moment'),
      );
      final result = await save(browserOf(12));

      expect(result.status, SaveStatus.partial);
      expect(result.stopReason, isNull);
      expect(result.manifest, isNotNull);
      expect(result.manifest!.storedAssetCount, 11);
    });
  });
}

/// Answers every request the same way, unless the URL is named in
/// [refuseUrls], and records what was asked for.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({
    required this.status,
    required this.body,
    this.refuseUrls = const {},
    Uint8List? refusalBody,
  }) : refusalBody = refusalBody ?? Uint8List(0);

  final int status;
  final Uint8List body;
  final Set<String> refuseUrls;
  final Uint8List refusalBody;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    if (refuseUrls.contains(url)) {
      return ResponseBody.fromBytes(refusalBody, 403);
    }
    return ResponseBody.fromBytes(body, status);
  }

  @override
  void close({bool force = false}) {}
}

/// A Browser whose page can read the bytes — the CORS-open case, where the
/// session the user established is enough.
class _InPageBrowser extends FakeBrowser {
  _InPageBrowser(this.bytes);

  final Uint8List bytes;

  @override
  Future<InPageBytes?> fetchAsBase64(String url) async =>
      InPageBytes(base64Data: base64Encode(bytes), mimeType: 'image/png');
}
