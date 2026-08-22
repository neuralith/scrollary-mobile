/// H2 — end to end: a client action reaches the backend, and the backend
/// reaches a second phone.
///
/// Real client, real HTTP, real Go service, real PostgreSQL. The first half
/// asserts against the wire rather than against a second client, because "the
/// server holds what the contract says" and "another client agrees with us"
/// are different claims and only the first one catches a shared misreading.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late RawApi raw;

  // What client A builds, remembered for the second half.
  late String folderId;
  late String collectionId;
  late String sourceId;
  late String entryId;
  late String locationId;
  late String partUrl;
  late RecognitionKeys keys;

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('h2');
    a = E2EClient.start('A', library);
    raw = RawApi(library: library);
    partUrl = fixture.partUrl('alpha', 5);
    keys = RecognitionKeys.of(partUrl);
  });

  tearDownAll(() async {
    raw.close();
    await a.stop();
    fixture.expectNothingFetched('H2 client action to phone');
    await fixture.stop();
  });

  test('a local library is built, then drained to the service', () async {
    final root = await a.folders.ensureRoot();
    final (folder, folderViolation) = await a.folders.create(
      'Reading',
      parentId: root.id,
    );
    expect(folderViolation, isNull);
    folderId = folder!.id;

    final (collection, collectionViolation) = await a.collections.create(
      name: 'Fixture multi-source work',
      folderId: folderId,
      orderingBasis: OrderingBasis.explicitNumericIndex,
      detectedTitle: 'Fixture multi-source work',
    );
    expect(collectionViolation, isNull);
    collectionId = collection!.id;

    expect(keys.pathKey, isNotNull, reason: 'the fixture address has a path');
    final (source, sourceViolation) = await a.collections.addSource(
      collectionId: collectionId,
      host: keys.host,
      pathKey: keys.pathKey!,
      language: 'en',
    );
    expect(sourceViolation, isNull);
    sourceId = source!.id;

    final (entry, entryViolation) = await a.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 5,
      title: 'Part 5',
    );
    expect(entryViolation, isNull);
    entryId = entry!.id;

    final (location, locationViolation) = await a.entries.addLocation(
      entryId: entryId,
      sourceId: sourceId,
      url: partUrl,
      urlKey: keys.urlKey,
      sourceLabel: 'Part 5',
      sourceNumber: 5,
      discoveryBasis: 'listing',
    );
    expect(locationViolation, isNull);
    locationId = location!.id;

    final (reading, readingViolation) = await a.readingStates
        .recordSourceAccess(entryId);
    expect(readingViolation, isNull);
    expect(reading!.status, ReadStatus.reading);

    final (_, measurementViolation) = await a.measurements.put(
      entryId: entryId,
      sourceId: sourceId,
      fraction: 0.25,
    );
    expect(measurementViolation, isNull);

    expect(
      await a.outbox.pendingCount(),
      7,
      reason: 'one intent per mutation, recorded in its own transaction',
    );

    final outcome = await a.sync();
    expect(outcome.pushed!.acked, 7);
    expect(outcome.pushed!.rejected, 0);
    expect(
      await a.outbox.pendingCount(),
      0,
      reason: 'an acknowledged intent leaves the outbox',
    );
  });

  test(
    'the service holds the contract rows, in snake_case, revisioned',
    () async {
      final folders = await raw.entities('folder');
      final serverRoot = folders.values.firstWhere((f) => f['kind'] == 'root');
      final serverFolder = folders[folderId];
      expect(
        serverFolder,
        isNotNull,
        reason: 'the user Folder reached the wire',
      );
      expect(serverFolder!['parent_id'], serverRoot['id']);
      expect(serverFolder['kind'], 'user');
      expect(serverFolder['name'], 'Reading');
      expect(serverFolder['sort_key'], 0);
      expect((serverFolder['revision'] as num).toInt(), greaterThan(1));
      expect(serverFolder['updated_at'], isA<String>());

      final collection = (await raw.entities('collection'))[collectionId];
      expect(collection, isNotNull);
      expect(collection!['folder_id'], folderId);
      expect(collection['name'], 'Fixture multi-source work');
      expect(collection['detected_title'], 'Fixture multi-source work');
      expect(collection['ordering_basis'], 'explicitNumericIndex');
      expect(collection['lifecycle'], 'active');
      expect(collection['preferred_source_id'], isNull);

      final source = (await raw.entities('source'))[sourceId];
      expect(source, isNotNull);
      expect(source!['collection_id'], collectionId);
      expect(source['host'], keys.host);
      expect(source['path_key'], keys.pathKey);
      expect(source['language'], 'en');
      expect(source['lifecycle'], 'active');
      expect(source['resolved_into_source_id'], isNull);

      final entry = (await raw.entities('entry'))[entryId];
      expect(entry, isNotNull);
      expect(entry!['collection_id'], collectionId);
      expect(
        entry['folder_id'],
        isNull,
        reason: 'I3: a Folder iff no Collection',
      );
      expect((entry['ordinal'] as num).toDouble(), 5);
      expect(entry['placement'], 'placed');
      expect(entry['title'], 'Part 5');

      final location = (await raw.entities('location'))[locationId];
      expect(location, isNotNull);
      expect(location!['entry_id'], entryId);
      expect(location['source_id'], sourceId);
      expect(location['url'], partUrl);
      expect(location['url_key'], keys.urlKey);
      expect(location['source_label'], 'Part 5');
      expect((location['source_number'] as num).toDouble(), 5);
      expect(location['discovery_basis'], 'listing');
      expect(location['lifecycle'], 'active');

      final reading = (await raw.entities('readingState'))[entryId];
      expect(reading, isNotNull);
      expect(reading!['status'], 'reading');
      expect(reading['first_opened_at'], isA<String>());
      expect(reading['last_read_at'], isA<String>());
      expect(
        reading['completed_at'],
        isNull,
        reason: 'opening at a source records access, never completion (I16)',
      );

      final measurement = (await raw.entities(
        'measurement',
      ))['$entryId|$sourceId'];
      expect(measurement, isNotNull);
      expect(measurement!['source_id'], sourceId, reason: 'I12: scoped');
      expect((measurement['fraction'] as num).toDouble(), 0.25);

      final revisions = [
        for (final change in await raw.feed())
          (change['revision'] as num).toInt(),
      ];
      expect(
        revisions,
        equals(List.of(revisions)..sort()),
        reason: 'the feed is in revision order',
      );
      expect(
        revisions.toSet().length,
        revisions.length,
        reason: 'one revision per change',
      );
    },
  );

  test('a second phone bootstraps from cursor 0 and matches', () async {
    final b = E2EClient.start('B', library);
    addTearDown(b.stop);

    expect(await b.syncState.cursor(), 0, reason: 'nothing seen yet');
    final outcome = await b.sync();
    expect(outcome.pulled!.applied, greaterThan(0));
    expect(outcome.pulled!.errors, isEmpty);
    expect(await b.syncState.cursor(), await raw.latestRevision());

    final bRoot = await b.folders.ensureRoot();
    final aRoot = await a.folders.ensureRoot();
    expect(
      bRoot.serverId,
      isNotNull,
      reason: 'the root is mapped by kind, not by id (V2-D21)',
    );
    expect(bRoot.serverId, aRoot.serverId);
    expect(bRoot.id, isNot(aRoot.id), reason: 'local ids stay local');

    final bFolder = await b.folders.byId(folderId);
    expect(bFolder, isNotNull);
    expect(bFolder!.parentId, bRoot.id, reason: 'reparented onto B own root');
    expect(bFolder.name, 'Reading');

    final bCollection = await b.collections.byId(collectionId);
    expect(bCollection, isNotNull);
    expect(bCollection!.name, 'Fixture multi-source work');
    expect(bCollection.folderId, folderId);
    expect(bCollection.orderingBasis, 'explicitNumericIndex');

    final bSource = await b.collections.sourceById(sourceId);
    expect(bSource, isNotNull);
    expect(bSource!.host, keys.host);
    expect(bSource.pathKey, keys.pathKey);
    expect(bSource.language, 'en');
    expect(bSource.collectionId, collectionId);

    final bEntry = await b.entries.byId(entryId);
    expect(bEntry, isNotNull);
    expect(bEntry!.ordinal, 5);
    expect(bEntry.title, 'Part 5');
    expect(bEntry.collectionId, collectionId);
    expect(bEntry.folderId, isNull);

    final bLocation = await b.entries.locationById(locationId);
    expect(bLocation, isNotNull);
    expect(bLocation!.url, partUrl);
    expect(bLocation.urlKey, keys.urlKey);
    expect(bLocation.entryId, entryId);
    expect(bLocation.sourceId, sourceId);

    final bReading = await b.readingStates.stateOf(entryId);
    expect(bReading.status, ReadStatus.reading);
    expect(bReading.completedAt, isNull);

    final bMeasurement = await b.measurements.of(entryId, sourceId);
    expect(bMeasurement, isNotNull);
    expect(bMeasurement!.fraction, 0.25);

    expect(
      await b.outbox.pendingCount(),
      0,
      reason: 'applying a pull never writes an intent',
    );
  });
}
