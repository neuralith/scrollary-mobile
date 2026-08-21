/// Measurement repository (C7): the (entry, source) scope is never dropped.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/domain/invariants.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test(
    'a measurement on one Source is never read as a claim about another',
    () async {
      final seeded = await h.seedLibrary();
      final (translation, _) = await h.collections.addSource(
        collectionId: seeded.collection.id,
        host: 'texts.example.org',
        pathKey: 'serial-alpha',
        language: 'tr',
      );

      final (m, violation) = await h.measurements.put(
        entryId: seeded.entry.id,
        sourceId: seeded.source.id,
        fraction: 0.6,
      );
      expect(violation, isNull);
      expect(m!.fraction, 0.6);

      // Sixty percent of one rendering says nothing about the other.
      expect(await h.measurements.of(seeded.entry.id, translation!.id), isNull);

      // Each cell is its own fact.
      await h.measurements.put(
        entryId: seeded.entry.id,
        sourceId: translation.id,
        fraction: 0.25,
      );
      final all = await h.measurements.allOf(seeded.entry.id);
      expect(all, hasLength(2));
      expect(all.map((x) => x.sourceId).toSet(), {
        seeded.source.id,
        translation.id,
      });
    },
  );

  test('replacing a cell keeps the other cells', () async {
    final seeded = await h.seedLibrary();
    await h.measurements.put(
      entryId: seeded.entry.id,
      sourceId: seeded.source.id,
      fraction: 0.3,
    );
    await h.measurements.put(
      entryId: seeded.entry.id,
      sourceId: seeded.source.id,
      fraction: 0.9,
    );
    final cell = await h.measurements.of(seeded.entry.id, seeded.source.id);
    expect(cell!.fraction, 0.9);
    expect(await h.measurements.allOf(seeded.entry.id), hasLength(1));
  });

  test('a fraction is a fraction, and the scope is required (I12)', () async {
    final seeded = await h.seedLibrary();
    final (_, tooBig) = await h.measurements.put(
      entryId: seeded.entry.id,
      sourceId: seeded.source.id,
      fraction: 1.2,
    );
    expect(tooBig, measurementNeedsScope);
    final (_, noScope) = await h.measurements.put(
      entryId: seeded.entry.id,
      sourceId: '',
      fraction: 0.5,
    );
    expect(noScope, measurementNeedsScope);
  });

  test('a measurement for an unknown Entry is refused', () async {
    final seeded = await h.seedLibrary();
    final (_, violation) = await h.measurements.put(
      entryId: 'missing',
      sourceId: seeded.source.id,
      fraction: 0.5,
    );
    expect(violation, unknownRow);
  });
}
