/// How a Collection's Entries are ordered: the ladder, the fallbacks, and the
/// rule that a sort can never reach an `ordinal`.
///
/// Every test here is about `library/entry_sort.dart` alone — no database, no
/// widget, no row. That is deliberate: the comparator is the part that has to
/// be right for lists nobody has looked at yet, on data that arrived from
/// three different places, and it should be provable without any of them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/library/entry_sort.dart';

void main() {
  EntrySortFacts facts({
    double? number,
    DateTime? published,
    DateTime? added,
    String label = '',
  }) => EntrySortFacts(
    number: number,
    publishedAt: published,
    addedAt: added,
    label: label,
  );

  DateTime day(int d) => DateTime.utc(2026, 1, d);

  /// The labels of [entries] in the order [sort] draws them.
  List<String> ordered(EntrySort sort, List<EntrySortFacts> entries) =>
      ([...entries]..sort((a, b) => compareEntriesBySort(sort, a, b)))
          .map((f) => f.label)
          .toList();

  group('by number', () {
    test('runs low to high, and 10 does not come before 9', () {
      final list = [
        facts(number: 9, label: 'Part 9'),
        facts(number: 10, label: 'Part 10'),
        facts(number: 1, label: 'Part 1'),
      ];
      expect(ordered(const EntrySort(EntrySortField.number), list), [
        'Part 1',
        'Part 9',
        'Part 10',
      ]);
    });

    test('decimals sit between their neighbours', () {
      final list = [
        facts(number: 100, label: 'a'),
        facts(number: 99.5, label: 'b'),
        facts(number: 99, label: 'c'),
      ];
      expect(ordered(const EntrySort(EntrySortField.number), list), [
        'c',
        'b',
        'a',
      ]);
    });

    test('descending reverses the numbered entries', () {
      final list = [
        facts(number: 1, label: 'one'),
        facts(number: 3, label: 'three'),
        facts(number: 2, label: 'two'),
      ];
      expect(
        ordered(
          const EntrySort(EntrySortField.number, EntrySortDirection.descending),
          list,
        ),
        ['three', 'two', 'one'],
      );
    });
  });

  group('by publish date', () {
    test('oldest first ascending, newest first descending', () {
      final list = [
        facts(published: day(3), label: 'march'),
        facts(published: day(1), label: 'january'),
        facts(published: day(2), label: 'february'),
      ];
      expect(ordered(const EntrySort(EntrySortField.publishDate), list), [
        'january',
        'february',
        'march',
      ]);
      expect(
        ordered(
          const EntrySort(
            EntrySortField.publishDate,
            EntrySortDirection.descending,
          ),
          list,
        ),
        ['march', 'february', 'january'],
      );
    });

    test('a number nobody asked to sort by changes nothing', () {
      final list = [
        facts(number: 99, published: day(1), label: 'first'),
        facts(number: 1, published: day(2), label: 'second'),
      ];
      expect(ordered(const EntrySort(EntrySortField.publishDate), list), [
        'first',
        'second',
      ]);
    });
  });

  group('by date added', () {
    test('is the floor, and orders both ways', () {
      final list = [
        facts(added: day(2), label: 'later'),
        facts(added: day(1), label: 'earlier'),
      ];
      expect(ordered(const EntrySort(EntrySortField.addedDate), list), [
        'earlier',
        'later',
      ]);
      expect(
        ordered(
          const EntrySort(
            EntrySortField.addedDate,
            EntrySortDirection.descending,
          ),
          list,
        ),
        ['later', 'earlier'],
      );
    });
  });

  group('entries that cannot answer', () {
    test('sort last ascending AND descending', () {
      final list = [
        facts(label: 'unknown'),
        facts(published: day(2), label: 'newer'),
        facts(published: day(1), label: 'older'),
      ];
      expect(
        ordered(const EntrySort(EntrySortField.publishDate), list),
        ['older', 'newer', 'unknown'],
        reason: 'an unknown is not an early date',
      );
      expect(
        ordered(
          const EntrySort(
            EntrySortField.publishDate,
            EntrySortDirection.descending,
          ),
          list,
        ),
        ['newer', 'older', 'unknown'],
        reason:
            'reversing reverses the entries that have an answer; it must not '
            'promote the ones that do not',
      );
    });

    test('several unknowns fall back to the label, ascending, either way', () {
      final list = [
        facts(label: 'Zebra'),
        facts(label: 'apple'),
        facts(label: 'Mango'),
      ];
      for (final direction in EntrySortDirection.values) {
        expect(
          ordered(EntrySort(EntrySortField.publishDate, direction), list),
          ['apple', 'Mango', 'Zebra'],
          reason: 'the tiebreak is stability, not a fourth sort option',
        );
      }
    });

    test('entries with the same date still have one settled order', () {
      final list = [
        facts(published: day(1), label: 'beta'),
        facts(published: day(1), label: 'alpha'),
      ];
      expect(ordered(const EntrySort(EntrySortField.publishDate), list), [
        'alpha',
        'beta',
      ]);
    });
  });

  group('what a Collection can be sorted by', () {
    test('offers only the fields its Entries can answer', () {
      expect(
        availableEntrySortFields([
          facts(number: 1, added: day(1)),
          facts(number: 2, added: day(2)),
        ]),
        [EntrySortField.number, EntrySortField.addedDate],
        reason: 'no site printed a date, so there is no publish order to be in',
      );
    });

    test('one dated Entry is enough to offer the order', () {
      expect(
        availableEntrySortFields([
          facts(added: day(1)),
          facts(published: day(2), added: day(2)),
        ]),
        [EntrySortField.publishDate, EntrySortField.addedDate],
      );
    });

    test('an Entry with no address at all offers nothing', () {
      expect(availableEntrySortFields([facts(label: 'stray')]), isEmpty);
    });
  });

  group('the default ladder', () {
    List<EntrySortField> all(List<EntrySortFacts> f) =>
        availableEntrySortFields(f);

    test('1. a reliably numbered Collection opens in numeric order', () {
      final entries = [
        facts(number: 1, published: day(3), added: day(1)),
        facts(number: 2, published: day(1), added: day(2)),
      ];
      expect(
        defaultEntrySort(
          basis: OrderingBasis.explicitNumericIndex,
          available: all(entries),
        ),
        const EntrySort(EntrySortField.number, EntrySortDirection.ascending),
      );
    });

    test('2. otherwise publish date, where there is one to use', () {
      final entries = [
        facts(number: 1, published: day(3), added: day(1)),
        facts(number: 2, published: day(1), added: day(2)),
      ];
      expect(
        defaultEntrySort(
          basis: OrderingBasis.discoveryOrder,
          available: all(entries),
        ),
        const EntrySort(EntrySortField.publishDate),
        reason:
            'source_number is sortable but nothing vouched for it as a '
            'sequence, so it is offered and not defaulted to',
      );
    });

    test('3. otherwise the date it arrived', () {
      final entries = [facts(added: day(1)), facts(added: day(2))];
      for (final basis in OrderingBasis.values) {
        expect(
          defaultEntrySort(basis: basis, available: all(entries)),
          const EntrySort(EntrySortField.addedDate),
        );
      }
    });

    test('a numeric basis with nothing numbered still falls down the '
        'ladder', () {
      final entries = [
        facts(published: day(1), added: day(1)),
        facts(published: day(2), added: day(2)),
      ];
      expect(
        defaultEntrySort(
          basis: OrderingBasis.explicitNumericIndex,
          available: all(entries),
        ),
        const EntrySort(EntrySortField.publishDate),
      );
    });

    test('a Collection whose Entries answer nothing still gets a sort', () {
      expect(
        defaultEntrySort(
          basis: OrderingBasis.discoveryOrder,
          available: const [],
        ),
        const EntrySort(EntrySortField.addedDate),
      );
    });
  });

  group('resolving a remembered choice', () {
    const numbered = [EntrySortField.number, EntrySortField.addedDate];

    test('a supported choice stands, over the default', () {
      expect(
        resolveEntrySort(
          stored: const EntrySort(
            EntrySortField.addedDate,
            EntrySortDirection.descending,
          ),
          basis: OrderingBasis.explicitNumericIndex,
          available: numbered,
        ),
        const EntrySort(
          EntrySortField.addedDate,
          EntrySortDirection.descending,
        ),
      );
    });

    test('a choice the data no longer supports falls back to the default', () {
      expect(
        resolveEntrySort(
          stored: const EntrySort(EntrySortField.publishDate),
          basis: OrderingBasis.explicitNumericIndex,
          available: numbered,
        ),
        const EntrySort(EntrySortField.number),
        reason:
            'the last dated Entry can be removed; the list must not be drawn '
            'in an order nothing in it has',
      );
    });

    test('nobody having said resolves to the default', () {
      expect(
        resolveEntrySort(
          stored: null,
          basis: OrderingBasis.explicitNumericIndex,
          available: numbered,
        ),
        const EntrySort(EntrySortField.number),
      );
    });
  });

  group('the stored form', () {
    test('round-trips every field and direction', () {
      for (final field in EntrySortField.values) {
        for (final direction in EntrySortDirection.values) {
          final sort = EntrySort(field, direction);
          expect(parseEntrySort(sort.storedValue), sort);
        }
      }
    });

    test('refuses what it cannot name rather than guessing half of it', () {
      for (final stored in [
        null,
        '',
        'number',
        'number:sideways',
        'starRating:ascending',
        'number:ascending:extra',
      ]) {
        expect(
          parseEntrySort(stored),
          isNull,
          reason: '"$stored" must read as "nobody has said"',
        );
      }
    });
  });
}
