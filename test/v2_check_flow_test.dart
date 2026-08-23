/// The way into a Collection check, and the way its result is told.
///
/// Three rules from CLAUDE.md are what these tests are for.
///
/// * **A check is content-affecting source automation**, so it is user-started,
///   visible, bounded and cancellable. Bounded means [kCollectionCheckLimits]
///   is a ceiling *the user can see*: the numbers are asserted on screen, not
///   in the constant.
/// * **The gate is about where the user waits, never whether the check runs.**
///   Without the capability the visible-Browser start is whole, and backing out
///   of the sheet writes nothing at all.
/// * **"Finished" and "the reading was cut short" are different outcomes.** The
///   sentence tests below are exact on purpose: a reading cut by its own
///   ceiling still found what it found, and calling that "up to date" would be
///   a claim the check never made.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/library_ui/collection_actions.dart';
import 'package:web_reader/library_ui/collection_models.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/recognition/discovery.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/v2_harness.dart';
import 'library_ui/support/ui_harness.dart' show screenTest;

void main() {
  group('what the check says it did', () {
    test('a collection with no site to read is told exactly that', () {
      expect(
        checkOutcomeSentence(null),
        'Nothing was checked — this collection has no site to read right now.',
      );
    });

    test('nothing found in a reading it can vouch for is up to date', () {
      expect(
        checkOutcomeSentence(
          _outcome(state: SourceCheckState.upToDate, pagesRead: 2),
        ),
        'Up to date. Nothing new on this collection\'s site.',
      );
    });

    test('nothing found in a reading cut short says there is more to read', () {
      final sentence = checkOutcomeSentence(
        _outcome(stop: SourceCheckStop.pageLimitReached, pagesRead: 3),
      );
      expect(
        sentence,
        'Read what it is allowed to in one go and found nothing new — check '
        'again to carry on.',
      );
      expect(
        sentence,
        isNot(contains('Up to date')),
        reason:
            'a reading stopped by its own ceiling vouches for no interval, so '
            'it may not report the library as current',
      );
    });

    test('one entry found in a full reading is counted, and says so', () {
      expect(
        checkOutcomeSentence(
          _outcome(state: SourceCheckState.updatesAvailable, found: 1),
        ),
        '1 new entry added to your library. Nothing was downloaded.',
      );
    });

    test('several entries found in a full reading are counted', () {
      expect(
        checkOutcomeSentence(
          _outcome(state: SourceCheckState.updatesAvailable, found: 4),
        ),
        '4 new entries added to your library. Nothing was downloaded.',
      );
    });

    test('entries found in a reading cut short ask to be checked again', () {
      final sentence = checkOutcomeSentence(
        _outcome(
          found: 2,
          stop: SourceCheckStop.newEntryLimitReached,
          pagesRead: 1,
        ),
      );
      expect(
        sentence,
        '2 new entries added. There is more of the list to read — check again '
        'to carry on.',
      );
      expect(
        sentence,
        isNot(contains('Nothing was downloaded')),
        reason:
            'the two endings are separate sentences, not one sentence with a '
            'clause bolted on',
      );
    });

    test('a check stopped with nothing found says nothing changed', () {
      expect(
        checkOutcomeSentence(
          _outcome(stop: SourceCheckStop.cancelledByUser, pagesRead: 1),
        ),
        'Stopped. Nothing was added, and nothing was removed.',
      );
    });

    test('a check stopped with entries found says where they went', () {
      expect(
        checkOutcomeSentence(
          _outcome(found: 3, stop: SourceCheckStop.cancelledByUser),
        ),
        'Stopped. The 3 found so far are in your library.',
      );
    });

    test('a source that stops listing something says so, and says what was '
        'not deleted', () {
      // V2 has always computed retractions and never told anyone. "No longer
      // listed" and "deleted from your device" are different things, and the
      // sentence has to carry the difference or it reads as data loss.
      final sentence = checkOutcomeSentence(
        _outcome(state: SourceCheckState.upToDate, retracted: 2),
      );

      expect(sentence, contains('2 entries are no longer listed'));
      expect(sentence, contains('nothing on this device was deleted'));
    });

    test('one retraction is not "1 entries"', () {
      expect(
        checkOutcomeSentence(
          _outcome(state: SourceCheckState.upToDate, retracted: 1),
        ),
        contains('1 entry is no longer listed'),
      );
    });

    test('a check that retracted nothing says nothing about it', () {
      expect(
        checkOutcomeSentence(_outcome(state: SourceCheckState.upToDate)),
        isNot(contains('no longer listed')),
      );
    });

    test('a reading that could not happen never says "check again"', () {
      // The regression: nine of twelve stop reasons produced "Read 0 page(s)
      // and found nothing new. There is more of the list to read — check
      // again to continue." That is false in all nine, and it tells the user
      // to repeat an action that will fail identically.
      const cannotBeRepeatedAway = [
        SourceCheckStop.preferredSourceNotChosen,
        SourceCheckStop.collectionNotFollowed,
        SourceCheckStop.sourceNotReadable,
        SourceCheckStop.sourceUnknown,
        SourceCheckStop.listingUnreadable,
        SourceCheckStop.listingUnrecognised,
        SourceCheckStop.listingTruncated,
        SourceCheckStop.listingOrderingAmbiguous,
        SourceCheckStop.entryIdentityUnsupported,
      ];

      final said = <String>{};
      for (final stop in cannotBeRepeatedAway) {
        final sentence = checkOutcomeSentence(_outcome(stop: stop));
        expect(
          sentence,
          isNot(contains('check again')),
          reason: '$stop cannot be fixed by checking again',
        );
        expect(
          sentence,
          isNot(contains('Up to date')),
          reason: '$stop concluded nothing, so it may not report currency',
        );
        said.add(sentence);
      }

      expect(
        said,
        hasLength(cannotBeRepeatedAway.length),
        reason: 'each condition says what is actually wrong with it',
      );
    });

    test('more than one site with none preferred says which choice to '
        'make', () {
      expect(
        checkOutcomeSentence(
          _outcome(stop: SourceCheckStop.preferredSourceNotChosen),
        ),
        contains('Choose which one to check'),
      );
    });

    test('an archived collection is told it is archived', () {
      expect(
        checkOutcomeSentence(
          _outcome(stop: SourceCheckStop.collectionNotFollowed),
        ),
        contains('archived'),
      );
    });

    test('a site this app does not read from is named as this app\'s own', () {
      expect(
        checkOutcomeSentence(
          _outcome(stop: SourceCheckStop.captureRestrictedForSite),
        ),
        'This collection\'s site is one Scrollary does not read from.',
      );
    });
  });

  group('starting one', () {
    late V2Harness v2;
    late ValueNotifier<int?> tabRequest;
    late String collectionId;
    late String collectionName;

    setUp(() {
      v2 = V2Harness(browser: BrowserController(), fileStore: tempFileStore());
      tabRequest = ValueNotifier<int?>(null);
      collectionName = 'Serial Alpha';
    });
    tearDown(() async {
      tabRequest.dispose();
      await v2.close();
    });

    /// A Collection with one Source, which is everything a check needs to be
    /// startable.
    Future<CollectionRow> seed() async {
      final root = await v2.ui.folders.ensureRoot();
      final (collection, _) = await v2.ui.collections.create(
        name: collectionName,
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      collectionId = collection!.id;
      await v2.ui.collections.addSource(
        collectionId: collection.id,
        host: 'reading.example.com',
        pathKey: 'serial-alpha',
        language: 'en',
      );
      return collection;
    }

    Widget app(Widget home) => ProviderScope(
      overrides: [
        v2ServicesProvider.overrideWithValue(v2.services),
        libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
        shellTabRequestProvider.overrideWithValue(tabRequest),
      ],
      child: MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Scaffold(body: home),
      ),
    );

    /// The control the shell puts behind `V2Services.checkCollection`.
    Widget starter(void Function(SourceCheckOutcome?) onDone) => Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () async => onDone(
          await startCollectionCheck(
            context,
            ref,
            collectionId,
            collectionName: collectionName,
          ),
        ),
        child: const Text('check'),
      ),
    );

    final cancel = find.byKey(const ValueKey('startOptionsCancel'));
    final inBrowser = find.byKey(const ValueKey('startInBrowser'));

    screenTest('the start sheet states what the check will actually do', (
      tester,
    ) async {
      await seed();
      await tester.pumpWidget(app(starter((_) {})));
      await tester.tap(find.text('check'));
      await _settle(tester);

      expect(find.textContaining(collectionName), findsWidgets);
      // The production reading takes one page — the observation source
      // reports no continuation — so the sheet must say one page rather than
      // quoting a ceiling nothing reaches. A bound the user cannot see is not
      // a bound they consented to; a bound that is not real is worse.
      expect(
        find.textContaining('one page'),
        findsOneWidget,
        reason: 'the sentence a user consents to has to be true',
      );
      expect(
        find.textContaining(
          '${kCollectionCheckLimits.maxNewEntries} new entries',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing is downloaded'), findsOneWidget);

      await tester.tap(cancel);
      await _settle(tester);
    });

    screenTest('not now runs no check and writes no row', (tester) async {
      await seed();
      var called = false;
      SourceCheckOutcome? outcome;
      await tester.pumpWidget(
        app(
          starter((o) {
            called = true;
            outcome = o;
          }),
        ),
      );
      await tester.tap(find.text('check'));
      await _settle(tester);
      await tester.tap(cancel);
      await _settle(tester);

      expect(called, isTrue);
      expect(outcome, isNull);
      expect(v2.check.isRunning, isFalse);
      expect(v2.check.lastOutcome, isNull);
      expect(
        tabRequest.value,
        isNull,
        reason: 'backing out does not even move the user',
      );
      expect(
        await v2.library.select(v2.library.entries).get(),
        isEmpty,
        reason: 'nothing was read, so there is nothing to have written',
      );
    });

    screenTest('a check already running is refused, not stacked', (
      tester,
    ) async {
      await seed();
      v2.check.debugSetRunning(true);
      SourceCheckOutcome? outcome;
      var called = false;
      await tester.pumpWidget(
        app(
          starter((o) {
            called = true;
            outcome = o;
          }),
        ),
      );
      await tester.tap(find.text('check'));
      await _settle(tester);

      expect(find.text('A check is already running.'), findsOneWidget);
      expect(cancel, findsNothing, reason: 'no second sheet was opened');
      expect(called, isTrue);
      expect(outcome, isNull);

      v2.check.debugSetRunning(false);
      await _settle(tester);
    });

    screenTest(
      'without the capability the visible-Browser start is fully functional',
      (tester) async {
        await seed();
        SourceCheckOutcome? outcome;
        await tester.pumpWidget(app(starter((o) => outcome = o)));
        await tester.tap(find.text('check'));
        await _settle(tester);

        expect(
          inBrowser,
          findsOneWidget,
          reason: 'the Free workflow is not degraded to make Pro look better',
        );
        expect(
          find.byKey(const ValueKey('startKeepUsingAppLocked')),
          findsOneWidget,
          reason: 'the paid option is visible and locked, never hidden',
        );

        await tester.tap(inBrowser);
        for (var i = 0; i < 40 && outcome == null; i++) {
          await _turn(tester);
        }

        expect(
          outcome,
          isNotNull,
          reason:
              'the gate decides where the user waits, never whether the '
              'check runs',
        );
        expect(v2.check.lastOutcome, isNotNull);
        expect(tabRequest.value, 1, reason: 'Browser first, automation second');
        expect(v2.check.isRunning, isFalse);
      },
    );
  });

  group('where the check is offered', () {
    late V2Harness v2;
    late CollectionRow collection;
    final checked = <String>[];

    setUp(() {
      v2 = V2Harness(browser: BrowserController(), fileStore: tempFileStore());
      checked.clear();
    });
    tearDown(() => v2.close());

    Future<CollectionRow> seed() async {
      final root = await v2.ui.folders.ensureRoot();
      final (row, _) = await v2.ui.collections.create(
        name: 'Serial Alpha',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      return collection = row!;
    }

    Widget app({required bool checkerAttached}) => ProviderScope(
      overrides: [
        libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
        if (checkerAttached)
          libui.collectionCheckerProvider.overrideWithValue(
            (id, name) async => checked.add('$id/$name'),
          ),
      ],
      child: MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showCollectionMenu(
                context,
                ref,
                CollectionView.from(collection: collection, entries: const []),
              ),
              child: const Text('menu'),
            ),
          ),
        ),
      ),
    );

    final checkItem = find.byKey(const ValueKey('collectionCheck'));

    screenTest('a followed collection offers it when a checker is attached', (
      tester,
    ) async {
      await seed();
      await tester.pumpWidget(app(checkerAttached: true));
      await tester.tap(find.text('menu'));
      await _settle(tester);

      expect(checkItem, findsOneWidget);
      expect(find.textContaining('Nothing is downloaded'), findsOneWidget);

      await tester.tap(checkItem);
      await _settle(tester);
      expect(checked, ['${collection.id}/Serial Alpha']);
    });

    screenTest('it is not offered when no checker is attached', (tester) async {
      await seed();
      await tester.pumpWidget(app(checkerAttached: false));
      await tester.tap(find.text('menu'));
      await _settle(tester);

      expect(
        checkItem,
        findsNothing,
        reason: 'an action nothing will pick up is not offered and left inert',
      );
      expect(
        find.byKey(const ValueKey('collectionArchive')),
        findsOneWidget,
        reason: 'the rest of the menu is unaffected',
      );
    });

    screenTest('what this collection is usually saved as is changeable from '
        'here', (tester) async {
      // The save sheet is where a preference is set, in the flow that had the
      // question in front of the user. Someone who changes their mind should
      // not have to find a page of the work and open the save sheet to get at
      // it again.
      await seed();
      await tester.pumpWidget(app(checkerAttached: true));
      await tester.tap(find.text('menu'));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('collectionCaptureMode')));
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('collectionCaptureMode_imageSequence')),
      );
      await _settle(tester);

      expect(
        await CapturePreferenceStore(
          LocalSettingsStore(v2.library),
        ).of(collection.id),
        CaptureMode.imageSequence,
      );
    });

    screenTest('and *Ask each time* is a real answer', (tester) async {
      await seed();
      final preferences = CapturePreferenceStore(
        LocalSettingsStore(v2.library),
      );
      await preferences.remember(collection.id, CaptureMode.imageSequence);

      await tester.pumpWidget(app(checkerAttached: true));
      await tester.tap(find.text('menu'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('collectionCaptureMode')));
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('collectionCaptureModeAsk')),
      );
      await _settle(tester);

      expect(
        await preferences.of(collection.id),
        isNull,
        reason: 'there is no safest mode, so no answer stays expressible',
      );
    });

    screenTest('an archived collection is not offered it', (tester) async {
      await seed();
      expect(await v2.ui.collections.archive(collection.id), isNull);
      collection = (await v2.ui.collections.byId(collection.id))!;

      await tester.pumpWidget(app(checkerAttached: true));
      await tester.tap(find.text('menu'));
      await _settle(tester);

      expect(
        checkItem,
        findsNothing,
        reason:
            'archiving is exactly "stop keeping this current", so offering a '
            'check there would contradict the sentence beside it',
      );
      expect(find.byKey(const ValueKey('collectionFollow')), findsOneWidget);
    });
  });
}

/// One outcome, built from the two facts the sentence reads: how many Entries
/// the check brought in, and whether the reading was cut short.
SourceCheckOutcome _outcome({
  SourceCheckState state = SourceCheckState.stopped,
  SourceCheckStop? stop,
  int found = 0,
  int pagesRead = 0,
  int retracted = 0,
}) => SourceCheckOutcome(
  sourceId: 'source-1',
  state: state,
  stopReason: stop,
  pagesRead: pagesRead,
  discovery: DiscoveryOutcome(
    createdEntryIds: [for (var i = 0; i < found; i++) 'entry-$i'],
    retractedLocationIds: [for (var i = 0; i < retracted; i++) 'loc-$i'],
  ),
);

/// One turn of the real event loop, then one frame.
///
/// A check started and left to run does its work on the real event loop, which
/// a `testWidgets` fake clock never turns on its own.
Future<void> _turn(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2)),
  );
  await tester.pump(const Duration(milliseconds: 25));
}

/// Enough turns for a sheet, a dialog or a snackbar to arrive.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await _turn(tester);
  }
}
