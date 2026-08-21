/// Preferred-source update checking (roadmap F4).
///
/// V1's `lib/library/update_checker.dart` asked "has this collection published
/// anything since?" of a Collection, because in V1 a Collection had exactly one
/// site. V2 splits that: a Collection has several Sources, and **one ordinary
/// check reads one Source** — the Collection's preferred one. Checking another
/// Source is [SourceCheck.checkSource], a separate call the user makes
/// deliberately. Nothing here iterates a Collection's Sources, and nothing here
/// falls back from one Source to another: a check that could quietly widen is a
/// check whose bound is not the number the user chose.
///
/// **What survives from V1, unchanged in substance:**
///
/// * The reading is a window, and absence only means something inside it
///   (`discovery.dart`, which owns the rule and is called rather than
///   re-derived).
/// * Novelty is measured against a **checkpoint** — the highest number this
///   Source has already shown — so a library holding parts 100–105 of 400 finds
///   106 onwards rather than backfilling 1–99. The checkpoint is rebuilt from
///   rows that are still true: a Location this very reading retracts does not
///   get to hold the high-water mark (V1 `update_checker.dart:614-637`).
/// * A re-listed address is judged for **fill-in only** — a blank the source
///   has now filled, never an overwrite of something already established
///   (V1 `AppDatabase.refreshDiscoveredEntry`, `storage/database.dart:1106`).
/// * **"Finished" and "the reading was cut short" are different outcomes.** A
///   check may only say `upToDate` after a reading it can vouch for; anything
///   else is `stopped` with a named reason.
/// * Every ceiling is a number the caller was handed by the user
///   ([SourceCheckLimits] has no defaults), the stop is cooperative and asked
///   between steps, and the restricted-site policy is asked here on this
///   file's own account as well as by whatever drives the browser.
///
/// **What does not live here.** How a page is opened, scrolled, settled and
/// read is device knowledge, and it sits behind [SourceObservationSource] for
/// the same reason capture's does behind `PageCaptureSource`: everything this
/// file decides has to be provable on a host with no WebView anywhere near it.
library;

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/location.dart' show LocationLifecycle;
import '../domain/source.dart' as domain;
import '../save/capture_policy.dart';
import 'discovery.dart';
import 'entry_identity.dart';

/// How much of someone else's site one check may open.
///
/// No defaults, deliberately. V1's `UpdateCheckConfig` carried them because one
/// controller owned every check; here the ceilings arrive from the surface that
/// asked, which is where the user's number is. There is no value of either
/// field that means "unlimited": zero or less simply reads nothing, and the
/// check says it stopped at the ceiling rather than reporting a clean result.
class SourceCheckLimits {
  const SourceCheckLimits({
    required this.maxPages,
    required this.maxNewEntries,
  });

  /// Pages of this Source's listing one check may read. The first page counts.
  final int maxPages;

  /// Entries one check may bring into the library. A reading cut by this
  /// ceiling vouches for no interval, so it can never also retract.
  final int maxNewEntries;
}

/// Why a check stopped short of a reading it could vouch for.
///
/// Named rather than free text, in the style of `save/stop_conditions.dart`, so
/// a new reason cannot be introduced by writing a new sentence — and so
/// "the check did what it was asked and there is more" can never be reported as
/// the same thing as "the library is up to date".
enum SourceCheckStop {
  // --- the check did what it was asked, and there is more ------------------
  /// The page ceiling was reached with more of the listing to read.
  pageLimitReached,

  /// The new-entry ceiling was reached. The rest is left for the next check.
  newEntryLimitReached,

  // --- the user ------------------------------------------------------------
  cancelledByUser,

  // --- the reading ---------------------------------------------------------
  /// The page could not be read at all.
  listingUnreadable,

  /// The page was not this Source's listing. Not evidence of being up to date.
  listingUnrecognised,

  /// The reading itself left out addresses it saw, so it stopped short of what
  /// the page held and cannot be used to conclude anything about absence.
  listingTruncated,

  /// The listing's own ordering was ambiguous, so "nothing above the
  /// checkpoint" may only mean we could not tell what was above it.
  listingOrderingAmbiguous,

