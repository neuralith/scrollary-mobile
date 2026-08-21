/// The reader opens through the OfflineCopy (roadmap E5).
///
/// What is proven here:
///
/// 1. **the active copy decides.** One copy per Entry per device (I13); a
///    replacement is what the reader opens, and the manifest — never a file
///    extension or an asset count — says what it holds;
/// 2. **an unreadable package is said plainly.** No copy, missing files, an
///    unparseable manifest and a format from a newer build are four different
///    answers, and none of them demotes the Entry;
/// 3. **position restore is unchanged.** The anchor is on the copy, and the
///    image reader can compute its offset before a single image decodes;
/// 4. **the write-back goes to two owners.** The anchor to the copy (device,
///    never synced); the reading state through its own repository, under the
///    completion policy.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/reading/reading_position.dart'
    show DocumentLayout, ReadingPosition, kDefaultCompletionPolicy;
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/capture_harness.dart';

void main() {
  late CaptureHarness h;

  setUp(() => h = CaptureHarness());
  tearDown(() => h.close());

  Future<({String entryId, String contentPath})> captureImages({
    int pages = 3,
    bool dimensionsVerified = true,
  }) async {
    final seeded = await h.repos.seedLibrary();
    final result = await h
        .captureWith(
          FakePageCaptureSource.images(
            pageCount: pages,
            dimensionsVerified: dimensionsVerified,
          ),
        )
        .capture(
          entryId: seeded.entry.id,
          locationId: seeded.location.id,
          locationUrl: seeded.location.url,
          captureMode: null,
        );
    return (entryId: seeded.entry.id, contentPath: result.contentPath!);
  }

  group('resolution', () {
    test('an image sequence resolves to its pages, in reading order', () async {
      final captured = await captureImages();
      final read = await h.read(captured.entryId);

      expect(read, isA<OfflineImageRead>());
      final image = read as OfflineImageRead;
      expect(image.manifest.artifact, ArtifactFormat.imageSequence);
      expect(image.pages, hasLength(3));
      expect(image.pages.every((page) => page.exists), isTrue);
      expect(
        image.pages.map((page) => p.basename(page.file.path)),
        ['001.png', '002.png', '003.png'],
        reason: 'manifest order is DOM order, which is reading order',
      );
      expect(image.entryDir.path, h.fileStore.resolve(captured.contentPath));
      expect(image.copy.contentPath, captured.contentPath);
    });

    test('an unverified dimension is "not measured", never a guess', () async {
      final captured = await captureImages(dimensionsVerified: false);
      final image = await h.read(captured.entryId) as OfflineImageRead;
      for (final page in image.pages) {
        expect(page.width, isNull);
        expect(page.height, isNull);
      }
      // The geometry still gives every panel a place to stand.
      expect(image.geometryFor(400).total, greaterThan(0));
    });

    test('a structured document resolves to its text', () async {
      final seeded = await h.repos.seedLibrary();
      await h
          .captureWith(FakePageCaptureSource.document())
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );

      final read = await h.read(seeded.entry.id);
      expect(read, isA<OfflineDocumentRead>());
      final document = read as OfflineDocumentRead;
      expect(document.manifest.artifact, ArtifactFormat.structuredDocument);
      expect(document.document.blockCount, 3);
      expect(document.document.blocks[1].text, startsWith('The first'));
      expect(document.entryDir.existsSync(), isTrue);
    });

    test('the active copy is what opens, after a replacement', () async {
      final seeded = await h.repos.seedLibrary();
      await h
          .captureWith(FakePageCaptureSource.images(pageCount: 2))
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      expect(await h.read(seeded.entry.id), isA<OfflineImageRead>());

      await h
          .captureWith(FakePageCaptureSource.document())
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );

      final read = await h.read(seeded.entry.id);
      expect(
        read,
        isA<OfflineDocumentRead>(),
        reason: 'the reader follows the active copy, not the first one',
      );
      expect(
        (read as OfflineDocumentRead).copy.id,
        (await h.repos.offline.activeCopyOf(seeded.entry.id))!.id,
      );
    });
  });

  group('an unreadable package is said plainly', () {
    test('no copy on this device', () async {
      final seeded = await h.repos.seedLibrary();
      final read = await h.read(seeded.entry.id);
      expect(read, isA<OfflineReadUnavailable>());
      expect(
        (read as OfflineReadUnavailable).refusal,
        OfflineReadRefusal.noCopy,
      );
      expect(read.copy, isNull);
    });

    test('the copy row survives its files, and names what is gone', () async {
      final captured = await captureImages(pages: 1);
      // The bytes go without the row: what a foreign wipe or a failed
      // restore looks like.
      await h.fileStore.deleteEntryContent(captured.contentPath);

      final read = await h.read(captured.entryId) as OfflineReadUnavailable;
      expect(read.refusal, OfflineReadRefusal.filesMissing);
      expect(
        read.copy,
        isNotNull,
        reason: 'the row is what lets a cleanup surface name what it holds',
      );
      expect(read.copy!.contentPath, captured.contentPath);
    });

    test('a package with no manifest', () async {
      final captured = await captureImages(pages: 1);
      File(
        p.join(
          h.fileStore.resolve(captured.contentPath),
          FileStore.manifestFileName,
        ),
      ).deleteSync();

      final read = await h.read(captured.entryId) as OfflineReadUnavailable;
      expect(read.refusal, OfflineReadRefusal.manifestUnreadable);
    });

    test(
      'a format a newer build wrote resolves to unknown and says so',
      () async {
        final captured = await captureImages(pages: 1);
        final manifestFile = File(
          p.join(
            h.fileStore.resolve(captured.contentPath),
            FileStore.manifestFileName,
          ),
        );
        manifestFile.writeAsStringSync(
          manifestFile.readAsStringSync().replaceFirst(
            '"artifact": "${ArtifactFormat.imageSequence.name}"',
            '"artifact": "somethingThisBuildHasNeverHeardOf"',
          ),
        );

        // The manifest itself is the authority, and it is honest about it.
        final manifest = await h.fileStore.readManifest(captured.contentPath);
        expect(manifest!.artifact, ArtifactFormat.unknown);

        final read = await h.read(captured.entryId) as OfflineReadUnavailable;
        expect(
          read.refusal,
          OfflineReadRefusal.unknownArtifact,
          reason: 'never misread as one of the formats this version knows',
        );
        expect(
          read.copy!.artifactFormat,
          ArtifactFormat.imageSequence.name,
          reason:
              'the copy row keeps its cached label; the files are what decide',
        );
      },
    );

    test('a document whose text will not parse', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h
          .captureWith(FakePageCaptureSource.document())
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      File(
        p.join(
          h.fileStore.resolve(result.contentPath!),
          FileStore.documentFileName,
        ),
      ).writeAsStringSync('{ not json');

      final read = await h.read(seeded.entry.id) as OfflineReadUnavailable;
      expect(read.refusal, OfflineReadRefusal.documentUnreadable);
    });
  });

  group('position restore is unchanged', () {
    test('the image reader knows its offset before anything decodes', () async {
      final captured = await captureImages();
      await h.repos.offline.saveAnchor(
        captured.entryId,
        anchorIndex: 2,
        anchorOffset: 0.5,
      );

      final image = await h.read(captured.entryId) as OfflineImageRead;
      expect(image.restored.anchorIndex, 2);
      expect(image.restored.offsetInAnchor, 0.5);

      // Panels are 40x60, so each is 1.5 viewport widths tall.
      final geometry = image.geometryFor(400);
      expect(geometry.total, 1800);
      expect(geometry.offsetForPosition(image.restored), 1500);
      // …and the inverse lands back on the same anchor.
      final back = geometry.positionForOffset(1500, viewportHeight: 600);
      expect(back.anchorIndex, 2);
      expect(back.offsetInAnchor, closeTo(0.5, 0.001));
    });

    test('a copy with no anchor opens at the start', () async {
      final captured = await captureImages();
      final image = await h.read(captured.entryId) as OfflineImageRead;
      expect(image.restored.isAtStart, isTrue);
    });

    test(
      'the document reader restores TO its block, not at an offset',
      () async {
        final seeded = await h.repos.seedLibrary();
        await h
            .captureWith(FakePageCaptureSource.document())
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );
        await h.repos.offline.saveAnchor(
          seeded.entry.id,
          anchorIndex: 2,
          anchorOffset: 0.25,
        );

        final document = await h.read(seeded.entry.id) as OfflineDocumentRead;
        expect(document.restored.anchorIndex, 2);

        // The offsets only exist once the blocks have been laid out — which is
        // exactly why the anchor is a block index and not a scroll position.
        final layout = DocumentLayout(
          offsets: const [0, 60, 200],
          heights: const [60, 140, 100],
        );
        expect(layout.offsetForPosition(document.restored), 225);
      },
    );

    test(
      'the anchor is on the copy, and a replacement gets a fresh one',
      () async {
        final seeded = await h.repos.seedLibrary();
        await h
            .captureWith(FakePageCaptureSource.images(pageCount: 2))
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );
        await h.repos.offline.saveAnchor(
          seeded.entry.id,
          anchorIndex: 1,
          anchorOffset: 0.75,
        );

        await h
            .captureWith(FakePageCaptureSource.document())
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );

        final read = await h.read(seeded.entry.id) as OfflineDocumentRead;
        expect(
          read.restored.isAtStart,
          isTrue,
          reason:
              'an anchor recorded against one artifact is meaningless against '
              'another, and it never follows the bytes it did not index',
        );
        final copies = await h.repos.offline.allCopies();
        final previous = copies.firstWhere((c) => !c.active);
        expect(previous.anchorIndex, 1, reason: 'the old copy keeps its own');
      },
    );
  });

  group('the write-back, and its two owners', () {
    test('opening records access and never completion', () async {
      final captured = await captureImages();
      final session = h.sessionFor(captured.entryId);

      expect(
        (await session.state()).status,
        ReadStatus.unread,
        reason: 'reading state exists for every Entry, stored or not (I10)',
      );
      final state = await session.recordOpen();
      expect(state.status, ReadStatus.reading);
      expect(state.firstOpenedAt, isNotNull);
      expect(state.completedAt, isNull);
    });

    test(
      'progress writes the anchor to the copy and the state to its own row',
      () async {
        final captured = await captureImages();
        final session = h.sessionFor(captured.entryId);

        final state = await session.saveProgress(
          const ReadingPosition(
            fraction: 0.4,
            anchorIndex: 1,
            offsetInAnchor: 0.3,
          ),
        );

        final copy = (await h.repos.offline.activeCopyOf(captured.entryId))!;
        expect(copy.anchorIndex, 1);
        expect(copy.anchorOffset, closeTo(0.3, 0.0001));
        expect(state.status, ReadStatus.reading);
        expect(state.completedAt, isNull);
      },
    );

    test('the completion policy is what finishes an Entry, and only in this '
        'reader', () async {
      final captured = await captureImages();
      final session = h.sessionFor(captured.entryId);
      const policy = kDefaultCompletionPolicy;

      // Past the threshold, but the reader has not held there for the dwell.
      expect(policy.reachedEnd(0.98), isTrue);
      var state = await session.saveProgress(
        const ReadingPosition(fraction: 0.98, anchorIndex: 2),
      );
      expect(
        state.status,
        ReadStatus.reading,
        reason: 'a fling to the bottom passes the threshold, never the dwell',
      );

      // The reader dwelt; it says so.
      state = await session.saveProgress(
        const ReadingPosition(
          fraction: 0.99,
          anchorIndex: 2,
          offsetInAnchor: 0.9,
        ),
        reachedEnd: true,
      );
      expect(state.status, ReadStatus.completed);
      expect(state.completedAt, isNotNull);

      // …and the anchor kept following the scroll, so resuming a finished
      // Entry still lands where the reader actually was.
      final copy = (await h.repos.offline.activeCopyOf(captured.entryId))!;
      expect(copy.anchorIndex, 2);
      expect(copy.anchorOffset, closeTo(0.9, 0.0001));
    });

    test('a completed Entry is 100% read, whatever the scroll says', () async {
      final captured = await captureImages();
      final session = h.sessionFor(captured.entryId);
      await session.markRead();

      final state = await session.state();
      expect(
        offlineReadProgress(
          state: state,
          live: const ReadingPosition(fraction: 0.1),
        ),
        1,
        reason: 'finished is a statement about the Entry, not about the scroll',
      );
    });

    test('marking unread lowers progress and keeps the anchor', () async {
      final captured = await captureImages();
      final session = h.sessionFor(captured.entryId);
      await session.saveProgress(
        const ReadingPosition(
          fraction: 0.5,
          anchorIndex: 1,
          offsetInAnchor: 0.2,
        ),
        reachedEnd: true,
      );

      final state = await session.markUnread();
      expect(state.status, ReadStatus.unread);
      expect(state.completedAt, isNull);
      expect(
        state.firstOpenedAt,
        isNotNull,
        reason: 'the open history stays — it happened',
      );

      final copy = (await h.repos.offline.activeCopyOf(captured.entryId))!;
      expect(
        copy.anchorIndex,
        1,
        reason: 'resuming still lands where they got to',
      );
      expect(
        offlineReadProgress(
          state: state,
          live: const ReadingPosition(fraction: 0.5),
        ),
        0.5,
      );
    });

    test(
      'reading writes no Measurement: this is not a Source rendering',
      () async {
        final seeded = await h.repos.seedLibrary();
        await h
            .captureWith(FakePageCaptureSource.images(pageCount: 2))
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );
        final session = h.sessionFor(seeded.entry.id);
        await session.saveProgress(
          const ReadingPosition(fraction: 0.6, anchorIndex: 1),
        );

        expect(
          await h.repos.measurements.allOf(seeded.entry.id),
          isEmpty,
          reason:
              'a measurement names the Source it was measured against (I12); an '
              'offline copy is not one',
        );
      },
    );
  });
}
