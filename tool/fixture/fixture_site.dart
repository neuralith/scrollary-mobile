// The controlled image sequence fixture: page markup and image bytes.
//
// Shared by the standalone CLI server (`serve.dart`, for manual browsing) and
// by the integration test, which serves it *in-process on the simulator* so
// the test can shut the source down mid-run and prove offline reading.
import 'dart:io';
import 'dart:typed_data';

import 'multi_source_fixtures.dart';
import 'text_fixtures.dart';

const int kEntryCount = 3;
const int kContentImagesPerEntry = 6;

/// Entry with a deliberately broken (503) panel, so partial save is
/// exercised on every run.
const int kBrokenEntry = 2;
const int kBrokenPanel = 5;

/// Panel that responds slowly, so "loaded" never means "finished".
const int kSlowPanel = 4;

/// Handle one fixture request. Returns false if the path is unknown.
Future<bool> handleFixtureRequest(
  HttpRequest req, {
  bool applyDelays = true,

  /// How many entries the "site" currently has. Tests raise this mid-run to
  /// simulate the source publishing new entries after a save.
  int entryCount = kEntryCount,
}) async {
  final path = req.uri.path;
  final res = req.response;
  res.headers.set('Access-Control-Allow-Origin', '*');

  if (path == '/' || path == '/index.html') {
    await _html(res, indexPage(entryCount));
    return true;
  }

  // Localised and awkward variants, for exercising detection without relying
  // on a language dictionary:
  //   /tr/<n>       Turkish label, no rel=next
  //   /de/<n>       German label, no rel=next
  //   /amb/<n>      two equally plausible controls -> must ask the user
  //   /nolabel/<n>  icon-only control, no rel/text/aria -> must ask the user
  final localeMatch = RegExp(r'^/(tr|de|amb|nolabel)/(\d+)$').firstMatch(path);
  if (localeMatch != null) {
    final variant = localeMatch.group(1)!;
    final n = int.parse(localeMatch.group(2)!);
    if (n < 1 || n > entryCount) {
      res.statusCode = 404;
      await _html(res, '<h1>No such entry</h1>');
      return true;
    }
    await _html(res, localisedEntryPage(variant, n, entryCount: entryCount));
    return true;
  }

  // Text-shaped fixtures, for exercising the capture modes deterministically:
  //   /text/<n>        prose only, no meaningful images  -> Text only
  //   /textimages/<n>  prose with two inline figures     -> Text and images
  //   /videopage       a player that fills the viewport  -> nothing to save
  //   /ambiguous       short text and two medium images  -> low confidence
  final textMatch = RegExp(r'^/(text|textimages)/(\d+)$').firstMatch(path);
  if (textMatch != null) {
    final withImages = textMatch.group(1) == 'textimages';
    final n = int.parse(textMatch.group(2)!);
    if (n < 1 || n > entryCount) {
      res.statusCode = 404;
      await _html(res, '<h1>No such entry</h1>');
      return true;
    }
    await _html(
      res,
      textEntryPage(n, entryCount: entryCount, withImages: withImages),
    );
    return true;
  }

  if (path == '/videopage') {
    await _html(res, videoPage());
    return true;
  }

  // An entry whose panel count exceeds what one probe call returns, so the
  // save has to enumerate the page across several slices to see all of it.
  //   /wide/<count>
  final wideMatch = RegExp(r'^/wide/(\d+)$').firstMatch(path);
  if (wideMatch != null) {
    await _html(res, wideEntryPage(int.parse(wideMatch.group(1)!)));
    return true;
  }

  // An app-shell layout: the document does not scroll, an inner element does.
  //   /innerscroll
  if (path == '/innerscroll') {
    await _html(res, innerScrollPage());
    return true;
  }

  // A page of panels whose only words are its own furniture.
  //   /noprose
  if (path == '/noprose') {
    await _html(res, noProsePage());
    return true;
  }

  // Panels that reserve a small box until they load, among furniture that
  // reserves boxes too.
  //   /minbox/<panelCount>
  final minBoxMatch = RegExp(r'^/minbox/(\d+)$').firstMatch(path);
  if (minBoxMatch != null) {
    await _html(
      res,
      minBoxLazyPage(panelCount: int.parse(minBoxMatch.group(1)!)),
    );
    return true;
  }

  // One of every lazy/broken/loaded image shape.
  //   /lazyshapes
  if (path == '/lazyshapes') {
    await _html(res, lazyShapesPage());
    return true;
  }

  // Never answered: an image that stays genuinely in flight.
  if (path.startsWith('/hang/')) return true;

  if (path == '/ambiguous') {
    await _html(res, ambiguousPage());
    return true;
  }

  // Figures for the text fixtures. Same generator as the panels, different
  // route, so a text page's images cannot be confused with a sequence's.
  // Figures for the text fixtures. Same generator as the panels, different
  // route, and the size is explicit: a page that DECLARES a 1x1 tracking pixel
  // must be served an actual 1x1 image, because the browser reports the
  // natural size and the extractor believes it over the attribute.
  final figureMatch = RegExp(r'^/figure/(\d+)/(\d+)\.png$').firstMatch(path);
  if (figureMatch != null) {
    await _png(
      res,
      panelPng(
        entry: int.parse(figureMatch.group(1)!),
        index: int.parse(figureMatch.group(2)!),
        width: int.tryParse(req.uri.queryParameters['w'] ?? '') ?? 640,
        height: int.tryParse(req.uri.queryParameters['h'] ?? '') ?? 420,
      ),
    );
    return true;
  }

  final entryMatch = RegExp(r'^/entry/(\d+)$').firstMatch(path);
  if (entryMatch != null) {
    final n = int.parse(entryMatch.group(1)!);
    if (n < 1 || n > entryCount) {
      res.statusCode = 404;
      await _html(res, '<h1>No such entry</h1>');
      return true;
    }
    await _html(res, entryPage(n, entryCount: entryCount));
    return true;
  }

  final imgMatch = RegExp(r'^/img/(\d+)/(\d+)\.png$').firstMatch(path);
  if (imgMatch != null) {
    final entry = int.parse(imgMatch.group(1)!);
    final index = int.parse(imgMatch.group(2)!);
    if (applyDelays && index == kSlowPanel) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (entry == kBrokenEntry && index == kBrokenPanel) {
      res.statusCode = 503;
      await res.close();
      return true;
    }
    await _png(res, panelPng(entry: entry, index: index));
    return true;
  }

  const chrome = <String, List<int>>{
    '/chrome/icon.png': [32, 32, 0x33, 0x33, 0x33],
    '/chrome/logo.png': [240, 48, 0x88, 0x44, 0xcc],
    '/chrome/pixel.png': [1, 1, 0xff, 0xff, 0xff],
    '/chrome/avatar.png': [64, 64, 0x22, 0x99, 0x66],
    '/chrome/banner.png': [970, 90, 0xdd, 0x22, 0x22],
  };
  final spec = chrome[path];
  if (spec != null) {
    await _png(res, solidPng(spec[0], spec[1], spec[2], spec[3], spec[4]));
    return true;
  }

  // Multi-source scenarios: `/s/<site>/...` and `/scenarios.json`.
  if (await handleMultiSourceRequest(req)) return true;

  res.statusCode = 404;
  await res.close();
  return false;
}

