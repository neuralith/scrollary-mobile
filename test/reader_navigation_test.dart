import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/reading_v2/offline_read.dart';

import 'helpers/reader_harness.dart';

/// Swiping right in the reader goes back to the collection's entry list.
///
/// The two things that make this correct rather than merely present: the
/// gesture must not fire on ordinary reading (which is vertical), and the
/// reading position must be written before the screen goes away.
///
/// Where the swipe lands is the route's business, not the reader's: the
/// collection is handed to the screen as an argument, exactly as
/// `V2ReaderRoute` hands it over. So the destination here is a stand-in — the
/// subject is that the reader leaves for it, and flushes on the way.
void main() {
  late ReaderHarness h;
  late String collectionId;
  late String entryId;
  late OfflineReaderData offline;

  setUp(() => h = ReaderHarness());
  tearDown(() => h.close());

  /// Three real panels, committed and recorded as this device's copy, then
  /// resolved into exactly what the route hands the screen.
  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    collectionId = await h.collectionId();
    entryId = await h.seedEntry(title: 'Foo Entry 1', ordinal: 201);
    await h.seedImages(entryId: entryId, pages: 3);
    offline = await h.open(entryId);
  });

  /// The two real routes involved, so the test exercises the actual
  /// pop-or-replace decision rather than a stand-in.
  Widget app({required String start}) {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/collection/:collectionId',
          builder: (context, state) =>
              _EntryList(collectionId: state.pathParameters['collectionId']!),
          routes: const [],
        ),
        GoRoute(
          path: '/reader/:entryId',
          builder: (context, state) => ReaderScreen(
            entryId: state.pathParameters['entryId']!,
            offline: offline,
            collectionId: collectionId,
          ),
        ),
      ],
    );
    return ProviderScope(child: MaterialApp.router(routerConfig: router));
  }

  /// Real file IO needs the event loop to turn (`runAsync`), and route
  /// transitions need the test clock to advance (`pump(duration)`). Both.
  Future<void> settleAsync(WidgetTester tester, {int rounds = 30}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Unmount inside the body, then let the disposal timers drift's stream
  /// teardown schedules actually run — the fake clock only turns while the
  /// test body is still going.
  void navTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  Future<void> openReader(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ListView).evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  navTest('a right swipe leaves for the entry list', (tester) async {
    await seed(tester);
    await openReader(tester, app(start: '/reader/$entryId'));

    await tester.drag(find.byType(ListView), const Offset(220, 0));
    await settleAsync(tester);

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byType(_EntryList), findsOneWidget);
  });

  navTest('the position is written before the reader goes away', (
    tester,
  ) async {
    await seed(tester);
    await openReader(tester, app(start: '/reader/$entryId'));

    // Read a little — well inside the 2s save debounce, so nothing has been
    // persisted yet when the swipe happens.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));
    expect((await h.repos.offline.activeCopyOf(entryId))!.anchorOffset, isNull);

    await tester.drag(find.byType(ListView), const Offset(220, 0));
    await settleAsync(tester);

    final copy = (await h.repos.offline.activeCopyOf(entryId))!;
    expect(copy.anchorOffset, isNotNull);
    expect(copy.anchorOffset, greaterThan(0));
  });

  navTest('scrolling to read never triggers it', (tester) async {
    await seed(tester);
    await openReader(tester, app(start: '/reader/$entryId'));

    // A long read scroll with the sideways wobble of a real thumb.
    await tester.drag(find.byType(ListView), const Offset(40, -600));
    await settleAsync(tester, rounds: 20);

    expect(
      find.byType(ReaderScreen),
      findsOneWidget,
      reason: 'a vertical drag belongs to the scroll view, not to navigation',
    );

    // Neither does a leftward one.
    await tester.drag(find.byType(ListView), const Offset(-220, 0));
    await settleAsync(tester, rounds: 20);
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  navTest('opened from the entry list, it pops back onto the same one', (
    tester,
  ) async {
    await seed(tester);
    final widget = app(start: '/collection/$collectionId');
    await tester.pumpWidget(widget);
    await settleAsync(tester, rounds: 40);

    final router = GoRouter.of(tester.element(find.byType(_EntryList)));
    router.push('/reader/$entryId');
    final readerList = find.descendant(
      of: find.byType(ReaderScreen),
      matching: find.byType(ListView),
    );
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (readerList.evaluate().isNotEmpty) break;
    }
    expect(readerList, findsOneWidget, reason: 'the reader opened');

    await tester.drag(readerList.first, const Offset(220, 0));
    await settleAsync(tester);

    expect(find.byType(_EntryList), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    // Popped rather than stacked: there is no second entry list underneath.
    expect(
      router.routerDelegate.currentConfiguration.matches,
      hasLength(1),
      reason: 'in-and-out must not pile up routes',
    );
  });
}

/// Stands in for the collection's entry list: these tests assert the reader
/// RETURNS somewhere, not what that somewhere renders.
class _EntryList extends StatelessWidget {
  const _EntryList({required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('entry list $collectionId')));
}