  /// The reading contradicted itself about an address's number. Nothing is
  /// written: reading on would be reading the rest of a page we have just
  /// shown we are reading wrongly.
  entryIdentityUnsupported,

  // --- this app's own policy ----------------------------------------------
  /// The Source is on a commercial content service this app does not capture
  /// from. Not something the site did — see `save/capture_policy.dart`.
  captureRestrictedForSite,

  // --- there was nothing to check -----------------------------------------
  /// The Source, or the Collection that owns it, is not in this library.
  sourceUnknown,

  /// The Source is dead, or a `resolvedInto` pointer led nowhere.
  sourceNotReadable,

  /// The Collection has several Sources and none of them is preferred. Which
  /// one to read is the user's answer, never this file's.
  preferredSourceNotChosen,

  /// The Collection is archived, so following has stopped (V2-D13) and there
  /// is nothing to keep current.
  collectionNotFollowed;

  /// The app withheld the check from its own static list, rather than the site
  /// refusing anything. The one user-facing sentence is
  /// [kCaptureRestrictedMessage] and lives nowhere else.
  bool get isCaptureRestricted =>
      this == SourceCheckStop.captureRestrictedForSite;
}

/// What a check can say about the library afterwards. Three answers, and each
/// of them is one.
enum SourceCheckState {
  /// This Source offered at least one address the library did not hold.
  updatesAvailable,

  /// A reading this check can vouch for showed nothing new.
  upToDate,

  /// The reading was cut short, so *nothing new was found* and *there is
  /// nothing new* are not the same statement and only the first is made.
  stopped,
}

/// A field a re-listing establishes that the stored Location does not have.
enum SourceFillInField { sourceLabel, sourceNumber, discoveryBasis }

/// What one re-listed address's second reading established.
///
/// V1's `refreshDiscoveredEntry` returned the names of the fields it wrote;
/// this is the same answer, computed by [sourceFillIn] and reported the same
/// way. Empty is the ordinary result.
class SourceFillIn {
  const SourceFillIn({
    required this.locationId,
    required this.urlKey,
    required this.fields,
    this.disagreedNumber,
  });

  final String locationId;
  final String urlKey;

  /// Blanks this reading filled in. Never a field that already had a value.
  final Set<SourceFillInField> fields;

  /// The number the source now prints where a **different** one is already
  /// stored. Reported and never acted on: replacing a stored number on the
  /// strength of a second reading trades a known value for a guess, and that
  /// number is the checkpoint the next check measures against
  /// (V1 `update_checker.dart:1156-1163`).
  final double? disagreedNumber;

  bool get isEmpty => fields.isEmpty && disagreedNumber == null;
}

/// Whether a second reading of an address may write anything, and what.
///
/// The judgement is V1's `refreshDiscoveredEntry`, retargeted from V1's fused
/// entry row onto the Location that carries the same facts in V2:
///
/// * **label** — V1 replaced a discovered row's title when the source printed a
///   different non-empty one, because that title *was* the source's own label
///   and there was no user-set title to protect. In V2 that field is
///   `source_label`, which is a transcription by construction, so the same rule
///   applies to it — and to nothing else. The Entry's own `title` is a
///   user-visible fact and is not reachable from a check.
/// * **number** — filled in only, never overwritten, for the checkpoint reason
///   above.
/// * **discovery basis** — filled in only. V1 allowed a low → high provenance
///   upgrade; V2's Location carries no confidence column, so what is left of
///   that rule is the blank case, which is the half that cannot lose
///   information.
///
/// Not touched, in either version: when the address was first discovered. A
/// re-sighting that refreshed it would make every address the source still
/// lists look newly found.
Set<SourceFillInField> sourceFillIn({
  required LocationRow existing,
  required ObservedEntryListing observed,
}) {
  final fields = <SourceFillInField>{};
  final label = observed.label.trim();
  if (label.isNotEmpty && label != existing.sourceLabel) {
    fields.add(SourceFillInField.sourceLabel);
  }
  if (existing.sourceNumber == null && observed.printedNumber != null) {
    fields.add(SourceFillInField.sourceNumber);
  }
  if (existing.discoveryBasis.isEmpty) {
    fields.add(SourceFillInField.discoveryBasis);
  }
  return fields;
}

