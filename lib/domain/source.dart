/// Source — one Collection as published on one site.
library;

/// Carries a Source through its whole life in one structure. Active
/// alternatives and dead predecessors are the same row at different times: a
/// site coming back is a state change, not a row moved between tables.
enum SourceLifecycle { active, dormant, dead, resolvedInto }

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
