import 'package:flutter/material.dart';

import '../library/update_checker.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'operation_panel.dart';

/// Status and controls for the running update check, docked under the WebView.
///
/// The same slot, the same chrome and the same log affordance the save run
/// gets ([SavePanel]) — because it is the same promise: while this app drives
/// the Browser, the user can see what it is doing and stop it. A check that
/// navigated the WebView with nothing on screen but a "Save" button was an
/// operation the user could watch but not name, and could not end.
///
/// It is deliberately **not** the save panel with a flag. A check has no
/// entries stored, no images, no scroll position, and nothing to pause, retry
/// or skip: it has pages read, entries found, and a stop. Sharing the widget
/// would mean six controls that do nothing and three counters that read zero.
class UpdateCheckPanel extends StatelessWidget {
  const UpdateCheckPanel({
    super.key,
    required this.checker,
    required this.expanded,
    required this.onToggle,
    required this.onStop,
  });

  final UpdateChecker checker;
  final bool expanded;
  final VoidCallback onToggle;

  /// Ends the check. Wired to the queue so the Activity row and the panel
  /// agree about what happened.
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (!checker.isRunning) return const SizedBox.shrink();

    final waiting = checker.state == UpdateCheckState.needsUserInput;
    final title = checker.activeTitle;

    return OperationPanelFrame(
      children: [
        Row(
          children: [
            OperationChip(
              icon: waiting ? Icons.ads_click : Icons.sync,
              // Never "SAVING": the whole point of this panel is that the
              // user can tell the two operations apart at a glance. Nothing
              // is being downloaded while this is on screen.
              label: waiting ? 'Needs you' : 'Checking',
              background: palette.primaryContainer,
              foreground: palette.onPrimaryContainer,
              border: palette.primaryBorder,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${checker.pagesInspected} page(s) read'
                ' · ${checker.newEntries} new'
                // Counted apart from "new", always: found and gone are
                // opposite facts, and one number for both says neither.
                '${checker.staleRemoved > 0 ? ' · ${checker.staleRemoved} gone' : ''}'
                ' · depth ${checker.forwardDepth}'
                '/${checker.config.maxForwardDepth}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 11.5, color: palette.inkMuted),
              ),
            ),
            OperationLogToggle(expanded: expanded, onToggle: onToggle),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          // What this operation *is*, stated whatever the log happens to say
          // right now. It is the sentence that stops a moving Browser from
          // reading as a download, so it does not get displaced by progress.
          'Checking${title.isEmpty ? '' : ' “$title”'} for new entries — '
          'metadata only, nothing is downloaded.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.35, color: palette.ink),
        ),
        if (checker.message.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            checker.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
          ),
        ],
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            // Indeterminate, and honestly so: a check does not know how many
            // pages it will read until it stops finding new entries. A bar
            // that pretended to a percentage would be inventing one.
            minHeight: 5,
            backgroundColor: palette.border,
            color: palette.primary,
          ),
        ),
        if (expanded && checker.log.isNotEmpty) ...[
          const SizedBox(height: 10),
          OperationLogDrawer(
            lines: checker.log,
            onCopy: () => _copyLog(context, checker),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            OperationPillButton('Stop check', Icons.stop, onStop),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Stops at the next safe point. Entries already found are '
                'kept; nothing saved is affected.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: palette.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _copyLog(BuildContext context, UpdateChecker checker) {
  final header = StringBuffer()
    ..writeln('Scrollary update-check log')
    ..writeln('state: ${checker.state.name}')
    ..writeln('collection: ${checker.activeTitle}')
    ..writeln(
      'pages: ${checker.pagesInspected}  new: ${checker.newEntries}  '
      'depth: ${checker.forwardDepth}/${checker.config.maxForwardDepth}',
    )
    ..write('---');
  return copyOperationLog(
    context,
    header: header.toString(),
    lines: checker.log,
  );
}