/// How one check ended. Counts and ids, so a report can be built without
/// re-deriving anything — the shape V1's `UpdateCheckOutcome` had.
class SourceCheckOutcome {
  const SourceCheckOutcome({
    required this.sourceId,
    required this.state,
    this.stopReason,
    this.pagesRead = 0,
    this.checkpoint,
    this.discovery = const DiscoveryOutcome(),
    this.fillIns = const [],
    this.concerns = const [],
    this.notClaimedAsNew = 0,
    this.restrictedAddresses = 0,
  });

  /// The one Source this check read. Empty only when there was none to read.
  final String sourceId;
  final SourceCheckState state;

  /// Set whenever the reading was cut short — including when new Entries were
  /// still found, which is V1's "new-entry bound reached; check again to
  /// continue".
  final SourceCheckStop? stopReason;

  /// Pages of this Source's listing this check opened.
  final int pagesRead;

  /// The highest number this Source had already shown, as the check measured
  /// novelty against it. Null when this Source has shown none.
  final double? checkpoint;

  /// What applying the reading did, straight from `discovery.dart`.
  final DiscoveryOutcome discovery;

  /// Second readings of addresses the library already holds. Non-empty means
  /// the source has filled a blank — see [sourceFillIn] and §"repository gap"
  /// on [SourceCheck].
  final List<SourceFillIn> fillIns;

  /// Present when the check stopped on an address whose number the reading's
  /// own evidence contradicts. The evidence, kept rather than repaired.
  final List<EntryIdentityConcern> concerns;

  /// Addresses the library does not hold that this check did **not** claim as
  /// new: at or below the checkpoint, or carrying no printed number to place
  /// against it. The back catalogue, left where it is.
  final int notClaimedAsNew;

  /// New addresses withheld because they sit on a service this app does not
  /// capture from. Counted rather than silently dropped.
  final int restrictedAddresses;

  /// Entries this check brought into the library.
  List<String> get newEntryIds => discovery.createdEntryIds;

  /// Whether this check's reading is one the library may act on as complete.
  bool get vouchesForReading => stopReason == null;

  /// True when the check stopped on this app's own policy.
  bool get isCaptureRestricted => stopReason?.isCaptureRestricted ?? false;
}

/// One reading of one page of a Source's listing.
///
/// The judgements stay on this side of the seam: whether the page was this
/// Source's listing at all, whether its ordering was unambiguous, which way it
/// ran, and how much of it the reading had to leave out. The check records
/// them; it does not re-derive them, because the only honest measurement is the
/// one taken on the settled page.
class SourceObservation {
  /// A page that was read.
  const SourceObservation.read({
    required this.url,
    required this.listings,
    required this.listRecognised,
    required this.orderingConfident,
    required this.newestFirst,
    this.dropped = 0,
    this.nextPageUrl,
  }) : stop = null;

  /// Nothing was read, and here is which named condition ended it.
  ///
  /// An implementation may report exactly three: [SourceCheckStop.listingUnreadable]
  /// (the page never came back, or never rendered), [SourceCheckStop.captureRestrictedForSite]
  /// (it *landed* on a service this app does not capture from — the boundary
  /// only whoever navigates can own), and [SourceCheckStop.cancelledByUser].
  const SourceObservation.unreadable({required this.url, required this.stop})
    : listings = const [],
      listRecognised = false,
      orderingConfident = false,
      newestFirst = false,
      dropped = 0,
      nextPageUrl = null;

  /// Where the reading actually happened — not necessarily where it aimed.
  final String url;

  /// Every address of this Source the page showed, in the page's own order.
  final List<ObservedEntryListing> listings;

  /// Whether the page plausibly showed this Source's listing at all. False
  /// means "this reading tells us nothing", never "up to date".
  final bool listRecognised;

  /// True only when the listing's own ordering was unambiguous.
  final bool orderingConfident;

  /// Whether the page itself ran newest-first. Only read from the first page:
  /// it is what makes "nothing above the top of the list" mean something, and
  /// that claim belongs to the front of a listing rather than to page four.
  final bool newestFirst;

