/// Whether a discovered entry's *number* is supported by the evidence the
/// discovery already had in hand.
///
/// This is a safety net, not a numbering scheme. It exists because the number
/// an entry is discovered with is durable: it decides reading order, and it
/// becomes the checkpoint the next update check measures novelty against. A
/// wrong one does not merely display wrong — it silently ends discovery for
/// that collection, because everything real afterwards compares as "older than
/// what we already have".
///
/// So the question asked here is deliberately narrow. Not "is this number
/// plausible" — plenty of collections number in twos, restart at a season
/// boundary, skip, or use decimals, and none of that is this file's business.
/// The question is: **do the two independent readings of this entry contradict
/// each other, in a way the rest of the list says they should not?**
///
/// Nothing here repairs anything. There is no "drop the last digit", no
/// "assume the next number", no "prefer the URL". A contradiction the evidence
/// cannot resolve stops the operation and keeps the contradiction; guessing
/// which reading was right would just trade one class of wrong data for
/// another, quieter one.
library;

import '../library/collection_identity.dart';

/// The sentence a refusal carries. Says what the app could not do, not what
/// the user was trying to do, and names no internals.
const String kEntryIdentityUnreliableMessage =
    'Could not reliably identify one or more entries.';

/// Why a candidate was not supported.
///
/// Named rather than free text so a future report can group these and explain
/// them, and so a new reason cannot be added by writing a new sentence.
enum EntryIdentityDoubt {
  /// The label's number sits an order of magnitude away from the run of
  /// numbers the addresses themselves spell out, on a list that has already
  /// shown its labels and addresses agree.
  labelFarFromAddressRun,
}

/// One entry as discovery read it — from both sources, **independently**.
///
/// Keeping the two readings apart is the whole point. `parseEntryNumber` takes
/// a title and a URL together and returns one answer, so by the time discovery
/// holds a number it can no longer tell whether the label and the address ever
/// agreed. Here they are parsed separately and both kept.
class EntryIdentityReading {
  const EntryIdentityReading({
    required this.url,
    required this.label,
    required this.labelNumber,
    required this.urlNumber,
  });

  /// Parse both readings from what discovery actually has: the visible text of
  /// the entry's label, and its address.
  factory EntryIdentityReading.read({
    required String url,
    required String label,
  }) => EntryIdentityReading(
    url: url,
    label: label,
    labelNumber: parseEntryNumber(title: label),
    urlNumber: parseEntryNumber(url: url),
  );

  final String url;

  /// The visible text the source labelled this entry with.
  final String label;

  /// The number read from [label] alone. Null when the label carries none —
  /// `"Prologue"`, `"Extra"`, an image-only link.
  final double? labelNumber;

  /// The number read from [url] alone. Null when the address carries none, and
  /// frequently *unrelated* to [labelNumber] on sites that address entries by
  /// an opaque id. That is exactly why a disagreement is not evidence on its
  /// own — see [reviewEntryIdentities].
  final double? urlNumber;

  /// Both readings exist, so they can be compared at all.
  bool get isCrossCheckable => labelNumber != null && urlNumber != null;

  /// The two readings are the same number.
  bool get readingsAgree => isCrossCheckable && labelNumber == urlNumber;
}

/// A candidate whose identity the evidence does not support.
///
/// Carries the evidence, not a conclusion, so the operation that refused it can
/// be explained later without re-deriving anything.
class EntryIdentityConcern {
  const EntryIdentityConcern({
    required this.url,
    required this.label,
    required this.labelNumber,
    required this.urlNumber,
    required this.nearbyNumbers,
    required this.doubt,
  });

  final String url;
  final String label;
  final double? labelNumber;
  final double? urlNumber;

  /// The addresses' own numbers this candidate was judged against, ascending.
  final List<double> nearbyNumbers;

  final EntryIdentityDoubt doubt;

