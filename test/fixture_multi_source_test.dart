// The fixture tool's own check on the multi-source scenarios: the in-process
// server serves each simulated site with the structure the scenario promises,
// and the manifest enumerates them so no consumer has to hardcode a path.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/fixture/fixture_site.dart';
import '../tool/fixture/multi_source_fixtures.dart';

void main() {
  late HttpServer server;
  late String origin;
  final client = HttpClient();

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      try {
        await handleFixtureRequest(req, applyDelays: false);
      } catch (_) {}
    });
  });

  tearDownAll(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  Future<(int, String)> get(String path) async {
    final req = await client.getUrl(Uri.parse('$origin$path'));
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    return (res.statusCode, body);
  }

  MultiSourceSite site(String id) =>
      kMultiSourceSites.firstWhere((s) => s.id == id);

  group('scenario manifest', () {
    test('is served, versioned, and lists every site', () async {
      final (status, body) = await get('/scenarios.json');
      expect(status, 200);
      final manifest = jsonDecode(body) as Map<String, dynamic>;
      expect(manifest['version'], 1);
      expect(manifest['work'], kMultiSourceWorkTitle);
      final sites = (manifest['sites'] as List).cast<Map<String, dynamic>>();
      expect(
        sites.map((s) => s['id']),
        kMultiSourceSites.map((s) => s.id),
        reason: 'the manifest and the Dart constants must agree',
      );
      expect(sites.map((s) => s['scenario']).toSet(), {
        kScenarioCleanMerge,
        kScenarioDeadSource,
        kScenarioRenumberingConflict,
        kScenarioNonNumeric,
      }, reason: 'all four scenarios are represented');
    });

    test('names reserved example hosts only', () {
      for (final s in kMultiSourceSites) {
        expect(
          s.host,
          endsWith('.example'),
          reason: 'simulated hosts are subdomains of the reserved TLD',
        );
      }
    });

    test('is enough to reach every site without hardcoded paths', () async {
      final (_, body) = await get('/scenarios.json');
      final manifest = jsonDecode(body) as Map<String, dynamic>;
      for (final s
          in (manifest['sites'] as List).cast<Map<String, dynamic>>()) {
        final (status, _) = await get(s['index'] as String);
        expect(
          status,
          s['pageStatus'],
          reason: '${s['id']}: the index answers with the declared status',
        );
      }
    });
  });

  group('clean merge — alpha.example and beta.example', () {
    test('alpha lists Part 1..10 with explicit printed numbering', () async {
      final a = site('alpha');
      final (status, body) = await get(a.indexPath);
      expect(status, 200);
      for (var n = a.firstPart!; n <= a.lastPart!; n++) {
        expect(body, contains('<span class="label">Part $n</span>'));
        expect(body, contains('href="${a.partPath(n)}"'));
      }
      expect(body, isNot(contains('<span class="label">Part 11</span>')));
    });

    /// The index writes its rows the way real listings write them, because a
    /// listing that separates its own label from its own metadata cannot
    /// reproduce the defect that reads them as one number.
    ///
    /// Two properties carry it, and both are asserted rather than described:
    /// the two elements are adjacent with **no whitespace between them**, so
    /// nothing but layout separates them; and one row of the index has no
    /// layout box at all, which is the case where `innerText` stops being the
    /// layout-aware reading and returns the welded characters instead.
    test('the rows carry metadata the way a real listing does', () async {
      final a = site('alpha');
      final (_, body) = await get(a.indexPath);

      for (var n = a.firstPart!; n <= a.lastPart!; n++) {
        expect(
          body,
          contains('<span class="label">Part $n</span><span class="meta">'),
          reason:
              'a space here would separate the two on its own and the row '
              'would parse correctly however it was read',
        );
      }

      expect(
        body,
        contains('<style>.label,.meta{display:block}</style>'),
        reason: 'layout is the only thing separating the label from the age',
      );

      expect(
        body,
        contains('<li style="display:none"><a href="${a.partPath(10)}"'),
        reason:
            'the last row is linked and readable but not rendered — the row '
            'the reading used to get wrong, and the only kind that can catch '
            'it coming back',
      );
    });

    test('an alpha part page prints its label and links onward', () async {
      final a = site('alpha');
      final (status, body) = await get(a.partPath(1));
      expect(status, 200);
      expect(body, contains('<html lang="en">'));
      expect(body, contains('<h1>Part 1</h1>'));
      expect(
        body,
        contains('rel="canonical" href="https://alpha.example/part/1"'),
      );
      expect(body, contains('<link rel="next" href="${a.partPath(2)}">'));
      expect(body, contains('<a rel="next" href="${a.partPath(2)}">'));
    });

    test('alpha ends at 10: no next on the last part, 404 past it', () async {
      final a = site('alpha');
      final (_, last) = await get(a.partPath(10));
      expect(last, isNot(contains('rel="next"')));
      expect(last, contains('rel="prev"'));
      final (status, _) = await get(a.partPath(11));
      expect(status, 404);
    });

    test('beta covers 5..15 in its own language, overlapping alpha', () async {
      final b = site('beta');
      final (missing, _) = await get(b.partPath(4));
      expect(missing, 404, reason: 'beta starts at Part 5');
      final (status, body) = await get(b.partPath(5));
      expect(status, 200);
      expect(body, contains('<html lang="tr">'));
      expect(body, contains('<h1>Part 5</h1>'));
      expect(body, contains('Sonraki part'));
      expect(
        body,
        contains('rel="canonical" href="https://beta.example/part/5"'),
      );
      final (tail, _) = await get(b.partPath(15));
      expect(tail, 200);
    });

    test('the overlap prints equal ordinals — the merge material', () async {
      final a = site('alpha');
      final b = site('beta');
      for (var n = b.firstPart!; n <= a.lastPart!; n++) {
        final (_, onA) = await get(a.partPath(n));
        final (_, onB) = await get(b.partPath(n));
        expect(onA, contains('<h1>${a.printedLabel(n)}</h1>'));
        expect(onB, contains('<h1>${b.printedLabel(n)}</h1>'));
        expect(a.printedLabel(n), b.printedLabel(n));
      }
    });
  });

  group('dead source — gone.example', () {
    test('answers 410 everywhere while the other sites stay alive', () async {
      final g = site('gone');
      final (index, _) = await get(g.indexPath);
      expect(index, HttpStatus.gone);
      final (part, _) = await get(g.partPath(3));
      expect(part, HttpStatus.gone);
      final (alpha, _) = await get(site('alpha').indexPath);
      expect(alpha, 200);
      final (beta, _) = await get(site('beta').partPath(7));
      expect(beta, 200);
    });
  });

  group('renumbering conflict — shifted.example', () {
    test('prints half a step below alpha for the same position', () async {
      final s = site('shifted');
      expect(s.printedNumberOffset, -0.5);
      final (status, body) = await get(s.partPath(5));
      expect(status, 200);
      expect(body, contains('<h1>Part 4.5</h1>'));
      final (_, onAlpha) = await get(site('alpha').partPath(5));
      expect(onAlpha, contains('<h1>Part 5</h1>'));
    });

    test('the contradiction holds across its whole range', () async {
      final s = site('shifted');
      final a = site('alpha');
      for (var n = s.firstPart!; n <= s.lastPart!; n++) {
        expect(
          s.printedLabel(n),
          isNot(a.printedLabel(n)),
          reason: 'position $n must never print alpha\'s number',
        );
      }
    });
  });

  group('non-numeric source — journal.example', () {
    test('the index is date-ordered and prints no part numbers', () async {
      final j = site('journal');
      final (status, body) = await get(j.indexPath);
      expect(status, 200);
      for (final post in kJournalPosts) {
        expect(body, contains('href="${j.pathPrefix}/post/${post.slug}"'));
        expect(body, contains('<time datetime="${post.date}">'));
      }
      expect(body, isNot(contains('Part ')));
    });

    test('posts chain by date through rel links, without numbers', () async {
      final j = site('journal');
      final first = kJournalPosts.first;
      final second = kJournalPosts[1];
      final (status, body) = await get('${j.pathPrefix}/post/${first.slug}');
      expect(status, 200);
      expect(body, contains('<h1>${first.title}</h1>'));
      expect(body, contains('<time datetime="${first.date}">'));
      expect(
        body,
        contains(
          '<link rel="next" href="${j.pathPrefix}/post/${second.slug}">',
        ),
      );
      expect(body, isNot(contains('Part ')));
      final (_, newest) = await get(
        '${j.pathPrefix}/post/${kJournalPosts.last.slug}',
      );
      expect(newest, isNot(contains('rel="next"')));
      final (missing, _) = await get('${j.pathPrefix}/post/no-such-post');
      expect(missing, 404);
    });
  });

  group('additivity', () {
    test('the existing fixture routes are untouched', () async {
      final (index, _) = await get('/');
      expect(index, 200);
      final (entry, entryBody) = await get('/entry/1');
      expect(entry, 200);
      expect(entryBody, contains('Fixture image sequence'));
      final (text, _) = await get('/text/1');
      expect(text, 200);
      final (unknown, _) = await get('/nowhere');
      expect(unknown, 404);
    });

    test('an unknown simulated site is a 404, not a crash', () async {
      final (status, _) = await get('/s/nosuchsite/part/1');
      expect(status, 404);
    });
  });
}
