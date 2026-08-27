/// The two questions the reader asks when the next Entry is not simply there.
///
/// Both are bottom sheets, and deliberately: the request they answer arrives
/// from the bottom of the screen — the *Next entry* control in the bottom
/// chrome, or a pull up from the bottom edge — so the answer belongs under the
/// same thumb rather than in the middle of the page.
///
/// Both are also **offers, never verdicts**. Neither sheet tells the user that
/// something has ended or that something is unavailable: one says where the
/// next Entry can still be read, the other says what the library knows right
/// now and offers to go and look again. The dead-end sentence this replaced —
/// "this entry is not available locally", full stop — was true about the
/// device and read as a fact about the work.
library;

import 'package:flutter/material.dart';

import '../ui/palette.dart';
import '../ui/status_style.dart';

/// *The next entry is in your library, but not on this device.*
///
/// The Entry is first-class and it is simply not downloaded here, so the way
/// on is its Source — offered as the action, with staying put as the plain
/// alternative rather than as a dismissal the user has to guess at.
///
/// Returns true when the user asked to continue at the source.
Future<bool> showContinueAtSourceSheet({
  required BuildContext context,
  required String entryName,
}) async {
  final chose = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _NextEntrySheet(
      sheetKey: const ValueKey('nextEntryAtSourceSheet'),
      icon: Icons.public,
      title: 'The next entry is not downloaded here',
      body:
          'It is in your library — this device just has no copy of it. You '
          'can carry on reading it at its original page.',
      subject: entryName,
      actionKey: const ValueKey('nextEntryOpenAtSource'),
      actionLabel: 'Open on website',
      cancelKey: const ValueKey('nextEntryStayHere'),
    ),
  );
  return chose ?? false;
}

/// *Nothing follows this entry in your library — shall I look?*
///
/// Never "you have reached the end of this collection": the library knowing of
/// no next Entry is a fact about the library, and an update check is the one
/// thing that can turn it into a fact about the site. The check itself is the
/// app's existing one, started by the caller — this sheet only asks.
///
/// [canCheck] false means no checker is wired to this surface at all, so the
/// action is absent rather than present and inert.
///
/// Returns true when the user asked for a check.
Future<bool> showCheckForNewEntriesSheet({
  required BuildContext context,
  required String collectionName,
  bool canCheck = true,
}) async {
  final chose = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _NextEntrySheet(
      sheetKey: const ValueKey('nextEntryCheckSheet'),
      icon: Icons.update,
      title: 'No next entry is currently in your library',
      body: canCheck
          ? 'That is what your library holds right now, not necessarily where '
                'this collection ends. Scrollary can open its site and read '
                'the list again — nothing is downloaded.'
          : 'That is what your library holds right now, not necessarily where '
                'this collection ends.',
      subject: collectionName,
      actionKey: const ValueKey('nextEntryCheckNow'),
      actionLabel: canCheck ? 'Check for new entries' : null,
      cancelKey: const ValueKey('nextEntryCheckDismiss'),
      cancelLabel: canCheck ? 'Not now' : 'Stay here',
    ),
  );
  return chose ?? false;
}

/// One shape for both questions: what this is about, what it means, one action
/// and one way to stay exactly where you are.
class _NextEntrySheet extends StatelessWidget {
  const _NextEntrySheet({
    required this.sheetKey,
    required this.icon,
    required this.title,
    required this.body,
    required this.subject,
    required this.actionKey,
    required this.actionLabel,
    required this.cancelKey,
    this.cancelLabel = 'Stay here',
  });

  final Key sheetKey;
  final IconData icon;
  final String title;
  final String body;

  /// The Entry or Collection this is about, printed when there is one. Never
  /// folded into [title]: the stored name is the user's, and a sentence built
  /// around it would put this app's words inside it.
  final String subject;

  final Key actionKey;

  /// Null leaves the action out entirely — see [showCheckForNewEntriesSheet].
  final String? actionLabel;

  final Key cancelKey;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final action = actionLabel;
    return SafeArea(
      key: sheetKey,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 26, color: palette.inkMuted),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(title, style: serifStyle(size: 22)),
              ),
              if (subject.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subject.trim(),
                  style: monoStyle(size: 11.5, color: palette.inkStrong),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              if (action != null)
                FilledButton(
                  key: actionKey,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(action),
                ),
              const SizedBox(height: 6),
              TextButton(
                key: cancelKey,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
