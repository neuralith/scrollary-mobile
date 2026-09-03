import '../browser/page_data.dart';
import '../core/config.dart';

/// Why an image was not treated as entry content. Kept per-image so the
/// debug view can explain every rejection instead of showing a silent gap.
enum RejectReason {
  noUrl,
  hidden,
  pageChrome,
  tooSmall,
  bannerAspect,
  duplicateUrl,
  outsideContentColumn,
}

class ImageCandidate {
  const ImageCandidate({
    required this.url,
    required this.domIndex,
    required this.width,
    required this.height,
    required this.documentTop,
  });

  final String url;
  final int domIndex;
  final int width;
  final int height;
  final int documentTop;
}

class RejectedImage {
  const RejectedImage(this.url, this.domIndex, this.reason);
  final String? url;
  final int domIndex;
  final RejectReason reason;
}

class CandidateSelection {
  const CandidateSelection({required this.accepted, required this.rejected});
  final List<ImageCandidate> accepted;
  final List<RejectedImage> rejected;

  int get acceptedCount => accepted.length;
}

/// Why this image cannot be entry content, judged from the image **alone** —
/// or null when nothing about it rules it out.
///
/// The whole-set rules ([RejectReason.duplicateUrl] and
/// [RejectReason.outsideContentColumn]) are deliberately not here: neither can
/// be decided from one image, and neither is safe to apply to a page that is
/// still loading.
///
/// [unknownSizeIsTooSmall] is the difference between the two callers, and it
/// is the only difference:
///
/// * **true** — the settled page, at final selection. A dimension of zero is a
///   fact about an image that is going nowhere, and the size floor applies to
///   it like any other.
/// * **false** — a page mid-traversal. A dimension of zero means *not measured
///   yet*: a lazy panel that has not been swapped in has no intrinsic size, no
///   `width` attribute and, until layout reserves space for it, no box either.
///   Reading that as "too small" is how a save walks past the content it came
///   for.
///
/// This makes the traversal answer a **superset** of the settled one: every
/// image final selection can accept, traversal already treated as relevant.
/// That direction is load-bearing and is asserted in
/// `test/image_candidates_test.dart` — the reverse would let the engine stop
/// waiting for something it then tries to save.
RejectReason? contentRejection(
  PageImage image, {
  SaveConfig config = kDefaultSaveConfig,
  required bool unknownSizeIsTooSmall,
}) {
  if (image.effectiveUrl == null) return RejectReason.noUrl;
  if (image.hidden) return RejectReason.hidden;
  if (image.inPageChrome) return RejectReason.pageChrome;

  final w = image.effectiveWidth;
  final h = image.effectiveHeight;
  if (unknownSizeIsTooSmall) {
    if (w < config.minImageEdge || h < config.minImageEdge) {
      return RejectReason.tooSmall;
    }
  } else {
    // A measured edge below the floor is a real disqualification — a 300x250
    // advertisement slot is not a panel, loaded or not. An edge of zero is
    // simply unknown, and unknown never disqualifies here.
    if (w > 0 && w < config.minImageEdge) return RejectReason.tooSmall;
    if (h > 0 && h < config.minImageEdge) return RejectReason.tooSmall;
  }

  if (h > 0 && w / h > config.maxAspectRatio) return RejectReason.bannerAspect;
  return null;
}

/// Nothing has told us how big this picture is.
///
/// Neither the file (it has not produced pixels) nor the document (`width` /
/// `height` are absent). All that is left is the box the stylesheet reserved,
/// and a reserved box is a fact about the page's CSS, not about the image that
/// will arrive in it.
bool _sizeIsOnlyItsReservedBox(PageImage image) =>
    image.naturalWidth == 0 &&
    image.naturalHeight == 0 &&
    image.attrWidth == 0 &&
    image.attrHeight == 0;

/// How far past one placeholder the next may start and still count as the same
/// run, when the placeholders are too short for their own height to say.
///
/// Small on purpose: this is the allowance for a margin between stacked
/// panels, not for the rest of a page.
const int kLazyRunGapFloor = 200;

