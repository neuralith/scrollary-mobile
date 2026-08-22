/// What this device is holding, and where the rows and the disk disagree.
///
/// This is the rebuilt cleanup surface (roadmap §10, last row: *recovery
/// rebuilt against OfflineCopy*). V1 answered both questions from one place,
/// because its rows **were** the library: the storage screen summed a column,
/// and startup rebuilt a row from any package it found on disk with nothing
/// pointing at it.
///
/// Neither is right for V2, and for opposite reasons:
///
///  * `offline_copies` is device state beside a library that synchronises, so
///    the rows and the disk can genuinely diverge — a package survives a
///    database that was reset, and a row survives files a restore did not
///    carry. A figure read from one source alone either hides bytes it could
///    free or counts bytes that are not there.
///  * A package on this device is **not evidence for an Entry** (V2-D22,
///    I14). Rebuilding one at boot would resurrect entries another device
///    deleted. So the disagreement is reported, and freeing it is a tap.
///
/// Three properties, in the order they matter:
///
/// 1. **Held is what both sources agree on**, and it is the only thing counted
///    as this app's usage.
/// 2. **An orphan is space, never a library row.** Discarding one takes the
///    files and touches no Entry.
/// 3. **A missing package is a state, not a demotion.** Forgetting the record
///    leaves the Entry, its reading state and its Locations exactly as they
///    were.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'data/support/repo_harness.dart';

