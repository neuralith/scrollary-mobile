// Capture integrity against a real WKWebView.
//
//   flutter test integration_test/capture_integrity_test.dart -d <simulator-id>
//
// Three properties that only a real browser can establish, because all three
// come from behaviour the scripted browser cannot model:
//
//  1. the bridge's per-call image cap, and a page read whole across slices;
//  2. image coordinates when an inner element is the active scroller;
//  3. `HTMLImageElement.complete` across the lazy/broken/loaded shapes.
//
// The fixture is served in-process, as in every other integration suite.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/image_candidates.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import '../tool/fixture/fixture_site.dart';

late String kFixtureBase;
final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

/// The bridge's per-call image cap. Not configurable from Dart — this suite
/// pins it, so a change to the JavaScript cannot pass unnoticed.
const int kProbeImageCap = 800;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BrowserController browser;
  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    kFixtureBase = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      try {
        await for (final req in server) {
          try {
            await handleFixtureRequest(req);
          } catch (_) {
            /* client went away */
          }
        }
      } catch (_) {
        /* server closed */
      }
    }());
  });
  tearDownAll(() => server.close(force: true));

  Future<void> boot(WidgetTester tester) async {
    db = AppDatabase(name: 'it_integrity_$kRunStamp');
    final fileStore = await FileStore.open(
      folderName: 'webread_it_integrity_$kRunStamp',
    );
    browser = BrowserController();
    final run = SaveRunController(
      browser: browser,
      db: db,
      fileStore: fileStore,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            AppServices(
              db: db,
              fileStore: fileStore,
              browser: browser,
              saveRun: run,
            ),
          ),
        ],
        child: const WebReaderApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // The shell boots on the Library tab, and a WKWebView that has never been
    // painted reports zero layout metrics — which collapses any fixture whose
    // shape depends on layout.
    await tester.tap(
      find.byKey(const ValueKey('navTab-Browser')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 800));
  }

  Future<void> settle(WidgetTester tester, {int ticks = 25}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  tearDown(() async => db.close());

  // ======================================================= enumeration
  group('image enumeration', () {
    testWidgets('one call stops at the cap and says so', (tester) async {
      await boot(tester);

      for (final (dom, expectReturned, expectTruncated) in [
        (kProbeImageCap - 1, kProbeImageCap - 1, false),
        (kProbeImageCap, kProbeImageCap, false),
        (kProbeImageCap + 1, kProbeImageCap, true),
      ]) {
        await browser.loadAndWait('$kFixtureBase/wide/$dom');
        await settle(tester, ticks: 18);
        final probe = await browser.probe(withSignals: false);

        expect(probe.images.length, expectReturned, reason: 'dom=$dom');
        expect(probe.imagesTruncated, expectTruncated, reason: 'dom=$dom');
        expect(
          probe.imageCount,
          dom,
          reason: 'the page always reports its whole population',
        );
      }
    });

    testWidgets('slices reassemble the page whole, in order', (tester) async {
      await boot(tester);
      const dom = kProbeImageCap + 137;
      await browser.loadAndWait('$kFixtureBase/wide/$dom');
      await settle(tester, ticks: 20);

      final first = await browser.probe(withSignals: false);
      expect(first.imagesTruncated, isTrue);

      // Exactly what SaveEngine._enumerateImages does.
      final byIndex = <int, PageImage>{
        for (final i in first.images) i.domIndex: i,
      };
      var offset = first.imageOffset + first.images.length;
      var truncated = first.imagesTruncated;
      var calls = 0;
      while (truncated && calls < 10) {
        calls++;
        final slice = await browser.probeImageSlice(offset);
        expect(slice.imageOffset, offset);
        for (final i in slice.images) {
          byIndex[i.domIndex] = i;
        }
        offset = slice.imageOffset + slice.images.length;
        truncated = slice.imagesTruncated;
      }

      expect(byIndex.length, dom, reason: 'every image, exactly once');
      final indexes = byIndex.keys.toList()..sort();
      expect(indexes.first, 0);
      expect(indexes.last, dom - 1);
      expect(
        indexes,
        List.generate(dom, (i) => i),
        reason: 'contiguous: no gap and no duplicate across slices',
      );

      final qualifying = selectImageCandidates([
        for (final i in indexes) byIndex[i]!,
      ]);
      expect(
        qualifying.acceptedCount,
        dom,
        reason: 'and all of them qualify as entry content',
      );
    });
  });

  // ==================================================== inner scroller
  group('inner scroll container', () {
    testWidgets('the document scroller is unchanged', (tester) async {
      // A page whose layout cannot shift under the measurement: the lazy
      // entry fixture legitimately reflows as panels arrive, which would
      // confound "did the coordinate basis move" with "did the page move".
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/wide/40');
      await settle(tester, ticks: 20);

      final top = await browser.probe(withSignals: false);
      expect(top.scrollY, 0);
      expect(
        top.viewportHeight,
        greaterThan(0),
        reason: 'the document is the scroller here',
      );
      final firstTops = top.images.map((i) => i.documentTop).toList();

      await browser.scrollTo(1500);
      await settle(tester, ticks: 6);
      final moved = await browser.probe(withSignals: false);

      expect(moved.scrollY, greaterThan(0));
      expect(
        moved.images.map((i) => i.documentTop).toList(),
        firstTops,
        reason:
            'document-relative positions are absolute: scrolling the document '
            'must not move them',
      );
      expect(
        firstTops.first,
        lessThan(firstTops.last),
        reason: 'and they increase down the page',
      );
    });

    testWidgets('inner-scroll positions are content offsets', (tester) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/innerscroll');
      await settle(tester, ticks: 30);

      Map<String, dynamic> truthOf(PageProbe p) =>
          jsonDecode(p.title) as Map<String, dynamic>;

      // The inner element really is the active scroller.
      final at0 = await browser.probe(withSignals: false);
      final t0 = truthOf(at0);
      expect(t0['win'], 0, reason: 'the document itself does not scroll');
      expect(at0.viewportHeight, t0['ch']);
      expect(at0.documentHeight, t0['sh']);
      expect(
        t0['rectTop'],
        greaterThan(0),
        reason: 'and it sits below the top of the document',
      );
      expect(t0['bt'], greaterThan(0), reason: 'with a border');
      expect(t0['pt'], greaterThan(0), reason: 'and padding');

      for (final target in [0, 1200, 4800, 9600]) {
        await browser.scrollTo(target);
        await settle(tester, ticks: 6);
        final probe = await browser.probe(withSignals: false);
        final truth = truthOf(probe);

        expect(probe.scrollY, truth['top']);

        for (final image in probe.images) {
          final expected = int.tryParse(image.alt);
          if (expected == null) continue;
          expect(
            image.documentTop,
            expected,
            reason:
                'image #${image.domIndex} at scrollTop=${truth['top']}: '
                'reported ${image.documentTop}, expected $expected',
          );
        }
      }
    });

    testWidgets('positions are stable as the inner scroller moves', (
      tester,
    ) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/innerscroll');
      await settle(tester, ticks: 30);

      final seen = <int, List<int>>{};
      for (final target in [0, 2400, 7200, 12000]) {
        await browser.scrollTo(target);
        await settle(tester, ticks: 6);
        final probe = await browser.probe(withSignals: false);
        for (final image in probe.images) {
          (seen[image.domIndex] ??= []).add(image.documentTop);
        }
      }

      for (final entry in seen.entries) {
        expect(
          entry.value.toSet().length,
          1,
          reason:
              'panel #${entry.key} reported ${entry.value} — a content offset '
              'must not change because the viewport moved',
        );
      }
    });

    testWidgets('a passed panel is behind, and an unloaded one is ahead', (
      tester,
    ) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/innerscroll');
      await settle(tester, ticks: 30);

      await browser.scrollTo(7200);
      await settle(tester, ticks: 6);
      final probe = await browser.probe(withSignals: false);

      final behind = probe.images.where((i) => i.documentTop < probe.scrollY);
      final ahead = probe.images.where((i) => i.documentTop > probe.scrollY);
      expect(behind, isNotEmpty);
      expect(ahead, isNotEmpty);

      // The engine's own gate, at this position.
      final lookahead = probe.scrollY + probe.viewportHeight * 6.5;
      final blocking = probe.images
          .where(
            (i) =>
                couldBeContent(i) && i.isUnsettled && i.documentTop < lookahead,
          )
          .toList();
      expect(
        blocking,
        isNotEmpty,
        reason: 'unloaded panels within the lookahead must hold fast mode',
      );
      for (final i in blocking) {
        expect(
          i.documentTop,
          lessThan(lookahead),
          reason: 'and they are judged in the scroller\'s own coordinates',
        );
      }
    });

    testWidgets('bottom detection is right on an inner scroller', (
      tester,
    ) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/innerscroll');
      await settle(tester, ticks: 30);

      final mid = await browser.probe(withSignals: false);
      expect(mid.atBottom, isFalse);

      await browser.scrollTo(mid.documentHeight);
      await settle(tester, ticks: 8);
      final end = await browser.probe(withSignals: false);

      expect(end.atBottom, isTrue);
      expect(
        end.scrollY + end.viewportHeight,
        greaterThan(end.documentHeight - 16),
      );
    });

    testWidgets('light and full probes agree on traversal numbers', (
      tester,
    ) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/innerscroll');
      await settle(tester, ticks: 30);
      await browser.scrollTo(4800);
      await settle(tester, ticks: 6);

      final light = await browser.probe(withSignals: false);
      final full = await browser.probe(withLinks: true);

      expect(full.scrollY, light.scrollY);
      expect(full.viewportHeight, light.viewportHeight);
      expect(full.documentHeight, light.documentHeight);
      expect(full.atBottom, light.atBottom);
      expect(
        full.images.map((i) => i.documentTop).toList(),
        light.images.map((i) => i.documentTop).toList(),
      );
    });
  });

  // ======================================================= lazy states
  group('image load state', () {
    testWidgets('every shape is classified correctly', (tester) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/lazyshapes');
      await settle(tester, ticks: 30);

      final probe = await browser.probe(withSignals: false);
      final byAlt = {for (final i in probe.images) i.alt: i};
      for (final image in probe.images) {
        debugPrint(
          'SHAPE ${image.alt}: hasSource=${image.hasSource} '
          'complete=${image.complete} nat=${image.naturalWidth} '
          '-> resolved=${image.isResolved} pending=${image.isPending} '
          'broken=${image.isBroken} unrequested=${image.isUnrequested}',
        );
      }

      expect(byAlt['loaded']!.isResolved, isTrue);
      expect(byAlt['loaded']!.isUnsettled, isFalse);

      expect(byAlt['in-flight']!.isPending, isTrue);
      expect(byAlt['in-flight']!.isBroken, isFalse);
      expect(byAlt['in-flight']!.isUnsettled, isTrue);

      expect(
        byAlt['failed']!.isBroken,
        isTrue,
        reason: 'a real 404 stays terminally broken',
      );
      expect(byAlt['failed']!.isUnsettled, isFalse);

      // The regression this suite exists for.
      expect(
        byAlt['untriggered']!.hasSource,
        isFalse,
        reason: 'no src and no srcset — nothing has been asked for',
      );
      expect(
        byAlt['untriggered']!.complete,
        isTrue,
        reason: 'yet HTML says complete is true, which is the whole trap',
      );
      expect(byAlt['untriggered']!.isBroken, isFalse);
      expect(byAlt['untriggered']!.isUnrequested, isTrue);
      expect(byAlt['untriggered']!.isUnsettled, isTrue);

      expect(byAlt['empty-src']!.isUnrequested, isTrue);
      expect(byAlt['empty-src']!.isBroken, isFalse);

      // Responsive shapes resolve through currentSrc.
      expect(byAlt['srcset']!.hasSource, isTrue);
      expect(byAlt['srcset']!.isResolved, isTrue);
      expect(byAlt['picture']!.hasSource, isTrue);
      expect(byAlt['picture']!.isResolved, isTrue);

      // Native lazy loading defers the request but still carries a source, so
      // it reads as pending rather than as never-asked.
      final nativeLazy = byAlt['native-lazy-far']!;
      expect(nativeLazy.hasSource, isTrue);
      expect(nativeLazy.isUnrequested, isFalse);
      expect(nativeLazy.isUnsettled, isTrue);
    });

    testWidgets('an untriggered panel holds the careful pace', (tester) async {
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/lazyshapes');
      await settle(tester, ticks: 30);
      final probe = await browser.probe(withSignals: false);
      final untriggered = probe.images.firstWhere(
        (i) => i.alt == 'untriggered',
      );

      expect(couldBeContent(untriggered), isTrue);
      expect(
        couldBeContent(untriggered) && untriggered.isUnsettled,
        isTrue,
        reason:
            'it qualifies as content and is not settled, so the lookahead '
            'must refuse to jump over it',
      );

      final failed = probe.images.firstWhere((i) => i.alt == 'failed');
      expect(
        couldBeContent(failed) && failed.isUnsettled,
        isFalse,
        reason: 'while a dead one is settled and must not slow anything down',
      );
    });

    testWidgets('the real lazy fixture still yields every panel', (
      tester,
    ) async {
      // The IntersectionObserver entry page: nothing about the state-model
      // change may cost it a panel.
      await boot(tester);
      await browser.loadAndWait('$kFixtureBase/entry/1');
      await settle(tester, ticks: 20);

      // Walk it the way the engine does, then look at what qualifies.
      var probe = await browser.probe(withSignals: false);
      for (var i = 0; i < 30 && !probe.atBottom; i++) {
        await browser.scrollStep((probe.viewportHeight * 0.8).round());
        await settle(tester, ticks: 4);
        probe = await browser.probe(withSignals: false);
      }
      await settle(tester, ticks: 12);
      probe = await browser.probe(withSignals: false);

      final chosen = selectImageCandidates(probe.images);
      expect(
        chosen.acceptedCount,
        kContentImagesPerEntry,
        reason: 'all $kContentImagesPerEntry lazy panels must be discovered',
      );
      expect(
        probe.images.where((i) => i.isUnrequested).length,
        0,
        reason: 'and every one of them was actually triggered',
      );
    });
  });
}