/// The not-yet-loaded images that sit in a **vertical run** of their own kind.
///
/// This exists because the per-image question is unanswerable for an image
/// that has not loaded. A page that reserves *no* box for one (`0x0`, much the
/// commonest) says "unknown", and [contentRejection] correctly treats unknown
/// as relevant. A page that reserves a *small* box says 50x50 — and a 50x50
/// placeholder, a 40x40 avatar and a 300x250 advertisement slot are the same
/// measurement. Read literally, a column of 132 unloaded panels is a column of
/// icons: [couldBeContent] rejects every one of them, and with that the
/// traversal loses exactly the images that set its pace. Nothing near the
/// position is unresolved, nothing pending is relevant, nothing in the
/// stability digest moves, and the page reads as settled while its panels have
/// never been asked for.
///
/// What separates them is not the box, it is the company it keeps. Reading
/// content arrives as a **run**: many boxes of the same width, stacked, each
/// starting where the one above it ended. Page furniture does not. An
/// advertisement rail is a handful of slots thousands of pixels apart with the
/// entry between them; a related-items grid is several boxes at the *same*
/// vertical position, side by side. Both are excluded by the same rule, and
/// neither needs a hostname, a selector or a class name to be recognised —
/// only the geometry the page has already laid out.
///
/// Deliberately a **traversal** rule and not a selection one. It answers "is
/// there more coming here, so keep waiting and keep the careful pace", never
/// "save this". An image that is still a placeholder when the page settles has
/// nothing to store and [selectImageCandidates] rejects it exactly as before.
class LazyImageRuns {
  const LazyImageRuns._(this._members);

  /// No run information — every ambiguous placeholder is judged on its own, as
  /// it was before this existed.
  static const LazyImageRuns none = LazyImageRuns._(<int>{});

  /// Find the runs among [images]. Only the ambiguous population is
  /// considered: images whose size is nothing but a reserved box, and whose
  /// box is what would have them rejected as too small.
  factory LazyImageRuns.of(
    List<PageImage> images, {
    SaveConfig config = kDefaultSaveConfig,
  }) {
    final ambiguous = <PageImage>[
      for (final image in images)
        if (_sizeIsOnlyItsReservedBox(image) &&
            contentRejection(
                  image,
                  config: config,
                  unknownSizeIsTooSmall: false,
                ) ==
                RejectReason.tooSmall)
          image,
    ]..sort((a, b) => a.documentTop.compareTo(b.documentTop));
    if (ambiguous.length < config.minClusterSize) return none;

    final members = <int>{};
    var run = <PageImage>[];

    void flush() {
      if (run.length >= config.minClusterSize) {
        members.addAll(run.map((i) => i.domIndex));
      }
      run = <PageImage>[];
    }

    for (final image in ambiguous) {
      if (run.isEmpty) {
        run.add(image);
        continue;
      }
      final previous = run.last;
      if (_continuesRun(previous, image, config)) {
        run.add(image);
      } else {
        flush();
        run.add(image);
      }
    }
    flush();

    return LazyImageRuns._(members);
  }

  final Set<int> _members;

  bool contains(PageImage image) => _members.contains(image.domIndex);

  int get length => _members.length;
}

/// Does [next] carry on the run [previous] is in?
///
/// Three conditions, and each one excludes a real shape of page furniture:
///
/// * **The same column width.** A run is one column. This is the same
///   tolerance the dominant-column rule uses, so "one column" means one thing
///   in both places.
/// * **Further down the page.** Strictly further: a related-items grid puts
///   several boxes at one vertical position, and side by side is not stacked.
/// * **Starting where the last one ended.** An advertisement rail is slots
///   thousands of pixels apart with the entry in between; stacked panels have
///   nothing between them. The allowance is generous relative to the
///   placeholder's own height because a short placeholder cannot speak for the
///   picture that replaces it.
bool _continuesRun(PageImage previous, PageImage next, SaveConfig config) {
  final reference = previous.renderedWidth;
  if (reference <= 0 || next.renderedWidth <= 0) return false;
  final widthDelta = (next.renderedWidth - reference).abs() / reference;
  if (widthDelta > config.widthClusterTolerance) return false;

  if (next.documentTop <= previous.documentTop) return false;

  final previousBottom = previous.documentTop + previous.renderedHeight;
  final gap = next.documentTop - previousBottom;
  final allowance = previous.renderedHeight * 2 > kLazyRunGapFloor
      ? previous.renderedHeight * 2
      : kLazyRunGapFloor;
  return gap <= allowance;
}

