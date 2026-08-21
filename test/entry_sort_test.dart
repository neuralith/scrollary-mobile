import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/collection_detail_screen.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/library/entry_labels.dart';

/// Entry ordering: newest first by default, flippable, and derived from the
/// parsed entry number rather than from whatever order the site listed them.
void main() {
  var seq = 0;

  Entry entry({
    required String id,
    double? number,
    String? label,
    DateTime? savedAt,
  }) => Entry(
    host: '',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    id: id,
    collectionId: 'collection-1',
    title: label ?? id,
    sourceUrl: 'https://x.example/guide/foo/$id',
    urlKey: 'https://x.example/guide/foo/$id',
    artifactFormat: 'imageSequence',
    saveStatus: 'complete',
    contentPath: 'library/collection-1/entries/$id',
    savedAt: savedAt ?? DateTime(2026, 7, 20),
    detectedAssetCount: 1,
    storedAssetCount: 1,
    entryOrder: ++seq,
    byteSize: 1,
    entryNumber: number,
    sourceMarker: label,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

  setUp(() => seq = 0);

  List<String> ids(List<Entry> list) => list.map((c) => c.id).toList();

  test('the default is newest first', () {
    // Fed in the order a site might list them — which is not an ordering.
    final list = [
      entry(id: 'b', number: 385),
      entry(id: 'c', number: 386),
      entry(id: 'a', number: 384),
    ];

    expect(ids(sortEntries(list, EntrySort.newestFirst)), ['c', 'b', 'a']);
    expect(entrySortFromName(null), EntrySort.newestFirst);
  });

  test('ascending is reading order', () {
    final list = [
      entry(id: 'c', number: 386),
      entry(id: 'a', number: 384),
      entry(id: 'b', number: 385),
    ];
    expect(ids(sortEntries(list, EntrySort.oldestFirst)), ['a', 'b', 'c']);
  });

  test('decimals sit between their neighbours, both ways', () {
    final list = [
      entry(id: 'x386', number: 386),
      entry(id: 'x385', number: 385),
      entry(id: 'x385h', number: 385.5),
    ];

    expect(ids(sortEntries(list, EntrySort.oldestFirst)), [
      'x385',
      'x385h',
      'x386',
    ]);
    expect(ids(sortEntries(list, EntrySort.newestFirst)), [
      'x386',
      'x385h',
      'x385',
    ]);
  });

  test('unnumbered entries keep a stable place, not a random one', () {
    // No number to compare: save sequence decides, and the two directions
    // are exact mirrors so an Extra keeps the same neighbours.
    final list = [
      entry(id: 'n1', number: 1),
      entry(id: 'extra', label: 'Extra'),
      entry(id: 'n2', number: 2),
      entry(id: 'prologue', label: 'Prologue'),
    ];

    final up = ids(sortEntries(list, EntrySort.oldestFirst));
    final down = ids(sortEntries(list, EntrySort.newestFirst));
    expect(up, ['n1', 'n2', 'extra', 'prologue'], reason: 'numbered first');
    expect(down, up.reversed.toList(), reason: 'one ordering, mirrored');
  });

  test('sorting is stable across repeated calls', () {
    final list = [
      entry(id: 'a', label: 'Extra'),
      entry(id: 'b', label: 'Special'),
    ];
    expect(
      ids(sortEntries(list, EntrySort.newestFirst)),
      ids(sortEntries([...list.reversed], EntrySort.newestFirst)),
    );
  });

  group('the preference persists', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('nothing stored means newest first', () async {
      expect(
        entrySortFromName(await db.setting(kEntrySortKey)),
        EntrySort.newestFirst,
      );
    });

    test('a choice survives a reload', () async {
      await db.setSetting(kEntrySortKey, EntrySort.oldestFirst.name);
      expect(
        entrySortFromName(await db.setting(kEntrySortKey)),
        EntrySort.oldestFirst,
      );

      await db.setSetting(kEntrySortKey, EntrySort.newestFirst.name);
      expect(
        entrySortFromName(await db.setting(kEntrySortKey)),
        EntrySort.newestFirst,
      );
    });

    test('an unrecognised stored value falls back to the default', () async {
      await db.setSetting(kEntrySortKey, 'sideways');
      expect(
        entrySortFromName(await db.setting(kEntrySortKey)),
        EntrySort.newestFirst,
      );
    });
  });

  group('display labels', () {
    // Chapter is one of eight display styles, reached only by a confident
    // detection. It is not the canonical model, and it is not the default.
    const chapters = EntryLabels(EntryLabelStyle.chapter);

    test('a number becomes the label, in the style the shape earned', () {
      expect(
        entryDisplayLabel(
          labels: chapters,
          number: 487,
          sourceMarker: '487. part',
        ),
        'Chapter 487',
      );
      expect(
        entryDisplayLabel(labels: chapters, number: 487.5),
        'Chapter 487.5',
      );
      expect(
        entryDisplayLabel(
          labels: const EntryLabels(EntryLabelStyle.page),
          number: 3,
        ),
        'Page 3',
      );
    });

    test('a style that does not take a number never prints one', () {
      // An article has no ordinal the source declared, so numbering it would
      // invent an ordering. The source's own words win instead.
      expect(
        entryDisplayLabel(
          labels: const EntryLabels(EntryLabelStyle.article),
          number: 12,
          sourceMarker: 'On typography',
        ),
        'On typography',
      );
      expect(
        entryDisplayLabel(
          labels: kGenericEntryLabels,
          number: 12,
          title: 'A saved page',
        ),
        'A saved page',
      );
    });

    test(
      'no number falls back to the source marker, never an invented one',
      () {
        expect(
          entryDisplayLabel(labels: chapters, sourceMarker: 'Prologue'),
          'Prologue',
        );
        expect(
          entryDisplayLabel(labels: chapters, sourceMarker: 'Extra'),
          'Extra',
        );
        expect(
          entryDisplayLabel(
            labels: chapters,
            sourceMarker: '  ',
            title: 'Side Story',
          ),
          'Side Story',
        );
      },
    );

    test('with nothing to go on, the generic noun is the last resort', () {
      expect(entryDisplayLabel(labels: kGenericEntryLabels), 'Saved item');
      expect(entryDisplayLabel(labels: chapters), 'Chapter');
    });

    test('an uncertain shape is never given a specific noun', () {
      // The rule the whole label system exists for.
      final labels = labelsFromNames(
        contentKind: 'sequentialText',
        confidence: 'low',
        sequenceKind: 'numberedPagination',
      );
      expect(labels.style, EntryLabelStyle.savedItem);
      expect(
        entryDisplayLabel(labels: labels, number: 12),
        'Saved item',
        reason: 'a low-confidence detection must not print "Chapter 12"',
      );
    });
  });
}
