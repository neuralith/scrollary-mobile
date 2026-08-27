/// The pull-up gesture, judged on the one thing that decides whether it is
/// usable: **it must never fire when nobody asked for it.**
///
/// A gesture that shares an edge with ordinary reading gets exactly one chance
/// with a user. So the cases here are mostly the ones where nothing may
/// happen — reading to the end, flinging into the end, pulling a little,
/// pulling a lot and changing your mind — and only one where something does.
///
/// Both scroll physics are exercised, because they express a pull past the end
/// in two completely different ways: clamping (Android) refuses the motion and
/// reports it as overscroll, bouncing (iOS) lets the position itself travel.
/// A rule proved under one of them is proved under half the devices.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/pull_up_next.dart';

void main() {
  for (final (name, physics) in [
    ('clamping physics', const ClampingScrollPhysics()),
    ('bouncing physics', const BouncingScrollPhysics()),
  ]) {
    group(name, () {
      late PullUpController pull;
      late ScrollController scroll;
      late int requests;

      setUp(() {
        pull = PullUpController();
        scroll = ScrollController();
        requests = 0;
      });
      tearDown(() {
        pull.dispose();
        scroll.dispose();
      });

      Widget app({bool enabled = true}) => MaterialApp(
        home: Scaffold(
          body: PullUpForNext(
            controller: pull,
            onRequest: enabled ? () async => requests++ : null,
            child: ListView(
              controller: scroll,
              physics: physics,
              children: const [SizedBox(height: 3000)],
            ),
          ),
        ),
      );

      /// Open, and put the reader at the very end of the entry — which is the
      /// only place any of this is allowed to start from.
      Future<void> openAtTheEnd(WidgetTester tester) async {
        await tester.pumpWidget(app());
        await tester.pump();
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
      }

      /// A finger going up the screen, in the small steps a real one moves in.
      Future<TestGesture> pullUpBy(WidgetTester tester, double distance) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ListView)),
        );
        // Clear the touch slop first, so the scroll view owns the gesture and
        // every step after this is a delta it has actually applied.
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        for (var moved = 0.0; moved < distance; moved += 20) {
          await gesture.moveBy(const Offset(0, -20));
          await tester.pump();
        }
        return gesture;
      }

      testWidgets('reading to the end reveals nothing and advances '
          'nothing', (tester) async {
        await tester.pumpWidget(app());
        await tester.pump();

        // A long, ordinary reading scroll that stops at the end.
        await tester.drag(find.byType(ListView), const Offset(0, -2400));
        await tester.pumpAndSettle();

        expect(pull.value, 0, reason: 'nothing was revealed');
        expect(requests, 0);
      });

      testWidgets('flinging into the end does not advance', (tester) async {
        await tester.pumpWidget(app());
        await tester.pump();
        scroll.jumpTo(scroll.position.maxScrollExtent - 900);
        await tester.pump();

        // The drag itself stops well short of the end; the fling carries it
        // into the bottom at speed. That ballistic overscroll is not a pull —
        // no finger is driving it.
        await tester.fling(find.byType(ListView), const Offset(0, -300), 8000);
        await tester.pumpAndSettle();

        expect(scroll.position.pixels, scroll.position.maxScrollExtent);
        expect(pull.value, 0);
        expect(requests, 0, reason: 'arriving fast is not asking');
      });

      testWidgets('a short pull past the end asks for nothing', (tester) async {
        await openAtTheEnd(tester);

        final gesture = await pullUpBy(tester, 40);
        expect(pull.armed, isFalse);
        await gesture.up();
        await tester.pumpAndSettle();

        expect(requests, 0);
        expect(pull.value, 0, reason: 'the affordance goes back down');
      });

      testWidgets('a long pull arms, says so, and fires on release', (
        tester,
      ) async {
        await openAtTheEnd(tester);

        final gesture = await pullUpBy(tester, 260);
        expect(pull.armed, isTrue, reason: 'past the threshold');

        // Nothing has been asked for yet: crossing the line arms it, releasing
        // is what commits.
        expect(requests, 0);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(requests, 1);
      });

      testWidgets('changing your mind before letting go cancels it', (
        tester,
      ) async {
        await openAtTheEnd(tester);

        final gesture = await pullUpBy(tester, 260);
        expect(pull.armed, isTrue);

        // Back down the screen, past the threshold and then some.
        for (var i = 0; i < 16; i++) {
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();
        }
        expect(pull.armed, isFalse, reason: 'disarmed on the way back');

        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          requests,
          0,
          reason:
              'releasing below the threshold does '
              'nothing at all',
        );
      });

      testWidgets('an entry with no reading order is inert', (tester) async {
        await tester.pumpWidget(app(enabled: false));
        await tester.pump();
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();

        final gesture = await pullUpBy(tester, 260);
        await gesture.up();
        await tester.pumpAndSettle();

        expect(pull.value, 0);
        expect(requests, 0);
      });

      testWidgets('one pull is one request, however hard it is pulled', (
        tester,
      ) async {
        await openAtTheEnd(tester);

        final first = await pullUpBy(tester, 400);
        await first.up();
        await tester.pumpAndSettle();
        final second = await pullUpBy(tester, 400);
        await second.up();
        await tester.pumpAndSettle();

        expect(requests, 2, reason: 'two pulls, two requests — and no more');
      });
    });
  }

  group('the affordance', () {
    testWidgets('says what the pull will do, and what releasing now would '
        'do', (tester) async {
      final controller = PullUpController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [PullUpAffordance(controller: controller)]),
          ),
        ),
      );

      // At rest it is not on the screen at all.
      expect(find.byKey(const ValueKey('pullUpNextLabel')), findsNothing);

      controller.value = 40;
      await tester.pump();
      expect(find.text('Pull up for next entry'), findsOneWidget);

      controller.value = kPullUpThreshold;
      await tester.pump();
      expect(find.text('Release for next entry'), findsOneWidget);
    });
  });
}
