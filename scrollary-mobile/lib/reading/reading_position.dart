/// Where the reader is inside an entry, and how that survives the entry
/// changing underneath it.
///
/// Pure Dart: the restore maths is the part most likely to be subtly wrong,
/// so it is tested directly rather than only through a running reader.
library;

/// Whether the reader has finished an entry. Separate from save state —
/// an entry can be re-downloaded and stay completed.
enum ReadStatus { unread, inProgress, completed }

ReadStatus readStatusFromName(String? name) => ReadStatus.values.firstWhere(
  (s) => s.name == name,
  orElse: () => ReadStatus.unread,
);

/// The one rule for what "how far through" means: **a completed entry is
/// 100%, always.**
///
/// Reading a finished entry again scrolls its stored fraction back down —
/// the scroll position is genuinely where the reader is — but "finished" is a
/// statement about the entry, not about the current scroll. Without this,
/// re-opening a finished entry and scrolling up makes it report 40% read.
///
/// Applied on both sides: writes store 1.0 for a completed entry, and every
/// display goes through here so rows written before this rule existed read
/// correctly too.
double readProgressFor({required String? readStatus, required double stored}) =>
    readStatusFromName(readStatus) == ReadStatus.completed
    ? 1
    : stored.clamp(0.0, 1.0);

/// A hybrid position: an anchor for precision, a fraction for durability.
///
/// The anchor ([ReadingPosition.anchorIndex] + [ReadingPosition.offsetInAnchor])
/// restores the exact spot but goes stale when an entry is re-saved with a
/// different unit count. The fraction is approximate but content-independent,
/// so it always means something. Both are stored; restore prefers the anchor
/// and falls back.
///
/// **What the anchor indexes depends on the artifact**, and deliberately so.
/// For an image sequence it is a panel; for a structured document it is a
/// *block*. The names are artifact-neutral because the storage is: an index
/// plus a fraction within it describes both, and one shared shape means one
/// set of columns, one write path and one completion rule. What differs is the
/// geometry — [EntryLayout] for panels, [DocumentLayout] for blocks — and the
/// geometry is what each reader owns.
///
/// The consequence worth naming: an anchor recorded against one artifact is
/// meaningless against the other. That is exactly why a save which changes an
/// entry's stored format resets the anchor and keeps only the fraction — see
/// `carryReading` in `save/save_engine.dart`.
class ReadingPosition {
  const ReadingPosition({
    this.fraction = 0,
    this.anchorIndex = 0,
    this.offsetInAnchor = 0,
  });

  /// 0..1 through the whole entry. Drives the progress bar and completion.
  final double fraction;

  /// Zero-based index of the unit at the top of the viewport — an image panel
  /// or a document block, depending on what the entry holds.
  final int anchorIndex;

  /// 0..1 down that unit.
  final double offsetInAnchor;

  static const ReadingPosition start = ReadingPosition();

  bool get isAtStart =>
      fraction <= 0 && anchorIndex == 0 && offsetInAnchor <= 0;

  @override
  String toString() =>
      'unit $anchorIndex +${(offsetInAnchor * 100).round()}% '
      '(${(fraction * 100).round()}% of entry)';
}

/// The two-way mapping between a scroll offset and a [ReadingPosition].
///
/// Implemented once per artifact — [EntryLayout] for image panels,
/// [DocumentLayout] for text blocks — so the reader screen can own progress
/// writing, the completion rule and the jump-back chip **once**, for both,
/// without knowing which kind of entry is open. The parts that genuinely
/// differ (are heights known in advance? what does an index mean?) stay inside
/// the implementations.
abstract interface class ReadingGeometry {
  bool get isEmpty;

  /// Total scrollable content height.
  double get total;

  double offsetForPosition(ReadingPosition position);

  ReadingPosition positionForOffset(double offset, {double viewportHeight});
}

/// Geometry of an entry laid out at a given width.
///
/// Panel heights come from the manifest's stored dimensions, so the list's
/// geometry is known before a single image decodes. That is what lets the
/// reader open *at* the saved position instead of jumping there after layout.
class EntryLayout implements ReadingGeometry {
  EntryLayout._(this.viewportWidth, this.heights, this._offsets, this.total);

