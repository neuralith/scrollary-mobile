import 'package:flutter/material.dart';

import '../save/save_preflight.dart';
import '../core/config.dart';
import '../ui/palette.dart';
import 'save_scope_sheet.dart';

/// What the user chose when told an entry already exists.
enum PreflightChoice {
  saveNow,
  openExisting,
  saveFollowing,
  redownload,
  retryMissing,
  restartSave,
  repair,
  removeRecord,
  resumeRun,
  discardRunAndRestart,
  cancel,
}

class PreflightDecision {
  const PreflightDecision(this.choice, {this.policy, this.entryLimit});

  final PreflightChoice choice;
  final DuplicatePolicy? policy;
  final int? entryLimit;
}

/// A resolved request: what to save, under what policy, and — unchanged
/// from the sheet the user came from — **how it should be launched**.
class SaveLaunchPlan {
  const SaveLaunchPlan({
    required this.action,
    required this.entryLimit,
    required this.policy,
    required this.range,
  });

  /// The launch the user chose before the preflight interrupted. Carried, not
  /// re-asked: a duplicate is a question about *this entry*, not about
  /// whether the user still wants it now (D58).
  final SaveSheetAction action;

  final int entryLimit;
  final DuplicatePolicy policy;
  final SaveScope range;
}

/// Turn a preflight answer into the request to launch, or null when the
/// answer was not a save at all (open the saved entry, remove the record,
/// resume the existing run, cancel).
///
/// Pure on purpose: "Start Save that became Re-download still starts" is
/// the kind of rule that quietly stops being true inside a 90-line switch.
SaveLaunchPlan? planAfterPreflight({
  required SaveSheetAction action,
  required PreflightChoice choice,
  required int requestedLimit,
  required SaveScope requestedRange,
  DuplicatePolicy? policy,
}) {
  switch (choice) {
    case PreflightChoice.openExisting:
    case PreflightChoice.removeRecord:
    case PreflightChoice.resumeRun:
    case PreflightChoice.cancel:
      return null;

    case PreflightChoice.saveFollowing:
    case PreflightChoice.saveNow:
    case PreflightChoice.discardRunAndRestart:
      return SaveLaunchPlan(
        action: action,
        entryLimit: requestedLimit,
        policy: policy ?? DuplicatePolicy.skipComplete,
        range: requestedRange,
      );

    case PreflightChoice.redownload:
    case PreflightChoice.retryMissing:
    case PreflightChoice.restartSave:
    case PreflightChoice.repair:
      // A repair of *this* entry is one entry, even when the sheet was
      // opened from a larger request: the user asked for this entry, not a
      // run starting at it.
      return SaveLaunchPlan(
        action: action,
        entryLimit: 1,
        policy: policy ?? DuplicatePolicy.skipComplete,
        range: SaveScope.currentPageOnly,
      );
  }
}

/// Explains what already exists and asks what to do about it.
///
/// The whole point of this screen: the app used to log "already saved" and
/// silently do nothing, which looks identical to a broken save. Anything
/// that changes or skips the user's content should say so and offer a choice.
Future<PreflightDecision?> showSavePreflightSheet({
  required BuildContext context,
  required EntryPreflight preflight,
  required int requestedCount,
  RangePreflight? range,
}) {
  return showModalBottomSheet<PreflightDecision>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _PreflightBody(
          preflight: preflight,
          requestedCount: requestedCount,
          range: range,
        ),
      ),
    ),
  );
}

class _PreflightBody extends StatelessWidget {
  const _PreflightBody({
    required this.preflight,
    required this.requestedCount,
    this.range,
  });

