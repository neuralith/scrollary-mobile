/// The Collection picker: the user decides identity, and only the user.
///
/// The property under test is the one the save flow depends on — **nothing is
/// selected without a tap**. A suggested title that exactly matches a
/// Collection's name still selects nothing; it only fills the filter, which is
/// what makes the row easy to find rather than easy to land on by accident.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/collection_picker.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// The choice the picker resolved to, and whether it has resolved at all.
  /// Both matter: "nothing chosen yet" and "chosen null" are different states.
  CollectionChoice? choice;
  var closed = false;

  Future<void> openPicker(
    WidgetTester tester, {
    String? suggestedTitle,
    bool allowCreate = true,
    bool confirmNameHere = true,
    String? attachingSourceHost,
  }) async {
    choice = null;
    closed = false;
    await tester.pumpWidget(
      h.app(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  choice = await showCollectionPicker(
                    context,
                    ref,
                    suggestedTitle: suggestedTitle,
                    allowCreate: allowCreate,
                    confirmNameHere: confirmNameHere,
                    attachingSourceHost: attachingSourceHost,
                  );
                  closed = true;
                },
                child: const Text('open the picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tapAndPump(tester, find.text('open the picker'));
  }

  Future<(String alpha, String beta)> seedTwo() async {
    final root = await h.root();
    final alpha = await h.collection('Alpha notes', folderId: root.id);
    final beta = await h.collection('Beta letters', folderId: root.id);
    return (alpha.id, beta.id);
  }

  screenTest('lists every collection in the library', (tester) async {
    await seedTwo();
    await openPicker(tester);

    await pumpUntil(tester, find.text('Alpha notes'));
    expect(find.text('Beta letters'), findsOneWidget);
  });

  screenTest('filters by what is typed, and matches nothing silently', (
    tester,
  ) async {
    await seedTwo();
    await openPicker(tester);
    await pumpUntil(tester, find.text('Alpha notes'));

    await tester.enterText(
      find.byKey(const ValueKey('collectionPickerFilter')),
      'beta',
    );
    await tester.pump();

    expect(find.text('Alpha notes'), findsNothing);
    expect(find.text('Beta letters'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('collectionPickerFilter')),
      'gamma',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('collectionPickerEmpty')), findsOneWidget);
    expect(
      closed,
      isFalse,
      reason: 'an empty filter result is an answer, not a dismissal',
    );
  });

  screenTest('a suggested title fills the filter and selects nothing', (
    tester,
  ) async {
    final (alphaId, _) = await seedTwo();
    // The exact name of a collection the user already has: the strongest
    // possible case for a "helpful" auto-match, and the app must still ask.
    await openPicker(tester, suggestedTitle: 'Alpha notes');
    await pumpUntil(tester, find.text('Alpha notes'));

    expect(
      find.widgetWithText(TextField, 'Alpha notes'),
      findsOneWidget,
      reason: 'the suggestion pre-fills the filter',
    );
    expect(closed, isFalse, reason: 'nothing was chosen for the user');
    expect(choice, isNull);

    await tapAndPump(tester, find.byKey(ValueKey('collectionOption-$alphaId')));

    expect(closed, isTrue);
    expect(choice, isA<ExistingCollectionChoice>());
    final picked = choice! as ExistingCollectionChoice;
    expect(picked.id, alphaId);
    expect(picked.name, 'Alpha notes');
  });

  screenTest('creating one returns the typed name, pre-filled from the '
      'suggestion', (tester) async {
    await seedTwo();
    await openPicker(tester, suggestedTitle: 'Gamma tales');
    await pumpUntil(tester, find.byKey(const ValueKey('collectionPickerNew')));

    await tapAndPump(tester, find.byKey(const ValueKey('collectionPickerNew')));

    final field = find.byKey(const ValueKey('collectionNameField'));
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Gamma tales',
      reason: 'the detected title is a suggestion the user may correct',
    );

    await tester.enterText(field, 'Gamma tales, corrected');
    await tester.pump();
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('collectionCreateConfirm')),
    );

    expect(choice, isA<NewCollectionChoice>());
    expect((choice! as NewCollectionChoice).name, 'Gamma tales, corrected');
    expect(
      await h.collections.inFolder((await h.root()).id),
      hasLength(2),
      reason: 'the picker chooses; it does not write',
    );
  });

  screenTest('hands the suggestion straight back when a sheet follows', (
    tester,
  ) async {
    await seedTwo();
    await openPicker(
      tester,
      suggestedTitle: 'Gamma tales',
      confirmNameHere: false,
    );
    await pumpUntil(tester, find.byKey(const ValueKey('collectionPickerNew')));

    await tapAndPump(tester, find.byKey(const ValueKey('collectionPickerNew')));

    // No screen of its own for one field: the sheet that follows already
    // prints this name in its header and is where it is confirmed (V2-D57).
    expect(find.byKey(const ValueKey('collectionNameField')), findsNothing);
    expect(closed, isTrue);
    expect(choice, isA<NewCollectionChoice>());
    expect((choice! as NewCollectionChoice).name, 'Gamma tales');
    expect(
      await h.collections.inFolder((await h.root()).id),
      hasLength(2),
      reason: 'the picker chooses; it does not write',
    );
  });

  screenTest('the list is still where a new one is started from', (
    tester,
  ) async {
    final (alphaId, _) = await seedTwo();
    await openPicker(
      tester,
      suggestedTitle: 'Alpha notes',
      confirmNameHere: false,
    );
    await pumpUntil(tester, find.text('Alpha notes'));

    // The collections the user already holds are visible before another is
    // started, whichever way the create row answers: skipping the list is how
    // a work held from a second site quietly becomes a duplicate.
    expect(find.byKey(ValueKey('collectionOption-$alphaId')), findsOneWidget);
    expect(find.byKey(const ValueKey('collectionPickerNew')), findsOneWidget);
    expect(closed, isFalse);
  });

  screenTest('the site an existing collection would gain is named on the '
      'rows that would gain it', (tester) async {
    // Both answers here do something to this site, and only *New collection*
    // said so. The list is the *add this site as another source* operation,
    // and a list of names alone does not read as one.
    final (alphaId, _) = await seedTwo();
    await openPicker(tester, attachingSourceHost: 'reading.example.com');
    await pumpUntil(tester, find.text('Alpha notes'));

    expect(
      find.byKey(const ValueKey('collectionPickerSourceNote')),
      findsOneWidget,
    );
    expect(find.textContaining('reading.example.com'), findsOneWidget);

    await tapAndPump(tester, find.byKey(ValueKey('collectionOption-$alphaId')));
    expect((choice! as ExistingCollectionChoice).id, alphaId);
  });

  screenTest('and is not named where picking one attaches no site', (
    tester,
  ) async {
    // Adopting a standalone Entry moves that Entry into a Collection; no site
    // is attached, so the sentence would be a claim about something that does
    // not happen.
    await seedTwo();
    await openPicker(tester, allowCreate: false);
    await pumpUntil(tester, find.text('Alpha notes'));

    expect(
      find.byKey(const ValueKey('collectionPickerSourceNote')),
      findsNothing,
    );
  });

  screenTest('cannot create one where creating one would be wrong', (
    tester,
  ) async {
    await seedTwo();
    await openPicker(tester, allowCreate: false);
    await pumpUntil(tester, find.text('Alpha notes'));

    expect(find.byKey(const ValueKey('collectionPickerNew')), findsNothing);
  });

  screenTest('says so honestly when there is nothing to pick', (tester) async {
    await h.root();
    await openPicker(tester, allowCreate: false);

    await pumpUntil(
      tester,
      find.byKey(const ValueKey('collectionPickerEmpty')),
    );
    expect(
      find.textContaining('You have no collections yet'),
      findsOneWidget,
      reason: 'an empty library is a state, not a blank sheet',
    );
  });
}
