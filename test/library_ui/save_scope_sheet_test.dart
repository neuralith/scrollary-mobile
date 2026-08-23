/// The recovered count sheet.
///
/// This interaction was device-tested in V1 and is under test here so it stays
/// recovered rather than redesigned: digits and nothing else, a blank and a
/// zero refused where they were typed, the ceiling stated and enforced, and an
/// OK that confirms the number without starting anything.
///
/// The two counted ranges are here for the same reason: *Entries from here*
/// counts on the Source and reads it forward for what the library is missing,
/// *Entries already in your library* counts on the library and opens nothing,
/// and which one the sheet returns is the difference between an app that opens
/// someone's site and one that does not.
///
/// The bound itself is not this file's to assert twice — `SaveLimits.forScope`
/// owns it — but *that the sheet builds its limits through it* is, because a
/// range whose real ceiling lived somewhere the user could not see is the
/// thing CLAUDE.md forbids.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library_ui/save_scope_sheet.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  final ceiling = kDefaultSaveConfig.maxEntriesPerRun;

  SaveScopeChoice? chosen;
  var closed = false;

  Future<void> openSheet(WidgetTester tester) async {
    chosen = null;
    closed = false;
    await tester.pumpWidget(
      h.app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  chosen = await showSaveScopeSheet(
                    context,
                    collectionName: 'Alpha notes',
                  );
                  closed = true;
                },
                child: const Text('open the sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tapAndPump(tester, find.text('open the sheet'));
  }

  Finder countField() => find.byKey(const ValueKey('saveCountField'));

  Future<void> chooseTypedRange(WidgetTester tester) =>
      tapAndPump(tester, find.byKey(const ValueKey('saveScopeFromHere')));

  Future<void> chooseLibraryOnlyRange(WidgetTester tester) =>
      tapAndPump(tester, find.byKey(const ValueKey('saveScopeKnownOnly')));

  screenTest('states the ceiling in words before anything is typed', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.textContaining('up to $ceiling'), findsOneWidget);
    expect(
      find.textContaining('Queued downloads wait for Start'),
      findsOneWidget,
      reason: 'the queue never starts itself, and the sheet says so',
    );
  });

  screenTest('the typed count says what it counts, before it is typed into', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    expect(
      find.text('How many entries, counting this one?'),
      findsOneWidget,
      reason:
          'ten from entry 101 is 101 through 110, and a sheet that leaves '
          'that to be inferred has said the wrong thing to half its readers',
    );
    expect(
      find.textContaining('5 means this entry and the next four'),
      findsOneWidget,
      reason: 'said again in numbers, where the answer is being typed',
    );
    expect(
      find.textContaining('reads forward from this page'),
      findsOneWidget,
      reason: 'the count is a claim about the site, and the site is opened',
    );
    expect(find.textContaining('stop it at any point'), findsOneWidget);
  });

  screenTest('the typed count reads this site forward for what is missing', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);
    await tester.enterText(countField(), '10');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.maxEntries, 10);
    expect(chosen!.discoverMissing, isTrue);
  });

  screenTest('the quieter range keeps the library-only answer', (tester) async {
    await openSheet(tester);
    await chooseLibraryOnlyRange(tester);

    expect(
      countField(),
      findsOneWidget,
      reason: 'it is the same question, answered from the library',
    );
    expect(
      find.textContaining('this site is not opened'),
      findsOneWidget,
      reason: 'which is the whole difference, so it is the sentence shown',
    );
    expect(
      find.textContaining('5 means this entry and the next four'),
      findsOneWidget,
      reason: 'a count means the same thing whichever range answers it',
    );

    await tester.enterText(countField(), '6');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.maxEntries, 6);
    expect(chosen!.discoverMissing, isFalse);
  });

  screenTest('switching between the two counted ranges keeps the number', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);
    await tester.enterText(countField(), '7');
    await chooseLibraryOnlyRange(tester);

    expect(tester.widget<TextField>(countField()).controller!.text, '7');

    await chooseTypedRange(tester);
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.maxEntries, 7);
    expect(chosen!.discoverMissing, isTrue);
  });

  screenTest('the default range is this entry alone', (tester) async {
    await openSheet(tester);

    expect(
      countField(),
      findsNothing,
      reason: 'the count belongs to the range that uses one',
    );
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(closed, isTrue);
    expect(chosen!.limits.maxEntries, 1);
    expect(chosen!.limits.isSinglePage, isTrue);
    expect(chosen!.startNow, isFalse);
    expect(
      chosen!.discoverMissing,
      isFalse,
      reason: 'the page is already in front of the user; nothing is opened',
    );
  });

  screenTest('the typed range opens on a replaceable 2 and returns it', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    expect(tester.widget<TextField>(countField()).controller!.text, '2');

    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeStartNow')));

    expect(chosen!.limits.maxEntries, 2);
    expect(
      chosen!.startNow,
      isTrue,
      reason: 'Start now is the explicit Start, taken in the same tap',
    );
  });

  screenTest('the field takes digits and nothing else', (tester) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    // However the text arrives — typed, pasted or dictated.
    await tester.enterText(countField(), '1a2-b3');
    await tester.pump();

    expect(tester.widget<TextField>(countField()).controller!.text, '123');
  });

  screenTest('a blank field is refused where it was typed', (tester) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    await tester.enterText(countField(), '');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
    expect(
      closed,
      isFalse,
      reason: 'nothing was chosen, so nothing was queued',
    );
    expect(
      tester.widget<TextField>(countField()).focusNode!.hasFocus,
      isTrue,
      reason: 'the keys to fix it stay under the thumb',
    );
  });

  screenTest('zero is refused with the same sentence', (tester) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    await tester.enterText(countField(), '0');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeStartNow')));

    expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
    expect(closed, isFalse);
  });

  screenTest('a number above the ceiling is refused, naming the ceiling', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    await tester.enterText(countField(), '${ceiling + 1}');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(find.text('At most $ceiling entries at a time.'), findsOneWidget);
    expect(closed, isFalse);

    // And the ceiling itself is fine — the refusal is about crossing it.
    await tester.enterText(countField(), '$ceiling');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.maxEntries, ceiling);
  });

  screenTest('OK confirms the number, drops the keyboard and starts nothing', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    // Leading zeros are normalised on confirmation rather than while typing.
    await tester.enterText(countField(), '004');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('saveCountOk')),
      findsOneWidget,
      reason: 'the way out of a number pad with no return key',
    );

    await tapAndPump(tester, find.byKey(const ValueKey('saveCountOk')));

    expect(tester.widget<TextField>(countField()).controller!.text, '4');
    expect(
      find.byKey(const ValueKey('saveCountOk')),
      findsNothing,
      reason: 'the keyboard is down, so there is nothing left to confirm',
    );
    expect(
      closed,
      isFalse,
      reason: 'confirming a number and authorising a download are two acts',
    );

    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));
    expect(chosen!.limits.maxEntries, 4);
  });

  screenTest('backing out chooses nothing at all', (tester) async {
    await openSheet(tester);
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeCancel')));

    expect(closed, isTrue);
    expect(chosen, isNull);
  });
}
