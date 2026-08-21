import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_url.dart';

/// What the Browser does with a line of text (§6). Pure, so it is asserted
/// directly rather than through a WebView.
void main() {
  group('interpretUrlInput', () {
    test('a full URL is navigated to, untouched', () {
      final intent = interpretUrlInput('https://example.com/path?a=1');
      expect(intent.kind, UrlIntentKind.navigate);
      expect(intent.url, 'https://example.com/path?a=1');
      expect(intent.addedScheme, isFalse);
    });

    test('a bare host gets https and keeps its path and query', () {
      final intent = interpretUrlInput('example.com/guide/x?lang=tr');
      expect(intent.kind, UrlIntentKind.navigate);
      expect(intent.url, 'https://example.com/guide/x?lang=tr');
      expect(intent.addedScheme, isTrue);
    });

    test('a valid hostname is never searched for', () {
      for (final host in [
        'example.com',
        'sub.example.co.uk',
        'example.com/comics/x/entry/137',
        'example.com:8443/x',
      ]) {
        expect(
          interpretUrlInput(host).kind,
          UrlIntentKind.navigate,
          reason: host,
        );
      }
    });

    test('prose becomes a Google search', () {
      final intent = interpretUrlInput('baekmyeong entry 234');
      expect(intent.kind, UrlIntentKind.search);
      expect(intent.query, 'baekmyeong entry 234');
      expect(intent.url, startsWith('https://www.google.com/search?q='));
      expect(intent.url, contains('baekmyeong'));
    });

    test('a dotted word inside a sentence is still a search', () {
      // "see example.com for details" is prose, not an address.
      final intent = interpretUrlInput('see example.com for details');
      expect(intent.kind, UrlIntentKind.search);
    });

    test('a single word with no dot is a search', () {
      expect(interpretUrlInput('guide').kind, UrlIntentKind.search);
    });

    test('a trailing or leading dot is a typo, not a host', () {
      expect(interpretUrlInput('example.').kind, UrlIntentKind.search);
      expect(interpretUrlInput('.com').kind, UrlIntentKind.search);
    });

    test('empty input does nothing', () {
      expect(interpretUrlInput('').isEmpty, isTrue);
      expect(interpretUrlInput('   ').isEmpty, isTrue);
    });

    test('localhost is an address in debug and a search otherwise', () {
      expect(
        interpretUrlInput('localhost:8099/entry/1', allowLocalhost: true).kind,
        UrlIntentKind.navigate,
      );
      expect(
        interpretUrlInput('localhost:8099/entry/1', allowLocalhost: false).kind,
        UrlIntentKind.search,
      );
    });

    test('a non-web scheme is handed back as-is, never searched', () {
      final intent = interpretUrlInput('reader://open?entry=888');
      expect(intent.kind, UrlIntentKind.navigate);
      expect(isExternalAppScheme(intent.url), isTrue);
      expect(isExternalAppScheme('mailto:someone@example.com'), isTrue);
      expect(isExternalAppScheme('https://example.com'), isFalse);
    });

    test('a host:port is a host and a port, not a scheme', () {
      // The colon here is not a scheme separator. Reading it as one sent
      // `example.com:8443` to the platform as an app link.
      expect(isExternalAppScheme('example.com:8443/x'), isFalse);
      expect(isExternalAppScheme('localhost:8099/entry/1'), isFalse);
      final intent = interpretUrlInput('example.com:8443/x');
      expect(intent.kind, UrlIntentKind.navigate);
      expect(intent.url, 'https://example.com:8443/x');
    });
  });

  group('display helpers', () {
    test('displayHost drops www for reading, not for identity', () {
      expect(displayHost('https://www.google.com/'), 'google.com');
      expect(displayHost('https://example.com/x'), 'example.com');
    });

    test('compactPath elides the middle and keeps the entry', () {
      final path = compactPath(
        'https://example.com/guide/the-long-guide/885-part-oku',
      );
      expect(path, startsWith('/…/'));
      expect(path, contains('885-part-oku'));
    });

    test('compactPath is empty for a bare host', () {
      expect(compactPath('https://example.com/'), '');
      expect(compactPath('https://example.com'), '');
    });

    test('shortUrl drops the scheme and bounds the length', () {
      expect(shortUrl('https://example.com/'), 'example.com');
      final long = shortUrl('https://example.com/${'a' * 200}');
      expect(long.length, lessThanOrEqualTo(44));
      expect(long, endsWith('…'));
    });

    test('faviconInitial is the first letter after www', () {
      expect(faviconInitial('www.google.com'), 'G');
      // Without a `www.` to skip, the first letter of the host is the initial.
      expect(faviconInitial('a.example'), 'A');
      expect(faviconInitial('www.b.example'), 'B');
    });
  });

  group('siteRootFor', () {
    test('derives a root for an ordinary https page', () {
      expect(
        siteRootFor('https://example.com/guide/x/1'),
        'https://example.com/',
      );
    });

    test('refuses when the origin carries anything unusual', () {
      // A non-default port or userinfo means "this page", not "this site" —
      // guessing a homepage there would save the wrong thing (§5).
      expect(siteRootFor('https://example.com:8443/x'), isNull);
      expect(siteRootFor('https://user@example.com/x'), isNull);
      expect(siteRootFor('reader://open'), isNull);
      expect(siteRootFor('not a url'), isNull);
    });
  });
}
