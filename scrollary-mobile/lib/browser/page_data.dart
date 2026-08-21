/// Plain models for what the JavaScript bridge reports about a page.
/// No Flutter, no plugin types — so the save heuristics that consume these
/// are unit testable against literal fixtures.
library;

import '../library/collection_identity.dart';

class PageImage {
  const PageImage({
    required this.domIndex,
    this.src,
    this.currentSrc,
    this.dataSrc,
    this.complete = false,
    // True by default, matching [PageImage.fromJson]'s treatment of a probe
    // that predates the flag: "this element has an address" is the ordinary
    // case, and the alternative default would quietly turn every fixture that
    // does not mention it into an image the engine waits forever for.
    this.hasSource = true,
    this.naturalWidth = 0,
    this.naturalHeight = 0,
    this.renderedWidth = 0,
    this.renderedHeight = 0,
    this.attrWidth = 0,
    this.attrHeight = 0,
    this.documentTop = 0,
    this.hidden = false,
    this.inPageChrome = false,
    this.className = '',
    this.alt = '',
  });

  factory PageImage.fromJson(Map<String, dynamic> json) => PageImage(
    domIndex: _int(json['index']),
    src: _str(json['src']),
    currentSrc: _str(json['currentSrc']),
    dataSrc: _str(json['dataSrc']),
    complete: json['complete'] == true,
    // Absent on a probe from an older bridge. Defaulting to **true** keeps
    // that case on the previous behaviour (complete + no pixels reads as
    // broken) rather than silently reclassifying every failed image as
    // "not tried yet", which would make the engine wait for the dead.
    hasSource: json['hasSource'] == null || json['hasSource'] == true,
    naturalWidth: _int(json['naturalWidth']),
    naturalHeight: _int(json['naturalHeight']),
    renderedWidth: _int(json['renderedWidth']),
    renderedHeight: _int(json['renderedHeight']),
    attrWidth: _int(json['attrWidth']),
    attrHeight: _int(json['attrHeight']),
    documentTop: _int(json['top']),
    hidden: json['hidden'] == true,
    inPageChrome: json['chrome'] == true,
    className: json['className']?.toString() ?? '',
    alt: json['alt']?.toString() ?? '',
  );

  final int domIndex;
  final String? src;
  final String? currentSrc;
  final String? dataSrc;
  final bool complete;

  /// The element has an address to load: a non-empty `src`, a `srcset`, or a
  /// `currentSrc` the browser has already selected (which is how `<picture>`
  /// carries one).
  ///
  /// Needed because `complete` cannot stand alone. HTML §img.complete is true
  /// when **both** `src` and `srcset` are omitted, exactly as it is true for a
  /// finished load and for a failed one — and `naturalWidth` is 0 for the
  /// failed case *and* the never-tried case. Without this flag a lazy image
  /// waiting for its loader is indistinguishable from a dead one.
  final bool hasSource;
  final int naturalWidth;
  final int naturalHeight;
  final int renderedWidth;
  final int renderedHeight;

  /// The `width`/`height` HTML attributes. The last resort for sizing an image
  /// that never loaded — without them a broken panel looks like a 0x0 icon and
  /// gets silently filtered out, which is how an entry loses a page and still
  /// reports success.
  final int attrWidth;
  final int attrHeight;
  final int documentTop;
  final bool hidden;

  /// Inside <header>, <footer>, <nav> or <aside>.
  final bool inPageChrome;
  final String className;
  final String alt;

