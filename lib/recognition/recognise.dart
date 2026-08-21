/// Recognition (roadmap F1): *given this URL, what is it?*
///
/// This is the hot path — asked on every page load — so it is answered from
/// local indexes and nothing else. No network is reachable from this file, and
/// none is needed: `url_key` resolves a Location in one indexed lookup, and
/// `(host, path_key)` resolves a Source in one more
/// (V2_ARCHITECTURE.md §6.3, DECISIONS.md V2-D24).
///
/// The keys are V1's, one level down (V2-D15). `normalizeUrl` is Location
/// identity; the collection fingerprint, reached through
/// `resolveCollectionIdentity`, is the Source half. Both algorithms are frozen
/// and are called here, never re-derived.
///
/// The answer is a union of three honest states, not a nullable hit: a URL is
/// a Location this library already holds, or a page of a Source it already
/// holds, or unknown. "Unknown" carries the keys it derived, so the caller can
/// submit evidence (F2) or promote from history (F6) without recomputing
/// anything.
library;

import '../core/url_utils.dart';
import '../data/collection_repository.dart';
import '../data/reading_state_repository.dart';
import '../data/recognition_index.dart';
// The drift table class of the same name would shadow the V1 page-signal type,
// which is the one this file means.
import '../data/schema.dart' hide PageHints;
import '../domain/collection.dart';
import '../domain/reading_state.dart';
import '../library/collection_identity.dart';

/// The deterministic keys one page yields, derived by the frozen algorithms.
///
/// Everything downstream — the lookups, the evidence payload, a history row —
/// is built from this one derivation, so a URL cannot be normalised two
/// different ways in two different places.
class RecognitionKeys {
  const RecognitionKeys({
    required this.url,
    required this.urlKey,
    required this.host,
    required this.pathKey,
    this.detectedCollectionTitle,
  });

  /// Derive from the URL as navigated to, plus whatever the page itself
  /// offered.
  ///
  /// The whole derivation is `resolveCollectionIdentity`'s, unchanged. The
  /// *key* always comes from the address — a collection link only ever
  /// confirms the fingerprint it already computed — so [pageTitle] and [hints]
  /// change nothing about identity. What they contribute is the detected
  /// title, which is evidence a page volunteered rather than something read
  /// out of a URL.
  factory RecognitionKeys.of(
    String url, {
    String? pageTitle,
    PageHints hints = const PageHints(),
  }) {
    final identity = resolveCollectionIdentity(
      entryUrl: url,
      pageTitle: pageTitle,
      hints: hints,
    );
    return RecognitionKeys(
      url: url,
      urlKey: normalizeUrl(url),
      host: identity.host,
      // High confidence is, by construction of `resolveCollectionIdentity`,
      // exactly the two path-derived cases. A `title:` or `host:` key is a
      // grouping fallback and is not a path, so there is no stable Source key
      // to report and the contract says to omit it.
      pathKey: identity.confidence == IdentityConfidence.high
          ? identity.collectionKey
          : null,
      detectedCollectionTitle: identity.detectedTitle,
    );
  }

  /// The URL as navigated to, after top-level redirects.
  final String url;

  /// Location identity (I6): `normalizeUrl(url)`.
  final String urlKey;

  /// The host component, lowercased.
  final String host;

  /// The Source-identity half. Null when no stable key could be derived —
  /// a real answer, never a guess.
  final String? pathKey;

  /// The work's title as the page named it, when it named one.
  final String? detectedCollectionTitle;

  /// Whether this is a renderable web page at all. `about:blank`, app schemes
  /// and junk are not, and nothing can match them.
  bool get isWebPage => pageIdentityKey(url).isNotEmpty;
}

/// What a URL turned out to be. Three states, each of them an answer.
sealed class RecognitionResult {
  const RecognitionResult(this.keys);

  final RecognitionKeys keys;
}

