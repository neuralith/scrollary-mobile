/// ReadingState — the portable, language-agnostic fact about an Entry.
library;

/// The three honest answers about an Entry.
enum ReadStatus { unread, reading, completed }

/// Reading state belongs to the logical Entry — not to a file, a URL, a
/// Source or a language. You read the work once.
///
/// A separate record from Entry for a concrete reason: reading updates are the
/// most frequent mutation, and a separate row means a separate revision, so
/// marking something read does not force every other client to re-pull Entry
/// metadata that did not change.
///
/// `updatedAt` is the merge clock. Last write wins, and completion is a value
/// rather than a floor — highest-progress-wins looks safer and breaks "mark as
/// unread", which exists precisely to lower progress (V2-D6).
class ReadingState {
  const ReadingState({
    required this.entryId,
    this.status = ReadStatus.unread,
    this.firstOpenedAt,
    this.lastReadAt,
    this.completedAt,
    this.updatedAt,
  });

  final String entryId;
  final ReadStatus status;
  final DateTime? firstOpenedAt;
  final DateTime? lastReadAt;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  /// Opening an Entry at its source counts as access and never as completion
  /// (I16, V2-D9).
  ///
  /// Completion is only ever reached automatically inside Scrollary's own
  /// reader, where position is measured and the dwell policy applies. On a
  /// source we cannot observe position, so nothing is inferred and no progress
  /// figure is invented.
  ReadingState recordSourceAccess(DateTime at) {
    return ReadingState(
      entryId: entryId,
      status: status == ReadStatus.unread ? ReadStatus.reading : status,
      firstOpenedAt: firstOpenedAt ?? at,
      lastReadAt: at,
      completedAt: completedAt,
      updatedAt: at,
    );
  }
}
