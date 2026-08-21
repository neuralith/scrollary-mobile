import '../capability/entitlement_developer_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_reset.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// The reset service, wired to the app's real stores.
final localResetProvider = Provider<LocalResetService>((ref) {
  final services = ref.watch(appServicesProvider);
  return LocalResetService(
    db: services.db,
    fileStore: services.fileStore,
    browser: services.browser,
    saveRun: services.saveRun,
    checker: services.updateChecker,
    taskQueue: services.taskQueue,
    clearCookies: () => CookieManager.instance().deleteAllCookies(),
  );
});

/// Development tools. Reachable only in debug builds — see
/// [developerToolsAvailable].
class DeveloperScreen extends ConsumerStatefulWidget {
  const DeveloperScreen({super.key});

  @override
  ConsumerState<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends ConsumerState<DeveloperScreen> {
  ResetReport? _lastReport;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // Belt and braces: the route is only registered in debug, and the screen
    // refuses to render outside it anyway.
    if (!developerToolsAvailable) {
      return const Scaffold(
        body: Center(child: Text('Developer tools are not available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        children: [
          const SectionLabel('SIMULATED ENTITLEMENT'),
          const EntitlementOverridePicker(),
          const SectionLabel('INTERNAL BUILD ONLY'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'These tools exist so development can start from a known empty '
              'state, and so Free and Pro behaviour can be exercised without '
              'reinstalling. Compiled out unless this is a debug build or was '
              'launched with SCROLLARY_INTERNAL_BUILD=true.',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppPalette.of(context).inkMuted,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('resetAllLocalData'),
            leading: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.delete_forever,
                    color: AppPalette.of(context).danger,
                  ),
            title: Text(
              'Reset all local app data',
              style: TextStyle(color: AppPalette.of(context).danger),
            ),
            subtitle: const Text(
              'Library, saved files, reading progress, queue, rules, '
              'settings and cookies',
            ),
            onTap: _busy ? null : _confirmReset,
          ),
          if (_lastReport != null) _ReportCard(report: _lastReport!),
        ],
      ),
    );
  }

  /// Two steps, and the second one cannot be hit by accident: the confirm
  /// button stays disabled until the word RESET has been typed.
  Future<void> _confirmReset() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber,
          size: 26,
          color: AppPalette.of(dialogContext).danger,
        ),
        title: const Text('Reset all local data?'),
        content: const Text(
          'This removes your library, saved files, reading progress, '
          'settings, queue, and saved site rules from this device.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('resetContinue'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final typed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _TypeToConfirmDialog(),
    );
    if (typed != true || !mounted) return;

    setState(() => _busy = true);
    final report = await ref.read(localResetProvider).resetEverything();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastReport = report;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(report.summary),
        backgroundColor: report.ok ? null : AppPalette.of(context).danger,
        action: report.ok
            ? null
            : SnackBarAction(label: 'Retry', onPressed: _confirmReset),
      ),
    );
  }
}

/// The second gate: type the word. A hold-to-confirm button was the
/// alternative; typing leaves a record of intent that a stray long-press
/// cannot produce.
class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog();

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _controller = TextEditingController();
  static const _word = 'RESET';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = _controller.text.trim().toUpperCase() == _word;
    return AlertDialog(
      title: const Text('Type RESET to confirm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Everything on this device goes. There is no undo and no backup.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('resetConfirmField'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: _word,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('resetEverything'),
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.of(context).danger,
            foregroundColor: AppPalette.of(context).onPrimary,
          ),
          onPressed: armed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Reset everything'),
        ),
      ],
    );
  }
}

/// The per-area outcome, so a partial failure is visible rather than implied.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final ResetReport report;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: report.ok ? palette.primaryContainer : palette.dangerContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: report.ok ? palette.primaryBorder : palette.dangerBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.summary,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: report.ok
                  ? palette.onPrimaryContainer
                  : palette.onDangerContainer,
            ),
          ),
          const SizedBox(height: 8),
          for (final step in report.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                step.toString(),
                style: monoStyle(
                  size: 11.5,
                  color: step.ok ? palette.onPrimaryContainer : palette.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
