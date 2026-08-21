import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/history_repository.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// The clear-history sheet: pick a range, see what it would remove, confirm.
///
/// The counts are read *before* anything is deleted, so "Clear today · 9
/// pages" is a promise rather than a guess. The "does not touch" block is
/// literally true: [HistoryRepository.clear] deletes from one table (§10).
Future<void> showClearHistorySheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _ClearHistorySheet(),
  );
}

class _ClearHistorySheet extends ConsumerStatefulWidget {
  const _ClearHistorySheet();

  @override
  ConsumerState<_ClearHistorySheet> createState() => _ClearHistorySheetState();
}

class _ClearHistorySheetState extends ConsumerState<_ClearHistorySheet> {
  HistoryClearRange _range = HistoryClearRange.today;
  Map<HistoryClearRange, int> _counts = const {};
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final repo = ref.read(historyRepositoryProvider);
    final now = DateTime.now();
    final counts = <HistoryClearRange, int>{};
    for (final range in HistoryClearRange.values) {
      counts[range] = await repo.countIn(range, now: now);
    }
    if (mounted) setState(() => _counts = counts);
  }

  Future<void> _confirm() async {
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final removed = await ref.read(historyRepositoryProvider).clear(_range);
    navigator.pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            removed == 0
                ? 'Nothing to clear in that range'
                : '$removed ${removed == 1 ? 'page' : 'pages'} cleared · '
                      'saved sites kept',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Clear browsing history',
              style: serifStyle(size: 20, color: palette.ink),
            ),
            const SizedBox(height: 5),
            Text(
              'Removes visited addresses, page titles and visit times from '
              'this device.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 13),
            for (final range in HistoryClearRange.values) ...[
              _RangeOption(
                range: range,
                count: _counts[range],
                selected: _range == range,
                onTap: () => setState(() => _range = range),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This does not touch',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontVariations: wght(600),
                      fontWeight: FontWeight.w600,
                      color: palette.inkStrong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved sites · your library · saved entries · reading '
                    'progress · website sign-ins.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.55,
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('confirmClearHistory'),
                    onPressed: _working ? null : _confirm,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(_range.cta),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeOption extends StatelessWidget {
  const _RangeOption({
    required this.range,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final HistoryClearRange range;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: ValueKey('clearRange-${range.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 19,
                color: selected ? palette.primary : palette.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  range.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontVariations: wght(500),
                    fontWeight: FontWeight.w500,
                    color: palette.ink,
                  ),
                ),
              ),
              Text(
                count == null ? '—' : '$count ${count == 1 ? 'page' : 'pages'}',
                style: monoStyle(size: 11, color: palette.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clear website data — cookies, site storage, cache.
///
/// A stronger confirmation than clearing history, because it signs the user
/// out of sources that need a login, and save on those sources stops
/// working until they sign in again (§11).
Future<void> showClearWebsiteDataDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  // Refused while an operation holds the WebView, the same way a collection
  // refuses to be deleted while one of its entries is open. Cookies and site
  // storage are process-global: clearing them mid-run signs the run out of the
  // site it is reading, and it would find out as a stopping condition several
  // pages later. Refusing is not a limitation the user has to work around —
  // the operation is theirs, it is on screen, and stopping it takes one tap.
  final run = ref.read(saveRunProvider);
  final checker = ref.read(updateCheckerProvider);
  if (run.isRunning ||
      checker.isRunning ||
      ref.read(browserProvider).isAutomating) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('clearDataRefused'),
        title: const Text('Something is using the Browser'),
        content: Text(
          run.isRunning
              ? 'A save is running. Clearing website data now would sign it '
                    'out of the site it is reading. Stop the save first, or '
                    'wait for it to finish.'
              : 'A check is running. Clearing website data now would sign it '
                    'out of the site it is reading. Stop the check first, or '
                    'wait for it to finish.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => const _ClearWebsiteDataDialog(),
  );
}

class _ClearWebsiteDataDialog extends ConsumerStatefulWidget {
  const _ClearWebsiteDataDialog();

  @override
  ConsumerState<_ClearWebsiteDataDialog> createState() =>
      _ClearWebsiteDataDialogState();
}

class _ClearWebsiteDataDialogState
    extends ConsumerState<_ClearWebsiteDataDialog> {
  bool _acknowledged = false;
  bool _working = false;

  Future<void> _confirm() async {
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final browser = ref.read(browserProvider);

    final failures = await browser.clearWebsiteData();
    // The icons were fetched from those sites too.
    await ref.read(faviconServiceProvider).clear();
    // The page behind Browser Home may no longer be signed in; stop the
    // "still open" row from implying otherwise.
    ref.read(browserPresentationProvider).forgetPreserved();

    navigator.pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            failures.isEmpty
                ? "Website data cleared · you'll need to sign in again"
                // Honest rather than tidy: naming what the platform refused
                // beats claiming a clean sweep (§11).
                : 'Website data cleared, except: ${failures.join(', ')}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      icon: Icon(Icons.no_encryption, size: 26, color: palette.danger),
      title: const Text('Clear website data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This signs you out of every site you've logged into in the "
            'Browser and clears their cookies and stored data. Sources that '
            'need a login will have to be signed in again before save '
            'works.',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'Your library, saved entries, saved sites and reading '
              'progress are kept. Browsing history is cleared separately.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: palette.inkMuted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('clearDataAcknowledge'),
            onTap: () => setState(() => _acknowledged = !_acknowledged),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _acknowledged
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 21,
                    color: _acknowledged ? palette.danger : palette.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "I understand I'll be signed out of these sites",
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirmClearWebsiteData'),
          // Gated on the acknowledgement, not merely warned about: this is
          // the one action here the user cannot undo by re-doing it.
          onPressed: _acknowledged && !_working ? _confirm : null,
          style: FilledButton.styleFrom(backgroundColor: palette.danger),
          child: const Text('Clear data'),
        ),
      ],
    );
  }
}
