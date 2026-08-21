import 'entitlement.dart';

/// The one place that answers "may this happen without the Browser on screen?"
///
/// Every screen that starts Browser-dependent work, or lets the user walk away
/// from it, asks here. Nothing asks `isPro` for itself, nothing reads the
/// internal override, and nothing re-derives the rule from
/// `Entitlement` + preference on its own — that is how a Queue screen and a
/// Reader end up disagreeing about what a user has paid for.
///
/// Pure functions over two inputs, so the whole product boundary is testable
/// without a WebView, a route or a widget.
///
/// **What is paid for, and what is not.** Starting a check or a save, running
/// it, watching it, stopping it, pausing it, recovering it, retrying it and
/// reading everything it produced are Free, permanently. The paid capability is
/// exactly one convenience: *whether Browser-dependent phases may continue
/// while the user goes and uses another part of the app.* Free keeps the
/// complete visible-Browser workflow that shipped before any of this existed.

/// What a caller is about to do. Used only to choose copy — never to change
/// the decision, which depends on entitlement, preference and phase alone.
enum ForegroundGateAction {
  startQueuedSaves,
  startCollectionCheck,
  startEntrySave,
  leaveBrowser,
  settingsPreference,
}

/// How a start will actually run.
enum StartMode {
  /// The Browser comes forward and stays visible. The Free workflow, and what
  /// a Pro user gets when they have not asked for anything else.
  visibleBrowser,

  /// The work starts and the user stays where they are.
  keepUsingApp,
}

/// What the gate says about *starting* Browser-dependent work.
enum StartGate {
  /// Pro, and the preference is on: offer both, default to keeping the user
  /// where they are.
  multitaskingReady,

  /// Pro, but the preference is off. Offer to turn it on and start, or to
  /// start in the Browser as usual. Never silently pick one.
  multitaskingAvailableButOff,

  /// No Pro. The visible-Browser start is fully functional, and the
  /// multitasking option is shown *locked* — visible, tappable, and it
  /// explains itself.
  multitaskingLocked,
}

StartGate resolveStartGate({
  required Entitlement effective,
  required bool preferenceEnabled,
}) {
  if (!proCapabilityAvailable(effective)) return StartGate.multitaskingLocked;
  return preferenceEnabled
      ? StartGate.multitaskingReady
      : StartGate.multitaskingAvailableButOff;
}

/// What the gate says about *leaving the Browser* right now.
enum LeaveGate {
  /// Nothing is at risk. Either no operation needs the page, the phase in
  /// flight is already safe away from it (a direct download, a commit), or the
  /// task is running with multitasking and will simply carry on.
  ///
  /// **This is the Free-preserving case and it must stay wide.** The phases
  /// that already continued without a painted WebView continued for everyone
  /// before this capability existed, and gating them now would be charging for
  /// something that used to be free.
  allowed,

  /// Free, and a Browser-dependent phase would be stranded. Offer to stay, to
  /// pause and leave, and to read what Pro would do differently.
  askFree,

  /// Pro, but this task started without multitasking, so its surface cannot be
  /// taken away from it now (see [TaskCapabilitySnapshot]). Offer to stay, to
  /// pause and leave, and to turn the preference on for the next task.
  askProPreferenceOff,
}

LeaveGate resolveLeaveGate({
  required bool phaseNeedsBrowser,
  required bool taskMultitaskingActive,
  required Entitlement effective,
  required bool preferenceEnabled,
}) {
  if (!phaseNeedsBrowser) return LeaveGate.allowed;
  if (taskMultitaskingActive) return LeaveGate.allowed;
  return proCapabilityAvailable(effective)
      ? LeaveGate.askProPreferenceOff
      : LeaveGate.askFree;
}

/// The capability as it stood when the operation now holding the Browser began.
///
/// **An operation keeps the surface it started with.** Without this, turning
/// the preference off — or an entitlement source answering differently — while
/// a save is mid-page would stop the app compositing the WebView underneath it,
/// and the run would stall on a page it was in the middle of reading. The user
/// changed a setting; they did not ask to interrupt anything.
///
/// It latches on the *edge*: taken when an operation acquires the Browser, and
/// dropped the moment nothing owns it, so the very next task reads the current
/// state. The consequence worth naming — and the reason the leave sheet says
/// so — is that the latch works in both directions: switching the preference on
/// mid-task does not retrofit multitasking onto a task that started without it.
/// A task that began expecting to be watched is allowed to go on expecting it.
class TaskCapabilitySnapshot {
  bool? _held;

  /// What the current owner started with, or null when nothing owns the
  /// Browser.
  bool? get held => _held;

  bool get isHeld => _held != null;

  /// Called on every surface recompute. Returns the value the surface rule
  /// should use.
  bool resolve({
    required bool operationOwnsBrowser,
    required bool liveEnabled,
  }) {
    if (!operationOwnsBrowser) {
      _held = null;
      return liveEnabled;
    }
    return _held ??= liveEnabled;
  }
}
