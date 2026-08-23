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
library;

import '../browser/page_data.dart';
import '../core/url_utils.dart';
import '../data/measurement_repository.dart';

/// How far down [probe]'s page the reading has got, or null when the page
/// carries no position to measure.
///
/// The bottom of the viewport rather than its top: a reader who can see the
/// last line has reached the end, and measuring the top would say 80% of a
/// page they have finished. The same formula the save engine uses for its own
/// scroll accounting, and deliberately the same one — two ways of measuring
/// the same scroll is how they come to disagree.
double? sourceReadingFraction(PageProbe probe) {
  final document = probe.documentHeight;
  final viewport = probe.viewportHeight;
  if (viewport <= 0 || document <= 0) return null;
  // Nothing to scroll is not "0% read" and not "100% read" — it is a page
  // with no position, and a figure for it would be a claim about a reading
  // this app cannot observe.
  if (document <= viewport) return null;
  return ((probe.scrollY + viewport) / document).clamp(0.0, 1.0);
}

/// Writes what a reading at a Source came to, for the Entry it is a reading
/// of.
///
/// Holds one target at a time, because one WebView shows one page at a time.
/// [watch] is set by whatever recognised the page; [record] is called at the
/// moments the app has — the reader has stopped, the Browser is being left,
/// the app is going away — and decides for itself whether there is anything
/// honest to write.
class SourceReadingMeter {
  SourceReadingMeter(this._measurements);

  final MeasurementRepository _measurements;

  String? _entryId;
  String? _sourceId;
  String? _urlKey;

  /// The Entry currently being read at [sourceId], and the address it is
  /// being read at.
  ///
  /// The address is kept so a probe taken after the user has moved on cannot
  /// be attributed to the page they left: a measurement written against the
  /// wrong Entry is worse than no measurement, and the check costs one
  /// comparison.
  void watch({
    required String entryId,
    required String sourceId,
    required String url,
  }) {
    _entryId = entryId;
    _sourceId = sourceId;
    _urlKey = normalizeUrl(url);
  }

  /// Nothing recognised is being read. A page the library does not hold is
  /// device-local history and has no Entry to measure against (I11).
  void clear() {
    _entryId = null;
    _sourceId = null;
    _urlKey = null;
  }

  bool get isWatching => _entryId != null;

  /// Record where this reading has got to, if it can be said honestly.
  ///
  /// Returns the fraction written, or null when nothing was — an unwatched
  /// page, a probe of somewhere else, a page with no position, or a reading
  /// that has not got further than the one already recorded.
  ///
  /// **It never goes down.** A site that reloads to the top, a page reopened
  /// to re-read a paragraph, and a reader scrolling back to check a name are
  /// all the same scroll event and none of them is un-reading. Lowering
  /// progress is a deliberate act and it has its own verb —
  /// `ReadingStateRepository.markUnread` — which is reading state, not a
  /// measurement.
  Future<double?> record(PageProbe probe) async {
    final entryId = _entryId;
    final sourceId = _sourceId;
    if (entryId == null || sourceId == null) return null;
    if (_urlKey != null &&
        probe.url.isNotEmpty &&
        normalizeUrl(probe.url) != _urlKey) {
      return null;
    }

    final fraction = sourceReadingFraction(probe);
    if (fraction == null) return null;

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
