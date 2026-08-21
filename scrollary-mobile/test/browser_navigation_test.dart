import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/browser_presentation.dart';
import 'package:web_reader/browser/history_repository.dart';

/// The navigation model (§1) and the page-state classifier (§14), asserted on
/// the state objects that actually decide them rather than through a platform
/// WebView a widget test cannot host.
void main() {
  group('presentation state', () {
    late BrowserPresentation p;

    setUp(() => p = BrowserPresentation());
    tearDown(() => p.dispose());

    test('starts on the website', () {
      expect(p.surface, BrowserSurface.website);
      expect(p.hasLocalSurface, isFalse);
    });

    test('opening Home preserves the page rather than discarding it', () {
      p.openHome(
        preserving: const PreservedPage(
          url: 'https://a.example/x',
          title: 'A page',
        ),
      );
      expect(p.surface, BrowserSurface.home);
      expect(p.hasLocalSurface, isTrue);
      expect(p.preserved!.url, 'https://a.example/x');
      expect(p.preserved!.title, 'A page');
    });

    test('returning from Home reveals the same page, unchanged', () {
      const page = PreservedPage(url: 'https://a.example/x', title: 'A page');
      p.openHome(preserving: page);
      p.showWebsite();
      expect(p.surface, BrowserSurface.website);
      // The snapshot is still there: nothing was reloaded or forgotten.
      expect(p.preserved!.url, page.url);
    });

    test('the editor opens with the URL selected from a page', () {
      p.openAddressEditor(draft: 'https://a.example/x', selectAll: true);
      expect(p.surface, BrowserSurface.editingAddress);
      expect(p.addressDraft, 'https://a.example/x');
      expect(p.selectAllOnOpen, isTrue);
    });

    test('the editor opens blank from Home', () {
      p.openHome();
      p.openAddressEditor();
      expect(p.addressDraft, isEmpty);
      expect(p.selectAllOnOpen, isFalse);
    });

    test('closing the editor can return to Home or to the page', () {
      p.openAddressEditor(draft: 'x');
      p.closeAddressEditor();
      expect(p.surface, BrowserSurface.website);

      p.openAddressEditor(draft: 'x');
      p.closeAddressEditor(toHome: true);
      expect(p.surface, BrowserSurface.home);
    });

    test('a page arriving late updates the snapshot', () {
      p.rememberPage(const PreservedPage(url: 'https://a.example/', title: ''));
      p.rememberPage(
        const PreservedPage(url: 'https://a.example/', title: 'Title'),
      );
      expect(p.preserved!.title, 'Title');
    });

    test('an empty page is never remembered', () {
      p.rememberPage(const PreservedPage(url: '', title: ''));
      expect(p.preserved, isNull);
    });

    test('clearing website data forgets the preserved page', () {
      p.openHome(
        preserving: const PreservedPage(url: 'https://a.example/', title: 'A'),
      );
      p.forgetPreserved();
      expect(p.preserved, isNull);
    });

    test('a Home request from outside is consumed exactly once', () {
      p.requestHome();
      expect(p.surface, BrowserSurface.home);
      expect(p.consumeHomeRequest(), isTrue);
      expect(p.consumeHomeRequest(), isFalse);
    });

    test('notifies on a real surface change, not on a repeat', () {
      var notifications = 0;
      p.addListener(() => notifications++);
      p.openHome();
      expect(notifications, 1);
      p.openHome();
      expect(notifications, 1, reason: 'already home');
      p.showWebsite();
      expect(notifications, 2);
    });
  });

  group('navigation source', () {
    late BrowserController browser;

    setUp(() => browser = BrowserController());
    tearDown(() => browser.dispose());

    test('is manual while nothing owns the WebView', () {
      expect(browser.isAutomating, isFalse);
      expect(browser.effectiveNavigationSource, NavigationSource.manual);
    });

    test('is the automation source while something owns it', () {
      browser.automationOwner = 'a save run';
      browser.navigationSource = NavigationSource.saveAutomation;
      expect(
        browser.effectiveNavigationSource,
        NavigationSource.saveAutomation,
      );
    });

    test('a forgotten assignment degrades to internal, never to manual', () {
      // The second guard: automation that failed to declare itself must not
      // land in the user's history (D53).
      browser.automationOwner = 'a save run';
      expect(browser.navigationSource, NavigationSource.manual);
      expect(browser.effectiveNavigationSource, NavigationSource.internal);
    });
  });

  group('completed loads', () {
    late BrowserController browser;
    late List<BrowserVisit> visits;

    setUp(() {
      browser = BrowserController();
      visits = [];
      browser.onVisitCompleted = visits.add;
    });

    tearDown(() => browser.dispose());

    test('a clean load is emitted as a visit', () async {
      browser.onLoadStart('https://a.example/x');
      await browser.onLoadStop('https://a.example/x');
      expect(visits, hasLength(1));
      expect(visits.single.url, 'https://a.example/x');
      expect(visits.single.source, NavigationSource.manual);
    });

    test('a load that faulted is not emitted', () async {
      browser.onLoadStart('https://a.example/x');
      browser.onPageFault(description: 'NSURLErrorCannotFindHost');
      await browser.onLoadStop('https://a.example/x');
      expect(visits, isEmpty);
    });

    test('a redirect is reported as one', () async {
      browser.onLoadStart('https://a.example/x');
      await browser.onLoadStop('https://a.example/y');
      expect(visits.single.wasRedirected, isTrue);
      expect(visits.single.requestedUrl, 'https://a.example/x');
      expect(visits.single.url, 'https://a.example/y');
    });

    test('starting a new load clears the previous fault', () {
      browser.onPageFault(description: 'NSURLErrorCannotFindHost');
      expect(browser.fault, isNotNull);
      browser.onLoadStart('https://a.example/x');
      expect(browser.fault, isNull);
    });
  });

  group('page fault classification', () {
    test('offline is distinguished from a site being down', () {
      expect(
        classifyPageError(description: 'anything', online: false),
        BrowserPageState.offline,
      );
      expect(
        classifyPageError(
          description: 'NSURLErrorNotConnectedToInternet',
          online: true,
        ),
        BrowserPageState.offline,
      );
    });

    test('DNS and connection failures are unreachable', () {
      for (final text in [
        'NSURLErrorCannotFindHost',
        'net::ERR_NAME_NOT_RESOLVED',
        'NSURLErrorCannotConnectToHost',
        'net::ERR_CONNECTION_REFUSED',
        'NSURLErrorTimedOut',
      ]) {
        expect(
          classifyPageError(description: text),
          BrowserPageState.unreachable,
          reason: text,
        );
      }
    });

    test('an HTTP error is the page being unavailable', () {
      expect(classifyPageError(statusCode: 404), BrowserPageState.unavailable);
      expect(classifyPageError(statusCode: 503), BrowserPageState.unavailable);
    });

    test('certificate problems are their own state', () {
      expect(
        classifyPageError(description: 'NSURLErrorServerCertificateUntrusted'),
        BrowserPageState.certificate,
      );
      expect(
        classifyPageError(description: 'net::ERR_CERT_DATE_INVALID'),
        BrowserPageState.certificate,
      );
    });

    test('a malformed address is named as one', () {
      expect(
        classifyPageError(description: 'NSURLErrorUnsupportedURL'),
        BrowserPageState.invalidAddress,
      );
    });

    test('an unknown error is honest rather than a guess', () {
      expect(
        classifyPageError(description: 'something nobody has seen'),
        BrowserPageState.unavailable,
      );
    });

    test('the raw platform text is kept for diagnostics', () {
      final browser = BrowserController();
      addTearDown(browser.dispose);
      browser.onPageFault(
        description: 'NSURLErrorCannotFindHost',
        type: 'WebResourceErrorType',
      );
      expect(browser.fault!.state, BrowserPageState.unreachable);
      expect(browser.fault!.detail, contains('NSURLErrorCannotFindHost'));
      expect(browser.lastError, contains('NSURLErrorCannotFindHost'));
    });
  });

  group('external app links', () {
    test('are classified and never loaded as a page', () async {
      final browser = BrowserController();
      addTearDown(browser.dispose);
      // No WebView attached, so `load` is a no-op — the point is the state.
      final intent = await browser.open('reader://open?entry=888');
      expect(intent.isSearch, isFalse);
      expect(browser.fault!.state, BrowserPageState.externalApp);
      expect(browser.fault!.detail, 'reader://open?entry=888');
    });
  });

  group('find in page', () {
    test('clears its own state', () async {
      final browser = BrowserController();
      addTearDown(browser.dispose);
      expect(browser.findQuery, isEmpty);
      expect(browser.findMatchCount, 0);
      expect(browser.findActiveMatch, 0);
      await browser.clearFind();
      expect(browser.findQuery, isEmpty);
    });
  });
}
