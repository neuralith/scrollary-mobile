/// Provisional-identity canonicalisation and removal semantics, end to end
/// (V2_SYNC.md §4.5 and §5, roadmap G3).
///
/// Two properties, both of which only a real arbitrator can settle:
///
/// * a Collection and Source minted offline meet identity another device
///   already established, and the local rows **survive** carrying the
///   canonical id — no rename, no duplicate;
/// * a removal that arrives from another device takes library rows and
///   **leaves the bytes on disk** (I14).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/recognition/evidence.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;

  setUpAll(() async {
    fixture = await FixtureSite.start();
  });

  tearDownAll(() async {
    fixture.expectNothingFetched('identity canonicalisation and removal');
    await fixture.stop();
  });

  test('an offline Collection and Source adopt canonical identity', () async {
    final library = uniqueLibrary('identity');
    final b = E2EClient.start('B', library);
    final a = E2EClient.start('A', library);
    final raw = RawApi(library: library);
    addTearDown(() async {
      raw.close();
      await a.stop();
      await b.stop();
    });

    // B established the canonical identity for this (host, path_key).
    final canonicalKeys = RecognitionKeys.of(fixture.partUrl('alpha', 3));
    final bRoot = await b.folders.ensureRoot();
    final (canonicalCollection, _) = await b.collections.create(
      name: 'Fixture multi-source work',
      folderId: bRoot.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (canonicalSource, _) = await b.collections.addSource(
      collectionId: canonicalCollection!.id,
      host: canonicalKeys.host,
      pathKey: canonicalKeys.pathKey!,
      language: 'en',
    );
    final (canonicalEntry, _) = await b.entries.createInCollection(
      collectionId: canonicalCollection.id,
      ordinal: 3,
      title: 'Part 3',
    );
    await b.entries.addLocation(
      entryId: canonicalEntry!.id,
      sourceId: canonicalSource!.id,
      url: fixture.partUrl('alpha', 3),
      urlKey: canonicalKeys.urlKey,
      sourceLabel: 'Part 3',
      sourceNumber: 3,
    );
    await b.sync();

    // A has never synced. It reads a page of the same Source at an address
    // nobody has recorded, and mints its own ids for what it sees.
    final aRoot = await a.folders.ensureRoot();
    final (provisionalCollection, _) = await a.collections.create(
      name: 'A work I just started reading',
      folderId: aRoot.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final unseenUrl = fixture.partUrl('alpha', 4);
    final unseenKeys = RecognitionKeys.of(unseenUrl);
    expect(unseenKeys.pathKey, canonicalKeys.pathKey);
    final (provisionalSource, _) = await a.collections.addSource(
      collectionId: provisionalCollection!.id,
      host: unseenKeys.host,
      pathKey: unseenKeys.pathKey!,
      language: 'en',
    );

    final response = await a.engine.identity.arbitrate(
      a.transport,
      ArbitrationRequest(
        evidence: Evidence.ofUrl(url: unseenUrl, observedAt: E2EClock.now()),
        provisional: ProvisionalIdentity(
          collectionId: provisionalCollection.id,
          sourceId: provisionalSource!.id,
        ),
      ),
    );

    expect(
      response.isResolved,
      isTrue,
      reason: 'a known (host, path_key) resolves the Source and its Collection',
    );
    expect(
      response.canonicalFor(IdentityKind.source, provisionalSource.id),
      canonicalSource.id,
    );
    expect(
      response.canonicalFor(IdentityKind.collection, provisionalCollection.id),
      canonicalCollection.id,
    );

    // Local ids are permanent primary keys: the canonical id is recorded
    // beside them, never written over them.
    final localCollection = await a.collections.byId(provisionalCollection.id);
    expect(localCollection, isNotNull, reason: 'the local row survives');
    expect(localCollection!.serverId, canonicalCollection.id);
    final localSource = await a.collections.sourceById(provisionalSource.id);
    expect(localSource, isNotNull);
    expect(localSource!.serverId, canonicalSource.id);

    await a.sync();

    expect(
      (await a.db.select(a.db.collections).get()).length,
      1,
      reason: 'the pulled canonical Collection landed on the provisional row',
    );
    expect((await a.db.select(a.db.sources).get()).length, 1);
    final survivingCollection = await a.collections.byId(
      provisionalCollection.id,
    );
    expect(
      survivingCollection!.serverId,
      canonicalCollection.id,
      reason: 'the canonical id sits beside the local one, still',
    );
    expect(
      await a.collections.sourceByIdentity(
        canonicalKeys.host,
        canonicalKeys.pathKey!,
      ),
      isNotNull,
    );
    final centralCollections = await raw.entities('collection');
    expect(
      centralCollections,
      hasLength(1),
      reason: 'nothing duplicated centrally either',
    );
    expect(await raw.entities('source'), hasLength(1));
    // A's own create was the later write of the two, so scalar last-write-wins
    // hands it the name. What matters here is that both sides carry ONE
    // Collection and agree about which one it is.
    expect(
      centralCollections[canonicalCollection.id]!['name'],
      survivingCollection.name,
    );

    // B converges on the same single Collection, under the canonical id.
    await b.sync();
    expect((await b.db.select(b.db.collections).get()).length, 1);
    expect((await b.db.select(b.db.sources).get()).length, 1);
    expect(
      (await b.collections.byId(canonicalCollection.id))!.name,
      survivingCollection.name,
    );
    expect(
      (await a.entries.byId(canonicalEntry.id))!.title,
      'Part 3',
      reason: "A also pulled the canonical Collection's Entry",
    );
  });

  test('a removal from another device leaves this device the bytes', () async {
    final library = uniqueLibrary('removal');
    final a = E2EClient.start('A', library);
    final b = E2EClient.start('B', library);
    final raw = RawApi(library: library);
    final store = Directory.systemTemp.createTempSync('scrollary-e2e-copy');
    addTearDown(() async {
      raw.close();
      await a.stop();
      await b.stop();
      if (store.existsSync()) store.deleteSync(recursive: true);
    });

    final root = await a.folders.ensureRoot();
    final keys = RecognitionKeys.of(fixture.partUrl('alpha', 7));
    final (collection, _) = await a.collections.create(
      name: 'Fixture multi-source work',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (source, _) = await a.collections.addSource(
      collectionId: collection!.id,
      host: keys.host,
      pathKey: keys.pathKey!,
      language: 'en',
    );
    final (entry, _) = await a.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 7,
      title: 'Part 7',
    );
    final (location, _) = await a.entries.addLocation(
      entryId: entry!.id,
      sourceId: source!.id,
      url: fixture.partUrl('alpha', 7),
      urlKey: keys.urlKey,
      sourceLabel: 'Part 7',
      sourceNumber: 7,
    );
    await a.readingStates.recordSourceAccess(entry.id);
    await a.sync();
    await b.sync();

    // This device holds bytes for the Entry. The package is a real file, and
    // its provenance is values rather than references (V2-D22).
    final package = File('${store.path}/${entry.id}.document.json')
      ..writeAsStringSync('{"blocks":[{"type":"text","text":"a page"}]}');
    final bytes = package.readAsBytesSync();
    final copy = await a.offline.recordCopy(
      entryId: entry.id,
      locationUrl: location!.url,
      artifactFormat: 'document',
      contentPath: package.path,
      byteSize: bytes.length,
      sourceHost: keys.host,
      sourceLanguage: 'en',
    );

    // B removes the Entry from the library.
    final removal = await b.entries.removeEntry(entry.id);
    expect(removal, isNull);
    await b.sync();
    expect(
      (await raw.entities('entry')),
      isEmpty,
      reason: 'a deliberate user removal tombstones centrally',
    );

    final pulled = await a.sync();
    expect(pulled.pulled!.errors, isEmpty);

    expect(
      await a.entries.byId(entry.id),
      isNull,
      reason: 'the library row goes',
    );
    expect(await a.entries.locationById(location.id), isNull);
    expect(
      (await a.db.select(a.db.readingStates).get()).length,
      0,
      reason: 'reading state cascades with its Entry',
    );

    final survivor = await a.offline.activeCopyOf(entry.id);
    expect(
      survivor,
      isNotNull,
      reason:
          'I14: a remote mutation never deletes local bytes — the copy row '
          'survives to name what a cleanup surface could offer to remove',
    );
    expect(survivor!.id, copy.id);
    expect(survivor.contentPath, package.path);
    expect(survivor.locationUrl, location.url);
    expect(
      package.existsSync(),
      isTrue,
      reason: 'the package on disk is untouched',
    );
    expect(package.readAsBytesSync(), bytes);
    expect(
      await a.outbox.pendingCount(),
      0,
      reason: 'nothing about an offline copy is ever an intent (I11)',
    );
  });
}
