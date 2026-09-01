/// Recognising that an address the library holds has **moved**.
///
/// **Why this file exists.** Location identity is `normalizeUrl(url)` and
/// Source identity is `(host, path_key)`, both exact and both frozen
/// (V2-D15). That is right for the hot path and wrong for nothing — until a
/// provider rewrites part of its own URL structure, at which point every key
/// the library holds for that site stops matching and the work reads as a
/// site nobody has ever seen. Recognition misses, the update check reads a
/// listing address that is no longer there, and the save sheet cheerfully
/// offers to start a second Collection for a work the library already holds.
///
/// The answer here is deliberately **not** a cleverer key. Loosening
/// `normalizeUrl` or `collectionFingerprint` would trade a stoppage for a
/// wrong merge, which is the trade V2-D16 exists to refuse, and it would
/// reindex every row in the library to do it. Instead this file adds *rows*
/// and leaves both algorithms untouched: a moved address becomes **another
/// Location on the Entry that already exists**, and a moved site becomes the
/// `resolvedInto` lifecycle transition V2-D14 already designed and the
/// repository already validates.
///
/// Three rules it carries:
///
/// * **Only the provider may say two addresses are one page.** A top-level
///   redirect from an address the library holds is the site's own statement,
///   in the same class as a printed label — evidence, not inference. Nothing
///   here matches on slug similarity, and no page's own `<link rel=canonical>`
///   reaches this file: a canonical tag is a hint a page makes about itself,
///   it is trivially wrong on paginated and syndicated pages, and it arrives
///   without the corroboration a redirect arrives with.
/// * **Evidence is corroborated before it is acted on.** The redirect must
///   stay on one host, must not land on a sign-in wall, and the page it lands
///   on must still print the number the stored Location was discovered with.
///   Anything less is refused by name — one wrong alias silently points an
///   Entry at somebody else's page.
/// * **A move preserves; it never deletes.** The superseded Location is
///   *retracted*, which is the lifecycle the model already has for "this
///   Source no longer lists this address". Nothing touches the Entry, its
///   reading state, its measurements or its downloaded bytes, all of which are
///   keyed on the Entry and not on any URL.
library;

import '../core/url_utils.dart';
import '../data/collection_repository.dart';
import '../data/data_violations.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/invariants.dart';
import '../domain/source.dart' as domain;
// One named refusal, not a second copy of it: the "this address yields no
// stable Source key" answer already exists and is spelled once.
import 'adopt.dart' show sourceKeyUnavailable;
import 'entry_identity.dart';
import 'page_kind.dart' show ownPathOf;
import 'recognise.dart';

/// How a Location that arrived because the provider redirected an address the
/// library already held says it was found.
///
/// One spelling in one place, beside `kSourceListingBasis` and
/// `kUserSaveBasis`, so a row written by a relocation is distinguishable from
/// one a listing or a person produced.
const String kProviderRedirectBasis = 'providerRedirect';

/// Why a redirect was not accepted as evidence that one page moved.
///
/// Named rather than free text, in the style of `SourceCheckStop` and
/// `EntryIdentityDoubt`, so a new reason cannot be introduced by writing a new
/// sentence — and so a refusal can be reported without re-deriving it.
enum RedirectAliasRefusal {
  /// The navigation landed where it aimed. There is no second address.
  notRedirected,

  /// The landed address is not a renderable web page.
  landedNotAWebPage,

  /// The redirect left the host. A site moving domain is a Source relocation
  /// the user confirms ([SourceRelocator]), never something inferred from one
  /// navigation.
  differentHost,

  /// The redirect ended at a sign-in, registration or subscription page. The
  /// site declined; it did not move anything.
  deniedDestination,

  /// The library does not hold the address that was asked for, so there is
  /// nothing for the landed address to be an alias *of*.
  requestedNotHeld,

  /// The library already holds the landed address. Recognition answers it
  /// directly and no row is needed.
  landedAlreadyHeld,

  /// The held Location belongs to no Source. Retraction is source-scoped
  /// (I15), so the superseded address could not be stood down and the Entry
  /// would keep offering a dead one.
  standaloneLocation,

  /// The held Location carries no printed number, so a landed page has nothing
  /// to be checked against.
  noStoredNumber,

