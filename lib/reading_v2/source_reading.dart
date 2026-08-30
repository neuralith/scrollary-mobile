/// How far through an Entry a reading **at its Source** got.
///
/// **Why this file exists.** V2 has a Measurement model — keyed `(entry,
/// source)`, because a fraction of one rendering is not an approximation of
/// another's (I12, V2-D18) — and nothing in the app ever wrote one.
/// `MeasurementRepository.put` had exactly one caller, the sync pull path, so
/// every measurement a device held had been measured somewhere else. Reading
/// an Entry on its own site recorded that it had been opened and nothing
/// about how far, and there is no honest way to show progress for an Entry
/// this device holds no copy of without it.
///
/// **Reading state and download state stay independent** (PRODUCT.md §2.3).
/// Nothing here needs an OfflineCopy, writes one, or asks whether one exists:
/// an Entry read at its Source keeps its progress on a device that has
/// downloaded nothing.
///
/// **Nothing is invented.** The only input is geometry the page itself
/// reports, through the same probe every other part of this app measures with.
/// A page no taller than the viewport has no position to be at, and gets no
/// figure — which is the same refusal `readPageShape` makes about a number no
/// page printed.
///
/// **A page is not the same thing as the reading on it.** The document a site
/// serves carries the entry *and* whatever the site puts after it — comments,
/// recommendations, a footer the length of a screen. Measuring against the
/// document says a reader who has seen every panel is at 70%, which is a claim
/// about the site rather than about the reading. Where the readable region can
/// be established from the page's own geometry, it is measured against that
/// instead: see [imageContentBand].
///
/// **A scroll a machine performed is not a reading.** Capture scrolls a page
/// to the bottom to enumerate it and leaves it there; a measurement taken
/// afterwards would mark an Entry read *by downloading it*, which is exactly
/// the conflation PRODUCT.md §2.3 forbids. The meter is told when automation
/// takes the page ([SourceReadingMeter.noteAutomationScroll]) and when the
/// user moves it themselves ([SourceReadingMeter.noteUserScroll]), and refuses
/// to attribute a position it has no evidence a person put the page in.
library;

import '../browser/page_data.dart';
import '../core/config.dart';
import '../core/url_utils.dart';
import '../data/data_ids.dart' show Clock, utcNow;
import '../data/measurement_repository.dart';
import '../save/image_candidates.dart';

/// The band of the document an image-based Entry's readable content occupies.
///
/// Document coordinates, the same origin `PageProbe.scrollY` is in.
class ImageContentBand {
  const ImageContentBand({
    required this.top,
    required this.bottom,
    required this.imageCount,
  });

  final int top;
  final int bottom;

  /// How many content images the band was established from. Carried so a
  /// caller can say *why* it trusts the band rather than only that it does.
  final int imageCount;

  int get height => bottom - top;
}

/// How much of the band's own height has to be image for it to be one.
///
/// A strip of panels is nearly solid image; two photographs at opposite ends
/// of an article are not a band, they are two photographs. 0.6 leaves room for
/// the gaps a site puts between panels — captions, ad slots the candidate
/// filter already removed, ordinary margins — without accepting a region that
/// is mostly something else.
const double kContentBandDensity = 0.6;

/// How few images may establish a band.
///
/// Three is the smallest number that can show a *pattern* of stacked content
/// rather than a coincidence of two. Below it the document is the honest
/// denominator.
const int kContentBandMinimumImages = 3;

