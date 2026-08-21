import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/recognition/entry_identity.dart';

/// The safety net under discovered entry numbers.
///
/// Its job is narrow on purpose. It is not a numbering scheme and it does not
/// know what the next number "should" be — collections skip, restart, count in
/// twos, use decimals, and number by season or volume, and every one of those
/// is legitimate. It asks one question: do this entry's two independent
/// readings contradict each other, on a list that has already shown the two
/// readings mean the same thing?
///
/// Most of what follows is therefore about what must **not** be refused. A
/// safety net that fires on ordinary collections is worse than no net: it turns
/// a working update check into a permanent failure, and the user cannot tell
/// the difference between "this site changed" and "this app is wrong".
void main() {
  const host = 'https://a.example';

  EntryIdentityReading row(String label, String path) =>
      EntryIdentityReading.read(url: '$host$path', label: label);

  /// The common shape: a list whose labels and addresses agree throughout.
  List<EntryIdentityReading> run(List<num> numbers) => [
    for (final n in numbers) row('Entry $n', '/guide/foo/$n'),
  ];

  List<EntryIdentityConcern> review(
    List<EntryIdentityReading> candidates,
    List<EntryIdentityReading> inView,
  ) => reviewEntryIdentities(candidates: candidates, inView: inView);

  group('readings', () {
    test('are parsed independently, never from each other', () {
      final r = row('Entry 101 2 weeks ago', '/guide/foo/101');
      expect(r.labelNumber, 101);
      expect(r.urlNumber, 101);
      expect(r.readingsAgree, isTrue);
    });

    test('a label with no number leaves nothing to cross-check', () {
      final r = row('Prologue', '/guide/foo/prologue');
      expect(r.labelNumber, isNull);
      expect(r.isCrossCheckable, isFalse);
    });

    test('an address with no number leaves nothing to cross-check', () {
      final r = row('Entry 12', '/guide/foo/the-awakening');
      expect(r.labelNumber, 12);
      expect(r.urlNumber, isNull);
      expect(r.isCrossCheckable, isFalse);
    });
  });

  group('numbering a real collection may use', () {
    test('consecutive numbers', () {
      final all = run([100, 101, 102, 103]);
      expect(review(all, all), isEmpty);
    });

    test('a gap where an entry was never published', () {
      final all = run([100, 101, 103]);
      expect(review(all, all), isEmpty);
    });

    test('decimals between whole numbers', () {
      final all = [
        row('Entry 12', '/guide/foo/12'),
        row('Entry 12.5', '/guide/foo/12-5'),
        row('Entry 13', '/guide/foo/13'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('increments that are not one', () {
      final all = run([10, 20, 30, 40]);
      expect(
        review(all, all),
        isEmpty,
        reason: 'nothing here requires a step of exactly 1',
      );
    });

    test('a jump of any size, as long as the address agrees', () {
      // A collection that restarts its numbering, or publishes a special at
      // 520 among 100s. Both readings say 520, so there is no contradiction to
      // find — and inventing a rule about how far entries may jump is exactly
      // what this file must not do.
      final all = [
        ...run([100, 101, 102]),
        row('Entry 520', '/guide/foo/520'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('a label the address rounds off', () {
      // The site's slug drops the decimal. A disagreement smaller than a whole
      // entry is a rounded address, never a corrupted digit.
      final all = [
        ...run([12, 13]),
        row('Entry 12.5', '/guide/foo/12'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('an address that is an opaque id, agreeing with nothing', () {
      // Ordinary and correct: "Entry 5" living at /posts/88213. The two
      // readings are different vocabularies, so they disagree on every single
      // row — and a disagreement therefore carries no information at all.
      // This is the case that keeps the net off most of the web.
      final all = [
        row('Entry 3', '/posts/88211'),
        row('Entry 4', '/posts/88212'),
        row('Entry 5', '/posts/88213'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('an unnumbered entry among numbered ones', () {
      final all = [
        ...run([100, 101]),
        row('Side Story', '/guide/foo/side'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('a season or volume in the label', () {
      final all = [
        row('Season 2 Part 1', '/guide/foo/part-1'),
        row('Season 2 Part 2', '/guide/foo/part-2'),
        row('Season 2 Part 3', '/guide/foo/part-3'),
      ];
      expect(
        review(all, all),
        isEmpty,
        reason: 'the more specific word wins in both readings alike',
      );
    });

    test('a list with nothing to compare against', () {
      // No entry anywhere reads the same number from both sources, so the
      // review has no ground to stand on and says so by staying silent.
      final all = [
        row('Entry 3', '/guide/foo/the-awakening'),
        row('Prologue', '/guide/foo/prologue'),
      ];
      expect(review(all, all), isEmpty);
    });
  });

  group('a reading the evidence contradicts', () {
    // The reported failure: a relative timestamp welded onto the label by a
    // text extraction that lost the boundary between two elements. Every
    // address is clean, and one row's metadata began with a letter so its two
    // readings still agree — which is what proves the site numbers its
    // addresses the way it numbers its labels.
    final asRead = [
      row('Entry 1003 weeks ago', '/guide/foo/100'),
      row('Entry 1012 weeks ago', '/guide/foo/101'),
      row('Entry 1022 weeks ago', '/guide/foo/102'),
      row('Entry 103last week', '/guide/foo/103'),
      row('Entry 1045 days ago', '/guide/foo/104'),
    ];

    test('is reported, with both readings and what it was judged against', () {
      final concerns = review([asRead[4]], asRead);

      expect(concerns, hasLength(1));
      final only = concerns.single;
      expect(only.url, '$host/guide/foo/104');
      expect(only.labelNumber, 1045);
      expect(only.urlNumber, 104);
      expect(only.nearbyNumbers, [100.0, 101.0, 102.0, 103.0, 104.0]);
      expect(only.doubt, EntryIdentityDoubt.labelFarFromAddressRun);
      expect(only.label, 'Entry 1045 days ago');
    });

    test('every corrupted row is caught, and the intact one is not', () {
      final concerns = review(asRead, asRead);

      expect(concerns.map((c) => c.urlNumber), [100.0, 101.0, 102.0, 104.0]);
      expect(
        concerns.map((c) => c.url),
        isNot(contains('$host/guide/foo/103')),
        reason: 'the row whose readings agree is the evidence, not a suspect',
      );
    });

    test('the same fault from metadata that is not a date', () {
      // A rating welded on instead of a timestamp. Nothing about this was ever
      // specific to dates.
      final all = [
        ...run([100, 102, 103]),
        row('Entry 1014.7', '/guide/foo/101'),
      ];
      final concerns = review(all, all);

      expect(concerns, hasLength(1));
      expect(concerns.single.labelNumber, 1014.7);
      expect(concerns.single.urlNumber, 101);
    });

    test('a view count welded on', () {
      final all = [
        ...run([100, 102, 103]),
        row('Entry 10112k views', '/guide/foo/101'),
      ];
      expect(review(all, all), hasLength(1));
    });

    test('one corrupted row among many intact ones', () {
      final all = [
        ...run([100, 101, 102, 103, 105, 106]),
        row('Entry 1042 weeks ago', '/guide/foo/104'),
      ];
      final concerns = review(all, all);

      expect(concerns.map((c) => c.urlNumber), [104.0]);
    });

    test('only the candidates asked about are judged', () {
      // A corrupted row that is not up for persistence is evidence, not a
      // verdict — the review answers about what the caller is about to write.
      final concerns = review([asRead[3]], asRead);
      expect(concerns, isEmpty);
    });
  });

  group('the edge of what can be claimed', () {
    test('a disagreement that is not extreme is left alone', () {
      // Deliberate. The label says 13 where its address says 12, on a list
      // that otherwise agrees. That is odd, but a site whose slug lags its
      // label by one is a real thing and inventing a verdict here would block
      // legitimate collections to catch a fault this narrow.
      final all = [
        ...run([10, 11, 12, 14, 15]),
        row('Entry 13', '/guide/foo/12'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('gluing onto a small number is below the threshold, and admitted', () {
      // "Entry 1" beside "2 weeks ago" glues to 12, which is genuinely
      // indistinguishable from a collection that reaches entry 12. The net
      // does not catch this, and pretending otherwise would mean guessing.
      final all = [
        ...run([1, 2, 3, 4, 5]),
        row('Entry 12', '/guide/foo/1'),
      ];
      expect(
        review(all, all),
        isEmpty,
        reason: 'a small run cannot tell corruption from an ordinary number',
      );
    });

    test('an address run of zero cannot make everything suspicious', () {
      final all = [
        row('Entry 0', '/guide/foo/0'),
        row('Entry 5000', '/guide/foo/0'),
      ];
      expect(review(all, all), isEmpty);
    });

    test('nothing to judge is not a concern', () {
      expect(review(const [], run([1, 2, 3])), isEmpty);
    });
  });
}
