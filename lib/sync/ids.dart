/// Local ↔ wire id translation (roadmap G1/G3, V2_ARCHITECTURE.md §4.1).
///
/// Local UUIDs are permanent primary keys. A client-minted id that the server
/// accepted IS the wire id; an id the server merged into existing identity
/// has the canonical id cached in `server_id`, and the local id never appears
/// on the wire again. So:
///
///   outbound: `server_id ?? local id`  — and an id with no local row at all
///   is passed through unchanged, because the only way a referenced row can
///   be gone is a duplicate merge, and a merged-away duplicate always carried
///   the canonical server id.
///
///   inbound: a wire id resolves to the local row that owns it — by `id`
///   (client-minted canonical) or by `server_id` (mapped) — or to nothing,
///   which means the row is new here.
///
/// This file only reads. Every write stays in the repositories.
library;

import '../data/schema.dart';
import '../domain/sync_kinds.dart';

/// Wire reference fields per entity kind, and the kind each one points at.
/// The vocabulary of `MutationEnvelope.fields` (contracts/openapi.yaml).
const Map<SyncedEntityKind, Map<String, SyncedEntityKind>> referenceFields = {
  SyncedEntityKind.folder: {'parent_id': SyncedEntityKind.folder},
  SyncedEntityKind.collection: {
    'folder_id': SyncedEntityKind.folder,
    'preferred_source_id': SyncedEntityKind.source,
  },
  SyncedEntityKind.source: {
    'collection_id': SyncedEntityKind.collection,
    'resolved_into_source_id': SyncedEntityKind.source,
  },
  SyncedEntityKind.entry: {
    'collection_id': SyncedEntityKind.collection,
    'folder_id': SyncedEntityKind.folder,
  },
  SyncedEntityKind.location: {
    'entry_id': SyncedEntityKind.entry,
    'source_id': SyncedEntityKind.source,
  },
  SyncedEntityKind.readingState: {},
  SyncedEntityKind.measurement: {'source_id': SyncedEntityKind.source},
  SyncedEntityKind.downloadRequest: {
    'entry_id': SyncedEntityKind.entry,
    'location_id': SyncedEntityKind.location,
  },
};

/// The kind an envelope's `entity_id` refers to. Reading state and
/// measurements are keyed by their Entry (the contract's keying convention).
SyncedEntityKind entityIdKind(SyncedEntityKind kind) {
  switch (kind) {
    case SyncedEntityKind.readingState:
    case SyncedEntityKind.measurement:
      return SyncedEntityKind.entry;
    default:
      return kind;
  }
}

class SyncIds {
  SyncIds(this._db);

  final LibraryDatabase _db;

  /// The id this entity travels under on the wire.
  Future<String> wireIdOf(SyncedEntityKind kind, String localId) async {
    final row = await _idPair(kind, localId: localId);
    return row?.$2 ?? localId;
  }

  /// The local row owning this wire id, or null when the row is new here.
  Future<String?> localIdOf(SyncedEntityKind kind, String wireId) async {
    final row = await _idPair(kind, localId: wireId);
    if (row != null) return row.$1;
    final mapped = await _idPair(kind, serverId: wireId);
    return mapped?.$1;
  }

  /// Translates every reference field of [fields] from local to wire ids,
  /// leaving non-reference fields untouched.
  Future<Map<String, Object?>> outboundFields(
    SyncedEntityKind kind,
    Map<String, Object?> fields,
  ) async {
    final refs = referenceFields[kind] ?? const {};
    final out = Map<String, Object?>.from(fields);
    for (final entry in refs.entries) {
      final value = out[entry.key];
      if (value is String) out[entry.key] = await wireIdOf(entry.value, value);
    }
    return out;
  }

  /// Resolves a wire reference to the local id, falling back to the wire id
  /// itself (the row may be created later in the same revision-ordered batch
  /// under exactly that id).
  Future<String> inboundRef(SyncedEntityKind kind, String wireId) async =>
      await localIdOf(kind, wireId) ?? wireId;

  /// `(local id, server id)` of the row matching [localId] or [serverId].
  Future<(String, String?)?> _idPair(
    SyncedEntityKind kind, {
    String? localId,
    String? serverId,
  }) async {
    assert((localId == null) != (serverId == null));
    switch (kind) {
      case SyncedEntityKind.folder:
        final row =
            await (_db.select(_db.folders)..where(
                  (f) => localId != null
                      ? f.id.equals(localId)
                      : f.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.collection:
        final row =
            await (_db.select(_db.collections)..where(
                  (c) => localId != null
                      ? c.id.equals(localId)
                      : c.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.source:
        final row =
            await (_db.select(_db.sources)..where(
                  (s) => localId != null
                      ? s.id.equals(localId)
                      : s.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.entry:
        final row =
            await (_db.select(_db.entries)..where(
                  (e) => localId != null
                      ? e.id.equals(localId)
                      : e.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.location:
        final row =
            await (_db.select(_db.locations)..where(
                  (l) => localId != null
                      ? l.id.equals(localId)
                      : l.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.downloadRequest:
        final row =
            await (_db.select(_db.downloadRequests)..where(
                  (r) => localId != null
                      ? r.id.equals(localId)
                      : r.serverId.equals(serverId!),
                ))
                .getSingleOrNull();
        return row == null ? null : (row.id, row.serverId);
      case SyncedEntityKind.readingState:
      case SyncedEntityKind.measurement:
        // Keyed by their Entry; they have no id of their own.
        return _idPair(
          SyncedEntityKind.entry,
          localId: localId,
          serverId: serverId,
        );
    }
  }
}
