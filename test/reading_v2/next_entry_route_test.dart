/// Reading on, from the real reader, in all three states the library can be
/// in — and by both ways of asking.
///
/// `next_entry_test.dart` proves the three answers are decided correctly and
/// `pull_up_next_test.dart` proves the gesture only fires when it is asked to.
/// This proves the two halves are **joined**: that the control and the gesture
/// reach the same operation, that the operation reaches the right question, and
/// that a question the user backs out of leaves them exactly where they were.
///
/// That is the half the capability parity contract exists for — working, tested
/// code with nothing routed to it passes its own suite all day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/features/v2_reader_route.dart';
import 'package:web_reader/library_ui/providers.dart';

import '../helpers/reader_harness.dart';

void main() {
  late ReaderHarness h;
  late LibraryUiServices services;
  late String collectionId;
  late GoRouter router;

  /// What the composition's two seams were asked to do.
  late List<String> opened;
  late List<(String, String)> checked;

  /// Run by the checker before it returns, so a test can say what the site had
  /// published by the time the check finished.
  Future<void> Function()? whatTheCheckFinds;

  setUp(() {
    h = ReaderHarness();
    opened = [];
    checked = [];
    whatTheCheckFinds = null;
  });
  tearDown(() => h.close());

  Future<void> seedServices(WidgetTester tester) => tester.runAsync(() async {
    services = LibraryUiServices(h.db, fileStore: h.fileStore);
    collectionId = await h.collectionId();
  });

  /// A placed Entry, optionally downloaded and optionally with an address.
  Future<String> entry(
    WidgetTester tester, {
    required double ordinal,
    required String title,
    bool downloaded = false,
    String? url,
  }) => tester
      .runAsync(() async {
        final id = await h.seedEntry(title: title, ordinal: ordinal);
        if (downloaded) await h.seedImages(entryId: id, pages: 2, title: title);
        if (url != null) await h.seedLocation(entryId: id, url: url);
        return id;
      })
      .then((id) => id!);

  Widget app(String startEntryId, {bool wireChecker = true}) {
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
      overrides: [
        libraryUiServicesProvider.overrideWithValue(services),
        sourceOpenerProvider.overrideWithValue((url) async => opened.add(url)),
        if (wireChecker)
          collectionCheckerProvider.overrideWithValue((id, name) async {
            checked.add((id, name));
            await whatTheCheckFinds?.call();
          }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Real file IO needs the event loop to turn (`runAsync`); routes and sheets
  /// need the test clock to advance (`pump`). Both, repeatedly.
  Future<void> settle(WidgetTester tester, {int rounds = 24}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Put the reader at the very end of the entry.
  ///
  /// Repeatedly, because a lazily built list corrects its own scroll offset as
  /// it discovers what its children actually measure, and one jump at an
  /// estimated extent lands short of — or past — the real bottom.
  Future<void> goToTheEnd(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('readerNextEntry')));
    await settle(tester);
  }

  /// The same request, asked the other way: drag the reader past the end of
  /// the entry and let go.
  Future<void> pullUp(WidgetTester tester) async {
    await goToTheEnd(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    await gesture.up();
    await settle(tester);
  }

  /// Unmount before the test ends, so the reader's own teardown timers run
  /// while the fake clock is still turning.
  void routeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, rounds: 4);
    });
  }

  // ── A. the next entry is on this device ──────────────────────────────────

  routeTest('the next entry this device holds simply opens', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    final second = await entry(
      tester,
      ordinal: 202,
      title: 'Part 202',
      downloaded: true,
    );

    await tester.pumpWidget(app(first));
    await settle(tester);
    await tapNext(tester);

    expect(location(), '/reader/$second');
    expect(opened, isEmpty, reason: 'nothing went to the Browser');
    expect(checked, isEmpty, reason: 'nothing was checked');
  });

  // ── B. the next entry is in the library, not on this device ──────────────

  routeTest('a next entry with no copy here offers its source, and opening '
      'it records the visit', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    final second = await entry(
      tester,
      ordinal: 202,
      title: 'Part 202',
      url: 'https://reading.example.com/serial-alpha/202',
    );

    await tester.pumpWidget(app(first));
    await settle(tester);
    await tapNext(tester);

    expect(
      find.byKey(const ValueKey('nextEntryAtSourceSheet')),
      findsOneWidget,
    );
    expect(find.text('Part 202'), findsOneWidget, reason: 'it names the entry');
    expect(location(), '/reader/$first', reason: 'nothing has moved yet');

    await tester.tap(find.byKey(const ValueKey('nextEntryOpenAtSource')));
    await settle(tester);

    expect(opened, ['https://reading.example.com/serial-alpha/202']);
    // The reader stays put: the page opens in the Browser, and this Entry is
    // still the one this device can read.
    expect(location(), '/reader/$first');
    // Opened at its source, never finished by it (I16).
    final state = await tester.runAsync(() => h.repos.reading.stateOf(second));
    expect(state!.status, ReadStatus.reading);
  });

  routeTest('staying here opens nothing and changes nothing', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    final second = await entry(
      tester,
      ordinal: 202,
      title: 'Part 202',
      url: 'https://reading.example.com/serial-alpha/202',
    );

    await tester.pumpWidget(app(first));
    await settle(tester);
    await tapNext(tester);
    await tester.tap(find.byKey(const ValueKey('nextEntryStayHere')));
    await settle(tester);

    expect(opened, isEmpty);
    expect(location(), '/reader/$first');
    final state = await tester.runAsync(() => h.repos.reading.stateOf(second));
    expect(state!.status, ReadStatus.unread);
  });

  // ── C. the library knows of no next entry ────────────────────────────────

  routeTest('the last entry in the library offers a check, never an '
      'ending', (tester) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );

    await tester.pumpWidget(app(last));
    await settle(tester);
    await tapNext(tester);

    expect(find.byKey(const ValueKey('nextEntryCheckSheet')), findsOneWidget);
    expect(
      find.text('No next entry is currently in your library'),
      findsOneWidget,
    );
    expect(find.textContaining('end of'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nextEntryCheckNow')));
    await settle(tester);

    expect(checked, [(collectionId, 'Serial Alpha')]);
    expect(location(), '/reader/$last', reason: 'a check moves nobody');
  });

  routeTest('backing out of the check runs nothing', (tester) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );

    await tester.pumpWidget(app(last));
    await settle(tester);
    await tapNext(tester);
    await tester.tap(find.byKey(const ValueKey('nextEntryCheckDismiss')));
    await settle(tester);

    expect(checked, isEmpty);
    expect(location(), '/reader/$last');
  });

  routeTest('a check that finds the next entry offers it at its source, '
      'and moves nobody on its own', (tester) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    // What the check writes: an Entry the library did not have, with an
    // address and — as a check downloads nothing — no copy on this device.
    whatTheCheckFinds = () async {
      final id = await h.seedEntry(title: 'Part 202', ordinal: 202);
      await h.seedLocation(
        entryId: id,
        url: 'https://reading.example.com/serial-alpha/202',
      );
    };

    await tester.pumpWidget(app(last));
    await settle(tester);
    await tapNext(tester);
    await tester.tap(find.byKey(const ValueKey('nextEntryCheckNow')));
    await settle(tester);

    expect(checked, hasLength(1));
    expect(
      find.byKey(const ValueKey('nextEntryAtSourceSheet')),
      findsOneWidget,
    );
    expect(location(), '/reader/$last');
  });

  routeTest('a check with nothing new asks nothing a second time', (
    tester,
  ) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );

    await tester.pumpWidget(app(last));
    await settle(tester);
    await tapNext(tester);
    await tester.tap(find.byKey(const ValueKey('nextEntryCheckNow')));
    await settle(tester);

    expect(checked, hasLength(1));
    expect(
      find.byKey(const ValueKey('nextEntryCheckSheet')),
      findsNothing,
      reason: 'the same question again would be a loop, not an answer',
    );
    expect(
      find.text('Nothing new — there is still no next entry in your library.'),
      findsOneWidget,
    );
  });

  routeTest('with no checker wired, the action is absent rather than '
      'inert', (tester) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );

    await tester.pumpWidget(app(last, wireChecker: false));
    await settle(tester);
    await tapNext(tester);

    expect(find.byKey(const ValueKey('nextEntryCheckSheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('nextEntryCheckNow')), findsNothing);
  });

  // ── one operation, two ways of asking ────────────────────────────────────

  routeTest('the pull-up goes through the same forward transition the '
      'control does', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    final second = await entry(
      tester,
      ordinal: 202,
      title: 'Part 202',
      downloaded: true,
    );

    await tester.pumpWidget(app(first));
    await settle(tester);
    await pullUp(tester);

    // The pull ends at the bottom of an Entry nobody marked finished, which is
    // exactly the case V2-D59 asks about — and it is asked here because the
    // pull-up shares `ForwardTransitionService` with the control rather than
    // navigating around it.
    expect(find.byKey(const ValueKey('entryCompletionDialog')), findsOneWidget);
    expect(location(), '/reader/$first', reason: 'nothing has moved yet');

    await tester.tap(
      find.byKey(const ValueKey('entryCompletion-continueWithout')),
    );
    await settle(tester);

    expect(location(), '/reader/$second');
    // Moved on and changed nothing: continuing is not a decision about
    // completion.
    final state = await tester.runAsync(() => h.repos.reading.stateOf(first));
    expect(state!.status, isNot(ReadStatus.completed));
  });

  routeTest('cancelling that question stays on the entry', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    await entry(tester, ordinal: 202, title: 'Part 202', downloaded: true);

    await tester.pumpWidget(app(first));
    await settle(tester);
    await pullUp(tester);
    await tester.tap(find.byKey(const ValueKey('entryCompletion-cancel')));
    await settle(tester);

    expect(location(), '/reader/$first');
  });

  routeTest('the pull-up asks the same question at the end of the '
      'library', (tester) async {
    await seedServices(tester);
    final last = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );

    await tester.pumpWidget(app(last));
    await settle(tester);
    await pullUp(tester);

    expect(find.byKey(const ValueKey('nextEntryCheckSheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nextEntryCheckNow')));
    await settle(tester);
    expect(checked, [(collectionId, 'Serial Alpha')]);
  });

  routeTest('the pull-up offers the source, exactly as the control '
      'does', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    await entry(
      tester,
      ordinal: 202,
      title: 'Part 202',
      url: 'https://reading.example.com/serial-alpha/202',
    );

    await tester.pumpWidget(app(first));
    await settle(tester);
    await pullUp(tester);

    expect(
      find.byKey(const ValueKey('nextEntryAtSourceSheet')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('nextEntryOpenAtSource')));
    await settle(tester);
    expect(opened, ['https://reading.example.com/serial-alpha/202']);
  });

  routeTest('reading an entry to its end asks for nothing', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    await entry(tester, ordinal: 202, title: 'Part 202', downloaded: true);

    await tester.pumpWidget(app(first));
    await settle(tester);

    // Read all the way to the bottom, and stop there.
    await goToTheEnd(tester);
    await settle(tester, rounds: 8);
    await tester.drag(find.byType(ListView), const Offset(0, -40));
    await settle(tester, rounds: 8);

    expect(location(), '/reader/$first', reason: 'reading is not navigating');
    expect(find.byKey(const ValueKey('nextEntryAtSourceSheet')), findsNothing);
  });

  // ── an entry with no reading order ───────────────────────────────────────

  routeTest('a standalone entry offers no way to read on', (tester) async {
    await seedServices(tester);
    final root = await tester.runAsync(() => h.repos.folders.ensureRoot());
    final loose = await tester.runAsync(() async {
      final (row, violation) = await h.repos.entries.createStandalone(
        folderId: root!.id,
        title: 'A page on its own',
      );
      expect(violation, isNull);
      await h.seedImages(entryId: row!.id, pages: 2, title: 'On its own');
      return row.id;
    });

    await tester.pumpWidget(app(loose!));
    await settle(tester);

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('readerNextEntry')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull, reason: 'there is no order to read on in');

    await pullUp(tester);
    expect(find.byKey(const ValueKey('nextEntryCheckSheet')), findsNothing);
    expect(find.byKey(const ValueKey('nextEntryAtSourceSheet')), findsNothing);
  });

  // ── the affordance is drawn, and only while the pull is on ───────────────

  routeTest('the pull reveals its label over the reader', (tester) async {
    await seedServices(tester);
    final first = await entry(
      tester,
      ordinal: 201,
      title: 'Part 201',
      downloaded: true,
    );
    await entry(tester, ordinal: 202, title: 'Part 202', downloaded: true);

    await tester.pumpWidget(app(first));
    await settle(tester);
    expect(find.byKey(const ValueKey('pullUpNextLabel')), findsNothing);

    await goToTheEnd(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(find.text('Pull up for next entry'), findsOneWidget);

    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    expect(find.text('Release for next entry'), findsOneWidget);

    // Back below the line: the affordance says so before the finger lifts.
    for (var i = 0; i < 16; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    expect(find.text('Release for next entry'), findsNothing);

    await gesture.up();
    await settle(tester);
    expect(location(), '/reader/$first', reason: 'cancelled, so nothing moved');
    expect(find.byKey(const ValueKey('pullUpNextLabel')), findsNothing);
  });
}
