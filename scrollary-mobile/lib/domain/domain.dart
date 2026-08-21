/// The V2 domain: pure entities and rules, no Flutter, no persistence.
///
/// The semantic twin of `backend/internal/domain`. Wire spellings come from
/// each enum's `name` and match `backend/migrations/0001_init.up.sql` exactly.
library;

export 'collection.dart';
export 'download_request.dart';
export 'entry.dart';
export 'equivalence.dart';
export 'folder.dart';
export 'invariants.dart';
export 'location.dart';
export 'measurement.dart';
export 'offline_copy.dart';
export 'reading_state.dart';
export 'source.dart';
export 'sync_kinds.dart';