  /// The URL the browser actually settled on, preferring `currentSrc` because
  /// it is the post-`srcset`/media-query resolution. Falls back to a lazy
  /// attribute for images that have not been swapped in yet.
  String? get effectiveUrl {
    for (final candidate in [currentSrc, src, dataSrc]) {
      if (candidate == null) continue;
      final t = candidate.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('data:')) continue;
      return t;
    }
    return null;
  }

  /// Intrinsic size when known, then the **declared** attributes, then the
  /// laid-out box.
  ///
  /// The attribute comes before the rendered box on purpose: `width="800"` is
  /// an intrinsic-basis declaration, while the rendered box is post-CSS layout
  /// (a 800px panel renders at ~390 logical px on a phone). Preferring the
  /// rendered box mixed the two bases, so a broken panel measured 390 against
  /// loaded panels measuring 800 and got discarded as "outside the content
  /// column" — silently shrinking the entry by a page.
  int get effectiveWidth => naturalWidth > 0
      ? naturalWidth
      : (attrWidth > 0 ? attrWidth : renderedWidth);
  int get effectiveHeight => naturalHeight > 0
      ? naturalHeight
      : (attrHeight > 0 ? attrHeight : renderedHeight);

  /// Loaded and decodable.
  bool get isResolved => complete && naturalWidth > 0 && naturalHeight > 0;

  /// Nothing has been asked for yet: a lazy image whose real address is still
  /// parked in an attribute, or one waiting for script to set `src`.
  ///
  /// **Not** a terminal state, and that is the whole point. Treating it as one
  /// let the adaptive lookahead — which ignores broken images — jump straight
  /// over a region whose panels had never been switched on, so the loader that
  /// would have produced them never fired.
  bool get isUnrequested => !hasSource;

  /// Asked for, finished, and produced no pixels — a genuine failure.
  ///
  /// [hasSource] is what makes this terminal rather than merely "no pixels
  /// yet". A broken image stays a candidate so its download fails out loud and
  /// the entry is marked partial; waiting for it would only spend the timeout.
  bool get isBroken => hasSource && complete && naturalWidth == 0;

  /// Asked for and still arriving.
  bool get isPending => hasSource && !complete;

  /// Not yet content: still coming, or never started. Either way the page has
  /// more to give here, so traversal must not treat this position as settled.
  bool get isUnsettled => !isResolved && !isBroken;
}

class PageLink {
  const PageLink({
    required this.href,
    this.rel = '',
    this.text = '',
    this.ariaLabel = '',
    this.title = '',
    this.className = '',
    this.id = '',
    this.imgAlt = '',
    this.inNav = false,
    this.documentTop = 0,
  });

  factory PageLink.fromJson(Map<String, dynamic> json) => PageLink(
    href: json['href']?.toString() ?? '',
    rel: json['rel']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    ariaLabel: json['ariaLabel']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    className: json['className']?.toString() ?? '',
    id: json['id']?.toString() ?? '',
    imgAlt: json['imgAlt']?.toString() ?? '',
    inNav: json['inNav'] == true,
    documentTop: _int(json['top']),
  );

  final String href;
  final String rel;
  final String text;
  final String ariaLabel;
  final String title;
  final String className;
  final String id;

  /// `alt` of an image inside the link — many "next" controls are icons.
  final String imgAlt;
  final bool inNav;
  final int documentTop;
}

/// Structural description of a page: how much prose, how much image area, does
/// it declare an article, does it carry a date, does it have real pagination.
///
/// Deliberately contains no subject matter and no genre. Every field is a
/// measurement or a standard HTML semantic, which is what lets one detector read
/// a blog post, a documentation page and an image gallery without knowing
/// anything about any website.
class PageContentSignals {
  const PageContentSignals({
    this.textLength = 0,
    this.paragraphCount = 0,
    this.headingCount = 0,
    this.contentImageCount = 0,
    this.contentImagePixels = 0,
    this.contentRegionImageCount = 0,
    this.contentRegionImagePixels = 0,
    this.hasArticleElement = false,
    this.hasMainElement = false,
    this.publishedAt,
    this.hasRelPrev = false,
    this.pagerNumbers = const [],
    this.listedDates = const [],
    this.headingText = '',
  });

