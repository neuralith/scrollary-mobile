import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/core/connectivity.dart';
import 'package:web_reader/features/open_in_browser.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';
import 'helpers/v2_harness.dart';

/// Making the Browser visible, and asking before taking it away from a run.
///
/// The bug this file exists to prevent: the action told the Browser
/// controller and flipped the shell's tab index, but the user was standing on
/// a route pushed *above* the shell, so nothing they could see changed. The
/// URL loaded into a Browser nobody was looking at.
///
/// Its sibling `open_in_browser_test.dart` owns the pending-request contract
/// and the drain into the WebView; everything here is the half that moves the
/// user — the pop, the tab, and the one modal that may stand in the way.
class _AlwaysOnline implements Connectivity {
  const _AlwaysOnline();

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<bool> canReach(String host) async => true;
}

/// Counts what the navigator was actually asked to do, so "it pops rather
/// than pushes" is asserted as the mechanism rather than inferred from what
/// happens to be on screen.
class _RouteLog extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;

  void reset() {
    pushes = 0;
    pops = 0;
  }
}

void main() {
  const url = 'https://a.example/x';

  late FakeBrowser browser;
  late FileStore fileStore;
  late V2Harness v2;
  late BrowserNavigator navigator;
  late ValueNotifier<int?> tabRequest;
  late _RouteLog routes;
  late GoRouter router;

  setUp(() {
    browser = FakeBrowser();
    fileStore = tempFileStore();
    v2 = V2Harness(browser: browser, fileStore: fileStore);
    navigator = BrowserNavigator();
    tabRequest = ValueNotifier<int?>(null);
    routes = _RouteLog();
  });

  tearDown(() async {
    navigator.dispose();
    tabRequest.dispose();
    await v2.close();
  });

  /// A shell at `/`, a `/collection` pushed above it and a `/reader` above
  /// that — the exact stack the bug lived in, at one and at two routes deep.
  ///
  /// [action] is built on all three, so the same call can be made from the
  /// shell itself and from either pushed route.
  Widget app(void Function(BuildContext, WidgetRef) action) {
    Widget page(String label, String? next) => Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Column(
          children: [
            Text(label),
            if (next != null)
              TextButton(
                onPressed: () => context.push(next),
                child: Text('to $next'),
              ),
            TextButton(
              onPressed: () => action(context, ref),
              child: Text('act on $label'),
            ),
          ],
        ),
      ),
    );

    router = GoRouter(
      initialLocation: '/',
      observers: [routes],
      routes: [
        GoRoute(path: '/', builder: (_, _) => page('SHELL', '/collection')),
        GoRoute(
          path: '/collection',
          builder: (_, _) => page('COLLECTION', '/reader'),
        ),
        GoRoute(path: '/reader', builder: (_, _) => page('READER', null)),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        fileStoreProvider.overrideWithValue(fileStore),
        browserProvider.overrideWithValue(browser),
        v2ServicesProvider.overrideWithValue(v2.services),
        browserNavigatorProvider.overrideWithValue(navigator),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        connectivityProvider.overrideWithValue(const _AlwaysOnline()),
      ],
      child: MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
  }

  /// Walk up to [label], then forget how we got there: every assertion about
  /// pushes and pops is about the action, not about the walk.
  Future<void> standOn(WidgetTester tester, String label) async {
    if (label != 'SHELL') {
      await tester.tap(find.text('to /collection'));
      await tester.pumpAndSettle();
    }
    if (label == 'READER') {
      await tester.tap(find.text('to /reader'));
      await tester.pumpAndSettle();
    }
    expect(find.text(label), findsOneWidget);
    routes.reset();
  }

  Future<void> act(WidgetTester tester, String label) async {
    await tester.tap(find.text('act on $label'));
    await tester.pumpAndSettle();
  }

  group('showing the Browser from a route above the shell', () {
    testWidgets('one route up, the shell comes back and the Browser tab is '
        'selected', (tester) async {
      await tester.pumpWidget(app(showBrowserSurface));
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      // The regression, stated directly: the user must not still be looking
      // at the route they started on.
      expect(find.text('COLLECTION'), findsNothing);
      expect(find.text('SHELL'), findsOneWidget);
      expect(tabRequest.value, 1, reason: 'the Browser section is selected');
    });

    testWidgets('two routes up, every pushed route is left behind', (
      tester,
    ) async {
      await tester.pumpWidget(app(showBrowserSurface));
      await standOn(tester, 'READER');

      await act(tester, 'READER');

      expect(find.text('READER'), findsNothing);
      expect(find.text('COLLECTION'), findsNothing);
      expect(find.text('SHELL'), findsOneWidget);
      expect(tabRequest.value, 1);
      expect(routes.pops, 2, reason: 'both pushed routes were popped');
    });

    testWidgets('it pops rather than pushes, so there is no second shell '
        'route', (tester) async {
      await tester.pumpWidget(app(showBrowserSurface));
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(routes.pushes, 0, reason: 'nothing is navigated forward');
      expect(routes.pops, 1);
      expect(find.text('SHELL'), findsOneWidget);
    });

    testWidgets('the shell is the bottom of the stack afterwards', (
      tester,
    ) async {
      await tester.pumpWidget(app(showBrowserSurface));
      await standOn(tester, 'READER');

      await act(tester, 'READER');

      // App-level back leaves the app rather than re-entering the reader.
      expect(router.canPop(), isFalse);
    });

    testWidgets('a caller that already holds the router gets the same two '
        'steps', (tester) async {
      // The running-operation indicator lives above the router's inherited
      // widget and cannot reach one from its context, so it passes the router
      // the app already owns.
      await tester.pumpWidget(
        app((context, ref) => showBrowserSurfaceWith(router, ref)),
      );
      await standOn(tester, 'READER');

      await act(tester, 'READER');

      expect(find.text('SHELL'), findsOneWidget);
      expect(tabRequest.value, 1);
      expect(routes.pushes, 0);
      expect(router.canPop(), isFalse);
    });
  });

  group('already on the Browser', () {
    testWidgets('asking again pushes nothing and pops nothing extra', (
      tester,
    ) async {
      await tester.pumpWidget(app(showBrowserSurface));
      await standOn(tester, 'SHELL');
      tabRequest.value = 1;

      await act(tester, 'SHELL');

      expect(routes.pushes, 0);
      expect(routes.pops, 0);
      expect(tabRequest.value, 1);
      expect(router.canPop(), isFalse);
      expect(find.text('SHELL'), findsOneWidget);
    });
  });

  group('a page there is no way to open', () {
    testWidgets('an empty URL says why, switches no section and leaves '
        'nothing pending', (tester) async {
      await tester.pumpWidget(
        app((context, ref) => openInBrowser(context, ref, '')),
      );
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(find.text(kNoSourcePageMessage), findsOneWidget);
      // Still exactly where they were.
      expect(find.text('COLLECTION'), findsOneWidget);
      expect(routes.pops, 0);
      expect(tabRequest.value, isNull);
      expect(navigator.hasPending, isFalse);
    });

    testWidgets('a malformed URL is treated the same way', (tester) async {
      await tester.pumpWidget(
        app((context, ref) => openInBrowser(context, ref, 'not a url')),
      );
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(find.text(kNoSourcePageMessage), findsOneWidget);
      expect(find.text('COLLECTION'), findsOneWidget);
      expect(tabRequest.value, isNull);
      expect(navigator.hasPending, isFalse);
    });
  });

  group('taking the Browser from a running operation', () {
    Widget open() => app((context, ref) => openInBrowser(context, ref, url));

    testWidgets('a running save is asked about before anything moves', (
      tester,
    ) async {
      v2.runner.debugSetRunning(true);
      await tester.pumpWidget(open());
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(find.text('A save is using the Browser'), findsOneWidget);
      expect(find.text('Saving an entry'), findsOneWidget);
      // Nothing has moved yet: the user has not answered.
      expect(find.text('COLLECTION'), findsOneWidget);
      expect(tabRequest.value, isNull);
      expect(navigator.hasPending, isFalse);

      await tester.tap(find.byKey(const ValueKey('takeOverBrowserPause')));
      await tester.pumpAndSettle();

      expect(tabRequest.value, 1);
      expect(navigator.pending?.url, url);
      expect(find.text('SHELL'), findsOneWidget);
      expect(
        v2.runner.isRunning,
        isTrue,
        reason: 'the run is held by the engine, never stopped from here',
      );
    });

    testWidgets('a running check is asked about too', (tester) async {
      v2.check.debugSetRunning(true);
      await tester.pumpWidget(open());
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(find.text('A save is using the Browser'), findsOneWidget);
      expect(find.text('Checking for new entries'), findsOneWidget);
      expect(tabRequest.value, isNull);

      await tester.tap(find.byKey(const ValueKey('takeOverBrowserPause')));
      await tester.pumpAndSettle();

      expect(tabRequest.value, 1);
      expect(navigator.pending?.url, url);
      expect(v2.check.isRunning, isTrue);
    });

    testWidgets('staying with the save leaves the tab, the pending URL and '
        'the run alone', (tester) async {
      v2.runner.debugSetRunning(true);
      await tester.pumpWidget(open());
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');
      await tester.tap(find.byKey(const ValueKey('takeOverBrowserStay')));
      await tester.pumpAndSettle();

      expect(tabRequest.value, isNull, reason: 'no section switch');
      expect(navigator.hasPending, isFalse, reason: 'no URL was stored');
      expect(v2.runner.isRunning, isTrue, reason: 'the run keeps the page');
      expect(find.text('COLLECTION'), findsOneWidget);
      expect(routes.pops, 1, reason: 'only the dialog was dismissed');
    });

    testWidgets('with nothing running the modal never appears and the page '
        'just opens', (tester) async {
      expect(v2.runner.isRunning, isFalse);
      expect(v2.check.isRunning, isFalse);
      await tester.pumpWidget(open());
      await standOn(tester, 'COLLECTION');

      await act(tester, 'COLLECTION');

      expect(find.text('A save is using the Browser'), findsNothing);
      expect(tabRequest.value, 1);
      expect(navigator.pending?.url, url);
      expect(find.text('SHELL'), findsOneWidget);
    });
  });
}
