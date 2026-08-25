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

/// The floor a list row keeps, whatever its content comes to.
///
/// The trailing [IconButton] is 48pt and would supply a floor by accident;
/// this says one on purpose, so a later tightening of that control cannot
/// silently collapse the list into a stack of hairlines.
const double kEntryRowMinHeight = 56;

/// The trailing state glyphs' size. One step under [EntryProgressRing]'s 18pt:
/// where a reading has got to is the fact a reader is scanning for, and the
/// device fact beside it is support, not competition.
const double kEntryStateGlyphSize = 16;

/// One Entry, wherever it appears.
///
/// Two facts, two vocabularies, never mixed: **read state owns the check**,
/// and availability is a device fact that decides nothing. A row with no copy
/// on this device is an ordinary row — same size, same ink, same actions.
///
/// **The steady state is drawn, not written** (V2-D63). The row used to spend
/// a whole line on the sentence *Unread · On this device* — prose for two
/// booleans, under an identity that inside a Collection is often a single
/// number. Both moved into the trailing block: an [EntryProgressRing] that is
/// now drawn on every row, and one `download_for_offline` glyph that appears
/// when this device holds bytes. So a row is one content line, or two when the
/// Entry has a name of its own, and every row in a list is the same height.
///
/// The words were not deleted, they are spoken instead. [entryRowSemantics]
/// puts the identity, the read state, the percentage and the availability on
/// one semantics node — more than the visible line ever said, because the line
/// never carried the percentage.
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

  /// Anything true of this row *right now* — a queued download, a position it
  /// is waiting for — on a line of its own, in words.
  ///
  /// The division the trailing block depends on: a state that is **happening**
  /// needs explaining and gets a sentence here; a state that simply **is**
  /// gets a glyph. Without it the right-hand side accumulates one more
  /// unlabelled mark per feature until nothing there means anything.
  ///
  /// Empty by default, and an empty list draws nothing at all.
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: ValueKey('entryRow-${view.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kEntryRowMinHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // One node for the whole of what this row *is*. The
                    // glyphs beside it are drawn and not spoken — they are
                    // this label's last two clauses — while the badges below
                    // keep their own words and their own nodes.
                    Semantics(
                      label: entryRowSemantics(view),
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  view.label,
                                  // One line where there is a subtitle under
                                  // it and two where there is not: a title's
                                  // second line and the subtitle are the same
                                  // slot, and only one of them can have it.
                                  maxLines: view.subtitle == null ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(
                                    size: 13.5,
                                    weight: FontWeight.w500,
                                    color: palette.ink,
                                  ),
                                ),
                                // What the source called this Entry, when it
                                // said anything the position and the work's
                                // name had not already said. Quieter than the
                                // identity above it — the row is a list item,
                                // not a record.
                                if (view.subtitle case final subtitle?) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    key: ValueKey('entrySubtitle-${view.id}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: palette.inkMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ExcludeSemantics(
                            child: _EntryStateGlyphs(view: view),
                          ),
                        ],
                      ),
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
      ),
    );
  }
}

/// What is permanently true of one Entry, drawn: whether this device holds a
/// copy, and how far through it a reading got.
///
/// Fixed-width children in a `min` Row, so nothing here can be clipped by a
/// long title or grow under a large text scale — which is what the line these
/// replaced did, silently, on a narrow screen.
class _EntryStateGlyphs extends StatelessWidget {
  const _EntryStateGlyphs({required this.view});

  final EntryRowView view;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The library's one mark for "this device holds bytes", and the same
        // filled glyph the Browser shows for a page it already has — against
        // the outlined twin that *offers* the download. Never a checkmark:
        // that belongs to read state and to nothing else.
        if (view.availableOffline) ...[
          Icon(
            Icons.download_for_offline,
            key: ValueKey('entryOffline-${view.id}'),
            size: kEntryStateGlyphSize,
            color: palette.primary,
          ),
          const SizedBox(width: 8),
        ],
        // Drawn on every row now, empty ring included. While the row also
        // printed the word *Unread* an empty circle was a second way of
        // saying it and was left off; with the word gone, absence would be
        // indistinguishable from "nothing is known about this one".
        Padding(
          key: ValueKey('entryProgress-${view.id}'),
          padding: const EdgeInsets.only(right: 2),
          child: EntryProgressRing(
            fraction: view.readFraction,
            completed: view.status == ReadStatus.completed,
          ),
        ),
      ],
    );
  }
}

/// What one row says to a screen reader.
///
/// The row draws two facts rather than writing them, so this is where the
/// words went — and there are more of them here than there ever were on
/// screen, because the visible line never carried the percentage.
///
/// Availability is stated **only when it is true**, exactly as it is drawn. A
/// list where every row ends "not on this device" is the download-manager
/// reading of a library, spoken instead of shown; what a device is not holding
/// is answered by *Entry details*, which says it in full.
///
/// The vocabulary is [EntryRowView.statusLabel]'s, not this function's, so the
/// sheet and the row cannot come to call the same state different things.
String entryRowSemantics(EntryRowView view) {
  final percent = (view.readFraction * 100).round();
  final read = percent == 0 || view.status == ReadStatus.completed
      ? view.statusLabel
      : '${view.statusLabel} · $percent%';
  return [
    view.label,
    ?view.subtitle,
    read,
    if (view.availableOffline) 'On this device',
  ].join('. ');
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
