/// A Collection that was checked five minutes ago does not say *Not checked
/// yet* after a restart.
///
/// The state used to live for one run of the app, because the schema was frozen
/// and a check is cheap to repeat. Cheap to repeat is not the same as free to
/// forget: the chip is how the library says whether it is current, and a chip
/// that resets on every launch says nothing at all.
///
/// What deliberately does NOT come back is covered here too. A check
/// interrupted by a kill is not still running, and the Entries a check found
/// answer "what arrived while you were looking".
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_check_repository.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/check_state.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/discovery.dart';

void main() {
  late LibraryDatabase db;
  late CollectionCheckRepository durable;

  setUp(() async {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    durable = CollectionCheckRepository(db);
  });

  tearDown(() => db.close());

  Future<String> aCollection() async {
    final root = await FolderRepository(db).ensureRoot();
    final (collection, _) = await CollectionRepository(db).create(
      name: 'Serial Alpha',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    return collection!.id;
  }

  SourceCheckOutcome concluded({List<String> found = const []}) =>
      SourceCheckOutcome(
        sourceId: 'src',
        state: found.isEmpty
            ? SourceCheckState.upToDate
            : SourceCheckState.updatesAvailable,
        discovery: DiscoveryOutcome(createdEntryIds: found),
      );

  SourceCheckOutcome cutShort() => const SourceCheckOutcome(
    sourceId: 'src',
    state: SourceCheckState.stopped,
    stopReason: SourceCheckStop.pageLimitReached,
  );

  /// Everything a restart keeps: a new store over the same database.
  Future<CheckStateStore> afterRestart() async {
    final store = CheckStateStore(durable);
    await store.restore();
    return store;
  }

  test('when a check last concluded survives a restart', () async {
    final id = await aCollection();
    final at = DateTime.utc(2026, 9, 3, 12);
    CheckStateStore(durable).recordCheck(id, concluded(), at: at);
    await pumpEventQueue();

    final restored = await afterRestart();

    expect(restored.of(id).checkedAt!.isAtSameMomentAs(at), isTrue);
    expect(restored.of(id).failed, isFalse);
  });

  test('and so does a check that failed', () async {
    final id = await aCollection();
    CheckStateStore(
      durable,
    ).recordCheck(id, cutShort(), at: DateTime.utc(2026, 9, 3, 12));
    await pumpEventQueue();

    final restored = await afterRestart();

    expect(restored.of(id).failed, isTrue);
    expect(
      restored.of(id).checkedAt,
      isNull,
      reason:
          'a reading that vouches for nothing must not stamp a time — '
          '"Checked 2 minutes ago" over a site that would not load is a lie',
    );
  });

  test('a run in progress does not come back as one', () async {
    final id = await aCollection();
    CheckStateStore(durable).beginCheck(id);
    await pumpEventQueue();

    final restored = await afterRestart();

    expect(
      restored.of(id).checking,
      isFalse,
      reason: 'a check interrupted by a kill is not still running',
    );
  });

  test("what a check found is this session's, not the library's", () async {
    final id = await aCollection();
    final store = CheckStateStore(durable);
    store.recordCheck(
      id,
      concluded(found: const ['e1', 'e2']),
      at: DateTime.utc(2026, 9, 3, 12),
    );
    await pumpEventQueue();
    expect(store.of(id).newCount, 2);

    final restored = await afterRestart();

    expect(restored.of(id).newEntryIds, isEmpty);
    expect(
      restored.of(id).checkedAt,
      isNotNull,
      reason: 'the conclusion still comes back; only the highlight does not',
    );
  });

  test('a check that never ran leaves the last one that did', () async {
    final id = await aCollection();
    final at = DateTime.utc(2026, 9, 3, 12);
    final store = CheckStateStore(durable);
    store.recordCheck(id, concluded(), at: at);
    await pumpEventQueue();

    // The Browser was busy, or there was no site to read.
    store.recordCheck(id, null, at: DateTime.utc(2026, 9, 3, 13));
    await pumpEventQueue();

    final restored = await afterRestart();
    expect(restored.of(id).checkedAt!.isAtSameMomentAs(at), isTrue);
  });

  test('a live check outranks what the restore read', () async {
    // The read is asynchronous and the app is already running: a check that
    // started while it was in flight knows more than the row does.
    final id = await aCollection();
    await durable.record(
      id,
      checkedAt: DateTime.utc(2026, 9, 1),
      failed: false,
    );

    final store = CheckStateStore(durable);
    store.beginCheck(id);
    await store.restore();

    expect(store.of(id).checking, isTrue);
    expect(store.of(id).checkedAt, isNull);
  });

  test('removing a Collection takes its check state with it', () async {
    final id = await aCollection();
    await durable.record(
      id,
      checkedAt: DateTime.utc(2026, 9, 1),
      failed: false,
    );

    await CollectionRepository(db).removeCollection(id);

    expect(await durable.load(), isEmpty);
  });

  test('a store with nowhere to write still works', () async {
    final id = await aCollection();
    final store = CheckStateStore();
    store.recordCheck(id, concluded(), at: DateTime.utc(2026, 9, 3, 12));
    expect(store.of(id).checkedAt, isNotNull);
    await store.restore();
    expect(store.of(id).checkedAt, isNotNull);
  });
}
