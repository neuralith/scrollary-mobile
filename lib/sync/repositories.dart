/// The repository bundle the sync engine works through. Sync never writes the
/// DAO directly: every mutation goes through these, so the outbox rule and
/// the invariants stay in one place.
library;

import '../data/collection_repository.dart';
import '../data/download_request_repository.dart';
import '../data/entry_repository.dart';
import '../data/folder_repository.dart';
import '../data/measurement_repository.dart';
import '../data/outbox_repository.dart';
import '../data/reading_state_repository.dart';
import '../data/schema.dart';
import 'ids.dart';

class SyncRepositories {
  SyncRepositories(this.db)
    : folders = FolderRepository(db),
      collections = CollectionRepository(db),
      entries = EntryRepository(db),
      readingStates = ReadingStateRepository(db),
      measurements = MeasurementRepository(db),
      downloadRequests = DownloadRequestRepository(db),
      outbox = OutboxRepository(db),
      syncState = SyncStateStore(db),
      ids = SyncIds(db);

  final LibraryDatabase db;
  final FolderRepository folders;
  final CollectionRepository collections;
  final EntryRepository entries;
  final ReadingStateRepository readingStates;
  final MeasurementRepository measurements;
  final DownloadRequestRepository downloadRequests;
  final OutboxRepository outbox;
  final SyncStateStore syncState;
  final SyncIds ids;
}