  /// Addresses the reading saw and had to leave out. Any at all and the
  /// reading vouches for no interval.
  final int dropped;

  /// A further page of the same listing, or null for the end of it.
  final String? nextPageUrl;

  final SourceCheckStop? stop;

  bool get isReadable => stop == null;
}

/// Reads one page of one Source's listing.
///
/// The production implementation is the only thing in the check path that may
/// touch a WebView, and it owns the landed-URL boundary the same way
/// `PageCaptureSource`'s does — a navigation can land somewhere other than
/// where it aimed, and no caller can ask the policy on its behalf. A test
/// implementation returns literal listings. Neither writes a database row and
/// neither decides whether the check was allowed to start.
abstract interface class SourceObservationSource {
  /// Read [pageUrl], or — when it is null — wherever this Source's listing
  /// begins. [source] carries `host` and `pathKey`, which are between them
  /// V1's `collection_key` and the address the listing lives at.
  ///
  /// [shouldContinue] is the cooperative stop. It is asked at safe boundaries
  /// and never mid-read; a `false` answer ends the reading with
  /// [SourceCheckStop.cancelledByUser].
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  });
}

/// One Source, read once, applied through `discovery.dart`.
///
/// ## Repository gap this lane could not close
///
/// [sourceFillIn] is the whole V1 judgement and it is computed for every
/// re-listed address, but `EntryRepository` currently exposes `addLocation`,
/// `retractLocation` and `removeLocationByHand` and **no field writer for an
/// existing Location**. So a fill-in whose subject is a Location the library
/// already holds is reported on [SourceCheckOutcome.fillIns] and not written;
/// the case that *is* writable — an Entry the library holds that this Source
/// had no address for — goes through `discovery.dart`'s ordinary merge path
/// and does appear as an added Location. `applyRemoteLocation` is not an
/// option: it is the pull path and writes no outbox row, so a local
/// observation applied through it would never reach the server.
class SourceCheck {
  SourceCheck({
    required this._collections,
    required this._entries,
    required this._index,
    required this._discovery,
    required this._observations,
  });

  final CollectionRepository _collections;
  final EntryRepository _entries;
  final RecognitionIndex _index;
  final SourceDiscovery _discovery;
  final SourceObservationSource _observations;

  /// The ordinary check: the Collection's **preferred** Source and no other.
  ///
  /// A Collection with one Source has no choice to make and that Source is
  /// read. A Collection with several and no preference is refused with
  /// [SourceCheckStop.preferredSourceNotChosen] — picking one here would be
  /// this file choosing which site to open on the user's behalf.
  Future<SourceCheckOutcome> checkPreferredSource(
    String collectionId, {
    required SourceCheckLimits limits,
    required bool Function() shouldContinue,
  }) async {
    final collection = await _collections.byId(collectionId);
    if (collection == null) return _nothing(SourceCheckStop.sourceUnknown);
    if (collection.lifecycle != CollectionLifecycle.active.name) {
      return _nothing(SourceCheckStop.collectionNotFollowed);
    }

    var sourceId = collection.preferredSourceId;
    if (sourceId == null) {
      final sources = await _collections.sourcesOf(collectionId);
      if (sources.isEmpty) return _nothing(SourceCheckStop.sourceUnknown);
      if (sources.length > 1) {
        return _nothing(SourceCheckStop.preferredSourceNotChosen);
      }
      sourceId = sources.single.id;
    }
    return checkSource(
      sourceId,
      limits: limits,
      shouldContinue: shouldContinue,
    );
  }

