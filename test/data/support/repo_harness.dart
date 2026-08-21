/// Shared harness for the V2 repository tests: an in-memory database with
/// foreign keys on (the schema's `beforeOpen` pragma), every repository over
/// it, a deterministic advancing clock, and outbox counting.
///
/// [CountingInterceptor] lives here too, because "this is one indexed lookup
/// and not a walk" is a claim several suites make and it should be measured
/// the same way in all of them.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/download_request_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/measurement_repository.dart';
import 'package:web_reader/data/offline_copy_repository.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';

/// Counts SELECT statements reaching the executor, so a test can assert that
/// a path is a single lookup rather than a chain, and that its cost does not
/// grow with the size of the library.
class CountingInterceptor extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

class RepoHarness {
  RepoHarness({QueryExecutor? executor})
    : db = LibraryDatabase.forTesting(executor ?? NativeDatabase.memory()) {
    folders = FolderRepository(db, now: tick);
    collections = CollectionRepository(db, now: tick);
    entries = EntryRepository(db, now: tick);
    reading = ReadingStateRepository(db, now: tick);
    measurements = MeasurementRepository(db, now: tick);
    offline = OfflineCopyRepository(db, now: tick);
    requests = DownloadRequestRepository(db, now: tick);
    outbox = OutboxRepository(db);
    syncState = SyncStateStore(db);
    recognition = RecognitionIndex(db);
  }

  final LibraryDatabase db;
  late final FolderRepository folders;
  late final CollectionRepository collections;
  late final EntryRepository entries;
  late final ReadingStateRepository reading;
  late final MeasurementRepository measurements;
  late final OfflineCopyRepository offline;
  late final DownloadRequestRepository requests;
  late final OutboxRepository outbox;
  late final SyncStateStore syncState;
  late final RecognitionIndex recognition;

  /// A strictly advancing deterministic clock.
  int _ticks = 0;
  DateTime tick() =>
      DateTime.utc(2026, 8, 21, 10).add(Duration(seconds: _ticks++));

  Future<int> outboxCount() => outbox.pendingCount();

  /// Root folder, one collection with one source, one placed entry with a
  /// location — the standing furniture most tests need.
  Future<
    ({
      FolderRow root,
      CollectionRow collection,
      SourceRow source,
      EntryRow entry,
      LocationRow location,
    })
  >
  seedLibrary() async {
    final root = await folders.ensureRoot();
    final (collection, cv) = await collections.create(
      name: 'Serial Alpha',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    assert(cv == null);
    final (source, sv) = await collections.addSource(
      collectionId: collection!.id,
      host: 'reading.example.com',
      pathKey: 'serial-alpha',
      language: 'en',
    );
    assert(sv == null);
    final (entry, ev) = await entries.createInCollection(
      collectionId: collection.id,
      ordinal: 101,
      title: 'Part 101',
    );
    assert(ev == null);
    final (location, lv) = await entries.addLocation(
      entryId: entry!.id,
      sourceId: source!.id,
      url: 'https://reading.example.com/serial-alpha/part-101',
      urlKey: 'https://reading.example.com/serial-alpha/part-101',
      sourceLabel: 'Part 101',
      sourceNumber: 101,
    );
    assert(lv == null);
    return (
      root: root,
      collection: collection,
      source: source,
      entry: entry,
      location: location!,
    );
  }

  Future<void> close() => db.close();
}
