/// What a row prints for one Entry, and how much of its identity the surface
/// around it has already said.
///
/// **The regression this pins.** Inside a Collection every row printed the
/// whole title a site had written for the page — so a work whose site titles
/// its pages *"Quiet Harbour — Part 101"* produced a list in which the only
/// thing that varied was three digits at the far right of four identical
/// lines. The Collection's name is at the top of that screen; repeating it on
/// every row is noise, and it made an ordered work look unordered.
///
/// Two properties do the work here, and they pull in opposite directions on
/// purpose: **an Entry inside its Collection leads with its position**, and
/// **nothing is deleted to achieve that** — the stored title is untouched and
/// still inspectable, and a title that says something the position does not
/// survives as a second line.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/entry_presentation.dart';

void main() {
  group('inside a collection', () {
    test('a position is the identity, and the work is not named again', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        ordinal: 101,
        title: 'Quiet Harbour — Part 101',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, '101');
      expect(
        shown.secondary,
        isNull,
        reason:
            'the title said the work and the number, and the screen has '
            'already said both',
      );
    });

    test('the same reading holds whichever way round the site wrote it', () {
      for (final title in [
        'Quiet Harbour - Part 101',
        'Quiet Harbour Part 101',
        'Part 101 - Quiet Harbour',
        'Part 101 | Quiet Harbour',
        'Quiet Harbour 101. Bölüm',
      ]) {
        final shown = entryPresentation(
          context: EntryContext.withinCollection,
          ordinal: 101,
          title: title,
          collectionName: 'Quiet Harbour',
        );
        expect(shown.primary, '101', reason: title);
        expect(shown.secondary, isNull, reason: title);
      }
    });

    test('a half position keeps its half', () {
      // 100 and 99.5 are two Entries (V2-D16); printing them the same would
      // say otherwise.
      expect(
        entryPresentation(
          context: EntryContext.withinCollection,
          ordinal: 99.5,
          title: 'Quiet Harbour Part 99.5',
          collectionName: 'Quiet Harbour',
        ).primary,
        '99.5',
      );
      expect(
        entryPresentation(
          context: EntryContext.withinCollection,
          ordinal: 100,
          title: 'Quiet Harbour Part 100',
          collectionName: 'Quiet Harbour',
        ).primary,
        '100',
        reason: 'never 100.0',
      );
    });

    test('a title that says something else keeps saying it', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        ordinal: 101,
        title: 'Part 101 - The Quiet Night',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, '101');
      expect(shown.secondary, 'The Quiet Night');
    });

    test('a number the row is not about survives', () {
      // The safety of the whole rule: only a marker naming *this* Entry's
      // position is removed. On Entry 101, "Part 7" is something the title
      // knows and the row does not.
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        ordinal: 101,
        title: 'A recap of Part 7',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.secondary, 'A recap of Part 7');
    });

    test('a work name that is only a prefix of a word is left alone', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        ordinal: 4,
        title: 'Quietly, and then not',
        collectionName: 'Quiet',
      );

      expect(
        shown.secondary,
        'Quietly, and then not',
        reason:
            'whole-token, or every title with the work\'s name inside a '
            'longer word comes out mangled',
      );
    });

    test('no position falls back to the title, and invents nothing', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        title: 'Prologue',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, 'Prologue');
      expect(shown.secondary, isNull);
    });

    test('with nothing at all it prints the generic noun', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, 'Item');
    });

    test('what the source printed stands in when the library holds no '
        'title', () {
      final shown = entryPresentation(
        context: EntryContext.withinCollection,
        ordinal: 12,
        title: '',
        sourceLabel: 'Appendix B',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, '12');
      expect(shown.secondary, 'Appendix B');
    });
  });

  group('across the library', () {
    // Continue Reading, Activity, a search result: nothing above the row says
    // which work this is, so the row has to.
    test('the row names itself', () {
      final shown = entryPresentation(
        context: EntryContext.acrossLibrary,
        ordinal: 101,
        title: 'Quiet Harbour — Part 101',
        collectionName: 'Quiet Harbour',
      );

      expect(shown.primary, 'Quiet Harbour · 101');
    });

    test('with no collection to name it, the position stands alone', () {
      final shown = entryPresentation(
        context: EntryContext.acrossLibrary,
        ordinal: 101,
        title: 'Part 101',
      );

      expect(shown.primary, '101');
    });

    test('a standalone entry says where it is from, which is nowhere', () {
      final shown = entryPresentation(
        context: EntryContext.acrossLibrary,
        title: 'A one-off piece',
      );

      expect(shown.primary, 'A one-off piece');
      expect(shown.secondary, isNull);
    });
  });

  group('the entry\'s own name', () {
    test('never reaches for the position', () {
      // *"Position 5 is already taken by …"* wants to know which Entry.
      // Answering it with `5` is a tautology.
      expect(entryOwnName(title: 'The first one'), 'The first one');
      expect(entryOwnName(title: '', sourceLabel: 'Part 5'), 'Part 5');
      expect(entryOwnName(), 'Item');
    });
  });

  group('the subtitle rule on its own', () {
    test('a residue that is only the number is not a second line', () {
      expect(
        entrySubtitle(
          title: 'Quiet Harbour 101',
          ordinal: 101,
          collectionName: 'Quiet Harbour',
        ),
        isNull,
      );
      expect(
        entrySubtitle(title: '#101', ordinal: 101, collectionName: null),
        isNull,
      );
    });

    test('an empty title is no title', () {
      expect(
        entrySubtitle(title: '   ', ordinal: 3, collectionName: 'Quiet'),
        isNull,
      );
    });

    test('with no position, nothing is stripped for one', () {
      expect(
        entrySubtitle(
          title: 'Part 101 - The Quiet Night',
          ordinal: null,
          collectionName: null,
        ),
        'Part 101 - The Quiet Night',
      );
    });
  });
}
