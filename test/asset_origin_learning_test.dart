import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/asset_origin_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_result_sink.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// **Stop asking a question that has been answered.**
///
/// A reading whose images are refused costs one request per panel to discover
/// it — seventy on the page this was measured against. Without memory, the
/// next Entry from the same site pays it again, and so does the one after
/// that. With memory it costs one request, and that one request is also what
/// notices the day the site starts serving again.
///
/// The three properties that keep this an observation rather than a rule about
/// a website are each pinned below: one refusal is not enough, any success
/// wipes it, and a verdict goes stale on its own.
void main() {
  group('what an origin is', () {
    test('scheme, host and a non-default port; nothing else', () {
      expect(
        originOf('https://cdn.example.com/a/b.jpg?v=2#x'),
        'https://cdn.example.com',
      );
      expect(
        originOf('https://CDN.Example.COM/a.jpg'),
        'https://cdn.example.com',
      );
      expect(
        originOf('https://cdn.example.com:443/a.jpg'),
        'https://cdn.example.com',
      );
      expect(
        originOf('http://cdn.example.com:8080/a.jpg'),
        'http://cdn.example.com:8080',
      );
    });

    test('http and https are different machines to a browser', () {
      expect(
        originOf('http://x.example/a.jpg'),
        isNot(originOf('https://x.example/a.jpg')),
      );
    });

    test('anything not fetchable has no identity, so nothing matches it', () {
      expect(originOf('data:image/gif;base64,R0lGOD'), '');
      expect(originOf('about:blank'), '');
      expect(originOf('not a url'), '');
      expect(originOf(''), '');
    });
  });

  group('what a verdict is worth over time', () {
    final now = DateTime.utc(2026, 3, 1);
    AssetOriginRow row({required String verdict, DateTime? establishedAt}) =>
        AssetOriginRow(
          origin: 'https://cdn.example.com',
          verdict: verdict,
          refusedCaptures: 2,
          establishedAt: establishedAt,
          updatedAt: now,
        );

    test('nothing learned is unknown', () {
      expect(verdictOf(null, now: now), AssetOriginVerdict.unknown);
    });

    test('a fresh verdict is believed', () {
      expect(
        verdictOf(
          row(
            verdict: 'refusing',
            establishedAt: now.subtract(const Duration(days: 3)),
          ),
          now: now,
        ),
        AssetOriginVerdict.refusing,
      );
    });

    test('a stale verdict stops being believed', () {
      // Websites change. Past the freshness window the ordinary path is taken
      // in full again, and if the site still refuses, one capture re-earns it.
      expect(
        verdictOf(
          row(
            verdict: 'refusing',
            establishedAt: now.subtract(kVerdictFreshness * 2),
          ),
          now: now,
        ),
        AssetOriginVerdict.suspected,
      );
    });
  });

  group('learning, over a real database', () {
    late LibraryDatabase db;
    late AssetOriginRepository repo;
    const origin = 'https://cdn.example.com';

    setUp(() {
      db = LibraryDatabase.forTesting(NativeDatabase.memory());
      repo = AssetOriginRepository(db);
    });
    tearDown(() => db.close());

    test('one refused reading is a suspicion, never a verdict', () async {
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      expect(await repo.verdictFor(origin), AssetOriginVerdict.suspected);
    });

    test('the same reading refused twice is still one observation', () async {
      // Otherwise *Retry failed* on one page would promote a verdict by
      // itself, which is a fact about one address and not about the host.
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      expect(await repo.verdictFor(origin), AssetOriginVerdict.suspected);
      expect((await repo.row(origin))!.refusedCaptures, 1);
    });

    test('two different readings refused is a pattern', () async {
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      await repo.noteRefusedCapture(origin: origin, locationKey: 'b');
      expect(await repo.verdictFor(origin), AssetOriginVerdict.refusing);
      expect((await repo.row(origin))!.establishedAt, isNotNull);
    });

    test('a single file served wipes everything believed', () async {
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      await repo.noteRefusedCapture(origin: origin, locationKey: 'b');
      expect(await repo.verdictFor(origin), AssetOriginVerdict.refusing);

      await repo.noteServed(origin);

      expect(await repo.verdictFor(origin), AssetOriginVerdict.unknown);
      final after = (await repo.row(origin))!;
      expect(after.refusedCaptures, 0);
      expect(after.establishedAt, isNull);
      expect(
        after.lastServedAt,
        isNotNull,
        reason: 'and it remembers that it served, so the next read is cheap',
      );
    });

    test('origins are judged separately', () async {
      await repo.noteRefusedCapture(origin: origin, locationKey: 'a');
      await repo.noteRefusedCapture(origin: origin, locationKey: 'b');
      // The page's own host served its furniture perfectly on the real site.
      expect(
        await repo.verdictFor('https://reading.example.com'),
        AssetOriginVerdict.unknown,
      );
    });

    test('nothing is seeded', () async {
      expect(await repo.all(), isEmpty);
    });

    test('a verdict speaks for its siblings under the same domain', () async {
      // Measured on a real site: two readings established a verdict against
      // `s3.<site>` and the next reading's panels came from `u1.<site>`, so
      // the whole discovery cost was paid again for delivery the same site
      // had arranged.
      await repo.noteRefusedCapture(
        origin: 'https://s3.reading.example.com',
        locationKey: 'a',
      );
      await repo.noteRefusedCapture(
        origin: 'https://s3.reading.example.com',
        locationKey: 'b',
      );

      expect(
        await repo.verdictFor('https://u1.reading.example.com'),
        AssetOriginVerdict.unknown,
        reason: 'the sibling itself has no history',
      );
      expect(
        await repo.verdictUnderDomain('reading.example.com'),
        AssetOriginVerdict.refusing,
        reason: 'but its domain does',
      );
    });

    test('the widening never reaches a host outside the domain', () async {
      await repo.noteRefusedCapture(
        origin: 'https://s3.reading.example.com',
        locationKey: 'a',
      );
      await repo.noteRefusedCapture(
        origin: 'https://s3.reading.example.com',
        locationKey: 'b',
      );
      expect(
        await repo.verdictUnderDomain('other.example.org'),
        AssetOriginVerdict.unknown,
      );
      expect(
        await repo.verdictUnderDomain('example.com'),
        AssetOriginVerdict.refusing,
        reason:
            'a broader domain does contain it — which is exactly why the '
            'caller, not this method, decides what domain is safe to ask about',
      );
    });
  });

  group('what the engine does with it', () {
    late Directory root;
    late FileStore store;
    late _CountingAdapter adapter;

    final png = panelPng(entry: 1, index: 1, width: 400, height: 600);
    final challenge = Uint8List.fromList(
      '<!DOCTYPE html><html><body>${'.' * 4096}</body></html>'.codeUnits,
    );

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
    const assetOrigin = 'https://cdn.example.com';

    setUp(() {
      root = Directory.systemTemp.createTempSync('webread_origin');
      store = FileStore(root);
      Directory('${root.path}/library').createSync(recursive: true);
      Directory('${root.path}/tmp').createSync(recursive: true);
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    FakeBrowser browserOf(int count, {String assetOrigin = assetOrigin}) {
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
              src: '$assetOrigin/panel/$i.jpg',
              currentSrc: '$assetOrigin/panel/$i.jpg',
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

    Future<EntrySaveResult> save(
      FakeBrowser browser,
      AssetOriginRepository repo,
    ) async {
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
        assetOrigins: repo,
        config: cfg,
      ).saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );
    }

    test('the first refused reading still costs a full attempt', () async {
      final db = LibraryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AssetOriginRepository(db);
      adapter = _CountingAdapter(status: 403, body: challenge);

      final result = await save(browserOf(20), repo);

      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(
        adapter.count,
        greaterThan(1),
        reason: 'nothing was known yet, so the question had to be asked',
      );
      expect(await repo.verdictFor(assetOrigin), AssetOriginVerdict.suspected);
    });

    test('a known-refusing origin is asked exactly once', () async {
      final db = LibraryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AssetOriginRepository(db);
      // Two separate readings already refused: the verdict is established.
      await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'x');
      await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'y');
      adapter = _CountingAdapter(status: 403, body: challenge);

      final result = await save(browserOf(40), repo);

      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(
        adapter.count,
        1,
        reason: 'forty panels, one request — the rest was already answered',
      );
      expect(result.manifest, isNull);
    });

    test(
      'and that one request is how the site gets to change its mind',
      () async {
        final db = LibraryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = AssetOriginRepository(db);
        await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'x');
        await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'y');
        // The host is serving again.
        adapter = _CountingAdapter(status: 200, body: png);

        final result = await save(browserOf(12), repo);

        expect(result.status, SaveStatus.complete);
        expect(result.manifest!.storedAssetCount, 12);
        expect(
          adapter.count,
          12,
          reason:
              'the probe served, so the ordinary path ran — and only once '
              'for the panel the probe already fetched',
        );
        expect(
          await repo.verdictFor(assetOrigin),
          AssetOriginVerdict.unknown,
          reason: 'the newer answer wins outright',
        );
      },
    );

    test('a probe that serves does not by itself clear the verdict', () async {
      // Measured on the real site: a challenge in front of a CDN is not
      // all-or-nothing. One probe was served and nine of the next thirteen
      // were still refused. If a single served file cleared the belief, every
      // reading would pay the full discovery cost again on the next one.
      final db = LibraryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AssetOriginRepository(db);
      await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'x');
      await repo.noteRefusedCapture(origin: assetOrigin, locationKey: 'y');

      // The first asset asked for is served; everything after it is refused.
      adapter = _CountingAdapter(status: 200, body: png, refuseAfter: 1);
      final result = await save(browserOf(20), repo);

      expect(result.stopReason, StopReason.assetsRefusedBySource);
      expect(
        await repo.verdictFor(assetOrigin),
        AssetOriginVerdict.refusing,
        reason: 'one file is evidence about one request, not about the host',
      );
      expect(
        (await repo.row(assetOrigin))!.refusedCaptures,
        3,
        reason: 'and this reading counted as another refusal, not a reprieve',
      );
    });

    test(
      'a new shard of a known-refusing site is asked once, not per panel',
      () async {
        // The real shape this exists for: the site's panels moved from one of
        // its own asset hosts to another between readings.
        final db = LibraryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = AssetOriginRepository(db);
        await repo.noteRefusedCapture(
          origin: 'https://s3.reading.example.com',
          locationKey: 'x',
        );
        await repo.noteRefusedCapture(
          origin: 'https://s3.reading.example.com',
          locationKey: 'y',
        );
        adapter = _CountingAdapter(status: 403, body: challenge);

        // This reading's panels come from a sibling shard nothing knows about.
        final result = await save(
          browserOf(30, assetOrigin: 'https://u1.reading.example.com'),
          repo,
        );

        expect(result.stopReason, StopReason.assetsRefusedBySource);
        expect(
          adapter.count,
          1,
          reason:
              'thirty panels on a new shard of a site already known to refuse, '
              'and one request',
        );
      },
    );

    test(
      'a shard outside the page’s own domain is judged on its own',
      () async {
        // The safety on the widening. A host's parent label is often a public
        // suffix, so evidence may only travel inside a domain the page itself
        // belongs to — here it does not.
        final db = LibraryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = AssetOriginRepository(db);
        await repo.noteRefusedCapture(
          origin: 'https://s3.elsewhere.example.org',
          locationKey: 'x',
        );
        await repo.noteRefusedCapture(
          origin: 'https://s3.elsewhere.example.org',
          locationKey: 'y',
        );
        adapter = _CountingAdapter(status: 403, body: challenge);

        final result = await save(
          browserOf(30, assetOrigin: 'https://u1.elsewhere.example.org'),
          repo,
        );

        expect(result.stopReason, StopReason.assetsRefusedBySource);
        expect(
          adapter.count,
          greaterThan(1),
          reason:
              'the page is on reading.example.com, so nothing learned about '
              'example.org may speak for it',
        );
      },
    );

    test('an engine given no memory behaves exactly as it used to', () async {
      adapter = _CountingAdapter(status: 200, body: png);
      final staging = await store.beginEntry(
        collectionId: null,
        entryId: 'forgetful',
      );
      final browser = browserOf(8);
      final result =
          await SaveEngine(
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

      expect(result.status, SaveStatus.complete);
      expect(result.manifest!.storedAssetCount, 8);
    });
  });
}

/// Answers everything the same way and counts what was asked.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({
    required this.status,
    required this.body,
    this.refuseAfter,
  });

  final int status;
  final Uint8List body;

  /// After this many requests, everything is refused — a gate that lets some
  /// through and challenges the rest, which is what a real one does.
  final int? refuseAfter;
  int count = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    count++;
    final gate = refuseAfter;
    if (gate != null && count > gate) {
      return ResponseBody.fromBytes(
        Uint8List.fromList(
          '<!DOCTYPE html><html><body>${'.' * 4096}</body></html>'.codeUnits,
        ),
        403,
      );
    }
    return ResponseBody.fromBytes(body, status);
  }

  @override
  void close({bool force = false}) {}
}
