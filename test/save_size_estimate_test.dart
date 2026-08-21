import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/size_estimate.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/manifest.dart';

/// The size estimate shown before a save: built from what this collection has
/// actually cost, from finished saves only, and never from a flat constant
/// multiplied by an entry count.
void main() {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;

  /// A finished, still-present entry of [bytes]. Everything not named here is
  /// irrelevant to the estimate and is filled with something valid.
  Entry entry({
    required int bytes,
    String status = 'complete',
    String? contentPath = 'library/c/e',
    DateTime? offlineRemovedAt,
    ArtifactFormat artifact = ArtifactFormat.imageSequence,
    String id = 'e',
  }) => Entry(
    id: id,
    collectionId: 'c',
    title: 'Entry',
    sourceUrl: 'https://example.com/$id',
    urlKey: 'example.com/$id',
    host: 'example.com',
    contentKind: 'imageDominant',
    contentKindConfidence: 'high',
    contentKindIsUserSet: false,
    artifactFormat: artifact.name,
    saveStatus: status,
    contentPath: contentPath,
    detectedAssetCount: 10,
    storedAssetCount: 10,
    entryOrder: 1,
    byteSize: bytes,
    offlineRemovedAt: offlineRemovedAt,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

  List<int> historyOf(List<Entry> entries) =>
      CollectionSizeHistory.fromEntries(entries).forArtifact(null);

  group('a collection with saved entries estimates from its own sizes', () {
    test('one entry costs what a typical entry here has cost', () {
      final history = historyOf([
        for (final (i, size) in [6, 6, 6, 7, 6].indexed)
          entry(bytes: size * mb, id: 'e$i'),
      ]);

      final estimate = estimateSaveSize(entryCount: 1, historyBytes: history);

      expect(estimate.basis, SizeEstimateBasis.collectionHistory);
      expect(estimate.typicalEntryBytes, 6 * mb);
      expect(estimate.lowBytes, 6 * mb);
      expect(estimate.highBytes, 6 * mb);
      // A band that has collapsed reads as one number, not "6–6 MB".
      expect(estimate.sizeLabel, '6 MB');
      expect(estimate.qualifier, contains('already saved here'));
    });

    test('the global constant is not what a save is measured against', () {
      // 12 MB entries: what the old estimator reported for four of them was
      // 4 × 50 MB = 200 MB, nearly four times the truth.
      final history = historyOf([
        for (var i = 0; i < 6; i++) entry(bytes: 12 * mb, id: 'e$i'),
      ]);

      final estimate = estimateSaveSize(entryCount: 4, historyBytes: history);

      expect(estimate.lowBytes, 48 * mb);
      expect(estimate.highBytes, 48 * mb);
      expect(estimate.sizeLabel, '48 MB');
    });

    test('more entries scale the collection-specific figure', () {
      final history = historyOf([
        for (var i = 0; i < 5; i++) entry(bytes: 3 * mb, id: 'lo$i'),
        for (var i = 0; i < 5; i++) entry(bytes: 5 * mb, id: 'hi$i'),
      ]);

      final one = estimateSaveSize(entryCount: 1, historyBytes: history);
      final ten = estimateSaveSize(entryCount: 10, historyBytes: history);

      expect(one.lowBytes, 3 * mb);
      expect(one.highBytes, 5 * mb);
      expect(ten.lowBytes, one.lowBytes! * 10);
      expect(ten.highBytes, one.highBytes! * 10);
      expect(ten.sizeLabel, '30–50 MB');
    });

    test(
      'the band is the middle of the data, so one freak entry is not it',
      () {
        final ordinary = [
          for (var i = 0; i < 8; i++) entry(bytes: 8 * mb, id: 'e$i'),
        ];
        final withOutlier = [...ordinary, entry(bytes: 4 * gb, id: 'huge')];

        final before = estimateSaveSize(
          entryCount: 5,
          historyBytes: historyOf(ordinary),
        );
        final after = estimateSaveSize(
          entryCount: 5,
          historyBytes: historyOf(withOutlier),
        );

        expect(after.typicalEntryBytes, before.typicalEntryBytes);
        expect(after.highBytes, before.highBytes);
        expect(after.sizeLabel, '40 MB');
        // A mean over the same rows would have said ~2.3 GB.
        expect(after.highBytes, lessThan(gb));
      },
    );

    test('a single unusually small entry does not drag the band down', () {
      final history = historyOf([
        entry(bytes: 512 * 1024, id: 'tiny'),
        for (var i = 0; i < 8; i++) entry(bytes: 10 * mb, id: 'e$i'),
      ]);

      final estimate = estimateSaveSize(entryCount: 3, historyBytes: history);

      expect(estimate.typicalEntryBytes, 10 * mb);
      expect(estimate.lowBytes, 30 * mb);
    });

    test('history is kept apart by artifact, so a text save is not '
        'estimated from image packages', () {
      final history = CollectionSizeHistory.fromEntries([
        for (var i = 0; i < 4; i++) entry(bytes: 14 * mb, id: 'img$i'),
        for (var i = 0; i < 4; i++)
          entry(
            bytes: 40 * 1024,
            id: 'doc$i',
            artifact: ArtifactFormat.structuredDocument,
          ),
      ]);

      final images = estimateSaveSize(
        entryCount: 2,
        historyBytes: history.forArtifact(ArtifactFormat.imageSequence),
      );
      final documents = estimateSaveSize(
        entryCount: 2,
        historyBytes: history.forArtifact(ArtifactFormat.structuredDocument),
        fetchesImages: false,
      );

      expect(images.lowBytes, 28 * mb);
      expect(documents.lowBytes, 80 * 1024);
      expect(documents.sizeLabel, '80 KB');
    });
  });

  group('records that are not measurements are ignored', () {
    test('failed, interrupted, discovered and partial rows do not count', () {
      final history = historyOf([
        entry(bytes: 900 * mb, status: 'failed', id: 'failed'),
        entry(bytes: 900 * mb, status: 'saving', id: 'saving'),
        entry(bytes: 900 * mb, status: 'knownRemote', id: 'known'),
        // A partial save understates a whole one: some assets never arrived.
        entry(bytes: 1 * mb, status: 'partial', id: 'partial'),
        entry(bytes: 9 * mb, id: 'good'),
      ]);

      expect(history, [9 * mb]);
      final estimate = estimateSaveSize(entryCount: 2, historyBytes: history);
      expect(estimate.lowBytes, 18 * mb);
    });

    test('a row with no package on disk does not count', () {
      final history = historyOf([
        entry(bytes: 700 * mb, contentPath: null, id: 'nopath'),
        entry(
          bytes: 700 * mb,
          offlineRemovedAt: DateTime(2026, 2, 2),
          id: 'removed',
        ),
        entry(bytes: 0, id: 'zero'),
        entry(bytes: 11 * mb, id: 'good'),
      ]);

      expect(history, [11 * mb]);
    });

    test(
      'a collection whose every row is unusable falls back, not to zero',
      () {
        final history = historyOf([
          entry(bytes: 0, id: 'zero'),
          entry(bytes: 40 * mb, status: 'failed', id: 'failed'),
        ]);

        expect(history, isEmpty);
        final estimate = estimateSaveSize(entryCount: 2, historyBytes: history);
        expect(estimate.basis, SizeEstimateBasis.typicalRange);
        expect(estimate.lowBytes, 6 * mb);
        expect(estimate.highBytes, 40 * mb);
      },
    );
  });

  group('a collection with no usable history uses the typical band', () {
    test('five entries read as a range, not a figure', () {
      final estimate = estimateSaveSize(entryCount: 5, historyBytes: const []);

      expect(estimate.basis, SizeEstimateBasis.typicalRange);
      expect(estimate.sizeLabel, '15–100 MB');
      expect(estimate.qualifier, contains('rough'));
    });

    test('one entry is 3–20 MB, not 50', () {
      final estimate = estimateSaveSize(entryCount: 1, historyBytes: const []);
      expect(estimate.lowBytes, 3 * mb);
      expect(estimate.highBytes, 20 * mb);
      expect(estimate.sizeLabel, '3–20 MB');
    });

    test('a text-only save says it cannot be estimated rather than '
        'quoting an image-sized guess', () {
      final estimate = estimateSaveSize(
        entryCount: 4,
        historyBytes: const [],
        fetchesImages: false,
      );

      expect(estimate.basis, SizeEstimateBasis.unknown);
      expect(estimate.sizeLabel, isNull);
      expect(estimate.isKnown, isFalse);
    });
  });

  group('scale', () {
    test('an ordinary save never reaches GB', () {
      for (final count in [1, 2, 5, 10, 20]) {
        final estimate = estimateSaveSize(
          entryCount: count,
          historyBytes: const [],
        );
        expect(
          estimate.highBytes,
          lessThan(gb),
          reason: '$count entries must not read as gigabytes',
        );
        expect(estimate.sizeLabel, isNot(contains('GB')), reason: '$count');
      }
    });

    test('a genuinely large request still reports gigabytes', () {
      final estimate = estimateSaveSize(
        entryCount: 400,
        historyBytes: const [],
      );
      // 400 × 3–20 MB really is 1.2–7.8 GB, and saying so is the point.
      expect(estimate.sizeLabel, '1.2–7.8 GB');
    });

    test(
      'a large count over real history reports what that history implies',
      () {
        final history = historyOf([
          for (var i = 0; i < 5; i++) entry(bytes: 30 * mb, id: 'e$i'),
        ]);
        final estimate = estimateSaveSize(
          entryCount: 200,
          historyBytes: history,
        );
        expect(estimate.lowBytes, 200 * 30 * mb);
        expect(estimate.sizeLabel, '5.9 GB');
      },
    );
  });

  group('counts that are not numbers to multiply', () {
    test('zero entries has no estimate', () {
      expect(
        estimateSaveSize(entryCount: 0, historyBytes: [10 * mb]).basis,
        SizeEstimateBasis.unknown,
      );
    });

    test('an unknown count has no estimate', () {
      final estimate = estimateSaveSize(
        entryCount: null,
        historyBytes: [10 * mb],
      );
      expect(estimate.basis, SizeEstimateBasis.unknown);
      expect(estimate.sizeLabel, isNull);
    });

    test('a negative count cannot produce a size', () {
      expect(
        estimateSaveSize(entryCount: -3, historyBytes: [10 * mb]).sizeLabel,
        isNull,
      );
    });
  });

  group('units', () {
    test('each step is 1024 of the one below', () {
      expect(formatEstimatedBytes(512), '512 B');
      expect(formatEstimatedBytes(1024), '1 KB');
      expect(formatEstimatedBytes(1536), '2 KB');
      expect(formatEstimatedBytes(mb), '1 MB');
      expect(formatEstimatedBytes(15 * mb), '15 MB');
      expect(formatEstimatedBytes(1023 * mb), '1023 MB');
      expect(formatEstimatedBytes(gb), '1.0 GB');
      expect(formatEstimatedBytes(3 * gb + 512 * mb), '3.5 GB');
      expect(formatEstimatedBytes(24 * gb), '24 GB');
    });

    test('a value that rounds up is promoted rather than printed as 1024', () {
      // 1023.99 KB and 1023.999 MB — one tick under the next unit each time.
      expect(formatEstimatedBytes(1048570), '1 MB');
      expect(formatEstimatedBytes(1073741000), '1.0 GB');
      // …and a value that does not round up stays where it is.
      expect(formatEstimatedBytes(1047552), '1023 KB');
    });

    test('a shared unit is written once', () {
      expect(formatByteRange(15 * mb, 100 * mb), '15–100 MB');
      expect(formatByteRange(36 * mb, 36 * mb), '36 MB');
      expect(formatByteRange(900 * mb, gb + 200 * mb), '900 MB – 1.2 GB');
    });
  });

  group('the typical entry', () {
    test('is the median of the sizes given', () {
      expect(typicalEntryBytes([1, 2, 3, 4, 5]), 3);
      expect(typicalEntryBytes([7]), 7);
      expect(typicalEntryBytes(const []), isNull);
    });
  });
}
