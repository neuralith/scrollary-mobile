// Multi-source scenarios: one logical work, published on several simulated
// sites, for exercising V2's cross-source behaviour deterministically.
//
// Reserved example domains only, generic markup only — exactly as the other
// fixtures. Each simulated site is a subdomain of the reserved `.example`
// top-level domain (RFC 2606), served by the same in-process server under a
// path prefix, because a test's loopback server cannot own real DNS names:
//
//   /s/<site id>/...      the simulated site's pages
//   /scenarios.json       the machine-readable scenario manifest
//
// The page a simulated site serves declares which host it simulates through
// standard HTML semantics — a `<link rel="canonical">` to the reserved host
// and the host printed in the page header — never through a special marker.
// Structure and numbering are likewise expressed the way the existing fixture
// pages express them: printed labels, index lists, `rel="next"` links.
//
// The scenarios (see `kMultiSourceSites` for the data):
//
//   cleanMerge          `alpha.example` publishes Part 1..10 in English;
//                       `beta.example` publishes Part 5..15 in Turkish. The
//                       ranges overlap on 5..10 and both sites print the same
//                       explicit numbering, so equal printed ordinals are the
//                       material for the merge-by-ordinal case (V2-D16), and
//                       a translation being a Source of the same Collection
//                       is the material for V2-D17.
//
//   deadSource          `gone.example` once published the same work; every
//                       request to it now returns `410 Gone` while the other
//                       sites stay alive. The material for source lifecycle
//                       (V2-D14): a dead Source is a state, not a deletion.
//
//   renumberingConflict `shifted.example` publishes the same ten parts but
//                       its printed numbering sits half a step below
//                       `alpha.example`'s — what alpha prints as "Part 5" it
//                       prints as "Part 4.5". Different printed ordinals must
//                       stay two Entries (V2-D16); this is the fixture a
//                       must-not-merge test runs against.
//
//   nonNumeric          `journal.example` publishes the same work as
//                       date-ordered posts with no printed numbers anywhere.
//                       Sources of a date-ordered Collection coexist and are
//                       readable, but their Entries are never merged (V2-D16).
//
// Tests enumerate the scenarios from `kMultiSourceSites` (in-process) or from
// `GET /scenarios.json` (over the wire) rather than hardcoding paths.
import 'dart:convert';
import 'dart:io';

/// The one logical work every simulated site publishes.
const String kMultiSourceWorkTitle = 'Fixture multi-source work';

/// Scenario names, as the manifest prints them.
const String kScenarioCleanMerge = 'cleanMerge';
const String kScenarioDeadSource = 'deadSource';
const String kScenarioRenumberingConflict = 'renumberingConflict';
const String kScenarioNonNumeric = 'nonNumeric';

/// One simulated site: this work, as published on one reserved example host.
class MultiSourceSite {
  const MultiSourceSite({
    required this.id,
    required this.host,
    required this.scenario,
    required this.language,
    required this.orderingBasis,
    this.firstPart,
    this.lastPart,
    this.printedNumberOffset = 0,
    this.pageStatus = HttpStatus.ok,
  });

  /// Path-prefix id: the site is served under `/s/<id>/`.
  final String id;

  /// The reserved example host this site simulates.
  final String host;

  /// Which scenario the site belongs to.
  final String scenario;

  /// BCP 47 language the site publishes in (`<html lang>`).
  final String language;

  /// The Collection ordering basis this site's structure expresses, in the
  /// vocabulary of docs/V2_ARCHITECTURE.md §4.3.
  final String orderingBasis;

  /// Inclusive printed part range, for numerically ordered sites.
  final int? firstPart;
  final int? lastPart;

  /// What the site's printed number is relative to the part's position:
  /// 0 for honest numbering, -0.5 for the renumbering conflict.
  final double printedNumberOffset;

  /// Status every page of the site answers with. 200 for a live site,
  /// 410 for the dead one.
  final int pageStatus;

  String get pathPrefix => '/s/$id';
  String get indexPath => '$pathPrefix/';
  String partPath(int n) => '$pathPrefix/part/$n';

  /// The label a part page prints, e.g. `Part 5` or `Part 4.5`.
  String printedLabel(int n) {
    final v = n + printedNumberOffset;
    return v == v.roundToDouble() ? 'Part ${v.round()}' : 'Part $v';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'host': host,
    'scenario': scenario,
    'language': language,
    'orderingBasis': orderingBasis,
    'pathPrefix': pathPrefix,
    'index': indexPath,
    if (firstPart != null) 'firstPart': firstPart,
    if (lastPart != null) 'lastPart': lastPart,
    if (firstPart != null) 'partPathTemplate': '$pathPrefix/part/<n>',
    'printedNumberOffset': printedNumberOffset,
    'pageStatus': pageStatus,
    if (orderingBasis == 'publicationDate')
      'posts': [
        for (final p in kJournalPosts)
          {
            'path': '$pathPrefix/post/${p.slug}',
            'date': p.date,
            'title': p.title,
          },
      ],
  };
}

