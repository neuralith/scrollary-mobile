/// User assist on the V2 capture path: the tap that teaches the app where an
/// entry's images are, and what happens to the rule afterwards.
///
/// The properties, in the order they matter:
///
/// 1. **A rule is only ever written from an explicit tap.** No capture result,
///    failed or otherwise, creates one on its own, and the table stays empty
///    until a person points at something.
/// 2. **The seam carries the judgement, it does not re-make it.** Whether
///    pointing at the reading area could help is decided where the page was
///    measured; `page_capture_source.dart` maps it and `entry_capture.dart`
///    passes the rules through untouched.
/// 3. **The hold is answered, then the capture is run again with what was
///    taught** — and the rule's counters move with the outcome.
/// 4. **The rule lands in the V2 library's `page_hints` table**, which is what
///    Settings reads.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../helpers/fake_browser.dart';
import 'support/capture_harness.dart';

/// What the JS picker reports for a tapped reading area.
const _readerContainer = SelectedElement(
  mode: 'reader',
  tag: 'div',
  classes: 'reading-content',
  selector: 'div.reading-content',
  imageCount: 12,
  minImageEdge: 800,
  imageSelector: 'img',
);

const _pageUrl = 'https://reading.example.com/serial-alpha/part-101';

void main() {
  late CaptureHarness h;
  late FakeBrowser browser;
  late PageHintRepository hints;
  late V2AssistController assist;

  setUp(() {
    h = CaptureHarness();
    browser = FakeBrowser();
    hints = PageHintRepository.forLibrary(h.db);
    assist = V2AssistController(browser: browser, hints: hints);
  });
  tearDown(() async {
    assist.dispose();
    await h.close();
  });

  Future<List<UserPageHint>> storedHints() => hints.all();

  group('the seam reports what the page was measured to need', () {
    test('an extraction failure surfaces as needing the reading area', () {
      final outcome = outcomeOf(
        const EntrySaveResult(
          status: SaveStatus.failed,
          entryId: 'e1',
          error: 'Only 1 content images found (need 3)',
          extractionFailed: true,
          pageUrl: _pageUrl,
        ),
        requestedUrl: _pageUrl,
      );

      expect(outcome.isCaptured, isFalse);
      expect(outcome.needsReaderAreaAssist, isTrue);
    });

    test('a saved rule that stopped matching surfaces the same way', () {
      final outcome = outcomeOf(
        const EntrySaveResult(
          status: SaveStatus.failed,
          entryId: 'e1',
          error: 'saved reader-area rule no longer matches',
          readerHintFailed: true,
          pageUrl: _pageUrl,
        ),
        requestedUrl: _pageUrl,
      );

      expect(outcome.needsReaderAreaAssist, isTrue);
    });

    test('an ordinary failure does not ask for the reading area', () {
      final outcome = outcomeOf(
        const EntrySaveResult(
          status: SaveStatus.failed,
          entryId: 'e1',
          error: 'the surface never rendered',
          pageUrl: _pageUrl,
        ),
        requestedUrl: _pageUrl,
      );

      expect(outcome.needsReaderAreaAssist, isFalse);
    });

    test('a refusal is the app\'s own, and never an invitation to tap', () {
      const outcome = PageCaptureOutcome.refused(pageUrl: _pageUrl);

      expect(outcome.stopReason, StopReason.captureRestrictedForSite);
      expect(outcome.needsReaderAreaAssist, isFalse);
    });

    test('a captured page needs nothing', () {
      const outcome = PageCaptureOutcome.captured(
        pageUrl: _pageUrl,
        title: 'Part 101',
        artifact: ArtifactFormat.imageSequence,
        captureMode: CaptureMode.imageSequence,
        status: SaveStatus.complete,
        detectedAssetCount: 2,
        storedAssetCount: 2,
        assets: [],
      );

      expect(outcome.needsReaderAreaAssist, isFalse);
    });
  });

  group('the pipeline passes rules through untouched', () {
    test(
      'both rules reach the source exactly as they were handed in',
      () async {
        final seeded = await h.repos.seedLibrary();
        final readerHint = await hints.createReaderAreaHint(
          element: _readerContainer,
          sourceUrl: _pageUrl,
        );
        final source = FakePageCaptureSource.images();

        await h
            .captureWith(source)
            .capture(
              entryId: seeded.entry.id,
              locationUrl: _pageUrl,
              captureMode: CaptureMode.imageSequence,
              readerHint: readerHint,
            );

        expect(source.readerHints, [same(readerHint)]);
        expect(source.nextHints, [isNull]);
      },
    );

    test('no rule is invented for a capture that was handed none', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.images();

      await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationUrl: _pageUrl,
            captureMode: null,
          );

      expect(source.readerHints, [isNull]);
      expect(await storedHints(), isEmpty);
    });

    test('a page that needs the reading area says so on the result', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.needingReaderAreaAssist();

      final result = await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationUrl: _pageUrl,
            captureMode: null,
          );

      expect(result.status, EntryCaptureStatus.failed);
      expect(result.needsReaderAreaAssist, isTrue);
      expect(
        h.stagingLeftovers(),
        isEmpty,
        reason: 'a failure still takes its staging tree with it',
      );
    });
  });

  group('the hold, and what the tap teaches', () {
    /// Run the assisted capture and answer the hold it opens with [answer].
    Future<EntryCaptureResult> captureAnswering(
      FakePageCaptureSource source,
      String entryId,
      Future<void> Function() answer, {
      CaptureMode? captureMode,
    }) async {
      final pending = v2CaptureWithAssist(
        capture: h.captureWith(source),
        assist: assist,
        entryId: entryId,
        locationUrl: _pageUrl,
        captureMode: captureMode,
      );
      // The hold is opened from inside the capture; let it get there.
      while (assist.pendingSelection == null) {
        await Future<void>.delayed(Duration.zero);
      }
      await answer();
      return pending;
    }

    test(
      'a tap writes one rule, and the capture is run again with it',
      () async {
        final seeded = await h.repos.seedLibrary();
        final source = FakePageCaptureSource.needingReaderAreaAssist();

        final result = await captureAnswering(
          source,
          seeded.entry.id,
          () => assist.submitSelection(_readerContainer),
        );

        expect(result.isCaptured, isTrue);

        final rules = await storedHints();
        expect(rules, hasLength(1), reason: 'one tap, one rule');
        expect(rules.single.kind, HintKind.readerArea);
        expect(
          rules.single.scope,
          HintScope.collection,
          reason: 'the narrowest scope is the default',
        );
        expect(rules.single.host, 'reading.example.com');

        expect(source.readerHints, hasLength(2));
        expect(source.readerHints.first, isNull);
        expect(
          source.readerHints.last?.id,
          rules.single.id,
          reason: 'the retry is the one that carries what was taught',
        );
        expect(
          source.modes.last,
          CaptureMode.imageSequence,
          reason: 'pointing at a container of images can only be an image save',
        );
      },
    );

    test(
      'the hold is closed and the page taken out of selection mode',
      () async {
        final seeded = await h.repos.seedLibrary();
        await captureAnswering(
          FakePageCaptureSource.needingReaderAreaAssist(),
          seeded.entry.id,
          () => assist.submitSelection(_readerContainer),
        );

        expect(assist.pendingSelection, isNull);
      },
    );

    test('cancelling teaches nothing and keeps the failure it had', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.needingReaderAreaAssist();

      final result = await captureAnswering(
        source,
        seeded.entry.id,
        assist.cancelSelection,
      );

      expect(result.status, EntryCaptureStatus.failed);
      expect(await storedHints(), isEmpty);
      expect(
        source.readerHints,
        hasLength(1),
        reason: 'nothing was taught, so there is nothing new to try',
      );
    });

    test('retry-auto runs detection again with no rule in the way', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.needingReaderAreaAssist();

      final result = await captureAnswering(
        source,
        seeded.entry.id,
        assist.retryAutomaticDetection,
      );

      expect(result.status, EntryCaptureStatus.failed);
      expect(await storedHints(), isEmpty);
      expect(source.readerHints, [isNull, isNull]);
    });
  });

  group('what a rule is worth, counted', () {
    test('a rule that produced a copy counts a success', () async {
      final seeded = await h.repos.seedLibrary();
      final taught = await hints.createReaderAreaHint(
        element: _readerContainer,
        sourceUrl: _pageUrl,
      );
      final source = FakePageCaptureSource.needingReaderAreaAssist();

      final result = await v2CaptureWithAssist(
        capture: h.captureWith(source),
        assist: assist,
        entryId: seeded.entry.id,
        locationUrl: _pageUrl,
        captureMode: null,
      );

      expect(result.isCaptured, isTrue);
      expect(
        assist.pendingSelection,
        isNull,
        reason: 'a rule that works is never a reason to ask again',
      );
      final reloaded = (await storedHints()).single;
      expect(reloaded.id, taught.id);
      expect(reloaded.successCount, 1);
      expect(reloaded.failureCount, 0);
      expect(reloaded.lastUsedAt, isNotNull);
    });

    test('the rule a page stops matching counts a failure', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.needingReaderAreaAssist(
        hintAlsoFails: true,
      );

      final pending = v2CaptureWithAssist(
        capture: h.captureWith(source),
        assist: assist,
        entryId: seeded.entry.id,
        locationUrl: _pageUrl,
        captureMode: null,
      );
      while (assist.pendingSelection == null) {
        await Future<void>.delayed(Duration.zero);
      }
      await assist.submitSelection(_readerContainer);
      final result = await pending;

      expect(result.status, EntryCaptureStatus.failed);
      expect(result.needsReaderAreaAssist, isTrue);

      final reloaded = (await storedHints()).single;
      expect(reloaded.failureCount, 1);
      expect(reloaded.successCount, 0);
    });

    test('teaching over a broken rule leaves exactly one', () async {
      final seeded = await h.repos.seedLibrary();
      final stale = await hints.createReaderAreaHint(
        element: _readerContainer,
        sourceUrl: _pageUrl,
      );
      final source = _RuleAwareSource(failFirstHint: true);

      final pending = v2CaptureWithAssist(
        capture: h.captureWith(source),
        assist: assist,
        entryId: seeded.entry.id,
        locationUrl: _pageUrl,
        captureMode: null,
      );
      while (assist.pendingSelection == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        assist.pendingSelection!.isHintFailure,
        isTrue,
        reason: 'the user is told a saved rule stopped working',
      );
      expect(assist.pendingSelection!.failedHintId, stale.id);
      await assist.submitSelection(_readerContainer);
      final result = await pending;

      expect(result.isCaptured, isTrue);
      final rules = await storedHints();
      expect(rules, hasLength(1), reason: 'the broken rule went with it');
      expect(rules.single.id, isNot(stale.id));
      expect(rules.single.successCount, 1);
    });
  });
}

/// A source that answers differently once a rule is in play: the first hinted
/// capture reports the rule stopped matching, the next one works. This is the
/// shape of a saved rule going stale on a site that changed.
class _RuleAwareSource extends FakePageCaptureSource {
  _RuleAwareSource({required this.failFirstHint})
    : super.needingReaderAreaAssist();

  final bool failFirstHint;
  int _hintedCaptures = 0;

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) async {
    if (readerHint != null) {
      _hintedCaptures++;
      if (failFirstHint && _hintedCaptures == 1) {
        readerHints.add(readerHint);
        nextHints.add(nextHint);
        requested.add(url);
        modes.add(requestedMode);
        reusedLoadedPage.add(pageAlreadyLoaded);
        return PageCaptureOutcome.failed(
          pageUrl: url,
          error: 'saved reader-area rule no longer matches',
          needsReaderAreaAssist: true,
        );
      }
    }
    return super.capturePage(
      url: url,
      staging: staging,
      requestedMode: requestedMode,
      shouldContinue: shouldContinue,
      readerHint: readerHint,
      nextHint: nextHint,
      pageAlreadyLoaded: pageAlreadyLoaded,
    );
  }
}
