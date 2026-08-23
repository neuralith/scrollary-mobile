/// The Library (roadmap D1) — the app's home screen.
///
/// One page: what to pick up again, then everything in the library. The
/// Collections and standalone Entries at the root are listed directly, and
/// each Folder is a **section on the same page** — collapsible, never a screen
/// of its own — so a Folder organises the library without hiding any of it
/// (V2-D43). The schema is hierarchical either way; a Folder inside a Folder
/// is a section inside a section.
///
/// The header carries the app-level doors: Activity and Settings. Making a
/// Folder is an organisation action and sits beside the MY LIBRARY heading,
/// not in the app header.
///
/// Nothing here asks whether a Collection or an Entry has been downloaded. An
/// item is on the shelf because it is in the library (PRODUCT.md §1.2), and
/// there is no code path in this file that could make availability decide
/// otherwise.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show LeaveBrowserGuard;
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'collection_actions.dart';
import 'collection_models.dart';
import 'continue_reading_strip.dart';
import 'collection_screen.dart';
import 'entry_offline.dart';
import 'folder_actions.dart';
import 'folder_models.dart';
import 'library_widgets.dart';
import 'providers.dart';
import 'shelf_models.dart';

/// The Library page, standing on the root Folder.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // The root is never deleted (I5), so a null here is a database
          // that has not minted one yet — the same picture as loading.
          data: (view) => view == null
              ? const Center(child: CircularProgressIndicator())
              : _LibraryBody(view: view),
        ),
      ),
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.view});

  final ShelfView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumable = ref.watch(continueReadingProvider).value ?? const [];
    final palette = AppPalette.of(context);
    final itemCount = view.collectionCountDeep + view.entryCountDeep;
    return Column(
      children: [
        LibraryHeader(
          title: 'Library',
          actions: [
            const _ActivityButton(),
            HeaderIconButton(
              key: const ValueKey('libraryAction-settings'),
              icon: Icons.settings,
              tooltip: 'Settings',
              onPressed: () => LeaveBrowserGuard.push(context, '/settings'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const ContinueReadingStrip(),
              // A library with nothing in progress says so quietly, in the
              // same place the strip would be. An empty library says nothing
              // here: its own empty state below already covers it.
              if (resumable.isEmpty && !view.isEmpty)
                const _NothingInProgress(),
              // The heading and its one action stand even over an empty
              // library: a Folder can be made before anything is in it.
              SectionLabel(
                'MY LIBRARY · $itemCount',
                trailing: IconButton(
                  key: const ValueKey('libraryAction-newFolder'),
                  tooltip: 'New folder',
                  icon: const Icon(Icons.create_new_folder_outlined, size: 22),
                  color: palette.inkMuted,
                  // A finger-sized target, whatever density the theme sets.
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  // The one Folder creation flow, named for the root: a
                  // Folder made here stands at the top of the library.
                  onPressed: () =>
                      createFolderIn(context, ref, parentId: view.folder.id),
                ),
              ),
              if (view.isEmpty)
                const LibraryEmptyState(
                  icon: Icons.local_library_outlined,
                  title: 'Your library is empty',
                  body:
                      'What you read is added here as Scrollary '
                      'recognises it. An entry is in your library '
                      'because you want to read it — not because this '
                      'device has downloaded it.',
                )
              else ...[
                const Divider(height: 1),
                ..._contentsOf(context, ref, view, depth: 0),
                for (final folder in view.folders)
                  _FolderSection(view: folder, depth: 0),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The Collections and standalone Entries directly in [view] — not its
/// Folders, which the caller draws as sections.
List<Widget> _contentsOf(
  BuildContext context,
  WidgetRef ref,
  ShelfView view, {
  required int depth,
}) => [
  for (final collection in view.collections) ...[
    _CollectionRow(collection: collection, depth: depth),
    const Divider(height: 1),
  ],
  if (view.entries.isNotEmpty) ...[
    SectionLabel(
      '${libraryEntryLabels.Many.toUpperCase()} · ${view.entries.length}',
      padding: EdgeInsets.fromLTRB(20 + _indent(depth), 14, 20, 6),
    ),
    const Divider(height: 1),
    for (final entry in view.entries) ...[
      Padding(
        padding: EdgeInsets.only(left: _indent(depth)),
        child: EntryRowTile(
          view: entry,
          // The same menu from either control: reading opens from a
          // downloaded copy, and that lane is not built yet.
          onTap: () => showEntryMenu(context, ref, entry),
          onMenu: () => showEntryMenu(context, ref, entry),
          // A standalone Entry is downloaded the same way any other is, so
          // it says so in the same place.
          badges: [
            ?entryQueueChip(
              context,
              ref.watch(entrySaveTaskProvider(entry.id)),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  ],
];

/// How far a Folder's contents sit in from the page edge. Capped: past three
/// levels the indent would say more about the user's tidiness than the page
/// has width for.
double _indent(int depth) => 16.0 * depth.clamp(0, 3);

/// The door to Activity, with a dot while the queue has something to say —
/// work waiting or running, or a failure still listed there. The dot is a
/// pointer, not a count: the count lives on the operation indicator.
class _ActivityButton extends ConsumerWidget {
  const _ActivityButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(saveTasksByEntryProvider).value?.values;
    final outstanding =
        tasks?.any((t) => !t.isTerminal || t.state == SaveTaskState.failed) ??
        false;
    final palette = AppPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        HeaderIconButton(
          key: const ValueKey('libraryAction-activity'),
          icon: Icons.playlist_add_check,
          tooltip: 'Activity',
          onPressed: () => LeaveBrowserGuard.push(context, '/activity'),
        ),
        if (outstanding)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('activityDot'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NothingInProgress extends StatelessWidget {
  const _NothingInProgress();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      key: const ValueKey('continueReadingEmpty'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        'Nothing in progress — entries you start reading show up here.',
        style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
      ),
    );
  }
}

/// One Folder as a section of the Library page: a header that expands and
/// collapses it, then its contents drawn in place. A Folder inside it is a
/// section one step further in.
class _FolderSection extends ConsumerWidget {
  const _FolderSection({required this.view, required this.depth});

  final ShelfView view;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(
      collapsedFoldersProvider.select((ids) => ids.contains(view.id)),
    );
    final palette = AppPalette.of(context);
    final count = view.collectionCountDeep + view.entryCountDeep;
    final summary = count == 0
        ? 'Empty'
        : _join([
            if (view.collectionCountDeep > 0)
              '${view.collectionCountDeep} '
                  '${view.collectionCountDeep == 1 ? 'collection' : 'collections'}',
            if (view.entryCountDeep > 0)
              libraryEntryLabels.count(view.entryCountDeep),
          ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('folderSection-${view.id}'),
          onTap: () =>
              ref.read(collapsedFoldersProvider.notifier).toggle(view.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12 + _indent(depth), 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  key: ValueKey(
                    'folderChevron-${view.id}-'
                    '${collapsed ? 'collapsed' : 'expanded'}',
                  ),
                  size: 20,
                  color: palette.inkFaint,
                ),
                const SizedBox(width: 6),
                Icon(Icons.folder, size: 20, color: palette.inkMuted),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderDisplayName(view.folder),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontVariations: wght(600),
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(summary, style: monoStyle(color: palette.inkFaint)),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('folderMenu-${view.id}'),
                  tooltip: 'Folder actions',
                  icon: const Icon(Icons.more_vert, size: 20),
                  color: palette.inkFaint,
                  onPressed: () => showFolderMenu(context, ref, view.folder),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (!collapsed) ...[
          if (view.isEmpty)
            Padding(
              key: ValueKey('folderEmpty-${view.id}'),
              padding: EdgeInsets.fromLTRB(20 + _indent(depth + 1), 10, 20, 12),
              child: Text(
                'Nothing in this folder yet. Move a collection here from '
                'its menu.',
                style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
              ),
            )
          else ...[
            ..._contentsOf(context, ref, view, depth: depth + 1),
            for (final child in view.folders)
              _FolderSection(view: child, depth: depth + 1),
          ],
        ],
      ],
    );
  }
}

String _join(List<String> parts) => parts.join(' · ');

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection, required this.depth});

  final ShelfCollectionView collection;
  final int depth;

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
        padding: EdgeInsets.fromLTRB(16 + _indent(depth), 13, 16, 14),
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