  factory PageContentSignals.fromJson(Map<String, dynamic> json) =>
      PageContentSignals(
        textLength: _int(json['textLength']),
        paragraphCount: _int(json['paragraphCount']),
        headingCount: _int(json['headingCount']),
        contentImageCount: _int(json['contentImageCount']),
        contentImagePixels: _int(json['contentImagePixels']),
        contentRegionImageCount: _int(json['contentRegionImageCount']),
        contentRegionImagePixels: _int(json['contentRegionImagePixels']),
        hasArticleElement: json['hasArticleElement'] == true,
        hasMainElement: json['hasMainElement'] == true,
        publishedAt: _date(json['publishedAt']),
        hasRelPrev: json['hasRelPrev'] == true,
        pagerNumbers: ((json['pagerNumbers'] as List<dynamic>?) ?? const [])
            .map(_int)
            .where((n) => n > 0)
            .toList(),
        listedDates: ((json['listedDates'] as List<dynamic>?) ?? const [])
            .map(_date)
            .whereType<DateTime>()
            .toList(),
        headingText: json['headingText']?.toString().trim() ?? '',
      );

  /// Characters of visible prose in the main content region.
  final int textLength;
  final int paragraphCount;

  /// Headings inside the readable region. Structure, not decoration: a page
  /// with prose *and* headings is a document, which is what separates an
  /// article from a long run of link text.
  final int headingCount;

  /// Images big enough to be content rather than chrome, anywhere on the page,
  /// and their total area.
  final int contentImageCount;
  final int contentImagePixels;

  /// Images that sit **inside the readable region** and are big enough to
  /// matter. Deliberately narrower than [contentImageCount]: a sidebar full of
  /// recommendation thumbnails raises that count and must not make a page look
  /// like it has illustrations worth saving between its paragraphs.
  final int contentRegionImageCount;
  final int contentRegionImagePixels;

  final bool hasArticleElement;
  final bool hasMainElement;

  /// Publication date, only from a standard declaration (`<time datetime>`,
  /// article metadata, JSON-LD). Never guessed from a URL.
  final DateTime? publishedAt;

  /// A declared previous-page relationship. With `rel=next` this is what makes a
  /// sequence *explicit* rather than inferred.
  final bool hasRelPrev;

  /// Numbers found inside a pagination control. A range here is the only thing
  /// that justifies calling something a "page".
  final List<int> pagerNumbers;

  /// Dates attached to repeated sibling items — the signature of a feed.
  final List<DateTime> listedDates;

  final String headingText;

  /// Share of the page that is image, by rough area. Compared against prose
  /// rather than used alone: a long article with one big photo is not
  /// image-dominant.
  bool get looksImageDominant =>
      contentImageCount >= 2 && textLength < 900 && contentImagePixels > 400000;

  bool get looksProse => textLength >= 900 && paragraphCount >= 3;
}

/// Audio and video the app deliberately does not save.
///
/// **Geometry only.** These fields describe how much of the page a player
/// occupies and whether it sits in the readable region — enough to say "this
/// page is a video, and this app does not save video" honestly. Nothing here
/// is, or may become, a media URL: no `src`, no manifest address, no iframe
/// contents. Adding one would turn a classification signal into the first half
/// of a downloader.
class PageMediaSignals {
  const PageMediaSignals({
    this.videoCount = 0,
    this.audioCount = 0,
    this.primaryVideoPixels = 0,
    this.videoInContentRegion = false,
  });

  factory PageMediaSignals.fromJson(Map<String, dynamic> json) =>
      PageMediaSignals(
        videoCount: _int(json['videoCount']),
        audioCount: _int(json['audioCount']),
        primaryVideoPixels: _int(json['primaryVideoPixels']),
        videoInContentRegion: json['videoInContentRegion'] == true,
      );

  final int videoCount;
  final int audioCount;

  /// Laid-out area of the **largest** player, in CSS pixels. One big player is
  /// a video page; a grid of small ones is a listing, and a 200×112 preview in
  /// a sidebar is neither.
  final int primaryVideoPixels;

