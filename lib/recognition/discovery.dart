/// Source-scoped discovery (roadmap F3).
///
/// V1's `ObservedEntryWindow` narrows here to exactly one Source
/// (V2_ARCHITECTURE.md §1): *what one Source's reading actually showed*. That
/// is what makes absence mean something — a page is a window, and an address
/// missing from a page that never covered it has not been shown to be missing.
///
/// Two rules do the work, and both are refusals:
///
/// * **I15.** A reading of Source A may retract Source A's Locations and never
///   Source B's. The Source is part of the window, so a cross-source
///   retraction cannot even be expressed here — and the repository refuses it
///   again on its own account.
/// * **V2-D16.** An Entry is placed only under `explicitNumericIndex`, from a
///   number the source *printed*. Anything else is **unplaced**: visible,
///   readable, offered to the user. Contradictory numbering (one Source
///   printing N where another prints N − 0.5) yields two Entries, never a
///   merge — the posture `entry_identity.dart` already takes inside one
///   Source, which this file calls rather than re-derives.
///
/// Every mutation goes through the repositories, so the outbox intents that
/// belong to a discovery happen without this file knowing about sync.
library;

import '../core/url_utils.dart';
import '../data/collection_repository.dart';
import '../data/data_violations.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/entry.dart';
import '../domain/equivalence.dart';
import '../domain/invariants.dart';
import '../domain/location.dart';
import 'entry_identity.dart';

/// How a Location found by reading a Source's own listing says it was found.
///
/// One spelling, in one place: a blank basis filled in later by a second
/// reading (`check.dart`) has to record the same fact as the first reading
/// recorded here, or two rows discovered the same way would disagree about it.
const String kSourceListingBasis = 'sourceListing';

/// One address a Source's reading listed, with its two readings kept apart.
///
/// Keeping them apart is the whole point (`entry_identity.dart`): the number
/// the source *printed* is the label's, and the address's own number is
/// evidence for the identity review only. This app never adopts a number it
/// read out of a URL.
class ObservedEntryListing {
  const ObservedEntryListing({
    required this.url,
    required this.urlKey,
    required this.label,
    required this.printedNumber,
    required this.urlNumber,
  });

  /// Read both numbers from what a listing actually offers: the visible label
  /// the source wrote, and the address it linked to.
  factory ObservedEntryListing.read({required String url, String label = ''}) {
    final reading = EntryIdentityReading.read(url: url, label: label);
    return ObservedEntryListing(
      url: url,
      urlKey: normalizeUrl(url),
      label: label,
      printedNumber: reading.labelNumber,
      urlNumber: reading.urlNumber,
    );
  }

  final String url;

  /// Location identity: `normalizeUrl(url)`.
  final String urlKey;

  /// The label the source printed, verbatim.
  final String label;

  /// The number read from [label] alone — what the source printed, and the
  /// only number that may become an ordinal.
  final double? printedNumber;

  /// The number read from [url] alone. Frequently unrelated to [printedNumber]
  /// on sites that address by an opaque id, which is exactly why it is never
  /// used as a number and only ever cross-checked.
  final double? urlNumber;

  EntryIdentityReading get identityReading => EntryIdentityReading(
    url: url,
    label: label,
    labelNumber: printedNumber,
    urlNumber: urlNumber,
  );
}

/// What one Source's reading showed.
///
/// Two separable claims live here, and collapsing them was the mistake worth
/// avoiding:
///
/// * **The listing set** — every address the reading saw. Always present, and
///   always enough to record what is new.
/// * **The numeric interval** — "between these two numbers, this is the
///   complete list". Present only when the reading was unambiguously ordered,
///   not truncated, and able to place every address it saw on the number line.
///   It is what lets *absence* mean something, so it is the only thing
///   retraction is ever allowed to rest on.
///
/// A date-ordered Source has no number line at all. It still records what it
/// listed; it simply can never retract, which is the honest answer rather than
/// a reason to invent positions.
class ObservedEntryWindow {
  const ObservedEntryWindow({
    required this.sourceId,
    required this.listings,
    this.from,
    this.to,
    this.openAbove = false,
  });