/// The document band an image-based Entry's readable content occupies, or null
/// when this page's geometry cannot establish one.
///
/// **Deliberately a measurement, never a site rule.** The inputs are the same
/// ones `selectImageCandidates` already judges content by — size floor, chrome
/// and hidden exclusion, banner aspect, the dominant width cluster — plus two
/// facts about how the accepted images sit on the page. No hostname, selector
/// or class name is consulted, and nothing here can be tuned for one site.
///
/// It refuses, and falls back to the whole document, whenever the band would
/// be a guess:
///
///  * the probe did not see the whole image population (`imagesTruncated`), so
///    the last accepted image is not known to be the last one;
///  * fewer than [kContentBandMinimumImages] images were accepted;
///  * any accepted image has no laid-out box yet — a lazy panel that has not
///    been swapped in has no position on the page, so neither has the band;
///  * the images are not a single vertical run — a grid or a carousel puts
///    several images at the same height, and a band across one is not a
///    reading order;
///  * the band is less than [kContentBandDensity] image by height;
///  * the band is no taller than the viewport, which is the same refusal
///    [sourceReadingFraction] makes about a page with no position to be at.
///
/// **The rendered box, not the intrinsic size.** `PageImage.effectiveHeight`
/// prefers `naturalHeight`, which is the file's own height and has nothing to
/// do with where the image ends on this page. A band is document geometry, so
/// it is built from `documentTop` and `renderedHeight` only.
ImageContentBand? imageContentBand(
  PageProbe probe, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  if (probe.imagesTruncated) return null;
  if (probe.viewportHeight <= 0 || probe.documentHeight <= 0) return null;

  final accepted = selectImageCandidates(probe.images, config: config).accepted;
  if (accepted.length < kContentBandMinimumImages) return null;

  final byIndex = {for (final image in probe.images) image.domIndex: image};
  final boxes = <({int top, int height})>[];
  for (final candidate in accepted) {
    final image = byIndex[candidate.domIndex];
    if (image == null) return null;
    // No laid-out box means no position on the page. A band whose end is an
    // image the browser has not placed yet would move under the reader, and
    // a measurement never goes down — so a band like that could only ever be
    // wrong in the direction that matters.
    if (image.renderedHeight <= 0) return null;
    boxes.add((top: image.documentTop, height: image.renderedHeight));
  }
  boxes.sort((a, b) => a.top.compareTo(b.top));

  // One vertical run. Each image starts below the middle of the one before
  // it; anything tighter is two images side by side, which is a grid and not
  // a reading order.
  for (var i = 1; i < boxes.length; i++) {
    final previous = boxes[i - 1];
    if (boxes[i].top < previous.top + (previous.height / 2)) return null;
  }

  final top = boxes.first.top;
  final last = boxes.last;
  final bottom = last.top + last.height;
  if (bottom <= top) return null;

  final span = bottom - top;
  if (span <= probe.viewportHeight) return null;

  final covered = boxes.fold<int>(0, (sum, box) => sum + box.height);
  if (covered / span < kContentBandDensity) return null;

  return ImageContentBand(
    top: top,
    // The band cannot end past the document it was measured on.
    bottom: bottom > probe.documentHeight ? probe.documentHeight : bottom,
    imageCount: boxes.length,
  );
}

/// How far down [probe]'s page the reading has got, or null when the page
/// carries no position to measure.
///
/// The bottom of the viewport rather than its top: a reader who can see the
/// last line has reached the end, and measuring the top would say 80% of a
/// page they have finished. The same formula the save engine uses for its own
/// scroll accounting, and deliberately the same one — two ways of measuring
/// the same scroll is how they come to disagree.
///
/// Measured against the readable band when the page has one ([imageContentBand]),
/// and against the whole document when it has not. Reaching the bottom of the
/// last panel is 100% even where the site goes on for another screen of
/// comments: the reading is of the Entry, not of the page it was served on.
double? sourceReadingFraction(
  PageProbe probe, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  final span = readableSpan(probe, config: config);
  if (span == null) return null;
  return ((probe.scrollY + probe.viewportHeight - span.top) / span.height)
      .clamp(0.0, 1.0);
}

/// The document region a fraction of this page is a fraction *of*, or null
/// when there is none.
///
/// Split out from [sourceReadingFraction] because the meter needs the size of
/// the region as well as the position within it: how many viewports of reading
/// a fraction represents is what tells a genuine reading from a flick through.
({int top, int height})? readableSpan(
  PageProbe probe, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  final document = probe.documentHeight;
  final viewport = probe.viewportHeight;
  if (viewport <= 0 || document <= 0) return null;

  final band = imageContentBand(probe, config: config);
  if (band != null) return (top: band.top, height: band.height);

  // Nothing to scroll is not "0% read" and not "100% read" — it is a page
  // with no position, and a figure for it would be a claim about a reading
  // this app cannot observe.
  if (document <= viewport) return null;
  return (top: 0, height: document);
}

/// What one visit to one Entry's Source came to.
///
/// The evidence a completion decision is allowed to be made from, and nothing
/// else: how far the reading got, how long it lasted, and how much of it the
/// reader moved themselves. Deliberately a value — whoever judges it says so
/// in its own file, so "was this read?" cannot quietly become something the
/// meter decides while it is writing a number.
class SourceReadingVisit {
  const SourceReadingVisit({
    required this.entryId,
    required this.sourceId,
    required this.fraction,
    required this.dwell,
    required this.viewportsCovered,
    required this.scrollEvents,
    required this.automationMoved,
  });

  final String entryId;
  final String sourceId;

  /// The furthest fraction observed on this visit, or null when the page never
  /// had a position to be at.
  final double? fraction;

  /// How long this page has been the watched one.
  final Duration dwell;

  /// How many viewports of readable region the reading has passed over. Zero
  /// when nothing was measurable.
  final double viewportsCovered;

  /// How many times the user moved the page themselves.
  final int scrollEvents;

  /// Automation has scrolled this page since the user last did, so the
  /// position it is in now is not one a person put it in.
  final bool automationMoved;
}

/// Writes what a reading at a Source came to, for the Entry it is a reading
/// of.
///
/// Holds one target at a time, because one WebView shows one page at a time.
/// [watch] is set by whatever recognised the page; [record] is called at the
/// moments the app has — the reader has stopped scrolling, the Browser is
/// being left, the app is going away — and decides for itself whether there is
/// anything honest to write.
class SourceReadingMeter {
  SourceReadingMeter(this._measurements, {Clock? now}) : _now = now ?? utcNow;

  final MeasurementRepository _measurements;
  final Clock _now;

