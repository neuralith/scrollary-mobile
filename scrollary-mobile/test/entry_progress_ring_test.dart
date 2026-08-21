import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/ui/status_style.dart';

/// The entry list's progress pie shows the real value, not a bucketed icon.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  EntryProgressRing ring(double fraction, {bool completed = false}) =>
      EntryProgressRing(fraction: fraction, completed: completed);

  testWidgets('0% renders an empty ring, not a filled one', (tester) async {
    await tester.pumpWidget(host(ring(0)));

    final painter = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(EntryProgressRing),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(painter.painter, isNotNull);
    // An empty ring still repaints against a filled one: 0% is a value, not
    // an absence.
    expect(
      painter.painter!.shouldRepaint(
        tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(EntryProgressRing),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!,
      ),
      isFalse,
    );
  });

  testWidgets('the painter repaints only when the value changes', (
    tester,
  ) async {
    await tester.pumpWidget(host(ring(0.4)));
    final first = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(EntryProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    await tester.pumpWidget(host(ring(0.4)));
    final same = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(EntryProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(
      same.shouldRepaint(first),
      isFalse,
      reason: 'an unchanged row must not repaint on every list rebuild',
    );

    await tester.pumpWidget(host(ring(0.75)));
    final moved = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(EntryProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(moved.shouldRepaint(first), isTrue);
  });

  group('semantics expose the percentage', () {
    testWidgets('unread', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ring(0)));
      expect(find.bySemanticsLabel('Unread · 0%'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('partially read', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ring(0.42)));
      expect(find.bySemanticsLabel('Reading progress 42%'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('finished', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ring(1, completed: true)));
      expect(find.bySemanticsLabel('Read · 100%'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('a completed entry always reads as 100%', (tester) async {
    final handle = tester.ensureSemantics();
    // Even handed a stale lower fraction, "finished" is the fact the user
    // asserted (D39).
    await tester.pumpWidget(host(ring(0.3, completed: true)));
    expect(find.bySemanticsLabel('Read · 100%'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('it works at a compact list-row size', (tester) async {
    await tester.pumpWidget(
      host(
        const SizedBox.square(
          dimension: 14,
          child: EntryProgressRing(fraction: 0.5, completed: false, size: 14),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(EntryProgressRing)), const Size(14, 14));
  });

  test('the canonical rule feeds the ring', () {
    // What the row passes in: completed is pinned at 1 before it ever reaches
    // the painter.
    expect(readProgressFor(readStatus: 'completed', stored: 0.3), 1);
    expect(
      readProgressFor(readStatus: 'inProgress', stored: 0.42),
      closeTo(0.42, 0.0001),
    );
    expect(readProgressFor(readStatus: 'unread', stored: 0), 0);
  });
}
