import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/scripted_browser.dart';

/// The adaptive traversal: fast over resolved regions, careful near pending
/// content, and never a full asset-wait for an avatar that will not load.
void main() {
  late AppDatabase db;
  late Directory root;

  const vp = 800;

  const config = SaveConfig(
    scrollDelay: Duration(milliseconds: 5),
    fastScrollDelay: Duration(milliseconds: 1),
    quietPeriod: Duration.zero,
    requiredStableChecks: 1,
    maxScrollIterations: 200,
    maxScrollPasses: 1,
    maxAssetWait: Duration(milliseconds: 600),
    domReadyTimeout: Duration(seconds: 2),
    downloadRetries: 0,
    cooldownBetweenEntries: Duration.zero,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_adaptive');
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  SaveEngine engine(ScriptedBrowser browser, {SaveConfig? cfg}) => SaveEngine(
    browser: browser,
    db: db,
    fileStore: FileStore(root),
    downloader: AssetFetcher(browser: browser, config: cfg ?? config),
    config: cfg ?? config,
  );

  Future<void> run(ScriptedBrowser browser, {SaveConfig? cfg}) async {
    browser.setUrl('https://x.example/guide/foo/1');
    // Downloads fail (no server) — irrelevant: the assertions are about the
    // scroll pacing recorded before the download phase.
    await engine(browser, cfg: cfg).saveCurrentPage(
      collectionId: 'collection-1',
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: CaptureMode.imageSequence,
    );
  }

  test('a fully loaded page is traversed in fast mode', () async {
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) =>
          lazyStripProbe(y: y, viewportHeight: vp, panelCount: 40),
    );
    await run(browser);

    final fastSteps = browser.scrollSteps.where((dy) => dy > (vp * 2)).length;
    expect(fastSteps, greaterThan(0), reason: 'fast mode must engage');
    expect(
      browser.scrollSteps.length,
      lessThan(40),
      reason:
          '80k px of resolved content must not take '
          '${browser.scrollSteps.length} careful steps',
    );
  });

  test('pending images nearby force the careful pace', () async {
    // Panels load only as the position approaches them (a strict lazy
    // loader). Fast steps are legal only once everything below is loaded —
    // never from a position with pending content in the lookahead.
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 10,
        loadedUpTo: y + vp * 2,
      ),
    );
    await run(browser);

    // Reconstruct the position each step started from (same clamp as the
    // scripted browser) and check no fast jump left unloaded ground.
    const docHeight = 10 * 2000;
    // The last panel (top 18000) resolves once y + 2*vp exceeds it.
    const fullyLoadedFrom = 18000 - vp * 2;
    var y = 0;
    for (final dy in browser.scrollSteps) {
      if (dy > vp) {
        expect(
          y,
          greaterThanOrEqualTo(fullyLoadedFrom),
          reason: 'fast jump from $y while the loader was still behind',
        );
      }
      y = (y + dy).clamp(0, docHeight - vp);
    }
  });

  test('stable loaded regions accelerate after consecutive probes', () async {
    // First half pending on approach, second half pre-loaded: careful early,
    // fast late.
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 30,
        loadedUpTo: y < 10000 ? y + vp * 2 : null,
      ),
    );
    await run(browser);

    final firstFastIndex = browser.scrollSteps.indexWhere((dy) => dy > vp * 2);
    expect(firstFastIndex, greaterThan(0), reason: 'starts careful');
    expect(
      browser.scrollSteps.take(firstFastIndex).every((dy) => dy <= vp),
      isTrue,
      reason: 'careful until the loaded region',
    );
  });

  test('end detection still stops at the bottom', () async {
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) =>
          lazyStripProbe(y: y, viewportHeight: vp, panelCount: 6),
    );
    await run(browser);

    // Reached the bottom (position clamped to docH - vp) and stopped well
    // inside the iteration bound.
    expect(browser.y, 6 * 2000 - vp);
    expect(browser.scrollSteps.length, lessThan(config.maxScrollIterations));
  });

  test('a permanently pending avatar does not burn the asset wait', () async {
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 5,
        extraImages: [avatarImage(1), avatarImage(2)],
      ),
    );
    const cfg = SaveConfig(
      scrollDelay: Duration(milliseconds: 5),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(seconds: 20),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
    );
    final started = DateTime.now();
    await run(browser, cfg: cfg);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 10)),
      reason: 'two unloadable avatars must not hold a 20s asset wait',
    );
  });

  // --- filter-aware traversal ---------------------------------------------
  // The three pacing gates ask `couldBeContent`, the same rule final selection
  // is built on. Before that, each carried its own looser idea of "relevant"
  // and an image the save would reject on sight could set the pace.

  test('advertisement slots do not slow an otherwise loaded entry', () async {
    Future<int> stepsFor(List<PageImage> extras) async {
      final browser = ScriptedBrowser(
        probeBuilder: (y, _) => lazyStripProbe(
          y: y,
          viewportHeight: vp,
          panelCount: 40,
          extraImages: extras,
        ),
      );
      await run(browser);
      return browser.scrollSteps.length;
    }

    final baseline = await stepsFor(const []);
    // Four 300x250 slots that never load, spread down the flow of the page so
    // each one sits inside the fast-mode lookahead in turn. This is the shape
    // that took the same 40 panels from ~4s to ~64s.
    final withAds = await stepsFor([
      adSlotImage(1, documentTop: 15000),
      adSlotImage(2, documentTop: 35000),
      adSlotImage(3, documentTop: 55000),
      adSlotImage(4, documentTop: 75000),
    ]);

    expect(
      withAds,
      lessThanOrEqualTo(baseline + 2),
      reason:
          'rejected assets must not change the pace: $baseline steps clean, '
          '$withAds with four advertisement slots',
    );
  });

  test('a rejected asset does not burn the asset wait either', () async {
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 5,
        extraImages: [adSlotImage(1, documentTop: 4000)],
      ),
    );
    const cfg = SaveConfig(
      scrollDelay: Duration(milliseconds: 5),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(seconds: 20),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
    );

    final started = DateTime.now();
    await run(browser, cfg: cfg);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 10)),
      reason: 'a 300x250 slot must not hold a 20s asset wait',
    );
  });

  test('a decorative image cycling at the bottom still settles', () async {
    // Everything readable is loaded and the page is at the bottom; one
    // rejected 300x250 slot flips between loaded and loading on every probe.
    // Judged over all images, that reset the quiet timer forever and the save
    // ran to its deadline.
    final browser = ScriptedBrowser(
      probeBuilder: (y, n) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 8,
        extraImages: [adSlotImage(1, documentTop: 8000, complete: n.isEven)],
      ),
    );
    const cfg = SaveConfig(
      scrollDelay: Duration(milliseconds: 5),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration(milliseconds: 20),
      requiredStableChecks: 3,
      maxScrollIterations: 200,
      maxScrollPasses: 1,
      maxAssetWait: Duration(milliseconds: 200),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
    );

    await run(browser, cfg: cfg);

    expect(
      browser.scrollSteps.length,
      lessThan(cfg.maxScrollIterations),
      reason: 'a rotating decoration must not hold the page open',
    );
  });

  test('a newly discovered panel still resets stability', () async {
    // A ninth panel appears part-way through. The page must not have been
    // declared settled before it arrived, and traversal must follow it down.
    final browser = ScriptedBrowser(
      probeBuilder: (y, n) =>
          lazyStripProbe(y: y, viewportHeight: vp, panelCount: n < 8 ? 8 : 9),
    );
    await run(browser);

    expect(
      browser.probeCount,
      greaterThan(8),
      reason: 'traversal ended before the late panel could be seen',
    );
    expect(browser.y, 9 * 2000 - vp, reason: 'and it scrolled to the new end');
  });

  test('unmeasured lazy panels are never treated as too small', () async {
    // The harsh loader: a pending panel has a column width but no reserved
    // height at all. Nothing may fast-jump past one.
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 10,
        loadedUpTo: y + vp * 2,
        unmeasuredWhilePending: true,
      ),
    );
    await run(browser);

    const docHeight = 10 * 2000;
    const fullyLoadedFrom = 18000 - vp * 2;
    var y = 0;
    for (final dy in browser.scrollSteps) {
      if (dy > vp) {
        expect(
          y,
          greaterThanOrEqualTo(fullyLoadedFrom),
          reason: 'fast jump from $y past an unmeasured pending panel',
        );
      }
      y = (y + dy).clamp(0, docHeight - vp);
    }
  });

  test('height growth with no new images is not a settled page', () async {
    // Infinite loading that has inserted containers but not yet images. The
    // structural half of the signature is the only thing that can see this.
    final browser = ScriptedBrowser(
      probeBuilder: (y, n) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 6,
        // Grows for the first stretch of probes, then holds.
        documentHeightOverride: n < 20 ? 12000 + n * 400 : 12000 + 20 * 400,
      ),
    );
    await run(browser);

    expect(
      browser.probeCount,
      greaterThan(20),
      reason: 'declared complete while the document was still growing',
    );
    expect(browser.y, 12000 + 20 * 400 - vp, reason: 'followed it to the end');
  });

  test('traversal never asks for the expensive signal half', () async {
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) =>
          lazyStripProbe(y: y, viewportHeight: vp, panelCount: 6),
    );
    await run(browser);

    expect(
      browser.fullSignalProbes,
      1,
      reason:
          'only the settled probe needs content, media and access signals — '
          'every probe the traversal takes is light',
    );
    expect(browser.probeCount, greaterThan(8));
  });

  group('a broken panel is never quietly dropped', () {
    late HttpServer server;
    late String origin;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        if (req.uri.path.startsWith('/broken')) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType('image', 'png');
          req.response.add(panelPng(entry: 1, index: 1));
        }
        await req.response.close();
      });
    });
    tearDown(() async => server.close(force: true));

    test('it stays a candidate and the entry is partial', () async {
      // A panel that finished loading badly: `complete` is true and there is
      // no intrinsic size, so only its declared attributes size it. It is not
      // pending — nothing waits for it — but it is still content, so it is
      // fetched, fails out loud, and the entry says so.
      PageProbe pageWithBrokenPanel(int y) => PageProbe(
        url: '$origin/entry/1',
        title: 'Entry 1',
        readyState: 'complete',
        documentHeight: 12000,
        viewportHeight: vp,
        scrollY: y,
        atBottom: y + vp >= 12000 - 8,
        images: [
          for (var i = 0; i < 5; i++)
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
          PageImage(
            domIndex: 5,
            src: '$origin/broken.png',
            currentSrc: '$origin/broken.png',
            complete: true,
            naturalWidth: 0,
            naturalHeight: 0,
            attrWidth: 800,
            attrHeight: 1200,
            renderedWidth: 390,
            renderedHeight: 585,
            documentTop: 6000,
          ),
        ],
      );

      final browser = ScriptedBrowser(
        probeBuilder: (y, _) => pageWithBrokenPanel(y),
      )..setUrl('$origin/entry/1');
      Directory('${root.path}/library').createSync(recursive: true);
      Directory('${root.path}/tmp').createSync(recursive: true);

      final result = await engine(browser).saveCurrentPage(
        collectionId: null,
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );

      expect(result.status, SaveStatus.partial);
      expect(result.detectedImages, 6, reason: 'the broken panel was fetched');
      expect(result.storedImages, 5);

      final entry = await db.entryById(result.entryId);
      expect(entry!.saveStatus, 'partial');
      expect(entry.detectedAssetCount, 6);
      expect(entry.storedAssetCount, 5);
    });
  });

  test('a pending REAL panel still blocks premature completion', () async {
    // One content-sized image never resolves: the asset wait must hold for
    // it (bounded by maxAssetWait), unlike the avatar case.
    final browser = ScriptedBrowser(
      probeBuilder: (y, _) => lazyStripProbe(
        y: y,
        viewportHeight: vp,
        panelCount: 5,
        loadedUpTo: 4 * 2000, // the last panel never loads
      ),
    );
    final started = DateTime.now();
    await run(browser);
    expect(
      DateTime.now().difference(started),
      greaterThanOrEqualTo(config.maxAssetWait),
      reason: 'a pending content panel is worth waiting for',
    );
  });
}
