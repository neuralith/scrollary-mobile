/// Checking every Collection at once.
///
/// The regression this pins is the largest one the forensic audit found: V1's
/// *"many collections, one visible operation"* went out in two commits —
/// `f1497bf` took the surface with the V1 library screens, `ac34124` took the
/// engine 34 minutes later — under preconditions that said nothing about it.
/// No lane replaced it, nothing noticed, and five documents went on promising
/// it existed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/library_check_flow.dart';

void main() {
  LibraryCheckEntry checked(
    String name, {
    int found = 0,
    bool failed = false,
  }) => LibraryCheckEntry(
    collectionId: name,
    name: name,
    found: found,
    failed: failed,
  );

  LibraryCheckEntry skipped(String name, LibraryCheckSkip why) =>
      LibraryCheckEntry(collectionId: name, name: name, skip: why);

  LibraryCheckReport report(
    List<LibraryCheckEntry> entries, {
    bool stopped = false,
  }) => LibraryCheckReport(entries: entries, stopped: stopped);

  group('what the pass came to', () {
    test('leads with where the new reading is', () {
      // The point of checking everything is to make new reading visible, so
      // the collections worth opening lead the sentence.
      final sentence = libraryCheckSentence(
        report([
          checked('Alpha', found: 3),
          checked('Beta', found: 2),
          checked('Gamma'),
          checked('Delta'),
        ]),
      );

      expect(sentence, contains('Checked 4 collections'));
      expect(sentence, contains('5 new entries across 2 collections'));
      expect(sentence, contains('2 up to date'));
    });

    test('a library with nothing new says so without a count of zero', () {
      final sentence = libraryCheckSentence(
        report([checked('Alpha'), checked('Beta')]),
      );

      expect(sentence, contains('2 up to date'));
      expect(sentence, isNot(contains('0 new')));
    });

    test('what could not be checked is counted, never passed over', () {
      final sentence = libraryCheckSentence(
        report([
          checked('Alpha', found: 1),
          skipped('Beta', LibraryCheckSkip.noPreferredSource),
          checked('Gamma', failed: true),
        ]),
      );

      expect(sentence, contains('2 need attention'));
    });

    test('a stopped pass says how far it got', () {
      final sentence = libraryCheckSentence(
        report([checked('Alpha', found: 2)], stopped: true),
      );

      expect(sentence, startsWith('Stopped after 1 of them.'));
    });

    test('an empty library is not a failure', () {
      expect(
        libraryCheckSentence(report([])),
        'There is nothing in your library to check yet.',
      );
    });

    test('a library where nothing could be checked says that plainly', () {
      final sentence = libraryCheckSentence(
        report([
          skipped('Alpha', LibraryCheckSkip.archived),
          skipped('Beta', LibraryCheckSkip.noSource),
        ]),
      );

      expect(sentence, contains('None of the 2 collections'));
      expect(sentence, isNot(contains('up to date')));
    });
  });

  group('the report itself', () {
    test('separates checked from skipped', () {
      final r = report([
        checked('Alpha', found: 4),
        skipped('Beta', LibraryCheckSkip.restricted),
        checked('Gamma', failed: true),
      ]);

      expect(r.checked.map((e) => e.name), ['Alpha', 'Gamma']);
      expect(r.skipped.map((e) => e.name), ['Beta']);
      expect(r.withNews.map((e) => e.name), ['Alpha']);
      expect(r.failed.map((e) => e.name), ['Gamma']);
      expect(r.newEntries, 4);
      expect(
        r.upToDate,
        0,
        reason: 'a collection that failed is not a collection that is current',
      );
    });

    test('every reason a collection can be skipped is a named one', () {
      // "Skipped with a reason" rather than silently passed over: an archived
      // collection, one with no site, one with several and no preference, and
      // one on a service this app does not read from.
      expect(LibraryCheckSkip.values, hasLength(4));
    });
  });
}
