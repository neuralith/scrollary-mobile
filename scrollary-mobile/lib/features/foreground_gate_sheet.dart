import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capability/foreground_gate.dart';
import '../capability/foreground_multitasking.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// The one surface that explains, offers and gates foreground multitasking.
///
/// Every start action, every way out of the Browser and the Settings row come
/// through here, so the product boundary is described in one voice and in one
/// file. A screen that wants to gate something supplies *what the user is
/// doing*; it never supplies the rule, the answer or the copy.
///
/// A bottom sheet because that is what this app already uses when a choice has
/// more than two outcomes and each one needs a sentence — the save scope sheet,
/// the batch queue sheet and the library check sheet are all built this way.

/// The name the capability goes by everywhere the user can see it.
const String kKeepWorkingLabel = 'Keep working while I read';

/// The one sentence about what this is and is not. Repeated deliberately: it
/// is the sentence that stops "keeps working" being read as "works in the
/// background", and it belongs next to every offer of the capability.
const String kForegroundOnlyNote =
    'Scrollary has to stay open in front. Nothing runs in the background, '
    'nothing runs while your phone is locked, and nothing runs once you close '
    'the app.';

/// What the user chose at a start.
enum StartChoice {
  /// Open the Browser and run it there — the Free workflow, unchanged.
  inBrowser,

  /// Start it and stay where you are.
  keepUsingApp,

  /// Turn the preference on, then start and stay where you are.
  enableAndKeepUsingApp,
}

/// What the user chose on the way out of the Browser.
enum LeaveChoice {
  /// Stay on the Browser; the operation is untouched.
  stay,

  /// Hold the operation at its next safe point, then leave.
  pauseAndLeave,
}

/// Offer the two ways to start Browser-dependent work.
///
/// [count] is only for the summary line; pass null when there is nothing to
/// count. Returns null when the user backed out, which must leave everything
/// queued exactly as it was.
Future<StartChoice?> showStartOptionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ForegroundGateAction action,
  required String title,
  required String summary,
}) {
  final capability = ref.read(foregroundMultitaskingProvider);
  final gate = capability.startGate;
  return showModalBottomSheet<StartChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _StartOptionsSheet(
      gate: gate,
      action: action,
      title: title,
      summary: summary,
    ),
  );
}

class _StartOptionsSheet extends StatelessWidget {
  const _StartOptionsSheet({
    required this.gate,
    required this.action,
    required this.title,
    required this.summary,
  });

  final StartGate gate;
  final ForegroundGateAction action;
  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: serifStyle(size: 22)),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              ForegroundStartActions(
                gate: gate,
                action: action,
                onChoice: (choice) => Navigator.of(context).pop(choice),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const ValueKey('startOptionsCancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gate's start options as a widget, so a screen with its own pre-run
/// sheet embeds the *same* rows rather than describing the boundary again.
///
/// This is the thing that makes "one gating flow" true rather than aspirational:
/// the Library check sheet has a great deal to say about what it is about to
/// check, and none of it belongs in this file — but the question of how the run
/// may proceed is identical to the queue's, so it is asked with these widgets.
class ForegroundStartActions extends StatelessWidget {
  const ForegroundStartActions({
    super.key,
    required this.gate,
    required this.action,
    required this.onChoice,
    this.inBrowserLabel = 'Start in Browser',
    this.keepUsingAppLabel = 'Start and keep using Scrollary',
  });

  final StartGate gate;
  final ForegroundGateAction action;
  final ValueChanged<StartChoice> onChoice;
  final String inBrowserLabel;
  final String keepUsingAppLabel;

  @override
  Widget build(BuildContext context) {
    final ready = gate == StartGate.multitaskingReady;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The multitasking option goes first when it is the one that will
        // actually happen, and last when it is locked — a locked control at the
        // top of a sheet reads as the main action.
        if (ready) ...[
          _GateAction(
            optionKey: 'startKeepUsingApp',
            icon: Icons.hourglass_bottom,
            label: keepUsingAppLabel,
            sub:
                'It runs while you read or use your Library. '
                '$kForegroundOnlyNote',
            primary: true,
            onTap: () => onChoice(StartChoice.keepUsingApp),
          ),
          const SizedBox(height: 8),
        ],
        _GateAction(
          optionKey: 'startInBrowser',
          icon: Icons.public,
          label: inBrowserLabel,
          sub:
              'The Browser opens and stays on screen while the work is done. '
              'You can watch it, and stop it at any point.',
          primary: !ready,
          onTap: () => onChoice(StartChoice.inBrowser),
        ),
        if (gate == StartGate.multitaskingAvailableButOff) ...[
          const SizedBox(height: 8),
          _GateAction(
            optionKey: 'startEnableAndKeepUsingApp',
            icon: Icons.hourglass_bottom,
            label: 'Turn on $kKeepWorkingLabel and start',
            sub:
                'Saves the setting, then starts and leaves you where you are. '
                '$kForegroundOnlyNote',
            onTap: () => onChoice(StartChoice.enableAndKeepUsingApp),
          ),
        ],
        if (gate == StartGate.multitaskingLocked) ...[
          const SizedBox(height: 8),
          _GateAction(
            optionKey: 'startKeepUsingAppLocked',
            icon: Icons.lock_outline,
            label: keepUsingAppLabel,
            sub: 'A Pro capability. Tap to see what it does.',
            lockedForPro: true,
            onTap: () => showProInfoSheet(context: context, action: action),
          ),
        ],
      ],
    );
  }
}