Future<void> _html(HttpResponse res, String body) {
  res.headers.contentType = ContentType.html;
  res.headers.set('Cache-Control', 'no-store');
  res.write(body);
  return res.close();
}

Future<void> _png(HttpResponse res, Uint8List bytes) {
  res.headers.contentType = ContentType('image', 'png');
  res.headers.set('Cache-Control', 'no-store');
  res.add(bytes);
  return res.close();
}

String indexPage([int entryCount = kEntryCount]) =>
    '''
<!doctype html><html><head><meta name="viewport"
  content="width=device-width, initial-scale=1"><title>Fixture image sequence</title></head>
<body style="font-family:-apple-system,sans-serif;padding:24px">
<h1>Fixture image sequence</h1>
<ul>${List.generate(entryCount, (i) => '<li><a href="/entry/${i + 1}">Entry ${i + 1}</a></li>').join()}</ul>
</body></html>''';

/// Panels 1-2 load eagerly; 3-6 are lazy-loaded on intersection with a delay,
/// so a save that trusted `onLoadStop` would miss two thirds of the entry.
String entryPage(int n, {int entryCount = kEntryCount}) {
  final buf = StringBuffer();
  for (var i = 1; i <= kContentImagesPerEntry; i++) {
    final url = '/img/$n/$i.png';
    if (i <= 2) {
      buf.writeln(
        '<img class="panel" src="$url" width="800" height="1200" '
        'alt="panel $i">',
      );
    } else {
      buf.writeln(
        '<img class="panel lazy" data-src="$url" width="800" '
        'height="1200" alt="panel $i">',
      );
    }
  }
  // Duplicate of panel 1: the filter must de-duplicate by URL.
  buf.writeln(
    '<img class="panel" src="/img/$n/1.png" width="800" '
    'height="1200" alt="duplicate of panel 1">',
  );
  // Hidden large image: must be rejected despite passing the size test.
  buf.writeln(
    '<img src="/img/$n/2.png" width="800" height="1200" '
    'style="display:none" alt="hidden">',
  );

  final nextLink = n < entryCount
      ? '<a id="next" rel="next" href="/entry/${n + 1}">Next Entry →</a>'
      : '<span id="next-disabled">No next entry</span>';
  final prevLink = n > 1
      ? '<a rel="prev" href="/entry/${n - 1}">← Previous</a>'
      : '';

  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fixture image sequence — Entry $n</title>
<link rel="canonical" href="/entry/$n">
<style>
  body { margin:0; background:#111; color:#eee; font-family:-apple-system,sans-serif; }
  header, footer { padding:12px 16px; background:#1c1c1c; }
  nav a { color:#8cf; margin-right:16px; }
  img.panel { display:block; width:100%; height:auto; margin:0 auto; max-width:800px; }
  img.lazy { min-height:1200px; background:#222; }
</style></head>
<body>
<header>
  <img src="/chrome/logo.png" width="240" height="48" alt="logo">
  <img src="/chrome/icon.png" width="32" height="32" alt="icon">
  <img src="/chrome/avatar.png" width="64" height="64" alt="avatar">
  <h2>Fixture image sequence — Entry $n</h2>
</header>
<img src="/chrome/banner.png" width="970" height="90" alt="ad banner">
<div class="reader">
$buf
</div>
<img src="/chrome/pixel.png" width="1" height="1" alt="">
<footer><nav>$prevLink $nextLink</nav></footer>
<script>
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      const img = e.target;
      io.unobserve(img);
      setTimeout(() => { img.src = img.dataset.src; img.classList.remove('lazy'); }, 400);
    }
  }, { rootMargin: '200px' });
  document.querySelectorAll('img.lazy').forEach((i) => io.observe(i));
</script>
</body></html>''';
}

/// An entry of [count] qualifying panels, for exercising enumeration beyond
/// what a single probe call returns.
///
/// The panels declare their size and never load: enumeration is the thing
/// under test, and `width`/`height` are enough to qualify them as content.
///
/// Each panel carries a **distinct** address, because candidate selection
/// de-duplicates by URL — a page of identical images would collapse to one
/// candidate and prove nothing about enumeration.
String wideEntryPage(int count) {
  final buf = StringBuffer();
  for (var i = 0; i < count; i++) {
    buf.writeln(
      '<img class="panel" data-src="/img/1/$i.png" width="800" height="1200" '
      'alt="panel $i">',
    );
  }
  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wide entry — $count panels</title>
<style>img.panel{display:block;width:100%;height:auto;min-height:12px}</style>
</head><body><div class="reader">$buf</div></body></html>''';
}

/// A page of stacked panels whose **only words are its own furniture**.
///
/// The shape that made an image page save as text. Three ordinary things hold
/// at once, and none of them is unusual on its own:
///
/// 1. **No `<article>`, no `<main>`, no `role=main`.** The readable region
///    therefore falls back to the whole document.
/// 2. **The menus, the listing and the sign-in box are `<div>`s, not `<nav>`
///    or `<footer>`.** Very common, and it matters because the region's text
///    reading drops chrome *tags* and nothing else — so all of that text is
///    counted as the page's prose.
/// 3. **The readable column carries a negated state class**
///    (`sidebar-hidden`: the column that is left when the sidebar is gone).
///    Matched as a declaration, it marks the readable half of the page as
///    furniture, which empties the content-region image count as well.
///
/// Together those made a page of panels measure several thousand characters
/// of "prose", classify as an article, resolve to a text capture, and fail
/// with "no readable text" — while its panels were never looked at.
///
/// The panels declare their size and carry distinct addresses, so what is
/// under test is the classification and not the loader.
String noProsePage({int panelCount = 6}) {
  final panels = StringBuffer();
  for (var i = 1; i <= panelCount; i++) {
    panels.writeln(
      '<img class="panel" src="/img/1/$i.png" width="800" height="1200" '
      'alt="panel $i">',
    );
  }

  // Furniture prose: comfortably past the 900-character prose floor and the
  // three-paragraph floor, and every character of it inside a container named
  // as furniture. Without the fix this is what the page is "about".
  String filler(String what) =>
      'This block is $what. It exists so the page carries more than nine '
      'hundred characters of words that no reader came here to read, in more '
      'than three paragraphs, in a container this markup names for what it '
      'is. Every sentence in it is page furniture and belongs to the site '
      'rather than to the entry, which is exactly why a measurement that '
      'counts it cannot tell an article from a column of pictures. ';

  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fixture — words are all furniture</title>
<style>
  body { margin:0; background:#111; color:#eee; font-family:-apple-system,sans-serif; }
  img.panel { display:block; width:100%; height:auto; margin:0 auto; max-width:800px; }
  .site-menu, .entry-list-widget, .login-widget, .comments-area,
  .page-footer { padding:12px 16px; background:#1c1c1c; }
</style></head>
<body class="header-style-1">
<div class="site-menu">
  <img src="/chrome/logo.png" width="240" height="48" alt="logo">
  <p>${filler('the site menu')}</p>
  <p>${filler('the second row of the site menu')}</p>
</div>
<div class="entry-list-widget">
  <p>${filler('the listing of everything else on the site')}</p>
</div>
<div class="main-col sidebar-hidden">
  <h1>Fixture — words are all furniture</h1>
  <div class="reader">
$panels
  </div>
</div>
<div class="login-widget">
  <p>${filler('the sign-in box')}</p>
  <p>${filler('the second half of the sign-in box')}</p>
</div>
<div class="comments-area">
  <p>${filler('the comments section')}</p>
</div>
<div class="page-footer">
  <p>${filler('the footer')}</p>
  <img src="/chrome/pixel.png" width="1" height="1" alt="">
</div>
</body></html>''';
}

/// Where [minBoxLazyPage]'s panels are served from. One definition, so the
/// page and the suite that asserts its reading order cannot disagree.
const String kMinBoxPanelPath = '/figure/1/';

/// Panels that reserve a **small box** until they load, among furniture that
/// reserves boxes too.
///
/// The shape a per-image size test cannot read. Until a panel loads it has no
/// intrinsic size and no `width`/`height`, so all it reports is the box the
/// stylesheet gave it — here `min-width: 50px; min-height: 50px`, which is
/// ordinary CSS and is what a real reading site does. Judged one at a time,
/// every panel on this page is an icon: traversal stops treating them as
/// content, nothing near the position looks unresolved, the whole unloaded
/// document is barely three viewports tall, and the save reaches the bottom
/// and calls it settled before a single panel has been asked for.
///
/// Two kinds of furniture are here for the opposite reason — they reserve
/// boxes as well, and must **not** be rescued by the rule that saves the
/// panels:
///
/// * **[adSlots] rail slots**, `300x250` and never loading, spread down the
///   page with the reading between them.
/// * **A related-items grid** at the foot: several boxes sharing one vertical
///   position, which is what side-by-side looks like to a geometry test.
///
/// Panels load only when scrolled near, and not instantly, so the run being
/// waited for is a run that is genuinely still arriving. **Only the panels
/// ever reach the network**: the furniture keeps its address in `data-src` and
/// is never switched on, which is both what an unfired advert slot really
/// looks like and what keeps twelve dead sockets from exhausting the WebView's
/// per-host connection pool — with that pool full, the panels cannot load at
/// all and the fixture tests nothing.
String minBoxLazyPage({int panelCount = 20, int adSlots = 4}) {
  final body = StringBuffer();
  final every = panelCount ~/ (adSlots + 1);
  for (var i = 1; i <= panelCount; i++) {
    // Comfortably past the size floor on both edges, and no larger. The
    // default panel is 800x1200, which is ~3.8MB of bitmap once decoded; a
    // page of thirty of those is a hundred and fifteen megabytes of decoded
    // image before the app has done anything, and the simulator kills it. The
    // shape under test is the reserved *box*, not the size of the picture that
    // eventually fills it.
    body.writeln(
      '<img class="panel" data-src="$kMinBoxPanelPath$i.png?w=400&h=600" '
      'alt="panel $i">',
    );
    // A rail slot every so often, in the flow of the reading rather than
    // beside it, so nothing but its geometry distinguishes it.
    if (adSlots > 0 && every > 0 && i % every == 0 && i != panelCount) {
      body.writeln('<img class="adslot" data-src="/ads/slot-$i.gif" alt="">');
    }
  }
  final grid = StringBuffer();
  for (var i = 1; i <= 7; i++) {
    grid.writeln('<img class="thumb" data-src="/related/$i.jpg" alt="">');
  }

  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fixture — panels that reserve a small box</title>
<style>
  body { margin:0; background:#111; color:#eee; font-family:-apple-system,sans-serif; }
  .reading .panel {
    display:block; width:100%; max-width:800px; margin:0 auto;
    /* The placeholder every unloaded panel reports until its bytes arrive. */
    min-width:50px; min-height:50px;
  }
  .adslot { display:block; width:300px; height:250px; margin:24px auto; background:#333; }
  .related { display:flex; flex-wrap:wrap; gap:8px; padding:16px; }
  .related .thumb { width:140px; background:#333; }
</style></head>
<body>
<h1>Fixture — panels that reserve a small box</h1>
<div class="reading">
$body
</div>
<div class="related">
$grid
</div>
<script>
  // Loads only on approach, and never instantly: the point is a run that is
  // still arriving while the save is deciding whether to wait for it.
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      const img = e.target;
      io.unobserve(img);
      setTimeout(() => { img.src = img.dataset.src; }, 250);
    }
  }, { rootMargin: '100px' });
  document.querySelectorAll('img.panel').forEach((i) => io.observe(i));
</script>
</body></html>''';
}

/// The app-shell layout: `<body>` does not scroll, an inner element does.
///
/// Deliberately awkward, so a coordinate formula that ignores any part of it
/// is caught — the scroller sits [headerHeight] px down the page and has both
/// a border and padding, and the panels are tall enough for several screens.
///
/// The page publishes its own truth for the test to compare against: each
/// panel's `alt` carries that panel's real offset inside the scrolled content,
/// and `document.title` carries the scroller's metrics. Both travel in fields
/// the probe already returns, so nothing in the app has to be opened up to
/// observe them.
String innerScrollPage({
  int panels = 12,
  int panelHeight = 1200,
  int headerHeight = 180,
  int pendingFrom = 6,
}) {
  final buf = StringBuffer();
  for (var i = 0; i < panels; i++) {
    // `/hang/` is never answered, so these stay genuinely in flight rather
    // than reading as broken.
    final src = i >= pendingFrom ? '/hang/$i.png' : '/img/1/1.png';
    buf.writeln(
      '<img class="panel" src="$src" width="800" height="$panelHeight" alt="">',
    );
  }
  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>boot</title>
<style>
  html,body{height:100%;margin:0;overflow:hidden;background:#111;color:#eee}
  #header{height:${headerHeight}px;background:#222}
  #scroller{
    height:600px; overflow-y:auto;
    border-top:8px solid #444; border-bottom:8px solid #444;
    padding-top:12px; padding-bottom:12px;
    box-sizing:border-box;
  }
  img.panel{display:block;width:100%;height:${panelHeight}px;background:#333}
</style></head>
<body>
  <div id="header">header</div>
  <div id="scroller">$buf</div>
<script>
  var sc = document.getElementById('scroller');
  function publish() {
    var sr = sc.getBoundingClientRect();
    var cs = getComputedStyle(sc);
    var bt = parseFloat(cs.borderTopWidth) || 0;
    var pt = parseFloat(cs.paddingTop) || 0;
    document.title = JSON.stringify({
      win: Math.round(window.scrollY || 0),
      top: Math.round(sc.scrollTop),
      ch: Math.round(sc.clientHeight),
      sh: Math.round(sc.scrollHeight),
      rectTop: Math.round(sr.top),
      bt: Math.round(bt), pt: Math.round(pt)
    });
    var imgs = document.querySelectorAll('img.panel');
    for (var i = 0; i < imgs.length; i++) {
      var r = imgs[i].getBoundingClientRect();
      imgs[i].alt = String(Math.round(r.top - sr.top + sc.scrollTop - bt - pt));
    }
  }
  publish();
  setInterval(publish, 30);
  sc.addEventListener('scroll', publish);
</script>
</body></html>''';
}

/// One of every image shape whose load state the engine has to classify.
///
/// `alt` names the shape so a test can address them without depending on
/// document order.
String lazyShapesPage() => '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lazy shapes</title>
<style>img{display:block;width:100%;height:auto;min-height:20px;background:#333}</style>
</head><body>
<img alt="loaded" src="/img/1/1.png" width="800" height="1200">
<img alt="in-flight" src="/hang/a.png" width="800" height="1200">
<img alt="failed" src="/nothing-here.png" width="800" height="1200">
<img alt="untriggered" data-src="/img/1/1.png" width="800" height="1200">
<img alt="empty-src" src="" data-src="/img/1/1.png" width="800" height="1200">
<img alt="srcset" srcset="/img/1/1.png 800w" sizes="100vw" width="800" height="1200">
<picture><source srcset="/img/1/1.png"><img alt="picture" width="800" height="1200"></picture>
<img alt="native-lazy-far" src="/img/1/2.png" loading="lazy" width="800" height="1200">
<div style="height:30000px">spacer, so the native-lazy image stays out of range</div>
</body></html>''';

// ---------------------------------------------------------------------------
// Minimal PNG encoder — keeps the fixture dependency-free.
// ---------------------------------------------------------------------------

/// A content panel: distinct colour per entry, plus `index` white bars so
/// panel order is verifiable by eye in the reader.
Uint8List panelPng({
  required int entry,
  required int index,
  int width = 800,
  int height = 1200,
}) {
  final w = width, h = height;
  const palette = [
    [0x1e, 0x3a, 0x8a],
    [0x7c, 0x2d, 0x12],
    [0x14, 0x53, 0x2d],
  ];
  final base = palette[(entry - 1) % palette.length];
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final shade = (y * 40 ~/ h);
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 3;
      rgb[o] = (base[0] + shade).clamp(0, 255);
      rgb[o + 1] = (base[1] + shade).clamp(0, 255);
      rgb[o + 2] = (base[2] + shade).clamp(0, 255);
    }
  }
  for (var b = 0; b < index; b++) {
    final x0 = 40 + b * 60;
    for (var y = 60; y < 220 && y < h; y++) {
      for (var x = x0; x < x0 + 40 && x < w; x++) {
        final o = (y * w + x) * 3;
        rgb[o] = 0xff;
        rgb[o + 1] = 0xff;
        rgb[o + 2] = 0xff;
      }
    }
  }
  return _encodePng(w, h, rgb);
}

Uint8List solidPng(int w, int h, int r, int g, int b) {
  final rgb = Uint8List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    rgb[i * 3] = r;
    rgb[i * 3 + 1] = g;
    rgb[i * 3 + 2] = b;
  }
  return _encodePng(w, h, rgb);
}

Uint8List _encodePng(int width, int height, Uint8List rgb) {
  final raw = Uint8List(height * (1 + width * 3));
  var o = 0;
  for (var y = 0; y < height; y++) {
    raw[o++] = 0; // filter: none
    raw.setRange(o, o + width * 3, rgb, y * width * 3);
    o += width * 3;
  }
  final idat = Uint8List.fromList(ZLibEncoder().convert(raw));

  final ihdr = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    ..add([8, 2, 0, 0, 0]); // 8-bit truecolour RGB

  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ..._chunk('IHDR', ihdr.toBytes()),
    ..._chunk('IDAT', idat),
    ..._chunk('IEND', Uint8List(0)),
  ]);
}

