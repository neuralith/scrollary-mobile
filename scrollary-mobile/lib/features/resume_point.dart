import '../reading/reading_position.dart';
import '../reading/reading_repository.dart';
import '../storage/database.dart';
import 'library_screen.dart' show LibraryCollection;

/// One row of Continue Reading / Recently Read: which collection, which entry to
/// open, and the reading state behind that choice.
class ResumePoint {
  const ResumePoint({
    required this.group,
    required this.entry,
    required this.state,
  });

  final LibraryCollection group;

  /// The entry tapping this opens — the unfinished one, else the next
  /// unread, else (for Recently Read) the last completed.
  final Entry entry;
  final CollectionReadingState state;

  String get displayName => group.displayName;

  String get sourceMarker {
    final label = entry.sourceMarker;
    return (label != null && label.isNotEmpty) ? label : entry.title;
  }

  double get progress => readProgressFor(
    readStatus: entry.readStatus,
    stored: entry.progressFraction,
  );
  bool get isCompleted => entry.readStatus == 'completed';
  DateTime? get lastReadAt => state.lastReadAt;

  /// Readable entries that come *after* [entry] in reading order.
  ///
  /// Deliberately not "how many are left in the collection". A collection can be added
  /// from the middle, so the local count is no evidence of what the source
  /// published; the only honest number is how much more this device holds.
  /// [CollectionReadingState.entries] is already the readable set in reading
  /// order, so this is a position lookup, not a second filter.
  int get laterEntryCount {
    final index = state.entries.indexWhere((c) => c.id == entry.id);
    return index < 0 ? 0 : state.entries.length - index - 1;
  }

  /// How [laterEntryCount] reads on a card, in this collection's own
  /// vocabulary. Nothing after this entry is a *state*, not a zero — a
  /// "0 remaining" line reads as a defect.
  String get laterEntriesLabel {
    final labels = group.labels;
    return switch (laterEntryCount) {
      0 => 'Latest ${labels.one} available',
      final n => '${labels.count(n)} remaining',
    };
  }
}
