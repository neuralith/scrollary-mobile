/// The V1 library shelf's models and formatters, kept for the surfaces that
/// outlive the screen itself — storage, settings, the reader's V1 path and
/// the V1 providers. The screen retired at the D3+E5 cutover; this tail
/// retires with the V1 database.
library;

import 'package:flutter/material.dart';

import '../library/collection_identity.dart';
import '../library/content_shape.dart';
import '../library/entry_labels.dart';
import '../library/collection_repository.dart';
import '../reading/reading_position.dart';
import '../ui/palette.dart';
import '../storage/database.dart';

/// A collection plus the numbers its library row shows.
/// One row on the library shelf: a [Collection] with its entries, **or** a
/// standalone entry that belongs to no collection.
///
/// A union rather than "wrap the standalone entry in a collection of one". The
/// database has no such row and must not gain one: a phantom group in the
/// library is something the user never made, cannot meaningfully open, and would
/// make "3 collections" mean "3 unrelated articles". [collection] is null for a
/// standalone entry, and [isStandalone] is what screens branch on.
///
/// Known limitation: archiving is a collection-level state, so a standalone
/// entry always reads as `active`. Removing its offline files and re-saving it
/// work exactly as they do for an entry inside a collection.
class LibraryCollection {
  const LibraryCollection({this.collection, required this.entries});

  /// Null when this shelf item *is* a single entry.
  final Collection? collection;
  final List<Entry> entries;

  bool get isStandalone => collection == null;

  /// The one entry, for a standalone shelf item.
  Entry? get standaloneEntry => isStandalone ? entries.firstOrNull : null;

  /// Stable identity for list keys and routes.
  String get id => collection?.id ?? (entries.firstOrNull?.id ?? '');

  String get host => collection?.host ?? (entries.firstOrNull?.host ?? '');

  /// Standalone entries have no archive state of their own.
  String get lifecycle => collection?.lifecycle ?? 'active';

  /// The detected title, and the user's override. Both null for a standalone
  /// entry, whose name is the entry's own title — see [displayName].
  String? get title => collection?.title;
  String? get userTitle => collection?.userTitle;

  /// The finished-entry cleanup decision. Always null for a standalone entry:
  /// the preference is per collection, and there is no forward transition to
  /// apply it to.
  String? get cleanupPreference => collection?.cleanupPreference;
  DateTime? get archivedAt => collection?.archivedAt;
  DateTime? get createdAt =>
      collection?.createdAt ?? entries.firstOrNull?.savedAt;
  DateTime? get lastReadAt =>
      collection?.lastReadAt ?? entries.firstOrNull?.lastReadAt;

  /// The vocabulary this shelf item uses for its entries, from the stored
  /// shape — never a noun typed into a screen.
  EntryLabels get labels => collection == null
      ? labelsFor(
          kind: ContentKind.fromName(entries.firstOrNull?.contentKind),
          confidence: ShapeConfidence.fromName(
            entries.firstOrNull?.contentKindConfidence,
          ),
        )
      : labelsFor(
          kind: ContentKind.fromName(collection!.contentKind),
          sequence: SequenceKind.fromName(collection!.sequenceKind),
          confidence: ShapeConfidence.fromName(collection!.shapeConfidence),
        );

  /// Total the source published, when it published one. Null is the normal
  /// answer and must never be rendered as a number.
  int? get knownEntryTotal => collection?.knownEntryTotal;

  bool get isOpenEnded =>
      SequenceKind.fromName(collection?.sequenceKind).isOpenEnded;

  String get displayName {
    final c = collection;
    if (c != null) return displayNameFor(c);
    final entry = entries.firstOrNull;
    final title = entry?.title.trim() ?? '';
    if (title.isNotEmpty) return title;
    return entry?.host.isNotEmpty == true ? entry!.host : 'Saved page';
  }

  /// Entries a save has at least been attempted for. Discovered-but-not-
  /// saved entries are counted separately — "12 entries" must not
  /// quietly include ones the device does not hold.
  List<Entry> get savedEntries =>
      entries.where((c) => c.saveStatus != 'knownRemote').toList();

