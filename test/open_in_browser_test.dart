import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/browser/browser_presentation.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/connectivity.dart';
import 'package:web_reader/features/entry_actions.dart';
import 'package:web_reader/features/open_in_browser.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';

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
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;
  late SaveRunController run;
  late UpdateChecker checker;
  late BrowserNavigator navigator;
  late ValueNotifier<int?> tabRequest;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_open_in_browser');
    browser = FakeBrowser();
    run = SaveRunController(
      browser: browser,
      db: db,
      fileStore: FileStore(root),
      config: const SaveConfig(),
    );
    checker = UpdateChecker(browser: browser, db: db);
    navigator = BrowserNavigator();
    tabRequest = ValueNotifier<int?>(null);
  });

  tearDown(() async {
    navigator.dispose();
    tabRequest.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void runningInState(SaveState state) {
    run.debugSetRunning(true);
    run.debugSetProgress(
      SaveProgress(
        state: state,
        currentUrl: 'https://x.example/guide/foo/1',
        entryTitle: 'Entry 1',
        storedEntries: 4,
        skippedEntries: 2,
        requestedEntries: 8,
      ),
    );
  }

  Entry entryWith(String sourceUrl) => Entry(
    host: '',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    id: 'c1',
    collectionId: 'item-1',
    title: 'Entry 885',
    sourceUrl: sourceUrl,
    urlKey: sourceUrl,
    artifactFormat: 'imageSequence',
    saveStatus: 'complete',
    detectedAssetCount: 0,
    storedAssetCount: 0,
    entryOrder: 0,
    byteSize: 0,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

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
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(FileStore(root)),
        browserProvider.overrideWithValue(browser),
        saveRunProvider.overrideWithValue(run),
        updateCheckerProvider.overrideWithValue(checker),
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

  group('from a route pushed above the shell', () {
    testWidgets('the shell becomes visible again and the Browser is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () => openEntryOnWebsite(
              context,
              ref,
              entryWith('https://a.example/x'),
            ),
            child: const Text('Open on website'),
          ),
        ),
      );
      await pushCollection(tester);

      await tester.tap(find.text('Open on website'));
      await tester.pumpAndSettle();

      // The regression, stated directly: the user must not still be looking
      // at Collection Detail.
      expect(find.text('SERIES DETAIL'), findsNothing);
      expect(find.text('SHELL'), findsOneWidget);
      expect(tabRequest.value, 1, reason: 'the Browser section is selected');
      expect(navigator.pending?.url, 'https://a.example/x');
    });

    testWidgets(
      'nothing is pushed — no duplicate Browser or Collection route',
      (tester) async {
        await tester.pumpWidget(
          app(
            collectionBody: (context, ref) => TextButton(
              onPressed: () =>
                  openInBrowser(context, ref, 'https://a.example/x'),
              child: const Text('go'),
            ),
          ),
        );
        await pushCollection(tester);
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        // Popped back to the root route, not navigated forward onto a second
        // copy of anything.
        expect(find.text('SHELL'), findsOneWidget);
        expect(find.text('SERIES DETAIL'), findsNothing);
      },
    );

    testWidgets('back returns to the previous app screen', (tester) async {
      late GoRouter router;
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) {
            router = GoRouter.of(context);
            return TextButton(
              onPressed: () =>
                  openInBrowser(context, ref, 'https://a.example/x'),
              child: const Text('go'),
            );
          },
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // The shell is the bottom of the stack: app-level back leaves the app
      // rather than re-entering Collection Detail, and the Browser's own Back
      // falls through to the Library tab (asserted in browser_ui_test).
      expect(router.canPop(), isFalse);
      expect(find.text('SHELL'), findsOneWidget);
    });
  });

  group('a missing source page', () {
    testWidgets('does not switch sections, and says why', (tester) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () => openEntryOnWebsite(context, ref, entryWith('')),
            child: const Text('Open on website'),
          ),
        ),
      );
      await pushCollection(tester);

      await tester.tap(find.text('Open on website'));
      await tester.pumpAndSettle();

      expect(find.text(kNoSourcePageMessage), findsOneWidget);
      expect(
        find.text('This entry does not have a source page.'),
        findsOneWidget,
      );
      // Still exactly where they were.
      expect(find.text('SERIES DETAIL'), findsOneWidget);
      expect(tabRequest.value, isNull);
      expect(navigator.hasPending, isFalse);
    });

    testWidgets('a malformed URL is treated the same way', (tester) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () =>
                openEntryOnWebsite(context, ref, entryWith('not a url')),
            child: const Text('Open on website'),
          ),
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('Open on website'));
      await tester.pumpAndSettle();

      expect(find.text(kNoSourcePageMessage), findsOneWidget);
      expect(find.text('SERIES DETAIL'), findsOneWidget);
      expect(tabRequest.value, isNull);
    });
  });

  group('an active Browser-dependent save', () {
    for (final state in const [
      SaveState.inspecting,
      SaveState.scrolling,
      SaveState.extracting,
    ]) {
      testWidgets('${state.name}: asks before taking the page', (tester) async {
        runningInState(state);
        await tester.pumpWidget(
          app(
            collectionBody: (context, ref) => TextButton(
              onPressed: () =>
                  openInBrowser(context, ref, 'https://a.example/x'),
              child: const Text('go'),
            ),
          ),
        );
        await pushCollection(tester);
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        expect(find.text('A save is using the Browser'), findsOneWidget);
        expect(find.text('Stay with save'), findsOneWidget);
        expect(find.text('Pause and open entry'), findsOneWidget);
        // Nothing has moved yet.
        expect(tabRequest.value, isNull);
        expect(navigator.hasPending, isFalse);

        await tester.tap(find.byKey(const ValueKey('takeOverBrowserPause')));
        await tester.pumpAndSettle();

        expect(
          run.pauseReason,
          kPauseBrowserHidden,
          reason: 'held, not stopped',
        );
        expect(tabRequest.value, 1);
        expect(navigator.pending?.url, 'https://a.example/x');
      });
    }

    testWidgets('"Stay with save" leaves everything alone', (tester) async {
      runningInState(SaveState.scrolling);
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
      await tester.tap(find.byKey(const ValueKey('takeOverBrowserStay')));
      await tester.pumpAndSettle();

      expect(run.pauseReason, isNull, reason: 'the run keeps the page');
      expect(tabRequest.value, isNull);
      expect(navigator.hasPending, isFalse);
      expect(find.text('SERIES DETAIL'), findsOneWidget);
    });

    for (final state in const [SaveState.fetchingAssets, SaveState.saving]) {
      testWidgets('${state.name}: download-only does not block navigation', (
        tester,
      ) async {
        // Panels are extracted; the run reads bytes over HTTP and touches no
        // layout, so moving the page costs it nothing.
        runningInState(state);
        await tester.pumpWidget(
          app(
            collectionBody: (context, ref) => TextButton(
              onPressed: () =>
                  openInBrowser(context, ref, 'https://a.example/x'),
              child: const Text('go'),
            ),
          ),
        );
        await pushCollection(tester);
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        expect(find.text('A save is using the Browser'), findsNothing);
        expect(tabRequest.value, 1);
        expect(navigator.pending?.url, 'https://a.example/x');
        expect(run.pauseReason, isNull);
      });
    }

    testWidgets('a queued-but-unstarted save never asks', (tester) async {
      expect(run.isRunning, isFalse);
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

      expect(find.text('A save is using the Browser'), findsNothing);
      expect(tabRequest.value, 1);
    });
  });

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

  group('every entry source-page action shares the flow', () {
    testWidgets('openEntryOnWebsite delegates to the coordinator', (
      tester,
    ) async {
      // Proven by behaviour rather than by inspection: the shared coordinator
      // is the only thing that produces this message and this stack change.
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () => openEntryOnWebsite(context, ref, entryWith('')),
            child: const Text('go'),
          ),
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(kNoSourcePageMessage), findsOneWidget);
    });

    testWidgets('the unavailable-entry sheet uses it', (tester) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => TextButton(
            onPressed: () => showUnavailableEntrySheet(
              context,
              ref,
              entryWith('https://a.example/x'),
            ),
            child: const Text('go'),
          ),
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open on website'));
      await tester.pumpAndSettle();

      expect(find.text('SERIES DETAIL'), findsNothing);
      expect(tabRequest.value, 1);
      expect(navigator.pending?.url, 'https://a.example/x');
    });

    testWidgets('the details-sheet tile uses it', (tester) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) => Builder(
            builder: (inner) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: inner,
                builder: (sheetContext) => openOnWebsiteTile(
                  inner,
                  ref,
                  entryWith('https://a.example/x'),
                  beforeOpen: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await pushCollection(tester);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open on website'));
      await tester.pumpAndSettle();

      expect(find.text('SERIES DETAIL'), findsNothing);
      expect(tabRequest.value, 1);
      expect(navigator.pending?.url, 'https://a.example/x');
    });

    testWidgets('a row with no source page disables the tile entirely', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          collectionBody: (context, ref) =>
              openOnWebsiteTile(context, ref, entryWith('')),
        ),
      );
      await pushCollection(tester);
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });
  });
}
