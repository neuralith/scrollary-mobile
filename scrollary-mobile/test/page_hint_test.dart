import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/page_hint.dart';

void main() {
  group('collectionFingerprint', () {
    test('strips a numeric entry segment', () {
      expect(
        collectionFingerprint(
          'https://x.example/comics/genius-archers/entry/101',
        ),
        '/comics/genius-archers',
      );
    });

    test('strips a Turkish entry slug', () {
      expect(
        collectionFingerprint(
          'https://x.example/guide/efsanevi-buyu/883-part-oku',
        ),
        '/guide/efsanevi-buyu',
      );
    });

    test('strips a German entry slug', () {
      expect(
        collectionFingerprint('https://x.example/guide/held/kapitel-42'),
        '/guide/held',
      );
    });

    test('consecutive entries of one collection share a fingerprint', () {
      expect(
        collectionFingerprint('https://x.example/guide/foo/883-part-oku'),
        collectionFingerprint('https://x.example/guide/foo/884-part-oku'),
      );
    });

    test('different collection never share a fingerprint', () {
      expect(
        collectionFingerprint('https://x.example/guide/foo/1'),
        isNot(collectionFingerprint('https://x.example/guide/bar/1')),
      );
    });
  });

  group('hrefPatternFrom', () {
    test('generalises the entry number', () {
      final pattern = hrefPatternFrom(
        'https://x.example/guide/foo/883-part-oku',
      );
      expect(RegExp(pattern!).hasMatch('/guide/foo/883-part-oku'), isTrue);
      expect(RegExp(pattern).hasMatch('/guide/foo/884-part-oku'), isTrue);
      expect(RegExp(pattern).hasMatch('/guide/bar/884-part-oku'), isFalse);
    });

    test('returns null when there is no number to generalise', () {
      expect(hrefPatternFrom('https://x.example/guide/foo/latest'), isNull);
    });
  });

  group('DomLocator', () {
    test('round-trips through JSON', () {
      const locator = DomLocator(
        tag: 'a',
        rel: 'next',
        cssSelector: 'a.next-entry',
        containerSelector: 'nav',
        linkText: 'Sonraki part',
        hrefPattern: r'^/guide/foo/(\d+)$',
      );
      final restored = DomLocator.decode(locator.encode());

      expect(restored.rel, 'next');
      expect(restored.cssSelector, 'a.next-entry');
      expect(restored.linkText, 'Sonraki part');
      expect(restored.hrefPattern, r'^/guide/foo/(\d+)$');
    });

    test('counts independent signals and flags a weak locator', () {
      const weak = DomLocator(tag: 'a', linkText: 'next');
      expect(weak.signalCount, 1);
      expect(weak.isWeak, isTrue);

      const strong = DomLocator(
        tag: 'a',
        rel: 'next',
        cssSelector: 'a.nav-next',
        hrefPattern: r'^/c/(\d+)$',
      );
      expect(strong.signalCount, 3);
      expect(strong.isWeak, isFalse);
    });
  });

  group('rule scoping', () {
    UserPageHint rule({
      required HintScope scope,
      String? hintPath,
      String host = 'x.example',
      HintKind kind = HintKind.nextLink,
      DateTime? created,
    }) => UserPageHint(
      id: '$scope-$hintPath-$kind',
      host: host,
      hintPath: hintPath,
      scope: scope,
      kind: kind,
      locator: const DomLocator(rel: 'next'),
      createdAt: created ?? DateTime(2026, 1, 1),
    );

    test('a collection rule matches only its own collection', () {
      final r = rule(scope: HintScope.collection, hintPath: '/guide/foo');

      expect(
        r.matches(
          'https://x.example/guide/foo/884-part-oku',
          kindName: 'nextLink',
        ),
        isTrue,
      );
      expect(
        r.matches(
          'https://x.example/guide/bar/884-part-oku',
          kindName: 'nextLink',
        ),
        isFalse,
        reason: 'a rule learned on one collection must not leak to another',
      );
    });

    test(
      'a host rule matches any collection on that host, and no other host',
      () {
        final r = rule(scope: HintScope.host);

        expect(
          r.matches('https://x.example/guide/anything/1', kindName: 'nextLink'),
          isTrue,
        );
        expect(
          r.matches('https://other.example/guide/foo/1', kindName: 'nextLink'),
          isFalse,
        );
      },
    );

    test('a path-pattern rule matches the same URL shape', () {
      final shape = pathShape('/guide/foo/883-part-oku');
      final r = rule(scope: HintScope.pathPattern, hintPath: shape);

      expect(
        r.matches(
          'https://x.example/guide/bar/12-part-oku',
          kindName: 'nextLink',
        ),
        isTrue,
      );
      expect(
        r.matches('https://x.example/novel/bar/12', kindName: 'nextLink'),
        isFalse,
      );
    });

    test('kind is part of matching — a reader rule is not a next rule', () {
      final r = rule(scope: HintScope.host, kind: HintKind.readerArea);
      expect(
        r.matches('https://x.example/a/1', kindName: 'readerArea'),
        isTrue,
      );
      expect(r.matches('https://x.example/a/1', kindName: 'nextLink'), isFalse);
    });

    test('the narrowest matching rule wins', () {
      final rules = [
        rule(scope: HintScope.host),
        rule(scope: HintScope.pathPattern, hintPath: pathShape('/guide/foo/1')),
        rule(scope: HintScope.collection, hintPath: '/guide/foo'),
      ];

      final best = bestMatchingHint(
        rules,
        'https://x.example/guide/foo/884-part-oku',
        kind: HintKind.nextLink,
      );
      expect(best!.scope, HintScope.collection);
    });

    test('ties break toward the most recently used rule', () {
      final older = UserPageHint(
        id: 'older',
        host: 'x.example',
        hintPath: '/guide/foo',
        scope: HintScope.collection,
        kind: HintKind.nextLink,
        locator: const DomLocator(rel: 'next'),
        createdAt: DateTime(2026, 1, 1),
        lastUsedAt: DateTime(2026, 1, 2),
      );
      final newer = UserPageHint(
        id: 'newer',
        host: 'x.example',
        hintPath: '/guide/foo',
        scope: HintScope.collection,
        kind: HintKind.nextLink,
        locator: const DomLocator(rel: 'next'),
        createdAt: DateTime(2026, 1, 1),
        lastUsedAt: DateTime(2026, 6, 1),
      );

      final best = bestMatchingHint(
        [older, newer],
        'https://x.example/guide/foo/1',
        kind: HintKind.nextLink,
      );
      expect(best!.id, 'newer');
    });

    test('no rule matches an unrelated host', () {
      final best = bestMatchingHint(
        [rule(scope: HintScope.host)],
        'https://elsewhere.example/guide/foo/1',
        kind: HintKind.nextLink,
      );
      expect(best, isNull);
    });
  });
}
