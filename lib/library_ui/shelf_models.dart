/// View models for the Library shelf (roadmap D1).
///
/// A shelf is **one Folder's contents**: the Collections in it, the standalone
/// Entries that live in it directly, and the Folders inside it — each of
/// which is a shelf of its own. The root's shelf is therefore the whole
/// library, and the Library screen draws it as one page with Folders as
/// collapsible sections rather than as screens to navigate into (V2-D43).
///
/// What is deliberately absent: any notion of a shelf item being unavailable.
/// Downloading is a per-device capability of an Entry, never the precondition
/// for it being here (PRODUCT.md §1.2).
library;

import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/folder.dart';
import 'collection_models.dart';

/// What one Folder holds, down to every Folder inside it.
class ShelfView {
  const ShelfView({
    required this.folder,
    required this.folders,
    required this.collections,
    required this.entries,
  });

  final FolderRow folder;

  /// The Folders inside this one, each with its own contents.
  final List<ShelfView> folders;
  final List<ShelfCollectionView> collections;

  /// Standalone Entries: first-class library items, never wrapped in a
  /// Collection of one (V2_ARCHITECTURE.md §2.4).
  final List<EntryRowView> entries;

  String get id => folder.id;

  bool get isRoot => folder.kind == FolderKind.root.name;

  /// Nothing in this Folder at all — not a Collection, not an Entry, and no
  /// Folder inside it either.
  bool get isEmpty => folders.isEmpty && collections.isEmpty && entries.isEmpty;

  /// Collections in this Folder and every Folder below it.
  int get collectionCountDeep =>
      collections.length +
      folders.fold(0, (sum, f) => sum + f.collectionCountDeep);

  /// Standalone Entries in this Folder and every Folder below it.
  int get entryCountDeep =>
      entries.length + folders.fold(0, (sum, f) => sum + f.entryCountDeep);
}

/// One Collection on a shelf row, with the reading signal that belongs beside
/// its name.
class ShelfCollectionView {
  const ShelfCollectionView({
    required this.row,
    required this.entryCount,
    required this.unreadCount,
  });

  final CollectionRow row;

  /// Entries in the library for this Collection — not entries downloaded.
  final int entryCount;

  /// Entries not yet read. Reading state belongs to the logical Entry,
  /// wherever it was read (I10).
  final int unreadCount;

  String get id => row.id;
  String get name => row.name;

  bool get archived => row.lifecycle == CollectionLifecycle.archived.name;

  /// `8 items · 3 unread`. Counting goes through the label file, so no screen
  /// hand-rolls a plural.
  String get signalLine {
    final extent = libraryEntryLabels.count(entryCount);
    return unreadCount == 0 ? extent : '$extent · $unreadCount unread';
  }
}