/// Could this image plausibly be part of the readable entry, on a page that is
/// still loading?
///
/// The traversal predicate. `SaveEngine` uses it for all three of its pacing
/// gates — the fast-mode lookahead, the pending-asset wait and the stability
/// signature — so that the images which decide how long a save takes are the
/// same ones the save is actually for. Before this existed each gate carried
/// its own looser idea of "relevant", and an advertisement slot that final
/// selection rejects on sight could hold a save at the careful pace for the
/// length of an entry.
///
/// Deliberately permissive: see [contentRejection] for why an unmeasured image
/// counts as relevant.
///
/// [runs] is the page-level half of the same question, and the reason this
/// takes a page and not just an image. Without it, a placeholder small enough
/// to be an icon is an icon; with it, a placeholder that is one of a stacked
/// run of its own kind is content still on its way. Defaulting to
/// [LazyImageRuns.none] keeps every caller that has no page to offer on the
/// per-image answer, which is what they had before.
bool couldBeContent(
  PageImage image, {
  SaveConfig config = kDefaultSaveConfig,
  LazyImageRuns runs = LazyImageRuns.none,
}) {
  final rejection = contentRejection(
    image,
    config: config,
    unknownSizeIsTooSmall: false,
  );
  if (rejection == null) return true;
  // The only rejection a run can overturn. A hidden image, one in page chrome,
  // one with no address and one whose *known* size is too small are all still
  // out — a run says "something is arriving here", never "keep this".
  return rejection == RejectReason.tooSmall && runs.contains(image);
}

/// [couldBeContent] for every image on one page, with the run rule applied.
///
/// The one call the pacing gates should use: it builds [LazyImageRuns] once
/// for the page rather than per image, and it is the only place the two halves
/// of the predicate are guaranteed to see the same page.
bool Function(PageImage) contentRelevanceFor(
  List<PageImage> images, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  final runs = LazyImageRuns.of(images, config: config);
  return (image) => couldBeContent(image, config: config, runs: runs);
}

/// Pick the entry's content images out of everything the page contains.
///
/// Deliberately a heuristic, not a site rule: size floor, chrome/hidden
/// exclusion, banner-aspect rejection, URL de-duplication, then a width
/// cluster to keep only the dominant content column. Preserves DOM order,
/// which is reading order — filenames are not trusted.
CandidateSelection selectImageCandidates(
  List<PageImage> images, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  final rejected = <RejectedImage>[];
  final survivors = <_Scored>[];
  final seenUrls = <String>{};

  for (final img in images) {
    final url = img.effectiveUrl;
    // The per-image rules, from the one place that states them. The page is
    // settled by the time this runs, so an unmeasured image really is too
    // small rather than not-yet-measured.
    final rejection = contentRejection(
      img,
      config: config,
      unknownSizeIsTooSmall: true,
    );
    if (rejection != null) {
      rejected.add(RejectedImage(url, img.domIndex, rejection));
      continue;
    }
    // Only the whole-set rules are left, and they cannot be asked of one image.
    if (!seenUrls.add(url!)) {
      rejected.add(RejectedImage(url, img.domIndex, RejectReason.duplicateUrl));
      continue;
    }

    survivors.add(_Scored(img, url, img.effectiveWidth, img.effectiveHeight));
  }

  final kept = _dominantWidthCluster(survivors, config, rejected);
  kept.sort((a, b) => a.image.domIndex.compareTo(b.image.domIndex));

  return CandidateSelection(
    accepted: [
      for (final s in kept)
        ImageCandidate(
          url: s.url,
          domIndex: s.image.domIndex,
          width: s.width,
          height: s.height,
          documentTop: s.image.documentTop,
        ),
    ],
    rejected: rejected,
  );
}

