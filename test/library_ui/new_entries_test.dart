/// The bar after a check, and the one tap that downloads what it found.
///
/// Under test here is the shape of the rows that tap writes, not the copy on
/// the bar. A Collection kept as *Images only* has to stay that way when its
/// new entries are downloaded from here, and the way that holds is the row
/// carrying **no capture mode of its own** so the capture seam can ask the
/// Collection (V2-D58). A row that arrived with a mode baked in would freeze
/// whatever the preference happened to be when the check ran.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/library_ui/new_entries_bar.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/discovery.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// A Collection whose last check found two entries the library did not have.
  Future<({CollectionRow collection, List<String> found})> seedNews() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final source = await h.source(collection.id);
    final found = <String>[];
    for (var i = 2; i <= 3; i++) {
      final entry = await h.entryIn(
        collection.id,
        title: 'Part $i',
        ordinal: i.toDouble(),
      );
      await h.location(
        entry.id,
        'https://reading.example.com/serial/$i',
        sourceId: source.id,
      );
      found.add(entry.id);
    }
    h.checkState.recordCheck(
      collection.id,
      SourceCheckOutcome(
        sourceId: source.id,
        state: SourceCheckState.updatesAvailable,
        discovery: DiscoveryOutcome(createdEntryIds: found),
      ),
      at: DateTime.utc(2026, 8, 24),
    );
    return (collection: collection, found: found);
  }

  Future<void> openBar(WidgetTester tester, String collectionId) async {
    await tester.pumpWidget(
      h.app(Scaffold(body: NewEntriesBar(collectionId: collectionId))),
    );
    await pumpUntil(tester, find.byKey(const ValueKey('newEntriesBar')));
  }

  screenTest('downloading what a check found queues a row per entry, and each '
      'one leaves the mode to the collection', (tester) async {
    final seeded = await seedNews();
    await openBar(tester, seeded.collection.id);

    await tapAndPump(tester, find.byKey(const ValueKey('downloadNewEntries')));
    await pumpUntil(tester, find.textContaining('2 queued'));

    final rows = await h.queue.pending();
    expect(rows.map((t) => t.entryId).toSet(), seeded.found.toSet());
    for (final row in rows) {
      expect(
        row.captureMode,
        isNull,
        reason:
            'what this collection is saved as is asked at capture, so it '
            'is the answer in force then rather than the one frozen here',
      );
      expect(row.captureModeIsUserSet, isFalse);
    }
    // And nothing ran: this is the queue, not a start.
    expect(await h.queue.eligible(), isEmpty);
  });
}