List<int> _u32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];

List<int> _chunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final crc = _crc32(Uint8List.fromList([...typeBytes, ...data]));
  return [..._u32(data.length), ...typeBytes, ...data, ..._u32(crc)];
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

/// Entry pages whose next-control is expressed differently, so detection is
/// exercised beyond `rel="next"` and beyond English.
///
/// Deliberately not a language-coverage exercise. `nolabel` and `amb` exist to
/// prove the app *asks the user* rather than guessing when the page gives it
/// nothing trustworthy — which is the point of the fallback model.
String localisedEntryPage(
  String variant,
  int n, {
  int entryCount = kEntryCount,
}) {
  final buf = StringBuffer();
  for (var i = 1; i <= kContentImagesPerEntry; i++) {
    buf.writeln(
      '<img class="panel" src="/img/$n/$i.png" width="800" height="1200" '
      'alt="panel $i">',
    );
  }

  final next = n < entryCount ? '/$variant/${n + 1}' : null;
  final String nav;
  switch (variant) {
    case 'tr':
      nav = next == null
          ? '<span>Son part</span>'
          : '<a class="nav-next" href="$next">Sonraki part</a>';
    case 'de':
      nav = next == null
          ? '<span>Letztes Kapitel</span>'
          : '<a class="weiter" href="$next">Naechstes Kapitel</a>';
    case 'amb':
      // Two equally plausible controls pointing at different pages: the app
      // must refuse to pick and ask instead.
      nav = next == null
          ? '<span>Ende</span>'
          : '<a href="$next">Next</a> '
                '<a href="/$variant/$entryCount">Continue</a>';
    case 'nolabel':
    default:
      // Icon-only control: no rel, no text, no aria-label, no href pattern the
      // heuristics can trust on their own.
      nav = next == null
          ? '<span>[end]</span>'
          : '<a class="x1" href="$next">'
                '<img src="/chrome/icon.png" width="32" height="32"></a>';
  }

  return '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fixture $variant - entry $n</title>
<style>
  body { margin:0; background:#111; color:#eee; }
  img.panel { display:block; width:100%; height:auto; max-width:800px; margin:0 auto; }
</style></head>
<body>
<div class="reading-content">
$buf
</div>
<footer><nav>$nav</nav></footer>
</body></html>''';
}
