/// Confirming a removal, and saying what happened.
///
/// One rule over all of it: **the caller computes the facts.** This file never
/// guesses at a size, a count or what will be kept — a dialog that estimated
/// its own numbers would be a second, differently-derived answer to a question
/// the storage survey has already answered.
///
/// Three questions live here, and they are asked in different places for
/// different reasons:
///
///  * [showRemovalConfirm] — the Storage screen, about bytes the user came
///    looking to free.
///  * [showEntryCompletionDialog] — the reader, when a forward move leaves an
///    Entry that is *near* the end but not finished (V2-D59).
///  * [showFinishedCleanupDialog] — the reader, once per Collection, for what
///    a finished Entry's downloaded copy should do from then on.
///
/// The last two were removed with the reader's V1 route in `b1be16d`, on the
/// reasoning that a reader opened over an OfflineCopy has no neighbour list.
/// That is true of the screen and not of the **Collection**, which is where
/// neighbours live; `V2ReaderRoute` resolves them, and
/// `lib/reading_v2/forward_transition.dart` is what asks these two again.
library;

import 'package:flutter/material.dart';

import '../reading_v2/finished_cleanup.dart';
import '../reading_v2/forward_transition.dart' show EntryCompletionChoice;
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// One removal confirmation for every scope: a single entry, a selection,
/// a whole collection, or every finished entry. Facts are computed by the
/// caller so this widget never guesses at sizes.
class RemovalSummary {
  const RemovalSummary({
    required this.title,
    required this.body,
    required this.facts,
    this.lockNote,
    this.cta = 'Remove files',
  });

  final String title;
  final String body;

  /// key → value rows ("Entries" → "412", "Space freed" → "~3.4 GB").
  final List<(String, String)> facts;

  /// Entries that will be kept because something is using them.
  final String? lockNote;
  final String cta;
}