  /// The largest player sits inside the page's readable region rather than in
  /// a header, sidebar or footer. An advertisement in the chrome is not what
  /// the page is about.
  final bool videoInContentRegion;

  bool get hasMedia => videoCount > 0 || audioCount > 0;
  int get total => videoCount + audioCount;
}

/// Signals that automatic continuation must stop.
///
/// Detection only. Nothing in the app attempts, works around, or retries past
/// any of these; the run stops and names which one it hit.
class PageAccessSignals {
  const PageAccessSignals({
    this.hasPasswordField = false,
    this.hasLoginForm = false,
    this.hasCaptchaWidget = false,
    this.hasPaywallMarker = false,
    this.deniedPhrase,
    this.ratePhrase,
    this.paywallPhrase,
    this.authPhrase,
    this.isEmptyDocument = false,
  });

  factory PageAccessSignals.fromJson(Map<String, dynamic> json) =>
      PageAccessSignals(
        hasPasswordField: json['hasPasswordField'] == true,
        hasLoginForm: json['hasLoginForm'] == true,
        hasCaptchaWidget: json['hasCaptchaWidget'] == true,
        hasPaywallMarker: json['hasPaywallMarker'] == true,
        deniedPhrase: _str(json['deniedPhrase']),
        ratePhrase: _str(json['ratePhrase']),
        paywallPhrase: _str(json['paywallPhrase']),
        authPhrase: _str(json['authPhrase']),
        isEmptyDocument: json['isEmptyDocument'] == true,
      );

  /// Structural: an actual input or widget is present.
  final bool hasPasswordField;
  final bool hasLoginForm;
  final bool hasCaptchaWidget;
  final bool hasPaywallMarker;

  /// Phrase hints. The weakest signal available, and used only to corroborate a
  /// structural one or an empty document — a page that merely *mentions*
  /// "subscribe to continue" in a footer is not a paywall.
  final String? deniedPhrase;
  final String? ratePhrase;
  final String? paywallPhrase;
  final String? authPhrase;

  /// Almost no visible text. On its own this is a load failure; combined with a
  /// phrase hint it is a gate.
  final bool isEmptyDocument;
}

/// One snapshot of the page, taken between scroll steps.
class PageProbe {
  const PageProbe({
    required this.url,
    required this.title,
    this.canonicalUrl,
    this.readyState = '',
    this.documentHeight = 0,
    this.viewportHeight = 0,
    this.viewportWidth = 0,
    this.pageHidden = false,
    this.scrollY = 0,
    this.images = const [],
    this.links = const [],
    this.headNextHref,
    this.atBottom = false,
    this.imagesTruncated = false,
    this.imageCount = 0,
    this.imageOffset = 0,
    this.pageHints = const PageHints(),
    this.content = const PageContentSignals(),
    this.media = const PageMediaSignals(),
    this.access = const PageAccessSignals(),
  });

