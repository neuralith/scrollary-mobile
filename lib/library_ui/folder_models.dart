/// The Folder tree's shape, and the words this UI uses about it (roadmap D2).
///
/// Folder deletion is conservative: children reparent to the deleted Folder's
/// parent, and nothing cascades into a Collection or an Entry (I5). The
/// repository has always behaved that way; the point of the copy in this file
/// is that the *user* is told so before they confirm, in the same counts the
/// repository reports afterwards.
library;

import '../data/data_violations.dart';
import '../data/folder_repository.dart';
import '../data/schema.dart';
import '../domain/folder.dart';
import '../domain/invariants.dart';
import 'collection_models.dart';

/// One Folder in a flattened tree, with the depth a picker indents by.
class FolderNode {
  const FolderNode({required this.folder, required this.depth});

  final FolderRow folder;
  final int depth;

  bool get isRoot => folder.kind == FolderKind.root.name;
  String get id => folder.id;
  String get name => folderDisplayName(folder);
}

/// The system root prints as **Library**: "at the library root" simply means
/// "in the root Folder" (V2-D21), and its stored name is not the user's to
/// see or change.
String folderDisplayName(FolderRow folder) =>
    folder.kind == FolderKind.root.name ? 'Library' : folder.name;

/// Depth-first, root first, siblings in the user's order.
///
/// A folder whose parent is missing is dropped rather than re-rooted: the
/// tree is what the rows say it is, and quietly adopting an orphan would hide
/// the inconsistency instead of surfacing it.
List<FolderNode> flattenFolderTree(List<FolderRow> all) {
  final root = all.where((f) => f.kind == FolderKind.root.name).firstOrNull;
  if (root == null) return const [];
  final children = <String, List<FolderRow>>{};
  for (final folder in all) {
    final parent = folder.parentId;
    if (parent == null) continue;
    children.putIfAbsent(parent, () => []).add(folder);
  }
  for (final list in children.values) {
    list.sort((a, b) {
      if (a.sortKey != b.sortKey) return a.sortKey.compareTo(b.sortKey);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  final nodes = <FolderNode>[];
  void walk(FolderRow folder, int depth) {
    nodes.add(FolderNode(folder: folder, depth: depth));
    for (final child in children[folder.id] ?? const <FolderRow>[]) {
      walk(child, depth + 1);
    }
  }

  walk(root, 0);
  return nodes;
}

/// What deleting a Folder will do, said before it happens.
///
/// Never "delete", never "remove", never a count of things destroyed —
/// because nothing is. The only verb available to this sentence is *move*.
String reparentSentence(ReparentCounts counts, String parentName) {
  if (counts.total == 0) {
    return 'This folder is empty. Nothing else changes.';
  }
  return 'Everything inside it — ${_contents(counts)} — moves up to '
      '$parentName. Nothing in your library is deleted.';
}

/// The same counts, reported by the repository after the move.
String reparentedSentence(ReparentCounts counts, String parentName) {
  if (counts.total == 0) return 'Folder deleted.';
  return 'Folder deleted. ${_contents(counts)} moved to $parentName.';
}

String _contents(ReparentCounts counts) => _join([
  if (counts.folders > 0) _plural(counts.folders, 'folder', 'folders'),
  if (counts.collections > 0)
    _plural(counts.collections, 'collection', 'collections'),
  // Entry counting goes through the label file; Folder and Collection are
  // ordinary nouns with regular plurals and are not its business.
  if (counts.entries > 0) libraryEntryLabels.count(counts.entries),
]);

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String _join(List<String> parts) => switch (parts.length) {
  0 => '',
  1 => parts.first,
  _ => '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}',
};

/// A named refusal from the repository, in a sentence.
///
/// The fallback is the violation's own message rather than an invented one:
/// refusals are named so that a new one cannot be introduced by writing a new
/// sentence, and that property is worth more here than polish.
String violationMessage(InvariantViolation violation) {
  if (violation == folderCycle) {
    return 'A folder cannot be moved into itself or into one of its own '
        'folders.';
  }
  if (violation == unknownParentFolder) {
    return 'That folder is no longer there.';
  }
  if (violation == rootFolderImmutable) {
    return 'The library root cannot be renamed, moved or deleted.';
  }
  if (violation == unknownRow) {
    return 'That is no longer in your library.';
  }
  return violation.message;
}
