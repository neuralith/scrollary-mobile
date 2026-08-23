/// The chrome the V2 library surfaces share: a screen header, an empty state
/// and the Entry row.
///
/// One definition of each, because the alternative is what a UI looks like
/// when three screens each grow their own: a different header height per
/// page, and an Entry that reads as three different things depending on where
/// it is drawn. The Entry row in particular is shared deliberately — a
/// standalone Entry on the shelf and an Entry inside a Collection are the same
/// object and must look it.
library;

import 'package:flutter/material.dart';

import '../domain/reading_state.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'collection_models.dart';

/// A screen header: an optional back action, a serif title, and actions that
/// are all [HeaderIconButton] — one height, one glyph size, one ink.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 8, 10, 12, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null)
          HeaderIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: onBack!,
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: onBack == null ? 0 : 8),
            child: Text(
              title,
              style: serifStyle(size: 26),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ...actions,
      ],
    ),
  );
}

/// An empty surface that says what it is and what fills it. Never a spinner,
/// never a blank page: "nothing here" and "still loading" are different
/// answers.
class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: palette.inkFaint),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One Entry, wherever it appears.
///
/// Two facts, two vocabularies, never mixed: **read state owns the check**,
/// and availability is a quiet line of metadata that decides nothing. A row
/// with no copy on this device is an ordinary row — same size, same ink, same
/// actions.
class EntryRowTile extends StatelessWidget {
  const EntryRowTile({
    super.key,
    required this.view,
    required this.onTap,
    required this.onMenu,
    this.badges = const <Widget>[],
  });

  final EntryRowView view;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  /// Anything else true of this row *right now* — a queued download, a
  /// position it is waiting for — on a line of its own.
  ///
  /// A second line rather than more items on the metadata line: three signals
  /// beside each other overflow a narrow screen, and the first thing to be
  /// clipped would be whichever one arrived last. Empty by default, and an
  /// empty list draws nothing at all.
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: ValueKey('entryRow-${view.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      size: 13.5,
                      weight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        view.statusLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.inkMuted,
                        ),
                      ),
                      if (view.availableOffline) ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: palette.inkDisabled,
                          ),
                        ),
                        Icon(
                          Icons.download_for_offline,
                          size: 13,
                          color: palette.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'On this device',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: palette.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: badges,
                    ),
                  ],
                ],
              ),
            ),
            // How far through, drawn once and only when there is something to
            // say. A completed Entry is a filled ring with a check — the same
            // mark the row carried before, now the full state of a quantity
            // rather than the only value of it — and an untouched one gets no
            // indicator at all rather than an empty circle.
            if (view.hasProgress)
              Padding(
                key: ValueKey('entryProgress-${view.id}'),
                padding: const EdgeInsets.only(right: 2),
                child: EntryProgressRing(
                  fraction: view.readFraction,
                  completed: view.status == ReadStatus.completed,
                ),
              ),
            IconButton(
              key: ValueKey('entryMenu-${view.id}'),
              tooltip: 'Entry actions',
              icon: const Icon(Icons.more_vert, size: 20),
              color: palette.inkFaint,
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// One transient line about what just happened, for the surfaces that have a
/// [ScaffoldMessenger] over them. Silent where there is none rather than
/// throwing: a message is never the point of an action.
void showLibraryMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
