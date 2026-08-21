/// The pull half of sync (roadmap G2): `GET /changes` applied through the
/// repositories, one page per database transaction, cursor advanced in that
/// same transaction — so a kill between pages resumes exactly at the last
/// committed page and a kill inside a page repeats it idempotently.
///
/// Every row decision goes through the merge rules (merge.dart). Incoming
/// rows are translated to local identity first (ids.dart, identity.dart):
/// a wire id resolves to the local row that owns it, a natural-identity
/// collision merges onto the provisional local row rather than inserting a
/// duplicate, and a genuinely new row adopts the server id as its local id.
library;

import '../domain/sync_kinds.dart';
import 'identity.dart';
import 'merge.dart';
import 'repositories.dart';
import 'transport.dart';

class PullResult {
  const PullResult({
    required this.pages,
    required this.applied,
    required this.skipped,
    required this.cursor,
    required this.errors,
  });

  final int pages;
  final int applied;

  /// Items not applied: lost the merge, referenced a row this device no
  /// longer holds, or failed individually (listed in [errors]).
  final int skipped;
  final int cursor;
  final List<String> errors;
}

class SyncPuller {
  SyncPuller(this._repos, this._identity);

  final SyncRepositories _repos;
  final SyncIdentity _identity;

  Future<PullResult> pullAll(SyncTransport transport, {int limit = 200}) async {
    var pages = 0;
    var applied = 0;
    var skipped = 0;
    final errors = <String>[];
    var cursor = await _repos.syncState.cursor();
    while (true) {
      final reply = await transport.getChanges(cursor: cursor, limit: limit);
      if (!reply.ok) {
        throw SyncTransportException(
          'changes: HTTP ${reply.status} ${reply.errorCode ?? ''}',
        );
      }
      final changes = (reply.body['changes'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>();
      final nextCursor = (reply.body['next_cursor'] as num).toInt();
      final hasMore = reply.body['has_more'] == true;
      if (changes.isEmpty && nextCursor <= cursor) break;
      pages += 1;
      await _repos.db.transaction(() async {
        for (final raw in changes) {
          final item = Map<String, Object?>.from(raw);
          try {
            final outcome = await _applyItem(item);
            if (outcome) {
              applied += 1;
            } else {
              skipped += 1;
            }
          } on Exception catch (e) {
            skipped += 1;
            errors.add('revision ${item['revision']}: $e');
          }
        }
        await _repos.syncState.setCursor(nextCursor);
      });
      cursor = nextCursor;
      if (!hasMore) break;
    }
    return PullResult(
      pages: pages,
      applied: applied,
      skipped: skipped,
      cursor: cursor,
      errors: errors,
    );
  }

  Future<bool> _applyItem(Map<String, Object?> item) async {
    final type = item['type'];
    if (type == 'tombstone') {
      return _applyTombstone(
        Map<String, Object?>.from(item['tombstone']! as Map),
      );
    }
    final entity = Map<String, Object?>.from(item['entity']! as Map);
    switch (item['entity_type']) {
      case 'folder':
        return _applyFolder(entity);
      case 'collection':
        return _applyCollection(entity);
      case 'source':
        return _applySource(entity);
      case 'entry':
        return _applyEntry(entity);
      case 'location':
        return _applyLocation(entity);
      case 'readingState':
        return _applyReadingState(entity);
      case 'measurement':
        return _applyMeasurement(entity);
      case 'downloadRequest':
        return _applyDownloadRequest(entity);
    }
    return false; // an entity kind this client does not know — never guessed
  }

  // ---- entities ------------------------------------------------------------

  Future<bool> _applyFolder(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    final kind = e['kind']! as String;
    var local = await _repos.ids.localIdOf(SyncedEntityKind.folder, wireId);
    if (local == null && kind == 'root') {
      // The one-root index makes the root a natural identity: map the
      // server's root onto the local one at first contact (V2-D21).
      local = (await _repos.folders.ensureRoot()).id;
    }
    final updatedAt = _time(e['updated_at'])!;
    final existing = local == null ? null : await _repos.folders.byId(local);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.updatedAt,
          remoteClock: updatedAt,
        )) {
      await _identity.adoptServerRow(SyncedEntityKind.folder, local!, wireId);
      return false;
    }
    final parentWire = e['parent_id'] as String?;
    final parent = parentWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.folder, parentWire);
    if (parent != null && await _repos.folders.byId(parent) == null) {
      return false; // parent unknown here; a later round converges
    }
    await _repos.folders.applyRemote(
      id: local ?? wireId,
      serverId: wireId,
      parentId: parent,
      kind: kind,
      name: e['name']! as String,
      sortKey: (e['sort_key']! as num).toInt(),
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applyCollection(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    final local = await _repos.ids.localIdOf(
      SyncedEntityKind.collection,
      wireId,
    );
    final updatedAt = _time(e['updated_at'])!;
    final existing = local == null
        ? null
        : await _repos.collections.byId(local);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.updatedAt,
          remoteClock: updatedAt,
        )) {
      await _identity.adoptServerRow(
        SyncedEntityKind.collection,
        local!,
        wireId,
      );
      return false;
    }
    final folderId = await _repos.ids.inboundRef(
      SyncedEntityKind.folder,
      e['folder_id']! as String,
    );
    if (await _repos.folders.byId(folderId) == null) return false;
    final preferredWire = e['preferred_source_id'] as String?;
    final preferred = preferredWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.source, preferredWire);
    await _repos.collections.applyRemoteCollection(
      id: local ?? wireId,
      serverId: wireId,
      folderId: folderId,
      name: e['name']! as String,
      detectedTitle: (e['detected_title'] as String?) ?? '',
      orderingBasis: e['ordering_basis']! as String,
      lifecycle: e['lifecycle']! as String,
      preferredSourceId: preferred,
      sortKey: (e['sort_key']! as num).toInt(),
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applySource(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    final host = e['host']! as String;
    final pathKey = e['path_key']! as String;
    var local = await _repos.ids.localIdOf(SyncedEntityKind.source, wireId);
    if (local == null) {
      // Natural-identity collision: a provisional local Source holding the
      // same (host, path_key) is this same Source — merge, never duplicate
      // (the local unique index would refuse the insert anyway).
      final collided = await _repos.collections.sourceByIdentity(host, pathKey);
      if (collided != null) local = collided.id;
    }
    final updatedAt = _time(e['updated_at'])!;
    final existing = local == null
        ? null
        : await _repos.collections.sourceById(local);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.updatedAt,
          remoteClock: updatedAt,
        )) {
      await _identity.adoptServerRow(SyncedEntityKind.source, local!, wireId);
      return false;
    }
    final collectionId = await _repos.ids.inboundRef(
      SyncedEntityKind.collection,
      e['collection_id']! as String,
    );
    if (await _repos.collections.byId(collectionId) == null) return false;
    final resolvedWire = e['resolved_into_source_id'] as String?;
    final resolvedInto = resolvedWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.source, resolvedWire);
    await _repos.collections.applyRemoteSource(
      id: local ?? wireId,
      serverId: wireId,
      collectionId: collectionId,
      host: host,
      pathKey: pathKey,
      language: (e['language'] as String?) ?? '',
      lifecycle: e['lifecycle']! as String,
      resolvedIntoSourceId: resolvedInto,
      firstSeenAt: _time(e['first_seen_at'])!,
      lastSeenAt: _time(e['last_seen_at'])!,
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applyEntry(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    var local = await _repos.ids.localIdOf(SyncedEntityKind.entry, wireId);
    final collectionWire = e['collection_id'] as String?;
    final ordinal = (e['ordinal'] as num?)?.toDouble();
    final collectionId = collectionWire == null
        ? null
        : await _repos.ids.inboundRef(
            SyncedEntityKind.collection,
            collectionWire,
          );
    if (local == null && collectionId != null && ordinal != null) {
      // I8 makes (collection, ordinal) unique locally, and under V2-D16 an
      // equal ordinal in the same Collection IS the same logical Entry.
      final siblings = await _repos.entries.entriesOf(collectionId);
      for (final sibling in siblings) {
        if (sibling.ordinal == ordinal) {
          local = sibling.id;
          break;
        }
      }
    }
    final updatedAt = _time(e['updated_at'])!;
    final existing = local == null ? null : await _repos.entries.byId(local);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.updatedAt,
          remoteClock: updatedAt,
        )) {
      await _identity.adoptServerRow(SyncedEntityKind.entry, local!, wireId);
      return false;
    }
    final folderWire = e['folder_id'] as String?;
    final folderId = folderWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.folder, folderWire);
    if (collectionId != null &&
        await _repos.collections.byId(collectionId) == null) {
      return false;
    }
    if (folderId != null && await _repos.folders.byId(folderId) == null) {
      return false;
    }
    await _repos.entries.applyRemoteEntry(
      id: local ?? wireId,
      serverId: wireId,
      collectionId: collectionId,
      folderId: folderId,
      ordinal: ordinal,
      placement: e['placement']! as String,
      title: (e['title'] as String?) ?? '',
      sortKey: (e['sort_key']! as num).toInt(),
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applyLocation(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    final urlKey = e['url_key']! as String;
    var local = await _repos.ids.localIdOf(SyncedEntityKind.location, wireId);
    if (local == null) {
      final collided = await _repos.entries.locationByUrlKey(urlKey);
      if (collided != null) local = collided.id;
    }
    final updatedAt = _time(e['updated_at'])!;
    final existing = local == null
        ? null
        : await _repos.entries.locationById(local);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.updatedAt,
          remoteClock: updatedAt,
        )) {
      await _identity.adoptServerRow(SyncedEntityKind.location, local!, wireId);
      return false;
    }
    final entryId = await _repos.ids.inboundRef(
      SyncedEntityKind.entry,
      e['entry_id']! as String,
    );
    if (await _repos.entries.byId(entryId) == null) return false;
    final sourceWire = e['source_id'] as String?;
    final sourceId = sourceWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.source, sourceWire);
    await _repos.entries.applyRemoteLocation(
      id: local ?? wireId,
      serverId: wireId,
      entryId: entryId,
      sourceId: sourceId,
      url: e['url']! as String,
      urlKey: urlKey,
      sourceLabel: (e['source_label'] as String?) ?? '',
      sourceNumber: (e['source_number'] as num?)?.toDouble(),
      discoveredAt: _time(e['discovered_at'])!,
      discoveryBasis: (e['discovery_basis'] as String?) ?? '',
      lifecycle: e['lifecycle']! as String,
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applyReadingState(Map<String, Object?> e) async {
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      e['entry_id']! as String,
    );
    if (entryLocal == null) return false;
    final updatedAt = _time(e['updated_at'])!;
    final current = await _repos.readingStates.stateOf(entryLocal);
    // An absent row reads as unread with an epoch clock; a stored row carries
    // its real clock. Whole-row LWW (V2-D6).
    final localClock = current.updatedAt;
    if (!remoteRowWins(localClock: localClock, remoteClock: updatedAt)) {
      return false;
    }
    await _repos.readingStates.applyRemote(
      entryId: entryLocal,
      status: e['status']! as String,
      firstOpenedAt: _time(e['first_opened_at']),
      lastReadAt: _time(e['last_read_at']),
      completedAt: _time(e['completed_at']),
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _applyMeasurement(Map<String, Object?> e) async {
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      e['entry_id']! as String,
    );
    final sourceLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.source,
      e['source_id']! as String,
    );
    if (entryLocal == null || sourceLocal == null) return false;
    final observedAt = _time(e['observed_at'])!;
    final existing = await _repos.measurements.of(entryLocal, sourceLocal);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.observedAt,
          remoteClock: observedAt,
        )) {
      return false;
    }
    await _repos.measurements.applyRemote(
      entryId: entryLocal,
      sourceId: sourceLocal,
      fraction: (e['fraction']! as num).toDouble(),
      observedAt: observedAt,
      revision: (e['revision']! as num).toInt(),
    );
    return true;
  }

  Future<bool> _applyDownloadRequest(Map<String, Object?> e) async {
    final wireId = e['id']! as String;
    final local = await _repos.ids.localIdOf(
      SyncedEntityKind.downloadRequest,
      wireId,
    );
    final existing = local == null
        ? null
        : await _repos.downloadRequests.byId(local);
    const terminal = {'completed', 'failed', 'cancelled'};
    final incomingState = e['state']! as String;
    if (existing != null &&
        terminal.contains(existing.state) &&
        !terminal.contains(incomingState)) {
      // This device already resolved the request; its pending resolve intent
      // is the newer fact. Never regress a terminal state from a stale pull.
      return false;
    }
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      e['entry_id']! as String,
    );
    if (entryLocal == null) return false;
    final locationWire = e['location_id'] as String?;
    final locationLocal = locationWire == null
        ? null
        : await _repos.ids.localIdOf(SyncedEntityKind.location, locationWire);
    await _repos.downloadRequests.applyRemote(
      id: local ?? wireId,
      serverId: wireId,
      entryId: entryLocal,
      locationId: locationLocal,
      state: incomingState,
      idempotencyKey: (e['idempotency_key'] as String?) ?? '',
      createdBy: (e['created_by'] as String?) ?? '',
      createdAt: _time(e['created_at'])!,
      claimedByDevice: (e['claimed_by_device'] as String?) ?? '',
      claimedAt: _time(e['claimed_at']),
      resolvedAt: _time(e['resolved_at']),
      failureReason: (e['failure_reason'] as String?) ?? '',
      revision: (e['revision']! as num).toInt(),
    );
    return true;
  }

  // ---- tombstones ----------------------------------------------------------

  Future<bool> _applyTombstone(Map<String, Object?> t) async {
    final kindRaw = t['kind'];
    final deletedAt = _time(t['deleted_at'])!;
    SyncedEntityKind? kind;
    for (final candidate in SyncedEntityKind.values) {
      if (candidate.name == kindRaw) kind = candidate;
    }
    if (kind == null) return false;
    final wireId = t['entity_id']! as String;
    switch (kind) {
      case SyncedEntityKind.folder:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        final row = await _repos.folders.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.folders.applyRemoteDelete(local);
      case SyncedEntityKind.collection:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        final row = await _repos.collections.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.collections.applyRemoteCollectionDelete(local);
      case SyncedEntityKind.source:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        final row = await _repos.collections.sourceById(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.collections.applyRemoteSourceDelete(local);
      case SyncedEntityKind.entry:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        final row = await _repos.entries.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.entries.applyRemoteEntryDelete(local);
      case SyncedEntityKind.location:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        final row = await _repos.entries.locationById(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.entries.applyRemoteLocationDelete(local);
      case SyncedEntityKind.readingState:
        final local = await _repos.ids.localIdOf(
          SyncedEntityKind.entry,
          wireId,
        );
        if (local == null) return false;
        final state = await _repos.readingStates.stateOf(local);
        if (!tombstoneWins(localClock: state.updatedAt, deletedAt: deletedAt)) {
          return false;
        }
        await _repos.readingStates.applyRemoteDelete(local);
      case SyncedEntityKind.measurement:
        final sourceWire = t['source_id'] as String?;
        if (sourceWire == null) {
          // The scope is part of the key (I12). An unscoped measurement
          // tombstone cannot name what it deletes — never wipe an Entry's
          // measurements wholesale on one.
          return false;
        }
        final entryLocal = await _repos.ids.localIdOf(
          SyncedEntityKind.entry,
          wireId,
        );
        final sourceLocal = await _repos.ids.localIdOf(
          SyncedEntityKind.source,
          sourceWire,
        );
        if (entryLocal == null || sourceLocal == null) return false;
        final existing = await _repos.measurements.of(entryLocal, sourceLocal);
        if (existing == null ||
            !tombstoneWins(
              localClock: existing.observedAt,
              deletedAt: deletedAt,
            )) {
          return false;
        }
        await _repos.measurements.applyRemoteDelete(
          entryId: entryLocal,
          sourceId: sourceLocal,
        );
      case SyncedEntityKind.downloadRequest:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return false;
        await _repos.downloadRequests.applyRemoteDelete(local);
    }
    return true;
  }

  DateTime? _time(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
