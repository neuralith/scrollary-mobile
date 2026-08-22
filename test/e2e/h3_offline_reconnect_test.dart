/// H3 — end to end: a phone mutates offline, reconnects, and a second client
/// converges. Includes the two cases the roadmap names explicitly: an
/// interrupted pull and a duplicate mutation batch.
///
/// "Offline" here is a real refused connection to a port nothing listens on,
/// not a flag inside the engine — the property under test is that the outbox
/// survives a transport that cannot be reached at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/sync/transport.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late E2EClient b;
  late RawApi raw;

  late String collectionId;
  late String sourceId;
  late String entryId;
  late String secondEntryId;

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('h3');
    a = E2EClient.start('A', library);
    b = E2EClient.start('B', library);
    raw = RawApi(library: library);

    final root = await a.folders.ensureRoot();
    final (collection, _) = await a.collections.create(
      name: 'Fixture multi-source work',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    collectionId = collection!.id;
    final keys = RecognitionKeys.of(fixture.partUrl('alpha', 1));
    final (source, _) = await a.collections.addSource(
      collectionId: collectionId,
      host: keys.host,
      pathKey: keys.pathKey!,
      language: 'en',
    );
    sourceId = source!.id;
    final (entry, _) = await a.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 1,
      title: 'Part 1',
    );
    entryId = entry!.id;
    await a.entries.addLocation(
      entryId: entryId,
      sourceId: sourceId,
      url: fixture.partUrl('alpha', 1),
      urlKey: keys.urlKey,
      sourceLabel: 'Part 1',
      sourceNumber: 1,
    );
    await a.sync();
    await b.sync();
  });

  tearDownAll(() async {
    raw.close();
    await a.stop();
    await b.stop();
    fixture.expectNothingFetched('H3 offline, reconnect, second client');
    await fixture.stop();
  });

  test(
    'offline mutations are durable, local, and drain on reconnect',
    () async {
      final offline = HttpSyncTransport(
        baseUrl: await unreachableBaseUrl(),
        libraryName: library,
      );
      addTearDown(offline.close);

      final renameViolation = await a.collections.rename(
        collectionId,
        'Fixture multi-source work (renamed offline)',
      );
      expect(renameViolation, isNull);
      final (second, entryViolation) = await a.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 2,
        title: 'Part 2',
      );
      expect(entryViolation, isNull);
      secondEntryId = second!.id;
      final (reading, _) = await a.readingStates.recordSourceAccess(entryId);
      expect(reading!.status, ReadStatus.reading);

      // Local state is the user's state: it is committed and visible before
      // anything touches the network (V2_SYNC.md §1).
      expect(
        (await a.collections.byId(collectionId))!.name,
        'Fixture multi-source work (renamed offline)',
      );
      expect((await a.entries.entriesOf(collectionId)).length, 2);
      expect(await a.outbox.pendingCount(), 3);

      final failed = await a.sync(via: offline, expectError: true);
      expect(failed.succeeded, isFalse);
      expect(failed.error, isNotNull);
      expect(
        await a.outbox.pendingCount(),
        3,
        reason: 'an unreachable service acknowledges nothing',
      );
      expect((await a.entries.entriesOf(collectionId)).length, 2);
      final status = await a.engine.status();
      expect(status.pendingCount, 3);
      expect(status.lastError, isNotNull);

      await a.sync();
      expect(await a.outbox.pendingCount(), 0);
      final healthy = await a.engine.status();
      expect(healthy.lastError, isNull);
      expect(healthy.pendingCount, 0);

      await b.sync();
      expect(
        (await b.collections.byId(collectionId))!.name,
        'Fixture multi-source work (renamed offline)',
      );
      final onB = await b.entries.byId(secondEntryId);
      expect(onB, isNotNull);
      expect(onB!.ordinal, 2);
      expect(
        (await b.readingStates.stateOf(entryId)).status,
        ReadStatus.reading,
      );
    },
  );

  test('a replayed batch is answered duplicate and lands once', () async {
    final recorder = RecordingTransport(a.transport);
    final violation = await a.collections.rename(collectionId, 'Renamed once');
    expect(violation, isNull);
    await a.sync(via: recorder);
    expect(recorder.batches, hasLength(1));

    final applied = recorder.replies.single;
    final firstResults = (applied.body['results']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(firstResults.single['outcome'], 'applied');
    final firstRevision = (firstResults.single['revision'] as num).toInt();

    final revisionBefore = await raw.latestRevision();
    final replay = await raw.post('/mutations', recorder.batches.single);
    expect(replay.status, 200);
    final results = (replay.body['results']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(results, hasLength(1));
    expect(
      results.single['outcome'],
      'duplicate',
      reason: 'the ledger answers a replayed mutation id',
    );
    expect(
      (results.single['revision'] as num).toInt(),
      firstRevision,
      reason: 'a duplicate carries the revision originally assigned',
    );
    expect(
      await raw.latestRevision(),
      revisionBefore,
      reason: 'a duplicate spends no revision',
    );

    await b.sync();
    expect((await b.collections.byId(collectionId))!.name, 'Renamed once');
    final collections = await raw.entities('collection');
    expect(collections, hasLength(1), reason: 'one effect, not two');
  });

  test('an interrupted pull resumes from the last committed page', () async {
    // Its own library, built in referential order and never updated again, so
    // this test measures the interruption and nothing else.
    final pagedLibrary = uniqueLibrary('h3-paged');
    final author = E2EClient.start('paged-author', pagedLibrary);
    addTearDown(author.stop);
    final pagedRaw = RawApi(library: pagedLibrary);
    addTearDown(pagedRaw.close);

    final root = await author.folders.ensureRoot();
    final (collection, _) = await author.collections.create(
      name: 'Paged work',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final firstKeys = RecognitionKeys.of(fixture.partUrl('beta', 5));
    final (source, _) = await author.collections.addSource(
      collectionId: collection!.id,
      host: firstKeys.host,
      pathKey: firstKeys.pathKey!,
      language: 'tr',
    );
    final placed = <String>[];
    for (final part in [5, 6, 7]) {
      final keys = RecognitionKeys.of(fixture.partUrl('beta', part));
      final (entry, _) = await author.entries.createInCollection(
        collectionId: collection.id,
        ordinal: part.toDouble(),
        title: 'Part $part',
      );
      placed.add(entry!.id);
      await author.entries.addLocation(
        entryId: entry.id,
        sourceId: source!.id,
        url: fixture.partUrl('beta', part),
        urlKey: keys.urlKey,
        sourceLabel: 'Part $part',
        sourceNumber: part.toDouble(),
      );
    }
    await author.sync();

    final feed = await pagedRaw.feed();
    expect(
      feed.length,
      greaterThanOrEqualTo(7),
      reason: 'the interrupted-pull case needs several pages',
    );

    final c = E2EClient.start('C', pagedLibrary);
    addTearDown(c.stop);
    final interrupting = InterruptingTransport(c.transport, pages: 1);

    final killed = await c.sync(
      pullLimit: 2,
      via: interrupting,
      expectError: true,
    );
    expect(killed.succeeded, isFalse);
    expect(killed.pulled, isNull, reason: 'the pull never returned');

    final cursorAfterKill = await c.syncState.cursor();
    expect(
      cursorAfterKill,
      (feed[1]['revision'] as num).toInt(),
      reason: 'the cursor moves with its committed page and no further',
    );
    expect(
      cursorAfterKill,
      lessThan(await pagedRaw.latestRevision()),
      reason: 'the rest of the feed is still owed',
    );

    // The next opportunity resumes exactly where the last committed page
    // ended; nothing before the cursor is asked for again.
    final resumed = await c.sync(pullLimit: 2);
    expect(resumed.pulled!.errors, isEmpty);
    expect(resumed.pulled!.skipped, 0);
    expect(await c.syncState.cursor(), await pagedRaw.latestRevision());

    expect((await c.collections.byId(collection.id))!.name, 'Paged work');
    expect((await c.entries.entriesOf(collection.id)).length, 3);
    for (final entryId in placed) {
      expect(await c.entries.byId(entryId), isNotNull);
      expect(await c.entries.locationsOf(entryId), hasLength(1));
    }
    expect(await c.outbox.pendingCount(), 0);
  });

  test('a client bootstrapping after a parent was renamed receives its '
      'children', () async {
    // The feed carries each row once, at the revision it *currently* holds, so
    // renaming a Collection moves it behind the Sources, Entries and Locations
    // that reference it. A client bootstrapping from cursor 0 then meets the
    // children first.
    final bootstrap = E2EClient.start('bootstrap', library);
    addTearDown(bootstrap.stop);

    final order = [
      for (final change in await raw.feed())
        if (change['type'] == 'entity') change['entity_type'] as String,
    ];
    expect(
      order.indexOf('collection'),
      greaterThan(order.indexOf('entry')),
      reason: 'this library is in the shape the case is about',
    );

    final pulled = await bootstrap.sync();
    expect(pulled.pulled!.errors, isEmpty);
    final diagnosis =
        'a bootstrapping client applied only ${pulled.pulled!.applied} of '
        '${pulled.pulled!.applied + pulled.pulled!.skipped} changes; the '
        'skipped rows referenced a parent that had not arrived yet, and the '
        'cursor moved past them in the same transaction, so they are never '
        'offered again';
    expect(
      (await bootstrap.entries.entriesOf(collectionId)).length,
      2,
      reason: diagnosis,
    );
    expect(await bootstrap.entries.byId(entryId), isNotNull);
    expect(await bootstrap.entries.byId(secondEntryId), isNotNull);
    expect(await bootstrap.collections.sourceById(sourceId), isNotNull);
    expect(await bootstrap.entries.locationsOf(entryId), hasLength(1));
  });

  test(
    'reading state inverts across two clients on the reading clock',
    () async {
      final earlier = E2EClock.now();
      final later = earlier.add(const Duration(minutes: 5));
      final latest = earlier.add(const Duration(minutes: 10));

      // B lowers progress first, A completes with a later clock. Whichever
      // order they reach the service, the later clock is the answer.
      await b.readingStates.markUnread(entryId, at: earlier);
      await a.readingStates.markRead(entryId, at: later);
      await b.sync();
      await a.sync();
      await b.sync();

      final onServer = (await raw.entities('readingState'))[entryId]!;
      expect(onServer['status'], 'completed');
      expect(
        (await a.readingStates.stateOf(entryId)).status,
        ReadStatus.completed,
      );
      expect(
        (await b.readingStates.stateOf(entryId)).status,
        ReadStatus.completed,
      );

      // The inversion: completion is a value, not a floor (V2-D6). A later
      // Mark as unread lowers it everywhere, which a highest-wins rule could
      // not express.
      await b.readingStates.markUnread(entryId, at: latest);
      await b.sync();
      await a.sync();

      final inverted = (await raw.entities('readingState'))[entryId]!;
      expect(inverted['status'], 'unread');
      expect(inverted['completed_at'], isNull);
      final onA = await a.readingStates.stateOf(entryId);
      expect(onA.status, ReadStatus.unread);
      expect(onA.completedAt, isNull);
      expect(
        onA.firstOpenedAt,
        isNotNull,
        reason: 'the open history stays: it happened',
      );
    },
  );
}
