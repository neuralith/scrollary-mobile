/// Multi-source semantics over the real change feed (roadmap H1 scenarios,
/// V2-D16, V2-D17, V2-D18, I12).
///
/// One logical work published on several simulated sites (`tool/fixture/`):
/// two Sources of one Collection, an Entry both of them print at the same
/// ordinal, a Source that dies, and the renumbering conflict that must stay
/// two Entries. The arbitration and the placement conflict are answered by the
/// real service, which is the only place either question is decided.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_ids.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/domain/source.dart' as domain;
import 'package:web_reader/recognition/evidence.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late E2EClient b;
  late RawApi raw;

  late String collectionId;
  late String turkishSourceId; // beta.example, tr
  late String englishSourceId; // alpha.example, en
  late String shiftedSourceId; // shifted.example, prints half a step below
  late String sharedEntryId;
  late String turkishLocationId;
  late String englishLocationId;
  late String entryAtHundred;
  late String entryAtNinetyNinePointFive;

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('multisource');
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

    Future<String> addSource(String siteId, String language) async {
      final keys = RecognitionKeys.of(fixture.partUrl(siteId, 1));
      final (source, violation) = await a.collections.addSource(
        collectionId: collectionId,
        host: keys.host,
        pathKey: keys.pathKey!,
        language: language,
      );
      expect(violation, isNull);
      return source!.id;
    }

    turkishSourceId = await addSource('beta', 'tr');
    englishSourceId = await addSource('alpha', 'en');
    shiftedSourceId = await addSource('shifted', 'en');

    // One Entry. Both live Sources print it as part 50, so it is one logical
    // unit of reading published in two places (V2-D16, V2-D17).
    final (entry, _) = await a.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 50,
      title: 'Part 50',
    );
    sharedEntryId = entry!.id;

    final turkishKeys = RecognitionKeys.of(fixture.partUrl('beta', 50));
    final (turkishLocation, _) = await a.entries.addLocation(
      entryId: sharedEntryId,
      sourceId: turkishSourceId,
      url: fixture.partUrl('beta', 50),
      urlKey: turkishKeys.urlKey,
      sourceLabel: 'Part 50',
      sourceNumber: 50,
    );
    turkishLocationId = turkishLocation!.id;

    final englishKeys = RecognitionKeys.of(fixture.partUrl('alpha', 50));
    final (englishLocation, _) = await a.entries.addLocation(
      entryId: sharedEntryId,
      sourceId: englishSourceId,
      url: fixture.partUrl('alpha', 50),
      urlKey: englishKeys.urlKey,
      sourceLabel: 'Part 50',
      sourceNumber: 50,
    );
    englishLocationId = englishLocation!.id;

    await a.readingStates.recordSourceAccess(sharedEntryId);
    await a.measurements.put(
      entryId: sharedEntryId,
      sourceId: turkishSourceId,
      fraction: 0.4,
    );
    await a.measurements.put(
      entryId: sharedEntryId,
      sourceId: englishSourceId,
      fraction: 0.9,
    );

    await a.sync();
    await b.sync();
  });

  tearDownAll(() async {
    raw.close();
    await a.stop();
    await b.stop();
    fixture.expectNothingFetched('multi-source semantics');
    await fixture.stop();
  });

  test('one Entry, two Locations, one reading state', () async {
    expect(await raw.entities('entry'), hasLength(1));
    final locations = await raw.entities('location');
    expect(locations, hasLength(2));
    expect(
      locations.values.map((l) => l['entry_id']).toSet(),
      {sharedEntryId},
      reason: 'an Entry is not a URL: both addresses are the same Entry',
    );
    expect(locations.values.map((l) => l['source_id']).toSet(), {
      turkishSourceId,
      englishSourceId,
    });
    expect(await raw.entities('readingState'), hasLength(1));

    expect(await b.entries.entriesOf(collectionId), hasLength(1));
    final onB = await b.entries.locationsOf(sharedEntryId);
    expect(onB, hasLength(2));
    expect(onB.map((l) => l.sourceId).toSet(), {
      turkishSourceId,
      englishSourceId,
    });
    expect(
      (await b.readingStates.stateOf(sharedEntryId)).status,
      ReadStatus.reading,
      reason: 'reading state is portable: it belongs to the Entry',
    );
  });

  test('measurements stay scoped to the rendering they measured', () async {
    final measurements = await raw.entities('measurement');
    expect(measurements, hasLength(2), reason: 'I12: keyed (entry, source)');
    expect(
      (measurements['$sharedEntryId|$turkishSourceId']!['fraction'] as num)
          .toDouble(),
      0.4,
    );
    expect(
      (measurements['$sharedEntryId|$englishSourceId']!['fraction'] as num)
          .toDouble(),
      0.9,
    );

    expect(
      (await b.measurements.of(sharedEntryId, turkishSourceId))!.fraction,
      0.4,
    );
    expect(
      (await b.measurements.of(sharedEntryId, englishSourceId))!.fraction,
      0.9,
    );
    expect(await b.measurements.allOf(sharedEntryId), hasLength(2));
  });

  test('a dead Source is a state, and takes nothing with it', () async {
    final violation = await a.collections.setSourceLifecycle(
      turkishSourceId,
      domain.SourceLifecycle.dead,
    );
    expect(violation, isNull);
    await a.sync();
    await b.sync();

    final sources = await raw.entities('source');
    expect(sources[turkishSourceId]!['lifecycle'], 'dead');
    expect(sources[englishSourceId]!['lifecycle'], 'active');
    expect(
      sources,
      hasLength(3),
      reason: 'a site that stopped publishing is not a deletion (V2-D14)',
    );

    final deadOnB = await b.collections.sourceById(turkishSourceId);
    expect(deadOnB!.lifecycle, 'dead');
    expect(
      await b.entries.byId(sharedEntryId),
      isNotNull,
      reason: 'the Entry survives its Source',
    );
    expect(
      (await b.collections.sourceById(englishSourceId))!.lifecycle,
      'active',
    );
    expect(
      await b.entries.locationsOf(sharedEntryId),
      hasLength(2),
      reason: 'a lifecycle change removes no address',
    );
    expect(
      (await b.entries.locationById(englishLocationId))!.lifecycle,
      'active',
    );
    expect(
      (await b.entries.locationById(turkishLocationId))!.lifecycle,
      'active',
    );
    expect(
      (await b.measurements.of(sharedEntryId, turkishSourceId))!.fraction,
      0.4,
      reason: 'what was read on that Source was still read',
    );
  });

  test(
    'equal printed ordinals are one Entry; the arbitrator says so',
    () async {
      // A third Source of the same Collection prints the same part. The address
      // is unknown, so identity has to come from (host, path_key) plus the
      // ordinal — which is exactly what the server arbitrates.
      final provisionalEntry = newLocalId();
      final provisionalLocation = newLocalId();
      final response = await a.engine.identity.arbitrate(
        a.transport,
        ArbitrationRequest(
          evidence: Evidence.observe(
            keys: RecognitionKeys.of(fixture.partUrl('shifted', 50)),
            observedAt: E2EClock.now(),
            sourceLabel: 'Part 50',
            sourceNumber: 50,
            orderingBasis: OrderingBasis.explicitNumericIndex,
            ordinal: 50,
          ),
          provisional: ProvisionalIdentity(
            entryId: provisionalEntry,
            locationId: provisionalLocation,
            sourceId: newLocalId(),
          ),
        ),
      );

      expect(response.isResolved, isTrue, reason: response.reason ?? '');
      expect(
        response.canonicalFor(IdentityKind.entry, provisionalEntry),
        sharedEntryId,
        reason: 'an equal ordinal in the same Collection IS the same Entry',
      );
      expect(
        response.canonicalFor(IdentityKind.collection, newLocalId()),
        isNull,
        reason: 'a mapping is only ever about an id that was submitted',
      );
    },
  );

  test('a printed number that contradicts the ordinal is refused, and the '
      'two Entries stay two', () async {
    // The renumbering conflict: this site prints "Part 99.5" for what the
    // other prints as "Part 100". Submitting one as the other is a claim no
    // source made, and the arbitrator refuses to repair it.
    final refusal = await a.engine.identity.arbitrate(
      a.transport,
      ArbitrationRequest(
        evidence: Evidence.observe(
          keys: RecognitionKeys.of(fixture.partUrl('shifted', 100)),
          observedAt: E2EClock.now(),
          sourceLabel: 'Part 99.5',
          sourceNumber: 99.5,
          orderingBasis: OrderingBasis.explicitNumericIndex,
          ordinal: 100,
        ),
        provisional: ProvisionalIdentity(entryId: newLocalId()),
      ),
    );
    expect(refusal.isResolved, isFalse);
    expect(refusal.reason, 'conflicting_ordinals');

    // Recorded honestly, they are two Entries and stay two.
    final hundredKeys = RecognitionKeys.of(fixture.partUrl('alpha', 100));
    final (hundred, hundredViolation) = await a.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 100,
      title: 'Part 100',
    );
    expect(hundredViolation, isNull);
    entryAtHundred = hundred!.id;
    await a.entries.addLocation(
      entryId: entryAtHundred,
      sourceId: englishSourceId,
      url: fixture.partUrl('alpha', 100),
      urlKey: hundredKeys.urlKey,
      sourceLabel: 'Part 100',
      sourceNumber: 100,
    );

    final shiftedKeys = RecognitionKeys.of(fixture.partUrl('shifted', 100));
    final (shifted, shiftedViolation) = await a.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 99.5,
      title: 'Part 99.5',
    );
    expect(shiftedViolation, isNull);
    entryAtNinetyNinePointFive = shifted!.id;
    await a.entries.addLocation(
      entryId: entryAtNinetyNinePointFive,
      sourceId: shiftedSourceId,
      url: fixture.partUrl('shifted', 100),
      urlKey: shiftedKeys.urlKey,
      sourceLabel: 'Part 99.5',
      sourceNumber: 99.5,
    );
    await a.sync();
    await b.sync();

    final entries = await raw.entities('entry');
    expect(entries, hasLength(3));
    expect((entries[entryAtHundred]!['ordinal'] as num).toDouble(), 100);
    expect(
      (entries[entryAtNinetyNinePointFive]!['ordinal'] as num).toDouble(),
      99.5,
      reason: 'different printed ordinals are never merged (V2-D16)',
    );
    expect(await b.entries.entriesOf(collectionId), hasLength(3));
  });

  test('placement is arbitrated centrally, and the loser is told', () async {
    final (unplaced, violation) = await a.entries.createInCollection(
      collectionId: collectionId,
      placement: Placement.unplaced,
      title: 'A part whose number nobody printed',
    );
    expect(violation, isNull);
    await a.sync();
    final unplacedId = unplaced!.id;
    final before = (await raw.entities('entry'))[unplacedId]!;
    expect(before['placement'], 'unplaced');
    expect(before['ordinal'], isNull);

    final conflict = await raw.post('/entries/$unplacedId/placement', {
      'ordinal': 100,
      'mutation_id': newLocalId(),
    });
    expect(conflict.status, 409, reason: conflict.raw);
    expect(conflict.errorCode, 'placement_conflict');
    final details =
        (conflict.body['error']! as Map)['details']! as Map<String, Object?>;
    expect(details['current_entry_id'], entryAtHundred);
    expect((details['current_ordinal'] as num).toDouble(), 100);

    expect(
      (await raw.entities('entry'))[unplacedId],
      before,
      reason: 'a losing placement spends no revision and moves no row',
    );

    final won = await raw.post('/entries/$unplacedId/placement', {
      'ordinal': 101,
      'mutation_id': newLocalId(),
    });
    expect(won.status, 200, reason: won.raw);
    final placed = won.body['entry']! as Map<String, Object?>;
    expect(placed['placement'], 'userPlaced');
    expect((placed['ordinal'] as num).toDouble(), 101);

    await a.sync();
    final locally = await a.entries.byId(unplacedId);
    expect(locally!.placement, 'userPlaced');
    expect(locally.ordinal, 101);
  });
}
