/// Pointing at the control that opens the next entry, and everything that must
/// be true before the app believes it.
///
/// The failure this covers was found on a real reader and is not exotic: the
/// page had no next *link* at all. Its Next was a `<button>` the site handles
/// in script, so a resolver that can only read `href`s found nothing, and
/// "nothing" was reported as the end of a collection that had two more entries
/// in it. The user could not correct it either — the rule the picker wrote had
/// no address in it and nothing could ever match it again.
///
/// So there are four separate things to prove, and they fail independently:
///
/// 1. **The page is asked about only when it says the sequence continues.** A
///    finished collection must not be met with a prompt.
/// 2. **A tap is judged before a rule is written from it.** An advert, the
///    previous entry, a link off the site, a link to another work on the same
///    site — each is refused with a reason, and the prompt stays open.
/// 3. **The rule is proved on the page it was taught on.** A locator that
///    cannot find the element the finger just hit is deleted rather than kept.
/// 4. **A control with no address is pressed, and where the page goes is what
///    the walk follows.** A press that changes nothing is a dead end, not a
///    next page.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/browser_forward_pages.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/selection_request.dart';

import '../helpers/fake_browser.dart';
import '../recognition/support/recognition_harness.dart';

/// The floating Next of a reader that routes itself: a labelled control with
/// no address anywhere on it.
const _nextButton = PageLink(
  href: '',
  ariaLabel: 'Next entry',
  className: 'reader-float__btn',
);

/// What the picker reports when that control is tapped.
const _tappedNextButton = SelectedElement(
  mode: 'link',
  tag: 'button',
  ariaLabel: 'Next entry',
  selector: 'button.reader-float__btn',
  containerSelector: 'div.reader-float',
);

