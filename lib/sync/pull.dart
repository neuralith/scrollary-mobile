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
///
/// **Parents can arrive after their children.** The feed carries each row
/// once, at the revision it *currently* holds, so renaming a Collection moves
/// it behind the Sources, Entries and Locations that reference it. A row
/// whose parent is not local yet is therefore **deferred in memory** and
/// retried after every later page and again at the end of the run, to a
/// fixpoint — every successful apply can unblock another. Two rules make that
/// durable:
///
/// * **The persisted cursor never moves past an unapplied row.** A page
///   commits `min(page's last revision, lowest deferred revision − 1)`, so an
///   interrupted run re-fetches from the first unresolved row and the
///   idempotent upserts converge on the next run.
/// * **At head, what is still waiting is an orphan.** `has_more=false` plus a
///   stalled fixpoint means the referenced parent exists nowhere in the feed:
///   the rows are dropped, reported in [PullResult.orphaned], and the cursor
///   commits at `latest_revision` so a dead row cannot pin it forever.
///
/// A tombstone for a parent takes its deferred children with it (the same
/// cascade the local schema applies to rows that did land).
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
    required this.orphaned,
    required this.orphanedKinds,
    required this.cursor,
    required this.errors,
  });

  final int pages;
  final int applied;

  /// Items not applied: lost the merge, referenced a row this device no
  /// longer holds, or failed individually (listed in [errors]).
  final int skipped;

  /// Rows dropped because the parent they reference exists nowhere in the
  /// feed up to head, or was tombstoned inside it. Silent data loss is the
  /// defect this count exists to make loud.
  final int orphaned;

  /// The entity kinds behind [orphaned], with a count each.
  final Map<String, int> orphanedKinds;

  /// The cursor this run committed — pinned below anything it could not
  /// apply, so the next run is offered those rows again.
  final int cursor;
  final List<String> errors;
}

/// What one incoming row did.
enum _Verdict { applied, skipped, deferred }

/// A row's verdict plus, when it is waiting on something, what it waits for.
///
/// `deferred` means nothing was written: the row cannot exist without that
/// reference. `applied` *with* a [waitingOn] means the row landed but an
/// optional pointer could not be resolved yet — it is retried to fill the
/// pointer in, and never counts as an orphan.
class _Outcome {
  const _Outcome(this.verdict, [this.waitingOn]);

  final _Verdict verdict;
  final (SyncedEntityKind, String)? waitingOn;

  static const applied = _Outcome(_Verdict.applied);
  static const skipped = _Outcome(_Verdict.skipped);

  static _Outcome waitFor(SyncedEntityKind kind, String wireId) =>
      _Outcome(_Verdict.deferred, (kind, wireId));

  static _Outcome appliedWaitingFor(SyncedEntityKind kind, String wireId) =>
      _Outcome(_Verdict.applied, (kind, wireId));
}

/// One row held back, and what it is held back by.
class _Deferred {
  _Deferred(this.item, this.revision, this.waitingOn, {required this.applied});

  final Map<String, Object?> item;
  final int revision;
  (SyncedEntityKind, String) waitingOn;

  /// True once the row itself has landed (an optional pointer is all that is
  /// still missing) — such a row is never an orphan.
  bool applied;

  String get label => (item['entity_type'] as String?) ?? 'tombstone';
}

/// The mutable tally of one `pullAll`.
class _PullRun {
  int pages = 0;
  int applied = 0;
  int skipped = 0;
  int orphaned = 0;
  final List<String> errors = [];
  final Map<String, int> orphanedKinds = {};
  final List<_Deferred> deferred = [];

  void recordOrphan(_Deferred row) {
    if (row.applied) return; // it landed; only an optional pointer is missing
    orphaned += 1;
    orphanedKinds.update(row.label, (count) => count + 1, ifAbsent: () => 1);
  }
}

class SyncPuller {
  SyncPuller(this._repos, this._identity);

  final SyncRepositories _repos;
  final SyncIdentity _identity;

