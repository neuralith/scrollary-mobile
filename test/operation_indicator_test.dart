/// The compact background-activity indicator, over the V2 save queue.
///
/// One sentence under test: **it says that work is outstanding and how much,
/// and nothing else.** Every word of detail — progress, logs, failures, stop,
/// retry — is one tap away on the surface that already owns those controls, so
/// this one is a pill, it never claims more motion than is true, and it leaves
/// whenever the Browser or the Reader is already speaking for the same run.
///
/// The counting itself is a pure function over [SaveTask] rows, and it is
/// tested as one: what a failure marker weighs is *when* one row finished
/// against *when* another was asked for, and that is a property of the list,
/// not of a widget.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/operation_indicator.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/status_style.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/v2_harness.dart';

void main() {
  // ─── the counting itself ──────────────────────────────────────────────────
  //
  // A `failed` row is terminal history and it is kept, for up to the whole
  // history limit. The question the marker has to answer is not "has anything
  // ever failed" — something always has — but "did the work I am watching lose
  // one".

  group('BackgroundActivity', () {
    SaveTask row(
      SaveTaskState state, {
      DateTime? queuedAt,
      DateTime? finishedAt,
      String? id,
    }) => SaveTask(
      id: id ?? state.name,
      entryId: 'entry-${id ?? state.name}',
      locationUrl: 'https://example.com/one/${id ?? state.name}',
      state: state,
      origin: SaveTaskOrigin.queue,
      orderIndex: 0,
      queuedAt: queuedAt ?? DateTime(2026, 8, 1),
      finishedAt: finishedAt,
    );

    BackgroundActivity resolve(
      List<SaveTask> tasks, {
      bool runningWithoutTask = false,
      bool needsUser = false,
      bool paused = false,
    }) => BackgroundActivity.resolve(
      tasks: tasks,
      runningWithoutTask: runningWithoutTask,
      needsUser: needsUser,
      paused: paused,
    );

    test('an empty queue is nothing to report', () {
      final activity = resolve(const []);
      expect(activity.remaining, 0);
      expect(activity.isPresent, isFalse);
    });

    group('scoping failures to the wave', () {
      final wave = DateTime(2026, 8, 5, 12);

      test('a failure that happened alongside the outstanding work counts', () {
        expect(
          resolve([
            row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              SaveTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(seconds: 30)),
              id: 'b',
            ),
          ]).failed,
          1,
        );
      });

      test('one from before the outstanding work was asked for does not', () {
        expect(
          resolve([
            row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              SaveTaskState.failed,
              queuedAt: wave.subtract(const Duration(days: 3)),
              finishedAt: wave.subtract(const Duration(days: 3)),
              id: 'b',
            ),
          ]).failed,
          0,
        );
      });

      test('the oldest outstanding row is what the wave is measured from', () {
        // Queued at 12:00, another at 12:10, a failure at 12:05: still this
        // wave, because the wave began with the first of them.
        expect(
          resolve([
            row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              SaveTaskState.running,
              queuedAt: wave.add(const Duration(minutes: 10)),
              id: 'b',
            ),
            row(
              SaveTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 5)),
              id: 'c',
            ),
          ]).failed,
          1,
        );
      });

      test('a failure with no finish time is never claimed', () {
        expect(
          resolve([
            row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
            row(SaveTaskState.failed, queuedAt: wave, id: 'b'),
          ]).failed,
          0,
        );
      });

      test('with nothing outstanding there is no wave to belong to', () {
        expect(
          resolve([
            row(
              SaveTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 1)),
              id: 'b',
            ),
          ]).failed,
          0,
        );
      });

      test('completed and cancelled rows are not failures', () {
        expect(
          resolve([
            row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              SaveTaskState.completed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 1)),
              id: 'b',
            ),
            row(
              SaveTaskState.cancelled,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 2)),
              id: 'c',
            ),
          ]).failed,
          0,
        );
      });
    });

    test('queued and running are both outstanding', () {
      final activity = resolve([
        row(SaveTaskState.queued, id: 'a'),
        row(SaveTaskState.queued, id: 'b'),
        row(SaveTaskState.running, id: 'c'),
      ]);
      expect(activity.active, 1);
      expect(activity.waiting, 2);
      expect(activity.remaining, 3);
      expect(activity.inMotion, isTrue);
    });

    test('a run without a row still counts as one job', () {
      final activity = resolve(const [], runningWithoutTask: true);
      expect(activity.active, 1);
      expect(activity.isPresent, isTrue);
    });

    test('a run WITH a row is not counted twice', () {
      final activity = resolve([
        row(SaveTaskState.running),
      ], runningWithoutTask: true);
      expect(
        activity.active,
        1,
        reason: 'one job counted two ways is the larger of the two, not a sum',
      );
    });

    test('finished work is history, not activity', () {
      final activity = resolve([
        row(SaveTaskState.completed, id: 'a'),
        row(SaveTaskState.cancelled, id: 'b'),
        row(
          SaveTaskState.failed,
          id: 'c',
          finishedAt: DateTime(2026, 8, 1, 0, 1),
        ),
      ]);
      expect(activity.remaining, 0);
      expect(
        activity.failed,
        0,
        reason: 'with nothing in flight there is no run for it to be about',
      );
      expect(
        activity.isPresent,
        isFalse,
        reason: 'a failed row belongs to Activity, not to a permanent badge',
      );
    });

    test('nothing that is holding is allowed to look like motion', () {
      expect(
        resolve(const [], runningWithoutTask: true, needsUser: true).inMotion,
        isFalse,
      );
      expect(
        resolve(const [], runningWithoutTask: true, paused: true).inMotion,
        isFalse,
      );
    });

    test('a hold is worth showing even with an empty queue', () {
      expect(resolve(const [], paused: true).isPresent, isTrue);
      expect(resolve(const [], needsUser: true).isPresent, isTrue);
    });

    test('the description says what the counts are', () {
      final wave = DateTime(2026, 8, 5, 12);
      final activity = resolve([
        row(SaveTaskState.queued, queuedAt: wave, id: 'a'),
        row(SaveTaskState.running, queuedAt: wave, id: 'b'),
        row(
          SaveTaskState.failed,
          queuedAt: wave,
          finishedAt: wave.add(const Duration(minutes: 1)),
          id: 'c',
        ),
      ]);
      expect(activity.description, contains('1 running'));
      expect(activity.description, contains('1 waiting'));
      expect(activity.description, contains('1 failed'));
      expect(activity.description, contains('Opens Activity'));
    });

    test('a held operation says where it will take you instead', () {
      expect(
        resolve(
          const [],
          runningWithoutTask: true,
          needsUser: true,
        ).description,
        contains('Opens the Browser'),
      );
    });
  });

  // ─── the widget ───────────────────────────────────────────────────────────

  group('OperationIndicator', () {
    late Directory root;
    late FileStore store;
    late BrowserController browser;
    late V2Harness v2;
    late ValueNotifier<bool> browserOnScreen;
    late ValueNotifier<bool> surfacePainted;
    late ReaderChromeVisibility readerChrome;
    late int detailsOpened;
    late int browserOpened;

    setUp(() {
      root = Directory.systemTemp.createTempSync('scrollary_operation_pill');
      Directory(
        '${root.path}/${FileStore.libraryFolderName}',
      ).createSync(recursive: true);
      Directory(
        '${root.path}/${FileStore.tmpFolderName}',
      ).createSync(recursive: true);
      store = FileStore(root);
      browser = BrowserController();
      v2 = V2Harness(browser: browser, fileStore: store);
      browserOnScreen = ValueNotifier<bool>(false);
      surfacePainted = ValueNotifier<bool>(true);
      readerChrome = ReaderChromeVisibility();
      detailsOpened = 0;
      browserOpened = 0;
    });

    tearDown(() async {
      browserOnScreen.dispose();
      surfacePainted.dispose();
      readerChrome.dispose();
      await v2.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    testWidgets('a run held on the user is present, and its destination is '
        'the Browser', (tester) async {
      // The state the audit found hardcoded to false: v2CaptureWithAssist can
      // park a capture on a selection, and off the Browser such a run looked
      // identical to one that was working.
      final held = BackgroundActivity.resolve(
        tasks: const [],
        runningWithoutTask: true,
        needsUser: true,
        paused: false,
      );

      expect(held.isPresent, isTrue);
      expect(held.needsUser, isTrue);

      // And nothing about it consults an entitlement: knowing the device is
      // waiting on you is Free (docs/V2_CAPABILITY_PARITY.md).
      final source = File(
        'lib/features/operation_indicator.dart',
      ).readAsStringSync();
      expect(
        source.contains('capability/'),
        isFalse,
        reason: 'the operation indicator must never import an entitlement',
      );
    });

    Widget harness() => ProviderScope(
      overrides: [
        v2ServicesProvider.overrideWithValue(v2.services),
        browserOnScreenProvider.overrideWithValue(browserOnScreen),
        browserSurfacePaintedProvider.overrideWithValue(surfacePainted),
        readerChromeVisibleProvider.overrideWithValue(readerChrome),
      ],
      // The app's own placement: above everything the router draws, in a
      // Stack, which is what makes "it leaves with the Reader's bars"
      // something to prove rather than assume.
      child: MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Stack(
          fit: StackFit.expand,
          children: [
            const Scaffold(body: Center(child: Text('some screen'))),
            OperationIndicator(
              onOpenDetails: () => detailsOpened++,
              onOpenBrowser: () => browserOpened++,
            ),
          ],
        ),
      ),
    );

    final pill = find.byKey(const ValueKey('operationIndicator'));

    /// Let the drift stream deliver and the widgets rebuild, on the fake
    /// clock. `pumpAndSettle` is unusable here: the spinner animates forever.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness());
      await settle(tester);
    }

    /// Unmount inside the body, then let drift's stream teardown timers run —
    /// the fake clock only turns while the test body is still going.
    void indicatorTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      });
    }

    /// An Entry for a queue row to point at. One each: the rows carry a real
    /// foreign key, and an Entry may hold only one open task (I13).
    Future<String> anEntry([String title = 'The saved page']) async {
      final folder = await v2.ui.folders.ensureRoot();
      final (entry, violation) = await v2.ui.entries.createStandalone(
        folderId: folder.id,
        title: title,
      );
      expect(violation, isNull, reason: 'seeding an Entry must not be refused');
      return entry!.id;
    }

    /// A queue row with its timestamps stated, which `enqueue` cannot give —
    /// it stamps the clock, and what the failure marker weighs is when one
    /// thing finished against when another was asked for.
    Future<void> putTask({
      required String entryId,
      required String id,
      required SaveTaskState state,
      required DateTime queuedAt,
      DateTime? finishedAt,
      int orderIndex = 0,
    }) => v2.library
        .into(v2.library.saveQueue)
        .insert(
          SaveQueueCompanion.insert(
            id: id,
            entryId: entryId,
            locationUrl: 'https://example.com/one/$id',
            state: Value(state.name),
            origin: Value(SaveTaskOrigin.queue.name),
            orderIndex: Value(orderIndex),
            queuedAt: queuedAt,
            finishedAt: Value(finishedAt),
          ),
        );

    /// [count] waiting rows, each for an Entry of its own.
    Future<void> queueSaves(int count) async {
      for (var i = 0; i < count; i++) {
        await putTask(
          entryId: await anEntry('Page $i'),
          id: 'q$i',
          state: SaveTaskState.queued,
          queuedAt: DateTime(2026, 8, 5, 12),
          orderIndex: i,
        );
      }
    }

    /// Read the count the pill is showing.
    String countOn(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(of: pill, matching: find.byType(Text)),
        )
        .first
        .data!;

    bool spinning(WidgetTester tester) => find
        .descendant(of: pill, matching: find.byType(CircularProgressIndicator))
        .evaluate()
        .isNotEmpty;

    bool hasIcon(WidgetTester tester, IconData icon) => find
        .descendant(of: pill, matching: find.byIcon(icon))
        .evaluate()
        .isNotEmpty;

    group('when it is there at all', () {
      indicatorTest('nothing outstanding shows nothing', (tester) async {
        await show(tester);
        expect(pill, findsNothing);
      });

      indicatorTest('queued work brings it up with its count', (tester) async {
        await queueSaves(2);
        await show(tester);

        expect(pill, findsOneWidget);
        expect(countOn(tester), '2');
      });

      indicatorTest('waiting work never claims to be moving', (tester) async {
        await queueSaves(1);
        await show(tester);

        expect(
          spinning(tester),
          isFalse,
          reason: 'a save waiting for an explicit Start is not running',
        );
        expect(hasIcon(tester, Icons.schedule), isTrue);
      });

      indicatorTest('a running save spins and counts itself', (tester) async {
        v2.runner.debugSetRunning(true);
        await show(tester);

        expect(pill, findsOneWidget);
        expect(countOn(tester), '1');
        expect(spinning(tester), isTrue);
      });

      indicatorTest('a direct run and its queue row are one job, not two', (
        tester,
      ) async {
        final entryId = await anEntry();
        await putTask(
          entryId: entryId,
          id: 'running-1',
          state: SaveTaskState.running,
          queuedAt: DateTime(2026, 8, 5, 12),
        );
        v2.runner.debugSetRunning(true);
        await show(tester);

        expect(countOn(tester), '1');
      });

      indicatorTest('a failed row on its own is history, not an indicator', (
        tester,
      ) async {
        final entryId = await anEntry();
        await putTask(
          entryId: entryId,
          id: 'failed-1',
          state: SaveTaskState.failed,
          queuedAt: DateTime(2026, 8, 5, 12),
          finishedAt: DateTime(2026, 8, 5, 12, 5),
        );
        await show(tester);

        expect(
          pill,
          findsNothing,
          reason: 'an indicator that never leaves is one nobody reads',
        );
      });
    });

    group('where it stays out of the way', () {
      indicatorTest('it stays out of the Browser, which says it all already', (
        tester,
      ) async {
        await queueSaves(1);
        await show(tester);
        expect(pill, findsOneWidget);

        browserOnScreen.value = true;
        await settle(tester);
        expect(pill, findsNothing);
      });

      indicatorTest('hiding the reader bars hides it too', (tester) async {
        await queueSaves(1);
        await show(tester);
        expect(pill, findsOneWidget);

        readerChrome.publish(false);
        await settle(tester);
        expect(pill, findsNothing);
      });

      indicatorTest('bringing the bars back brings it back', (tester) async {
        await queueSaves(1);
        await show(tester);
        readerChrome.publish(false);
        await settle(tester);
        expect(pill, findsNothing);

        readerChrome.publish(true);
        await settle(tester);
        expect(pill, findsOneWidget);
      });
    });

    // ─── a hidden Browser is what "held" means ──────────────────────────────
    //
    // There is no pause flag in V2 and deliberately should not be one: the
    // engine's render guards hold a capture the moment its surface stops
    // painting and resume when it returns, so the indicator reads that
    // condition rather than a mirror of it.

    group('a run whose surface stopped painting', () {
      indicatorTest('reads as held rather than as motion', (tester) async {
        v2.runner.debugSetRunning(true);
        surfacePainted.value = false;
        await show(tester);

        expect(
          pill,
          findsOneWidget,
          reason: 'a hold is worth showing — it is still the user\'s work',
        );
        expect(
          spinning(tester),
          isFalse,
          reason: 'a spinner over a page nobody is drawing claims a lie',
        );
        expect(hasIcon(tester, Icons.pause_circle_outline), isTrue);
      });

      indicatorTest('starts moving again the moment the surface returns', (
        tester,
      ) async {
        v2.runner.debugSetRunning(true);
        surfacePainted.value = false;
        await show(tester);
        expect(spinning(tester), isFalse);

        surfacePainted.value = true;
        await settle(tester);

        expect(spinning(tester), isTrue);
        expect(hasIcon(tester, Icons.pause_circle_outline), isFalse);
      });

      indicatorTest('a painted surface was never a hold to begin with', (
        tester,
      ) async {
        v2.runner.debugSetRunning(true);
        await show(tester);

        expect(hasIcon(tester, Icons.pause_circle_outline), isFalse);
        expect(spinning(tester), isTrue);
      });
    });

    group('the shape of the pill', () {
      indicatorTest('a large count cannot overflow it', (tester) async {
        await queueSaves(120);
        await show(tester);

        expect(countOn(tester), '99+');
        expect(tester.takeException(), isNull);
      });

      indicatorTest('the touch target holds at the app-wide size', (
        tester,
      ) async {
        await queueSaves(1);
        await show(tester);

        final box = tester.getRect(pill);
        expect(box.height, greaterThanOrEqualTo(kHeaderActionSize));
        expect(box.width, greaterThanOrEqualTo(kHeaderActionSize));
      });
    });

    group('what it says and where it goes', () {
      indicatorTest('it is one button, described in words', (tester) async {
        final semantics = tester.ensureSemantics();
        await queueSaves(2);
        await show(tester);

        expect(
          find.bySemanticsLabel(RegExp('2 waiting')),
          findsOneWidget,
          reason: 'a bare "2" tells a screen reader nothing',
        );
        expect(find.bySemanticsLabel(RegExp('Opens Activity')), findsOneWidget);
        semantics.dispose();
      });

      indicatorTest('tapping it asks for the detail surface', (tester) async {
        await queueSaves(1);
        await show(tester);

        await tester.tap(pill);
        await settle(tester);

        expect(detailsOpened, 1);
        expect(
          browserOpened,
          0,
          reason: 'nothing is holding on the user, so nothing wants a Browser',
        );
      });
    });
  });
}
