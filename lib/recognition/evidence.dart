/// Evidence and identity arbitration payloads (roadmap F2).
///
/// Evidence is **what a client observed, never what it concluded**
/// (contracts/evidence.yaml, DECISIONS.md V2-D24). The server never fetches a
/// page, so everything it knows arrives through these fields, and a field this
/// device did not observe is omitted rather than filled in.
///
/// Four never-invent rules are enforced here rather than documented:
///
/// * **`ordinal` requires `explicitNumericIndex`.** Constructing evidence with
///   an ordinal under any other ordering basis throws; the contract calls the
///   same submission `validation_failed`.
/// * **`source_number` is a transcription.** It is whatever the source
///   *printed*, and this file never derives one. A number inside a URL is not
///   a number the source printed, so [Evidence.observe] has no access to the
///   URL's digits at all.
/// * **`path_key` is omitted when no stable key could be derived** — the
///   honest answer, taken straight from [RecognitionKeys].
/// * **No page content and no asset URLs.** There is no field for either, by
///   construction.
///
/// Nothing here talks to a network: building and parsing the payloads is this
/// lane's job, carrying them is the sync lane's.
library;

import '../data/outbox_writer.dart' show wireTime;
import '../domain/collection.dart';
import '../domain/invariants.dart';
import '../library/collection_identity.dart';
import 'recognise.dart';

/// A payload rule the contract states and this device refused to break.
///
/// Named, in the style of `lib/domain/invariants.dart`, so a new refusal
/// cannot be introduced by writing a new sentence. The `invariant` field
/// carries the contract's own error code where there is one, so a local
/// refusal and a server rejection are recognisably the same rule.
class EvidenceViolation implements Exception {
  const EvidenceViolation(this.violation);

  final InvariantViolation violation;

  @override
  String toString() => 'EvidenceViolation($violation)';
}

/// contracts/evidence.yaml: `ordinal` is permitted only when `ordering_basis`
/// is `explicitNumericIndex`.
const evidenceOrdinalNeedsExplicitBasis = InvariantViolation(
  'validation_failed',
  'an ordinal may be submitted only with ordering_basis explicitNumericIndex',
);

/// contracts/evidence.yaml: `outcome` is a closed enumeration. An unrecognised
/// value is never read as a known one.
const arbitrationOutcomeUnrecognised = InvariantViolation(
  'invalid_request',
  'the arbitration outcome is not one this client recognises',
);

/// contracts/evidence.yaml: `IdentityMapping.kind` is a closed enumeration.
const identityKindUnrecognised = InvariantViolation(
  'invalid_request',
  'the identity mapping names a kind this client does not recognise',
);

/// The refusal codes an `unresolved` outcome may carry that are *about
/// arbitration*, from the shared vocabulary in contracts/errors.yaml.
///
/// The full `ErrorCode` enumeration is the sync lane's to model; a client that
/// branches on a refusal branches on one of these three. `reason` itself is
/// kept as the wire string, so an unrecognised code is passed through intact
/// instead of being flattened into a known one.
const kArbitrationRefusalCodes = <String>[
  'insufficient_evidence',
  'conflicting_ordinals',
  'ordering_basis_unsupported',
];

/// One observation of one page, in the contract's shape.
///
/// Field names below are Dart; [toJson] is the wire form and the only place
/// snake_case is spelled.
class Evidence {
  const Evidence._({
    required this.url,
    required this.urlKey,
    required this.host,
    required this.observedAt,
    this.pathKey,
    this.pageTitle,
    this.collectionTitle,
    this.sourceLabel,
    this.sourceNumber,
    this.orderingBasis,
    this.ordinal,
    this.language,
  });

  /// Build evidence from what a page observation actually provided.
  ///
  /// [sourceLabel] and [sourceNumber] are transcriptions of what the source
  /// printed. [language] is passed only when the page *declared* one — this
  /// constructor never guesses it from content. [collectionTitle] defaults to
  /// the title detection already carried on the keys.
  ///
  /// Throws [EvidenceViolation] when [ordinal] is supplied without
  /// `explicitNumericIndex`.
  factory Evidence.observe({
    required RecognitionKeys keys,
    required DateTime observedAt,
    String? pageTitle,
    String? collectionTitle,
    String? sourceLabel,
    double? sourceNumber,
    OrderingBasis? orderingBasis,
    double? ordinal,
    String? language,
  }) {
    if (ordinal != null &&
        orderingBasis != OrderingBasis.explicitNumericIndex) {
      throw const EvidenceViolation(evidenceOrdinalNeedsExplicitBasis);
    }
    return Evidence._(
      url: keys.url,
      urlKey: keys.urlKey,
      host: keys.host,
      pathKey: keys.pathKey,
      observedAt: observedAt.toUtc(),
      pageTitle: _observed(pageTitle),
      collectionTitle: _observed(
        collectionTitle ?? keys.detectedCollectionTitle,
      ),
      sourceLabel: _observed(sourceLabel),
      sourceNumber: sourceNumber,
      orderingBasis: orderingBasis,
      ordinal: ordinal,
      language: _observed(language),
    );
  }

  /// The same, from a raw URL plus the page signals recognition already reads.
  factory Evidence.ofUrl({
    required String url,
    required DateTime observedAt,
    String? pageTitle,
    PageHints hints = const PageHints(),
    String? collectionTitle,
    String? sourceLabel,
    double? sourceNumber,
    OrderingBasis? orderingBasis,
    double? ordinal,
    String? language,
  }) {
    return Evidence.observe(
      keys: RecognitionKeys.of(url, pageTitle: pageTitle, hints: hints),
      observedAt: observedAt,
      pageTitle: pageTitle,
      collectionTitle: collectionTitle,
      sourceLabel: sourceLabel,
      sourceNumber: sourceNumber,
      orderingBasis: orderingBasis,
      ordinal: ordinal,
      language: language,
    );
  }

