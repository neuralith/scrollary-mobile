/// Collection detail: **one** Entry list (roadmap D3).
///
/// There is one list on this screen and there is no way to grow a second one.
/// A downloaded Entry and an Entry this device has never held are the same
/// row, in the same order, with the same actions; availability is a line of
/// metadata on the row (PRODUCT.md §2.3). The screen V1 shipped — a saved list
/// above a "known remote" list — is the thing this file exists to replace.
///
/// **Unplaced Entries** (open question O-B) are shown *in that same list*,
/// last, under their own heading. The alternatives were to hide them in a
/// separate view, where a user would never find them, or to interleave them
/// with the numbered sequence, which would print a position the source never
/// gave. A trailing section says the honest thing — these are in the library,
/// their place in the sequence is not known — and changes no data: it is
/// presentation over `placement`, and swapping it for a different treatment
/// touches this file only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_actions.dart';
import 'collection_models.dart';
import 'library_widgets.dart';
import 'providers.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(collectionViewProvider(collectionId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: collection.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (view) => view == null
              ? Column(
                  children: [
                    LibraryHeader(
                      title: 'Collection',
                      onBack: _backOf(context),
                    ),
                    const LibraryEmptyState(
                      icon: Icons.help_outline,
                      title: 'This collection is no longer in your library',
                      body:
                          'It may have been removed on another screen or '
                          'another device.',
                    ),
                  ],
                )
              : _CollectionDetail(view: view),
        ),
      ),
    );
  }
}

class _CollectionDetail extends ConsumerWidget {
  const _CollectionDetail({required this.view});

  final CollectionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        LibraryHeader(
          title: view.name,
          onBack: _backOf(context),
          actions: [
            HeaderIconButton(
              icon: Icons.more_horiz,
              tooltip: 'Collection actions',
              onPressed: () => showCollectionMenu(context, ref, view),
            ),
          ],
        ),
        Expanded(
          // The one list. Sections inside it are headings, not lists.
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                child: Row(
                  children: [
                    Text(
                      view.extentLine,
                      style: monoStyle(color: palette.inkFaint),
                    ),
                    if (view.archived) ...[
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
              ),
              if (view.archived)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Scrollary is not keeping this collection current. '
                    'Nothing was removed, and following it again restores '
                    'that.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              if (view.total == 0)
                const LibraryEmptyState(
                  icon: Icons.article_outlined,
                  title: 'Nothing in this collection yet',
                  body:
                      'Entries appear as Scrollary recognises them while '
                      'you read. They stay here whether or not this device '
                      'holds a copy.',
                )
              else ...[
                SectionLabel(
                  '${libraryEntryLabels.Many.toUpperCase()} · '
                  '${view.entries.length}',
                ),
                const Divider(height: 1),
                for (final entry in view.entries) ...[
                  _entryRow(context, ref, entry),
                  const Divider(height: 1),
                ],
              ],
              if (view.needsPlacement.isNotEmpty) ...[
                SectionLabel('NEEDS PLACEMENT · ${view.needsPlacement.length}'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'In your library, and readable. Where they sit in this '
                    'collection is not known, so they are listed here rather '
                    'than guessed into the order above.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
                const Divider(height: 1),
                for (final entry in view.needsPlacement) ...[
                  _entryRow(context, ref, entry),
                  const Divider(height: 1),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One Entry row, drawn identically wherever it sits in the list.
///
/// The tap opens the same menu the trailing control does. Reading happens from
/// a downloaded copy, and that lane is not built yet — so the row offers what
/// can honestly be done with an Entry today rather than a tap that goes
/// nowhere.
Widget _entryRow(BuildContext context, WidgetRef ref, EntryRowView entry) =>
    EntryRowTile(
      view: entry,
      onTap: () => showEntryMenu(context, ref, entry),
      onMenu: () => showEntryMenu(context, ref, entry),
    );

VoidCallback? _backOf(BuildContext context) =>
    Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null;
