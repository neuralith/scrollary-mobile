import 'package:flutter/material.dart';

import '../save/save_run.dart';
import '../save/save_state.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'operation_panel.dart';

/// Status and controls for the running save run, docked under the WebView.
///
/// Layout follows the design's save panel: phase chip + entry counter +
/// log toggle on one line, a progress bar with mono image/scroll counters
/// under it, a dark log drawer, and a horizontal strip of pill controls.
class SavePanel extends StatelessWidget {
  const SavePanel({
    super.key,
    required this.run,
    required this.expanded,
    required this.onToggle,
  });

  final SaveRunController run;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final p = run.progress;
    if (p.state == SaveState.idle && !expanded) {
      return const SizedBox.shrink();
    }

    final pct = p.detectedImages > 0
        ? (p.storedImages / p.detectedImages).clamp(0.0, 1.0)
        : 0.0;

    return OperationPanelFrame(
      children: [
        Row(
          children: [
            _PhaseChip(state: p.state),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'entry ${p.entryIndex}/${p.requestedEntries}'
                ' · ${p.storedEntries} stored'
                '${p.skippedEntries > 0 ? ' · ${p.skippedEntries} skipped' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 11.5, color: palette.inkMuted),
              ),
            ),
            OperationLogToggle(expanded: expanded, onToggle: onToggle),
          ],
        ),
        if (p.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            p.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: palette.inkStrong),
          ),
        ],
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: p.state == SaveState.scrolling ? null : pct,
            minHeight: 5,
            backgroundColor: palette.border,
            color: run.isPaused ? palette.inkMuted : palette.primary,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${p.storedImages} / ${p.detectedImages} images'
              '${p.failedImages > 0 ? ' · ${p.failedImages} failed' : ''}',
              style: monoStyle(
                color: p.failedImages > 0 ? palette.danger : palette.inkMuted,
              ),
            ),
            Text(
              'scroll ${(p.scrollPercent * 100).round()}%'
              '${p.retryCount > 0 ? ' · retry ${p.retryCount}' : ''}',
              style: monoStyle(color: palette.inkMuted),
            ),
          ],
        ),
        if (p.lastError != null) ...[
          const SizedBox(height: 8),
          OperationErrorNote(message: p.lastError!),
        ],
        if (expanded && run.log.isNotEmpty) ...[
          const SizedBox(height: 10),
          OperationLogDrawer(
            lines: run.log,
            onCopy: () => _copyLog(context, run),
          ),
        ],
        if (run.isRunning) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (run.isPaused)
                  OperationPrimaryButton('Resume', Icons.play_arrow, run.resume)
                else
                  OperationPrimaryButton('Pause', Icons.pause, run.pause),
                const SizedBox(width: 7),
                OperationPillButton('Stop', Icons.stop, run.stop),
                const SizedBox(width: 7),
                OperationPillButton(
                  'Retry',
                  Icons.refresh,
                  run.retryCurrentEntry,
                ),
                const SizedBox(width: 7),
                OperationPillButton(
                  'Skip',
                  Icons.skip_next,
                  run.skipCurrentEntry,
                ),
                const SizedBox(width: 7),
                OperationPillButton(
                  'Pick reader',
                  Icons.ads_click,
                  run.requestReaderAreaSelection,
                ),
                const SizedBox(width: 7),
                OperationPillButton(
                  'Pick next',
                  Icons.low_priority,
                  run.requestNextLinkSelection,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// What a finished run did, for the page it happened on.
///
/// Deliberately a *result*, not a state (D59): it is dismissible, it never
/// disables anything, and it goes away the moment the Browser shows another
/// page. The durable copy of this outcome is the Activity row.
class SaveResultBanner extends StatelessWidget {
  const SaveResultBanner({
    super.key,
    required this.result,
    required this.onDismiss,
    required this.onViewActivity,
  });

  final SaveRunRecord result;
  final VoidCallback onDismiss;
  final VoidCallback onViewActivity;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ok = result.succeeded;
    final (bg, border, ink, icon) = ok
        ? (
            palette.primaryContainer,
            palette.primaryBorder,
            palette.onPrimaryContainer,
            Icons.download_for_offline,
          )
        : result.state == SaveState.cancelled
        ? (
            palette.surfaceHigh,
            palette.borderInset,
            palette.inkMuted,
            Icons.do_not_disturb_on,
          )
        : (
            palette.dangerContainer,
            palette.dangerBorder,
            palette.onDangerContainer,
            Icons.error,
          );

    return Container(
      key: const ValueKey('saveResultBanner'),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (result.state) {
                    SaveState.complete => 'Save finished',
                    SaveState.partial => 'Saved, with gaps',
                    SaveState.cancelled => 'Save stopped',
                    _ => 'Save failed',
                  },
                  style: TextStyle(
                    fontSize: 13,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.error ??
                      (result.message.isEmpty
                          ? '${result.storedEntries} entry(s) saved'
                          : result.message),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: ink),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onViewActivity,
            child: const Text('Activity', style: TextStyle(fontSize: 12.5)),
          ),
          IconButton(
            key: const ValueKey('saveResultDismiss'),
            tooltip: 'Dismiss',
            iconSize: 18,
            color: ink,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Copy the whole log, plus the context needed to make sense of it later.
///
/// Redacted the same way the log itself is: cookies and tokens never reach it,
/// so this is safe to paste into an issue. That property is what a future
/// "Report site" button would depend on.
Future<void> _copyLog(BuildContext context, SaveRunController run) async {
  final p = run.progress;
  final buffer = StringBuffer()
    ..writeln('Scrollary save log')
    ..writeln('state: ${p.state.name}  (${p.state.label})')
    ..writeln('url: ${p.currentUrl}')
    ..writeln(
      'entry: ${p.entryIndex}/${p.requestedEntries}  '
      'stored: ${p.storedEntries}',
    )
    ..writeln(
      'images: ${p.storedImages}/${p.detectedImages}  '
      'failed: ${p.failedImages}  retries: ${p.retryCount}',
    );
  if (p.lastError != null) buffer.writeln('error: ${p.lastError}');
  buffer.write('---');

  await copyOperationLog(context, header: buffer.toString(), lines: run.log);
}

/// The run-phase chip: icon + uppercase mono label. Terminal states carry
/// their own colours so "SAVED" and "FAILED" cannot be confused at a glance.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.state});
  final SaveState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Three vocabularies, and only three: neutral for "not running", accent
    // for "working", and the warn/danger containers for the two outcomes that
    // need to be told apart at a glance.
    final neutral = (palette.surfaceHigh, palette.inkMuted, palette.border);
    final accent = (
      palette.primaryContainer,
      palette.onPrimaryContainer,
      palette.primaryBorder,
    );
    final (icon, bg, fg, bd) = switch (state) {
      SaveState.paused => (
        Icons.pause_circle,
        neutral.$1,
        neutral.$2,
        neutral.$3,
      ),
      SaveState.complete => (
        Icons.download_for_offline,
        accent.$1,
        accent.$2,
        accent.$3,
      ),
      SaveState.partial => (
        Icons.arrow_circle_down,
        palette.warnContainer,
        palette.onWarnContainer,
        palette.warnBorder,
      ),
      SaveState.failed => (
        Icons.error,
        palette.dangerContainer,
        palette.onDangerContainer,
        palette.dangerBorder,
      ),
      SaveState.cancelled => (
        Icons.do_not_disturb_on,
        neutral.$1,
        neutral.$2,
        neutral.$3,
      ),
      SaveState.scrolling => (
        Icons.swipe_vertical,
        accent.$1,
        accent.$2,
        accent.$3,
      ),
      SaveState.inspecting || SaveState.navigating => (
        Icons.travel_explore,
        accent.$1,
        accent.$2,
        accent.$3,
      ),
      _ => (Icons.downloading, accent.$1, accent.$2, accent.$3),
    };

    return OperationChip(
      icon: icon,
      label: state.label,
      background: bg,
      foreground: fg,
      border: bd,
    );
  }
}
