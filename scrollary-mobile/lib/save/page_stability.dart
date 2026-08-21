/// What "the page changed" means while a save is traversing it.
///
/// The scroll loop stops when the page has been quiet at the bottom for a
/// while, so whatever this file counts as *change* is what a save waits for.
/// Getting the set wrong is expensive in both directions: too broad and a
/// rotating advertisement keeps a finished page from ever settling; too narrow
/// and an entry is declared complete while its panels are still arriving.
///
/// The rule here is that **change to an image only counts when that image
/// could plausibly be entry content** ([couldBeContent]) — the same test the
/// fast-mode lookahead and the pending-asset wait use — while the two
/// structural facts about the page, its height and how many images it holds at
/// all, count unconditionally. Structure has to stay unconditional: infinite
/// loading routinely inserts empty containers first and fills them with images
/// afterwards, and a signal that watched only qualified images would read that
/// growth as nothing happening.
///
/// Pure over a [PageProbe], so the whole rule is testable against literal
/// fixtures rather than only through a live WebView.
library;

import '../browser/page_data.dart';
import '../core/config.dart';
import 'image_candidates.dart';

/// A page's traversal state, compared between probes with `==`.
class PageStability {
  const PageStability({
    required this.documentHeight,
    required this.imageCount,
    required this.contentCount,
    required this.resolvedContentCount,
    required this.brokenContentCount,
    required this.unrequestedContentCount,
    required this.contentFingerprint,
  });

  /// Laid-out document height. Unconditional: infinite loading that has added
  /// containers but not yet images shows up here and nowhere else.
  final int documentHeight;

  /// Every `<img>` the probe reported, qualified or not. Unconditional for the
  /// same reason: a newly inserted node is new DOM content even before it has
  /// a size that would let it qualify.
  final int imageCount;

  /// Images that could be entry content.
  final int contentCount;

  /// …of those, how many have loaded, and how many have finished badly. A
  /// broken image is a settled outcome, not a pending one, and the two are
  /// counted apart so a panel turning from pending to broken registers as
  /// progress rather than as silence.
  final int resolvedContentCount;
  final int brokenContentCount;

  /// …and how many have not been asked for at all.
  ///
  /// Counted separately so a lazy loader firing registers as progress. That
  /// transition — untriggered to in-flight — changes neither the resolved
  /// count nor, usually, the URL, so without this term the page could look
  /// settled at the exact moment it started fetching a panel.
  final int unrequestedContentCount;

  /// Order-independent digest of every qualifying image's URL **and** its
  /// measured size.
  ///
  /// Both halves are needed. A placeholder swapped for the real file changes
  /// the URL while the count stands still; a `srcset` re-resolution or an
  /// image that finally reports its intrinsic size changes the dimensions
  /// while the URL stands still. Either is progress.
  ///
  /// Order-independent on purpose: the digest answers "is this the same set of
  /// images", and a page that reorders its DOM without changing what it holds
  /// has not produced anything new to save.
  final int contentFingerprint;

  @override
  bool operator ==(Object other) =>
      other is PageStability &&
      other.documentHeight == documentHeight &&
      other.imageCount == imageCount &&
      other.contentCount == contentCount &&
      other.resolvedContentCount == resolvedContentCount &&
      other.brokenContentCount == brokenContentCount &&
      other.unrequestedContentCount == unrequestedContentCount &&
      other.contentFingerprint == contentFingerprint;

  @override
  int get hashCode => Object.hash(
    documentHeight,
    imageCount,
    contentCount,
    resolvedContentCount,
    brokenContentCount,
    unrequestedContentCount,
    contentFingerprint,
  );

  @override
  String toString() =>
      'height $documentHeight, $imageCount image(s), '
      '$contentCount content ($resolvedContentCount loaded, '
      '$brokenContentCount broken, $unrequestedContentCount not yet asked '
      'for)';
}

/// Measure [probe]'s traversal state.
PageStability measureStability(
  PageProbe probe, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  var contentCount = 0;
  var resolved = 0;
  var broken = 0;
  var unrequested = 0;
  // Hashed per image, then sorted, so the digest cannot depend on the order
  // the page happened to report its images in.
  final tokens = <int>[];

  for (final image in probe.images) {
    if (!couldBeContent(image, config: config)) continue;
    contentCount++;
    if (image.isResolved) resolved++;
    if (image.isBroken) broken++;
    if (image.isUnrequested) unrequested++;
    tokens.add(
      Object.hash(
        image.effectiveUrl,
        image.effectiveWidth,
        image.effectiveHeight,
      ),
    );
  }
  tokens.sort();

  return PageStability(
    documentHeight: probe.documentHeight,
    imageCount: probe.images.length,
    contentCount: contentCount,
    resolvedContentCount: resolved,
    brokenContentCount: broken,
    unrequestedContentCount: unrequested,
    contentFingerprint: Object.hashAll(tokens),
  );
}
