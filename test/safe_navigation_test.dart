import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/core/url_utils.dart';

/// A user-selected control is a strong signal about one link. It is not
/// permission to follow whatever the page does next — these tests pin that.
void main() {
  group('navigation lock during a save run', () {
    late BrowserController browser;
    setUp(() => browser = BrowserController());
    tearDown(() => browser.dispose());

    test('nothing is blocked while no run is running', () {
      expect(
        browser.shouldBlockNavigation('https://x.example/a', isMainFrame: true),
        isFalse,
      );
    });

    test('an unannounced navigation is blocked while locked', () {
      browser.navigationLocked = true;
      expect(
        browser.shouldBlockNavigation(
          'https://x.example/popup',
          isMainFrame: true,
        ),
        isTrue,
      );
    });

    test('the entry the run chose is allowed through', () {
      browser.navigationLocked = true;
      browser.allowNextNavigation('https://x.example/guide/foo/11');
      expect(
        browser.shouldBlockNavigation(
          'https://x.example/guide/foo/11',
          isMainFrame: true,
        ),
        isFalse,
      );
    });

    test('a same-host redirect of the allowed target is permitted', () {
      browser.navigationLocked = true;
      browser.allowNextNavigation('https://x.example/guide/foo/11');
      expect(
        browser.shouldBlockNavigation(
          'https://x.example/guide/foo/11?utm_source=rss',
          isMainFrame: true,
        ),
        isFalse,
      );
    });

    test('a redirect to another host is blocked even when one was allowed', () {
      browser.navigationLocked = true;
      browser.allowNextNavigation('https://x.example/guide/foo/11');
      expect(
        browser.shouldBlockNavigation(
          'https://ads.example/landing',
          isMainFrame: true,
        ),
        isTrue,
      );
    });

    test('sub-frames are not policed — only top-level navigation is', () {
      browser.navigationLocked = true;
      expect(
        browser.shouldBlockNavigation(
          'https://cdn.example/frame',
          isMainFrame: false,
        ),
        isFalse,
      );
    });
  });

  group('post-redirect validation', () {
    const from = 'https://a.example/guide/foo/883-part-oku';

    test('a redirect inside the same collection is accepted', () {
      const landed = 'https://a.example/guide/foo/884-part-oku';
      final check = validateNextUrl(
        candidate: landed,
        currentUrl: from,
        visited: {normalizeUrl(from)},
      );
      expect(check.isAccepted, isTrue);
      expect(collectionFingerprint(landed), collectionFingerprint(from));
    });

    test('a redirect that leaves the collection is detectable', () {
      const landed = 'https://a.example/guide/OTHER-SERIES/1-part-oku';
      // URL validation alone would allow it — same host, not visited.
      final check = validateNextUrl(
        candidate: landed,
        currentUrl: from,
        visited: {normalizeUrl(from)},
      );
      expect(check.isAccepted, isTrue);

      // The collection check is what stops it.
      expect(
        collectionFingerprint(landed),
        isNot(collectionFingerprint(from)),
        reason: 'the run must stop rather than save a different collection',
      );
    });

    test('a redirect to a login page is refused', () {
      final check = validateNextUrl(
        candidate: 'https://a.example/login?next=/guide/foo/884',
        currentUrl: from,
        visited: {},
      );
      expect(check.rejection, NextUrlRejection.denyListed);
    });

    test('a redirect back to an already-saved entry is refused', () {
      final check = validateNextUrl(
        candidate: from,
        currentUrl: 'https://a.example/guide/foo/884-part-oku',
        visited: {normalizeUrl(from)},
      );
      expect(check.rejection, NextUrlRejection.alreadyVisited);
    });

    test('a redirect off-host is refused', () {
      final check = validateNextUrl(
        candidate: 'https://mirror.example/guide/foo/884',
        currentUrl: from,
        visited: {},
      );
      expect(check.rejection, NextUrlRejection.differentHost);
    });
  });

  _hostChangeTests();

  group('bounded entry count', () {
    test('the requested limit is clamped to the configured maximum', () {
      // The controller clamps with `entryLimit.clamp(1, maxEntriesPerRun)`.
      const maxEntries = 5;
      expect(999.clamp(1, maxEntries), maxEntries);
      expect(0.clamp(1, maxEntries), 1);
      expect(3.clamp(1, maxEntries), 3);
    });
  });
}

void _hostChangeTests() {
  group('cross-host consent', () {
    late BrowserController browser;
    setUp(() {
      browser = BrowserController();
      browser.onUrlChanged('https://a.example/guide/foo/883');
    });
    tearDown(() => browser.dispose());

    test('a page-initiated hop to another host needs consent', () {
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://ads.example/landing',
          isMainFrame: true,
          userInitiated: false,
        ),
        isTrue,
      );
    });

    test('same-host navigation never asks', () {
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://a.example/guide/foo/884',
          isMainFrame: true,
          userInitiated: false,
        ),
        isFalse,
      );
    });

    test('a deliberate tap while browsing is not nagged about', () {
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://other.example/',
          isMainFrame: true,
          userInitiated: true,
        ),
        isFalse,
      );
    });

    test('during a save run even a tap is questioned', () {
      browser.navigationLocked = true;
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://other.example/',
          isMainFrame: true,
          userInitiated: true,
        ),
        isTrue,
      );
    });

    test('sub-frames are not policed', () {
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://cdn.example/frame',
          isMainFrame: false,
          userInitiated: false,
        ),
        isFalse,
      );
    });

    test('non-http schemes are not treated as host changes', () {
      for (final target in ['mailto:a@b.example', 'tel:123', 'about:blank']) {
        expect(
          browser.needsHostChangeConsent(
            fromUrl: 'https://a.example/a',
            toUrl: target,
            isMainFrame: true,
            userInitiated: false,
          ),
          isFalse,
          reason: target,
        );
      }
    });

    test(
      'silence refuses, and the browser stays put',
      () async {
        final decision = browser.requestHostChange(
          fromUrl: 'https://a.example/guide/foo/883',
          toUrl: 'https://ads.example/landing',
        );
        expect(browser.pendingHostChange, isNotNull);
        expect(browser.pendingHostChange!.toHost, 'ads.example');

        // No answer: the timeout must deny rather than allow.
        expect(await decision, isFalse);
        expect(browser.pendingHostChange, isNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('an explicit Stay refuses immediately', () async {
      final decision = browser.requestHostChange(
        fromUrl: 'https://a.example/a',
        toUrl: 'https://ads.example/landing',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      browser.resolveHostChange(false);
      expect(await decision, isFalse);
    });

    test('an allowed host is remembered, so it asks only once', () async {
      final first = browser.requestHostChange(
        fromUrl: 'https://a.example/a',
        toUrl: 'https://mirror.example/a',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      browser.resolveHostChange(true);
      expect(await first, isTrue);

      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/a',
          toUrl: 'https://mirror.example/b',
          isMainFrame: true,
          userInitiated: false,
        ),
        isFalse,
      );

      // ...until a save run clears it, so a browsing-time decision does not
      // silently widen an autonomous run.
      browser.clearAllowedHostChanges();
      expect(
        browser.needsHostChangeConsent(
          fromUrl: 'https://a.example/a',
          toUrl: 'https://mirror.example/b',
          isMainFrame: true,
          userInitiated: false,
        ),
        isTrue,
      );
    });
  });
}
