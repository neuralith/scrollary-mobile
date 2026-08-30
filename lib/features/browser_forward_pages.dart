/// Reads one page of a Source's forward chain through the real Browser.
///
/// The walk's counterpart to `source_observation_browser.dart`, and it keeps
/// that file's protocol exactly, because the protocol is what was validated on
/// hardware: the navigation is announced with
/// [BrowserController.allowNextNavigation], the load is awaited, and every
/// judgement is taken from the settled page — never from the address the
/// reading aimed at. The landed-URL policy boundary is owned here, because
/// only the thing that navigates can know where it ended up.
///
/// Two things it deliberately does not do:
///
/// * **It finds no next page of its own.** That is `resolveNextPage`, the same
///   resolver capture uses, given the same saved rule the user taught and the
///   walk's own visited set. A number in a URL never manufactures the address
///   after it.
/// * **It writes nothing.** A [WalkedPage] is evidence; identity is
///   `LibrarySourceWalk`'s, through `EntryReconciler`.
///
/// ## Where the user is asked
///
/// This is the file that *asks*, and it is the only one. `resolveNextPage`
/// decides that it does not know; the walk names the stop; the hold, the
/// judgement of what was tapped, and the second attempt with what was taught
/// all happen here — because asking needs the loaded page, the Source, and
/// where the walk has already been, and this is the only place all three are
/// in hand.
///
/// Three rules bind the asking, and each of them exists because the obvious
/// alternative is worse:
///
/// * **A tap is a candidate, never a decision.** What comes back from the
///   picker is judged before a rule is written — an address off the site, onto
///   a sign-in page, or back where the walk has been is refused with the reason
///   on screen, and the prompt stays open. Missing a small control on a phone
///   is ordinary; ending someone's run for it is not.
/// * **The rule is proved, not assumed.** Once written, it is re-applied to
///   the very page it was taught on. A locator that cannot find the element the
///   user just tapped would fail on every page after it too, and finding that
///   out now costs one call instead of one wasted run.
/// * **A control with no address is pressed, not followed.** A reader that
///   routes itself in script publishes no `href` to read, so the rule is
///   applied by activating the control and taking the address the page went
///   to. That is still the page's own assertion — nothing is constructed — and
///   it goes through every check a plain link goes through.
library;

import '../browser/browser_controller.dart';
import '../browser/page_data.dart';
import '../core/url_utils.dart';
import '../data/schema.dart';
import '../recognition/page_kind.dart';
import '../recognition/recognise.dart' show RecognitionKeys;
import '../recognition/walk.dart';
import '../save/capture_policy.dart';
import '../save/next_page.dart';
import '../save/page_hint.dart';
import '../save/page_hint_repository.dart';
import '../save/selection_request.dart';

/// Hold the walk while the user points at the next-entry control.
///
/// A function rather than the assist controller itself, so nothing on the walk
/// side imports a widget layer: what this file needs is *somebody who can ask*,
/// and `V2AssistController.ask` is one. Composition wires the real one in
/// (`features/v2_adoption_providers.dart`); a walk given none simply cannot
/// ask, which is the honest state on any surface with no Browser in front of
/// the user.
typedef NextControlAsk =
    Future<SelectionOutcome> Function(
      SelectionRequest request, {
      SelectionValidator? validate,
    });

/// How many times one page may re-ask before the walk gives up on it.
///
/// Each pass is a deliberate act by the user — a refused tap, or *Retry auto* —
/// so the bound is not about them changing their mind. It is about a page whose
/// rule can never be proved: without it a locator that writes cleanly and
/// re-matches nothing would reopen the picker for as long as the user kept
/// answering it.
const int kMaxNextControlAsks = 4;

/// How many times a page that looks finished is looked at before it is
/// believed, and how long is left between the looks.
///
/// Only the *end of a collection* is re-checked, and only ever on a page that
/// offered nothing at all — see the comment at the call site. Two extra looks
/// a little over a second apart is enough for a reader that mounts itself in
/// script, and costs a run nothing on any page that had an answer the first
/// time.
const int kEndOfChainLooks = 3;
const Duration kEndOfChainSettle = Duration(milliseconds: 700);

