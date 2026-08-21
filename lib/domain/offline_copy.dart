/// OfflineCopy — device-local bytes. Never synced, in either direction (I11).
library;

/// One active copy per Entry per device (I13). A re-download replaces it
/// through the existing atomic commit-with-restore path.
///
/// Provenance is stored as VALUES, not references (V2-D22): a Source can die
/// and a Location can be retracted without orphaning a copy already on a
/// device, and the copy can still say where it came from. For the same reason
/// the record survives its Entry's deletion — a remote removal takes library
/// rows and leaves the package on disk (I14), and this record is what lets the
/// cleanup surface name what it is offering to remove.
class OfflineCopy {
  const OfflineCopy({
    required this.id,
    required this.entryId,
    required this.locationUrl,
    required this.capturedAt,
    required this.artifactFormat,
    required this.contentPath,
    required this.byteSize,
    this.sourceName = '',
    this.sourceHost = '',
    this.sourceLanguage = '',
    this.anchorIndex,
    this.anchorOffset,
    this.active = true,
  });

  final String id;
  final String entryId;

  // Provenance, copied at capture. Values, never foreign keys.
  final String locationUrl;
  final String sourceName;
  final String sourceHost;
  final String sourceLanguage;
  final DateTime capturedAt;

  final String artifactFormat;
  final String contentPath;
  final int byteSize;

  /// The reading anchor: position inside this artifact. Meaningless without
  /// the bytes, which is why it lives here and nowhere else.
  final int? anchorIndex;
  final double? anchorOffset;

  final bool active;
}
