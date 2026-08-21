/// The pull half (G2): bootstrap, LWW, interruption safety, scoped
/// tombstones, folder-delete replay, and two-client convergence.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/folder.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  setUp(() async {
    h = await SyncHarness.start();
  });

  tearDown(() => h.stop());

  /// Seeds a full server-side library: root, folder, collection, source,
  /// entry, location, reading state, measurement.
  Map<String, String> seedServerLibrary() {
    final at = DateTime.utc(2026, 8, 21, 9);
    h.backend.seed('folder', {
      'id': 'srv-root',
      'parent_id': null,
      'kind': 'root',
      'name': 'Library',
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('folder', {
      'id': 'srv-folder',
      'parent_id': 'srv-root',
      'kind': 'user',
      'name': 'Weekly',
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('collection', {
      'id': 'srv-collection',
      'folder_id': 'srv-folder',
      'name': 'Quiet Harbour',
      'detected_title': 'Quiet Harbour',
      'ordering_basis': 'explicitNumericIndex',
      'lifecycle': 'active',
      'preferred_source_id': null,
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('source', {
      'id': 'srv-source',
      'collection_id': 'srv-collection',
      'host': 'reading.example',
      'path_key': '/works/quiet-harbour',
      'language': 'en',
      'lifecycle': 'active',
      'resolved_into_source_id': null,
      'first_seen_at': at.toIso8601String(),
      'last_seen_at': at.toIso8601String(),
    }, updatedAt: at);
    h.backend.seed('entry', {
      'id': 'srv-entry',
      'collection_id': 'srv-collection',
      'folder_id': null,
      'ordinal': 101,
      'placement': 'placed',
      'title': 'Part 101',
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('location', {
      'id': 'srv-location',
      'entry_id': 'srv-entry',
      'source_id': 'srv-source',
      'url': 'https://reading.example/works/quiet-harbour/101',
      'url_key': 'https://reading.example/works/quiet-harbour/101',
      'source_label': 'Part 101',
      'source_number': 101,
      'discovered_at': at.toIso8601String(),
      'discovery_basis': 'listing',
      'lifecycle': 'active',
    }, updatedAt: at);
    h.backend.seed('readingState', {
      'entry_id': 'srv-entry',
      'status': 'reading',
      'first_opened_at': at.toIso8601String(),
      'last_read_at': at.toIso8601String(),
      'completed_at': null,
    }, updatedAt: at);
    h.backend.seed('measurement', {
      'entry_id': 'srv-entry',
      'source_id': 'srv-source',
      'fraction': 0.4,
      'observed_at': at.toIso8601String(),
    }, key: 'srv-entry|srv-source');
    return {'entry': 'srv-entry', 'source': 'srv-source'};
  }

  test('bootstrap pull builds the library and maps the root', () async {
    final localRoot = await h.folders.ensureRoot();
    seedServerLibrary();

    final outcome = await h.engine.syncOnce(h.transport);
    expect(outcome.succeeded, isTrue);
    expect(outcome.pulled!.errors, isEmpty);

    // The server's root mapped onto the local root — no second root row.
    final root = await h.folders.byId(localRoot.id);
    expect(root!.serverId, 'srv-root');
    final rootMatches = await (h.db.select(
      h.db.folders,
    )..where((f) => f.kind.equals(FolderKind.root.name))).get();
    expect(rootMatches, hasLength(1));

    // Children hang off the LOCAL root id, not the wire id.
    final weekly = await h.folders.byId('srv-folder');
    expect(weekly!.parentId, localRoot.id);

    final collection = await h.collections.byId('srv-collection');
    expect(collection!.folderId, 'srv-folder');
    final entry = await h.entries.byId('srv-entry');
    expect(entry!.ordinal, 101);
    final location = await h.entries.locationById('srv-location');
    expect(location!.entryId, 'srv-entry');
    final state = await h.readingStates.stateOf('srv-entry');
    expect(state.status.name, 'reading');
    final measurement = await h.measurements.of('srv-entry', 'srv-source');
    expect(measurement!.fraction, 0.4);

    final status = await h.engine.status();
    expect(status.cursor, h.backend.revision);
  });

  test('an older incoming row never clobbers a newer local write', () async {
    seedServerLibrary();
    await h.engine.syncOnce(h.transport);

    // Local rename AFTER the server row's clock.
    h.clockValue = DateTime.utc(2026, 8, 21, 12);
    await h.collections.rename('srv-collection', 'Harbour, Renamed');

    // The server still carries the older row; pulling it again (cursor reset
    // simulates a re-delivered page) must not undo the rename.
    await h.syncState.setCursor(0);
    final outcome = await h.engine.syncOnce(h.transport);
    expect(outcome.succeeded, isTrue);

    final collection = await h.collections.byId('srv-collection');
    expect(collection!.name, 'Harbour, Renamed');

    // And once the rename lands server-side, a newer server edit wins here.
    h.backend.seed('collection', {
      ...h.backend.kindRows('collection')['srv-collection']!,
      'name': 'Harbour, From Elsewhere',
    }, updatedAt: DateTime.utc(2026, 8, 21, 13));
    await h.engine.syncOnce(h.transport);
    final after = await h.collections.byId('srv-collection');
    expect(after!.name, 'Harbour, From Elsewhere');
  });

  test(
    'an interrupted pull resumes at the last committed page',
    () async {
      seedServerLibrary();
      // Force paging and kill the second page's request mid-flight.
      h.backend.dieOnChangesRequest = 2;

      final first = await h.engine.syncOnce(h.transport, pullLimit: 3);
      expect(first.succeeded, isFalse);
      final cursorAfterKill = await h.syncState.cursor();
      expect(cursorAfterKill, greaterThan(0));
      expect(cursorAfterKill, lessThan(h.backend.revision));

      h.backend.dieOnChangesRequest = 0;
      final second = await h.engine.syncOnce(h.transport);
      expect(second.succeeded, isTrue);
      expect(await h.syncState.cursor(), h.backend.revision);
      expect(await h.collections.byId('srv-collection'), isNotNull);
      // Idempotent re-application: still exactly one of everything.
      final entries = await h.entries.entriesOf('srv-collection');
      expect(entries, hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'a measurement tombstone deletes its scope and only its scope',
    () async {
      final ids = seedServerLibrary();
      h.backend.seed('source', {
        'id': 'srv-source-b',
        'collection_id': 'srv-collection',
        'host': 'mirror.example',
        'path_key': '/works/quiet-harbour',
        'language': 'tr',
        'lifecycle': 'active',
        'resolved_into_source_id': null,
        'first_seen_at': DateTime.utc(2026, 8, 21, 9).toIso8601String(),
        'last_seen_at': DateTime.utc(2026, 8, 21, 9).toIso8601String(),
      }, updatedAt: DateTime.utc(2026, 8, 21, 9));
      h.backend.seed('measurement', {
        'entry_id': ids['entry'],
        'source_id': 'srv-source-b',
        'fraction': 0.7,
        'observed_at': DateTime.utc(2026, 8, 21, 9).toIso8601String(),
      }, key: '${ids['entry']}|srv-source-b');
      await h.engine.syncOnce(h.transport);

      h.backend.seedTombstone(
        'measurement',
        ids['entry']!,
        sourceId: ids['source'],
        deletedAt: DateTime.utc(2026, 8, 21, 14),
      );
      await h.engine.syncOnce(h.transport);

      expect(await h.measurements.of(ids['entry']!, ids['source']!), isNull);
      expect(
        (await h.measurements.of(ids['entry']!, 'srv-source-b'))!.fraction,
        0.7,
      );

      // An unscoped measurement tombstone names nothing and deletes nothing.
      h.backend.seedTombstone(
        'measurement',
        ids['entry']!,
        deletedAt: DateTime.utc(2026, 8, 21, 15),
      );
      await h.engine.syncOnce(h.transport);
      expect(await h.measurements.of(ids['entry']!, 'srv-source-b'), isNotNull);
    },
  );

  test(
    'a folder delete made here replays remotely and converges back',
    () async {
      seedServerLibrary();
      await h.engine.syncOnce(h.transport);

      // Local optimistic delete-with-reparent of the Weekly folder.
      final (counts, violation) = await h.folders.deleteWithReparent(
        'srv-folder',
      );
      expect(violation, isNull);
      expect(counts!.collections, 1);

      // Drain the single delete intent; the server reparents on its side and
      // the reparented rows flow back. Convergence must be idempotent.
      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      expect(await h.folders.byId('srv-folder'), isNull);
      final localRoot = await h.folders.ensureRoot();
      final collection = await h.collections.byId('srv-collection');
      expect(collection!.folderId, localRoot.id);
      expect(h.backend.kindRows('folder').containsKey('srv-folder'), isFalse);
      expect(
        h.backend.kindRows('collection')['srv-collection']!['folder_id'],
        'srv-root',
      );
    },
  );

  test('a second client\'s edits arrive on the next pull', () async {
    seedServerLibrary();
    await h.engine.syncOnce(h.transport);

    // "Client B": marks the entry read, server-side.
    h.backend.seed(
      'readingState',
      {
        'entry_id': 'srv-entry',
        'status': 'completed',
        'first_opened_at': DateTime.utc(2026, 8, 21, 9).toIso8601String(),
        'last_read_at': DateTime.utc(2026, 8, 21, 16).toIso8601String(),
        'completed_at': DateTime.utc(2026, 8, 21, 16).toIso8601String(),
      },
      updatedAt: DateTime.utc(2026, 8, 21, 16),
      key: 'srv-entry',
    );

    await h.engine.syncOnce(h.transport);
    final state = await h.readingStates.stateOf('srv-entry');
    expect(state.status.name, 'completed');
    expect(state.completedAt, DateTime.utc(2026, 8, 21, 16));
  });

  test(
    'an unknown entity kind on the feed is skipped, never guessed',
    () async {
      h.backend.feed.add({
        'type': 'entity',
        'entity_type': 'somethingNew',
        'revision': ++h.backend.revision,
        'entity': {'id': 'x'},
      });
      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      expect(outcome.pulled!.skipped, 1);
      expect(await h.syncState.cursor(), h.backend.revision);
    },
  );
}