  /// Check one named Source.
  ///
  /// Reached directly for "check the other site", which is a separate act the
  /// user performs. It is never reached by iterating: one call reads one
  /// Source, and a second Source needs a second call the user asked for.
  Future<SourceCheckOutcome> checkSource(
    String sourceId, {
    required SourceCheckLimits limits,
    required bool Function() shouldContinue,
  }) async {
    final named = await _collections.sourceById(sourceId);
    if (named == null) return _nothing(SourceCheckStop.sourceUnknown);
    // A site that moved points forward, and reading it means reading where it
    // went (V2-D14). A pointer that loops resolves to nothing.
    final source = await _collections.terminalSourceOf(sourceId);
    if (source == null) return _nothing(SourceCheckStop.sourceNotReadable);
    if (!_readable(source)) {
      return _nothing(SourceCheckStop.sourceNotReadable, sourceId: source.id);
    }

    final collection = await _collections.byId(source.collectionId);
    if (collection == null) {
      return _nothing(SourceCheckStop.sourceUnknown, sourceId: source.id);
    }
    if (collection.lifecycle != CollectionLifecycle.active.name) {
      return _nothing(
        SourceCheckStop.collectionNotFollowed,
        sourceId: source.id,
      );
    }

    // The restricted-site policy, asked here on this file's own account. A
    // check is discovery *for* capture: it reads a listing and records rows the
    // user is then invited to download. Refused before anything is opened, so
    // the Collection's Entries, copies and reading state are untouched.
    if (isRestrictedCaptureHost(source.host)) {
      return _nothing(
        SourceCheckStop.captureRestrictedForSite,
        sourceId: source.id,
      );
    }

    if (!shouldContinue()) {
      return _nothing(SourceCheckStop.cancelledByUser, sourceId: source.id);
    }

    return _run(
      source: source,
      collection: collection,
      limits: limits,
      shouldContinue: shouldContinue,
    );
  }