/// Content pages in one column share a column width. Group survivors by similar width and
/// keep the dominant group — this removes a stray large image (a promo, a
/// related-collection thumbnail) that passed every other filter.
///
/// **Dominant means the group that occupies the most of the page, not the one
/// with the most members.** Counting members says a grid of twenty 400x580
/// cover thumbnails is more of the page than nineteen stacked panels the
/// reader actually scrolls through, because it stops at "twenty beats
/// nineteen" and never asks how tall either group is. That is the whole of the
/// failure: a recommendation grid below the entry won the column, every panel
/// was rejected as [RejectReason.outsideContentColumn], and what reached the
/// collapse guard was a set of thumbnails whose tallest member was a fraction
/// of the panels the traversal had already seen.
///
/// So the measure is [clusterVerticalExtent] — the same "how much of this band
/// is actually image" quantity `imageContentBand` builds its density test from
/// — and member count survives only as the tiebreak for a page that reported
/// no layout geometry at all, which is exactly the behaviour this had before.
///
/// Deliberately **not** ranked on whether a group forms a single vertical run.
/// That test belongs to `imageContentBand`, where a band that cannot be
/// established honestly falls back to the whole document; here a transient
/// side-by-side layout during lazy settling would demote the real content
/// column and there is nothing to fall back to.
///
/// If no group is convincing enough, keep everything: better a slightly noisy
/// entry than a silently truncated one.
List<_Scored> _dominantWidthCluster(
  List<_Scored> survivors,
  SaveConfig config,
  List<RejectedImage> rejected,
) {
  if (survivors.length < config.minClusterSize) return survivors;

  final clusters = <List<_Scored>>[];
  for (final s in survivors) {
    var placed = false;
    for (final cluster in clusters) {
      final ref = cluster.first.width;
      final delta = (s.width - ref).abs() / ref;
      if (delta <= config.widthClusterTolerance) {
        cluster.add(s);
        placed = true;
        break;
      }
    }
    if (!placed) clusters.add([s]);
  }

  // Only a group big enough to be a column may win one. Ranking first and
  // testing the winner afterwards was equivalent while the rank *was* the
  // member count; it is not equivalent to anything now, and a one-image group
  // that happened to be the tallest would have failed this test and thrown
  // away the whole page's candidates with it.
  final eligible = [
    for (final cluster in clusters)
      if (cluster.length >= config.minClusterSize) cluster,
  ];
  if (eligible.isEmpty) return survivors;

  eligible.sort((a, b) {
    // How much of the page each group is. Zero on both sides means the page
    // reported no laid-out boxes, and the comparison below is what this
    // always did.
    final byExtent = _verticalExtent(b).compareTo(_verticalExtent(a));
    if (byExtent != 0) return byExtent;
    final byCount = b.length.compareTo(a.length);
    if (byCount != 0) return byCount;
    return _area(b).compareTo(_area(a));
  });

  final best = eligible.first;

  final keptIds = best.map((s) => s.image.domIndex).toSet();
  for (final s in survivors) {
    if (!keptIds.contains(s.image.domIndex)) {
      rejected.add(
        RejectedImage(
          s.url,
          s.image.domIndex,
          RejectReason.outsideContentColumn,
        ),
      );
    }
  }
  return best;
}

/// How much of the page a set of images occupies vertically: the sum of the
/// heights of the boxes the browser actually laid out for them.
///
/// **The rendered box, not the intrinsic size.** `PageImage.effectiveHeight`
/// prefers `naturalHeight`, which is the image file's own height and says
/// nothing about how much of this page it takes up — a 16000px strip scaled
/// into a 720px column occupies 12800px, not 16000. Anything the browser has
/// not laid out yet contributes nothing, so a page that reported no geometry
/// measures zero and the caller falls back to whatever it did before.
///
/// One definition, two callers: the dominant-column rule in this file and
/// `imageContentBand`'s density test both mean this quantity, and the bug this
/// exists to prevent is the two of them drifting apart.
int verticalExtentOf(Iterable<PageImage> images) => images.fold(
  0,
  (sum, image) => sum + (image.renderedHeight > 0 ? image.renderedHeight : 0),
);

int _verticalExtent(List<_Scored> cluster) =>
    verticalExtentOf(cluster.map((s) => s.image));

int _area(List<_Scored> cluster) =>
    cluster.fold(0, (sum, s) => sum + s.width * s.height);

class _Scored {
  const _Scored(this.image, this.url, this.width, this.height);
  final PageImage image;
  final String url;
  final int width;
  final int height;
}
