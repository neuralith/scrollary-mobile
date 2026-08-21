/// Shared id minting and clock injection for the V2 repositories.
///
/// V1 mints ids with `Uuid().v4()` (`lib/library/collection_repository.dart`);
/// the V2 layer keeps the same mechanism. Local ids are permanent primary keys
/// (V2_ARCHITECTURE.md §6.4): a canonical server id is cached beside them and
/// never written over them.
library;

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Mints a new local entity or mutation id.
typedef IdGenerator = String Function();

/// The repositories' clock. Injectable so tests control every timestamp.
typedef Clock = DateTime Function();

String newLocalId() => _uuid.v4();

DateTime utcNow() => DateTime.now().toUtc();
