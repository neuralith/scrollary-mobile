// Pointing at a next-entry control on a **real** site, through the real
// WebView, the real bridge and the real forward-page source.
//
//   flutter test integration_test/live_next_control_test.dart -d <udid> \
//     --dart-define=LIVE_ENTRY_A='<a real entry url, part of a sequence>' \
//     --dart-define=LIVE_NEXT_LABEL='<the visible label or aria-label of its
//                                     next control>'
//
// **No address and no site is compiled in.** With no `LIVE_ENTRY_A` every case
// skips itself and says so, exactly as `device_matrix_test.dart` does — a live
// run is a deliberate, bounded act and never something `flutter test` does on
// its own (CLAUDE.md, *Live-site verification*).
//
// ## Why this exists when the deterministic suite already passes
//
// `test/save_v2/next_control_assist_test.dart` proves the judgement: when the
// user is asked, what a tap is judged against, that a rule is proved before it
// is used, that a control with no address is pressed. It proves all of that
// against a `FakeBrowser`, so it cannot prove the half that only a device has:
//
// * that the probe's control enumeration survives a **real** WKWebView on a
//   client-routed page, where the reader mounts after `readyState` is
//   `complete`;
// * that a locator built from what the **real** picker reports re-matches that
//   page — and matches *one* element, on a layout that gives Prev, Next and the
//   entry list the same class;
// * that `activateLocator` actually moves a page that navigates itself in
//   script, which is a promise about a WebView and not about Dart.
//
// Those three are where a resolver that reads only `href`s reported a sequence
// as finished with entries still to come (V2-D70), and none of them can be
// faked honestly.
//
// It downloads nothing. Every case reads, resolves and navigates; no capture
// runs and no bytes are kept.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/browser_forward_pages.dart';
import 'package:web_reader/recognition/recognise.dart' show RecognitionKeys;
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/next_page.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/selection_request.dart';

import 'support/v2_harness.dart';

/// A real entry that is part of a sequence. Supplied at run time; never here.
const String kLiveEntry = String.fromEnvironment('LIVE_ENTRY_A');

