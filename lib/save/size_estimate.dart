/// How much disk a save is likely to need, and how sure that number is.
///
/// One estimator, read by every surface that shows a size before a save: the
/// save sheet in the Browser, the batch queue confirmation in a collection, and
/// the run's own rolling disk check. They disagreed before — the sheet
/// multiplied a flat 50 MB constant by the entry count and reported "up to
/// ~1.0 GB" for twenty ordinary entries, the batch sheet used a plain mean of
/// every non-zero row it could see, and the run used a median. Three answers to
/// one question is two answers too many.
///
/// The rules, in order:
///
/// 1. **This collection's own history wins.** What entries here have actually
///    cost is the only evidence about what the next one will cost.
/// 2. **Only trustworthy rows count.** A failed, interrupted, partially written
///    or user-removed row is not a measurement of a finished save.
/// 3. **The middle of the data, not the edges.** The typical entry is the
///    median, and the band around it is the middle half — so one enormous
///    entry moves the estimate by nothing.
/// 4. **No history means say so.** A band of what image entries usually cost,
///    presented as a range, rather than a precise-looking number nobody
///    measured.
library;

import '../storage/database.dart';
import '../storage/manifest.dart';

/// What an image-based entry usually costs, low end.
///
/// The band is deliberately wide because real entries are: a short page of
/// modest images lands near the bottom of it and a long page of full-size ones
/// near the top. It is only ever used when a collection has told us nothing,
/// and it is always shown as a range so it cannot read as a measurement.
const int kTypicalEntryBytesLow = 3 * 1024 * 1024;

/// What an image-based entry usually costs, high end.
const int kTypicalEntryBytesHigh = 20 * 1024 * 1024;

/// The one sentence for "we genuinely do not know yet".
const String kSizeUnknownMessage = 'Size cannot be estimated yet.';

/// Where an estimate's numbers came from. The UI shows this rather than
/// presenting every estimate with the same confidence.
enum SizeEstimateBasis {
  /// Measured from entries already saved in this collection.
  collectionHistory,

  /// Nothing has been saved here, so the typical band is used instead.
  typicalRange,

  /// No number can be given: no history, and nothing to fall back on.
  unknown,
}

/// Whether an entry's recorded size is evidence about what a save costs.
///
/// A row is a measurement only when a save finished, wrote a package, and the
/// package is still there. Everything else is excluded on purpose:
///
/// * `partial` — some assets failed, so the size understates a full save;
/// * `failed` / `saving` — nothing landed, or landed half-way;
/// * `knownRemote` — discovered at the source, never downloaded;
/// * files the user removed — `byte_size` is cleared to 0 and `content_path`
///   to null by the removal, so both checks below catch it;
/// * a zero size — a row that claims to hold a package of nothing.
bool isUsableSizeSample(Entry entry) =>
    entry.byteSize > 0 &&
    entry.contentPath != null &&
    entry.offlineRemovedAt == null &&
    entry.saveStatus == SaveStatus.complete.name;

/// One collection's trustworthy entry sizes, grouped by the artifact each
/// package holds.
///
/// Grouped rather than pooled because a text document and a page of full-size
/// images differ by two orders of magnitude, and the save sheet lets the user
/// switch between them after it opens. Estimating a text-only save from image
/// packages would be arithmetic applied to the wrong evidence.
class CollectionSizeHistory {
  const CollectionSizeHistory._(this._byArtifact, this._all);

  /// Nothing known — the state of a collection that has never been saved from,
  /// and of a page that belongs to no collection at all.
  const CollectionSizeHistory.empty() : _byArtifact = const {}, _all = const [];

  factory CollectionSizeHistory.fromEntries(Iterable<Entry> entries) {
    final byArtifact = <ArtifactFormat, List<int>>{};
    final all = <int>[];
    for (final entry in entries) {
      if (!isUsableSizeSample(entry)) continue;
      final artifact = ArtifactFormat.fromName(entry.artifactFormat);
      (byArtifact[artifact] ??= <int>[]).add(entry.byteSize);
      all.add(entry.byteSize);
    }
    for (final sizes in byArtifact.values) {
      sizes.sort();
    }
    all.sort();
    return CollectionSizeHistory._(byArtifact, all);
  }

  final Map<ArtifactFormat, List<int>> _byArtifact;
  final List<int> _all;

  /// Sizes in ascending order. [artifact] null means "whatever this collection
  /// holds" — the right question for a re-download of entries that already
  /// have a format each.
  List<int> forArtifact(ArtifactFormat? artifact) =>
      artifact == null ? _all : (_byArtifact[artifact] ?? const []);

  bool get isEmpty => _all.isEmpty;
}

/// What a save is likely to need on disk.
///
/// Always a range, because a single figure would claim a precision that does
/// not exist. When the evidence is tight the two ends are equal and it renders
/// as one number.
class SaveSizeEstimate {
  const SaveSizeEstimate._({
    required this.basis,
    this.lowBytes,
    this.highBytes,
    this.typicalEntryBytes,
  });

