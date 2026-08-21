import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_gate.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/features/foreground_gate_sheet.dart';
import 'package:web_reader/features/settings_screen.dart'
    show KeepWorkingSettingRow;
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';

/// What the gate looks like, and what a screen reader is told about it.
///
/// The rule these tests exist to hold: **a locked capability is a control that
/// explains itself.** A disabled widget announces as unavailable and stops
/// there, which leaves the user knowing something is missing and nothing about
/// what or why. Every locked control here is tappable and says "Requires Pro"
/// out loud before it is tapped.
void main() {
  late AppDatabase db;
  late ForegroundMultitasking capability;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    capability = ForegroundMultitasking();
  });
  tearDown(() async {
    await db.close();
    capability.dispose();
  });

  Widget harness(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      foregroundMultitaskingProvider.overrideWithValue(capability),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  /// A button that opens the start sheet and records what it returned.
  Widget starter(void Function(StartChoice?) onResult) => Consumer(
    builder: (context, ref, _) => TextButton(
      onPressed: () async {
        final choice = await showStartOptionsSheet(
          context: context,
          ref: ref,
          action: ForegroundGateAction.startQueuedSaves,
          title: 'Start queued saves?',
          summary: 'Each page has to be prepared in the Browser.',
        );
        onResult(choice);
      },
      child: const Text('open'),
    ),
  );

  final inBrowser = find.byKey(const ValueKey('startInBrowser'));
  final keepUsingApp = find.byKey(const ValueKey('startKeepUsingApp'));
  final lockedOption = find.byKey(const ValueKey('startKeepUsingAppLocked'));
  final enableAndStart = find.byKey(
    const ValueKey('startEnableAndKeepUsingApp'),
  );

  group('the start sheet, without Pro', () {
    testWidgets('offers a working start in the Browser', (tester) async {
      StartChoice? result;
      await tester.pumpWidget(harness(starter((c) => result = c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(inBrowser, findsOneWidget);
      expect(keepUsingApp, findsNothing);
      await tester.tap(inBrowser);
      await tester.pumpAndSettle();

      expect(
        result,
        StartChoice.inBrowser,
        reason: 'the Free workflow is not degraded to make Pro look better',
      );
    });

    testWidgets('shows the multitasking option locked, not hidden', (
      tester,
    ) async {
      await tester.pumpWidget(harness(starter((_) {})));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(lockedOption, findsOneWidget);
      expect(find.text('PRO'), findsWidgets);
      // The key is on the InkWell itself: the locked row is one tappable
      // thing, not a disabled shell around one.
      final inkWell = tester.widget<InkWell>(lockedOption);
      expect(
        inkWell.onTap,
        isNotNull,
        reason: 'a locked control that cannot be tapped cannot explain itself',
      );
    });

    testWidgets('the locked option announces that it needs Pro', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(starter((_) {})));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(lockedOption);
      expect(node.label, contains('Requires Pro'));
      expect(node.label, contains('Start and keep using Scrollary'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'a locked control announced with no way to activate it tells a '
            'screen-reader user it is broken, rather than that it is a '
            'capability they do not have yet',
      );
      handle.dispose();
    });

    testWidgets('tapping it opens the explanation, and starts nothing', (
      tester,
    ) async {
      StartChoice? result;
      var called = false;
      await tester.pumpWidget(
        harness(
          starter((c) {
            called = true;
            result = c;
          }),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(lockedOption);
      await tester.pumpAndSettle();

      expect(find.text('Keep working while I read'), findsWidgets);
      expect(find.text('A Pro capability'), findsOneWidget);
      expect(
        find.textContaining('Nothing runs in the background'),
        findsWidgets,
        reason: 'the foreground-only limit is stated wherever Pro is offered',
      );
      expect(
        find.textContaining('not on sale yet'),
        findsOneWidget,
        reason: 'no purchase is faked',
      );
      expect(find.widgetWithText(FilledButton, 'Upgrade'), findsNothing);
      expect(
        called,
        isFalse,
        reason: 'the start sheet is still open behind it — nothing was chosen',
      );
      expect(result, isNull);
    });

    testWidgets('dismissing the sheet chooses nothing', (tester) async {
      StartChoice? result;
      var called = false;
      await tester.pumpWidget(
        harness(
          starter((c) {
            called = true;
            result = c;
          }),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('startOptionsCancel')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull, reason: 'nothing queued may be consumed by this');
    });
  });

  group('the start sheet, with Pro', () {
    testWidgets('the preference on offers both, multitasking first', (
      tester,
    ) async {
      capability
        ..override = EntitlementOverride.forcePro
        ..preference = true;
      StartChoice? result;
      await tester.pumpWidget(harness(starter((c) => result = c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(keepUsingApp, findsOneWidget);
      expect(lockedOption, findsNothing);
      expect(
        tester.getCenter(keepUsingApp).dy,
        lessThan(tester.getCenter(inBrowser).dy),
        reason: 'what will actually happen is offered first',
      );
      expect(
        inBrowser,
        findsOneWidget,
        reason: 'watching it is still on the table',
      );

      await tester.tap(keepUsingApp);
      await tester.pumpAndSettle();
      expect(result, StartChoice.keepUsingApp);
    });

    testWidgets('the preference off asks instead of assuming', (tester) async {
      capability.override = EntitlementOverride.forcePro;
      StartChoice? result;
      await tester.pumpWidget(harness(starter((c) => result = c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(keepUsingApp, findsNothing, reason: 'not silently on');
      expect(lockedOption, findsNothing, reason: 'and not silently Free');
      expect(enableAndStart, findsOneWidget);

      await tester.tap(enableAndStart);
      await tester.pumpAndSettle();
      expect(result, StartChoice.enableAndKeepUsingApp);
    });
  });

  group('the leave sheet', () {
    Widget leaver(LeaveGate gate, void Function(LeaveChoice?) onResult) =>
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              final choice = await showLeaveBrowserSheet(
                context: context,
                ref: ref,
                gate: gate,
                progressLine: 'Entry 3 of 8 · 12 images',
              );
              onResult(choice);
            },
            child: const Text('leave'),
          ),
        );

    testWidgets('Free is offered stay, pause and leave, and Pro', (
      tester,
    ) async {
      LeaveChoice? result;
      await tester.pumpWidget(
        harness(leaver(LeaveGate.askFree, (c) => result = c)),
      );
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('leaveStay')), findsOneWidget);
      expect(find.byKey(const ValueKey('leavePauseAndLeave')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaveLearnAboutPro')), findsOneWidget);
      expect(
        find.text('Entry 3 of 8 · 12 images'),
        findsOneWidget,
        reason: 'what is at stake is on screen before the choice',
      );
      expect(
        find.textContaining('nothing saved so far is lost'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('leavePauseAndLeave')));
      await tester.pumpAndSettle();
      expect(result, LeaveChoice.pauseAndLeave);
    });

    testWidgets('Pro with the preference off is told about the next task', (
      tester,
    ) async {
      capability.override = EntitlementOverride.forcePro;
      await tester.pumpWidget(
        harness(leaver(LeaveGate.askProPreferenceOff, (_) {})),
      );
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('leaveLearnAboutPro')), findsNothing);
      expect(
        find.byKey(const ValueKey('leaveEnableForNextTime')),
        findsOneWidget,
      );
      expect(
        find.textContaining('applies to the next check or save'),
        findsOneWidget,
        reason:
            'a task keeps the screen it started with, and the sheet says so '
            'rather than pretending the setting takes effect now',
      );

      await tester.tap(find.byKey(const ValueKey('leaveEnableForNextTime')));
      await tester.pumpAndSettle();

      expect(capability.preference, isTrue);
      expect(
        await db.setting(ForegroundMultitasking.settingKey),
        'true',
        reason: 'applied and persisted, in one place',
      );
      expect(
        find.byKey(const ValueKey('leaveStay')),
        findsOneWidget,
        reason: 'the sheet stays: the question it asked is still unanswered',
      );
    });

    testWidgets('dismissing the leave sheet means stay', (tester) async {
      LeaveChoice? result;
      var called = false;
      await tester.pumpWidget(
        harness(
          leaver(LeaveGate.askFree, (c) {
            called = true;
            result = c;
          }),
        ),
      );
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('leave'))).pop();
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(
        result,
        isNull,
        reason:
            'walking away from a question about work in flight is never '
            'permission to strand it',
      );
    });
  });

  group('the Settings row', () {
    /// The screen is a long list on a phone-sized surface. A tall test view is
    /// the least intrusive way to reach the row without scripting a scroll in
    /// three separate tests.
    void tallView(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 2400);
      addTearDown(tester.view.reset);
    }

    testWidgets('without Pro it is locked, tappable, and keeps the choice', (
      tester,
    ) async {
      // A preference stored while the user had Pro.
      tallView(tester);
      capability.preference = true;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(const KeepWorkingSettingRow()));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('settingsKeepWorking'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsNothing,
        reason: 'a switch that refuses to move is a control that lies',
      );
      final node = tester.getSemantics(row);
      expect(node.label, contains('Requires Pro'));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('A Pro capability'), findsOneWidget);
      expect(
        capability.preference,
        isTrue,
        reason: 'the stored preference is never discarded by being locked',
      );
      expect(
        capability.enabled,
        isFalse,
        reason: 'but it does not take effect',
      );
      handle.dispose();
    });

    testWidgets('with Pro it is a working switch that persists', (
      tester,
    ) async {
      tallView(tester);
      capability.override = EntitlementOverride.forcePro;
      await tester.pumpWidget(harness(const KeepWorkingSettingRow()));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('settingsKeepWorking'));
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(capability.preference, isTrue);
      expect(capability.enabled, isTrue);
      expect(await db.setting(ForegroundMultitasking.settingKey), 'true');
      expect(
        find.textContaining('Nothing runs in the background'),
        findsWidgets,
        reason: 'the foreground-only limit is in the enabled copy too',
      );
    });

    testWidgets('the internal override changes the row, live', (tester) async {
      tallView(tester);
      await tester.pumpWidget(harness(const KeepWorkingSettingRow()));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('settingsKeepWorking'));
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsNothing,
      );

      capability.override = EntitlementOverride.forcePro;
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsOneWidget,
      );
    });
  });
}
