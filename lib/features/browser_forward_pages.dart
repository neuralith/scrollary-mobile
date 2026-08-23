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
library;

import '../browser/browser_controller.dart';
import '../data/schema.dart';
import '../recognition/page_kind.dart';
import '../recognition/walk.dart';
import '../save/capture_policy.dart';
import '../save/next_page.dart';
import '../save/page_hint.dart';
import '../save/page_hint_repository.dart';

class BrowserForwardPageSource implements ForwardPageSource {
  BrowserForwardPageSource(this._browser, {this._hints});

  final BrowserController _browser;

  /// The rules the user taught by pointing at a next control. Optional: a
  /// walk with no hint store simply has no saved rule to apply, which is the
  /// ordinary case on a site nobody has corrected.
  final PageHintRepository? _hints;

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

    final next = resolveNextPage(
      probe,
      currentUrl: landed,
      visitedNormalized: visited,
      hintHref: await _savedNextHref(landed),
      // The walk *can* ask: `needsUserAssist` is one of its named stops, and
      // the user then points at the control once and the rule is kept. So an
      // ambiguous page must reach that stop rather than be walked past on a
      // best guess — "it stops rather than guesses" is the rule this whole
      // file serves.
    );
    if (next.needsUserSelection) {
      return WalkedPage.unreadable(url: landed, stop: WalkStop.needsUserAssist);
    }

    return WalkedPage(
      url: landed,
      printedNumber: shape.printedNumber,
      // What the page called *this* entry, not what the browser tab said. A
      // document title is the entry's name with the work's and the site's
      // appended; the Entry's own row should not carry all three.
      title: shape.entryLabel ?? probe.title,
      // `endOfChain` is null here, which the walk reads as the end of what
      // this Source publishes.
      nextUrl: next.hasNext ? next.chosen!.href : null,
    );
  }

  /// The href a rule the user taught points at on *this* page, or null.
  ///
  /// Resolved exactly as the save engine resolves it: the stored locator is
  /// applied to the settled document, and what it matched is offered to
  /// `resolveNextPage` as the highest-trust candidate. A rule that matches
  /// nothing here contributes nothing — it never becomes a guess.
  Future<String?> _savedNextHref(String landedUrl) async {
    final hint = await _hints?.findFor(landedUrl, HintKind.nextLink);
    if (hint == null) return null;
    final match = await _browser.applyLocator(hint.locator.toJson());
    if (match == null || !match.isMatch) return null;
    return match.href;
  }
}
