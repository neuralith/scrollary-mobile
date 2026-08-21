/// Collection detail (D3): one list, availability as a row state, and verbs
/// whose blast radius is what the wording says it is.
///
/// The load-bearing assertions here are the negative ones — there is exactly
/// one list, an Entry with no copy on this device is an ordinary row, and
/// removing an Entry from the library does not take this device's bytes with
/// it (I14).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/library_widgets.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// A Collection with three Entries: one this device holds, one it does not,
  /// and one whose position in the sequence is unknown.
  Future<
    ({
      CollectionRow collection,
      EntryRow held,
      EntryRow plain,
      EntryRow unplaced,
    })
  >
  seed() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final held = await h.entryIn(
      collection.id,
      title: 'The first one',
      ordinal: 1,
    );
    await h.copyFor(held.id);
    final plain = await h.entryIn(
      collection.id,
      title: 'The second one',
      ordinal: 2,
    );
    final unplaced = await h.entryIn(
      collection.id,
      title: 'A stray one',
      placement: Placement.unplaced,
    );
    return (
      collection: collection,
      held: held,
      plain: plain,
      unplaced: unplaced,
    );
  }

  Future<void> openEntryMenu(WidgetTester tester, String entryId) =>
      tapAndPump(tester, find.byKey(ValueKey('entryMenu-$entryId')));

  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  screenTest('there is one list, and a row with no copy is an ordinary row', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(EntryRowTile), findsNWidgets(3));
    // Availability is a line on the row that holds bytes, and nothing at all
    // on the two that do not.
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('3 items · 3 unread'), findsOneWidget);
  });

  screenTest('unplaced entries are last, in the same list, and ordinary '
      'entries are never in that section', (tester) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('NEEDS PLACEMENT · 1'));

    final heading = tester.getTopLeft(find.text('NEEDS PLACEMENT · 1')).dy;
    expect(
      tester.getTopLeft(find.byKey(ValueKey('entryRow-${s.held.id}'))).dy,
      lessThan(heading),
    );
    expect(
      tester.getTopLeft(find.byKey(ValueKey('entryRow-${s.plain.id}'))).dy,
      lessThan(heading),
    );
    expect(
      tester.getTopLeft(find.byKey(ValueKey('entryRow-${s.unplaced.id}'))).dy,
      greaterThan(heading),
    );
    expect(find.text('ITEMS · 2'), findsOneWidget);
  });

  screenTest('marking read and unread round-trips through the repository', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Mark read'));
    await pumpUntil(tester, find.text('Read'));
    expect((await h.reading.stateOf(s.plain.id)).status, ReadStatus.completed);

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Mark unread'));
    await pumpUntilGone(tester, find.text('Read'));
    expect((await h.reading.stateOf(s.plain.id)).status, ReadStatus.unread);
  });

  screenTest('removing an offline copy is offered only where one exists', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await openEntryMenu(tester, s.plain.id);
    expect(find.text('Remove offline copy'), findsNothing);
    await dismissSheet(tester);

    await openEntryMenu(tester, s.held.id);
    expect(find.text('Remove offline copy'), findsOneWidget);
    expect(
      find.textContaining('Frees the bytes on this device'),
      findsOneWidget,
    );
  });

  screenTest('removing an offline copy leaves the entry in the library', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await openEntryMenu(tester, s.held.id);
    await tapAndPump(tester, find.text('Remove offline copy'));
    await tapAndPump(tester, find.widgetWithText(TextButton, 'Remove copy'));
    await pumpUntilGone(tester, find.text('On this device'));

    expect(await h.entries.byId(s.held.id), isNotNull);
    expect(await h.offlineCopyRows(s.held.id), 0);
    expect(find.text('The first one'), findsOneWidget);
  });

  screenTest('removing an entry from the library keeps this device\'s copy '
      'row (I14)', (tester) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await openEntryMenu(tester, s.held.id);
    await tapAndPump(tester, find.text('Remove from library'));
    expect(find.textContaining('every device you use'), findsOneWidget);
    await tapAndPump(tester, find.widgetWithText(TextButton, 'Remove'));
    await pumpUntilGone(tester, find.text('The first one'));

    expect(await h.entries.byId(s.held.id), isNull);
    // The library row is gone; the bytes this device holds are not the
    // library's to take.
    expect(await h.offlineCopyRows(s.held.id), 1);
  });

  screenTest('opening at source records access and never completion', (
    tester,
  ) async {
    final s = await seed();
    final source = await h.source(s.collection.id);
    await h.location(
      s.plain.id,
      'https://reading.example.com/serial/2',
      sourceId: source.id,
    );

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The second one'));

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Open at source'));
    await pumpUntil(tester, find.text('Reading'));

    expect(h.opened, ['https://reading.example.com/serial/2']);
    final state = await h.reading.stateOf(s.plain.id);
    expect(state.status, ReadStatus.reading);
    expect(state.completedAt, isNull);
  });

  screenTest('downloading is not faked while the capture lane is absent', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await openEntryMenu(tester, s.plain.id);
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('entryDownload')),
    );
    expect(tile.enabled, isFalse);
    expect(find.text('Not available yet.'), findsOneWidget);
  });

  screenTest('archiving stops following and never says it deleted anything', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    await tapAndPump(tester, find.byTooltip('Collection actions'));
    expect(find.textContaining('Stops following it'), findsOneWidget);
    expect(find.textContaining('stay exactly as they are'), findsOneWidget);
    await tapAndPump(tester, find.text('Archive'));
    await pumpUntil(tester, find.text('Archived'));

    final row = await h.collections.byId(s.collection.id);
    expect(row!.lifecycle, CollectionLifecycle.archived.name);
    // Nothing else moved.
    expect(find.byType(EntryRowTile), findsNWidgets(3));
  });
}