void main() {
  late RecognitionHarness h;
  late FakeBrowser browser;
  late PageHintRepository hints;
  late CollectionRow collection;
  late SourceRow source;

  final here = partUrl(kHostA, '101');
  final there = partUrl(kHostA, '102');

  setUp(() async {
    h = RecognitionHarness();
    browser = FakeBrowser();
    hints = PageHintRepository.forLibrary(h.repos.db);
    collection = await h.collection();
    source = await h.source(collection: collection, host: kHostA);
  });
  tearDown(() => h.close());

  /// A reader page: images, no next link, and whatever controls it shows.
  void putPage(
    String url, {
    List<PageLink> controls = const [],
    List<PageLink> links = const [],
    String? nextHref,
  }) => browser.addPage(
    url,
    entryProbe(
      url: url,
      title: 'Part ${entryNumberOf(url)}',
      imageUrls: const ['https://cdn.example/a.jpg'],
      nextHref: nextHref,
      extraLinks: links,
      controls: controls,
    ),
  );

  /// One recorded hold, and the answer it was given.
  ///
  /// Stands in for `V2AssistController.ask` so a walk's side of the
  /// conversation can be driven without pumping a widget tree; the controller's
  /// own half is asserted in the last group.
  ({
    NextControlAsk ask,
    List<SelectionRequest> asked,
    List<SelectionValidator?> validators,
  })
  scriptedAsk(List<SelectionOutcome> answers) {
    final asked = <SelectionRequest>[];
    final validators = <SelectionValidator?>[];
    var next = 0;
    return (
      asked: asked,
      validators: validators,
      ask: (request, {validate}) async {
        asked.add(request);
        validators.add(validate);
        return next < answers.length
            ? answers[next++]
            : const SelectionOutcome.cancelled();
      },
    );
  }

  /// The same, for answers that must be produced *during* the hold.
  ///
  /// Teaching writes a row, and a row that exists before the walk starts is a
  /// rule the walk finds and uses instead of asking — which is right in life
  /// and wrong in a test about being asked. So the rule is created when the
  /// hold happens, exactly as a tap creates it.
  ({NextControlAsk ask, List<SelectionRequest> asked}) scriptedTeaching(
    List<Future<SelectionOutcome> Function()> answers,
  ) {
    final asked = <SelectionRequest>[];
    var next = 0;
    return (
      asked: asked,
      ask: (request, {validate}) async {
        asked.add(request);
        return next < answers.length
            ? await answers[next++]()
            : const SelectionOutcome.cancelled();
      },
    );
  }

  /// What a tap on the floating control teaches, written now.
  Future<SelectionOutcome> teachPressedControl() async => SelectionOutcome.rule(
    await hints.createNextLinkHint(
      element: _tappedNextButton,
      sourceUrl: here,
      activate: true,
    ),
    _tappedNextButton,
  );

  BrowserForwardPageSource pagesWith({NextControlAsk? ask}) =>
      BrowserForwardPageSource(browser, hints: hints, ask: ask);

  Future<WalkedPage> readHere(
    BrowserForwardPageSource pages, {
    Set<String>? visited,
  }) => pages.read(
    url: here,
    source: source,
    visited: visited ?? {normalizeUrl(here)},
    shouldContinue: () => true,
  );

  // ─── 1. asked only when the sequence says it continues ─────────────────

  group('when the user is asked at all', () {
    test('a page whose Next is a control rather than a link asks', () async {
      putPage(here, controls: const [_nextButton]);
      final script = scriptedAsk([const SelectionOutcome.cancelled()]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, hasLength(1));
      expect(script.asked.single.kind, HintKind.nextLink);
      expect(script.asked.single.sourceUrl, here);
      expect(
        page.stop,
        WalkStop.needsUserAssist,
        reason: 'cancelling teaches nothing, so the walk keeps the stop it had',
      );
    });

    test('a collection that has genuinely ended is not asked about', () async {
      putPage(
        here,
        links: const [
          PageLink(href: 'https://alpha.example/works', text: 'All'),
        ],
      );
      final script = scriptedAsk([]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(
        script.asked,
        isEmpty,
        reason:
            'a prompt at the end of a finished collection is a worse '
            'failure than the one the prompt exists for',
      );
      expect(page.stop, isNull);
      expect(
        page.nextUrl,
        isNull,
        reason: 'which the walk reads as the end of what the site publishes',
      );
    });

    test('a page with a plain next link is followed without asking', () async {
      putPage(here, nextHref: there, controls: const [_nextButton]);
      final script = scriptedAsk([]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, isEmpty);
      expect(page.nextUrl, normalizeUrl(there));
    });

    test('a reader that mounts its controls after the shell is looked at again '
        'before its collection is called finished', () async {
      // The live shape this exists for: `readyState` is complete for the
      // page the server sent, and the control that opens the next entry
      // appears when the reader script runs. A first probe therefore shows
      // nothing at all, which is exactly what a finished collection shows.
      putPage(here);
      browser.onProbe = (n) {
        if (n >= 2) putPage(here, controls: const [_nextButton]);
      };
      final script = scriptedAsk([const SelectionOutcome.cancelled()]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(
        script.asked,
        hasLength(1),
        reason:
            'the page did have a next control; it had simply not '
            'arrived when the first probe ran',
      );
      expect(page.stop, WalkStop.needsUserAssist);
      expect(browser.probeCount, greaterThan(1));
    });

    test('a page that answers at once is not looked at twice', () async {
      putPage(here, nextHref: there);

      await readHere(pagesWith());

      expect(
        browser.probeCount,
        1,
        reason:
            'only a page that offered nothing is re-read — a run must '
            'not pay a settle on every page it walks',
      );
    });

    test(
      'a collection that really has finished is still allowed to finish',
      () async {
        putPage(here);

        final page = await readHere(pagesWith());

        expect(page.stop, isNull);
        expect(page.nextUrl, isNull);
        expect(
          browser.probeCount,
          kEndOfChainLooks,
          reason: 'it looks again, and then believes what it sees',
        );
      },
    );

    test('a walk with nowhere to ask stops rather than guessing', () async {
      putPage(here, controls: const [_nextButton]);

      final page = await readHere(pagesWith());

      expect(page.stop, WalkStop.needsUserAssist);
    });
  });

  // ─── 2. the tap is judged before it is believed ────────────────────────

  group('what the user tapped is judged first', () {
    /// Ask once, capture the validator, and put [element] through it.
    Future<String?> refusalFor(
      SelectedElement element, {
      Set<String>? visited,
    }) async {
      putPage(here, controls: const [_nextButton]);
      final script = scriptedAsk([const SelectionOutcome.cancelled()]);
      await readHere(pagesWith(ask: script.ask), visited: visited);
      final validate = script.validators.single;
      expect(validate, isNotNull, reason: 'the hold must carry a judgement');
      return validate!(element);
    }

    SelectedElement link(String href) =>
        SelectedElement(mode: 'link', tag: 'a', text: 'Next', href: href);

    test('a link to the next entry on this source is accepted', () async {
      expect(await refusalFor(link(there)), isNull);
    });

    test('a link that leaves the site is refused by name', () async {
      final refusal = await refusalFor(link('https://elsewhere.example/x/2'));
      expect(refusal, isNotNull);
      expect(refusal, contains('elsewhere.example'));
      expect(refusal, contains('different site'));
    });

    test('a sign-in link is refused', () async {
      final refusal = await refusalFor(link('https://alpha.example/login'));
      expect(refusal, contains('sign-in'));
    });

    test('a link back to where the walk has been is refused', () async {
      final refusal = await refusalFor(
        link(there),
        visited: {normalizeUrl(here), normalizeUrl(there)},
      );
      expect(refusal, contains('circle'));
    });

    test('a link to another work on the same site is refused', () async {
      final refusal = await refusalFor(
        link('https://alpha.example/works/another-harbour/part-1'),
      );
      expect(
        refusal,
        contains('somewhere else on this site'),
        reason:
            'it passes every host check and is still the wrong answer — '
            'the Source is the identity that matters',
      );
    });

    test(
      'a labelled control with no address is accepted, to be pressed',
      () async {
        expect(await refusalFor(_tappedNextButton), isNull);
      },
    );

    test(
      'a stretch of page with nothing to recognise it by is refused',
      () async {
        final refusal = await refusalFor(
          const SelectedElement(mode: 'link', tag: 'div'),
        );
        expect(refusal, contains('not a control'));
      },
    );

    test('a control with a label but nothing else is still refused when there '
        'is no signal to find it by later', () async {
      final refusal = await refusalFor(
        const SelectedElement(mode: 'link', tag: 'button'),
      );
      expect(refusal, contains('nothing about that element'));
    });
  });

  // ─── 3. the rule is proved on the page it was taught on ────────────────

  group('the rule the tap produced is proved before it is used', () {
    test('a rule that cannot find the control again is deleted and the user '
        'is asked once more, carrying the reason', () async {
      putPage(here, controls: const [_nextButton]);
      // The locator writes cleanly and matches nothing.
      browser.onApplyLocator = (_, _) => const LocatorMatch.failed('no match');
      final script = scriptedTeaching([
        teachPressedControl,
        () async => const SelectionOutcome.cancelled(),
      ]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, hasLength(2));
      expect(script.asked[1].errorMessage, contains('find again'));
      expect(page.stop, WalkStop.needsUserAssist);
      expect(
        await hints.all(),
        isEmpty,
        reason:
            'a rule that cannot be proved is not kept — leaving it would '
            'answer this page wrongly and confidently on every later run',
      );
    });

    test('a pressed rule that matches two controls at once is refused, '
        'because pressing one of them could go backwards', () async {
      putPage(here, controls: const [_nextButton]);
      browser.onApplyLocator = (_, _) => const LocatorMatch(
        href: '',
        score: 4,
        ambiguous: true,
        activate: true,
      );
      final script = scriptedTeaching([
        teachPressedControl,
        () async => const SelectionOutcome.cancelled(),
      ]);

      await readHere(pagesWith(ask: script.ask));

      expect(script.asked[1].errorMessage, contains('go backwards'));
      expect(await hints.all(), isEmpty);
    });

    test('a rule that matches a different link than the finger did is '
        'refused', () async {
      putPage(here, controls: const [_nextButton]);
      browser.onApplyLocator = (_, _) => const LocatorMatch(
        href: 'https://elsewhere.example/somewhere',
        score: 5,
      );
      final script = scriptedTeaching([
        () async => SelectionOutcome.rule(
          await hints.createNextLinkHint(
            element: SelectedElement(
              mode: 'link',
              tag: 'a',
              text: 'Next',
              href: there,
            ),
            sourceUrl: here,
          ),
          _tappedNextButton,
        ),
        () async => const SelectionOutcome.cancelled(),
      ]);

      await readHere(pagesWith(ask: script.ask));

      expect(script.asked[1].errorMessage, contains('different link'));
      expect(await hints.all(), isEmpty);
    });

    test('a proved rule ends the hold and carries the walk on', () async {
      putPage(here, controls: const [_nextButton]);
      browser.onApplyLocator = (_, _) =>
          const LocatorMatch(href: '', score: 7, activate: true);
      final script = scriptedTeaching([teachPressedControl]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, hasLength(1));
      expect(page.stop, isNull);
      expect(
        page.nextUrl,
        isNull,
        reason: 'a pressed control has no address until it is pressed',
      );
      expect(page.resolveNext, isNotNull);
      expect(await hints.all(), hasLength(1));
    });

    test('a page whose rule can never be proved stops instead of asking for '
        'ever', () async {
      putPage(here, controls: const [_nextButton]);
      browser.onApplyLocator = (_, _) => const LocatorMatch.failed('no match');
      final script = scriptedTeaching([
        for (var i = 0; i < kMaxNextControlAsks + 2; i++) teachPressedControl,
      ]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, hasLength(kMaxNextControlAsks));
      expect(page.stop, WalkStop.needsUserAssist);
    });

    test('retry-auto runs detection again with no rule in the way', () async {
      // The page turns out to have a followable link after all.
      putPage(here, nextHref: there);
      browser.addPage(
        here,
        entryProbe(
          url: here,
          title: 'Part 101',
          imageUrls: const ['https://cdn.example/a.jpg'],
          controls: const [_nextButton],
        ),
      );
      var pass = 0;
      final script = scriptedAsk([const SelectionOutcome.retryAuto()]);
      final pages = BrowserForwardPageSource(
        browser,
        hints: hints,
        ask: (request, {validate}) async {
          pass++;
          // Between the ask and the retry the page settles and shows its link.
          putPage(here, nextHref: there, controls: const [_nextButton]);
          return script.ask(request, validate: validate);
        },
      );

      final page = await readHere(pages);

      expect(pass, 1);
      expect(page.nextUrl, normalizeUrl(there));
      expect(await hints.all(), isEmpty, reason: 'retry-auto teaches nothing');
    });
  });

  // ─── 4. pressing the control, and where the page goes ──────────────────

  group('pressing a control that carries no address', () {
    Future<WalkedPage> taughtPage({Set<String>? visited}) async {
      putPage(here, controls: const [_nextButton]);
      browser.onApplyLocator = (_, _) =>
          const LocatorMatch(href: '', score: 7, activate: true);
      final script = scriptedTeaching([teachPressedControl]);
      return readHere(pagesWith(ask: script.ask), visited: visited);
    }

    test(
      'the address the page routed itself to is what the walk follows',
      () async {
        final page = await taughtPage();
        browser.onActivateLocator = (_, _) => there;

        final step = await page.resolveNext!();

        expect(step.stop, isNull);
        expect(step.url, there);
        expect(browser.locatorsActivated, hasLength(1));
        expect((await hints.all()).single.successCount, 1);
      },
    );

    test('a press that changes nothing is a dead end, not the end of the '
        'collection', () async {
      final page = await taughtPage();
      browser.onActivateLocator = (_, _) => null;

      final step = await page.resolveNext!();

      expect(step.stop, WalkStop.noForwardProgress);
      expect(step.url, isNull);
      expect(
        (await hints.all()).single.failureCount,
        1,
        reason:
            'the rule that led nowhere is counted against, so the one the '
            'user teaches next wins the tie-break over it',
      );
    });

    test('a control the site switched off is the collection finishing, not a '
        'failure to move', () async {
      final page = await taughtPage();
      browser.nextControlIsDisabled = true;

      final step = await page.resolveNext!();

      expect(
        step.stop,
        WalkStop.endOfSource,
        reason:
            'the site turning its own Next off is it saying there is '
            'nothing after this page — reporting the last entry of a '
            'collection as "it went in a circle" says something went wrong '
            'when nothing did',
      );
      expect(
        (await hints.all()).single.successCount,
        1,
        reason:
            'and the rule worked: it found the control, and the control is '
            'what said the chain had ended',
      );
    });

    test(
      'a press that lands where the walk has already been is refused too',
      () async {
        final page = await taughtPage(
          visited: {normalizeUrl(here), normalizeUrl(there)},
        );
        browser.onActivateLocator = (_, _) => there;

        final step = await page.resolveNext!();

        expect(step.stop, WalkStop.noForwardProgress);
      },
    );
  });

  // ─── the rule, later ───────────────────────────────────────────────────

  group('a rule the user already taught', () {
    test('answers the page without asking again', () async {
      putPage(here, controls: const [_nextButton]);
      await hints.createNextLinkHint(
        element: _tappedNextButton,
        sourceUrl: here,
        activate: true,
      );
      browser.onApplyLocator = (_, _) =>
          const LocatorMatch(href: '', score: 7, activate: true);
      final script = scriptedAsk([]);

      final page = await readHere(pagesWith(ask: script.ask));

      expect(script.asked, isEmpty);
      expect(page.resolveNext, isNotNull);
      expect(
        (await hints.all()).single.successCount,
        0,
        reason:
            'matching a control says nothing about whether pressing it '
            'moves the page — a pressed rule is counted where that is known',
      );

      browser.onActivateLocator = (_, _) => there;
      expect((await page.resolveNext!()).url, there);
      expect((await hints.all()).single.successCount, 1);
    });

    test('applies to another entry of the same collection', () async {
      // The scope taught on part 101 is the collection, so part 102 is covered
      // without teaching it a second time.
      await hints.createNextLinkHint(
        element: _tappedNextButton,
        sourceUrl: here,
        activate: true,
      );
      final found = await hints.findFor(there, HintKind.nextLink);

      expect(found, isNotNull);
      expect(found!.scope, HintScope.collection);
      expect(found.hintPath, collectionFingerprint(here));
      expect(found.locator.activate, isTrue);
    });

    test(
      'does not leak onto an unrelated collection on the same site',
      () async {
        await hints.createNextLinkHint(
          element: _tappedNextButton,
          sourceUrl: here,
          activate: true,
        );

        expect(
          await hints.findFor(
            'https://alpha.example/works/another-harbour/part-1',
            HintKind.nextLink,
          ),
          isNull,
        );
      },
    );

    test('one that stopped matching is counted against and re-asked, saying '
        'so', () async {
      putPage(here, controls: const [_nextButton]);
      final stale = await hints.createNextLinkHint(
        element: _tappedNextButton,
        sourceUrl: here,
        activate: true,
      );
      browser.onApplyLocator = (_, _) => const LocatorMatch.failed('gone');
      final script = scriptedAsk([const SelectionOutcome.cancelled()]);

      await readHere(pagesWith(ask: script.ask));

      expect(script.asked.single.isHintFailure, isTrue);
      expect(script.asked.single.failedHintId, stale.id);
      expect(
        (await hints.all()).single.failureCount,
        1,
        reason:
            'a rule the page stopped matching counts a failure, and is '
            'kept until something better replaces it',
      );
    });
  });

  // ─── the host the walk holds on ────────────────────────────────────────

  group('the assist host', () {
    late V2AssistController assist;

    setUp(() => assist = V2AssistController(browser: browser, hints: hints));
    tearDown(() => assist.dispose());

    SelectionRequest requestOf(HintKind kind) =>
        SelectionRequest(kind: kind, sourceUrl: here, prompt: 'p', reason: 'r');

    test('a next-entry hold puts the page into link-picking, a reading-area '
        'hold into area-picking', () async {
      unawaited(assist.ask(requestOf(HintKind.nextLink)));
      await pumpEventQueue();
      expect(browser.selectionModes, ['link']);
      await assist.cancelSelection();

      unawaited(assist.ask(requestOf(HintKind.readerArea)));
      await pumpEventQueue();
      expect(browser.selectionModes, ['link', 'reader']);
      await assist.cancelSelection();
    });

    test('a refused pick keeps the prompt open, writes no rule, and says '
        'why', () async {
      final answer = assist.ask(
        requestOf(HintKind.nextLink),
        validate: (_) async => 'that opens an advert',
      );

      await assist.submitSelection(_tappedNextButton);

      expect(assist.pendingSelection, isNotNull);
      expect(assist.pendingSelection!.errorMessage, 'that opens an advert');
      expect(browser.isSelecting, isTrue, reason: 'still pointing');
      expect(await hints.all(), isEmpty);

      await assist.cancelSelection();
      expect((await answer).cancelled, isTrue);
    });

    test('an accepted pick writes the rule the hold asked for', () async {
      final answer = assist.ask(
        requestOf(HintKind.nextLink),
        validate: (_) async => null,
      );
      await assist.submitSelection(_tappedNextButton);

      final outcome = await answer;
      expect(outcome.hasRule, isTrue);
      expect(outcome.rule!.kind, HintKind.nextLink);
      expect(
        outcome.rule!.locator.activate,
        isTrue,
        reason: 'the tapped control carried no address, so it is pressed',
      );
      expect(assist.pendingSelection, isNull);
      expect(browser.isSelecting, isFalse);
    });

    test('a tapped link is stored as a rule that is followed', () async {
      final answer = assist.ask(requestOf(HintKind.nextLink));
      await assist.submitSelection(
        SelectedElement(mode: 'link', tag: 'a', text: 'Next', href: there),
      );

      final rule = (await answer).rule!;
      expect(rule.locator.activate, isFalse);
      expect(rule.exampleTargetUrl, there);
      expect(rule.locator.hrefPattern, isNotNull);
    });

    test('a reading-area hold still writes a reading-area rule', () async {
      final answer = assist.ask(requestOf(HintKind.readerArea));
      await assist.submitSelection(
        const SelectedElement(
          mode: 'reader',
          tag: 'div',
          selector: 'div.reader',
          imageCount: 12,
          minImageEdge: 800,
        ),
      );

      expect((await answer).rule!.kind, HintKind.readerArea);
    });
  });
}

/// The digits in a part address, for a fixture title. Nothing under test reads
/// a number this way.
String entryNumberOf(String url) =>
    RegExp(r'(\d+)$').firstMatch(url)?.group(1) ?? '?';
