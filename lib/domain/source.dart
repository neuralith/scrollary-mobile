/// Source — one Collection as published on one site.
library;

/// Carries a Source through its whole life in one structure. Active
/// alternatives and dead predecessors are the same row at different times: a
/// site coming back is a state change, not a row moved between tables.
enum SourceLifecycle { active, dormant, dead, resolvedInto }

/// Folds a host to the one spelling a Source's identity is stored and compared
/// under (I18).
///
/// DNS is case-insensitive, so two spellings of a host are one host and
/// folding them is not a guess. A path key gets no such treatment: RFC 3986
/// paths **are** case-sensitive, and folding one would merge two places a site
/// may genuinely keep apart. That asymmetry is the whole case rule, it matches
/// what `normalizeUrl` already does to a URL, and the service applies the same
/// one — so neither side can store an identity the other cannot.
String foldSourceHost(String host) => host.trim().toLowerCase();

/// `host` and `pathKey` together are the Source's identity — what V1 called
/// `collection_key`, one level down from where it used to sit. Language
/// belongs here rather than on the Collection, because a translation is a
/// Source of the same work: you read the work once.
class Source {
  const Source({
    required this.id,
    required this.collectionId,
    required this.host,
    required this.pathKey,
    this.language = '',
    this.lifecycle = SourceLifecycle.active,
    this.resolvedIntoSourceId,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String id;
  final String collectionId;
  final String host;
  final String pathKey;
  final String language;
  final SourceLifecycle lifecycle;

  /// Set when a site moves; the old row stays and points forward.
  final String? resolvedIntoSourceId;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  /// Whether this Source may currently be read from.
  bool get readable =>
      lifecycle == SourceLifecycle.active ||
      lifecycle == SourceLifecycle.dormant;
}
