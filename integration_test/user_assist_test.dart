// The user-assisted fallback, against a real WebView.
//
//   flutter test integration_test/user_assist_test.dart -d <device-id>
//
// Uses the in-process fixture, whose `/amb/` pages offer two equally plausible
// "next" controls pointing at different pages, and whose `/nolabel/` pages
// offer an icon with no rel, no text and no aria-label. Both are cases where
// guessing would be wrong, so the run must stop and ask — and then remember the
// answer.
//
// ## The state of this on the V2 branch, stated plainly
//
// **The judgement survived the port; the host did not.** `resolveNextPage`,
// `collectNextCandidates`, `validateNextUrl`, `PageHintRepository` and
// `BrowserController.selections` are all still here and still ported verbatim.
// What no longer exists is anything that *asks*: V1's `SaveRunController` held
// `pendingSelection`, drove `BrowserController` into element-picking mode, and
// resumed the run from `submitSelection`. V2's `QueueRunner` has no such state,
// `EntryCaptureService` has no selection path, and
// `operation_indicator.dart`'s `_needsUser` is hard-wired to `false` with a
// comment saying exactly this — "user-assisted selection has no host on the V2
// capture path … kept as a hook because the wiring above it is device-tested,
// and because restoring user assist restores this with it."
//
// So this file is in two halves:
//
// * **What runs today** — the two cases that establish the *premise*: on a
//   device, against the real DOM, the ambiguous and unlabelled fixture pages
//   really do defeat automatic detection, and the unambiguous one really does
//   not need help. These are the assertions that would silently rot if the
//   fixture or the detector drifted while the overlay was away, and they are
//   the ones that make restoring the host a small job rather than an
//   archaeology exercise.
// * **What is written and skipped** — the four cases that need a host to ask
//   through. They are written against the seam the V2 flow will use, so
//   restoring the overlay is a matter of deleting the `skip:` and pointing
//   three calls at whatever holds the pending selection. Each names precisely
//   what it is waiting for.
//
// Nothing here was weakened to go green. The skipped cases assert exactly what
// V1's did.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/save/next_page.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';

import 'support/v2_harness.dart';

