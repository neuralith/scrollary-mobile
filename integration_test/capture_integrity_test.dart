// Capture integrity against a real WebView.
//
//   flutter test integration_test/capture_integrity_test.dart -d <device-id>
//
// Three properties that only a real browser can establish, because all three
// come from behaviour a scripted browser cannot model:
//
//  1. the bridge's per-call image cap, and a page read whole across slices;
//  2. image coordinates when an inner element is the active scroller;
//  3. `HTMLImageElement.complete` across the lazy/broken/loaded shapes.
//
// **Unchanged by the V2 port, and that is the point.** Everything measured here
// lives in the injected bridge, `browser_controller.dart` and
// `save/image_candidates.dart` — components the port freezes verbatim
// (docs/V2_PORT_CHECKLIST.md, V2_ROADMAP.md §9). Only the app around them was
// rebuilt, so this suite boots the V2 composition and then asserts exactly what
// it asserted before. A difference here is a regression in device knowledge
// that was paid for on hardware, not a V2 design change.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/image_candidates.dart';

import 'support/v2_harness.dart';

/// The bridge's per-call image cap. Not configurable from Dart — this suite
/// pins it, so a change to the JavaScript cannot pass unnoticed.
const int kProbeImageCap = 800;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester) async {
    app = V2App(tag: 'integrity_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    // A WKWebView that has never been painted reports zero layout metrics,
    // which collapses any fixture whose shape depends on layout.
    await showBrowser(tester);
  }

  tearDown(() => app.shutdown(dumpLog: false));

  Future<void> settle(WidgetTester tester, {int ticks = 25}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  // ======================================================= enumeration
  group('image enumeration', () {
    testWidgets(
      'one call stops at the cap and says so',
      (tester) async {
        await boot(tester);

        for (final (dom, expectReturned, expectTruncated) in [
          (kProbeImageCap - 1, kProbeImageCap - 1, false),
          (kProbeImageCap, kProbeImageCap, false),
          (kProbeImageCap + 1, kProbeImageCap, true),
        ]) {
          await app.browser.loadAndWait('${fixture.base}/wide/$dom');
          await settle(tester, ticks: 18);
          final probe = await app.browser.probe(withSignals: false);

          expect(probe.images.length, expectReturned, reason: 'dom=$dom');
          expect(probe.imagesTruncated, expectTruncated, reason: 'dom=$dom');
          expect(
            probe.imageCount,
            dom,
            reason: 'the page always reports its whole population',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    testWidgets(
      'slices reassemble the page whole, in order',
      (tester) async {
        await boot(tester);
        const dom = kProbeImageCap + 137;
        await app.browser.loadAndWait('${fixture.base}/wide/$dom');
        await settle(tester, ticks: 20);

        final first = await app.browser.probe(withSignals: false);
        expect(first.imagesTruncated, isTrue);

        // Exactly what SaveEngine._enumerateImages does.
        final byIndex = <int, PageImage>{
          for (final image in first.images) image.domIndex: image,
        };
        var offset = first.imageOffset + first.images.length;
        var truncated = first.imagesTruncated;
        var calls = 0;
        while (truncated && calls < 10) {
          calls++;
          final slice = await app.browser.probeImageSlice(offset);
          expect(slice.imageOffset, offset);
          for (final image in slice.images) {
            byIndex[image.domIndex] = image;
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
          for (final index in indexes) byIndex[index]!,
        ]);
        expect(
          qualifying.acceptedCount,
          dom,
          reason: 'and all of them qualify as entry content',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });

  // ==================================================== inner scroller
  group('inner scroll container', () {
    testWidgets(
      'the document scroller is unchanged',
      (tester) async {
        // A page whose layout cannot shift under the measurement: the lazy entry
        // fixture legitimately reflows as panels arrive, which would confound
        // "did the coordinate basis move" with "did the page move".
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/wide/40');
        await settle(tester, ticks: 20);

        final top = await app.browser.probe(withSignals: false);
        expect(top.scrollY, 0);
        expect(
          top.viewportHeight,
          greaterThan(0),
          reason: 'the document is the scroller here',
        );
        final firstTops = top.images.map((i) => i.documentTop).toList();

        await app.browser.scrollTo(1500);
        await settle(tester, ticks: 6);
        final moved = await app.browser.probe(withSignals: false);

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
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'inner-scroll positions are content offsets',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/innerscroll');
        await settle(tester, ticks: 30);

        Map<String, dynamic> truthOf(PageProbe p) =>
            jsonDecode(p.title) as Map<String, dynamic>;

        // The inner element really is the active scroller.
        final at0 = await app.browser.probe(withSignals: false);
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
          await app.browser.scrollTo(target);
          await settle(tester, ticks: 6);
          final probe = await app.browser.probe(withSignals: false);
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
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    testWidgets(
      'positions are stable as the inner scroller moves',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/innerscroll');
        await settle(tester, ticks: 30);

        final seen = <int, List<int>>{};
        for (final target in [0, 2400, 7200, 12000]) {
          await app.browser.scrollTo(target);
          await settle(tester, ticks: 6);
          final probe = await app.browser.probe(withSignals: false);
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
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    testWidgets(
      'a passed panel is behind, and an unloaded one is ahead',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/innerscroll');
        await settle(tester, ticks: 30);

        await app.browser.scrollTo(7200);
        await settle(tester, ticks: 6);
        final probe = await app.browser.probe(withSignals: false);

        final behind = probe.images.where((i) => i.documentTop < probe.scrollY);
        final ahead = probe.images.where((i) => i.documentTop > probe.scrollY);
        expect(behind, isNotEmpty);
        expect(ahead, isNotEmpty);

        // The engine's own gate, at this position.
        final lookahead = probe.scrollY + probe.viewportHeight * 6.5;
        final blocking = probe.images
            .where(
              (i) =>
                  couldBeContent(i) &&
                  i.isUnsettled &&
                  i.documentTop < lookahead,
            )
            .toList();
        expect(
          blocking,
          isNotEmpty,
          reason: 'unloaded panels within the lookahead must hold fast mode',
        );
        for (final image in blocking) {
          expect(
            image.documentTop,
            lessThan(lookahead),
            reason: 'and they are judged in the scroller\'s own coordinates',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'bottom detection is right on an inner scroller',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/innerscroll');
        await settle(tester, ticks: 30);

        final mid = await app.browser.probe(withSignals: false);
        expect(mid.atBottom, isFalse);

        await app.browser.scrollTo(mid.documentHeight);
        await settle(tester, ticks: 8);
        final end = await app.browser.probe(withSignals: false);

        expect(end.atBottom, isTrue);
        expect(
          end.scrollY + end.viewportHeight,
          greaterThan(end.documentHeight - 16),
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'light and full probes agree on traversal numbers',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/innerscroll');
        await settle(tester, ticks: 30);
        await app.browser.scrollTo(4800);
        await settle(tester, ticks: 6);

        final light = await app.browser.probe(withSignals: false);
        final full = await app.browser.probe(withLinks: true);

        expect(full.scrollY, light.scrollY);
        expect(full.viewportHeight, light.viewportHeight);
        expect(full.documentHeight, light.documentHeight);
        expect(full.atBottom, light.atBottom);
        expect(
          full.images.map((i) => i.documentTop).toList(),
          light.images.map((i) => i.documentTop).toList(),
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // ======================================================= lazy states
  group('image load state', () {
    testWidgets(
      'every shape is classified correctly',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/lazyshapes');
        await settle(tester, ticks: 30);

        final probe = await app.browser.probe(withSignals: false);
        final byAlt = {for (final image in probe.images) image.alt: image};
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
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'an untriggered panel holds the careful pace',
      (tester) async {
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/lazyshapes');
        await settle(tester, ticks: 30);
        final probe = await app.browser.probe(withSignals: false);
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
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'panels that reserve a small box are read as a run, not as icons',
      (tester) async {
        // The shape a per-image size test cannot read, on a real browser:
        // until a panel loads it reports only the box its stylesheet reserved
        // (`min-width`/`min-height`), and 50x50 is an icon by any per-image
        // measure. What makes it content is that it is one of a stacked run.
        await boot(tester);
        await app.browser.loadAndWait('${fixture.base}/minbox/20');
        await settle(tester, ticks: 10);

        final atRest = await app.browser.probe(withSignals: false);
        final unloaded = atRest.images
            .where((i) => i.naturalWidth == 0 && i.renderedWidth > 0)
            .toList();
        expect(
          unloaded,
          isNotEmpty,
          reason: 'the fixture must arrive with panels still to come',
        );

        // Judged one at a time, the placeholders are icons…
        final aloneRelevant = unloaded.where(couldBeContent).length;
        // …and judged as a page, the stacked ones are content on its way.
        final asPage = contentRelevanceFor(atRest.images);
        final pageRelevant = unloaded.where(asPage).length;
        expect(
          pageRelevant,
          greaterThan(aloneRelevant),
          reason:
              'the run rule is what keeps the traversal waiting for these; '
              'alone=$aloneRelevant page=$pageRelevant',
        );

        // Now walk it the way the engine does.
        var probe = atRest;
        for (var i = 0; i < 40 && !probe.atBottom; i++) {
          await app.browser.scrollStep((probe.viewportHeight * 0.8).round());
          await settle(tester, ticks: 4);
          probe = await app.browser.probe(withSignals: false);
        }
        await settle(tester, ticks: 15);
        probe = await app.browser.probe(withSignals: false);

        final chosen = selectImageCandidates(probe.images);
        final urls = chosen.accepted.map((c) => c.url).toList();
        expect(
          urls,
          [
            for (var i = 1; i <= 20; i++)
              '${fixture.base}$kMinBoxPanelPath$i.png?w=400&h=600',
          ],
          reason: 'every panel, in reading order, and nothing else',
        );
        // The furniture reserved boxes too, and reserved them in vain: a rail
        // of slots down the page, and a grid of thumbnails sharing one
        // vertical position at the foot of it.
        expect(urls.any((u) => u.contains('/ads/')), isFalse);
        expect(urls.any((u) => u.contains('/related/')), isFalse);
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    testWidgets(
      'the real lazy fixture still yields every panel',
      (tester) async {
        // The IntersectionObserver entry page: nothing about the state-model
        // change may cost it a panel.
        await boot(tester);
        await app.browser.loadAndWait(fixture.entry(1));
        await settle(tester, ticks: 20);

        // Walk it the way the engine does, then look at what qualifies.
        var probe = await app.browser.probe(withSignals: false);
        for (var i = 0; i < 30 && !probe.atBottom; i++) {
          await app.browser.scrollStep((probe.viewportHeight * 0.8).round());
          await settle(tester, ticks: 4);
          probe = await app.browser.probe(withSignals: false);
        }
        await settle(tester, ticks: 12);
        probe = await app.browser.probe(withSignals: false);

        final chosen = selectImageCandidates(probe.images);
        expect(
          chosen.acceptedCount,
          kFixtureImagesPerEntry,
          reason: 'all $kFixtureImagesPerEntry lazy panels must be discovered',
        );
        expect(
          probe.images.where((i) => i.isUnrequested).length,
          0,
          reason: 'and every one of them was actually triggered',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}
