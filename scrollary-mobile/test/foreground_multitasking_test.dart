import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_surface_policy.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';
import 'package:web_reader/ui/app_page.dart';

import 'helpers/fake_browser.dart';
import 'helpers/scripted_browser.dart';

/// Foreground multitasking: one operation keeps running while the user is
/// somewhere else in the app.
///
/// The two halves that have to be true together are tested here — the guard
/// that decides when a page may be read at all, and the route mechanism that
/// keeps the WebView painted underneath another screen. See
/// docs/FOREGROUND_MULTITASKING.md.
void main() {
  group('capability seam', () {
    test('is off until a physical-device gate says otherwise', () {
      expect(ForegroundMultitasking.defaultEnabled, isFalse);
      expect(ForegroundMultitasking().preference, isFalse);
    });

    test('an unreadable stored value falls back to the default', () {
      expect(ForegroundMultitasking.parse('true'), isTrue);
      expect(ForegroundMultitasking.parse('false'), isFalse);
      expect(
        ForegroundMultitasking.parse(null),
        ForegroundMultitasking.defaultEnabled,
      );
      expect(
        ForegroundMultitasking.parse('yes'),
        ForegroundMultitasking.defaultEnabled,
      );
    });

    test('notifies once per real change', () {
      var notifications = 0;
      final capability = ForegroundMultitasking()
        ..addListener(() => notifications++);
      capability.preference = true;
      capability.preference = true;
      capability.preference = false;
      expect(notifications, 2);
    });
  });

  group('surface policy', () {
    BrowserSurfaceState resolve({
      bool capability = true,
      bool operation = true,
      bool foreground = true,
      bool browserTab = false,
      bool atShell = true,
    }) => resolveBrowserSurface(
      capabilityEnabled: capability,
      operationOwnsBrowser: operation,
      appInForeground: foreground,
      browserTabSelected: browserTab,
      atShellRoute: atShell,
    );

    test('with the capability off, leaving the Browser stops the drawing', () {
      // Exactly today's behaviour, and the rollback path.
      expect(resolve(capability: false, browserTab: true).isPainted, isTrue);
      expect(resolve(capability: false, browserTab: false).isPainted, isFalse);
      expect(
        resolve(capability: false, browserTab: true, atShell: false).isPainted,
        isFalse,
        reason: 'an opaque screen above the shell stops the compositing',
      );
      expect(resolve(capability: false).keepPainted, isFalse);
    });

    test('with it on, an operation keeps the surface alive anywhere', () {
      expect(resolve(browserTab: false).isPainted, isTrue);
      expect(resolve(browserTab: false, atShell: false).isPainted, isTrue);
      expect(resolve().keepPainted, isTrue);
    });

    test('no operation means nothing is kept alive for nothing', () {
      expect(resolve(operation: false).keepPainted, isFalse);
      expect(resolve(operation: false, browserTab: false).isPainted, isFalse);
      expect(resolve(operation: false, browserTab: true).isPainted, isTrue);
    });

    test('the app leaving the foreground always stops it', () {
      expect(resolve(foreground: false).isPainted, isFalse);
      expect(
        resolve(foreground: false, browserTab: true).isPainted,
        isFalse,
        reason: 'nothing continues once Scrollary is not in front',
      );
    });

    test('the indicator stays out of the Browser and nowhere else', () {
      expect(resolve(browserTab: true, atShell: true).browserOnScreen, isTrue);
      expect(
        resolve(browserTab: true, atShell: false).browserOnScreen,
        isFalse,
      );
      expect(resolve(browserTab: false).browserOnScreen, isFalse);
    });
  });

  group('the page-hidden contradiction', () {
    // Found on a physical iPhone against a real site: a Collection check
    // started while the Reader was open held on `pageReportsHidden` for its
    // entire budget and failed, on a page the app was drawing the whole time.
    // WebKit fixes a document's visibility when the document is created, and a
    // document created in an uncomposited view is born hidden and stays hidden.
    // An unbounded page-side veto is therefore a permanent stall.
    test('the app not drawing it holds for as long as it takes', () {
      for (final held in [Duration.zero, const Duration(minutes: 30)]) {
        expect(
          surfaceHoldReason(
            surfaceIsPainted: false,
            pageHidden: false,
            viewportHeight: 800,
            heldFor: held,
          ),
          SurfaceHold.notPainted,
          reason: 'the authoritative reason is never bounded',
        );
      }
    });

    test('no measurable layout holds for as long as it takes', () {
      expect(
        surfaceHoldReason(
          surfaceIsPainted: true,
          pageHidden: false,
          viewportHeight: 0,
          heldFor: const Duration(minutes: 30),
        ),
        SurfaceHold.unmeasurable,
      );
    });

    test('a page insisting it is hidden gets a settle window, then loses', () {
      SurfaceHold? at(Duration held) => surfaceHoldReason(
        surfaceIsPainted: true,
        pageHidden: true,
        viewportHeight: 800,
        heldFor: held,
      );
      expect(at(Duration.zero), SurfaceHold.pageReportsHidden);
      expect(
        at(kPageHiddenGrace - const Duration(seconds: 1)),
        SurfaceHold.pageReportsHidden,
      );
      expect(
        at(kPageHiddenGrace),
        isNull,
        reason:
            'past the window the app decides — a stale visibility flag must '
            'not be able to stall a run forever',
      );
    });

    test('a healthy page is never held', () {
      expect(
        surfaceHoldReason(
          surfaceIsPainted: true,
          pageHidden: false,
          viewportHeight: 800,
          heldFor: Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('the render guard', () {
    late AppDatabase db;
    late Directory root;

    const config = SaveConfig(
      scrollDelay: Duration(milliseconds: 5),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(milliseconds: 300),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
      cooldownBetweenEntries: Duration.zero,
    );

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_fg');
    });
    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// A page that measures perfectly well. Every arm below differs only in
    /// what the *app* or the *page* says about being shown.
    PageProbe healthy(int y, {bool pageHidden = false}) => lazyStripProbe(
      y: y,
      viewportHeight: 800,
      panelCount: 5,
    ).copyWithHidden(pageHidden);

    Future<List<SaveState>> statesFrom(ScriptedBrowser browser) async {
      final states = <SaveState>[];
      final engine = SaveEngine(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
        downloader: AssetFetcher(browser: browser, config: config),
        config: config,
        onProgress: (update) => states.add(update(const SaveProgress()).state),
      );
      final run = engine.saveCurrentPage(
        collectionId: 'collection-1',
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      engine.cancel();
      final result = await run;
      expect(result.status, SaveStatus.failed);
      return states;
    }

    test(
      'a healthy-looking page is not read while the app is not drawing it',
      () async {
        // The case the old viewport-only check could not see: on both
        // platforms an unpainted WebView reports a full viewport and scrolls
        // on request. Only the app knows it is not compositing.
        final browser = ScriptedBrowser(probeBuilder: (y, _) => healthy(y))
          ..setUrl('https://x.example/guide/foo/1')
          ..surfaceIsPainted = false;

        final states = await statesFrom(browser);

        expect(states, contains(SaveState.waitingForBrowser));
        expect(
          states,
          isNot(contains(SaveState.extracting)),
          reason: 'nothing may be read off a surface nobody is drawing',
        );
        expect(await db.allEntries(), isEmpty);
        expect(
          Directory(root.path).listSync(recursive: true).whereType<File>(),
          isEmpty,
        );
      },
    );

    test('a page that reports itself hidden also holds', () async {
      final browser = ScriptedBrowser(
        probeBuilder: (y, _) => healthy(y, pageHidden: true),
      )..setUrl('https://x.example/guide/foo/1');

      final states = await statesFrom(browser);

      expect(states, contains(SaveState.waitingForBrowser));
      expect(states, isNot(contains(SaveState.extracting)));
    });

    test('the same page is read normally once it is being drawn', () async {
      // Not drawn for the first five probes, drawn afterwards. Downloads have
      // no server, so the run fails there — the point is that it got past the
      // guard rather than holding forever.
      var probes = 0;
      final browser = ScriptedBrowser(
        probeBuilder: (y, n) {
          probes = n;
          return healthy(y);
        },
      )..setUrl('https://x.example/guide/foo/1');
      browser.surfaceIsPainted = false;

      final engine = SaveEngine(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
        downloader: AssetFetcher(browser: browser, config: config),
        config: config,
      );
      final run = engine.saveCurrentPage(
        collectionId: 'collection-1',
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(probes, greaterThan(0), reason: 'it kept checking while holding');
      browser.surfaceIsPainted = true;

      final result = await run;
      expect(result.error, 'No images could be downloaded');
    });

    test('the update checker holds on the same signal', () async {
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 's1',
          title: 'Foo',
          sourceUrl: 'https://x.example/guide/foo',
          host: 'x.example',
          collectionKey: '/guide/foo',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'c1',
          collectionId: 's1',
          title: 'Foo Entry 1',
          sourceUrl: 'https://x.example/guide/foo/1',
          urlKey: 'https://x.example/guide/foo/1',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/s1/entries/c1',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 3,
          storedAssetCount: 3,
          entryOrder: 1,
          byteSize: 1024,
          entryNumber: 1,
          sourceMarker: 'Entry 1',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );

      final browser = ScriptedBrowser(probeBuilder: (y, _) => healthy(y))
        ..setUrl('https://x.example/guide/foo/1')
        ..surfaceIsPainted = false;
      final checker = UpdateChecker(browser: browser, db: db);

      final outcome = checker.check('s1');
      // Past `awaitPaintedSurface`'s window: the checker now declines to open
      // the first page until the app is drawing the WebView, so the hold it
      // reports afterwards is the guard, not the wait.
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(checker.log.join('\n'), contains('open the Browser'));
      checker.cancel();
      final result = await outcome;
      expect(
        result.state,
        anyOf(UpdateCheckState.cancelled, UpdateCheckState.failed),
      );
    });
  });

  group('renderer termination', () {
    late AppDatabase db;
    late Directory root;

    const config = SaveConfig(
      scrollDelay: Duration(milliseconds: 5),
      fastScrollDelay: Duration(milliseconds: 1),
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollPasses: 1,
      maxAssetWait: Duration(milliseconds: 300),
      domReadyTimeout: Duration(seconds: 2),
      downloadRetries: 0,
      cooldownBetweenEntries: Duration.zero,
    );

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_rt');
    });
    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a terminated renderer is named, not left as a timeout', () {
      final browser = FakeBrowser();
      expect(browser.fault, isNull);
      browser.onRendererTerminated();
      expect(
        browser.fault,
        isNotNull,
        reason: 'the death of the page is recorded as a page fault',
      );
      expect(browser.fault!.detail, contains('stopped responding'));
      expect(browser.isLoading, isFalse);
    });

    test('an Entry in flight when the renderer dies is never committed', () {
      // The renderer dying mid-run looks, from Dart, exactly like a page that
      // stopped answering. The rule is the same either way and it is the one
      // that matters: whatever was measured a moment ago is no longer true, so
      // nothing may be written from it.
      final browser = ScriptedBrowser(
        probeBuilder: (y, n) {
          if (n > 4) throw StateError('web content process terminated');
          return lazyStripProbe(y: y, viewportHeight: 800, panelCount: 5);
        },
      )..setUrl('https://x.example/guide/foo/1');

      final engine = SaveEngine(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
        downloader: AssetFetcher(browser: browser, config: config),
        config: config,
      );

      return engine
          .saveCurrentPage(
            collectionId: 'collection-1',
            entryOrder: 1,
            visitedNormalized: {},
            captureMode: CaptureMode.imageSequence,
          )
          .then((result) async {
            expect(
              result.status,
              isNot(SaveStatus.complete),
              reason: 'a run whose page died may never report success',
            );
            expect(
              await db.allEntries(),
              isEmpty,
              reason: 'and it may never leave an Entry behind',
            );
            expect(
              Directory(root.path).listSync(recursive: true).whereType<File>(),
              isEmpty,
              reason: 'nor any bytes',
            );
          });
    });
  });

  group('AppPage keeps what is below it painted', () {
    /// The whole mechanism in one assertion: with the flag off the route is
    /// opaque, so Flutter stops painting the screen underneath; with it on the
    /// route is not opaque, so it carries on.
    testWidgets('route opacity follows the flag, live', (tester) async {
      final keep = ValueNotifier<bool>(false);
      addTearDown(keep.dispose);

      late final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('below')),
        ),
      );

      final page = AppPage<void>(
        keepBelowPainted: keep,
        child: const Scaffold(body: Text('above')),
      );
      final route = page.createRoute(navKey.currentContext!);
      expect(route, isA<PageRoute<void>>());
      expect(
        (route as PageRoute<void>).opaque,
        isTrue,
        reason: 'off by default: today\'s behaviour, and today\'s cost',
      );

      keep.value = true;
      expect(
        route.opaque,
        isFalse,
        reason: 'a non-opaque route is what keeps the WebView below alive',
      );

      keep.value = false;
      expect(route.opaque, isTrue, reason: 'and it goes back');
    });

    testWidgets('the screen below is still built and painted', (tester) async {
      final keep = ValueNotifier<bool>(true);
      addTearDown(keep.dispose);
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('below')),
        ),
      );
      navKey.currentState!.push(
        AppPage<void>(
          keepBelowPainted: keep,
          child: const Scaffold(body: Text('above')),
        ).createRoute(navKey.currentContext!),
      );
      await tester.pumpAndSettle();

      expect(find.text('above'), findsOneWidget);
      expect(
        find.text('below'),
        findsOneWidget,
        reason: 'the shell underneath must still be in the tree and drawn',
      );
    });

    testWidgets(
      'a screen already open starts painting when the flag turns on',
      (tester) async {
        // The ordinary case, and the one that is easy to get wrong: the user
        // opens an Entry, *then* starts a check. The screen they are on has to
        // stop being opaque underneath them.
        final keep = ValueNotifier<bool>(false);
        addTearDown(keep.dispose);
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('below')),
          ),
        );
        navKey.currentState!.push(
          AppPage<void>(
            keepBelowPainted: keep,
            child: const Scaffold(body: Text('above')),
          ).createRoute(navKey.currentContext!),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('below'),
          findsNothing,
          reason: 'an opaque route takes the screen below out of the frame',
        );

        keep.value = true;
        await tester.pumpAndSettle();

        expect(
          find.text('below'),
          findsOneWidget,
          reason: 'flipping the flag has to reach a route that is already up',
        );
      },
    );
  });
}

/// Small local helper: the fixtures build a settled page; these tests need the
/// same page with one extra bit set.
extension on PageProbe {
  PageProbe copyWithHidden(bool hidden) => PageProbe(
    url: url,
    title: title,
    canonicalUrl: canonicalUrl,
    readyState: readyState,
    documentHeight: documentHeight,
    viewportHeight: viewportHeight,
    viewportWidth: viewportWidth,
    pageHidden: hidden,
    scrollY: scrollY,
    images: images,
    links: links,
    headNextHref: headNextHref,
    atBottom: atBottom,
    imagesTruncated: imagesTruncated,
    imageCount: imageCount,
    imageOffset: imageOffset,
    pageHints: pageHints,
    content: content,
    media: media,
    access: access,
  );
}
