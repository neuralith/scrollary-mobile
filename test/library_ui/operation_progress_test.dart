/// What a person can see while a download runs.
///
/// The regression this pins: `SaveEngine` published entry counters, image
/// counts, failures and a log through two nullable callbacks, and the V2
/// composition built the engine without either — so a ten-entry download
/// showed one indeterminate bar and an entry title, and every counter the
/// engine computed went nowhere.
///
/// Two guarantees are asserted here, and the second is why this file names
/// the parity contract: the counts reach the surface, and **seeing them is
/// never gated**.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/operation_progress.dart';
import 'package:web_reader/features/running_operation_panel.dart';
import 'package:web_reader/save/save_state.dart';

void main() {
  group('the progress line', () {
    test('names the entry within the batch and the images within the '
        'entry', () {
      final parts = operationProgressParts(
        position: 3,
        total: 10,
        progress: const SaveProgress(detectedImages: 18, storedImages: 12),
      );

      expect(parts, ['Entry 3 of 10', '12 of 18 images']);
    });

    test('a batch of one says nothing about position', () {
      // "Entry 1 of 1" is noise: the panel already names the entry.
      final parts = operationProgressParts(
        position: 1,
        total: 1,
        progress: const SaveProgress(detectedImages: 6, storedImages: 6),
      );

      expect(parts, ['6 of 6 images']);
    });

    test('images the site would not give up are counted, not hidden', () {
      final parts = operationProgressParts(
        position: 2,
        total: 4,
        progress: const SaveProgress(
          detectedImages: 20,
          storedImages: 18,
          failedImages: 2,
        ),
      );

      expect(parts, [
        'Entry 2 of 4',
        '18 of 20 images',
        '2 could not be fetched',
      ]);
    });

    test('nothing known yet is an empty line, never a row of zeroes', () {
      expect(
        operationProgressParts(
          position: 0,
          total: 0,
          progress: const SaveProgress(),
        ),
        isEmpty,
      );
    });
  });

  group('the store behind it', () {
    test('applies the engine\'s updates and keeps its log', () {
      final progress = OperationProgress();
      addTearDown(progress.dispose);

      progress.apply((p) => p.copyWith(detectedImages: 9));
      progress.apply((p) => p.copyWith(storedImages: 4));
      progress.record('[engine] scroll pass 1');

      expect(progress.progress.detectedImages, 9);
      expect(progress.progress.storedImages, 4);
      expect(progress.log, ['[engine] scroll pass 1']);
      expect(progress.hasReading, isTrue);
    });

    test('a new entry starts from zero, and the log survives it', () {
      final progress = OperationProgress();
      addTearDown(progress.dispose);
      progress.apply((p) => p.copyWith(detectedImages: 9, storedImages: 9));
      progress.record('[engine] saved 9/9 images');

      progress.beginEntry();

      expect(progress.progress.detectedImages, 0);
      expect(
        progress.log,
        hasLength(1),
        reason:
            'the log is the thread through the batch, not through one '
            'entry — it is what makes "the third one failed" explainable',
      );
    });

    test('the log is bounded', () {
      final progress = OperationProgress();
      addTearDown(progress.dispose);

      for (var i = 0; i < kOperationLogLimit + 50; i++) {
        progress.record('line $i');
      }

      expect(progress.log, hasLength(kOperationLogLimit));
      expect(
        progress.log.last,
        'line ${kOperationLogLimit + 49}',
        reason: 'the newest lines are the ones worth keeping',
      );
    });
  });

  test('progress is never behind an entitlement', () {
    // docs/V2_CAPABILITY_PARITY.md: Pro buys foreground multitasking — *where*
    // the user waits — and nothing about whether they can see the work.
    for (final path in [
      'lib/features/operation_progress.dart',
      'lib/features/running_operation_panel.dart',
      'lib/features/activity_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains('capability/'),
        isFalse,
        reason: '$path must never import an entitlement',
      );
    }
  });
}
