/// How much, decided once and answered in rows (V2_SAVE_FLOW.md §4).
///
/// Three properties carried from V1, because they were the safety story: the
/// plan is built from a clamped [SaveLimits] and there is no open-ended scope;
/// planning reads the library and opens nothing; and a short plan is stated
/// rather than padded. Nothing here starts a run — a queued row waits for an
/// explicit Start, and the last test says so.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_task.dart';

import '../recognition/support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  /// A Collection on one site holding [numbers], in order.
  Future<(CollectionRow, SourceRow, List<EntryRow>)> serial(
    List<double> numbers, {
    String host = kHostA,
  }) async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: host);
    final entries = <EntryRow>[];
    for (final number in numbers) {
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: source,
        host: host,
        number: number,
      );
      entries.add(entry);
    }
    return (collection, source, entries);
  }

  test('the library knows what was asked for, so the plan is whole', () async {
    final (_, _, entries) = await serial([1, 2, 3, 4, 5]);

    final plan = await h.planner.plan(
      startEntryId: entries[1].id,
      limits: count(3),
    );

    expect(plan.requested, 3);
    expect(plan.planned, 3);
    expect(plan.shortfall, 0);
    expect(plan.saves.map((s) => s.ordinal), [2, 3, 4]);
    expect(plan.saves.first.url, partUrl(kHostA, 2));
  });

  test('the library knows fewer, and the plan says so', () async {
    final (_, _, entries) = await serial([1, 2, 3]);

    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(10),
    );

    expect(plan.planned, 3);
    expect(plan.shortfall, 7);
    expect(plan.startIsUnplaced, isFalse);
  });

  test('an Entry with no address ends the walk rather than being '
      'skipped', () async {
    final (collection, source, entries) = await serial([1, 3]);
    // Part 2 is in the library but the app holds no address for it.
    await h.repos.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 2,
      title: 'Part 2',
    );
    expect(source.id, isNotEmpty);

    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(3),
    );

    expect(plan.saves.map((s) => s.ordinal), [1]);
    expect(plan.shortfall, 2);
  });

  test('a retracted address is not an address', () async {
    final (_, source, entries) = await serial([1, 2]);
    final second = (await h.repos.entries.locationsOf(entries[1].id)).single;
    await h.repos.entries.retractLocation(
      second.id,
      readingSourceId: source.id,
    );

    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(2),
    );

    expect(plan.planned, 1);
    expect(plan.shortfall, 1);
  });

  test('an unplaced start is that Entry alone, and says why', () async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: kHostA);
    await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: 1,
    );
    final (loose, _) = await h.repos.entries.createInCollection(
      collectionId: collection.id,
      placement: Placement.unplaced,
      title: 'Epilogue',
    );
    final url = postUrl(kHostA, 'epilogue');
    await h.repos.entries.addLocation(
      entryId: loose!.id,
      url: url,
      urlKey: url,
      sourceId: source.id,
    );

    final plan = await h.planner.plan(startEntryId: loose.id, limits: count(5));

    expect(plan.startIsUnplaced, isTrue);
    expect(plan.planned, 1);
    expect(plan.saves.single.entryId, loose.id);
    expect(plan.saves.single.ordinal, isNull);
  });

  test('a standalone Entry is that Entry alone', () async {
    final (entry, _) = await h.repos.entries.createStandalone(
      folderId: (await h.root()).id,
      title: 'A page',
    );
    final url = postUrl(kHostA, 'epilogue');
    await h.repos.entries.addLocation(
      entryId: entry!.id,
      url: url,
      urlKey: url,
    );

    final plan = await h.planner.plan(startEntryId: entry.id, limits: count(4));

    expect(plan.startIsUnplaced, isTrue);
    expect(plan.saves.single.entryId, entry.id);
  });

  test('the count is clamped by the configured ceiling, never by a '
      'plan', () async {
    final (_, _, entries) = await serial([1, 2]);

    final limits = count(50000);
    expect(limits.maxEntries, kDefaultSaveConfig.maxEntriesPerRun);

    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: limits,
    );
    expect(plan.requested, kDefaultSaveConfig.maxEntriesPerRun);
    expect(plan.planned, 2);
  });

  test('a preferred Source is used where the Entry has one', () async {
    final (collection, sourceA, entries) = await serial([1]);
    final sourceB = await h.source(collection: collection, host: kHostB);
    final url = partUrl(kHostB, 1);
    await h.repos.entries.addLocation(
      entryId: entries.first.id,
      url: url,
      urlKey: url,
      sourceId: sourceB.id,
      sourceNumber: 1,
    );

    final preferred = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(1),
      preferSourceId: sourceB.id,
    );
    final earliest = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(1),
    );

    expect(preferred.saves.single.url, url);
    expect(earliest.saves.single.url, partUrl(kHostA, 1));
    expect(sourceA.host, kHostA);
  });

  test('a plan becomes queue rows, and nothing is started', () async {
    final (_, _, entries) = await serial([1, 2, 3]);
    final queue = SaveQueueRepository(h.repos.db);

    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(3),
    );
    for (final save in plan.saves) {
      final result = await queue.enqueue(
        entryId: save.entryId,
        locationId: save.locationId,
        locationUrl: save.url,
      );
      expect(result.refusedReason, isNull);
    }

    final rows = await queue.watch().first;
    expect(rows, hasLength(3));
    expect(rows.every((t) => t.state == SaveTaskState.queued), isTrue);
    expect(
      queue.saveStartAuthorised,
      isFalse,
      reason: 'queued work waits for an explicit Start',
    );
  });

  test('enqueueing the same Entry twice does not stack a second '
      'row', () async {
    final (_, _, entries) = await serial([1]);
    final queue = SaveQueueRepository(h.repos.db);
    final plan = await h.planner.plan(
      startEntryId: entries.first.id,
      limits: count(1),
    );
    final save = plan.saves.single;

    await queue.enqueue(
      entryId: save.entryId,
      locationId: save.locationId,
      locationUrl: save.url,
    );
    final second = await queue.enqueue(
      entryId: save.entryId,
      locationId: save.locationId,
      locationUrl: save.url,
    );

    expect(second.alreadyQueued, isTrue);
    expect(await queue.watch().first, hasLength(1));
  });
}
