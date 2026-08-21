import 'package:web_reader/browser/page_data.dart';

import 'fake_browser.dart';

/// A [FakeBrowser] whose probes are computed per call — enough control to
/// script an unrendered surface (zero viewport), a page that loads panel by
/// panel, or one whose layout is torn down mid-save.
class ScriptedBrowser extends FakeBrowser {
  ScriptedBrowser({required this.probeBuilder});

  /// Called with the current scroll position and how many probes have been
  /// answered so far.
  PageProbe Function(int y, int probeCount) probeBuilder;

  /// Every dy passed to [scrollStep], in order.
  final List<int> scrollSteps = [];

  /// How many probes asked for the expensive signal half. The traversal loop
  /// must never be one of them.
  int fullSignalProbes = 0;

  /// When false, scroll commands do not move the position (frozen page).
  bool scrollMoves = true;

  int y = 0;
  int probeCount = 0;

  @override
  Future<PageProbe> probe({
    bool withLinks = false,
    bool withSignals = true,
  }) async {
    probeCount++;
    if (withLinks || withSignals) fullSignalProbes++;
    return probeBuilder(y, probeCount);
  }

  @override
  Future<Map<String, dynamic>> scrollStep(int dy) async {
    scrollSteps.add(dy);
    if (scrollMoves) {
      final probe = probeBuilder(y, probeCount);
      final maxY = probe.documentHeight - probe.viewportHeight;
      y = (y + dy).clamp(0, maxY < 0 ? 0 : maxY);
    }
    return const {};
  }

  @override
  Future<void> scrollTo(int target) async {
    if (scrollMoves) y = target < 0 ? 0 : target;
  }
}

/// A page of [panelCount] tall panels; panels whose top edge is above
/// `loadedUpTo` are resolved, the rest pending — a plain lazy-loading strip.
///
/// Set [unmeasuredWhilePending] for the harsher lazy loader: a panel that has
/// not loaded yet has no intrinsic size, no `height` attribute and **no
/// reserved height** — the page has not laid out a box for it. Its measurable
/// height is therefore 0, which the traversal predicate must read as "unknown,
/// therefore relevant" rather than as "too small". (Zero on *both* edges is a
/// 0x0 element, which the bridge already reports as hidden; that case is
/// covered directly in `image_candidates_test.dart`.)
PageProbe lazyStripProbe({
  required int y,
  required int viewportHeight,
  int panelCount = 10,
  int panelWidth = 800,
  int panelHeight = 2000,
  int? loadedUpTo,
  bool unmeasuredWhilePending = false,
  String url = 'https://x.example/guide/foo/1',
  String title = 'Foo Entry 1',
  String? nextHref,
  int? documentHeightOverride,
  List<PageImage> extraImages = const [],
}) {
  final docHeight = documentHeightOverride ?? panelCount * panelHeight;
  final resolvedBelow = loadedUpTo ?? docHeight;
  return PageProbe(
    url: url,
    title: title,
    readyState: 'complete',
    documentHeight: docHeight,
    viewportHeight: viewportHeight,
    scrollY: y,
    atBottom: viewportHeight > 0 && y + viewportHeight >= docHeight - 8,
    images: [
      for (var i = 0; i < panelCount; i++)
        if (i * panelHeight < resolvedBelow)
          PageImage(
            domIndex: i,
            src: 'https://cdn.example/p/$i.png',
            currentSrc: 'https://cdn.example/p/$i.png',
            complete: true,
            naturalWidth: panelWidth,
            naturalHeight: panelHeight,
            renderedWidth: 390,
            renderedHeight: 975,
            documentTop: i * panelHeight,
          )
        else
          PageImage(
            domIndex: i,
            src: 'https://cdn.example/p/$i.png',
            currentSrc: 'https://cdn.example/p/$i.png',
            complete: false,
            renderedWidth: 390,
            renderedHeight: unmeasuredWhilePending ? 0 : 975,
            documentTop: i * panelHeight,
          ),
      ...extraImages,
    ],
    links: [
      if (nextHref != null)
        PageLink(href: nextHref, rel: 'next', text: 'Next Entry'),
    ],
  );
}

/// A small avatar-like image (comment section): tiny rendered box, never
/// finishes loading unless [complete].
PageImage avatarImage(int index, {bool complete = false}) => PageImage(
  domIndex: 100 + index,
  src: 'https://cdn.example/avatar/$index.webp',
  currentSrc: 'https://cdn.example/avatar/$index.webp',
  complete: complete,
  naturalWidth: complete ? 538 : 0,
  naturalHeight: complete ? 539 : 0,
  renderedWidth: 40,
  renderedHeight: 40,
  documentTop: 999999,
);

/// A 300x250 advertisement slot, parked at [documentTop] in the flow of the
/// page — **not** in `<header>`/`<footer>`/`<nav>`/`<aside>`, so the chrome
/// flag does not save us, and never finishing loading.
///
/// The shape matters. An avatar is obviously irrelevant at 40x40; this is the
/// case that defeats a naive size test, because its width alone clears a
/// loosened floor and only its height gives it away. It is the fixture the
/// regression is really about: four of these turned a four-second traversal
/// into a sixty-four-second one.
PageImage adSlotImage(
  int index, {
  required int documentTop,
  bool complete = false,
  int width = 300,
  int height = 250,
}) => PageImage(
  domIndex: 300 + index,
  src: 'https://ads.example/slot/$index.gif',
  currentSrc: 'https://ads.example/slot/$index.gif',
  complete: complete,
  naturalWidth: complete ? width : 0,
  naturalHeight: complete ? height : 0,
  renderedWidth: width,
  renderedHeight: height,
  documentTop: documentTop,
);
