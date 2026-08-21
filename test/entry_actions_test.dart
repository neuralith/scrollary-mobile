import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/browser_navigator.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/core/connectivity.dart';
import 'package:web_reader/features/entry_actions.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// Tapping an entry: the reader when it can be read, and the two things
/// worth offering when it cannot.
class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this.online);

  bool online;
  final hosts = <String>[];

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<bool> canReach(String host) async {
    hosts.add(host);
    return online;
  }
}

void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late BrowserController browser;
  late _FakeConnectivity connectivity;
  late BrowserNavigator browserNavigator;
  late ValueNotifier<int?> tabRequest;
  String? lastRoute;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_entry_actions');
    store = FileStore(root);
    browser = BrowserController();
    connectivity = _FakeConnectivity(true);
    browserNavigator = BrowserNavigator();
    tabRequest = ValueNotifier<int?>(null);
    lastRoute = null;
  });
  tearDown(() async {
    browserNavigator.dispose();
    tabRequest.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const url = 'https://x.example/guide/foo/12';

  Future<void> seedCollection() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 'collection-1',
      title: 'Foo',
      sourceUrl: 'https://x.example/guide/foo',
      host: 'x.example',
      collectionKey: '/guide/foo',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  Future<void> seedEntry({
    String id = 'c1',
    String sourceUrl = url,
    bool offline = true,
    String saveStatus = 'complete',
    DateTime? removedAt,
  }) async {
    if (offline) {
      Directory(
        '${root.path}/library/collection-1/entries/$id',
      ).createSync(recursive: true);
    }
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: id,
        collectionId: 'collection-1',
        title: 'Foo Entry 12',
        sourceUrl: sourceUrl,
        urlKey: '$sourceUrl#$id',
        artifactFormat: 'imageSequence',
        saveStatus: saveStatus,
        contentPath: offline ? 'library/collection-1/entries/$id' : null,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 1,
        storedAssetCount: offline ? 1 : 0,
        entryOrder: 12,
        byteSize: offline ? 64 : 0,
        entryNumber: 12,
        sourceMarker: 'Entry 12',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        offlineRemovedAt: removedAt,
      ),
    );
  }

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/collection/collection-1',
      routes: [
        GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              CollectionDetailScreen(collectionId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/reader/:entryId',
          builder: (context, state) {
            lastRoute = state.uri.toString();
            return const Scaffold(body: Text('READER'));
          },
        ),
        GoRoute(path: '/rules', builder: (_, _) => const SizedBox()),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        connectivityProvider.overrideWithValue(connectivity),
        // "Open on website" now goes through the shared coordinator, which
        // asks the save run whether anything owns the rendered Browser
        // before it moves the user (D60).
        saveRunProvider.overrideWithValue(
          SaveRunController(browser: browser, db: db, fileStore: store),
        ),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        browserNavigatorProvider.overrideWithValue(browserNavigator),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        cleanupProvider.overrideWithValue(
          CleanupService(db: db, fileStore: store),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Entry 12').evaluate().isNotEmpty) return;
    }
    fail('collection detail never listed the entry');
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('an offline entry still opens the reader', (tester) async {
    await seedCollection();
    await seedEntry();
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();

    expect(find.text('READER'), findsOneWidget);
    expect(lastRoute, '/reader/c1');
    await drain(tester);
  });

  testWidgets('an entry with no files offers website and save', (tester) async {
    await seedCollection();
    await seedEntry(offline: false, removedAt: DateTime(2026, 7, 26));
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();

    expect(
      find.text('READER'),
      findsNothing,
      reason: 'there is nothing to read; the reader must not be opened',
    );
    expect(find.text('Open on website'), findsOneWidget);
    expect(find.text('Add to save queue'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('you removed its files'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('Open on website sends the Browser to the entry URL', (
    tester,
  ) async {
    await seedCollection();
    await seedEntry(offline: false);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open on website'));
    await tester.pumpAndSettle();

    expect(connectivity.hosts, ['x.example']);
    // The page is handed to the shared coordinator's pending request, and the
    // Browser section is selected — the two halves the old flow only did one
    // of (D60). The Browser drains the request once it is mounted.
    expect(
      browserNavigator.pending?.url,
      url,
      reason: 'the stored entry URL, never a collection or fallback page',
    );
    expect(tabRequest.value, 1, reason: 'the Browser section is selected');
    await drain(tester);
  });

  testWidgets('an offline device says so instead of navigating', (
    tester,
  ) async {
    connectivity.online = false;
    await seedCollection();
    await seedEntry(offline: false);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open on website'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No network connection'), findsOneWidget);
    expect(browserNavigator.hasPending, isFalse);
    expect(tabRequest.value, isNull, reason: 'the user stays where they are');
    await drain(tester);
  });

  testWidgets('an entry with no known URL cannot be opened on the web', (
    tester,
  ) async {
    await seedCollection();
    await seedEntry(offline: false, sourceUrl: '');
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();

    expect(find.text('Open on website'), findsOneWidget);
    expect(
      find.text('The original page is unknown for this entry'),
      findsOneWidget,
    );
    // Disabled, not merely unhelpful: tapping must not navigate anywhere.
    await tester.tap(find.text('Open on website'));
    await tester.pumpAndSettle();
    expect(browserNavigator.hasPending, isFalse);
    expect(tabRequest.value, isNull);
    expect(connectivity.hosts, isEmpty);
    await drain(tester);
  });

  testWidgets('an available entry can still reach its source page', (
    tester,
  ) async {
    await seedCollection();
    await seedEntry();
    await open(tester);

    // Offered on long-press, so it never competes with reading.
    await tester.longPress(find.byKey(const ValueKey('entryRow-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Open entry'), findsOneWidget);

    await tester.tap(find.text('Open on website'));
    await tester.pumpAndSettle();
    expect(browserNavigator.pending?.url, url);
    expect(tabRequest.value, 1);
    await drain(tester);
  });
}
