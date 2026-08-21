/// The Sources section on the Collection screen, and the preference switch
/// (roadmap D4).
///
/// Every Source of the Collection is drawn, in the order they were first seen,
/// whatever state it is in. **A dead site is stated dead and a moved one names
/// where it went** — hiding either would leave a user with a Collection whose
/// history had been quietly edited, and V2-D14 keeps that history in the same
/// row rather than in a table nobody reads.
///
/// The preference switch is offered only for a Source that can still be read
/// from. A control that does not apply is absent, not disabled — the same
/// pattern the root Folder's missing actions use — and the row's own sentence
/// already says why.
///
/// Nothing on this surface says Scrollary will check, fetch, follow or watch a
/// site. Source traversal is content-affecting automation that stays explicit
/// and user-started, and it is not built here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/source.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'library_widgets.dart';
import 'providers.dart';
import 'source_models.dart';

/// The section, drawn inside the Collection screen's one list.
///
/// Absent when the Collection has no Sources: a Collection assembled by hand
/// has none, and an empty heading would invent a state the model does not have.
class CollectionSourcesSection extends ConsumerWidget {
  const CollectionSourcesSection({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sources = ref.watch(collectionSourcesProvider(collectionId));
    return sources.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Text(
          'The sources of this collection could not be read.',
          style: TextStyle(fontSize: 12, color: palette.inkMuted),
        ),
      ),
      data: (views) => views.isEmpty
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('SOURCES · ${views.length}'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    kSourcesSectionNote,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
                const Divider(height: 1),
                for (final view in views) ...[
                  _SourceRow(collectionId: collectionId, view: view),
                  const Divider(height: 1),
                ],
              ],
            ),
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.collectionId, required this.view});

  final String collectionId;
  final SourceView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final look = _lifecycleLook(view, palette);
    return InkWell(
      key: ValueKey('sourceRow-${view.id}'),
      onTap: () => showSourceMenu(context, ref, collectionId, view),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    view.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      size: 13.5,
                      weight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (view.preferred) ...[
                  const SizedBox(width: 8),
                  StatusChip(
                    icon: Icons.star,
                    label: 'Preferred',
                    bg: palette.primaryContainer,
                    fg: palette.onPrimaryContainer,
                    border: palette.primaryBorder,
                  ),
                ],
                const SizedBox(width: 6),
                StatusChip(
                  icon: look.icon,
                  label: view.lifecycleLabel,
                  bg: look.bg,
                  fg: look.fg,
                  border: look.border,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (view.languageTag.isNotEmpty) ...[
                  Text(
                    view.languageTag,
                    style: monoStyle(color: palette.inkFaint),
                  ),
                  Text(' · ', style: monoStyle(color: palette.inkDisabled)),
                ],
                Expanded(
                  child: Text(
                    view.lifecycleSentence,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What one Source can be asked to do: be preferred, or stop being.
///
/// Deliberately short. Removing a Source is a library removal that takes its
/// Locations with it and belongs with the other removals, not behind a tap on
/// a metadata row.
Future<void> showSourceMenu(
  BuildContext context,
  WidgetRef ref,
  String collectionId,
  SourceView view,
) async {
  final action = await showModalBottomSheet<_SourceAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              view.host,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: serifStyle(size: 20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              view.lifecycleSentence,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppPalette.of(sheetContext).inkMuted,
              ),
            ),
          ),
          if (view.preferred)
            ListTile(
              key: const ValueKey('sourceClearPreferred'),
              leading: const Icon(Icons.star_border),
              title: const Text('Clear preferred source'),
              subtitle: const Text(
                'Leaves this collection with no preference between its sites.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_SourceAction.clear),
            )
          // Absent for a site that cannot be read from: preferring one would
          // be a preference the app could not honour.
          else if (view.readable)
            ListTile(
              key: const ValueKey('sourcePrefer'),
              leading: const Icon(Icons.star_outline),
              title: const Text('Prefer this source'),
              subtitle: const Text(
                'Which site you would rather read this collection on. '
                'Nothing is fetched by choosing it.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_SourceAction.prefer),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  final repository = ref.read(collectionRepoProvider);
  final violation = await repository.setPreferredSource(
    collectionId,
    action == _SourceAction.prefer ? view.id : null,
  );
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    violation != null
        ? sourcePreferenceMessage(violation)
        : action == _SourceAction.prefer
        ? 'Preferred source set.'
        : 'No preferred source now.',
  );
}

enum _SourceAction { prefer, clear }

/// The chip one lifecycle wears.
///
/// A dead or moved site is not an error — it is what happened to somebody
/// else's website — so neither borrows the danger ink that means *this app
/// failed*.
({IconData icon, Color bg, Color fg, Color border}) _lifecycleLook(
  SourceView view,
  AppPalette palette,
) => switch (view.lifecycle) {
  SourceLifecycle.active => (
    icon: Icons.public,
    bg: palette.primaryContainer,
    fg: palette.onPrimaryContainer,
    border: palette.primaryBorder,
  ),
  SourceLifecycle.dormant => (
    icon: Icons.hourglass_empty,
    bg: palette.surfaceHigh,
    fg: palette.inkMuted,
    border: palette.border,
  ),
  SourceLifecycle.dead => (
    icon: Icons.link_off,
    bg: palette.warnContainer,
    fg: palette.onWarnContainer,
    border: palette.warnBorder,
  ),
  SourceLifecycle.resolvedInto => (
    icon: Icons.arrow_forward,
    bg: palette.surfaceHigh,
    fg: palette.inkMuted,
    border: palette.border,
  ),
};