/// The way out of the Browser while something is using the page.
///
/// [gate] decides which third option is offered — reading about Pro, or turning
/// the preference on for next time. The two that are always there are the two
/// that resolve the situation in front of the user: stay, or hold it and go.
Future<LeaveChoice?> showLeaveBrowserSheet({
  required BuildContext context,
  required WidgetRef ref,
  required LeaveGate gate,
  required String progressLine,
}) => showModalBottomSheet<LeaveChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) =>
      _LeaveSheet(gate: gate, progressLine: progressLine, ref: ref),
);

class _LeaveSheet extends StatelessWidget {
  const _LeaveSheet({
    required this.gate,
    required this.progressLine,
    required this.ref,
  });

  final LeaveGate gate;
  final String progressLine;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final free = gate == LeaveGate.askFree;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('This step needs the Browser', style: serifStyle(size: 22)),
              const SizedBox(height: 6),
              Text(
                free
                    // States what the app does, and what Pro would do instead,
                    // without implying anything is broken or lost.
                    ? 'The page has to stay on screen while Scrollary reads it. '
                          'You can stay and watch it, or hold it here and come '
                          'back — nothing saved so far is lost either way.'
                    : 'This one started while $kKeepWorkingLabel was off, so it '
                          'still needs the page on screen. Turning the setting '
                          'on now applies to the next check or save — an '
                          'operation already under way keeps the screen it '
                          'started with.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: palette.inkMuted,
                ),
              ),
              if (progressLine.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    progressLine,
                    style: monoStyle(size: 11.5, color: palette.inkMuted),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _GateAction(
                optionKey: 'leaveStay',
                icon: Icons.public,
                label: 'Stay in Browser',
                sub: 'Carry on watching it. Nothing changes.',
                primary: true,
                onTap: () => Navigator.of(context).pop(LeaveChoice.stay),
              ),
              const SizedBox(height: 8),
              _GateAction(
                optionKey: 'leavePauseAndLeave',
                icon: Icons.pause_circle_outline,
                label: 'Pause and leave',
                sub:
                    'It stops at the next safe point and waits. Everything '
                    'saved so far is kept, and it picks up where it left off '
                    'when you come back.',
                onTap: () =>
                    Navigator.of(context).pop(LeaveChoice.pauseAndLeave),
              ),
              const SizedBox(height: 8),
              if (free)
                _GateAction(
                  optionKey: 'leaveLearnAboutPro',
                  icon: Icons.lock_outline,
                  label: 'What Pro does here',
                  sub:
                      'Pro can keep this same check or save running while you '
                      'read or use your Library.',
                  lockedForPro: true,
                  onTap: () => showProInfoSheet(
                    context: context,
                    action: ForegroundGateAction.leaveBrowser,
                  ),
                )
              else
                _EnableForNextTimeAction(ref: ref),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns the preference on without touching the operation in flight.
///
/// Its own widget because it is the only action in either sheet that writes
/// something and then *stays put*: the sheet remains open, the row confirms,
/// and the user still has to answer the question they were asked.
class _EnableForNextTimeAction extends StatefulWidget {
  const _EnableForNextTimeAction({required this.ref});

  final WidgetRef ref;

  @override
  State<_EnableForNextTimeAction> createState() =>
      _EnableForNextTimeActionState();
}

class _EnableForNextTimeActionState extends State<_EnableForNextTimeAction> {
  bool _done = false;

  Future<void> _enable() async {
    await setKeepWorkingPreference(widget.ref, true);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) => _GateAction(
    optionKey: 'leaveEnableForNextTime',
    icon: _done ? Icons.check_circle_outline : Icons.hourglass_bottom,
    label: _done
        ? '$kKeepWorkingLabel is on'
        : 'Turn on $kKeepWorkingLabel for next time',
    sub: _done
        ? 'The next check or save will keep running while you use Scrollary. '
              'This one still needs the page on screen.'
        : 'Applies to the next check or save, not this one.',
    onTap: _done ? null : _enable,
  );
}

/// What Pro adds here, and what it does not.
///
/// There is no billing in this build, so there is no Buy button: offering one
/// that cannot charge anybody would be the one genuinely dishonest thing this
/// screen could do. When a real store lands, its entry point goes
/// exactly where [_upgradeSeat] is.
Future<void> showProInfoSheet({
  required BuildContext context,
  required ForegroundGateAction action,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) {
    final palette = AppPalette.of(sheetContext);
    final what = switch (action) {
      ForegroundGateAction.startCollectionCheck =>
        'The check you are starting needs the Browser to read each '
            'collection\'s page.',
      ForegroundGateAction.startQueuedSaves ||
      ForegroundGateAction.startEntrySave =>
        'The save you are starting needs the Browser to prepare each page.',
      ForegroundGateAction.leaveBrowser =>
        'The step running right now needs the Browser page on screen.',
      ForegroundGateAction.settingsPreference =>
        'A check or save needs the Browser page on screen while it works.',
    };
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(kKeepWorkingLabel, style: serifStyle(size: 22)),
              ),
              const SizedBox(height: 4),
              Text(
                'A Pro capability',
                style: monoStyle(size: 11.5, color: palette.inkFaint),
              ),
              const SizedBox(height: 12),
              Text(
                '$what With Pro, Scrollary can keep that same check or save '
                'running while you read, browse your Library, or look at a '
                'collection.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              _ProFact(icon: Icons.phone_iphone, text: kForegroundOnlyNote),
              _ProFact(
                icon: Icons.pan_tool_outlined,
                text:
                    'Some pages still need you — a sign-in, a consent banner, '
                    'or a page Scrollary cannot read on its own. When that '
                    'happens it brings you back to the exact page.',
              ),
              _ProFact(
                icon: Icons.check_circle_outline,
                text:
                    'Everything else is the same on Free: starting, running, '
                    'progress, stopping, pausing, retrying, and everything you '
                    'have already saved. Without Pro a check or save simply '
                    'waits while you are elsewhere.',
              ),
              const SizedBox(height: 16),
              _upgradeSeat(context, palette),
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('proInfoClose'),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

/// Where a purchase will go, and what stands there until it does.
///
/// A line of text, not a disabled button: a greyed-out *Upgrade* implies a
/// purchase exists and is momentarily unavailable, which is a different and
/// untrue statement.
Widget _upgradeSeat(BuildContext context, AppPalette palette) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  decoration: BoxDecoration(
    color: palette.surfaceMuted,
    borderRadius: BorderRadius.circular(13),
    border: Border.all(color: palette.border),
  ),
  child: Text(
    'Pro is not on sale yet. Nothing here charges you, and nothing is '
    'switched off while you wait — this is what it will do when it arrives.',
    style: TextStyle(fontSize: 12, height: 1.5, color: palette.inkFaint),
  ),
);

class _ProFact extends StatelessWidget {
  const _ProFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: palette.inkMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable row in either sheet.
///
/// A locked row is **tappable**, deliberately. A disabled widget cannot
/// explain itself: a screen reader announces it as unavailable and stops
/// there, and a finger gets nothing back. This one announces that it needs Pro
/// and opens the explanation, which is the only useful thing it could do.
class _GateAction extends StatelessWidget {
  const _GateAction({
    required this.optionKey,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.primary = false,
    this.lockedForPro = false,
  });

  final String optionKey;
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;
  final bool primary;
  final bool lockedForPro;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      // The action is re-declared because [excludeSemantics] drops the
      // InkWell's own. Without it the row announces as a button and then
      // cannot be activated — the exact failure this widget exists to avoid.
      onTap: onTap,
      // The lock is in the spoken label, not only in the glyph: "requires Pro"
      // has to arrive before the tap, not after it.
      label: lockedForPro ? '$label. Requires Pro. $sub' : '$label. $sub',
      excludeSemantics: true,
      child: Material(
        color: primary ? palette.primaryContainer : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(optionKey),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: primary ? palette.primaryBorder : palette.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: primary ? palette.primary : palette.inkMuted,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontVariations: wght(500),
                                fontWeight: FontWeight.w500,
                                color: palette.ink,
                              ),
                            ),
                          ),
                          if (lockedForPro) ...[
                            const SizedBox(width: 7),
                            const ProBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: palette.inkMuted,
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

/// The word *Pro*, drawn the same way wherever a capability is locked.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.primaryBorder),
      ),
      child: Text('PRO', style: monoStyle(size: 9.5, color: palette.primary)),
    );
  }
}

/// Write the preference, in the one place that knows it has to be persisted
/// as well as applied.
///
/// Three callers — Settings, the start sheet and the leave sheet — and a
/// preference that is applied but never written is a setting that forgets
/// itself on the next launch.
Future<void> setKeepWorkingPreference(WidgetRef ref, bool value) async {
  final capability = ref.read(foregroundMultitaskingProvider);
  capability.preference = value;
  await ref
      .read(databaseProvider)
      .setSetting(ForegroundMultitasking.settingKey, capability.storedValue);
}
