/// Shared fixture for the sync-engine tests: an in-memory LibraryDatabase,
/// repositories with a controllable clock, the fake backend, and a real
/// [HttpSyncTransport] talking to it over loopback.
library;

import 'package:drift/native.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/download_request_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/measurement_repository.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/transport.dart';

import 'fake_server.dart';

class SyncHarness {
  SyncHarness._(this.db, this.backend, this.transport, this.engine);

  static Future<SyncHarness> start() async {
    final db = LibraryDatabase.forTesting(NativeDatabase.memory());
    final backend = FakeBackend();
    await backend.start();
    final harness = SyncHarness._(
      db,
      backend,
      HttpSyncTransport(baseUrl: backend.baseUrl, libraryName: 'test-library'),
      SyncEngine(db),
    );
    return harness;
  }

  final LibraryDatabase db;
  final FakeBackend backend;
  final HttpSyncTransport transport;
  final SyncEngine engine;

  /// A controllable clock for local writes, monotonic per call.
  DateTime clockValue = DateTime.utc(2026, 8, 21, 10);
  DateTime tick() => clockValue = clockValue.add(const Duration(seconds: 1));

  late final folders = FolderRepository(db, now: tick);
  late final collections = CollectionRepository(db, now: tick);
  late final entries = EntryRepository(db, now: tick);
  late final readingStates = ReadingStateRepository(db, now: tick);
  late final measurements = MeasurementRepository(db, now: tick);
  late final downloadRequests = DownloadRequestRepository(db, now: tick);
  late final outbox = OutboxRepository(db);
  late final syncState = SyncStateStore(db);

  Future<void> stop() async {
    transport.close();
    await backend.stop();
    await db.close();
  }
}