  Future<PullResult> pullAll(SyncTransport transport, {int limit = 200}) async {
    final run = _PullRun();
    var cursor = await _repos.syncState.cursor();
    var committed = cursor;
    var head = cursor;
    var confirmedHead = false;
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
      final latest =
          (reply.body['latest_revision'] as num?)?.toInt() ?? nextCursor;
      final hasMore = reply.body['has_more'] == true;
      if (latest > head) head = latest;
      if (nextCursor > head) head = nextCursor;
      final delivered = changes.isNotEmpty || nextCursor > cursor;
      if (delivered) {
        run.pages += 1;
        await _repos.db.transaction(() async {
          for (final raw in changes) {
            await _offer(run, Map<String, Object?>.from(raw));
          }
          await _settle(run);
          committed = _pinnedCursor(nextCursor, run.deferred);
          await _repos.syncState.setCursor(committed);
        });
        cursor = nextCursor;
        if (changes.isNotEmpty) confirmedHead = false;
      }
      if (delivered && hasMore) continue;
      if (run.deferred.isEmpty || confirmedHead) break;
      // Nothing is called an orphan on one look: a parent may have landed on
      // the service while this run was paging. Ask once more, then decide.
      confirmedHead = true;
    }
    if (run.deferred.isNotEmpty) {
      // Head, and the fixpoint still stalled: these rows name a parent the
      // feed does not contain. Drop them, say so, and let the cursor reach
      // head — a dead row must not pin it forever.
      await _repos.db.transaction(() async {
        for (final waiting in run.deferred) {
          run.recordOrphan(waiting);
        }
        run.deferred.clear();
        committed = head;
        await _repos.syncState.setCursor(committed);
      });
    }
    return PullResult(
      pages: run.pages,
      applied: run.applied,
      skipped: run.skipped,
      orphaned: run.orphaned,
      orphanedKinds: Map.unmodifiable(run.orphanedKinds),
      cursor: committed,
      errors: run.errors,
    );
  }

  /// The cursor a page may commit: never past a row still waiting.
  int _pinnedCursor(int nextCursor, List<_Deferred> deferred) {
    var pinned = nextCursor;
    for (final row in deferred) {
      if (row.revision - 1 < pinned) pinned = row.revision - 1;
    }
    return pinned;
  }

  /// Applies one incoming item, holding it back when it names a parent that
  /// is not local yet.
  Future<void> _offer(_PullRun run, Map<String, Object?> item) async {
    final revision = (item['revision'] as num?)?.toInt() ?? 0;
    _Outcome outcome;
    try {
      outcome = await _applyItem(item);
    } on Exception catch (e) {
      run.skipped += 1;
      run.errors.add('revision $revision: $e');
      return;
    }
    switch (outcome.verdict) {
      case _Verdict.applied:
        run.applied += 1;
        if (outcome.waitingOn != null) {
          run.deferred.add(
            _Deferred(item, revision, outcome.waitingOn!, applied: true),
          );
        }
      case _Verdict.skipped:
        run.skipped += 1;
      case _Verdict.deferred:
        run.deferred.add(
          _Deferred(item, revision, outcome.waitingOn!, applied: false),
        );
    }
    if (item['type'] == 'tombstone') {
      await _cascade(run, Map<String, Object?>.from(item['tombstone']! as Map));
    }
  }

  /// Retries everything deferred until a pass changes nothing. Every apply
  /// can unblock another row, so this loops rather than sweeping once.
  Future<void> _settle(_PullRun run) async {
    var progress = true;
    while (progress) {
      progress = false;
      for (final row in List<_Deferred>.of(run.deferred)) {
        if (!run.deferred.contains(row)) continue; // a cascade took it
        _Outcome outcome;
        try {
          outcome = await _applyItem(row.item);
        } on Exception catch (e) {
          run.skipped += 1;
          run.errors.add('revision ${row.revision}: $e');
          run.deferred.remove(row);
          progress = true;
          continue;
        }
        switch (outcome.verdict) {
          case _Verdict.applied:
            if (!row.applied) {
              run.applied += 1;
              row.applied = true;
              progress = true;
            }
            if (outcome.waitingOn == null) {
              run.deferred.remove(row);
              progress = true;
            } else {
              row.waitingOn = outcome.waitingOn!;
            }
          case _Verdict.skipped:
            run.skipped += 1;
            run.deferred.remove(row);
            progress = true;
          case _Verdict.deferred:
            row.waitingOn = outcome.waitingOn!;
        }
      }
    }
  }

  /// A tombstone for a row nothing here holds takes the children waiting on
  /// it — and, transitively, whatever was waiting on *them*. The same cascade
  /// the local schema applies to rows that did land.
  Future<void> _cascade(_PullRun run, Map<String, Object?> tombstone) async {
    final kind = _syncedKind(tombstone['kind']);
    final wireId = tombstone['entity_id'] as String?;
    if (kind == null || wireId == null) return;
    // The row may have survived the tombstone (a newer local add wins); then
    // its children are not orphans at all, they resolve on the next pass.
    if (await _repos.ids.localIdOf(kind, wireId) != null) return;
    await _dropWaitingOn(run, (kind, wireId));
  }

  Future<void> _dropWaitingOn(
    _PullRun run,
    (SyncedEntityKind, String) gone,
  ) async {
    for (final row in run.deferred.where((d) => d.waitingOn == gone).toList()) {
      run.deferred.remove(row);
      run.recordOrphan(row);
      final own = _identityOf(row.item);
      if (own != null) await _dropWaitingOn(run, own);
    }
  }

  /// `(kind, wire id)` this item *is*, for the transitive cascade. Reading
  /// state and measurements carry no id of their own; nothing waits on them.
  (SyncedEntityKind, String)? _identityOf(Map<String, Object?> item) {
    if (item['type'] == 'tombstone') return null;
    final kind = _syncedKind(item['entity_type']);
    if (kind == null) return null;
    final entity = item['entity'];
    if (entity is! Map) return null;
    final id = entity['id'];
    return id is String ? (kind, id) : null;
  }

  SyncedEntityKind? _syncedKind(Object? name) {
    for (final candidate in SyncedEntityKind.values) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  Future<_Outcome> _applyItem(Map<String, Object?> item) async {
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
    // An entity kind this client does not know — never guessed, and never
    // waited for: no later row can make it applicable.
    return _Outcome.skipped;
  }

  // ---- entities ------------------------------------------------------------

  Future<_Outcome> _applyFolder(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final parentWire = e['parent_id'] as String?;
    final parent = parentWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.folder, parentWire);
    if (parent != null && await _repos.folders.byId(parent) == null) {
      return _Outcome.waitFor(SyncedEntityKind.folder, parentWire!);
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
    return _Outcome.applied;
  }

  Future<_Outcome> _applyCollection(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final folderWire = e['folder_id']! as String;
    final folderId = await _repos.ids.inboundRef(
      SyncedEntityKind.folder,
      folderWire,
    );
    if (await _repos.folders.byId(folderId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.folder, folderWire);
    }
    // The preferred Source is the one reference that points back *into* this
    // Collection's own subtree: waiting for it would deadlock against the
    // Source waiting for this Collection. It lands as null now and is filled
    // in by a later pass instead (V2_SYNC.md §4.2 — a scalar, nulled on
    // delete either side).
    final preferredWire = e['preferred_source_id'] as String?;
    final preferred = preferredWire == null
        ? null
        : await _repos.ids.localIdOf(SyncedEntityKind.source, preferredWire);
    await _repos.collections.applyRemoteCollection(
      id: local ?? wireId,
      serverId: wireId,
      folderId: folderId,
      name: e['name']! as String,
      detectedTitle: (e['detected_title'] as String?) ?? '',
      orderingBasis: e['ordering_basis']! as String,
      lifecycle: e['lifecycle']! as String,
      preferredSourceId: preferred,
      // Opaque preference tokens: taken as written and never parsed here. A
      // value this build cannot read is the reader's to resolve to "unset"
      // (`parseEntrySort`, `captureModeFromName`), which is what lets a device
      // on an older build hold a newer one's answer without losing it.
      captureMode: (e['capture_mode'] as String?) ?? '',
      entrySort: (e['entry_sort'] as String?) ?? '',
      sortKey: (e['sort_key']! as num).toInt(),
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return preferredWire != null && preferred == null
        ? _Outcome.appliedWaitingFor(SyncedEntityKind.source, preferredWire)
        : _Outcome.applied;
  }

  Future<_Outcome> _applySource(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final collectionWire = e['collection_id']! as String;
    final collectionId = await _repos.ids.inboundRef(
      SyncedEntityKind.collection,
      collectionWire,
    );
    if (await _repos.collections.byId(collectionId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.collection, collectionWire);
    }
    // Sideways within the same kind: a resolution chain could be offered in
    // either order, so this pointer is filled in later rather than waited on.
    final resolvedWire = e['resolved_into_source_id'] as String?;
    final resolvedInto = resolvedWire == null
        ? null
        : await _repos.ids.localIdOf(SyncedEntityKind.source, resolvedWire);
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
    return resolvedWire != null && resolvedInto == null
        ? _Outcome.appliedWaitingFor(SyncedEntityKind.source, resolvedWire)
        : _Outcome.applied;
  }

  Future<_Outcome> _applyEntry(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final folderWire = e['folder_id'] as String?;
    final folderId = folderWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.folder, folderWire);
    if (collectionId != null &&
        await _repos.collections.byId(collectionId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.collection, collectionWire!);
    }
    if (folderId != null && await _repos.folders.byId(folderId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.folder, folderWire!);
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
    return _Outcome.applied;
  }

  Future<_Outcome> _applyLocation(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final entryWire = e['entry_id']! as String;
    final entryId = await _repos.ids.inboundRef(
      SyncedEntityKind.entry,
      entryWire,
    );
    if (await _repos.entries.byId(entryId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.entry, entryWire);
    }
    final sourceWire = e['source_id'] as String?;
    final sourceId = sourceWire == null
        ? null
        : await _repos.ids.inboundRef(SyncedEntityKind.source, sourceWire);
    if (sourceId != null &&
        await _repos.collections.sourceById(sourceId) == null) {
      return _Outcome.waitFor(SyncedEntityKind.source, sourceWire!);
    }
    await _repos.entries.applyRemoteLocation(
      id: local ?? wireId,
      serverId: wireId,
      entryId: entryId,
      sourceId: sourceId,
      url: e['url']! as String,
      urlKey: urlKey,
      sourceLabel: (e['source_label'] as String?) ?? '',
      sourceNumber: (e['source_number'] as num?)?.toDouble(),
      publishedAt: _time(e['published_at']),
      discoveredAt: _time(e['discovered_at'])!,
      discoveryBasis: (e['discovery_basis'] as String?) ?? '',
      lifecycle: e['lifecycle']! as String,
      revision: (e['revision']! as num).toInt(),
      updatedAt: updatedAt,
    );
    return _Outcome.applied;
  }

  Future<_Outcome> _applyReadingState(Map<String, Object?> e) async {
    final entryWire = e['entry_id']! as String;
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      entryWire,
    );
    if (entryLocal == null) {
      return _Outcome.waitFor(SyncedEntityKind.entry, entryWire);
    }
    final updatedAt = _time(e['updated_at'])!;
    final current = await _repos.readingStates.stateOf(entryLocal);
    // An absent row reads as unread with an epoch clock; a stored row carries
    // its real clock. Whole-row LWW (V2-D6).
    final localClock = current.updatedAt;
    if (!remoteRowWins(localClock: localClock, remoteClock: updatedAt)) {
      return _Outcome.skipped;
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
    return _Outcome.applied;
  }

  Future<_Outcome> _applyMeasurement(Map<String, Object?> e) async {
    final entryWire = e['entry_id']! as String;
    final sourceWire = e['source_id']! as String;
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      entryWire,
    );
    if (entryLocal == null) {
      return _Outcome.waitFor(SyncedEntityKind.entry, entryWire);
    }
    final sourceLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.source,
      sourceWire,
    );
    if (sourceLocal == null) {
      return _Outcome.waitFor(SyncedEntityKind.source, sourceWire);
    }
    final observedAt = _time(e['observed_at'])!;
    final existing = await _repos.measurements.of(entryLocal, sourceLocal);
    if (existing != null &&
        !remoteRowWins(
          localClock: existing.observedAt,
          remoteClock: observedAt,
        )) {
      return _Outcome.skipped;
    }
    await _repos.measurements.applyRemote(
      entryId: entryLocal,
      sourceId: sourceLocal,
      fraction: (e['fraction']! as num).toDouble(),
      observedAt: observedAt,
      revision: (e['revision']! as num).toInt(),
    );
    return _Outcome.applied;
  }

  Future<_Outcome> _applyDownloadRequest(Map<String, Object?> e) async {
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
      return _Outcome.skipped;
    }
    final entryWire = e['entry_id']! as String;
    final entryLocal = await _repos.ids.localIdOf(
      SyncedEntityKind.entry,
      entryWire,
    );
    if (entryLocal == null) {
      return _Outcome.waitFor(SyncedEntityKind.entry, entryWire);
    }
    final locationWire = e['location_id'] as String?;
    final locationLocal = locationWire == null
        ? null
        : await _repos.ids.localIdOf(SyncedEntityKind.location, locationWire);
    if (locationWire != null && locationLocal == null) {
      return _Outcome.waitFor(SyncedEntityKind.location, locationWire);
    }
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
    return _Outcome.applied;
  }

  // ---- tombstones ----------------------------------------------------------

  Future<_Outcome> _applyTombstone(Map<String, Object?> t) async {
    final kindRaw = t['kind'];
    final deletedAt = _time(t['deleted_at'])!;
    final kind = _syncedKind(kindRaw);
    if (kind == null) return _Outcome.skipped;
    final wireId = t['entity_id']! as String;
    switch (kind) {
      case SyncedEntityKind.folder:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        final row = await _repos.folders.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.folders.applyRemoteDelete(local);
      case SyncedEntityKind.collection:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        final row = await _repos.collections.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.collections.applyRemoteCollectionDelete(local);
      case SyncedEntityKind.source:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        final row = await _repos.collections.sourceById(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.collections.applyRemoteSourceDelete(local);
      case SyncedEntityKind.entry:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        final row = await _repos.entries.byId(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.entries.applyRemoteEntryDelete(local);
      case SyncedEntityKind.location:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        final row = await _repos.entries.locationById(local);
        if (row == null ||
            !tombstoneWins(localClock: row.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.entries.applyRemoteLocationDelete(local);
      case SyncedEntityKind.readingState:
        final local = await _repos.ids.localIdOf(
          SyncedEntityKind.entry,
          wireId,
        );
        if (local == null) return _Outcome.skipped;
        final state = await _repos.readingStates.stateOf(local);
        if (!tombstoneWins(localClock: state.updatedAt, deletedAt: deletedAt)) {
          return _Outcome.skipped;
        }
        await _repos.readingStates.applyRemoteDelete(local);
      case SyncedEntityKind.measurement:
        final sourceWire = t['source_id'] as String?;
        if (sourceWire == null) {
          // The scope is part of the key (I12). An unscoped measurement
          // tombstone cannot name what it deletes — never wipe an Entry's
          // measurements wholesale on one.
          return _Outcome.skipped;
        }
        final entryLocal = await _repos.ids.localIdOf(
          SyncedEntityKind.entry,
          wireId,
        );
        final sourceLocal = await _repos.ids.localIdOf(
          SyncedEntityKind.source,
          sourceWire,
        );
        if (entryLocal == null || sourceLocal == null) return _Outcome.skipped;
        final existing = await _repos.measurements.of(entryLocal, sourceLocal);
        if (existing == null ||
            !tombstoneWins(
              localClock: existing.observedAt,
              deletedAt: deletedAt,
            )) {
          return _Outcome.skipped;
        }
        await _repos.measurements.applyRemoteDelete(
          entryId: entryLocal,
          sourceId: sourceLocal,
        );
      case SyncedEntityKind.downloadRequest:
        final local = await _repos.ids.localIdOf(kind, wireId);
        if (local == null) return _Outcome.skipped;
        await _repos.downloadRequests.applyRemoteDelete(local);
    }
    return _Outcome.applied;
  }

  DateTime? _time(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