/// A dated post on the non-numeric site, oldest first.
class JournalPost {
  const JournalPost(this.slug, this.date, this.title);

  final String slug;

  /// ISO date, also printed in the page's `<time datetime>`.
  final String date;
  final String title;
}

const List<JournalPost> kJournalPosts = [
  JournalPost('a-walk-before-rain', '2024-01-07', 'A walk before rain'),
  JournalPost('the-quiet-harbour', '2024-01-21', 'The quiet harbour'),
  JournalPost('letters-from-the-attic', '2024-02-04', 'Letters from the attic'),
  JournalPost('a-lamp-in-the-window', '2024-02-18', 'A lamp in the window'),
  JournalPost('the-long-afternoon', '2024-03-03', 'The long afternoon'),
];

const List<MultiSourceSite> kMultiSourceSites = [
  MultiSourceSite(
    id: 'alpha',
    host: 'alpha.example',
    scenario: kScenarioCleanMerge,
    language: 'en',
    orderingBasis: 'explicitNumericIndex',
    firstPart: 1,
    lastPart: 10,
  ),
  MultiSourceSite(
    id: 'beta',
    host: 'beta.example',
    scenario: kScenarioCleanMerge,
    language: 'tr',
    orderingBasis: 'explicitNumericIndex',
    firstPart: 5,
    lastPart: 15,
  ),
  MultiSourceSite(
    id: 'gone',
    host: 'gone.example',
    scenario: kScenarioDeadSource,
    language: 'en',
    orderingBasis: 'explicitNumericIndex',
    firstPart: 1,
    lastPart: 10,
    pageStatus: HttpStatus.gone,
  ),
  MultiSourceSite(
    id: 'shifted',
    host: 'shifted.example',
    scenario: kScenarioRenumberingConflict,
    language: 'en',
    orderingBasis: 'explicitNumericIndex',
    firstPart: 1,
    lastPart: 10,
    printedNumberOffset: -0.5,
  ),
  MultiSourceSite(
    id: 'journal',
    host: 'journal.example',
    scenario: kScenarioNonNumeric,
    language: 'en',
    orderingBasis: 'publicationDate',
  ),
];

/// The scenario manifest served at `/scenarios.json`.
String scenarioManifestJson() => const JsonEncoder.withIndent('  ').convert({
  'version': 1,
  'work': kMultiSourceWorkTitle,
  'sites': [for (final s in kMultiSourceSites) s.toJson()],
});

/// Handle one multi-source request. Returns false if the path is not one of
/// this module's, so the caller can fall through to its own routes.
Future<bool> handleMultiSourceRequest(HttpRequest req) async {
  final path = req.uri.path;
  final res = req.response;

  if (path == '/scenarios.json') {
    res.headers.contentType = ContentType.json;
    res.headers.set('Cache-Control', 'no-store');
    res.write(scenarioManifestJson());
    await res.close();
    return true;
  }

  final m = RegExp(r'^/s/([a-z]+)(/.*)?$').firstMatch(path);
  if (m == null) return false;

  MultiSourceSite? site;
  for (final s in kMultiSourceSites) {
    if (s.id == m.group(1)) site = s;
  }
  if (site == null) {
    res.statusCode = HttpStatus.notFound;
    await _html(res, '<h1>No such site</h1>');
    return true;
  }

  // The dead site is dead everywhere: index, parts, anything.
  if (site.pageStatus != HttpStatus.ok) {
    res.statusCode = site.pageStatus;
    await _html(
      res,
      '<h1>Gone</h1><p>${site.host} no longer publishes anything.</p>',
    );
    return true;
  }

  final rest = m.group(2) ?? '/';

  if (rest == '/' || rest.isEmpty || rest == '/index.html') {
    await _html(res, _indexPage(site));
    return true;
  }

  if (site.orderingBasis == 'publicationDate') {
    final postMatch = RegExp(r'^/post/([a-z-]+)$').firstMatch(rest);
    final index = postMatch == null
        ? -1
        : kJournalPosts.indexWhere((p) => p.slug == postMatch.group(1));
    if (index < 0) {
      res.statusCode = HttpStatus.notFound;
      await _html(res, '<h1>No such post</h1>');
      return true;
    }
    await _html(res, _journalPostPage(site, index));
    return true;
  }

  final partMatch = RegExp(r'^/part/(\d+)$').firstMatch(rest);
  if (partMatch != null) {
    final n = int.parse(partMatch.group(1)!);
    if (n < site.firstPart! || n > site.lastPart!) {
      res.statusCode = HttpStatus.notFound;
      await _html(res, '<h1>No such part</h1>');
      return true;
    }
    await _html(res, _partPage(site, n));
    return true;
  }

  res.statusCode = HttpStatus.notFound;
  await _html(res, '<h1>Not found</h1>');
  return true;
}

