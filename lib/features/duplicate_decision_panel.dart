import 'package:flutter/material.dart';

import '../save/save_run.dart';
import '../save/save_preflight.dart';
import '../features/library_screen.dart' show formatRelative;
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// Shown in place of the save panel while the running run holds on a
/// entry that already exists locally.
///
/// The run is paused underneath: nothing downloads and nothing navigates
/// until the user answers. Offered actions depend on the entry's state —
/// a complete entry cannot "retry missing files", a partial one can.
class DuplicateDecisionPanel extends StatefulWidget {
  const DuplicateDecisionPanel({
    super.key,
    required this.run,
    required this.request,
  });

  final SaveRunController run;
  final DuplicateRequest request;

  @override
  State<DuplicateDecisionPanel> createState() => _DuplicateDecisionPanelState();
}

class _DuplicateDecisionPanelState extends State<DuplicateDecisionPanel> {
  bool _applyToSession = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final request = widget.request;
    final entry = request.entry;

    // The leading glyph speaks the save-status vocabulary: what state the
    // existing copy is in decides both the icon and its colour.
    final (icon, iconColor) = switch (entry?.saveStatus) {
      'partial' => (Icons.arrow_circle_down, palette.warn),
      'failed' => (Icons.error, palette.danger),
      _ => (Icons.download_for_offline, palette.primary),
    };

    return Material(
      color: palette.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 430),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 24, color: iconColor),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.3,
                            fontVariations: wght(600),
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        if (entry != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${entry.sourceMarker ?? entry.title}'
                            ' · ${entry.storedAssetCount}/${entry.detectedAssetCount} images'
                            ' · saved ${formatRelative(entry.savedAt)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(
                              size: 11.5,
                              color: palette.inkMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Nothing has been overwritten. Choose what the run '
                          'should do.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final action in request.availableActions) ...[
                _ActionCard(action: action, onTap: () => _submit(action)),
                const SizedBox(height: 7),
              ],
              InkWell(
                onTap: () => setState(() => _applyToSession = !_applyToSession),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                  child: Row(
                    children: [
                      Icon(
                        _applyToSession
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 21,
                        color: _applyToSession
                            ? palette.primary
                            : palette.inkMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use this choice for every already-saved entry '
                          'in this run',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: palette.inkStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 35, top: 6),
                child: Text(
                  'Applies to this session only. Nothing is deleted either '
                  'way.',
                  style: TextStyle(fontSize: 11, color: palette.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(DuplicateChoiceAction action) => widget.run.resolveDuplicate(
    DuplicateChoice(
      action,
      // Stop is a one-off by design: "stop" is not a policy.
      applyToSession:
          _applyToSession && action != DuplicateChoiceAction.stopSave,
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.onTap});

  final DuplicateChoiceAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label, sub, highlighted) = switch (action) {
      DuplicateChoiceAction.skip => (
        Icons.skip_next,
        'Skip this entry',
        "Keep what's on the device, move to the next",
        false,
      ),
      DuplicateChoiceAction.redownload => (
        Icons.download,
        'Download again',
        'Replaces the local copy when it finishes',
        true,
      ),
      DuplicateChoiceAction.retryMissing => (
        Icons.download,
        'Fetch only the missing images',
        'Leaves the saved images alone',
        true,
      ),
      DuplicateChoiceAction.restartEntry => (
        Icons.restart_alt,
        'Start this entry over',
        'The earlier attempt found no images',
        true,
      ),
      DuplicateChoiceAction.stopSave => (
        Icons.stop_circle,
        'Stop the run',
        'Keeps everything saved so far',
        false,
      ),
    };

    final palette = AppPalette.of(context);
    return Material(
      color: highlighted ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: highlighted ? palette.primary : palette.inkMuted,
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
                        color: highlighted
                            ? palette.onPrimaryContainer
                            : palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: highlighted
                            ? palette.onPrimaryContainer
                            : palette.inkMuted,
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