  final String url;
  final String urlKey;
  final String host;
  final String? pathKey;
  final String? pageTitle;
  final String? collectionTitle;
  final String? sourceLabel;
  final double? sourceNumber;
  final OrderingBasis? orderingBasis;
  final double? ordinal;
  final String? language;
  final DateTime observedAt;

  /// The wire form. Snake_case keys, ISO-8601 UTC time, enum `name` spellings
  /// — and an absent observation is an absent key, never a null or an empty
  /// string.
  Map<String, Object?> toJson() => {
    'url': url,
    'url_key': urlKey,
    'host': host,
    if (pathKey != null) 'path_key': pathKey,
    if (pageTitle != null) 'page_title': pageTitle,
    if (collectionTitle != null) 'collection_title': collectionTitle,
    if (sourceLabel != null) 'source_label': sourceLabel,
    if (sourceNumber != null) 'source_number': sourceNumber,
    if (orderingBasis != null) 'ordering_basis': orderingBasis!.name,
    if (ordinal != null) 'ordinal': ordinal,
    if (language != null) 'language': language,
    'observed_at': wireTime(observedAt),
  };

  static String? _observed(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// Locally minted ids the client is already using for what the evidence
/// describes. Local ids are permanent primary keys; the server maps them and
/// never asks for a rewrite (V2_ARCHITECTURE.md §4.1).
class ProvisionalIdentity {
  const ProvisionalIdentity({
    this.collectionId,
    this.sourceId,
    this.entryId,
    this.locationId,
  });

  final String? collectionId;
  final String? sourceId;
  final String? entryId;
  final String? locationId;

  bool get isEmpty =>
      collectionId == null &&
      sourceId == null &&
      entryId == null &&
      locationId == null;

  Map<String, Object?> toJson() => {
    if (collectionId != null) 'collection_id': collectionId,
    if (sourceId != null) 'source_id': sourceId,
    if (entryId != null) 'entry_id': entryId,
    if (locationId != null) 'location_id': locationId,
  };
}

/// POST /identity/arbitrate.
class ArbitrationRequest {
  const ArbitrationRequest({required this.evidence, this.provisional});

  final Evidence evidence;
  final ProvisionalIdentity? provisional;

  Map<String, Object?> toJson() => {
    'evidence': evidence.toJson(),
    if (provisional != null && !provisional!.isEmpty)
      'provisional': provisional!.toJson(),
  };
}

/// What an [IdentityMapping] is about. Deliberately narrower than
/// `SyncedEntityKind`: the contract's mapping enumeration is these four.
enum IdentityKind { collection, source, entry, location }

/// One provisional id resolved to canonical identity.
class IdentityMapping {
  const IdentityMapping({
    required this.kind,
    required this.provisionalId,
    required this.canonicalId,
  });

  factory IdentityMapping.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    for (final candidate in IdentityKind.values) {
      if (candidate.name == kind) {
        return IdentityMapping(
          kind: candidate,
          provisionalId: json['provisional_id']! as String,
          canonicalId: json['canonical_id']! as String,
        );
      }
    }
    throw const EvidenceViolation(identityKindUnrecognised);
  }

  final IdentityKind kind;
  final String provisionalId;
  final String canonicalId;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'provisional_id': provisionalId,
    'canonical_id': canonicalId,
  };
}

/// The two outcomes. `unresolved` is a first-class answer at HTTP 200, not an
/// error: the client keeps its provisional identity and the Entry stays
/// visible, readable and unplaced.
enum ArbitrationOutcome { resolved, unresolved }

class ArbitrationResponse {
  const ArbitrationResponse({
    required this.outcome,
    this.mappings = const [],
    this.reason,
  });

  /// Parses a 200 body. An outcome or mapping kind this client does not
  /// recognise throws rather than being read as a known one.
  factory ArbitrationResponse.fromJson(Map<String, Object?> json) {
    final raw = json['outcome'];
    ArbitrationOutcome? outcome;
    for (final candidate in ArbitrationOutcome.values) {
      if (candidate.name == raw) outcome = candidate;
    }
    if (outcome == null) {
      throw const EvidenceViolation(arbitrationOutcomeUnrecognised);
    }
    final rawMappings = json['mappings'] as List<Object?>? ?? const [];
    return ArbitrationResponse(
      outcome: outcome,
      mappings: [
        for (final m in rawMappings)
          IdentityMapping.fromJson(Map<String, Object?>.from(m! as Map)),
      ],
      reason: json['reason'] as String?,
    );
  }

  final ArbitrationOutcome outcome;

  /// Present when [outcome] is `resolved`.
  final List<IdentityMapping> mappings;

  /// The refusal code when [outcome] is `unresolved`, kept as the wire string
  /// from the shared vocabulary.
  final String? reason;

  bool get isResolved => outcome == ArbitrationOutcome.resolved;

  /// The canonical id for one provisional id, or null when the response says
  /// nothing about it.
  String? canonicalFor(IdentityKind kind, String provisionalId) {
    for (final m in mappings) {
      if (m.kind == kind && m.provisionalId == provisionalId) {
        return m.canonicalId;
      }
    }
    return null;
  }
}
