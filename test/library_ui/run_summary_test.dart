/// What a finished batch says for itself.
///
/// The regression this pins: a ten-entry download ended in silence. The
/// indicator disappeared when the count reached zero, and the only sentence
/// anyone saw about the batch described the *queueing* — held in a bottom
/// sheet's state and destroyed with the sheet.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/run_summary.dart';
import 'package:web_reader/save/queue_runner.dart';

void main() {
  RunSummary run({
    int requested = 10,
    int downloaded = 10,
    int failed = 0,
    int cancelled = 0,
    bool stoppedEarly = false,
  }) => RunSummary(
    requested: requested,
    downloaded: downloaded,
    failed: failed,
    cancelled: cancelled,
    stoppedEarly: stoppedEarly,
  );

  group('the headline', () {
    test('a run that did everything asked says so plainly', () {
      expect(runSummaryHeadline(run()), '10 entries downloaded');
      expect(runSummaryDetail(run()), isEmpty);
    });

    test('one entry is not "1 entries"', () {
      expect(
        runSummaryHeadline(run(requested: 1, downloaded: 1)),
        '1 entry downloaded',
      );
    });

    test('a partial run names both numbers', () {
      // "Finished" and "finished some of it" are different outcomes.
      expect(
        runSummaryHeadline(run(downloaded: 8, failed: 2)),
        '8 of 10 entries downloaded',
      );
      expect(
        runSummaryDetail(run(downloaded: 8, failed: 2)),
        '2 could not be completed',
      );
    });

    test('a stopped run is not a failed one', () {
      final stopped = run(downloaded: 0, cancelled: 1, stoppedEarly: true);
      expect(runSummaryHeadline(stopped), 'Download stopped');
      expect(
        runSummaryDetail(stopped),
        '1 stopped · the run ended before the rest were reached',
      );
    });

    test('a run that ended before reaching the rest says that too', () {
      // The disk gate ends the loop with work still eligible; saying "3
      // downloaded" alone would imply the other seven were tried.
      final short = run(downloaded: 3, stoppedEarly: true);
      expect(runSummaryHeadline(short), '3 of 10 entries downloaded');
      expect(
        runSummaryDetail(short),
        'the run ended before the rest were reached',
      );
    });
  });

  group('what needs a person', () {
    test('a clean run needs nothing', () {
      expect(run().needsAttention, isFalse);
    });

    test('a failure or an early end does', () {
      expect(run(downloaded: 9, failed: 1).needsAttention, isTrue);
      expect(run(downloaded: 3, stoppedEarly: true).needsAttention, isTrue);
    });

    test('settled counts every row that reached an end', () {
      expect(run(downloaded: 6, failed: 2, cancelled: 1).settled, 9);
    });
  });
}
