/// Roughly what a download will cost, from what it has cost.
///
/// V1 showed an estimate and the free space before the user chose a count, and
/// it went out with the scope sheet in `b0740eb`. What replaced it was a
/// per-row disk gate that fails a row silently once a run is already going —
/// which answers the safety question and not the user's.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/size_estimate.dart';

void main() {
  const mb = 1024 * 1024;

  test('a collection with history expects the same again', () {
    final estimate = estimateDownload(
      alreadyDownloaded: [10 * mb, 12 * mb, 11 * mb],
      entries: 10,
    );

    expect(estimate.isKnown, isTrue);
    expect(estimate.bytes, 11 * mb * 10);
    expect(estimate.sampleSize, 3);
    expect(estimate.isRough, isFalse);
  });

  test('one enormous entry does not drag the figure', () {
    // The median, not the mean: an entry that happened to be one tall
    // image should not set expectations for the ordinary ones after it.
    final estimate = estimateDownload(
      alreadyDownloaded: [10 * mb, 11 * mb, 12 * mb, 900 * mb],
      entries: 1,
    );

    expect(estimate.bytes, lessThan(20 * mb));
  });

  test('a collection nothing has been downloaded from says nothing', () {
    final estimate = estimateDownload(alreadyDownloaded: [], entries: 10);

    expect(estimate.isKnown, isFalse);
    expect(
      downloadEstimateSentence(estimate, (b) => '\$b'),
      isNull,
      reason:
          'a number invented for a collection nothing has been saved '
          'from is a guess wearing an estimate\'s clothes',
    );
  });

  test('an estimate from one entry says it is rough', () {
    final estimate = estimateDownload(alreadyDownloaded: [8 * mb], entries: 5);

    expect(estimate.isRough, isTrue);
    expect(
      downloadEstimateSentence(estimate, (b) => 'SIZE'),
      contains('Roughly'),
    );
  });

  test('a solid estimate is stated as about, never exactly', () {
    final estimate = estimateDownload(
      alreadyDownloaded: [9 * mb, 10 * mb, 11 * mb, 10 * mb],
      entries: 4,
    );

    expect(
      downloadEstimateSentence(estimate, (b) => 'SIZE'),
      contains('About SIZE'),
    );
  });

  test('zero entries is not a download', () {
    expect(
      estimateDownload(alreadyDownloaded: [10 * mb], entries: 0).isKnown,
      isFalse,
    );
  });

  test('copies with no recorded size are left out of the sample', () {
    final estimate = estimateDownload(
      alreadyDownloaded: [0, 10 * mb, 0],
      entries: 1,
    );

    expect(estimate.sampleSize, 1);
    expect(estimate.bytes, 10 * mb);
  });
}
