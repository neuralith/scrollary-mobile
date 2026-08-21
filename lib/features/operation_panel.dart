import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/palette.dart';
import '../ui/theme.dart';

/// The shared parts of the bottom "something is running" panel.
///
/// Two operations dock under the WebView — a save run and an update check —
/// and they are not the same shape: a save counts entries, images and scroll
/// position and can be paused, retried and skipped; a check counts pages and
/// discovered entries and can only be stopped. What they *do* share is the
/// chrome: the frame, the phase chip, the log drawer with its toggle and copy
/// action, and the control pills.
///
/// That chrome lives here so neither panel is a copy of the other. It
/// deliberately holds no state and knows nothing about either controller — a
/// panel builds these from whatever it has, which is what lets a second
/// operation reuse it without the first one changing behaviour.

/// The docked container: surface, top rule, padding.
class OperationPanelFrame extends StatelessWidget {
  const OperationPanelFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// The phase chip: icon + uppercase mono label, in the colours the caller
/// chose. Which colours mean what is the *operation's* decision — a save's
/// "PARTIAL" and a check's "CHECKING" are not comparable states — so this
/// takes them rather than deriving them.
class OperationChip extends StatelessWidget {
  const OperationChip({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 11.5,
            letterSpacing: 0.35,
            fontWeight: FontWeight.w500,
            color: foreground,
          ),
        ),
      ],
    ),
  );
}

/// "Log" / "Hide log", right-aligned on the header row.
class OperationLogToggle extends StatelessWidget {
  const OperationLogToggle({
    super.key,
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Hide log' : 'Log',
              style: TextStyle(
                fontSize: 11.5,
                fontVariations: wght(500),
                fontWeight: FontWeight.w500,
                color: palette.primary,
              ),
            ),
            Icon(
              expanded ? Icons.expand_more : Icons.expand_less,
              size: 16,
              color: palette.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark log drawer, newest line first, with a copy action.
class OperationLogDrawer extends StatelessWidget {
  const OperationLogDrawer({
    super.key,
    required this.lines,
    required this.onCopy,
  });

  /// Newest first, as both controllers keep them.
  final List<String> lines;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 8),
      decoration: BoxDecoration(
        color: palette.toastSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines.take(40))
                    Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontSize: 10.5,
                        height: 1.7,
                        color: line.contains('fail')
                            ? AppPalette.dark.danger
                            : palette.toastInk,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onCopy,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.content_copy, size: 14, color: palette.toastAccent),
                const SizedBox(width: 5),
                Text(
                  'Copy log',
                  style: TextStyle(fontSize: 11, color: palette.toastAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short banner for the operation's last error.
class OperationErrorNote extends StatelessWidget {
  const OperationErrorNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: palette.dangerContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.dangerBorder),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.45,
          color: palette.onDangerContainer,
        ),
      ),
    );
  }
}

class OperationPrimaryButton extends StatelessWidget {
  const OperationPrimaryButton(this.label, this.icon, this.onTap, {super.key});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    ),
  );
}

class OperationPillButton extends StatelessWidget {
  const OperationPillButton(this.label, this.icon, this.onTap, {super.key});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      foregroundColor: AppPalette.of(context).inkStrong,
      side: BorderSide(color: AppPalette.of(context).borderStrong),
    ),
  );
}

/// Copy a log to the clipboard and say how much went.
///
/// Both operations redact the same way — cookies and tokens never reach a log
/// line — so what this produces is safe to paste into an issue.
Future<void> copyOperationLog(
  BuildContext context, {
  required String header,
  required List<String> lines,
}) async {
  final buffer = StringBuffer()..writeln(header);
  for (final line in lines.reversed) {
    buffer.writeln(line);
  }
  await Clipboard.setData(ClipboardData(text: buffer.toString()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Copied ${lines.length} log lines'),
      duration: const Duration(seconds: 2),
    ),
  );
}