class BrowserForwardPageSource implements ForwardPageSource {
  BrowserForwardPageSource(this._browser, {this._hints, this.ask});

  final BrowserController _browser;

  /// The rules the user taught by pointing at a next control. Optional: a
  /// walk with no hint store simply has no saved rule to apply, which is the
  /// ordinary case on a site nobody has corrected.
  final PageHintRepository? _hints;

  /// Where a walk that cannot identify the next control holds. Null means it
  /// cannot ask, and it stops with [WalkStop.needsUserAssist] instead.
  final NextControlAsk? ask;

  @override
  Future<WalkedPage> read({
    required String url,
    required SourceRow source,
    required Set<String> visited,
    required bool Function() shouldContinue,
  }) async {
    if (!shouldContinue()) {
      return WalkedPage.unreadable(url: url, stop: WalkStop.cancelledByUser);
    }

    _browser.allowNextNavigation(url);
    await _browser.loadAndWait(url);
    final landed = _browser.currentUrl.isEmpty ? url : _browser.currentUrl;

    // The boundary only the navigator can own: where the reading LANDED.
    if (isCaptureRestricted(landed)) {
      return WalkedPage.unreadable(
        url: landed,
        stop: WalkStop.captureRestrictedForSite,
      );
    }
    if (!shouldContinue()) {
      return WalkedPage.unreadable(url: landed, stop: WalkStop.cancelledByUser);
    }

    final probe = await _browser.probe(withLinks: true);
    if (probe.readyState != 'complete' && probe.links.isEmpty) {
      return WalkedPage.unreadable(url: landed, stop: WalkStop.unreadable);
    }

    // Evidence, not identity: the number the page printed, read the one way
    // this app reads one — and read from **everything the probe already
    // carried**. `probe.pageHints` holds the page's own `h1`, its `og:title`
    // and its breadcrumb trail, which is where a great many sites print the
    // entry's number and its name; passing only the document title threw that
    // away one line before it was needed, and left every walked Entry
    // unnumbered and titled with the site's name appended.
    final shape = readPageShape(
      landed,
      pageTitle: probe.title,
      hints: probe.pageHints,
    );

    WalkedPage pageWith({String? nextUrl, UserPageHint? press}) => WalkedPage(
      url: landed,
      printedNumber: shape.printedNumber,
      // What the page called *this* entry, not what the browser tab said. A
      // document title is the entry's name with the work's and the site's
      // appended; the Entry's own row should not carry all three.
      title: shape.entryLabel ?? probe.title,
      nextUrl: nextUrl,
      resolveNext: press == null
          ? null
          : () => _pressForNext(press, source: source, visited: visited),
    );

    // The narrowest rule the user taught for this address, applied to the
    // settled document. A rule that matches nothing here contributes nothing —
    // it never becomes a guess — and it is counted as the failure it is, so the
    // rule the user fixes next wins the most-recently-used tie-break over it.
    final saved = await _hints?.findFor(landed, HintKind.nextLink);
    final match = saved == null
        ? null
        : await _browser.applyLocator(saved.locator.toJson());

    // A rule that is *pressed* must identify one control and no other. Prev and
    // Next are siblings that share a class, and a press has no address to check
    // afterwards, so a tie here is as likely to walk the run backwards as
    // forwards. An ambiguous press rule is therefore not a rule at all on this
    // page: it is treated as stale, and the user is asked again — which is what
    // the ambiguity check at teaching time does, applied on every later page
    // where the layout may have changed under it.
    final usable =
        match != null && match.isMatch && !(match.activate && match.ambiguous);
    final staleHint = saved != null && !usable ? saved : null;

    // Only a rule that is followed is counted here. A pressed one is counted
    // where it can actually be judged — matching a control says nothing about
    // whether pressing it moves the page, and counting it in both places
    // scored one use twice.
    if (saved != null && !(match?.activate ?? false)) {
      await _hints?.recordUse(saved.id, success: usable);
    } else if (staleHint != null) {
      await _hints?.recordUse(staleHint.id, success: false);
    }

    // A rule that is pressed cannot be resolved to an address by reading the
    // page. It is answered after this page has been captured — see
    // [WalkedPage.resolveNext].
    if (usable && match.activate) return pageWith(press: saved!);

    // Resolved from the probe in hand, and re-resolved on a fresher one before
    // the end of a collection is declared.
    //
    // **Why a page is read more than once.** A client-routed reader reports
    // `readyState: complete` for the shell it served and mounts its reader —
    // and with it the control that opens the next entry — some time after.
    // The first probe of such a page therefore shows neither a next link nor a
    // next control, which is indistinguishable from a collection that has
    // finished, and was read as one: the run stopped and said the site
    // publishes nothing further while entries were still to come.
    //
    // So *declaring the end* is the one answer this file will not give on a
    // first look. A page that already has an answer — a link to follow, or a
    // control to ask about — is used immediately and re-probed never; only the
    // silent one is looked at again, which is exactly where being wrong is
    // expensive.
    NextPageResult resolveOn(PageProbe p) => resolveNextPage(
      p,
      currentUrl: landed,
      visitedNormalized: visited,
      hintHref: usable ? match.href : null,
      // The walk *can* ask: `needsUserAssist` is one of its named stops, and
      // the user then points at the control once and the rule is kept. So an
      // ambiguous page must reach that stop rather than be walked past on a
      // best guess — "it stops rather than guesses" is the rule this whole
      // file serves.
    );

    var next = resolveOn(probe);
    for (
      var look = 1;
      look < kEndOfChainLooks && next.decision == NextDecision.endOfChain;
      look++
    ) {
      if (!shouldContinue()) {
        return WalkedPage.unreadable(
          url: landed,
          stop: WalkStop.cancelledByUser,
        );
      }
      await Future<void>.delayed(kEndOfChainSettle);
      try {
        next = resolveOn(await _browser.probe(withLinks: true));
      } catch (_) {
        // Mid-navigation, or the page went away. What was read stands.
        break;
      }
    }
    if (next.hasNext) return pageWith(nextUrl: next.chosen!.href);

    // Nothing followable. Ask only when the page itself says the sequence
    // continues — `resolveNextPage` reports `askUser` for a signal too weak to
    // act on *and* for a page whose Next is a control rather than a link. A
    // genuine end of chain is `endOfChain`, and it is answered with silence
    // rather than a prompt.
    if (!next.needsUserSelection) {
      // `endOfChain` is null nextUrl here, which the walk reads as the end of
      // what this Source publishes.
      return pageWith();
    }
    if (ask == null) {
      return WalkedPage.unreadable(url: landed, stop: WalkStop.needsUserAssist);
    }
    return _askForNextControl(
      first: next,
      staleHint: staleHint,
      landed: landed,
      source: source,
      visited: visited,
      shouldContinue: shouldContinue,
      pageWith: pageWith,
    );
  }