  /// One line for the operation log. Internal — a user-facing report is a
  /// separate concern and builds itself from the fields above.
  String get summary {
    final nearby = nearbyNumbers.map(_plain).join(', ');
    return 'entry identity not supported: label reads ${_plain(labelNumber)}, '
        'address reads ${_plain(urlNumber)}, addresses nearby run [$nearby] '
        '— $url';
  }

  static String _plain(double? n) {
    if (n == null) return 'no number';
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
  }
}

/// How far outside the addresses' own run a label number must sit before it is
/// called extreme.
///
/// Welding one digit onto a number multiplies it by roughly ten, so five times
/// catches that with room to spare while staying far away from anything a real
/// list does. A page showing entries 100–104 does not also contain entry 520;
/// if it genuinely did, that entry's address would say 520 too, and agreeing
/// readings are never questioned.
const double _extremeFactor = 5;

/// Which of [candidates] the evidence does not support.
///
/// [inView] is everything the discovery could see — the candidates included.
/// It is the evidence; [candidates] are what is being judged. An empty result
/// means "nothing here contradicts itself", which is the answer in the
/// overwhelming majority of cases and the only one that lets work proceed.
///
/// Two conditions have to hold before a single candidate is doubted, and they
/// are ordered so the cheap disqualifier runs first:
///
/// 1. **The source must demonstrably number its addresses the way it numbers
///    its labels.** At least one entry in view has to read the same number
///    from both. Without that, the readings are simply different vocabularies
///    — `"Entry 5"` living at `/posts/88213` is ordinary, correct, and
///    disagrees on every row — and a disagreement carries no information at
///    all. This single check is what keeps opaque-id sites out of the net.
/// 2. **The label must be an extreme discontinuity** against the run the
///    addresses spell out, not merely different from its own address. A label
///    that says 12.5 where the address says 12 is a site rounding its slug; a
///    label that says 1012 where the addresses in view run 100 to 104 is not a
///    numbering convention.
///
/// Everything else is left alone on purpose. Gaps, non-unit increments,
/// decimals, restarts, unnumbered entries and labels with no address number
/// are all legitimate, and none of them can reach a concern from here.
List<EntryIdentityConcern> reviewEntryIdentities({
  required List<EntryIdentityReading> candidates,
  required List<EntryIdentityReading> inView,
}) {
  if (candidates.isEmpty) return const [];

  // 1. Does this source number addresses and labels the same way? One
  //    agreement is the entire evidence, and its absence ends the review.
  if (!inView.any((r) => r.readingsAgree)) return const [];

  // The run the addresses themselves spell out. Addresses are used as the
  // reference rather than labels because a text-extraction fault corrupts
  // labels wholesale — in the failure this was built for, four of five labels
  // were wrong and judging them against each other would have convicted the
  // one that was right.
  final addressRun = inView.map((r) => r.urlNumber).whereType<double>().toList()
    ..sort();
  if (addressRun.isEmpty) return const [];
  final lowest = addressRun.first;
  final highest = addressRun.last;
  if (highest <= 0) return const [];

  final concerns = <EntryIdentityConcern>[];
  for (final candidate in candidates) {
    if (!candidate.isCrossCheckable) continue;
    final label = candidate.labelNumber!;
    final url = candidate.urlNumber!;

    // A disagreement smaller than a whole entry is a decimal or a rounded
    // slug, never a corrupted digit. Excluded before anything else is asked.
    if ((label - url).abs() < 1) continue;

    // 2. Extreme in either direction. The low side is guarded on a positive
    //    lowest so a run containing 0 cannot make everything suspicious.
    final farAbove = label >= highest * _extremeFactor;
    final farBelow = lowest > 0 && label <= lowest / _extremeFactor;
    if (!farAbove && !farBelow) continue;

    concerns.add(
      EntryIdentityConcern(
        url: candidate.url,
        label: candidate.label,
        labelNumber: label,
        urlNumber: url,
        nearbyNumbers: addressRun,
        doubt: EntryIdentityDoubt.labelFarFromAddressRun,
      ),
    );
  }
  return concerns;
}