  factory EntryLayout({
    required double viewportWidth,
    required List<({int? width, int? height})> panels,
    double fallbackAspectRatio = kFallbackAspectRatio,
  }) {
    final heights = <double>[];
    final offsets = <double>[];
    var running = 0.0;

    for (final panel in panels) {
      final w = panel.width ?? 0;
      final h = panel.height ?? 0;
      // A panel with no recorded size still needs a place to stand.
      final ratio = (w > 0 && h > 0) ? h / w : fallbackAspectRatio;
      final height = viewportWidth * ratio;
      offsets.add(running);
      heights.add(height);
      running += height;
    }
    return EntryLayout._(viewportWidth, heights, offsets, running);
  }

  /// Height/width used when the manifest recorded no dimensions. Tall rather
  /// than square: a tall content page is far more often long than wide, and
  /// guessing short makes the restore land past the intended spot.
  static const double kFallbackAspectRatio = 1.5;

  final double viewportWidth;
  final List<double> heights;
  final List<double> _offsets;

  /// Total scrollable content height.
  @override
  final double total;

  int get panelCount => heights.length;

  @override
  bool get isEmpty => heights.isEmpty || total <= 0;

  double heightOf(int index) =>
      (index >= 0 && index < heights.length) ? heights[index] : 0;

  double offsetOf(int index) =>
      (index >= 0 && index < _offsets.length) ? _offsets[index] : 0;

  /// Scroll offset for a saved position.
  ///
  /// Uses the anchor when the panel still exists, else maps the fraction onto
  /// the current content height — which is why a re-download with a different
  /// panel count still lands somewhere sensible.
  @override
  double offsetForPosition(ReadingPosition position) {
    if (isEmpty) return 0;
    if (position.anchorIndex >= 0 && position.anchorIndex < panelCount) {
      final base = offsetOf(position.anchorIndex);
      final within =
          heightOf(position.anchorIndex) *
          position.offsetInAnchor.clamp(0.0, 1.0);
      return (base + within).clamp(0.0, total);
    }
    return (position.fraction.clamp(0.0, 1.0) * total).clamp(0.0, total);
  }

  /// The inverse: turn a live scroll offset back into a saved position.
  @override
  ReadingPosition positionForOffset(
    double offset, {
    double viewportHeight = 0,
  }) {
    if (isEmpty) return ReadingPosition.start;
    final clamped = offset.clamp(0.0, total);

    var index = 0;
    while (index + 1 < panelCount && _offsets[index + 1] <= clamped) {
      index++;
    }
    final within = heights[index] <= 0
        ? 0.0
        : ((clamped - _offsets[index]) / heights[index]).clamp(0.0, 1.0);

    // Progress counts the *bottom* of the viewport: a reader who can see the
    // last panel in full has finished, even though the scroll offset stops one
    // screen short of the content height.
    final scrollable = (total - viewportHeight);
    final fraction = scrollable <= 0
        ? 1.0
        : (clamped / scrollable).clamp(0.0, 1.0);

    return ReadingPosition(
      fraction: fraction,
      anchorIndex: index,
      offsetInAnchor: within,
    );
  }
}

/// Geometry of a **structured document**, measured after layout.
///
/// The difference from [EntryLayout] is not a detail — it is why this is a
/// separate class rather than a flag on that one. An image panel's height is
/// known before anything renders, because the manifest recorded the pixels;
/// a paragraph's height is not knowable until it has been laid out at a
/// particular width, in a particular font, at a particular text scale. So the
/// image reader opens *at* its position and the document reader restores *to*
/// it once the first frame exists.
///
/// What makes that restore reliable across restarts, rotations and font-size
/// changes is that the stored anchor is a **block index**, which no amount of
/// reflow can move. Only the offset within the block is proportional, and a
/// block that reflows from three lines to five keeps the reader at the same
/// relative point inside it.
///
/// Offsets are handed in by the reader after it measures its own children; the
/// maths lives here so it is testable without a widget tree.
class DocumentLayout implements ReadingGeometry {
  DocumentLayout._(this._offsets, this._heights, this.total);

  /// Build from measured block offsets and heights, in block order.
  factory DocumentLayout({
    required List<double> offsets,
    required List<double> heights,
    double? totalHeight,
  }) {
    final count = offsets.length < heights.length
        ? offsets.length
        : heights.length;
    final o = offsets.take(count).toList(growable: false);
    final h = heights.take(count).toList(growable: false);
    final total =
        totalHeight ?? (count == 0 ? 0.0 : o[count - 1] + h[count - 1]);
    return DocumentLayout._(o, h, total);
  }