  // ─── holding for the user ──────────────────────────────────────────────

  /// Hold, judge what was tapped, prove the rule, and carry on with it.
  Future<WalkedPage> _askForNextControl({
    required NextPageResult first,
    required UserPageHint? staleHint,
    required String landed,
    required SourceRow source,
    required Set<String> visited,
    required bool Function() shouldContinue,
    required WalkedPage Function({String? nextUrl, UserPageHint? press})
    pageWith,
  }) async {
    WalkedPage held() =>
        WalkedPage.unreadable(url: landed, stop: WalkStop.needsUserAssist);

    var request = SelectionRequest(
      kind: HintKind.nextLink,
      sourceUrl: landed,
      prompt: 'Show the app the next-entry control',
      reason: staleHint != null
          ? 'the rule you taught for this site no longer matches this page'
          : first.reason,
      candidates: first.considered,
      isHintFailure: staleHint != null,
      failedHintId: staleHint?.id,
    );

    for (var attempt = 0; attempt < kMaxNextControlAsks; attempt++) {
      if (!shouldContinue()) {
        return WalkedPage.unreadable(
          url: landed,
          stop: WalkStop.cancelledByUser,
        );
      }

      final outcome = await ask!(
        request,
        validate: (element) async => _refusalFor(
          element,
          landed: landed,
          source: source,
          visited: visited,
        ),
      );

      // Nothing was taught, so there is nothing new to try. The walk keeps the
      // stop it already had, and everything it resolved stays resolved.
      if (outcome.cancelled) return held();

      if (outcome.retryAutomatic) {
        // Detection again with no rule in the way, including the one that just
        // stopped matching. A page that is still ambiguous is asked about
        // again rather than guessed at.
        final retry = resolveNextPage(
          await _browser.probe(withLinks: true),
          currentUrl: landed,
          visitedNormalized: visited,
        );
        if (retry.hasNext) return pageWith(nextUrl: retry.chosen!.href);
        if (!retry.needsUserSelection) return pageWith();
        request = SelectionRequest(
          kind: HintKind.nextLink,
          sourceUrl: landed,
          prompt: request.prompt,
          reason: retry.reason,
          candidates: retry.considered,
        );
        continue;
      }

      final rule = outcome.rule;
      if (rule == null) return held();

      // **The rule is proved, not assumed**: re-applied to the page it was
      // taught on. What is checked is the rule, not the tap — the locator may
      // match a different element than the finger did, and a rule that cannot
      // find the control on the page it was born on will not find it on the
      // next one either.
      final proof = await _proveOnThisPage(
        rule,
        landed: landed,
        source: source,
        visited: visited,
      );
      if (proof.refusal == null) {
        // The rule the page stopped matching is gone, replaced by the one the
        // user just pointed at.
        if (staleHint != null) await _hints?.delete(staleHint.id);
        return rule.locator.activate
            ? pageWith(press: rule)
            : pageWith(nextUrl: proof.href);
      }

      // A rule that cannot be proved is not kept: leaving it would answer this
      // page wrongly and confidently on every future run, which is worse than
      // having no rule at all.
      await _hints?.delete(rule.id);
      request = request.withError(proof.refusal!);
    }
    return held();
  }

