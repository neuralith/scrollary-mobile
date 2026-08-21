/// Provisional-identity canonicalisation (roadmap G3, V2_SYNC.md §4.5).
///
/// Three ways a local provisional id meets canonical identity:
///
/// 1. **Arbitration** — the client submits evidence, the server answers with
///    mappings. [applyMappings].
/// 2. **Implicit collision during pull** — an incoming server row and a
///    provisional local row hold the same natural identity (a Source's
///    `(host, path_key)`, a Location's `url_key`, the root Folder's kind).
///    The puller detects it and calls [adoptServerRow].
/// 3. **A duplicate pair** — a mapping (or collision) names a canonical id
///    for which a *different* local row already exists. [mergeDuplicate]
///    keeps the elder local row (the one local state may depend on), rewrites
///    every reference, and deletes the duplicate locally.
///
/// Local ids are never rewritten and file paths are never touched — the
/// canonical id is only ever *recorded beside* the surviving local id.
library;

import '../domain/sync_kinds.dart';
import '../recognition/evidence.dart';
import 'repositories.dart';
import 'transport.dart';

class SyncIdentity {
  SyncIdentity(this._repos);

  final SyncRepositories _repos;

  /// Submits one arbitration request and applies the outcome. Returns the
  /// parsed response; `unresolved` is a first-class answer, not an error.
  Future<ArbitrationResponse> arbitrate(
    SyncTransport transport,
    ArbitrationRequest request,
  ) async {
    final reply = await transport.arbitrate(request.toJson());
    if (!reply.ok) {
      throw SyncTransportException(
        'arbitrate: HTTP ${reply.status} ${reply.errorCode ?? ''}',
      );
    }
    final response = ArbitrationResponse.fromJson(reply.body);
    if (response.isResolved) await applyMappings(response.mappings);
    return response;
  }

  /// Records each canonical id beside its provisional local row, merging
  /// duplicates where the canonical identity already has a local row.
  Future<void> applyMappings(List<IdentityMapping> mappings) async {
    for (final mapping in mappings) {
      final kind = _kindOf(mapping.kind);
      final provisional = await _repos.ids.localIdOf(
        kind,
        mapping.provisionalId,
      );
      if (provisional == null) continue; // already merged away, or unknown
      final canonicalLocal = await _repos.ids.localIdOf(
        kind,
        mapping.canonicalId,
      );
      if (canonicalLocal != null && canonicalLocal != provisional) {
        await mergeDuplicate(
          kind,
          survivor: provisional,
          duplicate: canonicalLocal,
        );
      }
      await _applyServerId(kind, provisional, mapping.canonicalId);
    }
  }

  /// Marks [localId] as owning the canonical [serverId].
  Future<void> _applyServerId(
    SyncedEntityKind kind,
    String localId,
    String serverId,
  ) async {
    switch (kind) {
      case SyncedEntityKind.folder:
        await _repos.folders.applyServerId(localId, serverId);
      case SyncedEntityKind.collection:
        await _repos.collections.applyCollectionServerId(localId, serverId);
      case SyncedEntityKind.source:
        await _repos.collections.applySourceServerId(localId, serverId);
      case SyncedEntityKind.entry:
        await _repos.entries.applyEntryServerId(localId, serverId);
      case SyncedEntityKind.location:
        await _repos.entries.applyLocationServerId(localId, serverId);
      case SyncedEntityKind.downloadRequest:
        await _repos.downloadRequests.applyServerId(localId, serverId);
      case SyncedEntityKind.readingState:
      case SyncedEntityKind.measurement:
        break; // keyed by their Entry; nothing of their own to mark
    }
  }

  /// Exposed for the puller: record canonical identity on a surviving row.
  Future<void> adoptServerRow(
    SyncedEntityKind kind,
    String localId,
    String serverId,
  ) => _applyServerId(kind, localId, serverId);

  /// Keeps [survivor], repoints every local reference from [duplicate] to it,
  /// and deletes the duplicate row locally (a local tombstone — never an
  /// outbox intent; the server never asked for this and never hears of it).
  Future<void> mergeDuplicate(
    SyncedEntityKind kind, {
    required String survivor,
    required String duplicate,
  }) async {
    switch (kind) {
      case SyncedEntityKind.folder:
        await _repos.folders.rewriteFolderParentRefs(duplicate, survivor);
        await _repos.collections.rewriteCollectionFolderRefs(
          duplicate,
          survivor,
        );
        await _repos.entries.rewriteEntryFolderRefs(duplicate, survivor);
        await _repos.folders.applyRemoteDelete(duplicate);
      case SyncedEntityKind.collection:
        await _repos.collections.rewriteSourceCollectionRefs(
          duplicate,
          survivor,
        );
        await _repos.entries.rewriteEntryCollectionRefs(duplicate, survivor);
        await _repos.collections.applyRemoteCollectionDelete(duplicate);
      case SyncedEntityKind.source:
        await _repos.collections.rewriteSourceRefs(duplicate, survivor);
        await _repos.entries.rewriteLocationSourceRefs(duplicate, survivor);
        await _repos.measurements.rewriteSourceRef(duplicate, survivor);
        await _repos.collections.applyRemoteSourceDelete(duplicate);
      case SyncedEntityKind.entry:
        await _repos.entries.rewriteLocationEntryRefs(duplicate, survivor);
        await _repos.readingStates.rewriteEntryRef(duplicate, survivor);
        await _repos.measurements.rewriteEntryRef(duplicate, survivor);
        await _repos.downloadRequests.rewriteEntryRefs(duplicate, survivor);
        await _repos.entries.applyRemoteEntryDelete(duplicate);
      case SyncedEntityKind.location:
        await _repos.downloadRequests.rewriteLocationRefs(duplicate, survivor);
        await _repos.entries.applyRemoteLocationDelete(duplicate);
      case SyncedEntityKind.downloadRequest:
        await _repos.downloadRequests.applyRemoteDelete(duplicate);
      case SyncedEntityKind.readingState:
      case SyncedEntityKind.measurement:
        break; // keyed rows merge through their Entry
    }
  }

  SyncedEntityKind _kindOf(IdentityKind kind) {
    switch (kind) {
      case IdentityKind.collection:
        return SyncedEntityKind.collection;
      case IdentityKind.source:
        return SyncedEntityKind.source;
      case IdentityKind.entry:
        return SyncedEntityKind.entry;
      case IdentityKind.location:
        return SyncedEntityKind.location;
    }
  }
}
