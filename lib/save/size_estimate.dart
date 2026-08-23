/// Roughly how much a download will cost, from what this collection has
/// actually cost so far.
///
/// **Why this file exists.** V1 showed an estimate and the free space beside
/// it before the user chose a count, and refused the run if there was not
/// room. That went out with the scope sheet in `b0740eb`; V2 kept a per-row
/// disk gate that fails a row *silently* once a run is already going, which
/// answers the safety question and not the user's.
///
/// **Evidence, not a model.** The only input is what entries of this
/// collection already took on this device. No per-format guess, no
/// image-count heuristic, no site knowledge — an entry has an honest expected
/// size exactly when something comparable has been downloaded, and says so
/// otherwise. V1's `unknownEntryEstimate` constant is deliberately not
/// restored: a number invented for a collection nothing has been saved from
/// is not an estimate, it is a guess wearing one's clothes.
library;

/// What a download is expected to cost.
class DownloadEstimate {
  const DownloadEstimate({required this.bytes, required this.sampleSize});

  /// Nothing comparable has been downloaded, so there is no honest figure.
  const DownloadEstimate.unknown() : bytes = 0, sampleSize = 0;

  /// The expected total, in bytes. Meaningless unless [isKnown].
  final int bytes;

  /// How many already-downloaded entries it was derived from. The user is
  /// told when this is thin, because an estimate from one entry is one
  /// entry's worth of confidence.
  final int sampleSize;

  bool get isKnown => sampleSize > 0;

  /// True when it rests on so little that it should be read as a hint.
  bool get isRough => sampleSize > 0 && sampleSize < 3;
}

/// What [entries] more of this collection would be expected to cost, given
/// [alreadyDownloaded] byte sizes from it.
///
/// The **median** rather than the mean: one enormous entry — one that
/// happened to be a single tall image, or a gallery — should not drag the
/// figure for the twenty ordinary ones after it.
DownloadEstimate estimateDownload({
  required List<int> alreadyDownloaded,
  required int entries,
}) {
  final sample = [
    for (final bytes in alreadyDownloaded)
      if (bytes > 0) bytes,
  ]..sort();
  if (sample.isEmpty || entries <= 0) return const DownloadEstimate.unknown();

  final middle = sample.length ~/ 2;
  final typical = sample.length.isOdd
      ? sample[middle]
      : (sample[middle - 1] + sample[middle]) ~/ 2;

  return DownloadEstimate(bytes: typical * entries, sampleSize: sample.length);
}

/// The estimate in words, or null when there is nothing honest to say.
///
/// Deliberately vague where the evidence is thin: *about* rather than a
/// figure, and a plain admission when nothing comparable exists. A precise
/// number carries a confidence the input does not have.
String? downloadEstimateSentence(
  DownloadEstimate estimate,
  String Function(int bytes) format,
) {
  if (!estimate.isKnown) return null;
  final size = format(estimate.bytes);
  return estimate.isRough
      ? 'Roughly $size, going by the one already downloaded.'
      : 'About $size, going by what this collection usually costs.';
}
