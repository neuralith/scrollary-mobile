import 'package:flutter/foundation.dart';

import 'entitlement.dart';
import 'foreground_gate.dart';

/// Whether one user-started operation may keep running while the user is
/// somewhere else in the app.
///
/// **One boolean, one owner.** Everything that changes behaviour reads
/// [enabled] and nothing asks *why* it is what it is. Today the only thing
/// that writes it is a setting the user can see and change. That single
/// indirection is the whole seam — see docs/FOREGROUND_MULTITASKING.md §10.
/// Nothing here counts anything, remembers a purchase, or holds a state
/// waiting to be switched on; `library_check_test.dart` fails the build if it
/// ever does.
///
/// The capability may only ever remove a *convenience*. With it off, every
/// operation still runs, still completes, still reports and still recovers —
/// the user simply has to be looking at the Browser, which is the behaviour
/// that shipped before this existed. Nothing here may gate safety, status,
/// cancellation, recovery or access to saved content.
///
/// Deliberately in its own directory with no imports beyond `foundation`: it
/// must stay unreachable from reading state, cleanup and collection deletion.
class ForegroundMultitasking extends ChangeNotifier {
  ForegroundMultitasking([this._enabled = defaultEnabled]);

  /// The persisted key for the internal entitlement override.
  static const String overrideSettingKey = 'capability.entitlementOverride';

  /// The persisted settings key. The value is `'true'` or `'false'`; anything
  /// else — including a missing row — reads as [defaultEnabled].
  static const String settingKey = 'capability.foregroundMultitasking';

  /// **Off, deliberately.**
  ///
  /// The architecture gate passed on the iOS Simulator and the Android
  /// emulator, but not yet on physical hardware (docs/FOREGROUND_MULTITASKING.md
  /// §3.1, and test D-1 in the plan). Until it does, keeping a WebView painted
  /// under another screen is an opt-in, so an unverified compositing assumption
  /// cannot become the default path a save takes.
  ///
  /// Flip this to `true` when D-1 and D-2 pass, and say so in the plan's
  /// validation record.
  static const bool defaultEnabled = false;

  static bool parse(String? raw) => switch (raw) {
    'true' => true,
    'false' => false,
    _ => defaultEnabled,
  };

  bool _enabled;

  /// What the **user asked for**, whatever they are entitled to.
  ///
  /// Deliberately survives losing Pro. A preference is a statement of intent,
  /// and discarding it on entitlement loss would silently reset a choice the
  /// user made — so it is kept and simply stops taking effect. [enabled] is
  /// the honest answer to "is this happening", [preference] to "what did they
  /// ask for", and the Settings toggle shows the second while obeying the
  /// first.
  bool get preference => _enabled;

  set preference(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  EntitlementOverride _override = EntitlementOverride.production;

  /// The internal build's pretend entitlement. Always `production` in a
  /// production build, where nothing can write it.
  EntitlementOverride get override => _override;

  set override(EntitlementOverride value) {
    if (_override == value) return;
    _override = value;
    notifyListeners();
  }

  /// The entitlement after the override is applied.
  Entitlement get effectiveEntitlement => resolveEntitlement(
    production: productionEntitlement(),
    override: _override,
  );

  /// Is the paid capability available to this user at all?
  bool get proAvailable => proCapabilityAvailable(effectiveEntitlement);

  /// **Is foreground multitasking actually happening?**
  ///
  /// Pro available *and* the user asked for it. Everything in the app reads
  /// this and nothing reads the two halves separately, so there is one answer
  /// and it cannot drift.
  bool get enabled => foregroundMultitaskingActive(
    effective: effectiveEntitlement,
    preferenceEnabled: _enabled,
  );

  /// The capability the operation currently holding the Browser started with.
  ///
  /// Kept here rather than in the shell because it is part of the answer to
  /// "is this happening", and the shell is only the thing that happens to
  /// notice ownership changing. See [TaskCapabilitySnapshot].
  final TaskCapabilitySnapshot taskSnapshot = TaskCapabilitySnapshot();

  /// **Is the task in flight multitasking?**
  ///
  /// [enabled] answers for the *next* task; this answers for the one already
  /// running. They differ exactly when the user changed something mid-task,
  /// which is the case the snapshot exists for — and the reason the leave sheet
  /// can honestly say a new preference applies to the next task.
  bool get enabledForActiveTask => taskSnapshot.held ?? enabled;

  /// What a start surface should offer. One question, one answer, everywhere.
  StartGate get startGate => resolveStartGate(
    effective: effectiveEntitlement,
    preferenceEnabled: _enabled,
  );

  /// What should happen when the user tries to leave the Browser now.
  ///
  /// [phaseNeedsBrowser] is the caller's own knowledge of the operation in
  /// flight — a download or commit phase that is already safe away from the
  /// page answers false, and gets [LeaveGate.allowed] for everyone.
  LeaveGate leaveGate({required bool phaseNeedsBrowser}) => resolveLeaveGate(
    phaseNeedsBrowser: phaseNeedsBrowser,
    taskMultitaskingActive: enabledForActiveTask,
    effective: effectiveEntitlement,
    preferenceEnabled: _enabled,
  );

  /// What the persisted row should say.
  String get storedValue => _enabled ? 'true' : 'false';
}
