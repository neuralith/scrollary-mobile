import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/reading/decode_budget.dart';

/// Decoding a stored image is where a Reader's memory actually goes, and both
/// readers used to ask for it wrong in the same way. Measured on a physical
/// iPhone: an image-heavy structured document reached ~1.4 GB, on content whose
/// stored panels are narrower than the screen.
void main() {
  group('decode width', () {
    test('never exceeds what the file actually has', () {
      // The bug: 800px of stored art asked for at 1179px is an upscale, and an
      // upscaled bitmap costs (1179/800)^2 = 2.17x for no added detail.
      expect(
        decodeWidthFor(
          displayWidth: 393,
          devicePixelRatio: 3,
          naturalWidth: 800,
        ),
        800,
      );
    });

    test('still downscales when the file is bigger than the screen', () {
      expect(
        decodeWidthFor(
          displayWidth: 393,
          devicePixelRatio: 3,
          naturalWidth: 4000,
        ),
        1179,
      );
    });

    test('unknown natural width is not guessed at', () {
      // A save that could not verify dimensions says so. "Do not know" must
      // behave exactly as it did before, not as "assume something".
      expect(decodeWidthFor(displayWidth: 393, devicePixelRatio: 3), 1179);
      expect(
        decodeWidthFor(displayWidth: 393, devicePixelRatio: 3, naturalWidth: 0),
        1179,
      );
    });

    test('a degenerate display width produces no instruction at all', () {
      expect(decodeWidthFor(displayWidth: 0, devicePixelRatio: 3), isNull);
    });
  });

  group('decode budget', () {
    test('an ordinary panel is never touched', () {
      // 1179 x 4000 is 4.7 MP — nowhere near the ceiling.
      expect(
        decodeWidthWithinBudget(
          width: 1179,
          naturalWidth: 1179,
          naturalHeight: 4000,
        ),
        1179,
      );
    });

    test('a pathologically tall strip is capped by area, not by height', () {
      // 1179 wide at 20:1 would be 27.8 MP.
      final capped = decodeWidthWithinBudget(
        width: 1179,
        naturalWidth: 1000,
        naturalHeight: 20000,
      );
      expect(capped, lessThan(1179));
      final area = capped * capped * 20;
      expect(
        area,
        lessThanOrEqualTo(kPanelDecodeBudgetPixels + 1),
        reason: 'the point of the cap is the decoded area',
      );
    });

    test('unknown dimensions leave the width alone', () {
      expect(
        decodeWidthWithinBudget(
          width: 1179,
          naturalWidth: null,
          naturalHeight: 4000,
        ),
        1179,
      );
      expect(
        decodeWidthWithinBudget(
          width: 1179,
          naturalWidth: 1179,
          naturalHeight: null,
        ),
        1179,
      );
    });

    test('the cap can only ever shrink, never grow', () {
      for (final h in [100, 1000, 8000, 40000]) {
        expect(
          decodeWidthWithinBudget(
            width: 900,
            naturalWidth: 900,
            naturalHeight: h,
          ),
          lessThanOrEqualTo(900),
        );
      }
    });
  });
}
