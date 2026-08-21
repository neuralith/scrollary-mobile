/// Folder — user organisation and nothing else.
library;

import 'invariants.dart';

/// Separates the single system root from folders the user made.
enum FolderKind { root, user }

/// A Folder holds Collections and standalone Entries. It carries no source
/// identity and no content relationship, and Sources are never attached to it.
///
/// There is exactly one system root per library, chosen over a nullable
/// placement or a separate "unfiled" folder so that every item has exactly one
/// parent and every placement syncs as a value rather than sometimes as a null.
///
/// Deleting a Folder reparents its children to the deleted Folder's parent
/// (I5); the reparent itself lives in the repository, which owns the tree.
class Folder {
  const Folder({
    required this.id,
    required this.kind,
    required this.name,
    this.parentId,
    this.sortKey = 0,
  });

  final String id;
  final String? parentId;
  final FolderKind kind;
  final String name;
  final int sortKey;

  bool get isRoot => kind == FolderKind.root;

  /// I1: `parentId` is null if and only if this is the root. Also refuses the
  /// degenerate self-parent, the one cycle visible without the tree (I2).
  InvariantViolation? validate() {
    switch (kind) {
      case FolderKind.root:
        if (parentId != null) return rootMustNotHaveParent;
      case FolderKind.user:
        if (parentId == null) return folderMustHaveParent;
        if (parentId == id) return folderCycle;
    }
    return null;
  }
}

/// I2 over the whole tree: whether moving [folderId] under [newParentId] would
/// make the folder contain itself. [parentOf] maps folder id to parent id.
///
/// Used by the repository before a move; kept pure so the rule is testable
/// without a database.
bool wouldCreateFolderCycle({
  required Map<String, String?> parentOf,
  required String folderId,
  required String newParentId,
}) {
  var cursor = newParentId;
  final seen = <String>{};
  while (true) {
    if (cursor == folderId) return true;
    if (!seen.add(cursor)) return true; // pre-existing corruption: refuse
    final next = parentOf[cursor];
    if (next == null) return false;
    cursor = next;
  }
}