Future<bool> showRemovalConfirm({
  required BuildContext context,
  required RemovalSummary summary,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final palette = AppPalette.of(context);
      return AlertDialog(
        icon: Icon(Icons.delete_sweep, size: 26, color: palette.inkMuted),
        title: Text(summary.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.body,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                children: [
                  for (final (k, v) in summary.facts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            k,
                            style: monoStyle(
                              size: 11.5,
                              color: palette.inkMuted,
                            ),
                          ),
                          Text(
                            v,
                            style: monoStyle(size: 11.5, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (summary.lockNote != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock, size: 15, color: palette.warn),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      summary.lockNote!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(summary.cta),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Row _toastRow(AppPalette palette, IconData icon, String text) => Row(
  children: [
    Icon(icon, size: 19, color: palette.toastAccent),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.toastInk),
      ),
    ),
  ],
);

/// The design's dark toast, with an optional Undo.
/// Say what a cleanup did.
///
/// **There is no Undo here, and there deliberately is not one.** Cleanup
/// deletes packages from disk outright — `FileStore.deleteEntryContent` is a
/// recursive delete, not a move to staging — so an Undo action would be a
/// button that cannot do what it says. The honest version of reversibility is
/// the confirmation before it: it names the entries and the space, and it is
/// the same reasoning V2-D33 records for Folder deletion.
void showCleanupToast(
  BuildContext context, {
  required String text,
  IconData icon = Icons.delete_sweep,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final palette = AppPalette.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 4200),
      backgroundColor: palette.toastSurface,
      content: _toastRow(palette, icon, text),
    ),
  );
}

// ─── reading on to the next entry ───────────────────────────────────────────

/// The two outcomes, in the order they are offered.
///
/// Shared by the first-transition question and the Collection menu's sheet, so
/// a rewording can never drift between the place a rule is set and the place it
/// is changed.
const _cleanupRules = <(FinishedCleanupRule, String, String)>[
  (
    FinishedCleanupRule.remove,
    'Remove after finishing',
    'When you read on to the next entry, the finished one\'s downloaded '
        'files are freed on this device. It stays in your library with your '
        'reading history, and you can download it again any time.',
  ),
  (
    FinishedCleanupRule.keep,
    'Keep downloaded',
    'Finished entries stay downloaded on this device until you remove them '
        'yourself.',
  ),
];

/// The label and the sentence under it for one rule. Public so the Collection
/// menu draws the same words this dialog does.
(String, String) finishedCleanupRuleCopy(FinishedCleanupRule rule) {
  for (final option in _cleanupRules) {
    if (option.$1 == rule) return (option.$2, option.$3);
  }
  throw StateError('no copy for $rule');
}

/// The one-time question for a Collection (V2-D59).
///
/// Asked on the first forward move inside a Collection that has no rule yet,
/// and never again unless the rule is cleared from the Collection menu. It is a
/// choice between two named outcomes with an explicit *Save choice* — not a
/// yes/no about the Entry in hand, because what is being saved is a rule for
/// the Collection.
///
/// *Remove after finishing* is preselected, always. The preselection is a
/// constant of this widget: no other Collection, no previous answer and no
/// device-wide setting can reach it, because there is no device-wide setting.
/// Dismissing without saving returns null, which stores nothing and keeps the
/// files.
Future<FinishedCleanupRule?> showFinishedCleanupDialog({
  required BuildContext context,
  required String collectionName,
}) => showDialog<FinishedCleanupRule>(
  context: context,
  builder: (context) => _FinishedCleanupDialog(collectionName: collectionName),
);

class _FinishedCleanupDialog extends StatefulWidget {
  const _FinishedCleanupDialog({required this.collectionName});

  final String collectionName;

  @override
  State<_FinishedCleanupDialog> createState() => _FinishedCleanupDialogState();
}

class _FinishedCleanupDialogState extends State<_FinishedCleanupDialog> {
  /// The preselected answer, fixed by the product model (V2-D59).
  FinishedCleanupRule _choice = FinishedCleanupRule.remove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      key: const ValueKey('finishedCleanupDialog'),
      // Two option rows and their explanations are taller than a short phone
      // in landscape: the content scrolls rather than overflowing.
      scrollable: true,
      icon: Icon(Icons.folder_open, size: 26, color: palette.inkMuted),
      title: const Text('Downloaded entries in this collection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.collectionName.trim().isNotEmpty) ...[
            Text(
              widget.collectionName,
              style: TextStyle(
                fontSize: 12,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.inkStrong,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            "What should happen to a finished entry's downloaded files on this "
            'device after you read on to the next entry?',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
          const SizedBox(height: 13),
          for (final option in _cleanupRules) ...[
            _CleanupRuleOption(
              optionKey: 'finishedCleanup-${option.$1.name}',
              label: option.$2,
              sub: option.$3,
              selected: _choice == option.$1,
              onTap: () => setState(() => _choice = option.$1),
            ),
            const SizedBox(height: 7),
          ],
          const SizedBox(height: 3),
          Text(
            'This applies to this collection on this device. You can change it '
            'later from the collection menu.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: palette.inkFaint,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          key: const ValueKey('saveFinishedCleanup'),
          onPressed: () => Navigator.pop(context, _choice),
          child: const Text('Save choice'),
        ),
      ],
    );
  }
}

/// Asked when the reader moves forward out of an Entry it is *near* the end of
/// but has not finished (`CompletionPolicy.nearEnd`).
///
/// It exists because moving forward is not evidence of finishing. A reader
/// looks ahead, compares two entries, mistaps, or means to come back — so the
/// app asks instead of deciding, and the answer that changes nothing is offered
/// as plainly as the one that does.
///
/// [willRemoveCopy] is what turns this from bookkeeping into a consequence:
/// when the collection already frees a finished entry's files, saying this one
/// is finished is also what frees them, and the question says so *before* the
/// tap rather than in a notice afterwards. When the collection has no rule yet
/// the note is absent, because that question comes next and explains itself.
Future<EntryCompletionChoice?> showEntryCompletionDialog({
  required BuildContext context,
  required String entryName,
  required int percentRead,
  required bool willRemoveCopy,
}) => showDialog<EntryCompletionChoice>(
  context: context,
  builder: (context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      key: const ValueKey('entryCompletionDialog'),
      scrollable: true,
      icon: Icon(Icons.flag_outlined, size: 26, color: palette.inkMuted),
      title: const Text('You have not finished this one'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entryName.trim().isNotEmpty) ...[
            Text(
              entryName,
              style: TextStyle(
                fontSize: 12,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.inkStrong,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            'You are $percentRead% through it. Moving to the next entry does '
            'not finish it — it stays where you left off, and you can come '
            'back to it any time.',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
          if (willRemoveCopy) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.delete_outline, size: 15, color: palette.warn),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    key: const ValueKey('entryCompletionConsequence'),
                    'This collection frees a finished entry\'s downloaded '
                    'files, so marking this one finished also frees its files '
                    'on this device. It stays in your library with your '
                    'reading history.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: palette.warn,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      // Stacked, primary at the top: three labels this long never sit in one
      // row on a phone, and a wrapped row would put the consequential answer
      // wherever it happened to land.
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          key: const ValueKey('entryCompletion-cancel'),
          onPressed: () => Navigator.pop(context, EntryCompletionChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('entryCompletion-continueWithout'),
          onPressed: () =>
              Navigator.pop(context, EntryCompletionChoice.continueWithout),
          child: const Text('Continue without finishing'),
        ),
        FilledButton(
          key: const ValueKey('entryCompletion-complete'),
          onPressed: () =>
              Navigator.pop(context, EntryCompletionChoice.completeAndContinue),
          child: const Text('Mark finished and continue'),
        ),
      ],
    );
  },
);

/// Settings-sheet-shaped radio row, for the two options this dialog offers.
///
/// The Collection menu's sheet draws its own list rows in that sheet's shape;
/// what the two share is the **words**, through [finishedCleanupRuleCopy], so
/// a rewording cannot drift between where a rule is set and where it is
/// changed.
class _CleanupRuleOption extends StatelessWidget {
  const _CleanupRuleOption({
    required this.optionKey,
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String optionKey;
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(optionKey),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? palette.primary : palette.inkMuted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
