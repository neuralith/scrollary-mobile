/// Collection and Source repository (C4): follow/archive, preferred source,
/// source lifecycle, resolvedInto chains, identity uniqueness.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/invariants.dart';
import 'package:web_reader/domain/source.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test(
    'archive writes lifecycle and nothing else; follow writes it back',
    () async {
      final seeded = await h.seedLibrary();
      final before = (await h.collections.byId(seeded.collection.id))!;

      expect(await h.collections.archive(seeded.collection.id), isNull);
      final archived = (await h.collections.byId(seeded.collection.id))!;
      expect(archived.lifecycle, 'archived');
      expect(archived.name, before.name);
      expect(archived.folderId, before.folderId);
      expect(archived.preferredSourceId, before.preferredSourceId);

      final rows = await h.outbox.pending(limit: 100);
      final fields = jsonDecode(rows.last.payload) as Map<String, dynamic>;
      expect(fields.keys.toList(), ['lifecycle']);

      expect(await h.collections.follow(seeded.collection.id), isNull);
      expect(
        (await h.collections.byId(seeded.collection.id))!.lifecycle,
        'active',
      );
    },
  );

  test('preferred source must belong to the collection (I9)', () async {
    final seeded = await h.seedLibrary();
    final root = seeded.root;
    final (other, _) = await h.collections.create(
      name: 'Other work',
      folderId: root.id,
      orderingBasis: OrderingBasis.publicationDate,
    );
    final (foreignSource, _) = await h.collections.addSource(
      collectionId: other!.id,
      host: 'texts.example.org',
      pathKey: 'other-work',
    );

    expect(
      await h.collections.setPreferredSource(
        seeded.collection.id,
        foreignSource!.id,
      ),
      preferredSourceForeign,
    );
    expect(
      await h.collections.setPreferredSource(
        seeded.collection.id,
        seeded.source.id,
      ),
      isNull,
    );
    // Clearing is a real write, not an absent field.
    expect(
      await h.collections.setPreferredSource(seeded.collection.id, null),
      isNull,
    );
    expect(
      (await h.collections.byId(seeded.collection.id))!.preferredSourceId,
      isNull,
    );
  });

  test('a (host, path_key) pair identifies exactly one Source', () async {
    final seeded = await h.seedLibrary();
    final (dup, violation) = await h.collections.addSource(
      collectionId: seeded.collection.id,
      host: 'reading.example.com',
      pathKey: 'serial-alpha',
    );
    expect(dup, isNull);
    expect(violation, sourceIdentityTaken);

    // The recognition index is per library, so another collection cannot take
    // the pair either.
    final (other, _) = await h.collections.create(
      name: 'Other',
      folderId: seeded.root.id,
      orderingBasis: OrderingBasis.discoveryOrder,
    );
    final (dup2, violation2) = await h.collections.addSource(
      collectionId: other!.id,
      host: 'reading.example.com',
      pathKey: 'serial-alpha',
    );
    expect(dup2, isNull);
    expect(violation2, sourceIdentityTaken);
  });

  test('resolvedInto requires a target of the same collection and resolves '
      'through chains without looping', () async {
    final seeded = await h.seedLibrary();
    final (successor, _) = await h.collections.addSource(
      collectionId: seeded.collection.id,
      host: 'mirror.example.test',
      pathKey: 'serial-alpha',
    );

    // Missing, self and foreign targets are refused.
    expect(
      await h.collections.setSourceLifecycle(
        seeded.source.id,
        SourceLifecycle.resolvedInto,
      ),
      resolvedIntoForeign,
    );
    expect(
      await h.collections.setSourceLifecycle(
        seeded.source.id,
        SourceLifecycle.resolvedInto,
        resolvedIntoSourceId: seeded.source.id,
      ),
      resolvedIntoForeign,
    );

    expect(
      await h.collections.setSourceLifecycle(
        seeded.source.id,
        SourceLifecycle.resolvedInto,
        resolvedIntoSourceId: successor!.id,
      ),
      isNull,
    );
    final terminal = await h.collections.terminalSourceOf(seeded.source.id);
    expect(terminal!.id, successor.id);

    // A site coming back is a state change, not a row move: the pointer
    // clears when the lifecycle leaves resolvedInto.
    expect(
      await h.collections.setSourceLifecycle(
        seeded.source.id,
        SourceLifecycle.active,
      ),
      isNull,
    );
    final revived = await h.collections.sourceById(seeded.source.id);
    expect(revived!.resolvedIntoSourceId, isNull);
  });

  test('removing a Source takes its Locations and leaves Entries', () async {
    final seeded = await h.seedLibrary();
    expect(await h.collections.removeSource(seeded.source.id), isNull);
    expect(await h.collections.sourceById(seeded.source.id), isNull);
    expect(await h.entries.locationById(seeded.location.id), isNull);
    expect(await h.entries.byId(seeded.entry.id), isNotNull);
  });

  test('lifecycle transitions cover dormant and dead', () async {
    final seeded = await h.seedLibrary();
    for (final lifecycle in [
      SourceLifecycle.dormant,
      SourceLifecycle.dead,
      SourceLifecycle.active,
    ]) {
      expect(
        await h.collections.setSourceLifecycle(seeded.source.id, lifecycle),
        isNull,
      );
      expect(
        (await h.collections.sourceById(seeded.source.id))!.lifecycle,
        lifecycle.name,
      );
    }
  });
}