  Future<SourceCheckOutcome> _run({
    required SourceRow source,
    required CollectionRow collection,
    required SourceCheckLimits limits,
    required bool Function() shouldContinue,
  }) async {
    // --- read the Source, page by page, within the ceilings ------------------
    final listings = <ObservedEntryListing>[];
    final seen = <String>{};
    SourceCheckStop? stop;
    var pagesRead = 0;
    var dropped = 0;
    var orderingConfident = true;
    var newestFirst = false;
    String? pageUrl;

    while (true) {
      if (pagesRead >= limits.maxPages) {
        // Only a ceiling when there was more to read. A listing that ended on
        // its last allowed page was read in full.
        if (pagesRead == 0 || pageUrl != null) {
          stop = SourceCheckStop.pageLimitReached;
        }
        break;
      }
      if (!shouldContinue()) {
        stop = SourceCheckStop.cancelledByUser;
        break;
      }

      final observation = await _observations.observe(
        source: source,
        pageUrl: pageUrl,
        shouldContinue: shouldContinue,
      );
      pagesRead++;
      if (!observation.isReadable) {
        stop = observation.stop;
        break;
      }
      // The landed address is judged too. An implementation that navigates owns
      // this boundary, and this is the second ask, not the only one.
      if (isCaptureRestricted(observation.url)) {
        stop = SourceCheckStop.captureRestrictedForSite;
        break;
      }
      if (!observation.listRecognised) {
        stop = SourceCheckStop.listingUnrecognised;
        break;
      }
      if (pagesRead == 1) newestFirst = observation.newestFirst;
      orderingConfident &= observation.orderingConfident;
      dropped += observation.dropped;
      for (final listing in observation.listings) {
        // A paginated listing repeats itself at its seams; one address is one
        // listing however many pages showed it.
        if (seen.add(listing.urlKey)) listings.add(listing);
      }
      pageUrl = observation.nextPageUrl;
      if (pageUrl == null) break;
    }

    // Two ways a reading that ran to its end still cannot be vouched for: it
    // left addresses out, or its own ordering was ambiguous, in which case
    // "nothing above the checkpoint" may only mean we could not tell what was
    // above it — V1 walked the entry chain rather than say so
    // (`update_checker.dart:598-604`). Both are reached only once every more
    // specific reason has been ruled out.
    SourceCheckStop? resolved(SourceCheckStop? reason) =>
        reason ??
        (dropped > 0
            ? SourceCheckStop.listingTruncated
            : orderingConfident
            ? null
            : SourceCheckStop.listingOrderingAmbiguous);

    if (listings.isEmpty) {
      final only = resolved(stop);
      return SourceCheckOutcome(
        sourceId: source.id,
        state: only == null
            ? SourceCheckState.upToDate
            : SourceCheckState.stopped,
        stopReason: only,
        pagesRead: pagesRead,
      );
    }

    // --- what the reading showed, and whether it contradicts itself ----------
    final (full, concerns) = ObservedEntryWindow.read(
      sourceId: source.id,
      listings: listings,
      listRecognised: true,
      orderingConfident: orderingConfident,
      newestFirst: newestFirst,
      dropped: dropped,
    );
    if (concerns.isNotEmpty) {
      // Nothing is written. Stopping is the point: not writing the doubted
      // address would still leave the rest of the same reading being acted on
      // with the same fault.
      return SourceCheckOutcome(
        sourceId: source.id,
        state: SourceCheckState.stopped,
        stopReason: SourceCheckStop.entryIdentityUnsupported,
        pagesRead: pagesRead,
        concerns: concerns,
      );
    }
    if (full == null) {
      // Unreachable as things stand — a recognised, non-empty, uncontradicted
      // reading always yields a window — and the honest answer if it ever were
      // reachable: this reading showed nothing that can be acted on.
      return SourceCheckOutcome(
        sourceId: source.id,
        state: SourceCheckState.stopped,
        stopReason: SourceCheckStop.listingUnrecognised,
        pagesRead: pagesRead,
      );
    }

    // --- the checkpoint: what this Source has already shown -------------------
    final checkpoint = await _checkpoint(
      collectionId: collection.id,
      sourceId: source.id,
      reading: full,
    );

    // --- which addresses this reading may act on -----------------------------
    final held = <String, LocationRow>{};
    final novel = <ObservedEntryListing>[];
    final fillIns = <SourceFillIn>[];
    var notClaimedAsNew = 0;
    var restricted = 0;

    for (final listing in listings) {
      final hit = await _index.lookupUrl(listing.urlKey);
      if (hit != null) {
        held[listing.urlKey] = hit.location;
        // The source's current words about an address already held. Judged, and
        // only ever a blank filled.
        if (hit.location.sourceId == source.id) {
          final fields = sourceFillIn(
            existing: hit.location,
            observed: listing,
          );
          final stored = hit.location.sourceNumber;
          final printed = listing.printedNumber;
          final disagreed =
              stored != null && printed != null && stored != printed
              ? printed
              : null;
          final fillIn = SourceFillIn(
            locationId: hit.location.id,
            urlKey: listing.urlKey,
            fields: fields,
            disagreedNumber: disagreed,
          );
          if (!fillIn.isEmpty) fillIns.add(fillIn);
        }
        continue;
      }
      if (!_isNew(listing, checkpoint)) {
        notClaimedAsNew++;
        continue;
      }
      // A discovered address is one the user is invited to download. One on a
      // restricted service is not recorded at all, so it can never become
      // queued work.
      if (isCaptureRestricted(listing.url)) {
        restricted++;
        continue;
      }
      novel.add(listing);
    }

    // Oldest first, so whatever a user then asks to download runs forward and
    // a partial run leaves a contiguous block rather than holes.
    novel.sort(_oldestFirst);
    final ceiling = limits.maxNewEntries < 0 ? 0 : limits.maxNewEntries;
    final admitted = ceiling < novel.length
        ? novel.take(ceiling).toList()
        : novel;
    if (admitted.length < novel.length) {
      stop ??= SourceCheckStop.newEntryLimitReached;
    }
    final admittedKeys = {for (final listing in admitted) listing.urlKey};

    // --- apply -----------------------------------------------------------
    //
    // The interval is the **page's**, never the filter's: retraction rests on
    // what the reading covered, and narrowing it to the addresses that survived
    // the checkpoint would shrink what absence can be measured against. What is
    // safe to drop is exactly what was dropped — an address the library does
    // not hold has no Location to retract, so removing it from the listing set
    // changes recording and cannot change retraction.
    //
    // A reading that was cut short vouches for no interval at all, which is
    // `discovery.dart`'s own rule for a truncated reading and the reason a
    // cancelled check can never also retract.
    final stopped = resolved(stop);
    final complete = stopped == null;
    final window = ObservedEntryWindow(
      sourceId: full.sourceId,
      listings: [
        for (final listing in listings)
          if (held.containsKey(listing.urlKey) ||
              admittedKeys.contains(listing.urlKey))
            listing,
      ],
      from: complete ? full.from : null,
      to: complete ? full.to : null,
      openAbove: complete && full.openAbove,
    );

    // A cancelled reading is still applied, and that is deliberate: what it saw
    // is true, and rolling it back would be a deletion nobody asked for (V1
    // `update_checker.dart:637-651`). What a cancelled reading may not do is
    // conclude an *absence*, and it cannot — the interval above is null.
    final outcome = await _discovery.apply(window);

    return SourceCheckOutcome(
      sourceId: source.id,
      state: outcome.addedLocationIds.isNotEmpty
          ? SourceCheckState.updatesAvailable
          : stopped == null
          ? SourceCheckState.upToDate
          : SourceCheckState.stopped,
      stopReason: stopped,
      pagesRead: pagesRead,
      checkpoint: checkpoint,
      discovery: outcome,
      fillIns: fillIns,
      notClaimedAsNew: notClaimedAsNew,
      restrictedAddresses: restricted,
    );
  }