  /// Why this tapped element cannot be used, or null when it can.
  ///
  /// Runs before a rule exists, so a refusal costs the user one more tap and
  /// nothing else. The order is by how cheap the answer is.
  Future<String?> _refusalFor(
    SelectedElement element, {
    required String landed,
    required SourceRow source,
    required Set<String> visited,
  }) async {
    if (nextControlMustBePressed(href: element.href, currentUrl: landed)) {
      // A control with no usable address. It can still be taught — it is
      // pressed rather than followed — but only if there is enough about it to
      // find again, and only if it is a control at all.
      const pressable = {'a', 'button', 'summary', 'input'};
      final tag = element.tag.toLowerCase();
      final looksLikeControl =
          pressable.contains(tag) ||
          element.ariaLabel.isNotEmpty ||
          element.title.isNotEmpty;
      if (!looksLikeControl) {
        return 'That is not a control this app can press. Tap the button or '
            'link that opens the next entry.';
      }
      if (_signalsFor(element) == 0) {
        return 'There is nothing about that element to recognise it by later — '
            'no label, no name and no stable class. Try the control itself '
            'rather than the space around it.';
      }
      return null;
    }

    final check = validateNextUrl(
      candidate: element.href,
      currentUrl: landed,
      visited: visited,
    );
    if (!check.isAccepted) {
      return switch (check.rejection!) {
        NextUrlRejection.differentHost =>
          'That opens ${hostOf(element.href)}, which is a different site. Pick '
              'the control that stays on this one.',
        NextUrlRejection.denyListed =>
          'That leads to a sign-in or account page, not to the next entry.',
        NextUrlRejection.alreadyVisited =>
          'That opens an entry this download has already been through, so it '
              'would go round in a circle.',
        NextUrlRejection.unsupportedScheme ||
        NextUrlRejection.unparseable => 'That is not a page this app can open.',
        // Handled above as a control to press rather than a link to follow.
        NextUrlRejection.sameAsCurrent =>
          'That opens the page you are already on.',
      };
    }

    // On this Source, judged the one way the library judges it. A link to
    // another work on the same site passes every check above and is still the
    // wrong answer.
    if (!_isOnSource(check.normalized!, source)) {
      return 'That leads somewhere else on this site, not to the next entry '
          'of this collection.';
    }
    return null;
  }

