/// The restart group: nothing the service knows may live in the process.
///
/// Run in two phases by `tool/e2e/run.sh`, with the service killed and started
/// again on the same database in between:
///
///   --dart-define=SCROLLARY_E2E_RESTART_PHASE=seed     writes the library
///   --dart-define=SCROLLARY_E2E_RESTART_PHASE=verify   checks it survived
///
/// Three pieces of state have to come back, and each is checked for itself:
/// the **change feed** (the rows and their revisions), the **cursor** (the
/// monotonic counter, which must continue rather than restart), and the
/// **mutation ledger** (a replayed id is still a duplicate, at the revision it
/// was originally given).
///
/// With no phase define both groups skip, so the file is inert in an ordinary
/// `flutter test test/e2e` sweep.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;
  if (kE2ERestartPhase.isEmpty || kE2ERestartHandoff.isEmpty) {
    test('restart_persistence', () {}, skip: 'runs only from tool/e2e/run.sh');
    return;
  }

  late FixtureSite fixture;
  final handoff = File(kE2ERestartHandoff);

  setUpAll(() async {
    fixture = await FixtureSite.start();
  });

  tearDownAll(() async {
    fixture.expectNothingFetched('restart persistence ($kE2ERestartPhase)');
    await fixture.stop();
  });

  if (kE2ERestartPhase == 'seed') {
    test(
      'restart_persistence: a library is written and its state recorded',
      () async {
        final library = uniqueLibrary('restart');
        final a = E2EClient.start('A', library);
        final raw = RawApi(library: library);
        addTearDown(() async {
          raw.close();
          await a.stop();
        });

        final root = await a.folders.ensureRoot();
        final (folder, _) = await a.folders.create(
          'Reading',
          parentId: root.id,
        );
        final (collection, _) = await a.collections.create(
          name: 'Fixture multi-source work',
          folderId: folder!.id,
          orderingBasis: OrderingBasis.explicitNumericIndex,
        );
        final keys = RecognitionKeys.of(fixture.partUrl('alpha', 9));
        final (source, _) = await a.collections.addSource(
          collectionId: collection!.id,
          host: keys.host,
          pathKey: keys.pathKey!,
          language: 'en',
        );
        final (entry, _) = await a.entries.createInCollection(
          collectionId: collection.id,
          ordinal: 9,
          title: 'Part 9',
        );
        final (location, _) = await a.entries.addLocation(
          entryId: entry!.id,
          sourceId: source!.id,
          url: fixture.partUrl('alpha', 9),
          urlKey: keys.urlKey,
          sourceLabel: 'Part 9',
          sourceNumber: 9,
        );
        await a.readingStates.markRead(entry.id);
        await a.measurements.put(
          entryId: entry.id,
          sourceId: source.id,
          fraction: 0.6,
        );

        final recorder = RecordingTransport(a.transport);
        await a.sync(via: recorder);
        expect(await a.outbox.pendingCount(), 0);
        expect(recorder.batches, hasLength(1));

        final results =
            (recorder.replies.single.body['results']! as List<Object?>)
                .cast<Map<String, Object?>>();
        expect(results.every((r) => r['outcome'] == 'applied'), isTrue);

        final feed = await raw.feed();
        await handoff.writeAsString(
          jsonEncode({
            'library': library,
            'cursor': await a.syncState.cursor(),
            'latest_revision': await raw.latestRevision(),
            'feed': [
              for (final change in feed)
                {
                  'revision': change['revision'],
                  'type': change['type'],
                  'entity_type': change['entity_type'],
                },
            ],
            'batch': recorder.batches.single,
            'revisions': {
              for (final result in results)
                result['mutation_id'] as String: result['revision'],
            },
            'folder_id': folder.id,
            'collection_id': collection.id,
            'source_id': source.id,
            'entry_id': entry.id,
            'location_id': location!.id,
            'url': location.url,
            'url_key': keys.urlKey,
          }),
        );
        stdout.writeln(
          'RESTART SEED: ${feed.length} changes, '
          'cursor ${await a.syncState.cursor()}',
        );
      },
    );
    return;
  }

  test(
    'restart_persistence: the feed, the cursor and the ledger survived',
    () async {
      expect(
        handoff.existsSync(),
        isTrue,
        reason: 'the seed phase must run before the verify phase',
      );
      final seeded =
          jsonDecode(await handoff.readAsString()) as Map<String, Object?>;
      final library = seeded['library']! as String;
      final cursor = (seeded['cursor']! as num).toInt();
      final latest = (seeded['latest_revision']! as num).toInt();
      final raw = RawApi(library: library);
      addTearDown(raw.close);

      // 1. The change feed. Same rows, same revisions, same order.
      final feed = await raw.feed();
      expect(
        [
          for (final change in feed)
            {
              'revision': change['revision'],
              'type': change['type'],
              'entity_type': change['entity_type'],
            },
        ],
        seeded['feed'],
        reason: 'the change feed came back exactly as it went in',
      );

      // 2. The cursor. A client that had caught up is still caught up, and the
      // counter continues rather than restarting.
      final atCursor = await raw.get('/changes?cursor=$cursor&limit=100');
      expect(atCursor.status, 200);
      expect((atCursor.body['changes']! as List<Object?>), isEmpty);
      expect((atCursor.body['next_cursor'] as num).toInt(), cursor);
      expect((atCursor.body['latest_revision'] as num).toInt(), latest);

      // 3. The mutation ledger. A replayed batch is still a duplicate, at the
      // revisions originally assigned.
      final replay = await raw.post(
        '/mutations',
        Map<String, Object?>.from(seeded['batch']! as Map),
      );
      expect(replay.status, 200, reason: replay.raw);
      final results = (replay.body['results']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final expected = Map<String, Object?>.from(seeded['revisions']! as Map);
      expect(results, hasLength(expected.length));
      for (final result in results) {
        expect(
          result['outcome'],
          'duplicate',
          reason: 'the ledger is durable, not a process-lifetime cache',
        );
        expect(result['revision'], expected[result['mutation_id']]);
      }
      expect(
        await raw.latestRevision(),
        latest,
        reason: 'a replay after a restart spends no revision either',
      );

      // 4. A device that has never seen this library still bootstraps from it.
      final fresh = E2EClient.start('after-restart', library);
      addTearDown(fresh.stop);
      final pulled = await fresh.sync();
      expect(pulled.pulled!.errors, isEmpty);
      expect(
        pulled.pulled!.applied,
        greaterThanOrEqualTo(feed.length - 1),
        reason:
            'everything but the root Folder, which this device already has and '
            'only adopts the canonical id of (V2-D21)',
      );
      expect(await fresh.syncState.cursor(), latest);

      final entryId = seeded['entry_id']! as String;
      final entry = await fresh.entries.byId(entryId);
      expect(entry, isNotNull);
      expect(entry!.title, 'Part 9');
      expect(entry.ordinal, 9);
      expect(entry.collectionId, seeded['collection_id']);
      final location = await fresh.entries.locationById(
        seeded['location_id']! as String,
      );
      expect(location, isNotNull);
      expect(location!.url, seeded['url']);
      expect(location.urlKey, seeded['url_key']);
      expect(
        (await fresh.readingStates.stateOf(entryId)).status,
        ReadStatus.completed,
      );
      expect(
        (await fresh.measurements.of(
          entryId,
          seeded['source_id']! as String,
        ))!.fraction,
        0.6,
      );
      expect(
        (await fresh.collections.byId(
          seeded['collection_id']! as String,
        ))!.name,
        'Fixture multi-source work',
      );

      // 5. And the counter carries on from where it was, rather than reusing a
      // revision the old process had already handed out.
      final violation = await fresh.collections.rename(
        seeded['collection_id']! as String,
        'Renamed after the restart',
      );
      expect(violation, isNull);
      await fresh.sync();
      expect(
        await raw.latestRevision(),
        greaterThan(latest),
        reason: 'the revision counter continued across the restart',
      );
      stdout.writeln(
        'RESTART VERIFY: ${feed.length} changes replayed, '
        'cursor $cursor, latest $latest',
      );
    },
  );
}
