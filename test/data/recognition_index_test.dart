/// Recognition indexes (C9): the hot path answers from one indexed local
/// lookup, offline, or says "unknown" honestly.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/repo_harness.dart';

/// Counts SELECT statements reaching the executor, so a test can assert the
/// hot path is a single lookup rather than a chain.
class CountingInterceptor extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  late RepoHarness h;
  late CountingInterceptor counter;

  setUp(() {
    counter = CountingInterceptor();
    h = RepoHarness(executor: NativeDatabase.memory().interceptWith(counter));
  });
  tearDown(() => h.close());

  test(
    'a known url_key resolves Location and Entry in ONE statement',
    () async {
      final seeded = await h.seedLibrary();

      counter.selects = 0;
      final hit = await h.recognition.lookupUrl(seeded.location.urlKey);
      expect(hit, isNotNull);
      expect(hit!.location.id, seeded.location.id);
      expect(hit.entry.id, seeded.entry.id);
      expect(hit.collectionId, seeded.collection.id);
      expect(counter.selects, 1, reason: 'the hot path is one indexed lookup');
    },
  );

  test('an unknown URL answers null rather than guessing', () async {
    await h.seedLibrary();
    expect(
      await h.recognition.lookupUrl('https://elsewhere.example.test/page'),
      isNull,
    );
  });

  test('(host, path_key) resolves the Source in one statement', () async {
    final seeded = await h.seedLibrary();
    counter.selects = 0;
    final source = await h.recognition.lookupSource(
      'reading.example.com',
      'serial-alpha',
    );
    expect(source!.id, seeded.source.id);
    expect(counter.selects, 1);
    expect(
      await h.recognition.lookupSource('reading.example.com', 'other'),
      isNull,
    );
  });

  test('(collection, ordinal) resolves the Entry in one statement', () async {
    final seeded = await h.seedLibrary();
    counter.selects = 0;
    final entry = await h.recognition.lookupOrdinal(seeded.collection.id, 101);
    expect(entry!.id, seeded.entry.id);
    expect(counter.selects, 1);
    expect(
      await h.recognition.lookupOrdinal(seeded.collection.id, 999),
      isNull,
    );
  });

  test('a retracted Location still resolves — retraction is evidence about '
      'a listing, not about what the address is', () async {
    final seeded = await h.seedLibrary();
    await h.entries.retractLocation(
      seeded.location.id,
      readingSourceId: seeded.source.id,
    );
    final hit = await h.recognition.lookupUrl(seeded.location.urlKey);
    expect(hit, isNotNull);
    expect(hit!.location.lifecycle, 'retracted');
  });

  test(
    'a standalone Entry\'s Location resolves with a null collection',
    () async {
      final root = await h.folders.ensureRoot();
      final (standalone, _) = await h.entries.createStandalone(
        folderId: root.id,
        title: 'One-off',
      );
      await h.entries.addLocation(
        entryId: standalone!.id,
        url: 'https://pages.example.org/essay',
        urlKey: 'https://pages.example.org/essay',
      );
      final hit = await h.recognition.lookupUrl(
        'https://pages.example.org/essay',
      );
      expect(hit!.entry.id, standalone.id);
      expect(hit.collectionId, isNull);
    },
  );
}