/// The fast path: this exact URL is a Location this library already holds.
///
/// [collection] is null for a standalone Entry's Location — a first-class
/// library item that is not wrapped in a Collection of one (I3).
final class RecognisedLocation extends RecognitionResult {
  const RecognisedLocation(
    super.keys, {
    required this.location,
    required this.entry,
    required this.collection,
  });

  final LocationRow location;
  final EntryRow entry;
  final CollectionRow? collection;

  /// The Source this address sits on. Null for a standalone Entry (I7).
  String? get sourceId => location.sourceId;

  /// Whether reading this may keep the library current (V2-D13). A standalone
  /// Entry is in the library by construction; a Collection has to be followed.
  bool get authorisesLibraryUpdate =>
      collection == null ||
      collection!.lifecycle == CollectionLifecycle.active.name;
}

/// The Collection is known, the Entry is not: this page sits on a Source the
/// library already holds, at an address it has never seen.
final class RecognisedSource extends RecognitionResult {
  const RecognisedSource(
    super.keys, {
    required this.source,
    required this.collection,
  });

  final SourceRow source;
  final CollectionRow collection;

  bool get followed => collection.lifecycle == CollectionLifecycle.active.name;
}

/// Neither the address nor the Source is known. Carries the derived keys so
/// the caller can submit evidence or create something from them.
final class Unrecognised extends RecognitionResult {
  const Unrecognised(super.keys);
}

/// The pipeline. Holds read paths and one write helper, and nothing else:
/// deciding what to *do* about a result belongs to discovery (F3), history
/// (F6) and the surfaces above them.
class Recogniser {
  Recogniser({
    required this._index,
    required this._collections,
    required this._reading,
  });

  final RecognitionIndex _index;
  final CollectionRepository _collections;
  final ReadingStateRepository _reading;

  /// Recognise [url]. Local, offline, and never more than the indexed lookups
  /// the answer needs.
  Future<RecognitionResult> recognise(
    String url, {
    String? pageTitle,
    PageHints hints = const PageHints(),
  }) {
    return recogniseKeys(
      RecognitionKeys.of(url, pageTitle: pageTitle, hints: hints),
    );
  }

  /// The same pipeline over keys already derived — for a caller that built
  /// evidence first and must not normalise the URL a second time.
  Future<RecognitionResult> recogniseKeys(RecognitionKeys keys) async {
    final hit = await _index.lookupUrl(keys.urlKey);
    if (hit != null) {
      final collectionId = hit.entry.collectionId;
      return RecognisedLocation(
        keys,
        location: hit.location,
        entry: hit.entry,
        collection: collectionId == null
            ? null
            : await _collections.byId(collectionId),
      );
    }

    final pathKey = keys.pathKey;
    if (pathKey != null) {
      final source = await _index.lookupSource(keys.host, pathKey);
      if (source != null) {
        final collection = await _collections.byId(source.collectionId);
        // A Source with no Collection row cannot happen under the schema's
        // cascade; if it somehow does, the honest answer is "unknown".
        if (collection != null) {
          return RecognisedSource(keys, source: source, collection: collection);
        }
      }
    }

    return Unrecognised(keys);
  }

  /// I16 / V2-D9 / V2-D13: opening a recognised Entry of a followed Collection
  /// records access, and nothing else. It never infers completion — on a
  /// source there is no position to measure, so no progress figure is
  /// invented.
  ///
  /// Returns the new reading state, or null when there was nothing to record:
  /// an unrecognised page, a Source-level match with no Entry yet, or an Entry
  /// of a Collection the user has stopped following.
  Future<ReadingState?> recordAccess(
    RecognitionResult result, {
    DateTime? at,
  }) async {
    if (result is! RecognisedLocation) return null;
    if (!result.authorisesLibraryUpdate) return null;
    final (state, _) = await _reading.recordSourceAccess(
      result.entry.id,
      at: at,
    );
    return state;
  }
}
