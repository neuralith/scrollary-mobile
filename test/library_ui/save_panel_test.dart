/// The save panel, one row of docs/V2_SAVE_FLOW.md §3 at a time.
///
/// What each row asserts is the same pair of facts: **which actions the sheet
/// offers**, and **which domain call the tap makes**, with the limits it
/// carries. The domain half is stood in for here — this lane decides what to
/// ask for, not what a row is written as — so the assertions are about the
/// question, which is the part that was lost.
///
/// Two rules show up as tests rather than as comments: a serialized page is
/// never standalone by default, and a listing never becomes an Entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
// STUB IMPORT — switch to 'package:web_reader/features/v2_add_flow.dart' at
// merge.
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import '../helpers/fake_browser.dart';
import 'support/ui_harness.dart';

/// One entry of a work, on a reserved example host: a printed number makes it
/// an entry page whatever the library knows.
const _entryUrl = 'https://reading.example.com/works/alpha/12';
const _entryTitle = 'Alpha 12';

/// The address the listing itself sits at.
const _indexUrl = 'https://reading.example.com/works/alpha';
const _indexTitle = 'Alpha';

/// A page that says nothing about itself either way.
const _plainUrl = 'https://news.example.com/';
const _plainTitle = 'Home';

/// What the panel asked the domain for.
class _AddCall {
  _AddCall({
    required this.url,
    required this.collectionId,
    required this.newCollectionName,
    required this.limits,
    this.isListing = false,
    this.discoverMissing = false,
    this.captureMode,
    this.captureModeIsUserSet = false,
  });

  final String url;
  final String? collectionId;
  final String? newCollectionName;
  final SaveLimits? limits;

  /// What the sheet asked the save to produce, and whether a person picked it
  /// rather than it being detection's or the collection's answer.
  final CaptureMode? captureMode;
  final bool captureModeIsUserSet;

  /// Whether the sheet told the domain this address is a Source's own page.
  final bool isListing;

  /// Whether the count was a claim about the Source — read this site forward
  /// for whatever the library is missing.
  final bool discoverMissing;
}

