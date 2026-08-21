import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/url_utils.dart';

void main() {
  group('normalizeUrl', () {
    test('lowercases scheme and host, drops the default port', () {
      expect(
        normalizeUrl('HTTPS://Example.COM:443/Entry/1'),
        'https://example.com/Entry/1',
      );
    });

    test('drops the fragment and tracking params, sorts the rest', () {
      expect(
        normalizeUrl('https://x.example/c/1?utm_source=rss&b=2&a=1#comments'),
        'https://x.example/c/1?a=1&b=2',
      );
    });

    test('collapses duplicate slashes and strips a trailing slash', () {
      expect(normalizeUrl('https://x.example//a//b/'), 'https://x.example/a/b');
      expect(normalizeUrl('https://x.example/'), 'https://x.example/');
    });

    test('keeps www and the scheme — they can be distinct origins', () {
      expect(
        normalizeUrl('https://www.x.example/a'),
        isNot(normalizeUrl('https://x.example/a')),
      );
      expect(
        normalizeUrl('http://x.example/a'),
        isNot(normalizeUrl('https://x.example/a')),
      );
    });
  });

  group('resolveUrl', () {
    test('resolves relative hrefs against the page URL', () {
      expect(
        resolveUrl('https://x.example/collection/foo/entry-1', '../entry-2'),
        'https://x.example/collection/entry-2',
      );
      expect(
        resolveUrl('https://x.example/a/b', '/c/d'),
        'https://x.example/c/d',
      );
    });
  });

  group('validateNextUrl — loop and scope prevention', () {
    const current = 'https://x.example/entry/1';

    test('accepts a same-host forward link', () {
      final check = validateNextUrl(
        candidate: '/entry/2',
        currentUrl: current,
        visited: {normalizeUrl(current)},
      );
      expect(check.isAccepted, isTrue);
      expect(check.normalized, 'https://x.example/entry/2');
    });

    test('rejects the current URL', () {
      final check = validateNextUrl(
        candidate: current,
        currentUrl: current,
        visited: {},
      );
      expect(check.rejection, NextUrlRejection.sameAsCurrent);
    });

    test('rejects a URL differing only by fragment as the current page', () {
      final check = validateNextUrl(
        candidate: '$current#end',
        currentUrl: current,
        visited: {},
      );
      expect(check.rejection, NextUrlRejection.sameAsCurrent);
    });

    test('rejects an already-visited URL — this is the loop guard', () {
      final check = validateNextUrl(
        candidate: 'https://x.example/entry/1',
        currentUrl: 'https://x.example/entry/2',
        visited: {'https://x.example/entry/1'},
      );
      expect(check.rejection, NextUrlRejection.alreadyVisited);
    });

    test('rejects a different host unless explicitly allowed', () {
      final check = validateNextUrl(
        candidate: 'https://other.example/entry/2',
        currentUrl: current,
        visited: {},
      );
      expect(check.rejection, NextUrlRejection.differentHost);
      expect(check.crossHost, isTrue);

      final allowed = validateNextUrl(
        candidate: 'https://other.example/entry/2',
        currentUrl: current,
        visited: {},
        allowCrossHost: true,
      );
      expect(allowed.isAccepted, isTrue);
    });

    test('rejects non-http schemes', () {
      for (final candidate in [
        'javascript:void(0)',
        'mailto:a@b.example',
        'ftp://x.example/f',
      ]) {
        final check = validateNextUrl(
          candidate: candidate,
          currentUrl: current,
          visited: {},
        );
        expect(check.isAccepted, isFalse, reason: candidate);
      }
    });

    test('rejects auth-shaped destinations', () {
      for (final candidate in ['/login', '/account/signin', '/register']) {
        final check = validateNextUrl(
          candidate: candidate,
          currentUrl: current,
          visited: {},
        );
        expect(check.rejection, NextUrlRejection.denyListed, reason: candidate);
      }
    });
  });
}
