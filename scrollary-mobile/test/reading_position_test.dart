import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/reading/reading_position.dart';

/// Panels 800 wide by 1200 tall, the shape the fixture produces.
List<({int? width, int? height})> panels(
  int count, {
  int w = 800,
  int h = 1200,
}) => List.generate(count, (_) => (width: w, height: h));

void main() {
  group('layout geometry', () {
    test('panel heights scale to the viewport width', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(3));
      // 800x1200 at 400 wide is 600 tall.
      expect(layout.heightOf(0), 600);
      expect(layout.total, 1800);
      expect(layout.offsetOf(2), 1200);
    });

    test('a panel with no recorded size still gets a place to stand', () {
      final layout = EntryLayout(
        viewportWidth: 400,
        panels: [(width: null, height: null), (width: 800, height: 1200)],
      );
      expect(layout.heightOf(0), greaterThan(0));
      expect(layout.total, greaterThan(600));
    });

    test('an empty entry has no geometry and cannot be scrolled into', () {
      final layout = EntryLayout(viewportWidth: 400, panels: const []);
      expect(layout.isEmpty, isTrue);
      expect(layout.offsetForPosition(const ReadingPosition(fraction: 0.5)), 0);
    });
  });

  group('anchor restoration', () {
    test('restores to the exact panel and offset within it', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(5));
      const position = ReadingPosition(
        fraction: 0.4,
        anchorIndex: 2,
        offsetInAnchor: 0.5,
      );
      // Panel 2 starts at 1200; half of its 600 height is 300 more.
      expect(layout.offsetForPosition(position), 1500);
    });

    test('round-trips a scroll offset back to the same position', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(5));
      final position = layout.positionForOffset(1500, viewportHeight: 600);

      expect(position.anchorIndex, 2);
      expect(position.offsetInAnchor, closeTo(0.5, 0.001));
      expect(layout.offsetForPosition(position), closeTo(1500, 0.001));
    });

    test('falls back to the fraction when the anchor no longer exists', () {
      // Re-downloaded with fewer panels: the saved anchor points past the end.
      final smaller = EntryLayout(viewportWidth: 400, panels: panels(3));
      const stale = ReadingPosition(
        fraction: 0.5,
        anchorIndex: 9,
        offsetInAnchor: 0.2,
      );

      final offset = smaller.offsetForPosition(stale);
      expect(offset, closeTo(smaller.total * 0.5, 0.001));
      expect(offset, lessThanOrEqualTo(smaller.total));
    });

    test('a fraction restore still lands somewhere valid after a resize', () {
      final narrow = EntryLayout(viewportWidth: 300, panels: panels(4));
      final wide = EntryLayout(viewportWidth: 600, panels: panels(4));
      const position = ReadingPosition(
        fraction: 0.5,
        anchorIndex: 2,
        offsetInAnchor: 0,
      );

      // The anchor is what keeps the *content* stable across a width change,
      // which raw pixel offsets could not.
      expect(narrow.offsetForPosition(position), narrow.offsetOf(2));
      expect(wide.offsetForPosition(position), wide.offsetOf(2));
    });

    test('a missing asset does not shift the panels after it', () {
      // A panel whose file is gone still occupies its recorded height, so the
      // anchors of later panels stay correct.
      final layout = EntryLayout(viewportWidth: 400, panels: panels(4));
      expect(layout.offsetOf(3), 1800);
    });
  });

  group('progress fraction', () {
    test('is 0 at the top and 1 once the end is on screen', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(4));
      expect(layout.positionForOffset(0, viewportHeight: 600).fraction, 0);

      // Scrolled as far as it goes: content 2400, viewport 600 -> max 1800.
      final end = layout.positionForOffset(1800, viewportHeight: 600);
      expect(end.fraction, 1.0);
    });

    test('an entry shorter than the viewport counts as fully read', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(1));
      final position = layout.positionForOffset(0, viewportHeight: 2000);
      expect(position.fraction, 1.0);
    });

    test('is clamped even when handed a nonsense offset', () {
      final layout = EntryLayout(viewportWidth: 400, panels: panels(3));
      expect(
        layout.positionForOffset(999999, viewportHeight: 600).fraction,
        1.0,
      );
      expect(layout.positionForOffset(-50, viewportHeight: 600).fraction, 0.0);
    });
  });

  group('completion policy', () {
    const policy = kDefaultCompletionPolicy;

    test('does not fire before the threshold', () {
      expect(policy.reachedEnd(0.5), isFalse);
      expect(policy.reachedEnd(0.96), isFalse);
    });

    test('fires at and past the threshold', () {
      expect(policy.reachedEnd(0.97), isTrue);
      expect(policy.reachedEnd(1.0), isTrue);
    });

    test('the threshold is short of the last pixel on purpose', () {
      // A trailing comments section or an over-tall final panel would make an
      // exact 1.0 requirement impossible to satisfy.
      expect(policy.threshold, lessThan(1.0));
      expect(policy.threshold, greaterThan(0.9));
    });

    test('near-completion is a question, not a second completion rule', () {
      // Well short: moving on here is a skip ahead, and asking about it would
      // be a nag.
      expect(policy.nearEnd(0.5), isFalse);
      expect(policy.nearEnd(0.89), isFalse);
      // Close enough that "did you finish this?" is fair.
      expect(policy.nearEnd(0.9), isTrue);
      expect(policy.nearEnd(0.96), isTrue);
      // And still fair past the automatic threshold: a fling to the bottom
      // clears [reachedEnd] without ever satisfying the dwell, so the entry is
      // unfinished and is exactly what the question is for.
      expect(policy.nearEnd(0.97), isTrue);
      expect(policy.nearEnd(1.0), isTrue);
    });

    test('near-completion sits below automatic completion, with room', () {
      expect(policy.nearThreshold, lessThan(policy.threshold));
      // Not merely below it: the gap is the band the question lives in, and a
      // near-threshold pressed up against the automatic one would leave almost
      // nothing to ask about.
      expect(policy.threshold - policy.nearThreshold, greaterThan(0.05));
      // Nor so low that most of an entry counts as nearly finished.
      expect(policy.nearThreshold, greaterThan(0.75));
    });

    test('requires dwell, so a fling to the bottom is not reading', () {
      expect(policy.dwell, greaterThan(Duration.zero));
    });
  });
}
