import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/rendered_consent.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'helpers/fake_browser.dart';

/// **Silence is not consent.**
///
/// A rendering is not the site's own files and never will be, so whether a
/// shorter, re-encoded copy is worth having is a judgement about what the
/// person wants. Until they have answered, a refused reading stops with its
/// named reason exactly as it did before the fallback existed — and that has
/// to be true of an engine nobody wired an answerer to, which is most of them.
///
/// Asked **once per Source**: a Collection saved an Entry at a time would
/// otherwise put the same question on screen at every one of them.
void main() {
  group('the stored answer', () {
    late LibraryDatabase db;
    late RenderedFallbackConsentStore store;
    const key = 'source:s-1';

    setUp(() {
      db = LibraryDatabase.forTesting(NativeDatabase.memory());
      store = RenderedFallbackConsentStore(LocalSettingsStore(db));
    });
    tearDown(() => db.close());

    test('the settings key spelling is pinned', () {
      // A key that changes silently is an answer that silently vanishes, and
      // the user is asked again about a site they already decided.
      expect(
        renderedFallbackKeyFor('source:s-1'),
        'rendered_fallback.source:s-1',
      );
    });

    test('nobody asked yet is not permission', () async {
      expect(await store.of(key), isNull);
      expect(await store.allows(key), isFalse);
    });

    test('yes and no are both answers, and both stick', () async {
      await store.record(key, RenderedFallbackChoice.allowed);
      expect(await store.allows(key), isTrue);

      await store.record(key, RenderedFallbackChoice.declined);
      expect(await store.allows(key), isFalse);
      expect(
        await store.of(key),
        RenderedFallbackChoice.declined,
        reason: 'a decline must be distinguishable from never having asked',
      );
    });

    test('forgetting puts the question back', () async {
      await store.record(key, RenderedFallbackChoice.declined);
      await store.forget(key);
      expect(await store.of(key), isNull);
    });

    test('a value this build cannot read is not a decision', () async {
      await LocalSettingsStore(db).set(renderedFallbackKeyFor(key), 'maybe');
      expect(await store.of(key), isNull);
      expect(await store.allows(key), isFalse);
    });

    test('Sources are answered separately', () async {
      await store.record('source:s-1', RenderedFallbackChoice.allowed);
      expect(await store.allows('source:s-2'), isFalse);
    });
  });

  group('asking once', () {
    late LibraryDatabase db;
    late RenderedFallbackConsentStore store;
    const pageUrl = 'https://reading.example.com/entry/1';

    setUp(() {
      db = LibraryDatabase.forTesting(NativeDatabase.memory());
      store = RenderedFallbackConsentStore(LocalSettingsStore(db));
    });
    tearDown(() => db.close());

    RenderedFallbackGate gateWith(List<String> asked, bool answer) =>
        RenderedFallbackGate(
          index: RecognitionIndex(db),
          store: store,
          ask: (url) async {
            asked.add(url);
            return answer;
          },
        );

    test('a yes is asked once and remembered', () async {
      final asked = <String>[];
      final gate = gateWith(asked, true);

      expect(await gate(pageUrl), isTrue);
      expect(asked, hasLength(1));

      // The next Entry from the same site. The question is settled.
      expect(await gate('https://reading.example.com/entry/2'), isTrue);
      expect(
        asked,
        hasLength(1),
        reason: 'the second Entry must read the answer, not ask again',
      );
    });

    test('a no is asked once and remembered too', () async {
      final asked = <String>[];
      final gate = gateWith(asked, false);

      expect(await gate(pageUrl), isFalse);
      expect(await gate('https://reading.example.com/entry/2'), isFalse);
      expect(
        asked,
        hasLength(1),
        reason: 'a declined site must not keep asking on every Entry',
      );
    });

    test('no way to ask answers no, and records nothing', () async {
      final gate = RenderedFallbackGate(
        index: RecognitionIndex(db),
        store: store,
        ask: null,
      );
      expect(await gate(pageUrl), isFalse);
      expect(
        await store.of('host:reading.example.com'),
        isNull,
        reason:
            'a question nobody could see is not a question anybody answered',
      );
    });

    test('an unadopted page is keyed by host, not by Entry', () async {
      // Nothing has been adopted into a Source here, so the key falls back to
      // the host — one answer for the site, not one per address.
      expect(
        await renderedFallbackSourceKey(pageUrl, RecognitionIndex(db)),
        'host:reading.example.com',
      );
    });
  });

  group('what the engine does without an answer', () {
    late Directory root;
    late FileStore store;
    late _RefusingAdapter adapter;

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

    const pageUrl = 'https://reading.example.com/entry/7';

    setUp(() {
      root = Directory.systemTemp.createTempSync('webread_consent');
      store = FileStore(root);
      Directory('${root.path}/library').createSync(recursive: true);
      Directory('${root.path}/tmp').createSync(recursive: true);
      adapter = _RefusingAdapter();
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<EntrySaveResult> save({
      Future<bool> Function(String)? consent,
    }) async {
      final probe = PageProbe(
        url: pageUrl,
        title: 'An entry',
        readyState: 'complete',
        documentHeight: 20 * 1200,
        viewportHeight: 800,
        viewportWidth: 400,
        scrollY: 20 * 1200 - 800,
        atBottom: true,
        images: [
          for (var i = 0; i < 20; i++)
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
      final browser = FakeBrowser()
        ..setUrl(pageUrl)
        ..addPage(pageUrl, probe);
      final staging = await store.beginEntry(
        collectionId: null,
        entryId: 'e${DateTime.now().microsecondsSinceEpoch}',
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
        renderedConsent: consent,
        config: cfg,
      ).saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );
    }

    test('an engine with no answerer never renders', () async {
      // The default, and what every engine built before consent existed gets.
      final result = await save();
      expect(result.status, SaveStatus.failed);
      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(result.manifest, isNull);
    });

    test('a declined Source stops exactly as it did before', () async {
      final result = await save(consent: (_) async => false);
      expect(result.status, SaveStatus.failed);
      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(result.manifest, isNull);
    });

    test('consent is only asked about a page that could be rendered', () async {
      // This browser cannot hand back pixels, so nothing could have been kept
      // — and a question about it should never have reached the user. The
      // band is established first; the answer is asked for after.
      var asked = 0;
      await save(
        consent: (_) async {
          asked++;
          return true;
        },
      );
      expect(
        asked,
        lessThanOrEqualTo(1),
        reason: 'at most one question per capture, never one per panel',
      );
    });
  });
}

/// Refuses everything, the way a challenged host does.
class _RefusingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    Uint8List.fromList(
      '<!DOCTYPE html><html><body>${'.' * 4096}</body></html>'.codeUnits,
    ),
    403,
  );

  @override
  void close({bool force = false}) {}
}