void main() {
  late UiHarness h;
  late FakeBrowser browser;
  late List<_AddCall> adds;
  late List<String> standalones;

  /// What the stand-in domain reports as the Collection the save went to, for
  /// a call that did not name one. The real orchestration answers this from
  /// the library; a test that seeds a Collection sets it to that one.
  late String reportedCollectionId;

  /// The foreground boundary, injected so a test can say what this device may
  /// do without reaching for a purchase of any kind.
  late ForegroundMultitasking capability;

  setUp(() {
    h = UiHarness();
    browser = FakeBrowser();
    adds = [];
    standalones = [];
    reportedCollectionId = 'made-up-collection';
    capability = ForegroundMultitasking();
  });
  tearDown(() {
    capability.dispose();
    h.close();
  });

  Future<AddToLibraryReport> fakeAdd(
    WidgetRef ref, {
    required String url,
    required String pageTitle,
    String? collectionId,
    String? newCollectionName,
    String? folderId,
    SaveLimits? limits,
    bool isListing = false,
    bool discoverMissing = false,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    adds.add(
      _AddCall(
        url: url,
        collectionId: collectionId,
        newCollectionName: newCollectionName,
        limits: limits,
        isListing: isListing,
        discoverMissing: discoverMissing,
        captureMode: captureMode,
        captureModeIsUserSet: captureModeIsUserSet,
      ),
    );
    return AddToLibraryReport(
      sentence: 'The domain said what it did.',
      collectionId: collectionId ?? reportedCollectionId,
      entryId: limits == null ? null : 'made-up-entry',
      queued: limits?.maxEntries ?? 0,
    );
  }

  Future<AddToLibraryReport> fakeStandalone(
    WidgetRef ref, {
    required String url,
    required String pageTitle,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    standalones.add(url);
    return const AddToLibraryReport(
      sentence: 'Saved on its own.',
      entryId: 'made-up-entry',
      queued: 1,
    );
  }

  /// A page the bridge could read, carrying nothing in particular — enough for
  /// detection to run for real, which is what the panel does before it offers
  /// anything.
  PageProbe probeOf(String url, String title) => PageProbe(
    url: url,
    title: title,
    readyState: 'complete',
    documentHeight: 2000,
    viewportHeight: 800,
    viewportWidth: 400,
    atBottom: false,
  );

  /// A page as the save sheet actually meets one: **not scrolled**.
  ///
  /// Its prose is in the DOM from the first byte, so text-only measures true
  /// straight away. Its images are lazy, so before any scrolling the sheet
  /// sees almost none of them — which is exactly the state the engine refuses
  /// to decide from ("Measured on the SETTLED probe, after scrolling",
  /// `save_engine.dart`). Anything the sheet concludes about *images* here is
  /// a measurement of how far the page has got, not of what it holds.
  PageProbe lazyImagePageProbe(String url, String title) => PageProbe(
    url: url,
    title: title,
    readyState: 'complete',
    documentHeight: 12000,
    viewportHeight: 800,
    viewportWidth: 400,
    atBottom: false,
    content: const PageContentSignals(
      textLength: 1400,
      paragraphCount: 6,
      contentRegionImageCount: 1,
    ),
  );

  Future<void> openPanel(
    WidgetTester tester,
    String url,
    String title, {
    PageProbe? probe,
  }) async {
    browser
      ..setUrl(url)
      ..addPage(url, probe ?? probeOf(url, title));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(h.services),
          browserProvider.overrideWithValue(browser),
          saveQueueStarterProvider.overrideWithValue(h.starter),
          v2AddAndDownloadProvider.overrideWithValue(fakeAdd),
          v2SaveStandaloneProvider.overrideWithValue(fakeStandalone),
          foregroundMultitaskingProvider.overrideWithValue(capability),
        ],
        child: MaterialApp(
          theme: appTheme(palette: AppPalette.light),
          home: Scaffold(
            body: V2SavePanel(url: url, pageTitle: title),
          ),
        ),
      ),
    );
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  /// Press a launch, scrolling to it first.
  ///
  /// One sheet now carries the identity line, the range block, the count and
  /// the launches, so on a short viewport the launches start below the fold —
  /// which is what the scroll view is for (V2-D62). A real sheet is
  /// `isScrollControlled` and gets the whole screen; a test viewport is 800px.
  Future<void> launch(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tapAndPump(tester, finder);
  }

  // ─── row 1: an Entry the library already holds ──────────────────────────

  group('an entry in the library', () {
    Future<String> seed({bool queued = false}) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      final source = await h.source(collection.id, pathKey: '/works/alpha');
      final entry = await h.entryIn(
        collection.id,
        title: _entryTitle,
        ordinal: 12,
      );
      final location = await h.location(
        entry.id,
        _entryUrl,
        sourceId: source.id,
      );
      if (queued) {
        await h.queue.enqueue(
          entryId: entry.id,
          locationId: location.id,
          locationUrl: _entryUrl,
        );
      }
      return collection.id;
    }

    screenTest('a run in flight is stopped from the sheet that started it', (
      tester,
    ) async {
      await seed(queued: true);
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2StartButton'));
      final task = (await h.queue.pending()).single;
      await h.queue.claim(task.id);

      // The panel's own Stop is docked at the bottom of the Browser — which is
      // exactly where this sheet sits. A control the user must dismiss the
      // sheet to reach is not reachable while the thing it stops is running.
      final panel = tester.state(find.byType(V2SavePanel));
      // ignore: avoid_dynamic_calls
      (panel as dynamic).debugSetRunningFromHere(true);
      await tester.pump();

      expect(key('sheetStopRun'), findsOneWidget);
      await tapAndPump(tester, key('sheetStopRun'));

      expect(
        (await h.queue.byId(task.id))?.state,
        SaveTaskState.cancelled,
        reason: 'the sheet must be able to stop what the sheet started',
      );
    });

    screenTest('asks how much on the sheet itself, under one identity line', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('saveScopeThisEntry'));
      // One sheet: the three ranges and the launch, with nothing to press
      // first (V2-D62).
      expect(key('saveScopeFromHere'), findsOneWidget);
      expect(key('saveScopeAddToQueue'), findsOneWidget);
      expect(
        key('saveScopeKnownOnly'),
        findsNothing,
        reason: 'the save flow offers two ranges, not three (V2-D65)',
      );
      expect(find.textContaining('already in your library'), findsNothing);
      expect(key('v2DownloadEntry'), findsNothing);
      expect(key('v2DownloadEntries'), findsNothing);

      // One identity line, not three. The site is in the address bar of the
      // Browser this sheet is sitting on.
      expect(find.text('Alpha · Entry 12'), findsOneWidget);
      expect(find.text('Collection · Alpha'), findsNothing);
      expect(find.text('Source · reading.example.com'), findsNothing);
      expect(
        key('v2AddToCollection'),
        findsNothing,
        reason: 'it is already in one',
      );
    });

    screenTest('downloading this entry asks for exactly one', (tester) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 1);
      expect(
        adds.single.collectionId,
        isNull,
        reason: 'recognition already places it; nothing is being adopted',
      );
      expect(find.text('The domain said what it did.'), findsOneWidget);
    });

    // *How many* and *what happens next* are one sheet and one answer. What
    // these three replace: a *Start now* button here, a gate sheet before the
    // run asking where to wait, and the queue's own gate sheet afterwards
    // asking it again — three questions about one decision, and one route
    // through them (*Add to queue*, then *Start in Browser*) that showed the
    // user the Browser and started nothing.
    screenTest('the count sheet carries the number onto the call, and asks '
        'nothing else', (tester) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeFromHere'));

      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '5');
      // The launch rows are in this sheet: the foreground boundary's own,
      // beside a *Queue only* that needs no capability at all.
      expect(key('startInBrowser'), findsOneWidget);
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 5);
      expect(
        adds.single.discoverMissing,
        isTrue,
        reason: 'the typed count is a claim about the Source',
      );
      expect(
        key('startOptionsCancel'),
        findsNothing,
        reason: 'the launch was chosen; there is no second question',
      );
      expect(h.starts, 0, reason: 'Queue only starts nothing');
    });

    screenTest('Start now actually starts', (tester) async {
      final collectionId = await seed();
      // A row already waiting, for an Entry that is not this page: the Start
      // this launch authorises is the queue's, and the queue has to have
      // something in it for "it started" to mean anything.
      final other = await h.entryIn(
        collectionId,
        title: 'Alpha 13',
        ordinal: 13,
      );
      final otherUrl = 'https://reading.example.com/works/alpha/13';
      final source = await h.source(collectionId, pathKey: '/works/alpha-2');
      final otherLocation = await h.location(
        other.id,
        otherUrl,
        sourceId: source.id,
      );
      await h.queue.enqueue(
        entryId: other.id,
        locationId: otherLocation.id,
        locationUrl: otherUrl,
      );

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeFromHere'));

      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '3');
      await launch(tester, key('startInBrowser'));

      expect(adds, hasLength(1));
      expect(
        key('startOptionsCancel'),
        findsNothing,
        reason: 'asking again where to wait is the modal this removes',
      );
      expect(h.starts, 1, reason: 'Start now means it started');
    });

    screenTest('choosing a range and a count starts nothing on its own', (
      tester,
    ) async {
      // There is no *Cancel* to press any more: the sheet the user dismisses
      // is the sheet they were answering, and answering it is not launching.
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeFromHere'));

      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '4');
      await tester.pump();

      expect(adds, isEmpty);
      expect(h.starts, 0);
    });

    screenTest('this entry alone is never gated and discovers nothing', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      await launch(tester, key('saveScopeAddToQueue'));

      expect(
        adds.single.discoverMissing,
        isFalse,
        reason: 'the page is already in front of the user; nothing is opened',
      );
      expect(h.starts, 0);
      expect(key('startOptionsCancel'), findsNothing);
    });

    screenTest('a row already waiting offers the Start and no second '
        'download', (tester) async {
      await seed(queued: true);
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2StartButton'));
      expect(find.text('Queued — waiting for Start.'), findsOneWidget);
      expect(key('v2DownloadEntry'), findsNothing);

      await tapAndPump(tester, key('v2StartButton'));

      expect(h.starts, 1);
      expect(
        h.queue.saveStartAuthorised,
        isTrue,
        reason: 'the Start is the authorisation, and it is explicit',
      );
    });
  });

  // ─── row 2: a page on a Source the library holds ────────────────────────

  group('a page on a known source', () {
    Future<void> seed({bool archived = false}) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      await h.source(collection.id, pathKey: '/works/alpha');
      if (archived) await h.collections.archive(collection.id);
    }

    screenTest('adds to the collection it belongs to, and says which', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('saveScopeThisEntry'));
      expect(key('saveScopeFromHere'), findsOneWidget);
      expect(find.text('Adds to Alpha.'), findsOneWidget);
      expect(
        key('v2SaveStandalone'),
        findsNothing,
        reason: 'the library knows where this belongs',
      );

      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.collectionId, isNotNull);
      expect(adds.single.limits!.maxEntries, 1);
    });

    screenTest('does not offer Follow for a collection already followed', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('saveScopeThisEntry'));
      expect(key('v2FollowCollection'), findsNothing);
    });

    screenTest('offers Follow beside the download, never folded into it', (
      tester,
    ) async {
      await seed(archived: true);
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2FollowCollection'));
      expect(
        key('saveScopeThisEntry'),
        findsOneWidget,
        reason:
            'following and downloading are separate acts, offered side by '
            'side',
      );
    });

    screenTest('the listing of a known collection is a check, never an entry', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _indexUrl, _indexTitle);

      await pumpUntil(tester, key('v2CheckCollection'));
      expect(key('v2AddAndDownloadEntry'), findsNothing);
      expect(key('v2SaveStandalone'), findsNothing);
    });
  });

  // ─── rows 3–5: a site the library knows nothing about ───────────────────

  group('an unknown site', () {
    screenTest('an entry page leads with the collection, standalone second', (
      tester,
    ) async {
      await h.root();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2AddToCollection'));
      expect(key('v2SaveStandalone'), findsOneWidget);
      expect(
        tester.widget(key('v2AddToCollection')),
        isA<FilledButton>(),
        reason: 'a serialized page never becomes standalone by default',
      );
      expect(tester.widget(key('v2SaveStandalone')), isA<TextButton>());
      expect(
        find.textContaining('another source'),
        findsOneWidget,
        reason: 'joining a collection and starting one are different acts',
      );
    });

    screenTest('picking a collection then a count reaches the domain once', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));

      await tapAndPump(tester, key('v2AddToCollection'));
      // The page's own title is a suggestion, and here it matches none of the
      // user's collections: the picker says so and offers the way back to the
      // whole list rather than pretending the library is empty.
      await pumpUntil(tester, key('collectionPickerClearFilter'));
      await tapAndPump(tester, key('collectionPickerClearFilter'));
      await pumpUntil(tester, key('collectionOption-${collection.id}'));
      await tapAndPump(tester, key('collectionOption-${collection.id}'));
      await pumpUntil(tester, key('saveScopeAddToQueue'));
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.collectionId, collection.id);
      expect(adds.single.newCollectionName, isNull);
      expect(adds.single.limits!.maxEntries, 1);
      expect(adds.single.discoverMissing, isFalse);
      expect(standalones, isEmpty);
    });

    screenTest('starting a collection is one sheet: the name, the count and '
        'the launch together', (tester) async {
      // The regression this pins: *New collection* used to take over the
      // picker with a screen holding one text field, and the sheet that
      // followed printed the same name in its header (V2-D57).
      await h.root();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));

      await tapAndPump(tester, key('v2AddToCollection'));
      await pumpUntil(tester, key('collectionPickerNew'));
      await tapAndPump(tester, key('collectionPickerNew'));

      // Straight to the one sheet. No naming surface on the way, and no
      // second chance to answer the same question.
      await pumpUntil(tester, key('saveScopeFromHere'));
      expect(
        key('collectionCreateConfirm'),
        findsNothing,
        reason:
            'the picker no longer confirms a name it is not the last '
            'surface for',
      );
      expect(key('collectionNameField'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('collectionNameField')).controller!.text,
        _entryTitle,
        reason: 'what the page called the work, offered as a suggestion',
      );
      expect(
        find.text('First source · reading.example.com'),
        findsOneWidget,
        reason: 'the site that becomes its first source is named here',
      );

      await tester.enterText(key('collectionNameField'), 'Alpha');
      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '4');
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(
        adds.single.newCollectionName,
        'Alpha',
        reason:
            'the edited name is what the domain is asked to create, not '
            'the suggestion it replaced',
      );
      expect(adds.single.collectionId, isNull);
      expect(adds.single.limits!.maxEntries, 4);
      expect(adds.single.discoverMissing, isTrue);
      expect(standalones, isEmpty);
    });

    screenTest('a blank name on that sheet starts nothing at all', (
      tester,
    ) async {
      await h.root();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));
      await tapAndPump(tester, key('v2AddToCollection'));
      await pumpUntil(tester, key('collectionPickerNew'));
      await tapAndPump(tester, key('collectionPickerNew'));
      await pumpUntil(tester, key('collectionNameField'));

      await tester.enterText(key('collectionNameField'), '   ');
      await launch(tester, key('saveScopeAddToQueue'));

      expect(find.text('Give this collection a name.'), findsOneWidget);
      expect(adds, isEmpty, reason: 'nothing was asked of the domain');
      expect(key('saveScopeFromHere'), findsOneWidget);
    });

    screenTest('an existing collection is chosen and not renamed', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));

      await tapAndPump(tester, key('v2AddToCollection'));
      // The page's title suggests a filter that matches none of them, and the
      // way back to the whole list is one visible tap.
      await pumpUntil(tester, key('collectionPickerClearFilter'));
      await tapAndPump(tester, key('collectionPickerClearFilter'));
      await pumpUntil(tester, key('collectionOption-${collection.id}'));
      await tapAndPump(tester, key('collectionOption-${collection.id}'));
      await pumpUntil(tester, key('saveScopeAddToQueue'));

      expect(
        key('collectionNameField'),
        findsNothing,
        reason: 'a collection that exists is not renamed on the way past',
      );
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds.single.collectionId, collection.id);
      expect(adds.single.newCollectionName, isNull);
    });

    screenTest('a page that could be a listing offers the site itself, and '
        'adding it writes no entry', (tester) async {
      await h.root();
      await openPanel(tester, _indexUrl, _indexTitle);

      // On a site the library knows nothing about, "this is a listing" is not
      // a claim the app can make — the same address shape describes an about
      // page. So all three answers are offered and none is assumed: the loose
      // save, a Collection to put it in, and the site itself.
      await pumpUntil(tester, key('v2AddCollection'));
      expect(key('v2SaveStandalone'), findsOneWidget);
      expect(key('v2AddToCollection'), findsOneWidget);

      await tapAndPump(tester, key('v2AddCollection'));
      await pumpUntil(tester, key('collectionPickerNew'));
      await tapAndPump(tester, key('collectionPickerNew'));
      await tapAndPump(tester, key('collectionCreateConfirm'));

      expect(adds, hasLength(1));
      expect(adds.single.newCollectionName, 'Alpha');
      expect(
        adds.single.limits,
        isNull,
        reason: 'no entry is created for the index page itself',
      );
      expect(
        adds.single.isListing,
        isTrue,
        reason: 'the sheet tells the domain what the user answered',
      );
      await pumpUntil(tester, key('v2CheckAfterAdd'));
    });

    screenTest('an ordinary page leads with standalone', (tester) async {
      await h.root();
      await openPanel(tester, _plainUrl, _plainTitle);

      await pumpUntil(tester, key('v2SaveStandalone'));
      expect(tester.widget(key('v2SaveStandalone')), isA<FilledButton>());
      expect(tester.widget(key('v2AddToCollection')), isA<TextButton>());

      await tapAndPump(tester, key('v2SaveStandalone'));

      expect(standalones, [_plainUrl]);
      expect(adds, isEmpty);
      expect(find.text('Saved on its own.'), findsOneWidget);
    });
  });

  // ─── the question that was asked every single time ──────────────────────

  group('what this collection is usually saved as', () {
    // The regression: `CaptureMode` was a queue-row column and nothing else,
    // so *What to save* was asked on the first entry of a work and on the
    // five-hundredth, with the same three rows and the same detected default.
    Future<String> seedKnownEntry() async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      final source = await h.source(collection.id, pathKey: '/works/alpha');
      final entry = await h.entryIn(
        collection.id,
        title: _entryTitle,
        ordinal: 12,
      );
      await h.location(entry.id, _entryUrl, sourceId: source.id);
      reportedCollectionId = collection.id;
      return collection.id;
    }

    screenTest('with nothing remembered the full block is asked', (
      tester,
    ) async {
      await seedKnownEntry();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      expect(find.text('What to save'), findsOneWidget);
      expect(key('captureModeRemembered'), findsNothing);
    });

    screenTest('a remembered answer stands in for the block', (tester) async {
      final collectionId = await seedKnownEntry();
      await CapturePreferenceStore(
        LocalSettingsStore(h.db),
      ).remember(collectionId, CaptureMode.imageSequence);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('captureModeRemembered'));

      expect(
        find.text('What to save'),
        findsNothing,
        reason: 'the question has an answer, so it is not asked again',
      );
      // One line: the word, the answer, and the way in — no detection
      // sentence, no three descriptions, no reasons for modes nobody is
      // choosing between right now (V2-D60).
      expect(find.text('Capture'), findsOneWidget);
      expect(find.text('Images only'), findsOneWidget);
      expect(find.text(CaptureMode.imageSequence.description), findsNothing);
      expect(key('captureDetectionSummary'), findsNothing);
      expect(key('captureMode_textOnly'), findsNothing);

      // And everything the block says is one tap away — on the row itself,
      // not on a button beside it, and not behind a second sheet.
      await tapAndPump(tester, key('captureModeRemembered'));
      expect(find.text('What to save'), findsOneWidget);
      expect(key('captureMode_textOnly'), findsOneWidget);
      expect(key('captureModeRemembered'), findsNothing);
    });

    screenTest('the remembered answer is what the save is asked for', (
      tester,
    ) async {
      final collectionId = await seedKnownEntry();
      await CapturePreferenceStore(
        LocalSettingsStore(h.db),
      ).remember(collectionId, CaptureMode.imageSequence);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('captureModeRemembered'));
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds.single.captureMode, CaptureMode.imageSequence);
      expect(
        adds.single.captureModeIsUserSet,
        isFalse,
        reason:
            'preselected from the work\'s standing answer, which is not the '
            'same fact as a person having chosen it on this page',
      );
    });

    screenTest('changing it through the line rewrites the collection\'s '
        'answer', (tester) async {
      final collectionId = await seedKnownEntry();
      final preferences = CapturePreferenceStore(LocalSettingsStore(h.db));
      await preferences.remember(collectionId, CaptureMode.imageSequence);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('captureModeRemembered'));
      await tapAndPump(tester, key('captureModeRemembered'));
      await tapAndPump(tester, key('captureMode_imageSequence'));
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds.single.captureMode, CaptureMode.imageSequence);
      expect(
        adds.single.captureModeIsUserSet,
        isTrue,
        reason: 'this time a person did choose it, on this page',
      );
      expect(await preferences.of(collectionId), CaptureMode.imageSequence);
    });

    screenTest('proceeding with the proposed mode is what remembers it', (
      tester,
    ) async {
      // The rule this replaces: only a tap counted, so a user already looking
      // at *Images only* had to tap *Images only* before the app would
      // believe them — and a work saved as images fifty times running still
      // asked on the fifty-first (V2-D61).
      final collectionId = await seedKnownEntry();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      expect(find.text('What to save'), findsOneWidget);
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1), reason: 'the save happened');
      expect(
        adds.single.captureModeIsUserSet,
        isFalse,
        reason: 'accepted, not chosen — the capture is not told otherwise',
      );
      expect(
        await CapturePreferenceStore(LocalSettingsStore(h.db)).of(collectionId),
        CaptureMode.imageSequence,
      );
    });

    screenTest('opening the sheet and saving nothing says nothing', (
      tester,
    ) async {
      // Acceptance is *starting a save*, not *seeing a proposal*.
      final collectionId = await seedKnownEntry();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      expect(find.text('What to save'), findsOneWidget);
      expect(adds, isEmpty);
      expect(
        await CapturePreferenceStore(LocalSettingsStore(h.db)).of(collectionId),
        isNull,
      );
    });

    screenTest('a lazy page does not un-remember what the collection is kept '
        'as', (tester) async {
      // The bug this pins. The sheet measures the page **before** it has been
      // scrolled, so on a lazy reader almost no images have loaded yet and
      // *Images only* looks impossible. Vetoing the remembered answer on that
      // measurement put the full three-row block back on every save of a work
      // the user had already settled — while the engine, which measures the
      // settled page, would have saved it as images all along (V2-D65).
      final collectionId = await seedKnownEntry();
      await CapturePreferenceStore(
        LocalSettingsStore(h.db),
      ).remember(collectionId, CaptureMode.imageSequence);

      await openPanel(
        tester,
        _entryUrl,
        _entryTitle,
        probe: lazyImagePageProbe(_entryUrl, _entryTitle),
      );
      await pumpUntil(tester, key('saveScopeThisEntry'));

      expect(
        key('captureModeRemembered'),
        findsOneWidget,
        reason: 'an unscrolled page cannot rule out an image save',
      );
      expect(find.text('What to save'), findsNothing);
      expect(key('captureMode_textOnly'), findsNothing);

      // And what the save is asked for is the remembered mode itself: the
      // engine re-resolves it on the settled page and falls back there, with
      // an explanation, if it truly cannot be honoured.
      await launch(tester, key('saveScopeAddToQueue'));
      expect(adds.single.captureMode, CaptureMode.imageSequence);
    });

    screenTest('*Ask each time* keeps asking, save after save', (tester) async {
      // The label is a promise. Because proceeding now records a mode, the
      // answer has to be stored as an answer or the next download would
      // quietly undo it (V2-D61).
      final collectionId = await seedKnownEntry();
      final preferences = CapturePreferenceStore(LocalSettingsStore(h.db));
      await preferences.askEachTime(collectionId);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));
      expect(find.text('What to save'), findsOneWidget);
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(
        await preferences.of(collectionId),
        isNull,
        reason: 'the save proposed a mode; it did not become a standing one',
      );
      expect(await preferences.isAnswered(collectionId), isTrue);
    });

    screenTest('a page that could not honour it does not redefine the work', (
      tester,
    ) async {
      // The other half of "the preference proposes and the page disposes"
      // (V2-D53): the mode on screen here is the *fallback*, and saving with
      // it must not turn one awkward entry into a new standing answer.
      final collectionId = await seedKnownEntry();
      final preferences = CapturePreferenceStore(LocalSettingsStore(h.db));
      await preferences.remember(collectionId, CaptureMode.textOnly);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));
      // The probe carries no prose, so text-only is blocked and the block is
      // asked again with the image fallback selected.
      expect(find.text('What to save'), findsOneWidget);
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.captureMode, CaptureMode.imageSequence);
      expect(
        await preferences.of(collectionId),
        CaptureMode.textOnly,
        reason: 'one page could not honour it; that is not a change of mind',
      );
    });

    screenTest('a page that cannot honour it asks again', (tester) async {
      final collectionId = await seedKnownEntry();
      await CapturePreferenceStore(
        LocalSettingsStore(h.db),
      ).remember(collectionId, CaptureMode.textOnly);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      // The probe carries no readable prose, so text-only is blocked here.
      // The preference proposes; the page disposes — and the preference is
      // left alone, because it was an answer about the work.
      expect(key('captureModeRemembered'), findsNothing);
      expect(find.text('What to save'), findsOneWidget);
      expect(
        await CapturePreferenceStore(LocalSettingsStore(h.db)).of(collectionId),
        CaptureMode.textOnly,
        reason: 'one page could not honour it; that is not a change of mind',
      );
    });

    screenTest('choosing a mode and saving remembers it for that collection', (
      tester,
    ) async {
      final collectionId = await seedKnownEntry();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      await tapAndPump(tester, key('captureMode_imageSequence'));
      await launch(tester, key('saveScopeAddToQueue'));

      expect(
        await CapturePreferenceStore(LocalSettingsStore(h.db)).of(collectionId),
        CaptureMode.imageSequence,
      );
    });

    screenTest('a standalone save redefines no collection', (tester) async {
      // The rule: an Entry-specific choice must not silently become a
      // standing instruction about a work it has nothing to do with.
      final collectionId = await seedKnownEntry();
      await h.root();
      await openPanel(tester, _plainUrl, _plainTitle);
      await pumpUntil(tester, key('v2SaveStandalone'));

      await tapAndPump(tester, key('captureMode_imageSequence'));
      await tapAndPump(tester, key('v2SaveStandalone'));

      expect(standalones, [_plainUrl]);
      expect(
        await CapturePreferenceStore(LocalSettingsStore(h.db)).of(collectionId),
        isNull,
      );
    });
  });

  // ─── where the user waits, and who decides ──────────────────────────────

  group('the launch row is the gate\'s own', () {
    // The rule this pins: the operation is never gated, and the one thing Pro
    // buys is where the user waits. Folding the launch into the scope sheet
    // must not have folded the boundary into it — the rows come from
    // `ForegroundStartActions`, so there is no second answer to the question
    // anywhere in this lane.
    Future<void> seedEntry() async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      final source = await h.source(collection.id, pathKey: '/works/alpha');
      final entry = await h.entryIn(
        collection.id,
        title: _entryTitle,
        ordinal: 12,
      );
      await h.location(entry.id, _entryUrl, sourceId: source.id);
      reportedCollectionId = collection.id;
    }

    Future<void> openScope(WidgetTester tester) async {
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeFromHere'));
      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '3');
      await tester.pump();
    }

    screenTest('without the capability, the visible-Browser start is fully '
        'functional and *Queue only* needs nothing at all', (tester) async {
      await seedEntry();
      await openScope(tester);

      expect(key('startInBrowser'), findsOneWidget);
      expect(key('saveScopeAddToQueue'), findsOneWidget);
      expect(
        key('startKeepUsingApp'),
        findsNothing,
        reason: 'not available, so not offered as though it were',
      );
      expect(
        key('startKeepUsingAppLocked'),
        findsOneWidget,
        reason:
            'named and tappable, never a disabled control that explains '
            'nothing',
      );

      await launch(tester, key('startInBrowser'));
      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 3);
    });

    screenTest('with it, the launch that keeps the user where they are is '
        'the same one answer', (tester) async {
      capability.override = EntitlementOverride.forcePro;
      capability.preference = true;
      await seedEntry();
      await openScope(tester);

      expect(key('startKeepUsingApp'), findsOneWidget);
      await launch(tester, key('startKeepUsingApp'));

      expect(adds, hasLength(1));
      expect(
        key('startOptionsCancel'),
        findsNothing,
        reason: 'the gate was answered here; nothing asks again',
      );
    });

    screenTest('a collection being created answers it in the same sheet, and '
        'is not asked twice', (tester) async {
      await h.root();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));
      await tapAndPump(tester, key('v2AddToCollection'));
      await pumpUntil(tester, key('collectionPickerNew'));
      await tapAndPump(tester, key('collectionPickerNew'));
      await pumpUntil(tester, key('collectionNameField'));

      await tester.enterText(key('collectionNameField'), 'Quiet Harbour');
      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '3');
      await tester.pump();
      await launch(tester, key('startInBrowser'));

      expect(adds, hasLength(1));
      expect(adds.single.newCollectionName, 'Quiet Harbour');
      expect(adds.single.limits!.maxEntries, 3);
      expect(
        key('startOptionsCancel'),
        findsNothing,
        reason:
            'naming a collection did not put the launch back on a second '
            'surface',
      );
      expect(key('collectionCreateConfirm'), findsNothing);
    });
  });

  // ─── the routine flow, end to end ───────────────────────────────────────

  // ─── the lifecycle, end to end (V2-D61) ─────────────────────────────────

  group('the first save answers it and the next one does not ask', () {
    // One test, one journey, because the claim is about what happens *between*
    // two saves. Every step is a control a user would press.
    screenTest('accept on the first entry, compact on the second', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      final source = await h.source(collection.id, pathKey: '/works/alpha');
      final first = await h.entryIn(
        collection.id,
        title: _entryTitle,
        ordinal: 12,
      );
      await h.location(first.id, _entryUrl, sourceId: source.id);
      final second = await h.entryIn(
        collection.id,
        title: 'Alpha 13',
        ordinal: 13,
      );
      const secondUrl = 'https://reading.example.com/works/alpha/13';
      await h.location(second.id, secondUrl, sourceId: source.id);
      reportedCollectionId = collection.id;
      final preferences = CapturePreferenceStore(LocalSettingsStore(h.db));

      // ── first save: nothing is remembered, so the whole block is asked,
      // on the same sheet as the range and the launch (V2-D62).
      expect(await preferences.of(collection.id), isNull);
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('saveScopeThisEntry'));

      expect(find.text('What to save'), findsOneWidget);
      expect(key('captureMode_imageSequence'), findsOneWidget);
      expect(key('captureModeRemembered'), findsNothing);
      expect(
        key('v2DownloadEntries'),
        findsNothing,
        reason: 'there is no second sheet to open',
      );

      // The range is on the smallest answer and the count field belongs to
      // the counted one, so it is not there until it is asked for.
      expect(key('saveCountField'), findsNothing);
      await tapAndPump(tester, key('saveScopeFromHere'));
      expect(key('saveScopeReadsForwardNote'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('saveCountField')).autofocus,
        isFalse,
        reason:
            'choosing a range is not asking for a keyboard over the '
            'launches below it',
      );

      // …and the proposal is never tapped. Proceeding is the acceptance.
      await tester.enterText(key('saveCountField'), '4');
      await launch(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 4);
      expect(adds.single.discoverMissing, isTrue);
      expect(adds.single.captureMode, CaptureMode.imageSequence);
      expect(
        adds.single.captureModeIsUserSet,
        isFalse,
        reason: 'accepted, not chosen',
      );
      expect(
        await preferences.of(collection.id),
        CaptureMode.imageSequence,
        reason: 'starting the save is the acceptance',
      );

      // ── second save, another entry of the same work: compact, no question
      await openPanel(tester, secondUrl, 'Alpha 13');
      await pumpUntil(tester, key('captureModeRemembered'));

      expect(find.text('Capture'), findsOneWidget);
      expect(find.text('Images only'), findsOneWidget);
      expect(
        find.text('What to save'),
        findsNothing,
        reason: 'the question has an answer and is not asked again',
      );
      expect(key('captureMode_imageSequence'), findsNothing);
      expect(key('captureMode_textOnly'), findsNothing);
      expect(
        key('saveScopeThisEntry'),
        findsOneWidget,
        reason: 'and the range is still right here, on the same sheet',
      );
      expect(key('captureDetectionSummary'), findsNothing);
    });
  });

  group('a collection the app already knows', () {
    // The shape this pass is aiming at, asserted rather than described:
    //
    //     Collection · Alpha
    //     Entry · 12
    //     Source · reading.example.com
    //
    //     Images only        [what this collection is usually saved as]
    //     Download this entry
    //     Download entries…
    //
    // Two taps to the ordinary download, and every question already
    // answered — which is the point of items 5, 6 and 8 together.
    screenTest('is two taps and no questions', (tester) async {
      final root = await h.root();
      final collection = await h.collection('Alpha', folderId: root.id);
      final source = await h.source(collection.id, pathKey: '/works/alpha');
      final entry = await h.entryIn(
        collection.id,
        title: _entryTitle,
        ordinal: 12,
      );
      await h.location(entry.id, _entryUrl, sourceId: source.id);
      reportedCollectionId = collection.id;
      await CapturePreferenceStore(
        LocalSettingsStore(h.db),
      ).remember(collection.id, CaptureMode.imageSequence);

      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('captureModeRemembered'));

      // Context: where it is and what it is, on one line.
      expect(find.text('Alpha · Entry 12'), findsOneWidget);
      expect(
        find.text('In your library.'),
        findsNothing,
        reason: 'the collection name is already the answer to that',
      );
      // The capture question, answered.
      expect(find.text('What to save'), findsNothing);
      expect(find.text('Images only'), findsOneWidget);

      // And the download is the next tap, with nothing in between: the range
      // is already on this sheet, on its smallest answer.
      expect(key('saveCountField'), findsNothing);
      await launch(tester, key('saveScopeAddToQueue'));
      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 1);
      expect(key('startOptionsCancel'), findsNothing);
    });
  });
}
