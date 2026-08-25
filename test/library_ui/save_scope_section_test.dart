/// The recovered count block.
///
/// This interaction was device-tested in V1 and is under test here so it stays
/// recovered rather than redesigned: digits and nothing else, a blank and a
/// zero refused where they were typed, the ceiling stated and enforced, and an
/// OK that confirms the number without starting anything. It is now a
/// **section of the save sheet** rather than a sheet after it (V2-D62), so
/// what is pumped here is that section over its controller, with a launch row
/// the surface would normally supply.
///
/// The two counted ranges are here for the same reason: *Entries from here*
/// counts on the Source and reads it forward for what the library is missing,
/// *Entries already in your library* counts on the library and opens nothing,
/// and which one the block returns is the difference between an app that opens
/// someone's site and one that does not.
///
/// The bound itself is not this file's to assert twice — `SaveLimits.forScope`
/// owns it — but *that the block builds its limits through it* is, because a
/// range whose real ceiling lived somewhere the user could not see is the
/// thing CLAUDE.md forbids.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library_ui/save_scope_section.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  final ceiling = kDefaultSaveConfig.maxEntriesPerRun;

  SaveScopeChoice? chosen;
  var closed = false;
  SaveScopeController? controller;

  tearDown(() {
    controller?.dispose();
    controller = null;
  });

  /// The section as the save sheet composes it: the block, the pinned OK bar
  /// below the scroll, and a launch row that validates through the controller.
  Future<void> openSheet(
    WidgetTester tester, {
    NewCollectionNaming? naming,
    SaveScope initialScope = SaveScope.currentPageOnly,
  }) async {
    chosen = null;
    closed = false;
    final scope = controller = SaveScopeController(
      initialScope: initialScope,
      naming: naming,
    );
    void submit(SaveStartMode start) {
      final choice = scope.choiceFor(start);
      if (choice == null) return;
      chosen = choice;
      closed = true;
    }

    await tester.pumpWidget(
      h.app(
        Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SaveScopeSection(controller: scope),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey('saveScopeAddToQueue'),
                                onPressed: () =>
                                    submit(SaveStartMode.queueOnly),
                                child: const Text('Queue only'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('saveScopeStartNow'),
                                onPressed: () => submit(SaveStartMode.startNow),
                                child: const Text('Start now'),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          key: const ValueKey('saveScopeCancel'),
                          onPressed: () => closed = true,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: scope,
                  builder: (context, _) => scope.showsOkBar
                      ? SaveCountOkBar(onPressed: scope.confirmCount)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The sheet as the Entry save flow opens it for a Collection that does not
  /// exist yet.
  Future<void> openNamingSheet(WidgetTester tester) => openSheet(
    tester,
    naming: const NewCollectionNaming(
      suggestedName: 'Quiet Harbour',
      host: 'reading.example.com',
    ),
  );

  Finder nameField() => find.byKey(const ValueKey('collectionNameField'));

  Finder countField() => find.byKey(const ValueKey('saveCountField'));

  Future<void> chooseTypedRange(WidgetTester tester) =>
      tapAndPump(tester, find.byKey(const ValueKey('saveScopeFromHere')));

  screenTest('states the ceiling in words, where the count is typed', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    expect(find.textContaining('up to $ceiling'), findsOneWidget);
  });

  screenTest('the typed count says what it counts, before it is typed into', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);

    expect(
      find.textContaining('Counts this entry as the first'),
      findsOneWidget,
      reason:
          'ten from entry 101 is 101 through 110, and a sheet that leaves '
          'that to be inferred has said the wrong thing to half its readers',
    );
    expect(
      find.textContaining('5 means this one and the next four'),
      findsOneWidget,
      reason: 'said again in numbers, beside the field it is typed into',
    );
    expect(
      find.textContaining('One page at a time'),
      findsOneWidget,
      reason:
          'the count is a claim about the site, and the site is read as the '
          'download moves along it',
    );
    expect(find.textContaining('stop at any point'), findsOneWidget);
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

  screenTest('there is no third range: saving does not offer the library', (
    tester,
  ) async {
    // *Entries already in your library* answered a different question —
    // queue what is already known, open nothing — and nobody reaches for it
    // while saving the page in front of them. It is gone from the save flow
    // and must not come back (V2-D65); `SaveScopePlanner` still implements it
    // for the paths that legitimately use it.
    await openSheet(tester);

    expect(find.byKey(const ValueKey('saveScopeKnownOnly')), findsNothing);
    expect(find.textContaining('already in your library'), findsNothing);
    expect(find.byKey(const ValueKey('saveScopeThisEntry')), findsOneWidget);
    expect(find.byKey(const ValueKey('saveScopeFromHere')), findsOneWidget);

    await chooseTypedRange(tester);
    await tester.enterText(countField(), '5');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(
      chosen!.discoverMissing,
      isTrue,
      reason: 'the one counted range reads the site forward',
    );
  });

  screenTest('a tap that lands on the row does not clear a refusal', (
    tester,
  ) async {
    // The count sits inside the row's tap target now, so the row's own tap has
    // to be idempotent: re-choosing the range it is already on must not wipe
    // the sentence the user is reading (V2-D65).
    await openSheet(tester);
    await chooseTypedRange(tester);
    await tester.enterText(countField(), '0');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));
    expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);

    await chooseTypedRange(tester);
    expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
  });

  screenTest('the number survives a trip through *This entry* and back', (
    tester,
  ) async {
    await openSheet(tester);
    await chooseTypedRange(tester);
    await tester.enterText(countField(), '12');
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeThisEntry')));
    await chooseTypedRange(tester);

    expect(
      tester.widget<TextField>(countField()).controller!.text,
      '12',
      reason:
          'coming back and finding the number gone would be the sheet '
          'forgetting something the user said',
    );
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

  screenTest('a caller that already said *entries* opens on entries', (
    tester,
  ) async {
    // The default stays *This entry* — the smallest answer, and the one that
    // opens no page. A control whose own label promised the plural passes the
    // plural, so the sheet does not arrive selecting what the user declined by
    // not pressing the other button (V2-D61).
    await openSheet(tester, initialScope: SaveScope.fixedCount);

    expect(countField(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('saveScopeReadsForwardNote')),
      findsOneWidget,
    );
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.maxEntries, 2, reason: 'the replaceable default');
    expect(chosen!.limits.isSinglePage, isFalse);
    expect(chosen!.discoverMissing, isTrue);
  });

  screenTest('and the way back to this entry alone is still one tap', (
    tester,
  ) async {
    await openSheet(tester, initialScope: SaveScope.fixedCount);
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeThisEntry')));
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeAddToQueue')));

    expect(chosen!.limits.isSinglePage, isTrue);
    expect(chosen!.discoverMissing, isFalse);
  });

  screenTest('backing out chooses nothing at all', (tester) async {
    await openSheet(tester);
    await tapAndPump(tester, find.byKey(const ValueKey('saveScopeCancel')));

    expect(closed, isTrue);
    expect(chosen, isNull);
  });

  // ─── naming the Collection that does not exist yet (V2-D57) ──────────

  group('a collection about to be created', () {
    screenTest('is named here, on the sheet that already printed its name', (
      tester,
    ) async {
      await openNamingSheet(tester);

      expect(
        tester.widget<TextField>(nameField()).controller!.text,
        'Quiet Harbour',
        reason: 'the detected title is a suggestion the user may correct',
      );
      expect(
        find.text('First source · reading.example.com'),
        findsOneWidget,
        reason:
            'the site about to become its first source is named, not '
            'referred to as "this site"',
      );
      expect(
        tester.widget<TextField>(nameField()).autofocus,
        isFalse,
        reason: 'confirming the suggestion must not cost a keyboard dismissal',
      );
    });

    screenTest('returns the edited name with the range and the launch', (
      tester,
    ) async {
      await openNamingSheet(tester);
      await tester.enterText(nameField(), 'Quiet Harbour, corrected');
      await chooseTypedRange(tester);
      await tester.enterText(countField(), '7');
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('saveScopeAddToQueue')),
      );

      expect(chosen!.collectionName, 'Quiet Harbour, corrected');
      expect(chosen!.limits.maxEntries, 7);
      expect(chosen!.discoverMissing, isTrue);
      expect(chosen!.start, SaveStartMode.queueOnly);
    });

    screenTest('trims what was typed, and keeps the untouched suggestion', (
      tester,
    ) async {
      await openNamingSheet(tester);
      await tester.enterText(nameField(), '  Quiet Harbour  ');
      await tapAndPump(tester, find.byKey(const ValueKey('saveScopeStartNow')));

      expect(chosen!.collectionName, 'Quiet Harbour');
      expect(chosen!.start, SaveStartMode.startNow);
    });

    screenTest('refuses a blank name where it was typed, and starts nothing', (
      tester,
    ) async {
      await openNamingSheet(tester);
      await tester.enterText(nameField(), '   ');
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('saveScopeAddToQueue')),
      );

      expect(find.text('Give this collection a name.'), findsOneWidget);
      expect(
        closed,
        isFalse,
        reason: 'a collection with no name is not something to create',
      );
      expect(chosen, isNull);

      // The count is not complained about underneath it: identity is the
      // first question, and it is the only one answered wrongly here.
      expect(find.text('Enter a whole number of 1 or more.'), findsNothing);

      await tester.enterText(nameField(), 'Quiet Harbour');
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('saveScopeAddToQueue')),
      );
      expect(chosen!.collectionName, 'Quiet Harbour');
    });

    screenTest('still refuses the number, and keeps the typed name while it '
        'does', (tester) async {
      await openNamingSheet(tester);
      await tester.enterText(nameField(), 'Quiet Harbour, corrected');
      await chooseTypedRange(tester);
      await tester.enterText(countField(), '0');
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('saveScopeAddToQueue')),
      );

      expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
      expect(closed, isFalse);
      expect(
        tester.widget<TextField>(nameField()).controller!.text,
        'Quiet Harbour, corrected',
        reason: 'a refused number does not lose the name that was typed',
      );
    });

    screenTest('the number pad still has its own way out', (tester) async {
      await openNamingSheet(tester);
      await chooseTypedRange(tester);
      await tester.enterText(countField(), '004');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('saveCountOk')),
        findsOneWidget,
        reason:
            'the count field owns the OK bar; the name field has a return '
            'key of its own and does not',
      );
      await tapAndPump(tester, find.byKey(const ValueKey('saveCountOk')));
      expect(tester.widget<TextField>(countField()).controller!.text, '4');
      expect(closed, isFalse);
    });

    screenTest('an existing collection is not renamed on the way past', (
      tester,
    ) async {
      await openSheet(tester);

      expect(nameField(), findsNothing);
      expect(
        find.byKey(const ValueKey('newCollectionSourceFact')),
        findsNothing,
      );
      // The block names the question; which Collection it is about is the
      // sheet's own identity line above it now (V2-D62).
      expect(find.byKey(const ValueKey('saveScopeThisEntry')), findsOneWidget);

      await tapAndPump(
        tester,
        find.byKey(const ValueKey('saveScopeAddToQueue')),
      );
      expect(chosen!.collectionName, isNull);
    });
  });
}