  /// The landed page prints a different number than the address it replaced.
  /// The commonest false match there is: a site that bounces a removed page to
  /// the newest one.
  numberNotCorroborated,
}

/// Whether a redirect may be read as one page having moved.
///
/// Mirrors [NextUrlCheck]'s shape — the established local idiom for a
/// validated navigation decision — rather than introducing a second one.
class RedirectAliasCheck {
  const RedirectAliasCheck.accepted({required this.corroboratedNumber})
    : refusal = null;

  const RedirectAliasCheck.refused(RedirectAliasRefusal this.refusal)
    : corroboratedNumber = null;

  final RedirectAliasRefusal? refusal;

  /// The number both the stored Location and the landed page agree on. The
  /// whole evidence for the alias, kept so a report can state it.
  final double? corroboratedNumber;

  bool get isAccepted => refusal == null;
}

/// The rule, as a pure function of what was observed.
///
/// Everything it needs is passed in, so it is unit tested against literal
/// values with no database and no WebView anywhere near it — the same posture
/// `windowRetracts` and `crossSourceEquivalence` take.
///
/// The checks are ordered so the cheap disqualifiers run first, and every one
/// of them is a refusal: there is no branch here that repairs, widens or
/// guesses.
RedirectAliasCheck judgeRedirectAlias({
  required RecognitionKeys requested,
  required RecognitionKeys landed,
  required bool requestedIsHeld,
  required bool landedIsHeld,
  required String? heldSourceId,
  required double? heldSourceNumber,
  required EntryIdentityReading landedReading,
}) {
  if (requested.urlKey == landed.urlKey) {
    return const RedirectAliasCheck.refused(RedirectAliasRefusal.notRedirected);
  }
  if (!landed.isWebPage) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.landedNotAWebPage,
    );
  }
  if (requested.host.isEmpty || requested.host != landed.host) {
    return const RedirectAliasCheck.refused(RedirectAliasRefusal.differentHost);
  }
  if (isDeniedDestination(landed.url)) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.deniedDestination,
    );
  }
  if (!requestedIsHeld) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.requestedNotHeld,
    );
  }
  if (landedIsHeld) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.landedAlreadyHeld,
    );
  }
  if (heldSourceId == null) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.standaloneLocation,
    );
  }
  if (heldSourceNumber == null) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.noStoredNumber,
    );
  }
  // The two readings of the landed page are kept apart exactly as
  // `entry_identity.dart` keeps them, and **either** may corroborate: a site
  // that rewrote its slug usually still prints the number in the label, and
  // one that dropped it from the label usually still spells it in the path.
  // Neither reading is adopted as a position — this is a cross-check, and the
  // number written on the new row is the one already stored.
  final agrees =
      landedReading.labelNumber == heldSourceNumber ||
      landedReading.urlNumber == heldSourceNumber;
  if (!agrees) {
    return const RedirectAliasCheck.refused(
      RedirectAliasRefusal.numberNotCorroborated,
    );
  }
  return RedirectAliasCheck.accepted(corroboratedNumber: heldSourceNumber);
}

/// What applying a redirect alias did.
class RedirectAliasOutcome {
  const RedirectAliasOutcome({
    this.entryId,
    this.locationId,
    this.retractedLocationId,
    this.refusal,
    this.violation,
  });

  const RedirectAliasOutcome.refused(RedirectAliasRefusal this.refusal)
    : entryId = null,
      locationId = null,
      retractedLocationId = null,
      violation = null;

  /// The Entry the moved address now also lives at. Unchanged by the move —
  /// this is the whole point.
  final String? entryId;

  /// The Location the landed address became.
  final String? locationId;

  /// The superseded Location, now `retracted`. Null when the retraction was
  /// itself refused, which leaves both addresses active rather than losing
  /// one.
  final String? retractedLocationId;

  final RedirectAliasRefusal? refusal;
  final InvariantViolation? violation;

  bool get aliased => locationId != null;
}

/// Applies the redirect rule to the library.
///
/// Holds no browser and no navigation: it is handed a pair of addresses that
/// a navigation already produced, which is what keeps the decision provable
/// on a host with no WebView.
class LocationRelocator {
  LocationRelocator({required this._entries, required this._index});