  factory PageProbe.fromJson(Map<String, dynamic> json) => PageProbe(
    url: json['url']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    canonicalUrl: _str(json['canonicalUrl']),
    readyState: json['readyState']?.toString() ?? '',
    documentHeight: _int(json['documentHeight']),
    viewportHeight: _int(json['viewportHeight']),
    viewportWidth: _int(json['viewportWidth']),
    pageHidden: json['pageHidden'] == true,
    scrollY: _int(json['scrollY']),
    images: (json['images'] as List<dynamic>? ?? const [])
        .map((e) => PageImage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    links: (json['links'] as List<dynamic>? ?? const [])
        .map((e) => PageLink.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    headNextHref: _str(json['headNextHref']),
    atBottom: json['atBottom'] == true,
    imagesTruncated: json['imagesTruncated'] == true,
    imageCount: _int(json['imageCount']),
    imageOffset: _int(json['imageOffset']),
    pageHints: json['pageHints'] is Map
        ? PageHints.fromJson(
            Map<String, dynamic>.from(json['pageHints'] as Map),
          )
        : const PageHints(),
    content: json['content'] is Map
        ? PageContentSignals.fromJson(
            Map<String, dynamic>.from(json['content'] as Map),
          )
        : const PageContentSignals(),
    media: json['media'] is Map
        ? PageMediaSignals.fromJson(
            Map<String, dynamic>.from(json['media'] as Map),
          )
        : const PageMediaSignals(),
    access: json['access'] is Map
        ? PageAccessSignals.fromJson(
            Map<String, dynamic>.from(json['access'] as Map),
          )
        : const PageAccessSignals(),
  );

  final String url;
  final String title;
  final String? canonicalUrl;
  final String readyState;
  final int documentHeight;
  final int viewportHeight;

  /// Viewport width, so an element's area can be compared against the screen's.
  /// Zero on a probe taken by an older bridge, which every ratio test guards
  /// against rather than dividing by.
  final int viewportWidth;

  /// The page says it is not being shown (`document.visibilityState`).
  ///
  /// A **hold** signal, never a liveness proof. Measured on both platforms
  /// (docs/FOREGROUND_MULTITASKING.md §3.1): a WebView the app has stopped
  /// painting reports `hidden` on iOS and `visible` on Android, so `true` here
  /// means "definitely not being shown" while `false` means nothing at all.
  /// Whether the app is painting its WebView is answered by
  /// [BrowserController.surfaceIsPainted], not from inside the page.
  final bool pageHidden;
  final int scrollY;

  /// Laid-out viewport area, or 0 when it could not be measured.
  int get viewportArea => viewportWidth <= 0 || viewportHeight <= 0
      ? 0
      : viewportWidth * viewportHeight;
  final List<PageImage> images;
  final List<PageLink> links;

  /// `<link rel="next">` from the document head, if present.
  final String? headNextHref;
  final bool atBottom;

  /// This probe's image list stops short of the end of the page's collection.
  /// Reported so a truncated save is never mistaken for a complete one.
  final bool imagesTruncated;

  /// How many `<img>` elements the page holds **in total**, independent of how
  /// many this probe returned. Without it Dart could not tell how much of the
  /// page it was looking at.
  final int imageCount;

  /// Where this probe's slice starts in that collection.
  final int imageOffset;

  /// What the page says about the collection this entry belongs to. Only
  /// populated when the probe was asked for links.
  final PageHints pageHints;

  /// Structure, media and access signals. Defaults are all "nothing detected",
  /// so a probe taken by an older bridge degrades to "unknown content" rather
  /// than to a confident wrong answer.
  final PageContentSignals content;
  final PageMediaSignals media;
  final PageAccessSignals access;

  bool get domReady => readyState == 'interactive' || readyState == 'complete';

  /// Images still in flight. A **broken** image is not pending — it has
  /// finished, badly. Counting it as pending made the scroll loop wait for
  /// something that would never arrive, until it hit the iteration bound.
  ///
  /// An **unrequested** image is not pending either: nothing is on the wire,
  /// so no amount of waiting produces it. Only scrolling to it does, which is
  /// why it is the *lookahead* that has to see it and not this count.
  int get pendingImageCount => images
      .where((i) => i.effectiveUrl != null && !i.hidden && i.isPending)
      .length;

  /// Images that finished loading with an error.
  int get brokenImageCount => images
      .where((i) => i.effectiveUrl != null && !i.hidden && i.isBroken)
      .length;

  /// Images whose real address has not been switched on yet.
  int get unrequestedImageCount =>
      images.where((i) => !i.hidden && i.isUnrequested).length;

  int get resolvedImageCount => images.where((i) => i.isResolved).length;

  // "Nothing changed since the last probe" is deliberately **not** a getter
  // here. It needs the save's own idea of which images could be entry content,
  // which needs `SaveConfig` — and a page model that reached for save
  // configuration would be the wrong shape. It lives in
  // `save/page_stability.dart` instead, as a pure function over this class.
}

/// One emphasis range as the page reported it.
class RawInlineMark {
  const RawInlineMark({
    required this.start,
    required this.end,
    required this.style,
  });

  factory RawInlineMark.fromJson(Map<String, dynamic> json) => RawInlineMark(
    start: _int(json['start']),
    end: _int(json['end']),
    style: json['style']?.toString() ?? '',
  );

  final int start;
  final int end;
  final String style;
}

/// One candidate document block, exactly as the page reported it — **before**
/// any decision about whether to keep it.
///
/// The split matters. Only a browser can answer "is this element visible" and
/// "does it sit inside a `<nav>`", so the JavaScript half measures and flags.
/// Everything that is a *judgement* — is this long enough, is this image big
/// enough, does this heading survive, what order do the survivors get — is
/// Dart, for the same reason `content_detection.dart` is: a rule that decides
/// what a user's saved copy contains has to be testable against a literal
/// fixture rather than only through a live WebView.
class RawDocumentBlock {
  const RawDocumentBlock({
    required this.kind,
    this.text = '',
    this.level = 0,
    this.ordered = false,
    this.src,
    this.alt = '',
    this.width = 0,
    this.height = 0,
    this.inChrome = false,
    this.hidden = false,
    this.marks = const [],
  });

  factory RawDocumentBlock.fromJson(Map<String, dynamic> json) =>
      RawDocumentBlock(
        kind: json['kind']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        level: _int(json['level']),
        ordered: json['ordered'] == true,
        src: _str(json['src']),
        alt: json['alt']?.toString() ?? '',
        width: _int(json['width']),
        height: _int(json['height']),
        inChrome: json['chrome'] == true,
        hidden: json['hidden'] == true,
        marks: ((json['marks'] as List<dynamic>?) ?? const [])
            .map(
              (e) =>
                  RawInlineMark.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
      );

  /// `heading` · `paragraph` · `quote` · `listItem` · `separator` · `image`.
  /// A kind this build does not recognise is dropped by the extractor rather
  /// than guessed at.
  final String kind;

  final String text;

  /// Heading level, or list nesting depth.
  final int level;
  final bool ordered;

  /// Absolute image URL. Null for every non-image block.
  final String? src;
  final String alt;

  /// Intrinsic size when the image had loaded, else its laid-out box. What the
  /// "is this meaningful or is it an icon" floor is applied to.
  final int width;
  final int height;

  /// Inside `<header>`, `<footer>`, `<nav>` or `<aside>`, or inside a
  /// container whose class names it as comments, an advertisement, a share bar
  /// or a recommendation grid.
  final bool inChrome;

  /// `display:none`, `visibility:hidden`, fully transparent, or zero-sized.
  final bool hidden;

  final List<RawInlineMark> marks;
}

/// The page's readable region, as reported by the bridge.
class RawDocument {
  const RawDocument({
    this.title = '',
    this.blocks = const [],
    this.truncated = false,
    this.regionBasis = '',
  });

  factory RawDocument.fromJson(Map<String, dynamic> json) => RawDocument(
    title: json['title']?.toString() ?? '',
    blocks: ((json['blocks'] as List<dynamic>?) ?? const [])
        .map(
          (e) => RawDocumentBlock.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false),
    truncated: json['truncated'] == true,
    regionBasis: json['regionBasis']?.toString() ?? '',
  );

  final String title;
  final List<RawDocumentBlock> blocks;

  /// The page had more blocks than the bridge returns. Reported so a truncated
  /// document is never mistaken for a complete one.
  final bool truncated;

  /// How the readable region was chosen (`<article>`, `<main>`, densest
  /// container, whole body). Logged, and shown in the details sheet, so a bad
  /// extraction is explainable rather than mysterious.
  final String regionBasis;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// A date only when it parses. An unparseable string is "no date", never today.
DateTime? _date(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}
