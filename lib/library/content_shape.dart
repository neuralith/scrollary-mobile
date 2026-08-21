/// The shape of saved content, modelled as three independent dimensions.
///
/// Pure Dart, no I/O. Kept independent on purpose: a page can be
/// image-dominant *and* part of a dated feed *and* ordered by publication date,
/// and collapsing those into one "type" is what produces a model that only
/// describes one kind of website.
///
/// Nothing here assumes numbering starts at 1, that a total is known, that a
/// sequence increases, that "next" means newer, that every entry belongs to a
/// collection, or that a collection has a final entry.
library;

/// What one saved [Entry] *is*.
///
/// Detection is a claim, not a fact — every value is paired with a
/// [ShapeConfidence], and [unknownWebContent] is a first-class answer rather
/// than a failure. The user-facing label never presents a low-confidence guess
/// as certain (see `entry_labels.dart`).
enum ContentKind {
  /// One page saved on its own, with no detected continuation.
  standalonePage,

  /// Article-shaped: a headline, a byline or dateline, and body prose.
  article,

  /// An article that carries a reliable publication date and sits in a feed.
  datedPost,

  /// Long prose split across a sequence of pages.
  sequentialText,

  /// Mostly images, with little text. Says nothing about the subject matter.
  imageDominant,

  /// The page is primarily a video player, and the video is what it is for.
  ///
  /// **Detected, never captured.** The app does not save audio or video, so
  /// this classification exists to say so honestly — and to stop the save
  /// flow from quietly falling back to sweeping up a video page's thumbnails
  /// and calling that an offline copy. A page that merely *contains* a player
  /// is not this: see `content_detection.dart` for the guards.
  videoDominant,

  /// One page of a document with real pagination (page 3 of 12).
  paginatedDocument,

  /// A single very long page meant to be read top to bottom.
  longFormDocument,

  /// Saved, readable, and not confidently anything more specific.
  unknownWebContent;

  static ContentKind fromName(String? name) => ContentKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => ContentKind.unknownWebContent,
  );

  /// True when the entry's offline copy is expected to be mostly images.
  bool get isImageDominant => this == ContentKind.imageDominant;
}

/// How (and whether) an entry continues into another one.
enum SequenceKind {
  /// Nothing follows. A standalone save.
  none,

  /// The page declares `rel=next` / `rel=prev`.
  explicitNextPrev,

  /// Numbered pagination controls with a visible, finite range.
  numberedPagination,

  /// A "next" link exists but the end is not knowable from the page.
  openEndedNext,

  /// A dated list running oldest → newest.
  chronologicalFeed,

  /// A dated list running newest → oldest, so "next" moves to an older item.
  reverseChronologicalFeed,

  /// One continuous page; there is nothing after it.
  continuousPage,

  /// The user picked the related pages by hand.
  manualSelection;

  static SequenceKind fromName(String? name) => SequenceKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => SequenceKind.none,
  );

  /// True when the number of entries cannot be known before walking.
  ///
  /// These are exactly the sequences that must not start without an explicit
  /// user-set limit.
  bool get isOpenEnded =>
      this == SequenceKind.openEndedNext ||
      this == SequenceKind.chronologicalFeed ||
      this == SequenceKind.reverseChronologicalFeed;

  /// True when the page told us how many items there are.
  bool get hasKnownExtent => this == SequenceKind.numberedPagination;

  /// True when following the sequence moves towards *older* material.
  bool get followsBackwardsInTime =>
      this == SequenceKind.reverseChronologicalFeed;
}

/// What decides the order of entries inside a collection.
enum OrderingBasis {
  /// A number the source itself printed (page 12, part 3).
  explicitNumericIndex,

  /// A publication date parsed from the page.
  publicationDate,

  /// The order the next-links were walked in.
  detectedNextLink,

  /// The order the entries happened to be discovered in. The weakest basis,
  /// and the honest answer when nothing better exists.
  discoveryOrder,

  /// The user arranged them.
  userDefinedManualOrder;

  static OrderingBasis fromName(String? name) =>
      OrderingBasis.values.firstWhere(
        (b) => b.name == name,
        orElse: () => OrderingBasis.discoveryOrder,
      );
}

/// How much a detected shape can be trusted.
///
/// [low] is not a bug — it is the correct answer for most of the web, and it is
/// what makes the UI say "Saved item" instead of inventing "Chapter 12".
enum ShapeConfidence {
  high,
  medium,
  low;

  static ShapeConfidence fromName(String? name) => ShapeConfidence.values
      .firstWhere((c) => c.name == name, orElse: () => ShapeConfidence.low);

  /// The threshold for showing a specific label rather than a generic one.
  bool get isActionable => this != ShapeConfidence.low;
}

/// A detected content shape, with the evidence that produced it.
class ContentShape {
  const ContentShape({
    this.kind = ContentKind.unknownWebContent,
    this.confidence = ShapeConfidence.low,
    this.basis = '',
  });

  final ContentKind kind;
  final ShapeConfidence confidence;

  /// Which signal decided it, kept for the log and the details sheet. The user
  /// can override the result; the basis is what makes a wrong guess
  /// explainable rather than mysterious.
  final String basis;

  @override
  String toString() =>
      '${kind.name} (${confidence.name}${basis.isEmpty ? '' : ', $basis'})';
}

/// A detected sequence, with its bounds when the page revealed any.
class SequenceShape {
  const SequenceShape({
    this.kind = SequenceKind.none,
    this.ordering = OrderingBasis.discoveryOrder,
    this.confidence = ShapeConfidence.low,
    this.knownTotal,
    this.basis = '',
  });

  final SequenceKind kind;
  final OrderingBasis ordering;
  final ShapeConfidence confidence;

  /// How many entries the sequence holds, when the page said so. Null means
  /// "not known" and must never be rendered as a number.
  final int? knownTotal;
  final String basis;

  /// A sequence that needs an explicit ceiling before anything is saved.
  bool get needsExplicitLimit => kind.isOpenEnded;

  @override
  String toString() =>
      '${kind.name}/${ordering.name} (${confidence.name}'
      '${knownTotal == null ? '' : ', $knownTotal known'}'
      '${basis.isEmpty ? '' : ', $basis'})';
}