void main() {
  late RepoHarness repos;
  late Directory root;
  late FileStore fileStore;
  late CleanupService cleanup;
  late String collectionId;

  setUp(() async {
    repos = RepoHarness();
    root = Directory.systemTemp.createTempSync('scrollary_survey');
    fileStore = FileStore(root);
    Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
    Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
    cleanup = CleanupService(
      offlineCopies: repos.offline,
      entries: repos.entries,
      collections: repos.collections,
      reading: repos.reading,
      fileStore: fileStore,
    );
    collectionId = (await repos.seedLibrary()).collection.id;
  });

  tearDown(() async {
    await repos.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A committed package on disk. Returns its path relative to the store.
  Future<String> commitPackage(String entryId) async {
    final staging = await fileStore.beginEntry(
      collectionId: collectionId,
      entryId: entryId,
    );
    await staging.assetFile('001.png').writeAsBytes(List.filled(2048, 7));
    return fileStore.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: entryId,
        collectionId: collectionId,
        sourceUrl: 'https://reading.example.com/serial-alpha/part-$entryId',
        title: 'Part $entryId',
        savedAt: DateTime.utc(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 1,
        storedAssetCount: 1,
        assets: const [],
      ),
    );
  }

  /// An Entry with a package on disk and the copy row that names it.
  Future<({String entryId, String path})> seedHeld({
    required double ordinal,
    required String title,
  }) async {
    final (entry, violation) = await repos.entries.createInCollection(
      collectionId: collectionId,
      ordinal: ordinal,
      title: title,
    );
    expect(violation, isNull);
    final path = await commitPackage(entry!.id);
    await repos.offline.recordCopy(
      entryId: entry.id,
      locationUrl: 'https://reading.example.com/serial-alpha/part-$ordinal',
      artifactFormat: 'imageSequence',
      contentPath: path,
      byteSize: await fileStore.entryByteSize(path),
    );
    return (entryId: entry.id, path: path);
  }

  group('held: what both sources agree on', () {
    test('a copy whose package is there is held, and counted', () async {
      final held = await seedHeld(ordinal: 201, title: 'Part 201');

      final survey = await cleanup.survey();

      expect(survey.held, hasLength(1));
      expect(survey.held.single.entryId, held.entryId);
      expect(survey.held.single.title, 'Part 201');
      expect(survey.held.single.collectionId, collectionId);
      expect(
        survey.held.single.bytes,
        greaterThan(0),
        reason: 'measured from disk, not taken from the row',
      );
      expect(survey.heldBytes, survey.held.single.bytes);
      expect(survey.missing, isEmpty);
      expect(survey.orphans, isEmpty);
    });

    test('held copies group by collection, largest first', () async {
      await seedHeld(ordinal: 201, title: 'Part 201');
      await seedHeld(ordinal: 202, title: 'Part 202');

      final survey = await cleanup.survey();

      expect(survey.byCollection, hasLength(1));
      expect(survey.byCollection.single.id, collectionId);
      expect(survey.byCollection.single.entryCount, 2);
      expect(survey.byCollection.single.bytes, survey.heldBytes);
    });

    test('finished is read to the end, and nothing else', () async {
      final read = await seedHeld(ordinal: 201, title: 'Part 201');
      await seedHeld(ordinal: 202, title: 'Part 202');
      await repos.reading.markRead(read.entryId);

      final survey = await cleanup.survey();

      expect(survey.finished.map((c) => c.entryId), [read.entryId]);
      expect(survey.finishedBytes, greaterThan(0));
      expect(
        survey.finishedBytes,
        lessThan(survey.heldBytes),
        reason: 'the unread copy is not on offer',
      );
    });

    test('freeing a held copy takes the package and the row', () async {
      final held = await seedHeld(ordinal: 201, title: 'Part 201');

      final freed = await cleanup.removeCopiesOf([held.entryId]);

      expect(freed, 1);
      expect(fileStore.entryExists(held.path), isFalse);
      expect(await repos.offline.activeCopyOf(held.entryId), isNull);
      // The Entry is in the library because somebody wants to read it.
      expect(await repos.entries.byId(held.entryId), isNotNull);
      expect(await cleanup.survey(), _surveyThatIsEmpty);
    });
  });

  group('orphans: a package no row refers to', () {
    test('is reported as space, and never as an entry', () async {
      // Committed with no copy row behind it: what a reset database, or a
      // restore that carried the files and not the rows, leaves.
      final path = await commitPackage('unclaimed-entry');

      final survey = await cleanup.survey();

      expect(survey.held, isEmpty);
      expect(survey.orphans, hasLength(1));
      expect(survey.orphans.single.relativePath, path);
      expect(survey.orphans.single.bytes, greaterThan(0));
      expect(survey.orphanBytes, survey.orphans.single.bytes);
      expect(
        survey.heldBytes,
        0,
        reason: 'an orphan is not this app holding a copy of anything',
      );
    });

    test('discarding one takes the files and no rows', () async {
      final held = await seedHeld(ordinal: 201, title: 'Part 201');
      await commitPackage('unclaimed-entry');
      final before = await cleanup.survey();

      final removed = await cleanup.discardOrphans(before.orphans);

      expect(removed, 1);
      final after = await cleanup.survey();
      expect(after.orphans, isEmpty);
      // Everything the library knew, it still knows.
      expect(after.held.single.entryId, held.entryId);
      expect(fileStore.entryExists(held.path), isTrue);
    });

    test('a package the rows do claim is never an orphan', () async {
      await seedHeld(ordinal: 201, title: 'Part 201');

      expect((await cleanup.survey()).orphans, isEmpty);
    });
  });

  group('missing: a row whose package is gone', () {
    test('is a state, not a demotion', () async {
      final held = await seedHeld(ordinal: 201, title: 'Part 201');
      await fileStore.deleteEntryContent(held.path);

      final survey = await cleanup.survey();

      expect(survey.held, isEmpty);
      expect(survey.missing, hasLength(1));
      expect(survey.missing.single.entryId, held.entryId);
      expect(
        survey.heldBytes,
        0,
        reason: 'the figure stops counting bytes that do not exist',
      );
      expect(survey.orphans, isEmpty);
    });

    test('forgetting the record leaves the Entry and its reading', () async {
      final held = await seedHeld(ordinal: 201, title: 'Part 201');
      await repos.reading.markRead(held.entryId);
      await fileStore.deleteEntryContent(held.path);
      final before = await cleanup.survey();

      final forgotten = await cleanup.forgetMissing(before.missing);

      expect(forgotten, 1);
      expect(await repos.offline.activeCopyOf(held.entryId), isNull);
      expect(await repos.entries.byId(held.entryId), isNotNull);
      expect(
        (await repos.reading.stateOf(held.entryId)).status,
        ReadStatus.completed,
      );
      expect((await cleanup.survey()).missing, isEmpty);
    });
  });
}

/// A survey holding nothing, in any of its three senses.
final Matcher _surveyThatIsEmpty = predicate<StorageSurvey>(
  (s) => s.held.isEmpty && s.missing.isEmpty && s.orphans.isEmpty,
  'a survey with no held copies, no missing packages and no orphans',
);
