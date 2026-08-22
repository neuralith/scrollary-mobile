/// The Library shelf (roadmap D1).
///
/// One Folder's contents, drawn as one list: the Folders inside it, the
/// Collections in it, and the standalone Entries that live in it directly.
/// Tapping a Folder pushes **this same screen**, scoped to that Folder —
/// flat-first, no tree widget, no expansion state to keep in sync with the
/// database (V2-D21, open question O-A). The schema is hierarchical either
/// way; only the presentation is flat.
///
/// Nothing here asks whether a Collection or an Entry has been downloaded. An
/// item is on the shelf because it is in the library (PRODUCT.md §1.2), and
/// there is no code path in this file that could make availability decide
/// otherwise.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schema.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'collection_actions.dart';
import 'collection_models.dart';
import 'continue_reading_strip.dart';
import 'collection_screen.dart';
import 'entry_offline.dart';
import 'folder_actions.dart';
import 'library_widgets.dart';
import 'providers.dart';
import 'shelf_models.dart';

/// The shelf for [folderId], or for the library root when it is null.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({super.key, this.folderId});

  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = folderId;
    if (id != null) return _Shelf(folderId: id);
    // "At the library root" means "in the root Folder", so the shelf always
    // stands on one.
    return ref
        .watch(rootFolderProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (root) => _Shelf(folderId: root.id),
        );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfProvider(folderId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: shelf.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (view) => view == null
              ? Column(
                  children: [
                    LibraryHeader(title: 'Folder', onBack: _backOf(context)),
                    const LibraryEmptyState(
                      icon: Icons.folder_off_outlined,
                      title: 'This folder is no longer here',
                      body:
                          'Everything that was inside it moved up to the '
                          'folder above.',
                    ),
                  ],
                )
              : _ShelfBody(view: view),
        ),
      ),
    );
  }
}

class _ShelfBody extends ConsumerWidget {
  const _ShelfBody({required this.view});

  final ShelfView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        LibraryHeader(
          title: view.isRoot ? 'Library' : view.folder.name,
          onBack: _backOf(context),
          actions: [
            HeaderIconButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: 'New folder',
              onPressed: () =>
                  createFolderIn(context, ref, parentId: view.folder.id),
            ),
            // Absent for the root, not disabled: the root is not the user's to
            // rename, move or delete, so the control that offers those is not
            // there at all.
            if (!view.isRoot)
              HeaderIconButton(
                icon: Icons.more_horiz,
                tooltip: 'Folder actions',
                onPressed: () => showFolderMenu(
                  context,
                  ref,
                  view.folder,
                  onDeleted: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
          ],
        ),
        if (view.isRoot) const ContinueReadingStrip(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (view.isEmpty)
                view.isRoot
                    ? const LibraryEmptyState(
                        icon: Icons.local_library_outlined,
                        title: 'Your library is empty',
                        body:
                            'What you read is added here as Scrollary '
                            'recognises it. An entry is in your library '
                            'because you want to read it — not because this '
                            'device has downloaded it.',
                      )
                    : const LibraryEmptyState(
                        icon: Icons.folder_open,
                        title: 'This folder is empty',
                        body:
                            'Move a collection or an entry into it, or '
                            'create a folder inside it.',
                      )
              else ...[
                if (view.folders.isNotEmpty) ...[
                  SectionLabel('FOLDERS · ${view.folders.length}'),
                  const Divider(height: 1),
                  for (final folder in view.folders) ...[
                    _FolderRow(folder: folder),
                    const Divider(height: 1),
                  ],
                ],
                if (view.collections.isNotEmpty) ...[
                  SectionLabel('COLLECTIONS · ${view.collections.length}'),
                  const Divider(height: 1),
                  for (final collection in view.collections) ...[
                    _CollectionRow(collection: collection),
                    const Divider(height: 1),
                  ],
                ],
                if (view.entries.isNotEmpty) ...[
                  SectionLabel(
                    '${libraryEntryLabels.Many.toUpperCase()} · '
                    '${view.entries.length}',
                  ),
                  const Divider(height: 1),
                  for (final entry in view.entries) ...[
                    EntryRowTile(
                      view: entry,
                      // The same menu from either control: reading opens from
                      // a downloaded copy, and that lane is not built yet.
                      onTap: () => showEntryMenu(context, ref, entry),
                      onMenu: () => showEntryMenu(context, ref, entry),
                      // A standalone Entry is downloaded the same way any
                      // other is, so it says so in the same place.
                      badges: [
                        ?entryQueueChip(
                          context,
                          ref.watch(entrySaveTaskProvider(entry.id)),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A Folder navigates; it never expands. One screen per level keeps the state
/// in the route stack instead of in a widget that has to be reconciled with
/// the tree.
class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder});

  final FolderRow folder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: ValueKey('folderRow-${folder.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShelfScreen(folderId: folder.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.folder, size: 22, color: palette.inkMuted),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontVariations: wght(600),
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: palette.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection});

  final ShelfCollectionView collection;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: ValueKey('collectionRow-${collection.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collectionId: collection.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MonogramTile(id: collection.id, title: collection.name),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            fontVariations: wght(600),
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      if (collection.archived) ...[
                        const SizedBox(width: 8),
                        StatusChip(
                          icon: Icons.inventory_2,
                          label: 'Archived',
                          bg: palette.surfaceHigh,
                          fg: palette.inkMuted,
                          border: palette.border,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // The reading signal, and only that: how much is in the
                  // library and how much of it is unread. Not how much has
                  // been downloaded.
                  Text(
                    collection.signalLine,
                    style: monoStyle(color: palette.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

VoidCallback? _backOf(BuildContext context) =>
    Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null;