/// Why every case below the line is skipped. One sentence, one place —
/// `testWidgets`'s `skip` takes only a bool, so the reason lives here and is
/// named from each `skip:` site.
const String kNoAssistHost =
    'V2 has no host for a user-assisted selection: QueueRunner holds no '
    'pendingSelection, EntryCaptureService has no selection path, and '
    'operation_indicator.dart hard-wires _needsUser to false. Un-skip with the '
    'lane that re-hosts the overlay.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite(applyDelays: false);
  late V2App app;
  late PageHintRepository rules;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester, {String? startUrl}) async {
    app = V2App(tag: 'assist_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    // Rules live in the V2 page_hints table.
    rules = PageHintRepository.forLibrary(app.library);
    await showBrowser(tester);
    if (startUrl != null) await openPage(tester, app, startUrl);
  }

  tearDown(() => app.shutdown(dumpLog: false));

  /// What automatic detection makes of the page the Browser is on.
  Future<NextPageResult> decideNext(WidgetTester tester, {String? hint}) async {
    final probe = await app.browser.probe(withLinks: true);
    return resolveNextPage(
      probe,
      currentUrl: app.browser.currentUrl,
      visitedNormalized: const <String>{},
      hintHref: hint,
    );
  }

  // ================================================= what runs today

  testWidgets(
    'two plausible controls defeat automatic detection',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/amb/1');

      final decision = await decideNext(tester);
      debugPrintAssist(decision);

      expect(
        decision.decision,
        NextDecision.askUser,
        reason:
            'the page offers "Next" and "Continue" pointing at different pages — '
            'a wrong automatic pick walks the run into the wrong collection, '
            'which is worse than a prompt',
      );
      expect(decision.needsUserSelection, isTrue);
      expect(decision.considered, isNotEmpty);
      expect(
        decision.hasNext,
        isFalse,
        reason:
            'a best candidate is still reported — it is what the prompt would '
            'be about — but nothing may be navigated to without an answer',
      );
      expect(
        decision.considered.map((c) => c.href).toSet().length,
        greaterThan(1),
        reason: 'and the ambiguity is real: the candidates disagree',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'an unlabelled control also asks rather than guessing',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/nolabel/1');

      final decision = await decideNext(tester);
      debugPrintAssist(decision);

      expect(
        decision.decision,
        NextDecision.askUser,
        reason:
            'an icon with no rel, no text and no aria-label is not a signal — '
            'guessing from position alone is how a run walks off a site',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'automatic detection needs no prompt on the plain fixture',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final decision = await decideNext(tester);
      debugPrintAssist(decision);

      expect(
        decision.decision,
        NextDecision.proceed,
        reason: 'rel=next is unambiguous; asking here would be a regression',
      );
      expect(decision.chosen!.href, contains('/entry/2'));
      expect(decision.chosen!.strategy, NextStrategy.anchorRelNext);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a taught rule answers the ambiguous page without asking',
    (tester) async {
      // The half of "remember the answer" that has no host dependency: a rule
      // the user taught is stored, found for this address, and resolves the
      // ambiguity outright. Only the *asking* is missing in V2; the remembering
      // and the reusing are both here and both device-real.
      await boot(tester, startUrl: '${fixture.base}/amb/1');

      await rules.createNextLinkHint(
        element: SelectedElement(
          mode: 'link',
          tag: 'a',
          text: 'Next',
          href: '${fixture.base}/amb/2',
        ),
        sourceUrl: '${fixture.base}/amb/1',
      );

      final saved = await rules.all();
      expect(saved, hasLength(1));
      expect(saved.single.kind, HintKind.nextLink);
      expect(
        saved.single.scope,
        HintScope.collection,
        reason: 'host plus the exact collection path — the narrowest scope',
      );
      expect(saved.single.host, '127.0.0.1');
      expect(saved.single.hintPath, '/amb');

      final found = await rules.findFor(
        '${fixture.base}/amb/1',
        HintKind.nextLink,
      );
      expect(
        found,
        isNotNull,
        reason: 'the rule must match the page it was for',
      );

      final decision = await decideNext(tester, hint: '${fixture.base}/amb/2');
      debugPrintAssist(decision);
      expect(
        decision.decision,
        NextDecision.proceed,
        reason: 'a saved rule must stop the prompts — that is the point of it',
      );
      expect(decision.chosen!.strategy, NextStrategy.savedHint);
      expect(decision.chosen!.href, '${fixture.base}/amb/2');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a selection that leaves the host is refused',
    (tester) async {
      // A user tap is a strong signal about one link — not permission to leave
      // the site. Asserted against the validator directly, because it is the
      // validator that owns the rule and the host to ask it about is real.
      await boot(tester, startUrl: '${fixture.base}/amb/1');

      final refused = validateNextUrl(
        candidate: 'https://elsewhere.example/entry/2',
        currentUrl: app.browser.currentUrl,
        visited: const <String>{},
      );
      expect(refused.isAccepted, isFalse);
      expect(refused.rejection, NextUrlRejection.differentHost);

      final accepted = validateNextUrl(
        candidate: '${fixture.base}/amb/2',
        currentUrl: app.browser.currentUrl,
        visited: const <String>{},
      );
      expect(accepted.isAccepted, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ============================================= waiting for a host
  //
  // Everything below asserts what V1's suite asserted, against the seam a V2
  // host will expose. Each is skipped for the one reason in [kNoAssistHost].

  testWidgets(
    'ambiguous page: the run asks, the answer is saved, the run continues',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/amb/1');
      final entryId = await app.queueSaveOf('${fixture.base}/amb/1');
      await startQueue(tester, app);

      // The seam: something the user can answer through, published while the
      // run holds. In V1 this was `SaveRunController.pendingSelection`, with
      // `BrowserController.isSelecting` true because the page is in
      // element-picking mode. A V2 host publishes the same two facts.
      await pumpUntil(
        tester,
        () => app.browser.isSelecting,
        timeout: const Duration(seconds: 90),
        reason: 'the run never asked',
      );

      // …the user taps the correct control, which is exactly this payload.
      app.browser.onSelection(const {
        'mode': 'link',
        'tag': 'a',
        'text': 'Next',
        'href': '/amb/2',
      });

      await awaitQueueIdle(tester, app);

      // A rule was created, scoped to this collection, and the run went on.
      final saved = await rules.all();
      expect(saved, hasLength(1));
      expect(saved.single.kind, HintKind.nextLink);
      expect(saved.single.scope, HintScope.collection);
      expect(saved.single.host, '127.0.0.1');
      expect(saved.single.hintPath, '/amb');
      expect(await app.storedImagesOf(entryId), greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 8)),
    // Reason: [kNoAssistHost].
    skip: true,
  );

  testWidgets(
    'cancelling the prompt ends the run rather than guessing on',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/nolabel/1');
      final entryId = await app.queueSaveOf('${fixture.base}/nolabel/1');
      await startQueue(tester, app);

      await pumpUntil(
        tester,
        () => app.browser.isSelecting,
        timeout: const Duration(seconds: 90),
        reason: 'the run never asked',
      );

      // The V2 host's cancel — whatever it is called — must end the run in a
      // named terminal state and must never guess.
      final task = await app.taskFor(entryId);
      await app.ui.queue.cancel(task!.id);
      await awaitQueueIdle(tester, app);

      expect((await app.ui.queue.byId(task.id))!.state.isTerminal, isTrue);
      expect(await rules.all(), isEmpty, reason: 'cancelling saves no rule');
    },
    timeout: const Timeout(Duration(minutes: 8)),
    // Reason: [kNoAssistHost].
    skip: true,
  );

  testWidgets(
    'a selected link that leaves the host is refused, and the prompt stays',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/amb/1');
      await app.queueSaveOf('${fixture.base}/amb/1');
      await startQueue(tester, app);

      await pumpUntil(
        tester,
        () => app.browser.isSelecting,
        timeout: const Duration(seconds: 90),
      );

      app.browser.onSelection(const {
        'mode': 'link',
        'tag': 'a',
        'text': 'Next',
        'href': 'https://elsewhere.example/entry/2',
      });
      await pumpFor(tester, const Duration(seconds: 3));

      expect(
        app.browser.isSelecting,
        isTrue,
        reason: 'the prompt stays open when the selection is refused',
      );
      expect(
        await rules.all(),
        isEmpty,
        reason: 'and no rule comes from a refused link',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
    // Reason: [kNoAssistHost].
    skip: true,
  );

  testWidgets(
    'a held run reports "needs you" and lands the user in the Browser',
    (tester) async {
      // `operation_indicator.dart`'s `_needsUser` hook, which is hard-wired
      // false today. When a host exists, a run waiting on a person must say so
      // — the pill announces it as a live region, and tapping it opens the
      // Browser rather than Activity, because the selection overlay is drawn on
      // that screen and nowhere else.
      await boot(tester, startUrl: '${fixture.base}/amb/1');
      await app.queueSaveOf('${fixture.base}/amb/1');
      await startQueue(tester, app);
      await openReader(tester, 'nothing');

      await pumpUntil(
        tester,
        () => find
            .bySemanticsLabel(
              'Background work needs you — 1 running. Opens the Browser.',
            )
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 90),
        reason: 'the indicator never reported that a person was needed',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
    // Reason: [kNoAssistHost].
    skip: true,
  );
}

/// One line per decision, so a failure says what the page actually offered.
void debugPrintAssist(NextPageResult result) {
  debugPrint(
    '[assist] decision=${result.decision.name} reason="${result.reason}" '
    'chosen=${result.chosen?.href} considered='
    '${[for (final c in result.considered) '${c.strategy.name}:${c.href}']}',
  );
}