  /// Apply the stored rule to the page it was taught on, and say why not.
  ///
  /// Returns the address it proved the rule leads to, for a rule that is
  /// followed — applied once, here, rather than matched to judge it and
  /// matched again to use it.
  Future<({String? refusal, String? href})> _proveOnThisPage(
    UserPageHint rule, {
    required String landed,
    required SourceRow source,
    required Set<String> visited,
  }) async {
    ({String? refusal, String? href}) no(String why) =>
        (refusal: why, href: null);

    final match = await _browser.applyLocator(rule.locator.toJson());
    if (match == null || !match.isMatch) {
      final why = match?.failureReason;
      return no(
        'That control could not be described in a way this app can find again'
        '${why == null ? '' : ' ($why)'}. Try a control with a label on it.',
      );
    }
    if (rule.locator.activate) {
      // A press has no address to check afterwards, so ambiguity has to be
      // fatal here: Prev and Next are siblings that share a class, and pressing
      // whichever scored first is as likely to go backwards as forwards.
      if (match.ambiguous) {
        return no(
          'That control looks the same to the app as another one beside it, '
          'so pressing it could go backwards. Try the one with its own label.',
        );
      }
      return (refusal: null, href: null);
    }

    final check = validateNextUrl(
      candidate: match.href,
      currentUrl: landed,
      visited: visited,
    );
    if (!check.isAccepted) {
      return no(
        'The rule matched a different link on this page, going to '
        '${match.href}. Try again on the control itself.',
      );
    }
    if (!_isOnSource(check.normalized!, source)) {
      return no(
        'The rule matched a link leading elsewhere on this site. Try again on '
        'the control itself.',
      );
    }
    return (refusal: null, href: check.normalized);
  }

  // ─── pressing a control that carries no address ────────────────────────

  /// Press the taught control and take the address the page went to.
  ///
  /// Called after the entry on this page has been captured, because pressing
  /// moves the browser off it. Everything the page does in response is judged
  /// afterwards by the walk exactly as a link's destination would be; the only
  /// judgement here is whether the press achieved anything at all.
  Future<NextStep> _pressForNext(
    UserPageHint rule, {
    required SourceRow source,
    required Set<String> visited,
  }) async {
    final press = await _browser.activateLocator(rule.locator.toJson());

    // The site switched its own next control off. The rule did its job — it
    // found the control — and what the control says is that this is the last
    // entry. That is the collection finishing, not the run failing, and the
    // two are never reported as the same outcome.
    if (press.atEndOfChain) {
      await _hints?.recordUse(rule.id, success: true);
      return const NextStep.endOfSource();
    }

    final landedNext = press.url;
    if (landedNext == null || landedNext.trim().isEmpty) {
      await _hints?.recordUse(rule.id, success: false);
      return const NextStep.ended(WalkStop.noForwardProgress);
    }
    if (visited.contains(normalizeUrl(landedNext))) {
      await _hints?.recordUse(rule.id, success: false);
      return const NextStep.ended(WalkStop.noForwardProgress);
    }
    await _hints?.recordUse(rule.id, success: true);
    return NextStep.address(landedNext);
  }

  // ─── small judgements ──────────────────────────────────────────────────

  /// How many independent things there are to recognise this element by later.
  int _signalsFor(SelectedElement element) => [
    element.rel,
    element.selector ?? '',
    element.containerSelector ?? '',
    element.text,
    element.ariaLabel,
    element.title,
    element.imgAlt,
  ].where((s) => s.trim().isNotEmpty).length;

  /// Whether an address is published by *this* Source: the same `(host,
  /// path_key)` identity the library keys a Source by, derived by the one
  /// derivation there is. The same test `LibrarySourceWalk` applies to a
  /// landed address, applied here to a candidate so the user is told at the
  /// moment they tap rather than after a page load.
  bool _isOnSource(String url, SourceRow source) {
    final keys = RecognitionKeys.of(url);
    return keys.host == source.host && keys.pathKey == source.pathKey;
  }
}
