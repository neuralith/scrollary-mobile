/// Folder management: create, rename, move, delete (roadmap D2).
///
/// The whole point of this file is the **delete**. Deleting a Folder moves its
/// children up to the Folder's parent and destroys nothing (I5) — and a user
/// only knows that if the confirmation says so, in the same counts the
/// repository reports back afterwards. Nothing here may print the word
/// *delete* about anything except the Folder itself.
///
/// The root is not the user's to rename, move or delete. Those actions are
/// **absent** for it, not disabled: the app's pattern for a control that does
/// not apply is that it is not there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schema.dart';
import '../ui/menu_sheet.dart';
import '../ui/status_style.dart';
import 'folder_models.dart';
import 'folder_picker.dart';
import 'library_widgets.dart';
import 'providers.dart';

/// Rename / move / delete for one user Folder. Never called for the root.
Future<void> showFolderMenu(
  BuildContext context,
  WidgetRef ref,
  FolderRow folder, {
  VoidCallback? onDeleted,
}) async {
  final action = await showLibraryMenu<_FolderAction>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            folderDisplayName(folder),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: serifStyle(size: 20),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline),
          title: const Text('Rename folder'),
          onTap: () => Navigator.of(sheetContext).pop(_FolderAction.rename),
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('Move folder'),
          subtitle: const Text('Puts this folder inside another one.'),
          onTap: () => Navigator.of(sheetContext).pop(_FolderAction.move),
        ),
        ListTile(
          leading: const Icon(Icons.folder_delete_outlined),
          title: const Text('Delete folder'),
          subtitle: const Text(
            'Everything inside moves up one level. Nothing is deleted.',
          ),
          onTap: () => Navigator.of(sheetContext).pop(_FolderAction.delete),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _FolderAction.rename:
      await renameFolder(context, ref, folder);
    case _FolderAction.move:
      await moveFolder(context, ref, folder);
    case _FolderAction.delete:
      final deleted = await deleteFolder(context, ref, folder);
      if (deleted) onDeleted?.call();
  }
}

enum _FolderAction { rename, move, delete }

/// Creates a Folder inside [parentId] — which is the root when the user is at
/// the top of their library, because "at the library root" means "in the root
/// Folder".
Future<void> createFolderIn(
  BuildContext context,
  WidgetRef ref, {
  required String parentId,
}) async {
  final repository = ref.read(folderRepoProvider);
  final name = await promptForFolderName(
    context,
    title: 'New folder',
    confirmLabel: 'Create',
  );
  if (name == null) return;
  final (_, violation) = await repository.create(name, parentId: parentId);
  if (!context.mounted) return;
  if (violation != null) {
    showLibraryMessage(context, violationMessage(violation));
  }
}

Future<void> renameFolder(
  BuildContext context,
  WidgetRef ref,
  FolderRow folder,
) async {
  final repository = ref.read(folderRepoProvider);
  final name = await promptForFolderName(
    context,
    title: 'Rename folder',
    confirmLabel: 'Rename',
    initial: folder.name,
  );
  if (name == null) return;
  final (_, violation) = await repository.rename(folder.id, name);
  if (!context.mounted) return;
  if (violation != null) {
    showLibraryMessage(context, violationMessage(violation));
  }
}

/// Moves a Folder under another. A refused move — a folder cannot contain
/// itself — is reported in the repository's own words, not hidden by removing
/// the option.
Future<void> moveFolder(
  BuildContext context,
  WidgetRef ref,
  FolderRow folder,
) async {
  final repository = ref.read(folderRepoProvider);
  final target = await pickFolder(
    context,
    title: 'Move “${folder.name}” to',
    currentId: folder.parentId,
  );
  if (target == null || target == folder.parentId) return;
  final violation = await repository.move(folder.id, target);
  if (!context.mounted) return;
  if (violation != null) {
    showLibraryMessage(context, violationMessage(violation));
  }
}

/// Deletes a Folder after saying what happens to what is inside it.
///
/// Returns true when the Folder is gone, so the surface standing on it can
/// leave.
Future<bool> deleteFolder(
  BuildContext context,
  WidgetRef ref,
  FolderRow folder,
) async {
  final repository = ref.read(folderRepoProvider);
  final counts = await countFolderChildren(
    ref.read(libraryDatabaseProvider),
    folder.id,
  );
  final parentId = folder.parentId;
  final parent = parentId == null ? null : await repository.byId(parentId);
  final parentName = parent == null ? 'Library' : folderDisplayName(parent);
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete folder “${folder.name}”?'),
      content: Text(reparentSentence(counts, parentName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete folder'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final (moved, violation) = await repository.deleteWithReparent(folder.id);
  if (!context.mounted) return moved != null;
  if (violation != null) {
    showLibraryMessage(context, violationMessage(violation));
    return false;
  }
  showLibraryMessage(context, reparentedSentence(moved!, parentName));
  return true;
}

/// A folder name, trimmed. Null when the user backed out; never an empty
/// string — an unnamed folder is not a folder.
Future<String?> promptForFolderName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _NameDialog(title: title, confirmLabel: confirmLabel, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('folderNameField'),
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Folder name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
