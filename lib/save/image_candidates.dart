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
bool couldBeContent(
  PageImage image, {
  SaveConfig config = kDefaultSaveConfig,
}) =>
    contentRejection(image, config: config, unknownSizeIsTooSmall: false) ==
    null;

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

  clusters.sort((a, b) {
    final byCount = b.length.compareTo(a.length);
    if (byCount != 0) return byCount;
    return _area(b).compareTo(_area(a));
  });

  final best = clusters.first;
  if (best.length < config.minClusterSize) return survivors;

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

int _area(List<_Scored> cluster) =>
    cluster.fold(0, (sum, s) => sum + s.width * s.height);

class _Scored {
  const _Scored(this.image, this.url, this.width, this.height);
  final PageImage image;
  final String url;
  final int width;
  final int height;
}
