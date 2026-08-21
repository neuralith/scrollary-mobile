import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_gate.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';

/// The product boundary, decided without a WebView, a route or a widget.
///
/// What is being pinned here is not "does Pro work" but **what Free keeps**.
/// Every case below that resolves to [LeaveGate.allowed] or to a working
/// [StartChoice.inBrowser] is a capability that shipped before any of this
/// existed, and charging for it later would be taking something away.
void main() {
  group('starting Browser-dependent work', () {
    test('no entitlement offers a working start and a locked option', () {
      for (final effective in [Entitlement.free, Entitlement.unknown]) {
        expect(
          resolveStartGate(effective: effective, preferenceEnabled: false),
          StartGate.multitaskingLocked,
        );
        expect(
          resolveStartGate(effective: effective, preferenceEnabled: true),
          StartGate.multitaskingLocked,
          reason:
              'a preference stored while the user had Pro does not survive '
              'losing it — but it is not deleted either',
        );
      }
    });

    test('Pro with the preference on is ready', () {
      expect(
        resolveStartGate(effective: Entitlement.pro, preferenceEnabled: true),
        StartGate.multitaskingReady,
      );
    });

    test('Pro with the preference off is offered, never assumed', () {
      expect(
        resolveStartGate(effective: Entitlement.pro, preferenceEnabled: false),
        StartGate.multitaskingAvailableButOff,
        reason:
            'granting Pro must not switch on a behaviour nobody asked for, '
            'and it must not silently act as Free either',
      );
    });
  });

  group('leaving the Browser', () {
    /// The phases that never needed the page: a direct download, a commit, a
    /// finished run. They were free for everyone before this capability
    /// existed and this is the test that keeps them that way.
    test('a phase that does not need the page lets everyone leave', () {
      for (final effective in Entitlement.values) {
        for (final preference in [true, false]) {
          for (final active in [true, false]) {
            expect(
              resolveLeaveGate(
                phaseNeedsBrowser: false,
                taskMultitaskingActive: active,
                effective: effective,
                preferenceEnabled: preference,
              ),
              LeaveGate.allowed,
              reason: 'no gate on a phase that is already safe away from it',
            );
          }
        }
      }
    });

    test('a multitasking task lets the user leave without a word', () {
      expect(
        resolveLeaveGate(
          phaseNeedsBrowser: true,
          taskMultitaskingActive: true,
          effective: Entitlement.pro,
          preferenceEnabled: true,
        ),
        LeaveGate.allowed,
      );
    });

    test('Free is asked, and the question names Pro', () {
      expect(
        resolveLeaveGate(
          phaseNeedsBrowser: true,
          taskMultitaskingActive: false,
          effective: Entitlement.free,
          preferenceEnabled: false,
        ),
        LeaveGate.askFree,
      );
    });

    test('Pro whose task started without it is asked differently', () {
      expect(
        resolveLeaveGate(
          phaseNeedsBrowser: true,
          taskMultitaskingActive: false,
          effective: Entitlement.pro,
          preferenceEnabled: false,
        ),
        LeaveGate.askProPreferenceOff,
        reason:
            'the honest answer is "this one keeps the screen it started '
            'with", not "buy Pro"',
      );
    });

    test('neither answer is ever "you cannot leave"', () {
      // Both asking outcomes exist to offer a way out. There is deliberately no
      // gate value that refuses navigation: pausing and leaving is always on
      // the table, for everyone.
      expect(LeaveGate.values, hasLength(3));
    });
  });

  group('the task capability snapshot', () {
    test('nothing owning the Browser reads the live value', () {
      final snapshot = TaskCapabilitySnapshot();
      expect(
        snapshot.resolve(operationOwnsBrowser: false, liveEnabled: true),
        isTrue,
      );
      expect(snapshot.isHeld, isFalse);
      expect(
        snapshot.resolve(operationOwnsBrowser: false, liveEnabled: false),
        isFalse,
      );
    });

    test('an owner keeps what it started with when the preference drops', () {
      final snapshot = TaskCapabilitySnapshot();
      expect(
        snapshot.resolve(operationOwnsBrowser: true, liveEnabled: true),
        isTrue,
      );
      expect(
        snapshot.resolve(operationOwnsBrowser: true, liveEnabled: false),
        isTrue,
        reason:
            'the user changed a setting; they did not ask to unpaint a page a '
            'save is in the middle of reading',
      );
    });

    test('and does not gain it when the preference is switched on', () {
      final snapshot = TaskCapabilitySnapshot();
      expect(
        snapshot.resolve(operationOwnsBrowser: true, liveEnabled: false),
        isFalse,
      );
      expect(
        snapshot.resolve(operationOwnsBrowser: true, liveEnabled: true),
        isFalse,
        reason:
            'the latch holds in both directions, which is what makes it '
            'a snapshot rather than a floor',
      );
    });

    test('the next task reads the new state', () {
      final snapshot = TaskCapabilitySnapshot();
      snapshot.resolve(operationOwnsBrowser: true, liveEnabled: false);
      // Ownership ends.
      expect(
        snapshot.resolve(operationOwnsBrowser: false, liveEnabled: true),
        isTrue,
      );
      expect(snapshot.isHeld, isFalse);
      // And the next one starts from it.
      expect(
        snapshot.resolve(operationOwnsBrowser: true, liveEnabled: true),
        isTrue,
      );
    });
  });

  group('the capability object answers both questions', () {
    ForegroundMultitasking pro({required bool preference}) =>
        ForegroundMultitasking(preference)
          ..override = EntitlementOverride.forcePro;

    test('enabled is for the next task, enabledForActiveTask for this one', () {
      final capability = pro(preference: true);
      expect(capability.enabled, isTrue);
      expect(capability.enabledForActiveTask, isTrue);

      // A task takes the Browser…
      capability.taskSnapshot.resolve(
        operationOwnsBrowser: true,
        liveEnabled: capability.enabled,
      );
      // …and the user turns the preference off mid-run.
      capability.preference = false;
      expect(capability.enabled, isFalse, reason: 'the next task will not');
      expect(
        capability.enabledForActiveTask,
        isTrue,
        reason: 'this one keeps the screen it started with',
      );
    });

    test('the leave gate reads the snapshot, not the preference', () {
      final capability = pro(preference: true);
      capability.taskSnapshot.resolve(
        operationOwnsBrowser: true,
        liveEnabled: true,
      );
      capability.preference = false;
      expect(
        capability.leaveGate(phaseNeedsBrowser: true),
        LeaveGate.allowed,
        reason: 'the task in flight is still multitasking',
      );
    });

    test('Force Free during a multitasking task does not strand it', () {
      final capability = pro(preference: true);
      capability.taskSnapshot.resolve(
        operationOwnsBrowser: true,
        liveEnabled: true,
      );
      capability.override = EntitlementOverride.forceFree;

      expect(capability.proAvailable, isFalse);
      expect(capability.enabled, isFalse);
      expect(
        capability.enabledForActiveTask,
        isTrue,
        reason: 'the running task keeps its surface',
      );
      expect(
        capability.preference,
        isTrue,
        reason: 'and the stored preference is not discarded',
      );
      expect(
        capability.startGate,
        StartGate.multitaskingLocked,
        reason: 'while the *next* start is Free again',
      );
    });
  });

  group('what may read an entitlement', () {
    /// One rule, enforced structurally: a screen asks the capability layer, and
    /// the capability layer asks the override. A screen that reads the override
    /// itself would be a second place the product boundary is decided, and the
    /// two would drift.
    test('no screen reads the internal override', () {
      final offenders = <String>[];
      final screens = <File>[
        ...Directory('lib/features').listSync().whereType<File>(),
        ...Directory('lib/browser').listSync().whereType<File>(),
      ];
      for (final file in screens) {
        if (!file.path.endsWith('.dart')) continue;
        // The internal developer control is where the override is *set*, and
        // it exists only in an internal build. Everything else asks the
        // capability layer.
        if (file.path.endsWith('developer_screen.dart')) continue;
        final source = file.readAsStringSync();
        if (source.contains('EntitlementOverride') ||
            source.contains('productionEntitlement(')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'read ForegroundMultitasking.startGate / leaveGate / enabled '
            'instead — the override is the capability layer\'s business',
      );
    });

    test('the developer control is the one place that may write it', () {
      final source = File(
        'lib/capability/entitlement_developer_control.dart',
      ).readAsStringSync();
      expect(source.contains('EntitlementOverride'), isTrue);
    });

    test('a production build ignores whatever is persisted', () {
      for (final override in EntitlementOverride.values) {
        expect(
          resolveEntitlement(
            production: Entitlement.free,
            override: override,
            internalBuild: false,
          ),
          Entitlement.free,
        );
      }
    });
  });
}