  /// Build a window, or explain why there is none.
  ///
  /// Returns the window and the identity concerns found in the reading. A
  /// non-empty concern list always comes with a **null** window: when two
  /// independent readings of an address contradict each other, the reading
  /// stops and keeps the contradiction rather than repairing it.
  ///
  /// [listRecognised] false means the page was not this Source's list at all,
  /// which is also no window. [orderingConfident] and [dropped] decide only
  /// whether the interval is vouched for — an incompletely read list still
  /// saw what it saw.
  static (ObservedEntryWindow?, List<EntryIdentityConcern>) read({
    required String sourceId,
    required List<ObservedEntryListing> listings,
    required bool listRecognised,
    required bool orderingConfident,
    required bool newestFirst,
    int dropped = 0,
  }) {
    final concerns = reviewEntryIdentities(
      candidates: [for (final l in listings) l.identityReading],
      inView: [for (final l in listings) l.identityReading],
    );
    if (!listRecognised || listings.isEmpty || concerns.isNotEmpty) {
      return (null, concerns);
    }

    var lowest = double.infinity;
    var highest = double.negativeInfinity;
    var placeable = orderingConfident && dropped == 0;
    for (final listing in listings) {
      final number = listing.printedNumber;
      // One address that cannot be placed and the interval no longer
      // describes the page.
      if (number == null) {
        placeable = false;
        break;
      }
      if (number < lowest) lowest = number;
      if (number > highest) highest = number;
    }

    return (
      ObservedEntryWindow(
        sourceId: sourceId,
        listings: List.unmodifiable(listings),
        from: placeable ? lowest : null,
        to: placeable ? highest : null,
        openAbove: placeable && newestFirst,
      ),
      concerns,
    );
  }

  /// The one Source this reading is about. I15 begins here: a window cannot
  /// name two.
  final String sourceId;

  /// Everything the reading showed — the complete observation, before any
  /// question of novelty.
  final List<ObservedEntryListing> listings;

  /// The lowest position the reading covered, or null when it vouches for no
  /// interval. A hard floor: below it is where the previous page lives.
  final double? from;

  /// The highest position the reading covered.
  final double? to;

  /// Whether anything *above* [to] can be ruled out — true only for a list the
  /// page itself ran newest-first.
  final bool openAbove;

  /// Whether this reading can say anything about absence at all.
  bool get vouchesForInterval => from != null && to != null;

  Set<String> get urlKeys => {for (final l in listings) l.urlKey};

  /// Would an address at [number] have had to appear in this reading?
  bool covers(double number) {
    if (!vouchesForInterval) return false;
    return number >= from! && (openAbove || number <= to!);
  }
}

/// Whether this window's own reading is evidence that [location] is no longer
/// listed.
///
/// I15 is the first clause and lives nowhere else in this file. The rest is
/// coverage: a Location with no printed number has no position from which to
/// say the page should have shown it, and one outside the interval — or one
/// judged by a reading that vouches for no interval — was never covered.
bool windowRetracts(ObservedEntryWindow window, LocationRow location) {
  if (location.sourceId != window.sourceId) return false;
  if (location.lifecycle != LocationLifecycle.active.name) return false;
  if (window.urlKeys.contains(location.urlKey)) return false;
  final number = location.sourceNumber;
  if (number == null) return false;
  return window.covers(number);
}

/// Why one listing was not recorded. Evidence, not an exception: the rest of
/// the window still applies.
class DiscoveryRefusal {
  const DiscoveryRefusal({required this.urlKey, required this.violation});

  final String urlKey;
  final InvariantViolation violation;

  @override
  String toString() => '$urlKey — $violation';
}

/// What applying a window did. Counts and ids, so a report can be built
/// without re-deriving anything.
class DiscoveryOutcome {
  const DiscoveryOutcome({
    this.createdEntryIds = const [],
    this.unplacedEntryIds = const [],
    this.mergedEntryIds = const [],
    this.addedLocationIds = const [],
    this.retractedLocationIds = const [],
    this.refusals = const [],
    this.alreadyHeld = 0,
  });

  /// Entries this window brought into existence, placed or unplaced.
  final List<String> createdEntryIds;

  /// The subset of [createdEntryIds] that carries no position (V2-D16).
  final List<String> unplacedEntryIds;

  /// Existing Entries that gained a Location from this Source — the
  /// merge-by-equal-ordinal case, and the only merge there is.
  final List<String> mergedEntryIds;

  final List<String> addedLocationIds;
  final List<String> retractedLocationIds;
  final List<DiscoveryRefusal> refusals;

  /// Listings whose address the library already held.
  final int alreadyHeld;
}

/// Applies one Source's reading to the library.
class SourceDiscovery {
  SourceDiscovery({
    required this._entries,
    required this._collections,
    required this._index,
  });

  final EntryRepository _entries;
  final CollectionRepository _collections;
  final RecognitionIndex _index;

