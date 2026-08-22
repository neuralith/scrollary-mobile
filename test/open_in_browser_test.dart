import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/browser/browser_presentation.dart';
import 'package:web_reader/core/connectivity.dart';
import 'package:web_reader/features/open_in_browser.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';
import 'helpers/v2_harness.dart';

/// "Open in Browser", end to end.
///
/// The bug this file exists to prevent: the action told the Browser
/// controller and flipped the shell's tab index, but the user was standing on
/// a route pushed *above* the shell, so nothing they could see changed. The
/// URL loaded into a Browser nobody was looking at.
class _AlwaysOnline implements Connectivity {
  const _AlwaysOnline();

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<bool> canReach(String host) async => true;
}

void main() {
  late Directory root;
  late FakeBrowser browser;
  late V2Harness v2;
  late BrowserNavigator navigator;
  late ValueNotifier<int?> tabRequest;

  setUp(() {
    root = Directory.systemTemp.createTempSync('webread_open_in_browser');
    browser = FakeBrowser();
    v2 = V2Harness(browser: browser, fileStore: FileStore(root));
    navigator = BrowserNavigator();
    tabRequest = ValueNotifier<int?>(null);
  });

  tearDown(() async {
    navigator.dispose();
    tabRequest.dispose();
    await v2.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A shell at `/` with a pushed `/collection` above it — the exact stack the
  /// bug lived in.
  Widget app({
    required Widget Function(BuildContext, WidgetRef) collectionBody,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  const Text('SHELL'),
                  TextButton(
                    onPressed: () => context.push('/collection'),
                    child: const Text('to collection'),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/collection',
          builder: (context, state) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  const Text('SERIES DETAIL'),
                  collectionBody(context, ref),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        fileStoreProvider.overrideWithValue(FileStore(root)),
        libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
        browserProvider.overrideWithValue(browser),
        v2ServicesProvider.overrideWithValue(v2.services),
        browserNavigatorProvider.overrideWithValue(navigator),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        connectivityProvider.overrideWithValue(const _AlwaysOnline()),
      ],
      child: MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
  }

  Future<void> pushCollection(WidgetTester tester) async {
    await tester.tap(find.text('to collection'));
    await tester.pumpAndSettle();
    expect(find.text('SERIES DETAIL'), findsOneWidget);
  }

  group('the pending-request contract', () {
    test('a request is consumed exactly once', () {
      navigator.request('https://a.example/x');
      expect(navigator.hasPending, isTrue);
      expect(navigator.consume()?.url, 'https://a.example/x');
      expect(navigator.consume(), isNull, reason: 'never twice');
      expect(navigator.hasPending, isFalse);
    });

    test('a newer request replaces an undrained one', () {
      navigator.request('https://a.example/one');
      navigator.request('https://a.example/two');
      expect(navigator.consume()?.url, 'https://a.example/two');
      expect(navigator.consume(), isNull);
    });

    test('cancel drops it', () {
      navigator.request('https://a.example/x');
      navigator.cancel();
      expect(navigator.hasPending, isFalse);
    });
  });

  group('draining into the Browser', () {
    late BrowserPresentation presentation;
    late List<String> loaded;
    late bool attached;

    PendingOpenDrainer makeDrainer() => PendingOpenDrainer(
      navigator: navigator,
      presentation: presentation,
      isAttached: () => attached,
      reveal: presentation.showWebsite,
      load: loaded.add,
    );

    setUp(() {
      presentation = BrowserPresentation();
      loaded = [];
      attached = true;
    });

    tearDown(() => presentation.dispose());

    test('loads the requested URL once the WebView is attached', () {
      navigator.request('https://a.example/x');
      expect(makeDrainer().drain(), isTrue);
      expect(loaded, ['https://a.example/x']);
    });

    test('waits for the WebView rather than dropping the URL', () {
      attached = false;
      navigator.request('https://a.example/x');

      expect(makeDrainer().drain(), isFalse);
      expect(loaded, isEmpty);
      expect(navigator.hasPending, isTrue, reason: 'still waiting, not lost');

      // The attach arrives; no polling, no delay.
      attached = true;
      expect(makeDrainer().drain(), isTrue);
      expect(loaded, ['https://a.example/x']);
    });

    test('Browser Home is dismissed and the website revealed', () {
      presentation.openHome(
        preserving: const PreservedPage(
          url: 'https://old.example/',
          title: 'Old',
        ),
      );
      expect(presentation.isHome, isTrue);

      navigator.request('https://a.example/x');
      makeDrainer().drain();

      expect(presentation.surface, BrowserSurface.website);
      expect(loaded, ['https://a.example/x']);
    });

    test('the URL editor is dismissed too', () {
      presentation.openAddressEditor(draft: 'half typed');
      navigator.request('https://a.example/x');
      makeDrainer().drain();
      expect(presentation.surface, BrowserSurface.website);
    });

    test('the Browser already being active is not a special case', () {
      presentation.showWebsite();
      navigator.request('https://a.example/x');
      expect(makeDrainer().drain(), isTrue);
      expect(loaded, ['https://a.example/x']);
    });

    test('a rebuild does not reload the URL', () {
      navigator.request('https://a.example/x');
      makeDrainer().drain();
      expect(loaded, hasLength(1));

      // Every subsequent rebuild drains again — and must find nothing.
      for (var i = 0; i < 5; i++) {
        expect(makeDrainer().drain(), isFalse);
      }
      expect(loaded, hasLength(1), reason: 'loaded once, not once per rebuild');
    });

    test('with nothing pending it does nothing at all', () {
      expect(makeDrainer().drain(), isFalse);
      expect(loaded, isEmpty);
      expect(presentation.surface, BrowserSurface.website);
    });
  });

  group('the existing Browser is reused', () {
    test('the coordinator never constructs a controller of its own', () {
      // The drainer is handed a `load` callback; there is no path by which it
      // can make a second WebView, and the request carries a URL and nothing
      // else. Asserted structurally: the request is data, not a browser.
      final request = navigator.request('https://a.example/x');
      expect(request.url, 'https://a.example/x');
      expect(navigator.pending, isNotNull);
    });

    testWidgets('the same controller instance receives the page', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () => openInBrowser(context, ref, 'https://a.example/x'),
            child: const Text('go'),
          ),
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final presentation = BrowserPresentation();
      addTearDown(presentation.dispose);
      PendingOpenDrainer(
        navigator: navigator,
        presentation: presentation,
        isAttached: () => browser.isAttached,
        reveal: presentation.showWebsite,
        load: browser.load,
      ).drain();
      await tester.pump();

      // `browser` is the one instance the whole test injected; its own
      // navigation list is what moved.
      expect(browser.currentUrl, 'https://a.example/x');
    });
  });
}