  /// Known to exist on the source, not yet saved (from an update check).
  List<Entry> get knownRemoteEntries =>
      entries.where((c) => c.saveStatus == 'knownRemote').toList();

  int get entryCount => savedEntries.length;
  int get knownRemoteCount => knownRemoteEntries.length;

  /// The newest entry the source is known to have, saved or not.
  String? get latestKnownLabel {
    final all = sortEntriesForReading(entries);
    if (all.isEmpty) return null;
    final last = all.last;
    final label = last.sourceMarker;
    return (label != null && label.isNotEmpty) ? label : last.title;
  }

  int get offlineCount => entries
      .where((c) => c.contentPath != null && c.saveStatus != 'failed')
      .length;

  /// Locally readable entries the user has not finished. This is the number
  /// a reader actually wants on the shelf: "how much is waiting for me here".
  int get unreadOfflineCount => entries
      .where(
        (c) =>
            c.contentPath != null &&
            (c.saveStatus == 'complete' || c.saveStatus == 'partial') &&
            c.readStatus != ReadStatus.completed.name,
      )
      .length;

  int get partialEntries =>
      entries.where((c) => c.saveStatus == 'partial').length;
  int get failedEntries =>
      entries.where((c) => c.saveStatus == 'failed').length;
  int get problemEntries => partialEntries + failedEntries;

  /// One line, worst first. Nothing wrong means no line at all — a row without
  /// a warning is the normal case and must not carry an empty slot.
  ///
  /// Takes the palette rather than baking a colour in: this is view data, and
  /// a model that names `0xFF8E3B31` decides what the dark theme looks like
  /// from inside a getter nobody thinks of as presentation.
  CollectionWarning? warningLine(AppPalette palette) {
    if (failedEntries > 0) {
      return CollectionWarning(
        Icons.error,
        '$failedEntries save${failedEntries == 1 ? '' : 's'} failed',
        palette.danger,
      );
    }
    if (partialEntries > 0) {
      return CollectionWarning(
        Icons.arrow_circle_down,
        '${labels.count(partialEntries)} partial',
        palette.warn,
      );
    }
    return null;
  }

  /// Update-check state for the row. `null` means **never checked** — which
  /// the UI must render as "not checked yet", never as zero new entries.
  DateTime? get lastCheckedAt => collection?.lastCheckSuccessAt;
  bool get lastCheckFailed => collection?.lastCheckError != null;

  DateTime? get lastSavedAt {
    DateTime? latest = collection?.lastSavedAt;
    for (final c in entries) {
      final at = c.savedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// The most recently saved entry, which is what a reader coming back is
  /// most likely looking for.
  String? get latestEntryLabel {
    Entry? newest;
    for (final c in entries) {
      if (c.savedAt == null) continue;
      if (newest?.savedAt == null || c.savedAt!.isAfter(newest!.savedAt!)) {
        newest = c;
      }
    }
    newest ??= entries.isEmpty ? null : entries.last;
    if (newest == null) return null;
    final label = newest.sourceMarker;
    return (label != null && label.isNotEmpty) ? label : newest.title;
  }
}

String formatRelative(DateTime? t) {
  if (t == null) return 'not saved';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The one warning a collection row is allowed to show, most serious first.
class CollectionWarning {
  const CollectionWarning(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
}

List<Entry> sortEntriesForReading(List<Entry> entries) {
  final sorted = [...entries];
  sorted.sort(
    (a, b) => compareEntriesForReading(
      (number: a.entryNumber, entryOrder: a.entryOrder, savedAt: a.savedAt),
      (number: b.entryNumber, entryOrder: b.entryOrder, savedAt: b.savedAt),
    ),
  );
  return sorted;
}

/// The persisted per-collection entry sort (V1). Kept for the developer
/// reset, which clears it.
const String kEntrySortKey = 'collection.entrySort';