  String? _entryId;
  String? _sourceId;
  String? _urlKey;

  DateTime? _watchedAt;
  double? _best;
  double _viewportsCovered = 0;
  int _scrollEvents = 0;
  bool _automationMoved = false;

  /// The Entry currently being read at [sourceId], and the address it is
  /// being read at.
  ///
  /// The address is kept so a probe taken after the user has moved on cannot
  /// be attributed to the page they left: a measurement written against the
  /// wrong Entry is worse than no measurement, and the check costs one
  /// comparison.
  ///
  /// Watching a page starts a fresh visit. Everything the last one knew — how
  /// far it got, how long it lasted, whether a machine had moved it — was
  /// about a page that is no longer on screen.
  void watch({
    required String entryId,
    required String sourceId,
    required String url,
  }) {
    _entryId = entryId;
    _sourceId = sourceId;
    _urlKey = normalizeUrl(url);
    _watchedAt = _now();
    _best = null;
    _viewportsCovered = 0;
    _scrollEvents = 0;
    _automationMoved = false;
  }

  /// Nothing recognised is being read. A page the library does not hold is
  /// device-local history and has no Entry to measure against (I11).
  void clear() {
    _entryId = null;
    _sourceId = null;
    _urlKey = null;
    _watchedAt = null;
    _best = null;
    _viewportsCovered = 0;
    _scrollEvents = 0;
    _automationMoved = false;
  }

  bool get isWatching => _entryId != null;

  /// Something other than the user is moving this page.
  ///
  /// Called when an operation takes the Browser — a capture enumerating a page
  /// by scrolling it to the bottom, an update check walking a site. From here
  /// on the page's scroll position is a fact about the operation, so the meter
  /// writes nothing from it. The seal lifts when the user scrolls the page
  /// themselves ([noteUserScroll]) or when a different page is watched.
  void noteAutomationScroll() {
    if (_entryId == null) return;
    _automationMoved = true;
  }

  /// The user moved this page.
  ///
  /// Both halves matter. It lifts the automation seal — wherever the page is
  /// now, a person put it there — and it counts, because a reading that was
  /// genuinely scrolled through produces a stream of these and a page tapped
  /// past produces none.
  void noteUserScroll() {
    if (_entryId == null) return;
    _automationMoved = false;
    _scrollEvents++;
  }

  /// What this visit has come to so far, or null when nothing is being
  /// watched.
  ///
  /// Read by whoever decides what *moving on* means, and read **before** the
  /// next page is watched — a visit is only knowable while it is still the
  /// current one.
  SourceReadingVisit? get visit {
    final entryId = _entryId;
    final sourceId = _sourceId;
    final watchedAt = _watchedAt;
    if (entryId == null || sourceId == null || watchedAt == null) return null;
    return SourceReadingVisit(
      entryId: entryId,
      sourceId: sourceId,
      fraction: _best,
      dwell: _now().difference(watchedAt),
      viewportsCovered: _viewportsCovered,
      scrollEvents: _scrollEvents,
      automationMoved: _automationMoved,
    );
  }

  /// Record where this reading has got to, if it can be said honestly.
  ///
  /// Returns the fraction written, or null when nothing was — an unwatched
  /// page, a probe of somewhere else, a page a machine last moved, a page with
  /// no position, or a reading that has not got further than the one already
  /// recorded.
  ///
  /// **It never goes down.** A site that reloads to the top, a page reopened
  /// to re-read a paragraph, and a reader scrolling back to check a name are
  /// all the same scroll event and none of them is un-reading. Lowering
  /// progress is a deliberate act and it has its own verb —
  /// `ReadingStateRepository.markUnread` — which is reading state, not a
  /// measurement.
  Future<double?> record(
    PageProbe probe, {
    SaveConfig config = kDefaultSaveConfig,
  }) async {
    final entryId = _entryId;
    final sourceId = _sourceId;
    if (entryId == null || sourceId == null) return null;
    // A position a machine put the page in is not a reading, and no probe of
    // it can be turned into one. See the library comment.
    if (_automationMoved) return null;
    if (_urlKey != null &&
        probe.url.isNotEmpty &&
        normalizeUrl(probe.url) != _urlKey) {
      return null;
    }

    final span = readableSpan(probe, config: config);
    if (span == null) return null;
    final fraction = sourceReadingFraction(probe, config: config);
    if (fraction == null) return null;

    // How much reading this position represents, in screens. Held for the
    // completion decision, which has to be able to tell twelve screens read
    // from one screen glanced at.
    if (probe.viewportHeight > 0) {
      final covered = fraction * span.height / probe.viewportHeight;
      if (covered > _viewportsCovered) _viewportsCovered = covered;
    }
    if (_best == null || fraction > _best!) _best = fraction;

    final existing = await _measurements.of(entryId, sourceId);
    if (existing != null && existing.fraction >= fraction) return null;

    final (written, _) = await _measurements.put(
      entryId: entryId,
      sourceId: sourceId,
      fraction: fraction,
    );
    return written?.fraction;
  }
}
