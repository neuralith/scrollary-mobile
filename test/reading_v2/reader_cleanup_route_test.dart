/// The whole thing, from a tap on *Next entry* in the real reader.
///
/// `forward_transition_test.dart` proves the decisions. This proves they are
/// **reachable**: the route resolves the neighbours, the reader's control calls
/// back with the live position, the questions are real dialogs, and the arrival
/// of the destination's own route is what makes the last Entry's bytes go.
///
/// That is the half the capability parity contract exists for — half the
/// regressions its audit found were working, tested code with nothing routed to
/// it, and a test that mounts a widget directly passes throughout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/features/v2_reader_route.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/providers.dart' show cleanupProvider;
import 'package:web_reader/reading_v2/finished_cleanup.dart';

import '../helpers/reader_harness.dart';

void main() {
  late ReaderHarness h;
  late LibraryUiServices services;
  late String collectionId;
  late List<String> ids;
  late Map<String, String> packagePath;
  late GoRouter router;

  /// The rule store the app itself resolves — same table, same keys.
  FinishedCleanupPreferenceStore preferences() =>
      FinishedCleanupPreferenceStore(LocalSettingsStore(h.db));

  setUp(() {
    h = ReaderHarness();
    packagePath = {};
  });
  tearDown(() => h.close());

  /// Two downloaded Entries in one Collection, and the services the route
  /// reads. Built inside the test body — a `ReadingStateRepository` created in
  /// `setUp` schedules its first continuation on the real microtask queue,
  /// which a `testWidgets` zone never turns.
  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    services = LibraryUiServices(h.db, fileStore: h.fileStore);
    collectionId = await h.collectionId();
    ids = [];
    for (var i = 1; i <= 2; i++) {
      final id = await h.seedEntry(title: 'Part $i', ordinal: i.toDouble());
      packagePath[id] = await h.seedImages(
        entryId: id,
        pages: 2,
        title: 'Part $i',
      );
      ids.add(id);
    }
  });

  Widget app(String startEntryId) {
    router = GoRouter(
      initialLocation: '/reader/$startEntryId',
      routes: [
        GoRoute(
          path: '/reader/:entryId',
          builder: (context, state) =>
              V2ReaderRoute(entryId: state.pathParameters['entryId']!),
        ),
      ],
    );
    return ProviderScope(
      overrides: [libraryUiServicesProvider.overrideWithValue(services)],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Real file IO needs the event loop to turn (`runAsync`); routes and dialogs
  /// need the test clock to advance (`pump`). Both, repeatedly.
  Future<void> settle(WidgetTester tester, {int rounds = 24}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  bool downloaded(String entryId) =>
      h.fileStore.entryExists(packagePath[entryId]!);

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Unmount before the test ends, so the reader's own teardown timers run
  /// while the fake clock is still turning.
  void routeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, rounds: 4);
    });
  }

  routeTest('reading on from a finished entry asks the collection, once, '
      'and frees it when it arrives', (tester) async {
    await seed(tester);
    await tester.runAsync(() => h.repos.reading.markRead(ids[0]));

    await tester.pumpWidget(app(ids[0]));
    await settle(tester);
    expect(find.byKey(const ValueKey('readerNextEntry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('readerNextEntry')));
    await settle(tester);

    // The Collection has never been asked, so it is — with the destructive
    // answer preselected but not yet taken.
    expect(find.byKey(const ValueKey('finishedCleanupDialog')), findsOneWidget);
    expect(downloaded(ids[0]), isTrue, reason: 'nothing has been decided yet');

    await tester.tap(find.byKey(const ValueKey('saveFinishedCleanup')));
    await settle(tester);

    expect(location(), '/reader/${ids[1]}');
    expect(downloaded(ids[0]), isFalse);
    expect(downloaded(ids[1]), isTrue);
    expect(
      await tester.runAsync(() => preferences().of(collectionId)),
      FinishedCleanupRule.remove,
      reason: 'the answer is stored, and this collection is not asked again',
    );
  });

  routeTest('a collection told to keep is never asked and frees '
      'nothing', (tester) async {
    await seed(tester);
    await tester.runAsync(() async {
      await h.repos.reading.markRead(ids[0]);
      await preferences().remember(collectionId, FinishedCleanupRule.keep);
    });

    await tester.pumpWidget(app(ids[0]));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('readerNextEntry')));
    await settle(tester);

    expect(find.byKey(const ValueKey('finishedCleanupDialog')), findsNothing);
    expect(location(), '/reader/${ids[1]}');
    expect(downloaded(ids[0]), isTrue);
  });

  routeTest('moving back to the previous entry frees nothing', (tester) async {
    await seed(tester);
    await tester.runAsync(() async {
      await h.repos.reading.markRead(ids[0]);
      await h.repos.reading.markRead(ids[1]);
      await preferences().remember(collectionId, FinishedCleanupRule.remove);
    });

    await tester.pumpWidget(app(ids[1]));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('readerPreviousEntry')));
    await settle(tester);

    expect(location(), '/reader/${ids[0]}');
    expect(downloaded(ids[1]), isTrue, reason: 'that was a move backward');
    expect(downloaded(ids[0]), isTrue);
  });

  routeTest('the entry open in the reader is not a sweep\'s to free', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(() async {
      await h.repos.reading.markRead(ids[0]);
      await h.repos.reading.markRead(ids[1]);
    });

    await tester.pumpWidget(app(ids[0]));
    await settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(V2ReaderRoute)),
    );
    final cleanup = container.read(cleanupProvider);
    expect(cleanup.openInReader.value, ids[0]);

    // *Remove finished offline entries* over everything finished — which is
    // both of them, including the one on screen.
    final freed = await tester.runAsync(
      () => cleanup.removeCopiesOf([ids[0], ids[1]]),
    );

    expect(freed, 1);
    expect(downloaded(ids[0]), isTrue, reason: 'it is being read right now');
    expect(downloaded(ids[1]), isFalse);
  });

  routeTest('the lock follows the reader, and lets go on the way out', (
    tester,
  ) async {
    await seed(tester);
    await tester.runAsync(() => h.repos.reading.markRead(ids[0]));
    await tester.runAsync(
      () => preferences().remember(collectionId, FinishedCleanupRule.keep),
    );

    await tester.pumpWidget(app(ids[0]));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(V2ReaderRoute)),
    );
    final cleanup = container.read(cleanupProvider);
    expect(cleanup.openInReader.value, ids[0]);

    // A replaced route builds the arriving reader before the departing one is
    // disposed: an unconditional release would drop the new lock here.
    await tester.tap(find.byKey(const ValueKey('readerNextEntry')));
    await settle(tester);
    expect(cleanup.openInReader.value, ids[1]);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, rounds: 4);
    expect(cleanup.openInReader.value, isNull);
  });
}