  /// Whether this reading may claim [listing] as new.
  ///
  /// V1 `update_checker.dart:1548-1566`, unchanged in substance:
  ///
  /// * nothing to measure against — the first reading reports the whole listing;
  /// * a printed number above the checkpoint is new;
  /// * a printed number at or below it is the back catalogue, and is left where
  ///   it is;
  /// * **no printed number at all is not claimed.** "New" cannot be established
  ///   from a listing alone. V1 could interpolate an unnumbered entry between
  ///   its numbered neighbours; V2's window deliberately does not, because a
  ///   position it invented would be a number this app never read. The case
  ///   that still lands honestly is the one with no checkpoint, where such an
  ///   address becomes an unplaced Entry — visible, readable, and offered to
  ///   the user to place (V2-D16).
  bool _isNew(ObservedEntryListing listing, double? checkpoint) {
    if (checkpoint == null) return true;
    final printed = listing.printedNumber;
    if (printed == null) return false;
    return printed > checkpoint;
  }

  /// The highest number this Source has already shown, over its own active
  /// Locations.
  ///
  /// Rebuilt from rows that are all still true: a Location this very reading
  /// retracts is excluded, because a stale high number is exactly what stops a
  /// Source ever discovering anything again (V1 `update_checker.dart:614-637`,
  /// which reconciled first and then re-read the page in hand against the
  /// corrected checkpoint — the same correction, made in one pass).
  ///
  /// The repository offers Locations by Entry, so the Collection's Entries are
  /// the enumeration available; every Location of this Source hangs off one of
  /// them (I7).
  Future<double?> _checkpoint({
    required String collectionId,
    required String sourceId,
    required ObservedEntryWindow reading,
  }) async {
    double? highest;
    for (final entry in await _entries.entriesOf(collectionId)) {
      for (final location in await _entries.locationsOf(entry.id)) {
        if (location.sourceId != sourceId) continue;
        if (location.lifecycle != LocationLifecycle.active.name) continue;
        if (windowRetracts(reading, location)) continue;
        final number = location.sourceNumber;
        if (number != null && (highest == null || number > highest)) {
          highest = number;
        }
      }
    }
    return highest;
  }

  SourceCheckOutcome _nothing(SourceCheckStop stop, {String sourceId = ''}) =>
      SourceCheckOutcome(
        sourceId: sourceId,
        state: SourceCheckState.stopped,
        stopReason: stop,
      );
}

/// Whether this Source may currently be read from. The rule is the domain's
/// and is reached through it rather than restated here.
bool _readable(SourceRow row) => domain.Source(
  id: row.id,
  collectionId: row.collectionId,
  host: row.host,
  pathKey: row.pathKey,
  lifecycle: domain.SourceLifecycle.values.byName(row.lifecycle),
).readable;

/// Ascending by what the source printed; anything unnumbered keeps the order
/// the listing gave it, after the numbered ones.
int _oldestFirst(ObservedEntryListing a, ObservedEntryListing b) {
  final an = a.printedNumber;
  final bn = b.printedNumber;
  if (an != null && bn != null) return an.compareTo(bn);
  if (an != null) return -1;
  if (bn != null) return 1;
  return 0;
}
