/// Ordering a Collection's Entries, on the screen that draws them.
///
/// The comparator itself is proved in `test/entry_sort_test.dart` without a
/// database. What is proved here is everything around it: that the facts it
/// sorts on are actually read out of `locations`, that the default ladder
/// picks the right one for a real Collection, that the control offers only
/// what the data supports, and that a choice survives closing the screen.
///
/// One negative assertion carries more than the rest: sorting by a
/// `source_number` must never write an `ordinal`. That column is identity —
/// cross-source merge keys on it and the update check measures novelty against
/// it — and a list being drawn in a different order is not a reason to touch
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/library/entry_sort.dart';
import 'package:web_reader/library/entry_sort_preference.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/data/local_settings.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  DateTime day(int d) => DateTime.utc(2026, 1, d);

  EntrySortPreferenceStore store() =>
      EntrySortPreferenceStore(LocalSettingsStore(h.db));

  /// The Entry titles on screen, top to bottom.
  List<String> titlesOnScreen(WidgetTester tester, List<String> candidates) {
    final seen = <(int, String)>[];
    for (final title in candidates) {
      final finder = find.text(title);
      if (finder.evaluate().isEmpty) continue;
      seen.add((tester.getTopLeft(finder.first).dy.round(), title));
    }
    seen.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, title) in seen) title];
  }

  Future<void> openCollection(WidgetTester tester, String collectionId) async {
    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: collectionId)),
    );
    await pumpUntil(tester, find.byKey(const ValueKey('entrySortButton')));
  }

  Future<void> openSortSheet(WidgetTester tester) =>
      tapAndPump(tester, find.byKey(const ValueKey('entrySortButton')));

  // ─── the default ladder, on real rows ──────────────────────────────────────

  screenTest('a reliably numbered collection opens in numeric order', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Numbered', folderId: root.id);
    final source = await h.source(collection.id);
    for (final (ordinal, title) in [
      (9.0, 'Part nine'),
      (10.0, 'Part ten'),
      (1.0, 'Part one'),
    ]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        ordinal: ordinal,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$ordinal',
        sourceId: source.id,
      );
    }

    await openCollection(tester, collection.id);

    expect(
      titlesOnScreen(tester, ['Part one', 'Part nine', 'Part ten']),
      ['Part one', 'Part nine', 'Part ten'],
      reason: 'and "Part ten" does not sort between one and nine',
    );
    expect(find.text('NUMBER'), findsOneWidget);
  });

  screenTest('an unnumbered collection with dates opens by publish date', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Dated',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    for (final (published, title) in [
      (day(3), 'Newest post'),
      (day(1), 'Oldest post'),
      (day(2), 'Middle post'),
    ]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        placement: Placement.unplaced,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$title',
        sourceId: source.id,
        publishedAt: published,
      );
    }

    await openCollection(tester, collection.id);

    expect(find.text('PUBLISH DATE'), findsOneWidget);
    expect(
      titlesOnScreen(tester, ['Oldest post', 'Middle post', 'Newest post']),
      ['Oldest post', 'Middle post', 'Newest post'],
    );
  });

  screenTest('with neither a number nor a date, it opens by date added', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Plain',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    // Seeded in this order, so `discovered_at` runs in it too.
    for (final title in ['Added first', 'Added second', 'Added third']) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        placement: Placement.unplaced,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$title',
        sourceId: source.id,
      );
    }

    await openCollection(tester, collection.id);

    expect(find.text('DATE ADDED'), findsOneWidget);
    expect(
      titlesOnScreen(tester, ['Added first', 'Added second', 'Added third']),
      ['Added first', 'Added second', 'Added third'],
    );
  });

  // ─── the control ───────────────────────────────────────────────────────────

  screenTest('the control offers only the orders the data supports', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Plain',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    final entry = await h.entryIn(
      collection.id,
      title: 'Just the one',
      placement: Placement.unplaced,
    );
    await h.location(
      entry.id,
      'https://reading.example.com/a/one',
      sourceId: source.id,
    );

    await openCollection(tester, collection.id);
    await openSortSheet(tester);

    expect(
      find.byKey(const ValueKey('entrySortField-addedDate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entrySortField-publishDate')),
      findsNothing,
      reason: 'no site printed a date, so there is no publish order to be in',
    );
    expect(
      find.byKey(const ValueKey('entrySortField-number')),
      findsNothing,
      reason: 'and nothing here carries a number of any kind',
    );
    // Direction is always a real choice.
    expect(
      find.byKey(const ValueKey('entrySortDirection-ascending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entrySortDirection-descending')),
      findsOneWidget,
    );
  });

  screenTest('choosing descending reverses the list', (tester) async {
    final root = await h.root();
    final collection = await h.collection('Numbered', folderId: root.id);
    final source = await h.source(collection.id);
    for (final (ordinal, title) in [(1.0, 'Part one'), (2.0, 'Part two')]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        ordinal: ordinal,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$ordinal',
        sourceId: source.id,
      );
    }

    await openCollection(tester, collection.id);
    expect(titlesOnScreen(tester, ['Part one', 'Part two']), [
      'Part one',
      'Part two',
    ]);

    await openSortSheet(tester);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entrySortDirection-descending')),
    );
    await pumpUntil(tester, find.text('NUMBER'));

    expect(
      titlesOnScreen(tester, ['Part one', 'Part two']),
      ['Part two', 'Part one'],
      reason: 'the list redraws behind the sheet, without leaving the screen',
    );
  });

  // ─── the preference ────────────────────────────────────────────────────────

  screenTest('the choice survives closing and reopening the collection', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Numbered', folderId: root.id);
    final source = await h.source(collection.id);
    for (final (ordinal, title) in [(1.0, 'Part one'), (2.0, 'Part two')]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        ordinal: ordinal,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$ordinal',
        sourceId: source.id,
      );
    }

    await openCollection(tester, collection.id);
    await openSortSheet(tester);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entrySortDirection-descending')),
    );
    await pumpUntil(tester, find.text('NUMBER'));

    expect(
      await store().of(collection.id),
      const EntrySort(EntrySortField.number, EntrySortDirection.descending),
    );

    // Leave the screen entirely and come back to it.
    await tester.pumpWidget(h.app(const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 10));
    await openCollection(tester, collection.id);

    expect(
      titlesOnScreen(tester, ['Part one', 'Part two']),
      ['Part two', 'Part one'],
      reason: 'exactly the order it was left in',
    );
  });

  screenTest('one collection remembering an order does not touch another', (
    tester,
  ) async {
    final root = await h.root();
    final first = await h.collection('First', folderId: root.id);
    final second = await h.collection('Second', folderId: root.id);
    // Titles that do not contain their Collection's name: a row inside a
    // Collection has the work's name taken out of its label, and a fixture
    // that ignored that would be asserting on text no row draws.
    for (final (collection, low, high) in [
      (first, 'Alpha one', 'Alpha two'),
      (second, 'Beta one', 'Beta two'),
    ]) {
      final source = await h.source(
        collection.id,
        pathKey: 'path-${collection.id}',
      );
      for (final (ordinal, title) in [(1.0, low), (2.0, high)]) {
        final entry = await h.entryIn(
          collection.id,
          title: title,
          ordinal: ordinal,
        );
        await h.location(
          entry.id,
          'https://reading.example.com/${collection.id}/$ordinal',
          sourceId: source.id,
        );
      }
    }

    await openCollection(tester, first.id);
    await openSortSheet(tester);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entrySortDirection-descending')),
    );
    await pumpUntil(tester, find.text('NUMBER'));

    expect(await store().of(second.id), isNull);
    await openCollection(tester, second.id);
    expect(
      titlesOnScreen(tester, ['Beta one', 'Beta two']),
      ['Beta one', 'Beta two'],
      reason: 'the second collection is still following its own data',
    );
  });

  // ─── source_number is evidence, not an ordinal ─────────────────────────────

  screenTest('a collection the app would not number is still drawn in the '
      'order its site printed — and gains no ordinal', (tester) async {
    final root = await h.root();
    final collection = await h.collection(
      'Unnumbered basis',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    final seeded = <EntryRow>[];
    for (final (number, title) in [
      (10.0, 'Printed ten'),
      (9.0, 'Printed nine'),
    ]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        placement: Placement.unplaced,
      );
      seeded.add(entry);
      await h.location(
        entry.id,
        'https://reading.example.com/a/$number',
        sourceId: source.id,
        sourceNumber: number,
      );
    }

    await openCollection(tester, collection.id);
    await openSortSheet(tester);
    // Offered, because the rows can answer it — just not the default.
    expect(find.text('DATE ADDED'), findsWidgets);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entrySortField-number')),
    );
    await pumpUntil(tester, find.text('NUMBER'));

    expect(titlesOnScreen(tester, ['Printed nine', 'Printed ten']), [
      'Printed nine',
      'Printed ten',
    ]);
    for (final entry in seeded) {
      final row = await h.entries.byId(entry.id);
      expect(
        (row!.ordinal, row.placement),
        (null, Placement.unplaced.name),
        reason:
            'drawing a list in an order must never write the column that '
            'decides identity and update discovery (V2-D15, V2-D16)',
      );
    }
  });

  // ─── the placement section ─────────────────────────────────────────────────

  screenTest('under a date sort there is one list and no placement heading', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Mixed',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    final placed = await h.entryIn(
      collection.id,
      title: 'Has a place',
      ordinal: 1,
    );
    await h.location(
      placed.id,
      'https://reading.example.com/a/1',
      sourceId: source.id,
      publishedAt: day(2),
    );
    final unplaced = await h.entryIn(
      collection.id,
      title: 'Has no place',
      placement: Placement.unplaced,
    );
    await h.location(
      unplaced.id,
      'https://reading.example.com/a/2',
      sourceId: source.id,
      publishedAt: day(1),
    );

    await openCollection(tester, collection.id);

    expect(find.text('PUBLISH DATE'), findsOneWidget);
    expect(
      find.textContaining('NEEDS PLACEMENT'),
      findsNothing,
      reason:
          'nothing on screen is claiming a numeric position, so holding rows '
          'back under a heading about placement would answer a question the '
          'list is not asking',
    );
    expect(
      titlesOnScreen(tester, ['Has a place', 'Has no place']),
      ['Has no place', 'Has a place'],
      reason: 'both rows are in the one list, in date order',
    );
  });

  screenTest('under a numeric sort the placement heading is still there', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Numbered', folderId: root.id);
    final source = await h.source(collection.id);
    final placed = await h.entryIn(
      collection.id,
      title: 'Has a place',
      ordinal: 1,
    );
    await h.location(
      placed.id,
      'https://reading.example.com/a/1',
      sourceId: source.id,
    );
    final unplaced = await h.entryIn(
      collection.id,
      title: 'Has no place',
      placement: Placement.unplaced,
    );
    await h.location(
      unplaced.id,
      'https://reading.example.com/a/2',
      sourceId: source.id,
    );

    await openCollection(tester, collection.id);

    expect(find.text('NUMBER'), findsOneWidget);
    expect(find.textContaining('NEEDS PLACEMENT'), findsOneWidget);
  });

  // ─── entries that cannot answer ────────────────────────────────────────────

  screenTest('an entry with no publish date sorts last, both ways round', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Half dated',
      folderId: root.id,
      basis: OrderingBasis.discoveryOrder,
    );
    final source = await h.source(collection.id);
    for (final (published, title) in [
      (day(1), 'Dated older'),
      (day(2), 'Dated newer'),
      (null, 'Never dated'),
    ]) {
      final entry = await h.entryIn(
        collection.id,
        title: title,
        placement: Placement.unplaced,
      );
      await h.location(
        entry.id,
        'https://reading.example.com/a/$title',
        sourceId: source.id,
        publishedAt: published,
      );
    }
    const all = ['Dated older', 'Dated newer', 'Never dated'];

    await openCollection(tester, collection.id);
    expect(titlesOnScreen(tester, all), [
      'Dated older',
      'Dated newer',
      'Never dated',
    ]);

    await openSortSheet(tester);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entrySortDirection-descending')),
    );
    await pumpUntil(tester, find.text('PUBLISH DATE'));

    expect(
      titlesOnScreen(tester, all),
      ['Dated newer', 'Dated older', 'Never dated'],
      reason:
          'reversing reverses the dated rows; it does not promote the '
          'undated one to the top',
    );
  });
}