  final EntryRepository _entries;
  final RecognitionIndex _index;

  /// *The site sent us somewhere else for an address we hold.*
  ///
  /// Records the landed address as another Location of the same Entry, on the
  /// same Source, carrying the same evidence the stored row carries — then
  /// retracts the address it replaced so the Entry stops offering one that no
  /// longer resolves.
  ///
  /// The new row keeps the **stored** label and number rather than the landed
  /// page's readings. What the page printed was the cross-check; adopting it
  /// would let a second reading overwrite a value the first established, which
  /// is the overwrite `check.dart` refuses for the same reason.
  Future<RedirectAliasOutcome> aliasOnRedirect({
    required String requestedUrl,
    required String landedUrl,
    String pageTitle = '',
  }) async {
    if (requestedUrl.trim().isEmpty) {
      return const RedirectAliasOutcome.refused(
        RedirectAliasRefusal.notRedirected,
      );
    }
    final requested = RecognitionKeys.of(requestedUrl);
    final landed = RecognitionKeys.of(landedUrl);
    if (requested.urlKey == landed.urlKey) {
      return const RedirectAliasOutcome.refused(
        RedirectAliasRefusal.notRedirected,
      );
    }

    final held = await _index.lookupUrl(requested.urlKey);
    final landedHit = await _index.lookupUrl(landed.urlKey);

    final check = judgeRedirectAlias(
      requested: requested,
      landed: landed,
      requestedIsHeld: held != null,
      landedIsHeld: landedHit != null,
      heldSourceId: held?.location.sourceId,
      heldSourceNumber: held?.location.sourceNumber,
      landedReading: EntryIdentityReading.read(
        url: landedUrl,
        label: pageTitle,
      ),
    );
    if (!check.isAccepted) {
      return RedirectAliasOutcome.refused(check.refusal!);
    }

    final stored = held!.location;
    final sourceId = stored.sourceId!;
    final (location, violation) = await _entries.addLocation(
      entryId: held.entry.id,
      url: landed.url,
      urlKey: landed.urlKey,
      sourceId: sourceId,
      sourceLabel: stored.sourceLabel,
      sourceNumber: stored.sourceNumber,
      discoveryBasis: kProviderRedirectBasis,
    );
    if (location == null) {
      return RedirectAliasOutcome(violation: violation ?? unknownRow);
    }

    // I15 in its own words: this Source's reading is what stands its own
    // address down. A refusal here is reported and never fatal — an Entry
    // with two active addresses is untidy, an Entry with none is broken.
    final retraction = await _entries.retractLocation(
      stored.id,
      readingSourceId: sourceId,
    );
    return RedirectAliasOutcome(
      entryId: held.entry.id,
      locationId: location.id,
      retractedLocationId: retraction == null ? stored.id : null,
      violation: retraction,
    );
  }
}

// ─── a Source that moved ────────────────────────────────────────────────────

/// Where a Source's listing turned out to live, as one reading found it.
///
/// Evidence for an offer, never an instruction: which Collection a site
/// belongs to stays the user's answer (V2-D45), and a site relocating is a
/// lifecycle change the user confirms (V2-D14).
class SourceRelocationCandidate {
  const SourceRelocationCandidate({
    required this.sourceId,
    required this.host,
    required this.previousPathKey,
    required this.pathKey,
    required this.listingsSeen,
  });

  /// The Source as the library holds it — the row whose `path_key` is stale.
  final String sourceId;

  /// Unchanged: a host move is never inferred from a redirect.
  final String host;

  final String previousPathKey;

  /// Where the listing was actually read, normalised the way a `path_key` is.
  final String pathKey;

  /// How many of this Source's addresses the landed page listed. A candidate
  /// only exists because the page worked as a listing, and this is that fact
  /// as a number.
  final int listingsSeen;
}

