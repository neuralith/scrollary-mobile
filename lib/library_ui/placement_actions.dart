/// Placing an unplaced Entry (roadmap D6).
///
/// The NEEDS PLACEMENT section says these Entries are in the library and
/// readable, and that where they sit in the sequence is not known. This file is
/// how a user answers that, and it answers it **only** with a number they
/// typed:
///
/// * The position this device already knows to be taken is shown while the
///   number is being typed, naming the Entry holding it, before anything is
///   committed anywhere.
/// * A refusal from the other side is drawn the same way — the position, the
///   Entry holding it, and *nothing was changed*. It is never auto-adjusted to
///   the next free number: that would put an Entry somewhere no source ever
///   said it was, which is precisely what the unplaced state exists to avoid
///   (V2-D16).
/// * Success is applied from what came back, not from what was asked for.
///
/// The submission itself goes through [placementSubmitProvider]. This lane
/// draws the dialog and applies the answer; where a placement travels belongs
/// to the lane that owns the transport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_violations.dart';
import '../library/entry_presentation.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'folder_models.dart';
import 'library_widgets.dart';
import 'placement_models.dart';
import 'providers.dart';

/// Ask for a position for [view], then submit it.
Future<void> placeEntryInSequence(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final collectionId = view.row.collectionId;
  if (collectionId == null) {
    // A standalone Entry is a first-class library item with no sequence to sit
    // in. Nothing is wrong with it, and nothing here can invent one.
    showLibraryMessage(
      context,
      'This entry is not in a collection, so it has no sequence to sit in.',
    );
    return;
  }

  final db = ref.read(libraryDatabaseProvider);
  final ordinal = await showDialog<double>(
    context: context,
    builder: (dialogContext) => _PlacementDialog(
      label: view.label,
      occupantAt: (value) async {
        final row = await entryAtOrdinal(db, collectionId, value);
        if (row == null || row.id == view.id) return null;
        // Its name, not its position: the sentence beside this already prints
        // the position, and *"taken by 5"* answers nothing.
        return entryOwnName(labels: libraryEntryLabels, title: row.title);
      },
    ),
  );
  if (ordinal == null || !context.mounted) return;

  final outcome = await ref.read(placementSubmitProvider)(
    PlacementRequest(
      entryId: view.id,
      collectionId: collectionId,
      ordinal: ordinal,
    ),
  );
  if (!context.mounted) return;

  switch (outcome.status) {
    case PlacementStatus.applied:
      // What was applied, not what was asked for.
      await _applyLocally(
        context,
        ref,
        collectionId: collectionId,
        entryId: view.id,
        ordinal: outcome.ordinal ?? ordinal,
      );
    case PlacementStatus.conflict:
      final occupant = await _occupantLabel(
        ref,
        entryId: outcome.occupyingEntryId,
        fallback: outcome.occupyingTitle,
      );
      if (!context.mounted) return;
      showLibraryMessage(
        context,
        placementConflictSentence(
          ordinal: outcome.ordinal ?? ordinal,
          occupantLabel: occupant,
        ),
      );
    case PlacementStatus.refused:
      showLibraryMessage(
        context,
        outcome.reason ?? 'That position was refused. Nothing was changed.',
      );
  }
}

/// Write the applied position onto the local row: `unplaced` → `userPlaced`,
/// which is the transition that records *the user chose this*.
///
/// The local write can still refuse — the position may have been taken here
/// while the dialog was open — and that refusal is drawn exactly like the far
/// side's, because from the user's chair they are the same event.
Future<void> _applyLocally(
  BuildContext context,
  WidgetRef ref, {
  required String collectionId,
  required String entryId,
  required double ordinal,
}) async {
  final (_, violation) = await ref
      .read(entryRepoProvider)
      .placeEntry(entryId, ordinal);
  if (!context.mounted) return;
  if (violation == null) {
    showLibraryMessage(context, 'Placed at ${formatOrdinal(ordinal)}.');
    return;
  }
  if (violation != duplicateOrdinal) {
    showLibraryMessage(context, violationMessage(violation));
    return;
  }
  final occupant = await entryAtOrdinal(
    ref.read(libraryDatabaseProvider),
    collectionId,
    ordinal,
  );
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    placementConflictSentence(
      ordinal: ordinal,
      // The Entry's own name, not its position: the sentence already says
      // the position, and answering "taken by 5" would be a tautology.
      occupantLabel: occupant == null
          ? null
          : entryOwnName(labels: libraryEntryLabels, title: occupant.title),
    ),
  );
}

/// What to call the Entry holding a position.
///
/// This device's own label first — it is the name the library holds and the
/// one the user is looking at in the list — and what the far side called it
/// only when the Entry is not here.
Future<String?> _occupantLabel(
  WidgetRef ref, {
  required String? entryId,
  required String? fallback,
}) async {
  if (entryId == null) return fallback;
  final row = await ref.read(entryRepoProvider).byId(entryId);
  return row == null
      ? fallback
      : entryOwnName(labels: libraryEntryLabels, title: row.title);
}

/// The dialog: one number, and the duplicate this device already knows about.
class _PlacementDialog extends StatefulWidget {
  const _PlacementDialog({required this.label, required this.occupantAt});

  final String label;

  /// The Entry already at a position, by label, or null when it is free.
  final Future<String?> Function(double ordinal) occupantAt;

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  final TextEditingController _controller = TextEditingController();

  double? _ordinal;
  String? _occupant;

  /// Which lookup the field is waiting on. A slower answer for a number the
  /// user has already typed past must not overwrite the current one.
  int _lookup = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final value = parseOrdinal(text);
    setState(() {
      _ordinal = value;
      _occupant = null;
    });
    if (value == null) return;
    final token = ++_lookup;
    widget.occupantAt(value).then((occupant) {
      if (!mounted || token != _lookup) return;
      setState(() => _occupant = occupant);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ordinal = _ordinal;
    final occupant = _occupant;
    return AlertDialog(
      title: const Text('Where does this go?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“${widget.label}” is in your library and readable. Its place in '
            'this collection is not known, so nothing is guessed — type the '
            'position its source gives it.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: palette.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('placementOrdinalField'),
            controller: _controller,
            autofocus: true,
            // Decimals are real: sources number half-positions, and a field
            // that could not express one would push the user into renumbering
            // somebody else's sequence.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Position'),
            onChanged: _onChanged,
          ),
          if (ordinal != null && occupant != null) ...[
            const SizedBox(height: 12),
            Text(
              key: const ValueKey('placementDuplicate'),
              placementConflictSentence(
                ordinal: ordinal,
                occupantLabel: occupant,
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: palette.onDangerContainer,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('confirmPlacement'),
          // Unavailable while the position is known to be taken, with the
          // reason printed directly above it. Never a silently adjusted number.
          onPressed: ordinal == null || occupant != null
              ? null
              : () => Navigator.of(context).pop(ordinal),
          child: const Text('Place'),
        ),
      ],
    );
  }
}

/// The affordance on an unplaced row.
///
/// A chip rather than a menu item alone: the NEEDS PLACEMENT section states a
/// question, and the answer belongs on the row that asks it.
class PlacementChip extends StatelessWidget {
  const PlacementChip({super.key, required this.entryId, required this.onTap});

  final String entryId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: ValueKey('placeEntry-$entryId'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: StatusChip(
        icon: Icons.numbers,
        label: 'Set position',
        bg: palette.surfaceHigh,
        fg: palette.inkMuted,
        border: palette.border,
      ),
    );
  }
}
