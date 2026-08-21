import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/url_utils.dart';

/// A [BrowserController] whose "pages" are literal [PageProbe]s.
///
/// Lets the save run loop and the update checker run headless in unit
/// tests: navigation just moves a pointer, probes return the fixture for the
/// current URL. Asset bytes still come over real HTTP (the tests stand up a
/// local server), so the downloader path is exercised for real.
class FakeBrowser extends BrowserController {
  FakeBrowser({Map<String, PageProbe> pages = const {}}) {
    this.pages.addAll(pages);
  }

  /// Keyed by normalised URL.
  final Map<String, PageProbe> pages = {};

  /// Optional redirects: navigating to key lands on value.
  final Map<String, String> redirects = {};

  final List<String> navigations = [];

  String _url = '';

  @override
  String get currentUrl => _url;

  @override
  bool get isAttached => true;

  @override
  String get title => pages[normalizeUrl(_url)]?.title ?? '';

  void setUrl(String url) => _url = url;

  void addPage(String url, PageProbe probe) => pages[normalizeUrl(url)] = probe;

  @override
  Future<void> loadAndWait(String url, {Duration? timeout}) async {
    navigations.add(url);
    _url = redirects[url] ?? url;
    notifyListeners();
  }

  /// The real controller pushes the URL into an attached WebView and reports
  /// it back through `onLoadStart`/`onUrlChanged`. There is no WebView here,
  /// so the observable effect is applied directly — otherwise a plain `load`
  /// looks like a no-op and a test asserting "the page was handed over" can
  /// never see it.
  @override
  Future<void> load(String url) async {
    if (url.trim().isEmpty) return;
    navigations.add(url);
    _url = redirects[url] ?? url;
    notifyListeners();
  }

  /// How many image records one probe returns, mirroring the bridge's own
  /// per-call cap. Null means "the whole list", which is what almost every
  /// fixture wants; set it to exercise enumeration across slices.
  int? imageSliceCap;

  /// Called before each slice is built, with the offset being asked for — a
  /// seam for scripting DOM mutation part-way through an enumeration.
  void Function(int offset)? onImageSlice;

  /// Every offset [probeImageSlice] was asked for, in order.
  final List<int> sliceOffsets = [];

  PageProbe _page() {
    final page = pages[normalizeUrl(_url)];
    if (page == null) {
      throw BridgeException('no fixture page for $_url');
    }
    return page;
  }

  /// The bridge's contract: a window into `document.images`, carrying the
  /// whole population's size and each image's absolute index.
  PageProbe _slice(PageProbe page, int offset) {
    final cap = imageSliceCap;
    if (cap == null) return page;
    final all = page.images;
    final from = offset.clamp(0, all.length);
    final to = (from + cap).clamp(0, all.length);
    final window = all.sublist(from, to);
    return PageProbe(
      url: page.url,
      title: page.title,
      canonicalUrl: page.canonicalUrl,
      readyState: page.readyState,
      documentHeight: page.documentHeight,
      viewportHeight: page.viewportHeight,
      viewportWidth: page.viewportWidth,
      scrollY: page.scrollY,
      images: window,
      links: page.links,
      headNextHref: page.headNextHref,
      atBottom: page.atBottom,
      imagesTruncated: to < all.length,
      imageCount: all.length,
      imageOffset: from,
      pageHints: page.pageHints,
      content: page.content,
      media: page.media,
      access: page.access,
    );
  }

  @override
  Future<PageProbe> probe({
    bool withLinks = false,
    bool withSignals = true,
  }) async => _slice(_page(), 0);

  @override
  Future<PageProbe> probeImageSlice(int imageOffset) async {
    sliceOffsets.add(imageOffset);
    onImageSlice?.call(imageOffset);
    return _slice(_page(), imageOffset);
  }

  /// What [extractDocument] returns, keyed by normalised URL. Absent means
  /// the bridge could not read the page — which the save engine reports as a
  /// text-extraction failure, exactly as a CSP-blocked page would.
  final Map<String, RawDocument> documents = {};

  void addDocument(String url, RawDocument document) =>
      documents[normalizeUrl(url)] = document;

  @override
  Future<RawDocument?> extractDocument({int blockCap = 2000}) async =>
      documents[normalizeUrl(_url)];

  @override
  Future<Map<String, dynamic>> scrollStep(int dy) async => const {};

  @override
  Future<void> scrollTo(int y) async {}

  @override
  Future<String?> userAgent() async => null;

  @override
  Future<String?> cookieHeaderFor(String url) async => null;

  @override
  Future<LocatorMatch?> applyLocator(Map<String, dynamic> locator) async =>
      null;

  @override
  Future<List<PageImage>?> applyReaderRule(Map<String, dynamic> rule) async =>
      null;

  @override
  Future<InPageBytes?> fetchAsBase64(String url) async => null;

  @override
  Future<void> startSelection({String mode = 'link'}) async {}

  @override
  Future<void> stopSelection() async {}
}

/// A settled entry page: [imageUrls] all loaded, one optional rel=next
/// link, plus whatever [extraLinks] the test wants in the way.
PageProbe entryProbe({
  required String url,
  required String title,
  required List<String> imageUrls,
  String? nextHref,
  List<PageLink> extraLinks = const [],
  int width = 800,
  int height = 1200,
}) {
  return PageProbe(
    url: url,
    title: title,
    readyState: 'complete',
    documentHeight: 4000,
    viewportHeight: 800,
    scrollY: 3200,
    atBottom: true,
    images: [
      for (final (i, src) in imageUrls.indexed)
        PageImage(
          domIndex: i,
          src: src,
          currentSrc: src,
          complete: true,
          naturalWidth: width,
          naturalHeight: height,
          renderedWidth: 390,
          renderedHeight: 585,
          documentTop: i * height,
        ),
    ],
    links: [
      if (nextHref != null)
        PageLink(href: nextHref, rel: 'next', text: 'Next Entry'),
      ...extraLinks,
    ],
  );
}