  /// Record what the window showed, then retract what it showed to be gone.
  Future<DiscoveryOutcome> apply(ObservedEntryWindow window) async {
    final source = await _collections.sourceById(window.sourceId);
    if (source == null) {
      return const DiscoveryOutcome(
        refusals: [DiscoveryRefusal(urlKey: '', violation: unknownRow)],
      );
    }
    final collection = await _collections.byId(source.collectionId);
    if (collection == null) {
      return const DiscoveryOutcome(
        refusals: [DiscoveryRefusal(urlKey: '', violation: unknownRow)],
      );
    }
    final basis = OrderingBasis.values.byName(collection.orderingBasis);

    final created = <String>[];
    final unplaced = <String>[];
    final merged = <String>[];
    final locations = <String>[];
    final refusals = <DiscoveryRefusal>[];
    var alreadyHeld = 0;

    for (final listing in window.listings) {
      if (await _index.lookupUrl(listing.urlKey) != null) {
        alreadyHeld++;
        continue;
      }

      final (entryId, violation) = await _entryFor(
        collectionId: collection.id,
        basis: basis,
        listing: listing,
        created: created,
        unplaced: unplaced,
        merged: merged,
      );
      if (violation != null || entryId == null) {
        refusals.add(
          DiscoveryRefusal(
            urlKey: listing.urlKey,
            violation: violation ?? unknownRow,
          ),
        );
        continue;
      }

      final (location, locationViolation) = await _entries.addLocation(
        entryId: entryId,
        url: listing.url,
        urlKey: listing.urlKey,
        sourceId: window.sourceId,
        sourceLabel: listing.label,
        sourceNumber: listing.printedNumber,
        discoveryBasis: kSourceListingBasis,
      );
      if (locationViolation != null || location == null) {
        refusals.add(
          DiscoveryRefusal(
            urlKey: listing.urlKey,
            violation: locationViolation ?? unknownRow,
          ),
        );
        continue;
      }
      locations.add(location.id);
    }

    final retracted = await _retract(window, refusals);

    return DiscoveryOutcome(
      createdEntryIds: created,
      unplacedEntryIds: unplaced,
      mergedEntryIds: merged,
      addedLocationIds: locations,
      retractedLocationIds: retracted,
      refusals: refusals,
      alreadyHeld: alreadyHeld,
    );
  }

  /// Which Entry this listing belongs to, creating one when it is new.
  ///
  /// The decision is the domain's ([crossSourceEquivalence]) and the gate is
  /// V2-D16's: a position is written only when the Collection's ordering basis
  /// supports it *and* the source printed a number. Otherwise the Entry is
  /// unplaced, which is an answer.
  Future<(String?, InvariantViolation?)> _entryFor({
    required String collectionId,
    required OrderingBasis basis,
    required ObservedEntryListing listing,
    required List<String> created,
    required List<String> unplaced,
    required List<String> merged,
  }) async {
    final printed = listing.printedNumber;
    final placeable = basis.supportsCrossSourceMerge && printed != null;
    final candidate = placeable
        ? await _index.lookupOrdinal(collectionId, printed)
        : null;

    final decision = crossSourceEquivalence(
      basis: basis,
      existingOrdinal: candidate?.ordinal,
      observedOrdinal: printed,
    );

    if (decision == EquivalenceDecision.sameEntry && candidate != null) {
      merged.add(candidate.id);
      return (candidate.id, null);
    }

    final place = placeable && decision == EquivalenceDecision.distinctEntries;
    final (entry, violation) = await _entries.createInCollection(
      collectionId: collectionId,
      ordinal: place ? printed : null,
      placement: place ? Placement.placed : Placement.unplaced,
      title: listing.label,
    );
    if (violation != null || entry == null) return (null, violation);
    created.add(entry.id);
    if (!place) unplaced.add(entry.id);
    return (entry.id, null);
  }

  /// Retract this Source's own Locations that the reading covered and did not
  /// show. Never another Source's (I15), and never a deletion: retraction
  /// writes a lifecycle and does not sync (V2_SYNC.md §5).
  Future<List<String>> _retract(
    ObservedEntryWindow window,
    List<DiscoveryRefusal> refusals,
  ) async {
    final retracted = <String>[];
    // A reading that vouches for no interval can rule nothing out, so there
    // is nothing to look through.
    if (!window.vouchesForInterval) return retracted;
    // The candidates are this Source's own Locations and only ever those
    // (I15), read in one indexed pass rather than walked Entry by Entry.
    for (final location in await _entries.locationsOfSource(window.sourceId)) {
      if (!windowRetracts(window, location)) continue;
      final violation = await _entries.retractLocation(
        location.id,
        readingSourceId: window.sourceId,
      );
      if (violation != null) {
        refusals.add(
          DiscoveryRefusal(urlKey: location.urlKey, violation: violation),
        );
        continue;
      }
      retracted.add(location.id);
    }
    return retracted;
  }
}