  final EntryPreflight preflight;
  final int requestedCount;
  final RangePreflight? range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body) = switch (preflight.state) {
      EntryLocalState.complete => (
        'This entry is already available offline.',
        'You can open it, save what comes after it, or download it again.',
      ),
      EntryLocalState.partial => (
        'This entry was saved incompletely.',
        'Some images are missing. You can retry just those, start the save '
            'over, or read what was saved.',
      ),
      EntryLocalState.failed => (
        'This entry failed to save.',
        'Nothing usable was stored last time. Saving again will start from '
            'scratch.',
      ),
      EntryLocalState.filesMissing => (
        'The saved files for this entry are missing.',
        'It is listed in your library, but the images are not on disk, so it '
            'cannot be read offline.',
      ),
      EntryLocalState.inActiveRun => (
        'Another save already covers this entry.',
        'Running two saves over the same entry at once would have them '
            'fight over the same files.',
      ),
      EntryLocalState.none => ('Start save', ''),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 12)),
        ],
        if (preflight.entry != null) ...[
          const SizedBox(height: 8),
          Text(
            '${preflight.entry!.sourceMarker ?? preflight.entry!.title}  ·  '
            '${preflight.entry!.storedAssetCount}/'
            '${preflight.entry!.detectedAssetCount} images',
            style: TextStyle(
              fontSize: 11,
              color: AppPalette.of(context).inkFaint,
            ),
          ),
        ],

        if (range != null && range!.hasExisting) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in range!.lines)
                  Text(line, style: const TextStyle(fontSize: 12)),
                if (range!.knownCount < requestedCount)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Only ${range!.knownCount} of $requestedCount could be '
                      'checked in advance; the rest are decided as they are '
                      'reached.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.of(context).inkFaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),
        ..._actionsFor(context),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(
              context,
              const PreflightDecision(PreflightChoice.cancel),
            ),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  List<Widget> _actionsFor(BuildContext context) {
    void choose(
      PreflightChoice choice, {
      DuplicatePolicy? policy,
      int? limit,
    }) => Navigator.pop(
      context,
      PreflightDecision(choice, policy: policy, entryLimit: limit),
    );

    switch (preflight.state) {
      case EntryLocalState.complete:
        return [
          _Action(
            icon: Icons.menu_book,
            label: 'Open saved entry',
            onTap: () => choose(PreflightChoice.openExisting),
          ),
          _Action(
            icon: Icons.skip_next,
            label: 'Save following entries',
            // The stated rule, shown rather than implied: the count is new
            // save attempts, so an already-saved starting entry does not
            // eat one of them.
            detail: requestedCount == 1
                ? 'Attempts the next entry after this one.'
                : 'Attempts the next $requestedCount entries after this one, '
                      'skipping ones already saved.',
            primary: true,
            onTap: () => choose(
              PreflightChoice.saveFollowing,
              policy: DuplicatePolicy.skipComplete,
            ),
          ),
          _Action(
            icon: Icons.refresh,
            label: 'Re-download this entry',
            detail:
                'Keeps the current copy until the new one succeeds. '
                'Reading progress is preserved.',
            onTap: () => choose(
              PreflightChoice.redownload,
              policy: DuplicatePolicy.replaceAll,
            ),
          ),
          if (range != null && range!.hasExisting)
            _Action(
              icon: Icons.replay_circle_filled,
              label: 'Save all in range again',
              onTap: () => choose(
                PreflightChoice.saveFollowing,
                policy: DuplicatePolicy.replaceAll,
              ),
            ),
        ];

      case EntryLocalState.partial:
        return [
          _Action(
            icon: Icons.download_done,
            label: 'Retry missing files',
            detail: 'Keeps what was stored and re-attempts the rest.',
            primary: true,
            onTap: () => choose(
              PreflightChoice.retryMissing,
              policy: DuplicatePolicy.retryPartial,
            ),
          ),
          _Action(
            icon: Icons.restart_alt,
            label: 'Restart entry save',
            detail: 'Clean replacement. Reading progress is kept.',
            onTap: () => choose(
              PreflightChoice.restartSave,
              policy: DuplicatePolicy.replaceAll,
            ),
          ),
          _Action(
            icon: Icons.menu_book,
            label: 'Open partial entry',
            onTap: () => choose(PreflightChoice.openExisting),
          ),
        ];

      case EntryLocalState.failed:
        return [
          _Action(
            icon: Icons.restart_alt,
            label: 'Save this entry',
            primary: true,
            onTap: () => choose(
              PreflightChoice.restartSave,
              policy: DuplicatePolicy.retryPartial,
            ),
          ),
        ];

      case EntryLocalState.filesMissing:
        return [
          _Action(
            icon: Icons.build,
            label: 'Repair save',
            detail: 'Download the entry again into the same library entry.',
            primary: true,
            onTap: () => choose(
              PreflightChoice.repair,
              policy: DuplicatePolicy.replaceAll,
            ),
          ),
          _Action(
            icon: Icons.delete_outline,
            label: 'Remove broken local record',
            detail: 'Deletes the library entry. Reading history goes with it.',
            danger: true,
            onTap: () async {
              final ok = await _confirmDestructive(context);
              if (ok && context.mounted) choose(PreflightChoice.removeRecord);
            },
          ),
        ];

      case EntryLocalState.inActiveRun:
        return [
          _Action(
            icon: Icons.play_arrow,
            label: 'Resume existing save',
            primary: true,
            onTap: () => choose(PreflightChoice.resumeRun),
          ),
          _Action(
            icon: Icons.restart_alt,
            label: 'Discard it and start over',
            danger: true,
            onTap: () => choose(PreflightChoice.discardRunAndRestart),
          ),
        ];

      case EntryLocalState.none:
        return [
          _Action(
            icon: Icons.download,
            label: 'Save',
            primary: true,
            onTap: () => choose(PreflightChoice.saveNow),
          ),
        ];
    }
  }

  Future<bool> _confirmDestructive(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this entry record?'),
        content: const Text(
          'The library entry and its reading history are deleted. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.primary = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: primary
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.of(context).inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