Future<void> _html(HttpResponse res, String body) {
  res.headers.contentType = ContentType.html;
  res.headers.set('Cache-Control', 'no-store');
  res.write(body);
  return res.close();
}

/// Enough neutral prose to clear the readable floor.
String _prose(String about) {
  const sentence =
      'The quick brown fox jumps over the lazy dog, and then it does so '
      'again, because that is what the sentence is for. ';
  final paragraphs = <String>[];
  for (var i = 1; i <= 4; i++) {
    paragraphs.add('<p>Paragraph $i of $about. ${sentence * 3}</p>');
  }
  return paragraphs.join('\n');
}

String _head(MultiSourceSite site, String title, String canonicalPath) =>
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<link rel="canonical" href="https://${site.host}$canonicalPath">'
    '<title>$title</title>';

String _header(MultiSourceSite site) =>
    '<header class="site-header"><p>${site.host}</p>'
    '<p>$kMultiSourceWorkTitle</p></header>';

String _indexPage(MultiSourceSite site) {
  final String items;
  if (site.orderingBasis == 'publicationDate') {
    items = [
      for (final p in kJournalPosts)
        '<li><a href="${site.pathPrefix}/post/${p.slug}">${p.title}</a> — '
            '<time datetime="${p.date}">${_printedDate(p.date)}</time></li>',
    ].join();
  } else {
    items = [
      for (var n = site.firstPart!; n <= site.lastPart!; n++)
        '<li><a href="${site.partPath(n)}">${site.printedLabel(n)}</a></li>',
    ].join();
  }
  return '<!doctype html><html lang="${site.language}"><head>'
      '${_head(site, kMultiSourceWorkTitle, '/')}</head>'
      '<body>${_header(site)}'
      '<main><h1>$kMultiSourceWorkTitle</h1>'
      '<ul>$items</ul></main>'
      '</body></html>';
}

String _partPage(MultiSourceSite site, int n) {
  final label = site.printedLabel(n);
  final turkish = site.language == 'tr';
  final nextRel = n < site.lastPart!
      ? '<link rel="next" href="${site.partPath(n + 1)}">'
      : '';
  final prevRel = n > site.firstPart!
      ? '<link rel="prev" href="${site.partPath(n - 1)}">'
      : '';
  final nextAnchor = n < site.lastPart!
      ? '<a rel="next" href="${site.partPath(n + 1)}">'
            '${turkish ? 'Sonraki part' : 'Next part'} →</a>'
      : '<span>${turkish ? 'Son part' : 'Last part'}</span>';
  final prevAnchor = n > site.firstPart!
      ? '<a rel="prev" href="${site.partPath(n - 1)}">'
            '← ${turkish ? 'Onceki part' : 'Previous part'}</a>'
      : '';
  return '<!doctype html><html lang="${site.language}"><head>'
      '${_head(site, '$label — $kMultiSourceWorkTitle', '/part/$n')}'
      '$nextRel$prevRel</head>'
      '<body>${_header(site)}'
      '<main><article>'
      '<h1>$label</h1>'
      '${_prose('$label on ${site.host}')}'
      '</article></main>'
      '<footer><nav>$prevAnchor $nextAnchor</nav></footer>'
      '</body></html>';
}

String _journalPostPage(MultiSourceSite site, int index) {
  final post = kJournalPosts[index];
  final next = index < kJournalPosts.length - 1
      ? kJournalPosts[index + 1]
      : null;
  final prev = index > 0 ? kJournalPosts[index - 1] : null;
  final nextRel = next != null
      ? '<link rel="next" href="${site.pathPrefix}/post/${next.slug}">'
      : '';
  final prevRel = prev != null
      ? '<link rel="prev" href="${site.pathPrefix}/post/${prev.slug}">'
      : '';
  final nextAnchor = next != null
      ? '<a rel="next" href="${site.pathPrefix}/post/${next.slug}">'
            'Newer post →</a>'
      : '<span>Newest post</span>';
  final prevAnchor = prev != null
      ? '<a rel="prev" href="${site.pathPrefix}/post/${prev.slug}">'
            '← Older post</a>'
      : '';
  return '<!doctype html><html lang="${site.language}"><head>'
      '${_head(site, '${post.title} — $kMultiSourceWorkTitle', '/post/${post.slug}')}'
      '$nextRel$prevRel</head>'
      '<body>${_header(site)}'
      '<main><article>'
      '<h1>${post.title}</h1>'
      '<p class="byline">Posted '
      '<time datetime="${post.date}">${_printedDate(post.date)}</time></p>'
      '${_prose('${post.title} on ${site.host}')}'
      '</article></main>'
      '<footer><nav>$prevAnchor $nextAnchor</nav></footer>'
      '</body></html>';
}

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `2024-01-07` → `7 January 2024`, the printed form beside the `datetime`.
String _printedDate(String iso) {
  final parts = iso.split('-');
  final month = _months[int.parse(parts[1]) - 1];
  return '${int.parse(parts[2])} $month ${parts[0]}';
}
