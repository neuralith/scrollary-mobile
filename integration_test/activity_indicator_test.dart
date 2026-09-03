// Where the compact activity indicator actually lands, on a real device.
//
//   flutter test integration_test/activity_indicator_test.dart -d <device-id>
//
// Everything about *when* the pill appears is decided in Dart and proved by the
// deterministic suite, which needs no device at all. The one thing a widget
// test cannot answer is the question this file exists for: **does it clear the
// hardware.** A simulated view padding is a number someone typed; a notch is
// not. So this boots the real app, puts one waiting row in the queue, and
// measures the pill against the insets the platform reports and against the
// shell's own chrome.
//
// No fixture server, no WebView, no capture: none of that is what is under
// test. The row is written straight through `SaveQueueRepository.enqueue`,
// which is the V2 replacement for V1's `upsertQueueTask` and the same row the
// Browser's save sheet writes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/ui/status_style.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late V2App app;
  var caseIndex = 0;

  Future<void> boot(WidgetTester tester) async {
    app = V2App(tag: 'ind_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
  }

  tearDown(() => app.shutdown(dumpLog: false));

  /// One save waiting for an explicit Start: the quietest state that still puts
  /// the pill on screen, and the one that leaves nothing spinning to settle.
  ///
  /// A reserved example domain, never a real host — the address is only there
  /// so the row has one.
  var queued = 0;
  Future<SaveTask> queueOne() async {
    // A distinct address each time: `url_key` is unique within a library, so
    // two Entries cannot share one — which is the invariant, not an obstacle.
    final url = 'https://reader.example/guide/foo/${++queued}';
    final id = await app.addEntry(url, title: 'A waiting item');
    final result = await app.ui.queue.enqueue(
      entryId: id.entryId,
      locationId: id.locationId,
      locationUrl: url,
    );
    expect(result.task, isNotNull);
    return result.task!;
  }

  final pill = find.byKey(const ValueKey('operationIndicator'));

  testWidgets(
    'it clears the hardware and the shell it floats over',
    (tester) async {
      await boot(tester);
      expect(pill, findsNothing, reason: 'an idle app says nothing');

      await queueOne();
      await pumpUntil(
        tester,
        () => pill.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'a waiting row must put the pill on screen',
      );

      final view = tester.view;
      final insetTop = view.padding.top / view.devicePixelRatio;
      final insetBottom = view.padding.bottom / view.devicePixelRatio;
      final screen = tester.getSize(find.byType(MaterialApp));
      final box = tester.getRect(pill);

      debugPrint(
        '[IND] screen=$screen insetTop=$insetTop insetBottom=$insetBottom '
        'pill=$box',
      );

      expect(
        box.top,
        greaterThanOrEqualTo(insetTop),
        reason: 'never under the status bar, notch or Dynamic Island',
      );
      expect(
        box.top,
        greaterThanOrEqualTo(insetTop + kToolbarHeight),
        reason: 'and never on the row where header actions sit',
      );
      expect(box.right, lessThanOrEqualTo(screen.width));
      expect(box.left, greaterThan(0));
      expect(
        box.height,
        greaterThanOrEqualTo(kHeaderActionSize),
        reason: 'the touch target survives the platform text size',
      );

      // The shell's bottom bar is the one piece of chrome that is always in the
      // same place. Nothing about the pill may reach it.
      expect(
        box.bottom,
        lessThan(screen.height - insetBottom - kShellBottomBarHeight),
      );

      // …and it is clear of the Library header's own actions, which live at
      // the top right of the screen it is floating over.
      //
      // **Clear of, not below.** This used to require `box.top >=
      // headerAction.bottom`, which encoded one particular arrangement — the
      // header on top, the pill under it. The one-page Library (V2-D43) draws
      // its header lower than a toolbar would sit, and the pill now floats
      // *above* that row rather than below it. Measured on an iPhone 17 Pro
      // simulator: pill 126–166, header actions 172–216. The requirement was
      // never the order, it is that the two do not sit on top of each other,
      // so that is what is asserted.
      final headerAction = tester.getRect(find.byTooltip('New folder'));
      debugPrint('[IND] headerAction=$headerAction');
      final overlaps =
          box.top < headerAction.bottom && headerAction.top < box.bottom;
      expect(
        overlaps,
        isFalse,
        reason:
            'the pill and the header\'s own actions must not share a band of '
            'the screen — whichever of them is on top',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'it counts what is outstanding, and says so out loud',
    (tester) async {
      await boot(tester);
      await queueOne();
      await queueOne();
      await pumpUntil(
        tester,
        () => pill.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
      );

      expect(
        find.descendant(of: pill, matching: find.text('2')),
        findsOneWidget,
        reason: 'the pill is a count, not an account',
      );
      // The count in words, and the destination named: a button that does not
      // say where it goes is one nobody presses twice. Read from the real
      // semantics tree, which is where an assistive technology reads it — and
      // which has to be asked for, because nothing on the device is running
      // one.
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Background work — 2 waiting. Opens Activity.'),
        findsOneWidget,
      );
      // Disposed inline, not through `addTearDown`: flutter_test verifies that
      // no handle outlived the body *before* it runs tear-downs.
      semantics.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'tapping it lands on Activity, and it leaves with the work',
    (tester) async {
      await boot(tester);
      final task = await queueOne();
      await pumpUntil(
        tester,
        () => pill.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
      );

      await tester.tap(pill, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 3));
      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(
        find.text('WAITING · 1'),
        findsOneWidget,
        reason: 'grouped by what the user can do about it',
      );
      expect(find.byKey(ValueKey('activityRow-${task.id}')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('activityStart')),
        findsOneWidget,
        reason: 'waiting work is offered a Start and never starts itself',
      );

      // The row goes; so does the pill. Proved here rather than only in Dart
      // because this is the real stream, the real database and the real router.
      // Cancel first — a live row is never dropped — then remove the terminal
      // row, which is *Remove from Activity* and deletes no Entry and no file.
      expect(
        await app.ui.queue.cancel(task.id),
        SaveCancelOutcome.cancelledBeforeStart,
      );
      expect(await app.ui.queue.removeTerminal(task.id), isTrue);
      await pumpUntil(
        tester,
        () => pill.evaluate().isEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'the pill outlived the work it was reporting',
      );
      expect(
        await app.ui.entries.byId(task.entryId),
        isNotNull,
        reason: 'and removing the row removed nothing from the library',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