/// What the control that opens the next entry says — its visible text or its
/// `aria-label`. Stands in for the finger: the picker is driven by dispatching
/// a real click on the element carrying this label, so what comes back is the
/// payload a tap produces and not one this file invented.
const String kNextLabel = String.fromEnvironment('LIVE_NEXT_LABEL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late V2App app;
  var caseIndex = 0;

  Future<bool> boot(WidgetTester tester) async {
    if (kLiveEntry.isEmpty) {
      debugPrint('[live] skipped — no LIVE_ENTRY_A');
      return false;
    }
    app = V2App(tag: 'livenext_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    await showBrowser(tester);
    await openPage(tester, app, kLiveEntry);
    return true;
  }

  tearDown(() async {
    if (kLiveEntry.isEmpty) return;
    await app.shutdown(dumpLog: false);
  });

  /// The Source the live entry belongs to, written the way the library writes
  /// one: `(host, path_key)` from the app's own derivation.
  Future<SourceRow> liveSource() async {
    final folder = await app.ui.folders.ensureRoot();
    final (collection, _) = await app.ui.collections.create(
      name: 'Live sequence',
      folderId: folder.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final keys = RecognitionKeys.of(app.browser.currentUrl);
    final (source, violation) = await app.ui.collections.addSource(
      collectionId: collection!.id,
      host: keys.host,
      pathKey: keys.pathKey!,
      language: 'en',
    );
    if (violation != null) throw StateError('$violation');
    return source!;
  }

  /// Put the page into element-picking mode and click the control the run was
  /// told about, so the bridge reports it the way a finger would.
  ///
  /// The click is dispatched *in the page*, on an element found by its label,
  /// and the bridge's own picker swallows it and describes what it hit. Nothing
  /// here constructs the payload.
  Future<SelectedElement?> tapNextControl(WidgetTester tester) async {
    SelectedElement? picked;
    final sub = app.browser.selections.listen((e) => picked = e);
    await app.browser.startSelection(mode: 'link');
    await pumpFor(tester, const Duration(milliseconds: 600));

    await app.browser.debugEvaluate('''
      var want = ${_jsString(kNextLabel)}.toLowerCase();
      var all = Array.prototype.slice.call(
        document.querySelectorAll('a, button, [role="button"]'));
      var hit = null;
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        var label = ((el.getAttribute('aria-label') || '') + ' ' +
                     (el.innerText || '')).toLowerCase();
        if (label.indexOf(want) >= 0) { hit = el; break; }
      }
      if (!hit) return { ok: false };
      hit.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
      return { ok: true };
    ''');

    await pumpFor(tester, const Duration(milliseconds: 900));
    await app.browser.stopSelection();
    await sub.cancel();
    return picked;
  }

  // ─── 1. the page defeats link-only detection, and says it continues ────

  testWidgets(
    'a next control that is not a link is seen, and asked about',
    (tester) async {
      if (!await boot(tester)) return;

      final probe = await app.browser.probe(withLinks: true);
      final landed = app.browser.currentUrl;
      debugPrint(
        '[live] $landed links=${probe.links.length} '
        'controls=${probe.controls.length} headNext=${probe.headNextHref}',
      );
      for (final c in probe.controls.where((c) => matchNextText(c) != null)) {
        debugPrint('[live] next-ish control: "${c.ariaLabel}" / "${c.text}"');
      }

      expect(
        probe.controls,
        isNotEmpty,
        reason:
            'the probe must report the page\'s addressless controls, or the '
            'discriminator between "finished" and "its Next is a button" has '
            'nothing to read',
      );
      expect(
        offersUnfollowableNext(probe),
        isTrue,
        reason:
            'this page is part of a sequence and shows a next control that '
            'carries no address — that is the whole premise of the run',
      );

      final decision = resolveNextPage(
        probe,
        currentUrl: landed,
        visitedNormalized: {normalizeUrl(landed)},
      );
      debugPrint(
        '[live] decision=${decision.decision.name} "${decision.reason}"',
      );
      expect(
        decision.decision,
        NextDecision.askUser,
        reason:
            'before V2-D70 this was endOfChain, and a sequence with entries '
            'still to come was reported as everything the site publishes',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ─── 2. what a real tap teaches, and whether it can be found again ─────

  testWidgets(
    'the tapped control becomes a rule that matches this page once',
    (tester) async {
      if (!await boot(tester)) return;
      if (kNextLabel.isEmpty) {
        debugPrint('[live] skipped — no LIVE_NEXT_LABEL');
        return;
      }

      final landed = app.browser.currentUrl;
      final picked = await tapNextControl(tester);
      expect(picked, isNotNull, reason: 'the picker reported no element');
      debugPrint(
        '[live] picked <${picked!.tag}> href="${picked.href}" '
        'aria="${picked.ariaLabel}" selector=${picked.selector} '
        'container=${picked.containerSelector}',
      );

      expect(
        nextControlMustBePressed(href: picked.href, currentUrl: landed),
        isTrue,
        reason:
            'a control the site handles in script carries no address to load, '
            'which is what makes it a rule that is pressed',
      );

      final hints = PageHintRepository.forLibrary(app.library);
      final rule = await hints.createNextLinkHint(
        element: picked,
        sourceUrl: landed,
        activate: true,
      );
      expect(rule.locator.activate, isTrue);
      expect(
        rule.locator.isWeak,
        isFalse,
        reason:
            'a rule with one signal is one deploy away from being wrong; the '
            'picker should have found a label and a selector at least',
      );

      final match = await app.browser.applyLocator(rule.locator.toJson());
      debugPrint(
        '[live] rule score=${match?.score} matched=${match?.matchedSignals} '
        'ambiguous=${match?.ambiguous}',
      );
      expect(
        match?.isMatch,
        isTrue,
        reason: 'the rule cannot find what it named',
      );
      expect(
        match!.ambiguous,
        isFalse,
        reason:
            'Prev, Next and the entry list are siblings that share a class — a '
            'rule that cannot tell them apart is refused rather than pressed, '
            'and this page must not need that refusal',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ─── 3. pressing it actually moves a page that routes itself ───────────

  testWidgets(
    'pressing the taught control opens the next entry',
    (tester) async {
      if (!await boot(tester)) return;
      if (kNextLabel.isEmpty) {
        debugPrint('[live] skipped — no LIVE_NEXT_LABEL');
        return;
      }

      final from = app.browser.currentUrl;
      final picked = await tapNextControl(tester);
      expect(picked, isNotNull);

      final hints = PageHintRepository.forLibrary(app.library);
      final rule = await hints.createNextLinkHint(
        element: picked!,
        sourceUrl: from,
        activate: true,
      );

      final press = await app.browser.activateLocator(rule.locator.toJson());
      await pumpFor(tester, const Duration(seconds: 2));
      debugPrint(
        '[live] press moved=${press.moved} atEnd=${press.atEndOfChain} '
        'refusal=${press.refusal} -> ${press.url}',
      );

      if (press.atEndOfChain) {
        // A legitimate outcome, and the one the fix in V2-D70 added: a site that
        // switches its own Next off is saying this is the last entry. It is
        // reported as the collection finishing, never as a failure to move.
        debugPrint('[live] the site says this is the last entry of the chain');
        return;
      }

      expect(
        press.moved,
        isTrue,
        reason:
            'the whole point of a pressed rule: the page routes itself and the '
            'address it goes to is what the walk follows. ${press.refusal}',
      );
      expect(
        normalizeUrl(press.url!),
        isNot(normalizeUrl(from)),
        reason:
            'a press that lands where it started is a dead end, not a next '
            'page',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ─── 4. the production path, end to end, with the hold answered ────────

  testWidgets('the forward page source asks, is taught, and hands the walk the '
      'next address', (tester) async {
    if (!await boot(tester)) return;
    if (kNextLabel.isEmpty) {
      debugPrint('[live] skipped — no LIVE_NEXT_LABEL');
      return;
    }

    final source = await liveSource();
    final hints = PageHintRepository.forLibrary(app.library);
    final from = app.browser.currentUrl;
    final visited = {normalizeUrl(from)};

    var asks = 0;
    final pages = BrowserForwardPageSource(
      app.browser,
      hints: hints,
      ask: (request, {validate}) async {
        asks++;
        debugPrint('[live] asked: "${request.reason}"');
        final picked = await tapNextControl(tester);
        if (picked == null) return const SelectionOutcome.cancelled();

        // The run's own judgement of the tap, before anything is written.
        final refusal = await validate?.call(picked);
        debugPrint('[live] validator said: ${refusal ?? "fine"}');
        if (refusal != null) return const SelectionOutcome.cancelled();

        final rule = await hints.createNextLinkHint(
          element: picked,
          sourceUrl: request.sourceUrl,
          activate: nextControlMustBePressed(
            href: picked.href,
            currentUrl: request.sourceUrl,
          ),
        );
        return SelectionOutcome.rule(rule, picked);
      },
    );

    final page = await pages.read(
      url: from,
      source: source,
      visited: visited,
      shouldContinue: () => true,
    );
    debugPrint(
      '[live] read: stop=${page.stop?.name} next=${page.nextUrl} '
      'press=${page.resolveNext != null} asks=$asks',
    );

    expect(page.stop, isNull, reason: 'the page was readable and was taught');
    expect(asks, 1, reason: 'asked once, and the answer settled it');

    // Whichever kind of rule the tap produced, the walk now has a next address.
    String? next = page.nextUrl;
    if (next == null && page.resolveNext != null) {
      final step = await page.resolveNext!();
      await pumpFor(tester, const Duration(seconds: 2));
      if (step.stop == WalkStop.endOfSource) {
        debugPrint('[live] the taught control says the chain ends here');
        return;
      }
      expect(
        step.stop,
        isNull,
        reason: 'the taught control led nowhere: ${step.stop?.name}',
      );
      next = step.url;
    }

    expect(next, isNotNull);
    expect(normalizeUrl(next!), isNot(normalizeUrl(from)));
    debugPrint('[live] the walk would go on to $next');

    // And the rule is the Source's now, not this one page's: the next entry
    // resolves without asking again.
    final reused = await hints.findFor(next, HintKind.nextLink);
    expect(
      reused,
      isNotNull,
      reason:
          'a rule taught on one entry must serve the rest of the '
          'collection, or the user is asked on every page',
    );
    expect(reused!.scope, HintScope.collection);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// A Dart string as a JavaScript literal.
String _jsString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