  /// Nothing measured yet — the state on the very first frame.
  static final DocumentLayout empty = DocumentLayout._(const [], const [], 0);

  final List<double> _offsets;
  final List<double> _heights;

  @override
  final double total;

  int get blockCount => _offsets.length;

  @override
  bool get isEmpty => _offsets.isEmpty || total <= 0;

  double offsetOf(int index) =>
      (index >= 0 && index < _offsets.length) ? _offsets[index] : 0;

  double heightOf(int index) =>
      (index >= 0 && index < _heights.length) ? _heights[index] : 0;

  /// Scroll offset for a saved position.
  ///
  /// The anchor when the block still exists, else the fraction mapped onto the
  /// current content height — so a re-save that added a paragraph still lands
  /// somewhere sensible rather than at the top.
  @override
  double offsetForPosition(ReadingPosition position) {
    if (isEmpty) return 0;
    if (position.anchorIndex >= 0 && position.anchorIndex < blockCount) {
      final base = offsetOf(position.anchorIndex);
      final within =
          heightOf(position.anchorIndex) *
          position.offsetInAnchor.clamp(0.0, 1.0);
      return (base + within).clamp(0.0, total);
    }
    return (position.fraction.clamp(0.0, 1.0) * total).clamp(0.0, total);
  }

  /// The inverse: a live scroll offset back into a saved position.
  @override
  ReadingPosition positionForOffset(
    double offset, {
    double viewportHeight = 0,
  }) {
    if (isEmpty) return ReadingPosition.start;
    final clamped = offset.clamp(0.0, total);

    var index = 0;
    while (index + 1 < blockCount && _offsets[index + 1] <= clamped) {
      index++;
    }
    final height = _heights[index];
    final within = height <= 0
        ? 0.0
        : ((clamped - _offsets[index]) / height).clamp(0.0, 1.0);

    // Progress counts the bottom of the viewport, exactly as the image reader
    // does: a reader who can see the last paragraph in full has finished.
    final scrollable = total - viewportHeight;
    final fraction = scrollable <= 0
        ? 1.0
        : (clamped / scrollable).clamp(0.0, 1.0);

    return ReadingPosition(
      fraction: fraction,
      anchorIndex: index,
      offsetInAnchor: within,
    );
  }
}

/// Rules for when an entry counts as finished.
class CompletionPolicy {
  const CompletionPolicy({
    this.threshold = 0.97,
    this.dwell = const Duration(milliseconds: 800),
    this.nearThreshold = 0.9,
  });

  /// How far through counts as the end. Not 1.0: a trailing comments section
  /// or a last panel taller than the viewport would otherwise make an entry
  /// impossible to finish.
  final double threshold;

  /// How long the reader must stay past the threshold. Stops a fast fling to
  /// the bottom from silently marking an entry read.
  final Duration dwell;

  /// Far enough through that "did you finish this?" is a fair question when the
  /// reader moves on to the next entry, but not far enough to answer it for
  /// them. Never a completion rule of its own: nothing is marked, removed or
  /// stored because a fraction crossed it — it only decides whether the reader
  /// is *asked*.
  ///
  /// A tenth of the entry left. Read against what [ReadingPosition.fraction]
  /// actually measures — the **bottom** of the viewport, so a reader who can
  /// see the last panel in full is already at 1.0 — 0.90 means roughly the
  /// final panel of an image sequence is still unseen, or the last few
  /// paragraphs of a document. Below that there is too much left for the
  /// question to be anything but a nag, and the reader is moving on for one of
  /// the ordinary reasons (a look ahead, a comparison, a mistap).
  ///
  /// Deliberately clear of [threshold] rather than just under it: the gap is
  /// where an entry that reached the end but never dwelt there lands, and that
  /// is the case the question exists for.
  final double nearThreshold;

  bool reachedEnd(double fraction) => fraction >= threshold;

  /// Whether an *unfinished* entry is close enough to the end to be worth
  /// asking about. Deliberately not bounded above by [threshold]: a fling to
  /// the bottom passes [reachedEnd] without ever satisfying [dwell], so it is
  /// still an unfinished entry — and still one to ask about.
  bool nearEnd(double fraction) => fraction >= nearThreshold;
}

const kDefaultCompletionPolicy = CompletionPolicy();
