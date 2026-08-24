/// The two questions the reader asks on the way out of a finished Entry.
///
/// `forward_transition_test.dart` proves what each *answer* does; this proves
/// the dialogs actually offer those answers, and that the destructive one is
/// never taken without an explicit tap.
///
/// The consequence note is the reason this file exists. Where a Collection
/// already frees a finished Entry's files, saying "this one is finished" is
/// also what frees them — and that has to be on screen *before* the tap, not
/// in a notice afterwards, because there is deliberately no Undo (V2-D59).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/cleanup_dialogs.dart';
import 'package:web_reader/reading_v2/finished_cleanup.dart';
import 'package:web_reader/reading_v2/forward_transition.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

void main() {
  /// Whatever the dialog returned, once it has closed.
  Object? answer;
  var answered = false;

  setUp(() {
    answer = null;
    answered = false;
  });

  Future<void> openCompletion(
    WidgetTester tester, {
    required bool willRemoveCopy,
    int percentRead = 94,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await showEntryCompletionDialog(
                    context: context,
                    entryName: 'Part 7',
                    percentRead: percentRead,
                    willRemoveCopy: willRemoveCopy,
                  );
                  answered = true;
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  Future<void> openRule(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await showFinishedCleanupDialog(
                    context: context,
                    collectionName: 'Serial Alpha',
                  );
                  answered = true;
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  group('the completion question', () {
    testWidgets('offers all three answers, and says where the reader is', (
      tester,
    ) async {
      await openCompletion(tester, willRemoveCopy: false);

      expect(
        find.byKey(const ValueKey('entryCompletionDialog')),
        findsOneWidget,
      );
      expect(find.text('Part 7'), findsOneWidget);
      expect(find.textContaining('94%'), findsOneWidget);
      for (final key in [
        'entryCompletion-complete',
        'entryCompletion-continueWithout',
        'entryCompletion-cancel',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
    });

    testWidgets('names the consequence only when there is one', (tester) async {
      const note = ValueKey('entryCompletionConsequence');

      await openCompletion(tester, willRemoveCopy: true);
      expect(find.byKey(note), findsOneWidget);
      expect(find.textContaining('stays in your library'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('entryCompletion-cancel')));
      await tester.pumpAndSettle();

      // No rule yet: the note would be a claim about a decision nobody has
      // made, and the rule question comes next and explains itself.
      await openCompletion(tester, willRemoveCopy: false);
      expect(find.byKey(note), findsNothing);
    });

    testWidgets('each button is the answer it is labelled', (tester) async {
      for (final (key, expected) in [
        ('entryCompletion-complete', EntryCompletionChoice.completeAndContinue),
        (
          'entryCompletion-continueWithout',
          EntryCompletionChoice.continueWithout,
        ),
        ('entryCompletion-cancel', EntryCompletionChoice.cancel),
      ]) {
        await openCompletion(tester, willRemoveCopy: true);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(answered, isTrue);
        expect(answer, expected);
      }
    });

    testWidgets('dismissing it is the same as Cancel', (tester) async {
      await openCompletion(tester, willRemoveCopy: true);
      // The barrier: what a tap outside the dialog does.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(answered, isTrue);
      expect(
        answer,
        isNull,
        reason: 'and null is read as cancel — nothing moves, nothing changes',
      );
    });
  });

  group('the collection question', () {
    testWidgets('preselects Remove, and does not take it until Save', (
      tester,
    ) async {
      await openRule(tester);

      expect(
        find.byKey(const ValueKey('finishedCleanupDialog')),
        findsOneWidget,
      );
      expect(find.text('Serial Alpha'), findsOneWidget);
      expect(find.text('Remove after finishing'), findsOneWidget);
      expect(find.text('Keep downloaded'), findsOneWidget);

      // Preselected — one radio is on, and it is that one.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('finishedCleanup-remove')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(
        answered,
        isFalse,
        reason:
            'preselected is not chosen — the destructive answer is not '
            'taken by a dialog appearing',
      );
    });

    testWidgets('Save choice returns the selected rule, not the preselected '
        'one', (tester) async {
      await openRule(tester);
      await tester.tap(find.byKey(const ValueKey('finishedCleanup-keep')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveFinishedCleanup')));
      await tester.pumpAndSettle();

      expect(answer, FinishedCleanupRule.keep);
    });

    testWidgets('dismissing it stores nothing', (tester) async {
      await openRule(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(answered, isTrue);
      expect(answer, isNull, reason: 'null keeps the files and stores no rule');
    });
  });
}
