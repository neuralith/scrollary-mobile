/// *Check all collections* — the Library's own verb.
///
/// One control, in the Library header beside Activity and Settings. It asks
/// first, because it drives the Browser: content-affecting source automation
/// is user-started, visible, bounded and cancellable, and this is no exception
/// (CLAUDE.md, "Two kinds of network work").
///
/// What it says afterwards is deliberately one sentence. Which Collections
/// have new entries is not repeated here — the rows carry that themselves
/// (`features/check_state.dart`), and a result screen listing what the library
/// is already showing is a second copy to keep in step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capability/foreground_gate.dart';
import '../library_ui/library_widgets.dart';
import '../providers.dart';
import '../ui/status_style.dart';
import 'foreground_gate_sheet.dart';
import 'library_check_flow.dart';
import 'operation_lane.dart';

/// The header control. Absent where no library-wide check is attached.
class LibraryCheckButton extends ConsumerWidget {
  const LibraryCheckButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(libraryCheckProvider);
    if (controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => HeaderIconButton(
        key: const ValueKey('libraryAction-checkAll'),
        icon: controller.isRunning ? Icons.stop_circle_outlined : Icons.refresh,
        tooltip: controller.isRunning
            ? 'Stop checking'
            : 'Check all collections',
        onPressed: controller.isRunning
            ? controller.stop
            : () => startLibraryCheck(context, ref),
      ),
    );
  }
}

/// Ask, then check every Collection.
///
/// Runs in the one lane every Browser-driving operation runs in: a pass asked
/// for while a download or a single check holds the Browser waits its turn and
/// says so, rather than being thrown away or started alongside.
///
/// Returns the report, or null when nothing ran — a dismissed sheet, or a
/// pass already in flight. Both are ordinary answers and neither writes a row.
Future<LibraryCheckReport?> startLibraryCheck(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = ref.read(libraryCheckProvider);
  if (controller == null) return null;
  final lane = ref.read(operationLaneProvider);
  // Already going, or already waiting its turn: a second tap is a duplicate,
  // and the control itself is a Stop while a pass is running.
  if (lane.holds(kLibraryCheckWorkKey)) {
    if (!controller.isRunning) {
      showLibraryMessage(
        context,
        'Your library is already waiting to be checked.',
      );
    }
    return null;
  }

  final choice = await showStartOptionsSheet(
    context: context,
    ref: ref,
    action: ForegroundGateAction.startCollectionCheck,
    title: 'Check every collection for new entries?',
    summary:
        'Scrollary opens each collection\'s site in the Browser, one at a '
        'time, and reads its list of entries. Nothing is downloaded, and you '
        'can stop it at any point.',
  );
  if (choice == null || !context.mounted) return null;

  if (choice == StartChoice.enableAndKeepUsingApp) {
    await setKeepWorkingPreference(ref, true);
    if (!context.mounted) return null;
  }
  // Browser first, automation second — the same order a single check uses.
  if (choice == StartChoice.inBrowser) {
    ref.read(shellTabRequestProvider).value = 1;
  }

  // The same lane a single check and a download run in: one thing drives the
  // Browser, and a pass asked for while something else holds it waits rather
  // than being thrown away.
  final report = await lane.submit(
    key: kLibraryCheckWorkKey,
    label: kCheckWorkLabel,
    whenQueued: (active) => showLibraryMessage(
      context,
      queuedBehindSentence(active: active, request: 'this check'),
    ),
    body: controller.run,
  );
  if (!context.mounted || report == null) return report;
  showLibraryMessage(context, libraryCheckSentence(report));
  return report;
}
