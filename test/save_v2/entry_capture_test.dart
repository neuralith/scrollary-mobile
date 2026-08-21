/// Capture retargeted to `(Entry, Location)`, writing an OfflineCopy (E2).
///
/// Runs against the **real** FileStore in a temp directory, so the atomic
/// commit, the manifest and the byte accounting are the ones that ship. What
/// is faked is only the half that would need a WebView: the page source stages
/// bytes and returns what it measured.
///
/// The four properties, in the order they matter:
///
/// 1. **a refusal costs nothing and leaves nothing** — no package, no
///    manifest, no copy row, no staging;
/// 2. **a success is self-describing** — the manifest reads back off disk, and
///    the copy carries its provenance as values;
/// 3. **a replacement is atomic and singular** — the predecessor is
///    deactivated in the same transaction the new copy becomes active in (I13),
///    and a readable copy is never traded for a failed one;
/// 4. **removing a copy is not removing an Entry** — the bytes go, the library
///    row and the reading state stay.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/capture_harness.dart';

void main() {
  late CaptureHarness h;

  setUp(() => h = CaptureHarness());
  tearDown(() => h.close());

  group('the restricted-site policy, asked before anything is read', () {
    test('a refused address produces no copy and no package', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.images();
      final result = await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationUrl: restrictedUrl(),
            captureMode: null,
          );

      expect(result.status, EntryCaptureStatus.refused);
      expect(result.stopReason, StopReason.captureRestrictedForSite);
      expect(result.message, kCaptureRestrictedMessage);
      expect(
        source.requested,
        isEmpty,
        reason: 'nothing is probed, measured or staged above this check',
      );
      expect(await h.repos.offline.allCopies(), isEmpty);
      expect(h.committedPaths(), isEmpty);
      expect(h.stagingLeftovers(), isEmpty);
    });

    test(
      'a landed refusal discards the staged tree before the commit',
      () async {
        final seeded = await h.repos.seedLibrary();
        // The source navigated, landed on a restricted service and said so —
        // the boundary only the thing that navigates can ask.
        final source = FakePageCaptureSource.refusing();
        final result = await h
            .captureWith(source)
            .capture(
              entryId: seeded.entry.id,
              locationId: seeded.location.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );

        expect(result.status, EntryCaptureStatus.refused);
        expect(await h.repos.offline.allCopies(), isEmpty);
        expect(h.committedPaths(), isEmpty);
        expect(h.stagingLeftovers(), isEmpty);
      },
    );

    test('the pre-commit check judges the manifest\'s own address', () async {
      final seeded = await h.repos.seedLibrary();
      // A source that stages successfully but landed somewhere restricted
      // without noticing. The pipeline asks about what the package claims to
      // be a copy of, not about the address the task named.
      final source = FakePageCaptureSource.images(landedUrl: restrictedUrl());
      final result = await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );

      expect(result.status, EntryCaptureStatus.refused);
      expect(
        h.committedPaths(),
        isEmpty,
        reason: 'no file, no manifest and no row survives a refusal',
      );
      expect(await h.repos.offline.allCopies(), isEmpty);
      expect(h.stagingLeftovers(), isEmpty);
    });
  });

  group('a successful capture', () {
    test('commits a readable package and records full provenance', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.images(pageCount: 3);
      final result = await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: CaptureMode.imageSequence,
          );

      expect(result.status, EntryCaptureStatus.captured);
      expect(source.requested, [seeded.location.url]);
      expect(source.modes, [CaptureMode.imageSequence]);

      // The package is on disk and describes itself.
      final relative = result.contentPath!;
      expect(
        relative,
        FileStore.entryRelativePath(seeded.collection.id, seeded.entry.id),
      );
      expect(
        relative.startsWith('/'),
        isFalse,
        reason: 'relative paths only — the iOS container path moves',
      );
      final onDisk = await h.fileStore.readManifest(relative);
      expect(onDisk, isNotNull);
      expect(onDisk!.schemaVersion, EntryManifest.currentSchemaVersion);
      expect(onDisk.artifact, ArtifactFormat.imageSequence);
      expect(onDisk.entryId, seeded.entry.id);
      expect(onDisk.collectionId, seeded.collection.id);
      expect(onDisk.sourceUrl, seeded.location.url);
      expect(onDisk.storedAssetCount, 3);
      expect(onDisk.storedAssets, hasLength(3));
      expect(onDisk.status, SaveStatus.complete);
      expect(
        onDisk.sourceMarker,
        'Part 101',
        reason: 'what the Source printed, kept verbatim as evidence',
      );
      expect(onDisk.entryNumber, 101);

      // The copy names the bytes, with provenance as values.
      final copy = (await h.repos.offline.activeCopyOf(seeded.entry.id))!;
      expect(copy.id, result.copy!.id);
      expect(copy.entryId, seeded.entry.id);
      expect(copy.locationUrl, seeded.location.url);
      expect(copy.sourceName, 'Serial Alpha');
      expect(copy.sourceHost, 'reading.example.com');
      expect(copy.sourceLanguage, 'en');
      expect(
        copy.capturedAt.toUtc(),
        onDisk.savedAt,
        reason:
            'the capture time is the manifest\'s own; drift reads a stored '
            'timestamp back in local time, so the comparison is made in UTC',
      );
      expect(copy.artifactFormat, ArtifactFormat.imageSequence.name);
      expect(copy.contentPath, relative);
      expect(copy.byteSize, greaterThan(0));
      expect(copy.byteSize, result.byteSize);
      expect(copy.active, isTrue);

      // The byte size is the package's, measured off disk.
      expect(copy.byteSize, await h.fileStore.entryByteSize(relative));
    });

    test('a structured document keeps its text beside its manifest', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h
          .captureWith(FakePageCaptureSource.document())
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: CaptureMode.textOnly,
          );

      expect(result.status, EntryCaptureStatus.captured);
      final manifest = await h.fileStore.readManifest(result.contentPath!);
      expect(manifest!.artifact, ArtifactFormat.structuredDocument);
      expect(manifest.document, isNotNull);
      expect(manifest.document!.blockCount, 3);

      final document = await h.fileStore.readDocument(result.contentPath!);
      expect(document, isNotNull);
      expect(document!.blockCount, 3);
      expect(
        (await h.repos.offline.activeCopyOf(seeded.entry.id))!.artifactFormat,
        ArtifactFormat.structuredDocument.name,
      );
    });

    test('a standalone Entry stores outside any collection folder', () async {
      final root = await h.repos.folders.ensureRoot();
      final (entry, _) = await h.repos.entries.createStandalone(
        folderId: root.id,
        title: 'Loose page',
      );
      final result = await h
          .captureWith(FakePageCaptureSource.images(pageCount: 1))
          .capture(
            entryId: entry!.id,
            locationUrl: 'https://reading.example.com/loose',
            captureMode: null,
          );

      expect(result.status, EntryCaptureStatus.captured);
      expect(
        result.contentPath,
        FileStore.entryRelativePath(null, entry.id),
        reason: 'a standalone Entry is never wrapped in a collection of one',
      );
      final copy = (await h.repos.offline.activeCopyOf(entry.id))!;
      expect(copy.sourceName, isEmpty);
      expect(
        copy.sourceHost,
        'reading.example.com',
        reason: 'no Source to ask, so the address answers',
      );
    });

    test('a null mode is passed through as "decide from the page"', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.images(pageCount: 1);
      await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      expect(source.modes, [null]);
    });
  });

  group('replacing a copy', () {
    test('deactivates its predecessor, leaving exactly one active', () async {
      final seeded = await h.repos.seedLibrary();
      final first = await h
          .captureWith(FakePageCaptureSource.images(pageCount: 2))
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      final second = await h
          .captureWith(FakePageCaptureSource.document())
          .capture(
            entryId: seeded.entry.id,
            locationId: seeded.location.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );

      expect(first.status, EntryCaptureStatus.captured);
      expect(second.status, EntryCaptureStatus.captured);

      final all = await h.repos.offline.allCopies();
      expect(all, hasLength(2));
      expect(all.where((c) => c.active), hasLength(1), reason: 'I13');
      final active = (await h.repos.offline.activeCopyOf(seeded.entry.id))!;
      expect(active.id, second.copy!.id);
      expect(active.artifactFormat, ArtifactFormat.structuredDocument.name);

      // One package, replaced in place through the atomic path — no
      // `.previous` left behind.
      expect(h.committedPaths(), hasLength(1));
      expect(
        Directory(
          '${h.fileStore.resolve(first.contentPath!)}.previous',
        ).existsSync(),
        isFalse,
      );
      final manifest = await h.fileStore.readManifest(second.contentPath!);
      expect(manifest!.artifact, ArtifactFormat.structuredDocument);
    });

    test(
      'a failed re-capture leaves the readable copy exactly as it was',
      () async {
        final seeded = await h.repos.seedLibrary();
        final first = await h
            .captureWith(FakePageCaptureSource.images(pageCount: 2))
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );

        final failed = await h
            .captureWith(
              FakePageCaptureSource.failing('the surface never drew'),
            )
            .capture(
              entryId: seeded.entry.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );

        expect(failed.status, EntryCaptureStatus.failed);
        expect(failed.error, 'the surface never drew');
        expect(await h.repos.offline.allCopies(), hasLength(1));
        final active = (await h.repos.offline.activeCopyOf(seeded.entry.id))!;
        expect(active.id, first.copy!.id);
        expect(active.contentPath, first.contentPath);
        expect(
          (await h.fileStore.readManifest(
            first.contentPath!,
          ))!.storedAssetCount,
          2,
        );
        expect(h.stagingLeftovers(), isEmpty);
      },
    );

    test('a partial capture is recorded as partial, not as complete', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h
          .captureWith(
            FakePageCaptureSource.images(
              pageCount: 2,
              status: SaveStatus.partial,
            ),
          )
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );

      expect(result.status, EntryCaptureStatus.captured);
      expect(
        (await h.fileStore.readManifest(result.contentPath!))!.status,
        SaveStatus.partial,
      );
    });
  });

  group('a capture that cannot start', () {
    test(
      'an Entry the library does not have is refused, not invented',
      () async {
        final source = FakePageCaptureSource.images();
        final result = await h
            .captureWith(source)
            .capture(
              entryId: 'no-such-entry',
              locationUrl: 'https://reading.example.com/whatever',
              captureMode: null,
            );
        expect(result.status, EntryCaptureStatus.failed);
        expect(source.requested, isEmpty);
        expect(h.stagingLeftovers(), isEmpty);
      },
    );

    test('a cooperative stop before staging ends it named', () async {
      final seeded = await h.repos.seedLibrary();
      final source = FakePageCaptureSource.images();
      final result = await h
          .captureWith(source)
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
            shouldContinue: () => false,
          );
      expect(result.status, EntryCaptureStatus.failed);
      expect(result.stopReason, StopReason.cancelledByUser);
      expect(source.requested, isEmpty);
      expect(await h.repos.offline.allCopies(), isEmpty);
    });
  });

  group('removing a copy is never removing an Entry', () {
    test(
      'the bytes go; the Entry, its Location and its reading state stay',
      () async {
        final seeded = await h.repos.seedLibrary();
        final result = await h
            .captureWith(FakePageCaptureSource.images(pageCount: 2))
            .capture(
              entryId: seeded.entry.id,
              locationId: seeded.location.id,
              locationUrl: seeded.location.url,
              captureMode: null,
            );
        await h.repos.reading.markRead(seeded.entry.id);

        final removed = await removeOfflineCopies(
          entryId: seeded.entry.id,
          offlineCopies: h.repos.offline,
          fileStore: h.fileStore,
        );

        expect(removed, 1);
        expect(await h.repos.offline.allCopies(), isEmpty);
        expect(h.fileStore.entryExists(result.contentPath!), isFalse);
        expect(h.committedPaths(), isEmpty);

        // Everything the user owns is untouched.
        expect(await h.repos.entries.byId(seeded.entry.id), isNotNull);
        expect(
          await h.repos.entries.locationById(seeded.location.id),
          isNotNull,
        );
        final state = await h.repos.reading.stateOf(seeded.entry.id);
        expect(state.status, ReadStatus.completed);
        expect(state.completedAt, isNotNull);
      },
    );

    test('the Entry can be captured again afterwards', () async {
      final seeded = await h.repos.seedLibrary();
      await h
          .captureWith(FakePageCaptureSource.images(pageCount: 1))
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      await removeOfflineCopies(
        entryId: seeded.entry.id,
        offlineCopies: h.repos.offline,
        fileStore: h.fileStore,
      );

      final again = await h
          .captureWith(FakePageCaptureSource.images(pageCount: 2))
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: null,
          );
      expect(again.status, EntryCaptureStatus.captured);
      expect(await h.repos.offline.allCopies(), hasLength(1));
      expect(
        (await h.fileStore.readManifest(again.contentPath!))!.storedAssetCount,
        2,
      );
    });
  });

  group('provenance resolution', () {
    test('reads the Source through the Location, and the name through the '
        'Collection', () async {
      final seeded = await h.repos.seedLibrary();
      final provenance = await resolveCaptureProvenance(
        entries: h.repos.entries,
        collections: h.repos.collections,
        locationUrl: seeded.location.url,
        locationId: seeded.location.id,
      );
      expect(provenance.sourceName, 'Serial Alpha');
      expect(provenance.sourceHost, 'reading.example.com');
      expect(provenance.sourceLanguage, 'en');
      expect(provenance.sourceLabel, 'Part 101');
      expect(provenance.sourceNumber, 101);
    });

    test('falls back to the address when there is no Location row', () async {
      final provenance = await resolveCaptureProvenance(
        entries: h.repos.entries,
        collections: h.repos.collections,
        locationUrl: 'https://Reading.Example.com/loose',
      );
      expect(provenance.sourceHost, 'reading.example.com');
      expect(provenance.sourceName, isEmpty);
      expect(provenance.sourceLanguage, isEmpty);
    });
  });
}