/// Where this Source's listing should be read, given where its own root
/// navigation landed.
///
/// Returns [sourcePathKey] unchanged for everything that is not a plain
/// same-host redirect into a real path — a cross-host landing, a sign-in wall,
/// a bare host. A caller that gets its own key back learns nothing and behaves
/// exactly as it did before this file existed.
///
/// This is deliberately only asked of a **listing root** navigation. A later
/// page of a paginated listing lands inside the listing by construction, and
/// reading its address as the Source's path would narrow the filter onto one
/// page of it.
String landedListingPath({
  required String sourceHost,
  required String sourcePathKey,
  required String landedUrl,
}) {
  final uri = Uri.tryParse(landedUrl.trim());
  if (uri == null || uri.host.isEmpty) return sourcePathKey;
  if (uri.host.toLowerCase() != sourceHost.toLowerCase()) return sourcePathKey;
  if (isDeniedDestination(landedUrl)) return sourcePathKey;
  final path = ownPathOf(landedUrl);
  if (path.isEmpty || path == '/') return sourcePathKey;
  return path;
}

/// What confirming a Source relocation did.
class SourceRelocationOutcome {
  const SourceRelocationOutcome({
    this.fromSourceId,
    this.toSourceId,
    this.violation,
  });

  const SourceRelocationOutcome.refused(InvariantViolation this.violation)
    : fromSourceId = null,
      toSourceId = null;

  /// The Source that moved. Kept, pointing forward — never deleted, so its
  /// Locations, its measurements and its history survive the move.
  final String? fromSourceId;

  /// The Source it now resolves to.
  final String? toSourceId;

  final InvariantViolation? violation;

  bool get relocated => toSourceId != null;
}

/// *This Collection's site moved.* The user's confirmation, applied.
///
/// V2-D14 designed `resolvedInto` for exactly this and the repository has
/// validated it since; what was missing was anything that could put a Source
/// into that state. This is that operation, and it is the only one — nothing
/// infers a relocation, because a person who can see both pages is the only
/// party with the evidence.
///
/// The new Source is created **under the same Collection**, which is what the
/// repository's `resolvedInto` validation requires and what keeps the move a
/// lifecycle change rather than a reparenting.
class SourceRelocator {
  SourceRelocator({required this._collections, required this._index});

  final CollectionRepository _collections;
  final RecognitionIndex _index;

  Future<SourceRelocationOutcome> relocate({
    required String fromSourceId,
    required String host,
    required String pathKey,
    String language = '',
  }) async {
    final from = await _collections.sourceById(fromSourceId);
    if (from == null) {
      return const SourceRelocationOutcome.refused(unknownRow);
    }
    if (host.isEmpty || pathKey.isEmpty) {
      return const SourceRelocationOutcome.refused(sourceKeyUnavailable);
    }
    // Relocating a Source onto its own identity is not a move. Refused rather
    // than written, because `resolvedInto` pointing at itself is the loop
    // `terminalSourceOf` exists to survive.
    if (host.toLowerCase() == from.host.toLowerCase() &&
        pathKey == from.pathKey) {
      return const SourceRelocationOutcome.refused(sourceIdentityTaken);
    }

    // A destination already published under another Collection is a refusal
    // in words, never a silent move (V2-D14, V2-D45).
    final existing = await _index.lookupSource(host, pathKey);
    if (existing != null && existing.collectionId != from.collectionId) {
      return const SourceRelocationOutcome.refused(sourceIdentityTaken);
    }

    var target = existing;
    if (target == null) {
      final (created, violation) = await _collections.addSource(
        collectionId: from.collectionId,
        host: host,
        pathKey: pathKey,
        language: language.isEmpty ? from.language : language,
      );
      if (created == null) {
        return SourceRelocationOutcome.refused(violation ?? unknownRow);
      }
      target = created;
    }

    final violation = await _collections.setSourceLifecycle(
      fromSourceId,
      domain.SourceLifecycle.resolvedInto,
      resolvedIntoSourceId: target.id,
    );
    if (violation != null) {
      return SourceRelocationOutcome.refused(violation);
    }
    return SourceRelocationOutcome(
      fromSourceId: fromSourceId,
      toSourceId: target.id,
    );
  }

  /// The Source a check should actually read for [sourceId], following a
  /// relocation chain. A thin pass-through so callers outside `check.dart`
  /// resolve a moved Source the same way it does.
  Future<SourceRow?> readableSourceOf(String sourceId) =>
      _collections.terminalSourceOf(sourceId);
}