  /// No number can honestly be given.
  const SaveSizeEstimate.unknown()
    : basis = SizeEstimateBasis.unknown,
      lowBytes = null,
      highBytes = null,
      typicalEntryBytes = null;

  final SizeEstimateBasis basis;

  /// Total bytes at the low and high end of the band. Both null, or neither.
  final int? lowBytes;
  final int? highBytes;

  /// The representative size of **one** entry the total was built from. Null
  /// when there is no estimate.
  final int? typicalEntryBytes;

  bool get isKnown => lowBytes != null && highBytes != null;

  /// `15–100 MB`, or `36 MB` when the band has collapsed. Null when unknown.
  String? get sizeLabel =>
      isKnown ? formatByteRange(lowBytes!, highBytes!) : null;

  /// Names the evidence in a few words, so the estimate is never read as a
  /// measurement it is not. Null when there is nothing to qualify.
  String? get qualifier => switch (basis) {
    SizeEstimateBasis.collectionHistory =>
      'based on entries already saved here',
    SizeEstimateBasis.typicalRange => 'a rough range — nothing saved here yet',
    SizeEstimateBasis.unknown => null,
  };
}

/// The typical size of one entry, given this collection's [sortedSizes].
///
/// The median: it needs one sort and one index, it is the number a person would
/// point at if you showed them the list, and an entry ten times the size of its
/// neighbours moves it by nothing. Null when there is no usable history.
int? typicalEntryBytes(List<int> sortedSizes) =>
    sortedSizes.isEmpty ? null : _orderStatistic(sortedSizes, 0.5);

/// What [entryCount] entries are likely to need.
///
/// [historyBytes] must be ascending — [CollectionSizeHistory.forArtifact]
/// returns it that way. [fetchesImages] is false for a text-only save, which
/// has no measured band to fall back on: with no history that returns
/// [SaveSizeEstimate.unknown] rather than quoting an image-sized guess.
SaveSizeEstimate estimateSaveSize({
  required int? entryCount,
  required List<int> historyBytes,
  bool fetchesImages = true,
}) {
  // Zero, negative, or "the user has not typed a number yet" all mean the same
  // thing: there is nothing to multiply, so there is no estimate to show.
  final count = entryCount ?? 0;
  if (count <= 0) return const SaveSizeEstimate.unknown();

  if (historyBytes.isNotEmpty) {
    // The middle half of what this collection has cost. One freak entry sits
    // outside it by construction, which is the whole point of using order
    // statistics rather than a mean.
    final low = _orderStatistic(historyBytes, 0.25);
    final high = _orderStatistic(historyBytes, 0.75);
    return SaveSizeEstimate._(
      basis: SizeEstimateBasis.collectionHistory,
      lowBytes: low * count,
      highBytes: high * count,
      typicalEntryBytes: _orderStatistic(historyBytes, 0.5),
    );
  }

  if (!fetchesImages) return const SaveSizeEstimate.unknown();

  return SaveSizeEstimate._(
    basis: SizeEstimateBasis.typicalRange,
    lowBytes: kTypicalEntryBytesLow * count,
    highBytes: kTypicalEntryBytesHigh * count,
    typicalEntryBytes: (kTypicalEntryBytesLow + kTypicalEntryBytesHigh) ~/ 2,
  );
}

/// Nearest-rank order statistic over an ascending list. `q` of 0.5 is the
/// median.
int _orderStatistic(List<int> sorted, double q) =>
    sorted[((sorted.length - 1) * q).round().clamp(0, sorted.length - 1)];

/// `15–100 MB` · `900 MB – 1.2 GB` · `36 MB`.
///
/// A shared unit is written once, which is what makes the common case short
/// enough for a phone.
String formatByteRange(int lowBytes, int highBytes) {
  final low = _magnitude(lowBytes);
  final high = _magnitude(highBytes);
  if (low.unit == high.unit) {
    return low.number == high.number
        ? '${high.number} ${high.unit}'
        : '${low.number}–${high.number} ${high.unit}';
  }
  return '${low.number} ${low.unit} – ${high.number} ${high.unit}';
}

/// One size, formatted the way every estimate formats one.
String formatEstimatedBytes(int bytes) {
  final m = _magnitude(bytes);
  return '${m.number} ${m.unit}';
}

const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// Split [bytes] into a number and a binary unit.
///
/// Two rules keep the arithmetic honest: the division walks one unit at a time
/// from bytes, so no call site can multiply by the wrong power of 1024; and a
/// value that would *round* up into the next unit is promoted, so 1023.7 KB
/// prints as `1 MB` rather than `1024 KB`.
({String number, String unit}) _magnitude(int bytes) {
  var value = bytes.abs().toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (value >= 1023.5 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  // A decimal only where it carries information: 1.4 GB is a different amount
  // of free space from 1 GB, whereas 1.4 MB and 1 MB are the same decision.
  final number = unit >= _units.indexOf('GB') && value < 10
      ? value.toStringAsFixed(1)
      : '${value.round()}';
  return (number: number, unit: _units[unit]);
}
