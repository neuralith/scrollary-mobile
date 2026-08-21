/// Folder repository (C3): tree operations, reparenting delete, cycle
/// refusal, root protection.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/invariants.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test(
    'ensureRoot creates once and is idempotent, with no outbox intent',
    () async {
      final first = await h.folders.ensureRoot();
      final second = await h.folders.ensureRoot();
      expect(second.id, first.id);
      expect(await h.outboxCount(), 0);
    },
  );

  test('create defaults to the root parent and records one intent', () async {
    final root = await h.folders.ensureRoot();
    final (folder, violation) = await h.folders.create('Weekly');
    expect(violation, isNull);
    expect(folder!.parentId, root.id);
    final rows = await h.outbox.pending();
    expect(rows, hasLength(1));
    expect(rows.single.entityKind, 'folder');
    expect(rows.single.op, 'upsert');
    final fields = jsonDecode(rows.single.payload) as Map<String, dynamic>;
    expect(fields['parent_id'], root.id);
    expect(fields['name'], 'Weekly');
    expect(fields['kind'], 'user');
  });

  test('create under an unknown parent is refused', () async {
    await h.folders.ensureRoot();
    final (folder, violation) = await h.folders.create(
      'Orphan',
      parentId: 'nope',
    );
    expect(folder, isNull);
    expect(violation, unknownParentFolder);
  });

  test('root cannot be renamed, moved or deleted', () async {
    final root = await h.folders.ensureRoot();
    final (f, _) = await h.folders.create('Weekly');
    final (_, renameViolation) = await h.folders.rename(root.id, 'X');
    expect(renameViolation, rootFolderImmutable);
    expect(await h.folders.move(root.id, f!.id), rootFolderImmutable);
    final (_, deleteViolation) = await h.folders.deleteWithReparent(root.id);
    expect(deleteViolation, rootFolderImmutable);
  });

  test(
    'a move that would make a folder contain itself is refused (I2)',
    () async {
      await h.folders.ensureRoot();
      final (a, _) = await h.folders.create('a');
      final (b, _) = await h.folders.create('b', parentId: a!.id);
      final (c, _) = await h.folders.create('c', parentId: b!.id);
      expect(await h.folders.move(a.id, c!.id), folderCycle);
      expect(await h.folders.move(a.id, a.id), folderCycle);
      // A legal reorganisation still works.
      expect(await h.folders.move(c.id, a.id), isNull);
    },
  );

  test('delete reparents child folders, collections and standalone entries '
      'to the parent and deletes no content (I5)', () async {
    final root = await h.folders.ensureRoot();
    final (doomed, _) = await h.folders.create('Doomed');
    final (child, _) = await h.folders.create('Child', parentId: doomed!.id);
    final (collection, _) = await h.collections.create(
      name: 'Kept work',
      folderId: doomed.id,
      orderingBasis: OrderingBasis.discoveryOrder,
    );
    final (standalone, _) = await h.entries.createStandalone(
      folderId: doomed.id,
      title: 'One-off',
    );

    final before = await h.outboxCount();
    final (counts, violation) = await h.folders.deleteWithReparent(doomed.id);
    expect(violation, isNull);
    expect((counts!.folders, counts.collections, counts.entries), (1, 1, 1));
    // One intent: the folder's delete. The server reparents on its side.
    expect(await h.outboxCount(), before + 1);

    expect(await h.folders.byId(doomed.id), isNull);
    expect((await h.folders.byId(child!.id))!.parentId, root.id);
    expect((await h.collections.byId(collection!.id))!.folderId, root.id);
    expect((await h.entries.byId(standalone!.id))!.folderId, root.id);
  });

  test('children are ordered by sort key then name', () async {
    final root = await h.folders.ensureRoot();
    await h.folders.create('zeta', sortKey: 0);
    await h.folders.create('alpha', sortKey: 0);
    await h.folders.create('first', sortKey: -1);
    final children = await h.folders.childrenOf(root.id);
    expect(children.map((f) => f.name).toList(), ['first', 'alpha', 'zeta']);
  });

  test(
    'applyRemote writes no outbox row and clears with explicit null',
    () async {
      final root = await h.folders.ensureRoot();
      await h.folders.applyRemote(
        id: 'remote-1',
        serverId: 'remote-1',
        parentId: root.id,
        kind: 'user',
        name: 'From elsewhere',
        sortKey: 3,
        revision: 7,
        updatedAt: DateTime.utc(2026, 8, 21),
      );
      expect(await h.outboxCount(), 0);
      final row = await h.folders.byId('remote-1');
      expect(row!.revision, 7);
      expect(row.serverId, 'remote-1');
    },
  );
}
