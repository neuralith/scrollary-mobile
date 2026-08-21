import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/features/save_scope_sheet.dart';
import 'package:web_reader/save/size_estimate.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/manifest.dart';

/// The three-choice range sheet: exactly three options, typed counts with
/// validation, the disk refusal in front of everything — and the two launches
/// the range can be given to, in the sheet itself (D58).
void main() {
  Widget host({
    required void Function(SaveRangeChoice?) onResult,
    int? free = 8 * 1024 * 1024 * 1024,
    String? busyLabel,
    CaptureCapabilities capabilities = const CaptureCapabilities.unanalysed(),
    CaptureMode? preferredMode,
    bool canRemember = false,
    CollectionSizeHistory sizeHistory = const CollectionSizeHistory.empty(),
    TextScaler textScale = TextScaler.noScaling,
  }) => MaterialApp(
    // Above the Navigator, so the sheet's own route inherits it too.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScale),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await showSaveRangeSheet(
              context: context,
              config: const SaveConfig(),
              deviceStorage: _FixedStorage(free),
              currentTitle: 'Foo Entry 137',
              busyLabel: busyLabel,
              capabilities: capabilities,
              preferredMode: preferredMode,
              canRemember: canRemember,
              sizeHistory: sizeHistory,
            );
            onResult(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The narrowest phone the design supports: both actions must fit here.
  void narrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// A phone-sized surface. With the count field open the sheet is taller than
  /// the test default, and the launches live below it.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Finder countField() => find.byKey(const ValueKey('saveCountField'));
  Finder countOk() => find.byKey(const ValueKey('saveCountOk'));

  /// The number the field is holding — '' when nothing is entered.
  String shownCount(WidgetTester tester) =>
      tester.widget<TextField>(countField()).controller!.text;

  /// Types a number the way a person does: into the field, on the platform's
  /// own keyboard, replacing whatever was there.
  Future<void> typeCount(WidgetTester tester, String digits) async {
    await tester.enterText(countField(), digits);
    await tester.pumpAndSettle();
  }

  /// Presses the sheet's own OK — the way out of a keyboard iOS gives no
  /// return key of its own.
  Future<void> confirmCount(WidgetTester tester) async {
    await tester.ensureVisible(countOk());
    await tester.pumpAndSettle();
    await tester.tap(countOk());
    await tester.pumpAndSettle();
  }

  /// Chooses the typed-count range on an already-open sheet.
  Future<void> chooseCount(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Number of entries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number of entries'));
    await tester.pumpAndSettle();
  }

  testWidgets('exactly the two choices, no count presets', (tester) async {
    await tester.pumpWidget(host(onResult: (_) {}));
    await open(tester);

    expect(find.text('Current entry'), findsOneWidget);
    expect(find.text('Number of entries'), findsOneWidget);
    // No open-ended range. It was bounded by a ceiling the user never saw,
    // and — with no field to type one into — it passed a count of 1 and saved
    // exactly one entry.
    expect(find.text('Until the end'), findsNothing);
    expect(find.textContaining('safety limit'), findsNothing);
    expect(find.textContaining('3 entries'), findsNothing);
    expect(find.textContaining('5 entries'), findsNothing);
    expect(find.textContaining('Next 3'), findsNothing);
    expect(find.textContaining('Next 5'), findsNothing);
  });

  group('the two launches', () {
    testWidgets('both are offered, in the sheet, with no second drawer', (
      tester,
    ) async {
      narrow(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);

      expect(find.byKey(const ValueKey('saveAddToQueue')), findsOneWidget);
      expect(find.byKey(const ValueKey('saveStartNow')), findsOneWidget);
      expect(find.byKey(const ValueKey('saveLaunchExplainer')), findsOneWidget);
      // Both fit, side by side, at 320pt.
      final queue = tester.getRect(
        find.byKey(const ValueKey('saveAddToQueue')),
      );
      final start = tester.getRect(find.byKey(const ValueKey('saveStartNow')));
      expect(queue.right, lessThanOrEqualTo(start.left));
      expect(start.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a range does not close the sheet or ask again', (
      tester,
    ) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await open(tester);

      await tester.ensureVisible(find.text('Number of entries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number of entries'));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'choosing a range decides nothing yet');
      expect(find.text('Number of entries'), findsOneWidget);
      expect(find.byKey(const ValueKey('saveStartNow')), findsOneWidget);
      // No queue/start question anywhere but here.
      expect(find.text('Start queued saves?'), findsNothing);
    });

    testWidgets('Add to Queue returns the range with the queue intent', (
      tester,
    ) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await open(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();

      expect(result?.mode, SaveScope.currentPageOnly);
      expect(result?.action, SaveSheetAction.addToQueue);
    });

    testWidgets('Start Save returns the range with the direct intent', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await open(tester);

      await chooseCount(tester);
      await typeCount(tester, '150');
      await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();

      expect(result?.mode, SaveScope.fixedCount);
      expect(result?.count, 150, reason: 'the number the user typed');
      expect(result?.action, SaveSheetAction.startNow);
    });

    testWidgets('the count field names the ceiling it will accept', (
      tester,
    ) async {
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);
      expect(
        find.textContaining('up to ${const SaveConfig().maxEntriesPerRun}'),
        findsOneWidget,
      );
    });
  });

  group('when the Browser is already busy', () {
    testWidgets('direct start is replaced, queueing is not', (tester) async {
      narrow(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(
        host(
          onResult: (r) => result = r,
          busyLabel: 'A save is using the Browser',
        ),
      );
      await open(tester);

      expect(find.byKey(const ValueKey('saveStartNow')), findsNothing);
      expect(find.byKey(const ValueKey('saveViewActiveTask')), findsOneWidget);
      expect(find.byKey(const ValueKey('saveBusyNote')), findsOneWidget);
      expect(
        find.textContaining('A save is using the Browser'),
        findsOneWidget,
      );

      // Queueing is still a real option — it starts nothing.
      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      expect(result?.action, SaveSheetAction.addToQueue);
    });

    testWidgets('View active task is its own outcome', (tester) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(
        host(onResult: (r) => result = r, busyLabel: 'An update check'),
      );
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveViewActiveTask')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveViewActiveTask')));
      await tester.pumpAndSettle();

      expect(result?.action, SaveSheetAction.viewActiveTask);
    });
  });

  testWidgets('typed count is validated for both actions', (tester) async {
    phone(tester);

    SaveRangeChoice? result;
    await tester.pumpWidget(host(onResult: (r) => result = r));
    await open(tester);
    await chooseCount(tester);

    // Zero refuses — and the sheet stays open, error visible.
    await typeCount(tester, '0');
    await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveStartNow')));
    await tester.pump();
    expect(find.textContaining('1 or more'), findsOneWidget);
    expect(result, isNull);
    expect(find.byKey(const ValueKey('saveAddToQueue')), findsOneWidget);

    // The same validation guards the queue action.
    await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
    await tester.pump();
    expect(result, isNull);

    // Excessive refuses, naming the bound.
    await typeCount(tester, '9999');
    await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveStartNow')));
    await tester.pump();
    expect(
      find.textContaining('${const SaveConfig().maxEntriesPerRun}'),
      findsWidgets,
    );
    expect(result, isNull);

    // A valid number shows the summary and returns with the chosen launch.
    await typeCount(tester, '8');
    expect(find.textContaining('Save 8 items'), findsOneWidget);
    expect(find.textContaining('Foo Entry 137'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveStartNow')));
    await tester.pumpAndSettle();
    expect(result?.mode, SaveScope.fixedCount);
    expect(result?.count, 8);
    expect(result?.action, SaveSheetAction.startNow);
  });

  /// The count is typed on the platform's own numeric keyboard.
  ///
  /// The sheet used to draw its own keypad, because iOS renders
  /// `TextInputType.number` as a pad with **no return key at all**. That is a
  /// real limitation, but it only means the sheet must supply the way out — not
  /// that it must supply the keys. So the field is a real text input, the
  /// keyboard is the system's on both platforms, and the app owns exactly one
  /// affordance the platform does not give it: OK.
  group('the count field', () {
    Future<void> openCount(WidgetTester tester) async {
      await open(tester);
      await chooseCount(tester);
    }

    testWidgets('choosing the range opens the system numeric keyboard', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);

      // Not before: with no number to type there is no field and no keyboard.
      expect(countField(), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);

      await chooseCount(tester);
      expect(countField(), findsOneWidget);

      // A real text input, asking the platform for its number pad — not a
      // grid of buttons the app drew.
      final field = tester.widget<TextField>(countField());
      expect(field.keyboardType, TextInputType.number);
      expect(field.autofocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.testTextInput.setClientArgs!['inputType']['name'],
        'TextInputType.number',
        reason: 'the platform is asked for digits',
      );

      // The keys the app used to draw are gone.
      expect(find.byKey(const ValueKey('saveCountKeypad')), findsNothing);
      for (final d in [for (var i = 0; i <= 9; i++) '$i']) {
        expect(find.byKey(ValueKey('keypadKey_$d')), findsNothing, reason: d);
      }
      expect(find.byKey(const ValueKey('keypadDelete')), findsNothing);
      expect(find.byKey(const ValueKey('keypadOk')), findsNothing);
    });

    testWidgets('Done is asked for, and confirms where the platform draws it', (
      tester,
    ) async {
      // Android's IME draws the action key and honours this; iOS's number pad
      // has none, which is why OK exists as well.
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      expect(
        tester.widget<TextField>(countField()).textInputAction,
        TextInputAction.done,
      );
      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.done',
      );

      await typeCount(tester, '14');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(shownCount(tester), '14', reason: 'the value is kept');
      expect(tester.testTextInput.isVisible, isFalse, reason: 'and dismissed');
      // Confirming a number is not authorising a save.
      expect(result, isNull);
    });

    testWidgets('the field takes digits and nothing else', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      // A decimal point cannot survive, however it arrives — typed on an IME
      // that offers one, dictated, or pasted.
      await typeCount(tester, '3.5');
      expect(shownCount(tester), '35');

      await typeCount(tester, '-7');
      expect(shownCount(tester), '7');

      await typeCount(tester, '1 2');
      expect(shownCount(tester), '12');

      await typeCount(tester, 'twelve');
      expect(shownCount(tester), '', reason: 'letters are not a number');

      // One digit more than the ceiling needs, so a number over the limit can
      // still be typed and answered — and nothing longer can be.
      await typeCount(tester, '99999999');
      expect(shownCount(tester), '9999');
    });

    testWidgets('OK keeps the value, dismisses the keyboard, starts nothing', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      await typeCount(tester, '12');
      expect(countOk(), findsOneWidget, reason: 'offered while typing');
      await confirmCount(tester);

      expect(shownCount(tester), '12', reason: 'the value is kept');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(countOk(), findsNothing, reason: 'nothing left to confirm');
      // Confirming a number is not authorising a save.
      expect(result, isNull);
      expect(find.byKey(const ValueKey('saveStartNow')), findsOneWidget);
      expect(find.byKey(const ValueKey('saveAddToQueue')), findsOneWidget);
    });

    testWidgets('OK normalises a leading zero, and only on confirmation', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      // Not while typing: rewriting the field under the cursor as digits
      // arrive is how a text field starts swallowing keystrokes.
      await typeCount(tester, '004');
      expect(shownCount(tester), '004');

      // 004 is 4, said once, when the number is accepted.
      await confirmCount(tester);
      expect(shownCount(tester), '4');
    });

    testWidgets('tapping the field again brings the keyboard back', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      await typeCount(tester, '6');
      await confirmCount(tester);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(countField());
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(countOk(), findsOneWidget);
    });

    testWidgets('Start Save after OK carries the confirmed count', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      await typeCount(tester, '12');
      await confirmCount(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();

      expect(result?.mode, SaveScope.fixedCount);
      expect(result?.count, 12);
      expect(result?.action, SaveSheetAction.startNow);
    });

    testWidgets('Add to Queue after OK carries the confirmed count', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      await typeCount(tester, '9');
      await confirmCount(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();

      expect(result?.mode, SaveScope.fixedCount);
      expect(result?.count, 9);
      expect(result?.action, SaveSheetAction.addToQueue);
    });

    testWidgets('OK answers a bad number where it was typed', (tester) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      // Nothing entered at all.
      await typeCount(tester, '');
      await confirmCount(tester);
      expect(find.textContaining('1 or more'), findsOneWidget);
      expect(result, isNull);
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'the keys to fix it stay under the thumb',
      );
      expect(countOk(), findsOneWidget);

      // Zero, then over the ceiling — the same two rules the launches apply.
      await typeCount(tester, '0');
      await confirmCount(tester);
      expect(find.textContaining('1 or more'), findsOneWidget);

      await typeCount(tester, '9999');
      await confirmCount(tester);
      expect(
        find.textContaining('At most ${const SaveConfig().maxEntriesPerRun}'),
        findsOneWidget,
      );
      expect(result, isNull);

      // A number that is fine clears the stale complaint and puts the
      // keyboard away.
      await typeCount(tester, '4');
      expect(find.textContaining('At most'), findsNothing);
      await confirmCount(tester);
      expect(find.textContaining('1 or more'), findsNothing);
      expect(find.textContaining('At most'), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(shownCount(tester), '4');
    });

    testWidgets('a refused launch calls the keyboard back to the number', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      await typeCount(tester, '0');
      await confirmCount(tester);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'nothing started');
      expect(find.textContaining('1 or more'), findsOneWidget);
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'answered where it was typed',
      );
    });

    testWidgets('switching range puts the keyboard away and still switches', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      // Leave a complaint on screen, then walk away from the range it is about.
      await typeCount(tester, '0');
      await confirmCount(tester);
      expect(find.textContaining('1 or more'), findsOneWidget);

      await tester.tap(find.text('Current entry'));
      await tester.pumpAndSettle();
      expect(countField(), findsNothing);
      expect(countOk(), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        find.textContaining('1 or more'),
        findsNothing,
        reason: 'not about the range being used any more',
      );
      expect(find.text('Current entry'), findsOneWidget);
    });

    testWidgets('switching back keeps the number that was entered', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);

      await typeCount(tester, '37');
      await confirmCount(tester);

      await tester.tap(find.text('Current entry'));
      await tester.pumpAndSettle();
      await chooseCount(tester);
      expect(shownCount(tester), '37', reason: 'the sheet does not forget');

      await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      expect(result?.count, 37);
    });

    testWidgets('the current entry range still saves exactly one', (
      tester,
    ) async {
      phone(tester);
      SaveRangeChoice? result;
      await tester.pumpWidget(host(onResult: (r) => result = r));
      await openCount(tester);
      await typeCount(tester, '37');
      await confirmCount(tester);

      await tester.tap(find.text('Current entry'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveStartNow')));
      await tester.pumpAndSettle();

      expect(result?.mode, SaveScope.currentPageOnly);
      expect(result?.count, 1, reason: 'the typed number is not in play');
    });

    testWidgets('the field and OK fit the narrowest phone', (tester) async {
      narrow(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      for (final finder in [countField(), countOk()]) {
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      // A target a thumb can actually hit.
      expect(tester.getRect(countOk()).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the field and OK stay above the keyboard when it arrives', (
      tester,
    ) async {
      // The real sequence on a short screen: the field takes focus, and the
      // keyboard slides up afterwards. The sheet is far taller than what is
      // left, so both the number and the way out of the keyboard have to
      // survive the viewport shrinking under them.
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);

      // Now the keyboard: 336 of the 640 belong to it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();

      const keyboardTop = 640.0 - 336.0;
      final field = tester.getRect(countField());
      final ok = tester.getRect(countOk());
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(keyboardTop));
      expect(ok.bottom, lessThanOrEqualTo(keyboardTop));
      expect(
        ok.top,
        greaterThanOrEqualTo(field.bottom),
        reason: 'pinned under the body, not floating over the number',
      );
    });

    testWidgets('large text does not overflow the field or OK', (tester) async {
      narrow(tester);
      await tester.pumpWidget(
        host(onResult: (_) {}, textScale: const TextScaler.linear(3.0)),
      );
      await openCount(tester);

      expect(countOk(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');

      // It still works at that size.
      await typeCount(tester, '5');
      expect(shownCount(tester), '5');
      await confirmCount(tester);
      expect(shownCount(tester), '5');
    });

    testWidgets('the field and OK carry semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await openCount(tester);
      await typeCount(tester, '12');

      // A real text field, announced as one, with the number as its value —
      // which also gets dictation, an external keyboard and paste for free.
      SemanticsData fieldData() => tester
          .getSemantics(
            find.descendant(
              of: countField(),
              matching: find.byType(EditableText),
            ),
          )
          .getSemanticsData();

      final data = fieldData();
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.label, contains('How many new entries'));
      expect(data.value, '12', reason: 'the number is announced');

      // Two letters do not say what they do, so OK says it in a sentence.
      final ok = tester.getSemantics(countOk());
      expect(ok.label, 'OK, use this number');
      expect(
        ok.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'a glyph a screen reader cannot operate is not a control',
      );

      // The complaint is attached to the field, not shouted somewhere else.
      await typeCount(tester, '');
      await confirmCount(tester);
      expect(fieldData().hint, contains('1 or more'));
      semantics.dispose();
    });
  });

  /// The estimate line, as the sheet is showing it.
  String estimateLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('saveEstimatedSize')))
      .data!;

  /// A finished image entry of [bytes], the only kind of row the estimate is
  /// allowed to learn from.
  Entry saved(int bytes, {String id = 'e', String status = 'complete'}) =>
      Entry(
        id: id,
        collectionId: 'c',
        title: 'Entry',
        sourceUrl: 'https://example.com/$id',
        urlKey: 'example.com/$id',
        host: 'example.com',
        contentKind: 'imageDominant',
        contentKindConfidence: 'high',
        contentKindIsUserSet: false,
        artifactFormat: ArtifactFormat.imageSequence.name,
        saveStatus: status,
        contentPath: 'library/c/$id',
        detectedAssetCount: 10,
        storedAssetCount: 10,
        entryOrder: 1,
        byteSize: bytes,
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      );

  group('what it will cost', () {
    const mb = 1024 * 1024;

    testWidgets('a collection nothing was saved from shows a rough range', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);
      await chooseCount(tester);
      await typeCount(tester, '5');
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );

      // The example from the design: five entries, 3–20 MB each.
      expect(estimateLine(tester), contains('15–100 MB'));
      expect(estimateLine(tester), contains('rough'));
      // And never the old flat-constant answer, which was 250 MB for these
      // five and a full gigabyte for twenty.
      expect(estimateLine(tester), isNot(contains('GB')));
    });

    testWidgets('a collection with saved entries is measured, not guessed', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          sizeHistory: CollectionSizeHistory.fromEntries([
            for (var i = 0; i < 5; i++) saved(6 * mb, id: 'e$i'),
          ]),
        ),
      );
      await open(tester);
      await chooseCount(tester);
      await typeCount(tester, '5');
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );

      expect(estimateLine(tester), contains('30 MB'));
      expect(estimateLine(tester), contains('already saved here'));
    });

    testWidgets('the single-entry range is estimated too, and for one entry', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          sizeHistory: CollectionSizeHistory.fromEntries([
            for (var i = 0; i < 5; i++) saved(12 * mb, id: 'e$i'),
          ]),
        ),
      );
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );

      expect(estimateLine(tester), contains('12 MB'));
    });

    testWidgets('unusable rows are not history', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          sizeHistory: CollectionSizeHistory.fromEntries([
            saved(900 * mb, id: 'failed', status: 'failed'),
            saved(0, id: 'empty'),
          ]),
        ),
      );
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );

      // Falls back to the band rather than reporting 900 MB for one entry.
      expect(estimateLine(tester), contains('3–20 MB'));
      expect(estimateLine(tester), contains('rough'));
    });

    testWidgets('a number that does not validate shows no size at all', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);
      await chooseCount(tester);

      await typeCount(tester, '');
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );
      expect(estimateLine(tester), kSizeUnknownMessage);

      await typeCount(tester, '0');
      expect(estimateLine(tester), kSizeUnknownMessage);

      await typeCount(tester, '9999');
      expect(estimateLine(tester), kSizeUnknownMessage);
    });

    testWidgets('a count that genuinely is gigabytes says so', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          sizeHistory: CollectionSizeHistory.fromEntries([
            for (var i = 0; i < 5; i++) saved(10 * mb, id: 'e$i'),
          ]),
        ),
      );
      await open(tester);
      await chooseCount(tester);
      await typeCount(tester, '400');
      await tester.ensureVisible(
        find.byKey(const ValueKey('saveEstimatedSize')),
      );

      expect(estimateLine(tester), contains('3.9 GB'));
    });
  });

  testWidgets('insufficient space refuses before any choice', (tester) async {
    SaveRangeChoice? result;
    await tester.pumpWidget(
      host(onResult: (r) => result = r, free: 100 * 1024 * 1024),
    );
    await open(tester);

    expect(find.text('Not enough space'), findsOneWidget);
    expect(find.textContaining('not affected'), findsOneWidget);
    expect(find.text('Current entry'), findsNothing);
    await tester.ensureVisible(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  group('what to save', () {
    testWidgets('all three modes are shown, unavailable ones disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          capabilities: const CaptureCapabilities(
            content: ContentShape(
              kind: ContentKind.article,
              confidence: ShapeConfidence.high,
            ),
            available: {CaptureMode.textOnly},
            blocked: {
              CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
              CaptureMode.textAndImages: ModeBlockReason.noMeaningfulImages,
            },
            defaultMode: CaptureMode.textOnly,
          ),
        ),
      );
      await open(tester);

      // Present, not hidden — a missing option reads as a bug.
      for (final mode in CaptureMode.values) {
        expect(
          find.byKey(ValueKey('captureMode_${mode.name}')),
          findsOneWidget,
          reason: mode.name,
        );
      }
      // …and the unavailable ones say why.
      expect(
        find.textContaining('does not have enough full-size images'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No images were found inside the readable text'),
        findsOneWidget,
      );
    });

    testWidgets('the detected default is returned when nothing is tapped', (
      tester,
    ) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(
        host(
          onResult: (r) => result = r,
          capabilities: const CaptureCapabilities(
            content: ContentShape(kind: ContentKind.article),
            available: {CaptureMode.textOnly, CaptureMode.textAndImages},
            blocked: {},
            defaultMode: CaptureMode.textAndImages,
          ),
        ),
      );
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();

      expect(result?.captureMode, CaptureMode.textAndImages);
      expect(result?.captureModeIsUserSet, isFalse);
    });

    testWidgets('choosing a mode marks it as the user\'s own', (tester) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(
        host(
          onResult: (r) => result = r,
          capabilities: const CaptureCapabilities(
            content: ContentShape(kind: ContentKind.article),
            available: {CaptureMode.textOnly, CaptureMode.textAndImages},
            blocked: {},
            defaultMode: CaptureMode.textAndImages,
          ),
        ),
      );
      await open(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('captureMode_textOnly')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('captureMode_textOnly')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();

      expect(result?.captureMode, CaptureMode.textOnly);
      expect(result?.captureModeIsUserSet, isTrue);
    });

    testWidgets('a video page with nothing readable cannot be launched', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          capabilities: const CaptureCapabilities(
            content: ContentShape(
              kind: ContentKind.videoDominant,
              confidence: ShapeConfidence.high,
            ),
            available: {},
            blocked: {
              CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
              CaptureMode.textOnly: ModeBlockReason.noReadableText,
              CaptureMode.textAndImages: ModeBlockReason.noReadableText,
            },
            videoDominant: true,
          ),
        ),
      );
      await open(tester);

      expect(find.byKey(const ValueKey('videoNotSavedNotice')), findsOneWidget);
      expect(
        find.textContaining('no readable text to save instead'),
        findsOneWidget,
      );
      // Queueing a save that is going to refuse would be a button that lies.
      final queue = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('saveAddToQueue')),
      );
      expect(queue.onPressed, isNull);
    });

    testWidgets('an unanalysed page offers everything and says so', (
      tester,
    ) async {
      await tester.pumpWidget(host(onResult: (_) {}));
      await open(tester);

      expect(find.textContaining('could not be analysed'), findsOneWidget);
      final queue = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('saveAddToQueue')),
      );
      expect(queue.onPressed, isNotNull);
    });

    testWidgets('an unclassified page says so plainly', (tester) async {
      await tester.pumpWidget(
        host(
          onResult: (_) {},
          capabilities: const CaptureCapabilities(
            content: ContentShape(
              kind: ContentKind.unknownWebContent,
              confidence: ShapeConfidence.low,
            ),
            available: {CaptureMode.imageSequence},
            blocked: {
              CaptureMode.textOnly: ModeBlockReason.noReadableText,
              CaptureMode.textAndImages: ModeBlockReason.noReadableText,
            },
            defaultMode: CaptureMode.imageSequence,
          ),
        ),
      );
      await open(tester);
      // Never "this looks like not something we could classify".
      expect(
        find.textContaining('did not say clearly what it is'),
        findsOneWidget,
      );
      expect(find.textContaining('This looks like'), findsNothing);
    });

    testWidgets('remembering a mode is not offered without a collection', (
      tester,
    ) async {
      await tester.pumpWidget(host(onResult: (_) {}, canRemember: false));
      await open(tester);
      expect(find.byKey(const ValueKey('rememberCaptureMode')), findsNothing);
    });

    testWidgets('remembering a mode is offered when there is one', (
      tester,
    ) async {
      await tester.pumpWidget(host(onResult: (_) {}, canRemember: true));
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('rememberCaptureMode')),
      );
      expect(find.byKey(const ValueKey('rememberCaptureMode')), findsOneWidget);
    });

    testWidgets('a remembered mode is carried back when it still applies', (
      tester,
    ) async {
      SaveRangeChoice? result;
      await tester.pumpWidget(
        host(
          onResult: (r) => result = r,
          canRemember: true,
          preferredMode: CaptureMode.textOnly,
          capabilities: const CaptureCapabilities(
            content: ContentShape(kind: ContentKind.article),
            available: {CaptureMode.textOnly, CaptureMode.textAndImages},
            blocked: {},
            defaultMode: CaptureMode.textAndImages,
          ),
        ),
      );
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveAddToQueue')));
      await tester.pumpAndSettle();

      // The preference wins over the detected default, and the sheet reports
      // that it should stay remembered.
      expect(result?.captureMode, CaptureMode.textOnly);
      expect(result?.rememberForCollection, isTrue);
    });
  });
}

class _FixedStorage extends DeviceStorage {
  _FixedStorage(this.free);
  final int? free;

  @override
  Future<int?> freeBytes() async => free;
}
