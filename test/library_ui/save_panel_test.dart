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
import 'package:web_reader/core/config.dart';
// STUB IMPORT — switch to 'package:web_reader/features/v2_add_flow.dart' at
// merge.
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_adoption_providers.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/capture_mode.dart';
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
  });

  final String url;
  final String? collectionId;
  final String? newCollectionName;
  final SaveLimits? limits;

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

  setUp(() {
    h = UiHarness();
    browser = FakeBrowser();
    adds = [];
    standalones = [];
  });
  tearDown(() => h.close());

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
      ),
    );
    return AddToLibraryReport(
      sentence: 'The domain said what it did.',
      collectionId: collectionId ?? 'made-up-collection',
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

  Future<void> openPanel(WidgetTester tester, String url, String title) async {
    browser
      ..setUrl(url)
      ..addPage(url, probeOf(url, title));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(h.services),
          browserProvider.overrideWithValue(browser),
          saveQueueStarterProvider.overrideWithValue(h.starter),
          v2AddAndDownloadProvider.overrideWithValue(fakeAdd),
          v2SaveStandaloneProvider.overrideWithValue(fakeStandalone),
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
      return entry.id;
    }

    screenTest('a walk in flight is stopped from the sheet that started it', (
      tester,
    ) async {
      await h.root();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2AddToCollection'));

      // The panel's own Stop is docked at the bottom of the Browser — which is
      // exactly where this sheet sits. A control the user must dismiss the
      // sheet to reach is not reachable while the thing it stops is running.
      final panel = tester.state(find.byType(V2SavePanel));
      // ignore: avoid_dynamic_calls
      (panel as dynamic).debugSetReadingForward(true);
      await tester.pump();

      expect(key('sheetStopReadingForward'), findsOneWidget);
      await tapAndPump(tester, key('sheetStopReadingForward'));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(V2SavePanel)),
      );
      expect(
        container.read(sourceWalkCancellationProvider).isCancelled,
        isTrue,
        reason: 'the sheet must be able to stop what the sheet started',
      );
    });

    screenTest('offers the two downloads, and names what the library knows', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2DownloadEntry'));
      expect(key('v2DownloadEntries'), findsOneWidget);
      expect(find.text('Collection · Alpha'), findsOneWidget);
      expect(find.text('Entry · 12'), findsOneWidget);
      expect(find.text('Source · reading.example.com'), findsOneWidget);
      expect(
        key('v2AddToCollection'),
        findsNothing,
        reason: 'it is already in one',
      );
    });

    screenTest('downloading this entry asks for exactly one', (tester) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2DownloadEntry'));

      await tapAndPump(tester, key('v2DownloadEntry'));

      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 1);
      expect(
        adds.single.collectionId,
        isNull,
        reason: 'recognition already places it; nothing is being adopted',
      );
      expect(find.text('The domain said what it did.'), findsOneWidget);
    });

    screenTest('the count sheet carries the number onto the call', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2DownloadEntries'));

      await tapAndPump(tester, key('v2DownloadEntries'));
      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '5');
      await tapAndPump(tester, key('saveScopeAddToQueue'));

      // A count taken from the Source may have to open a page, so the panel
      // asks where the user waits before anything starts — the check's sheet,
      // not a second one.
      await pumpUntil(tester, key('startInBrowser'));
      expect(adds, isEmpty, reason: 'nothing runs until that is answered');
      await tapAndPump(tester, key('startInBrowser'));

      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 5);
      expect(
        adds.single.discoverMissing,
        isTrue,
        reason: 'the typed count is a claim about the Source',
      );
    });

    screenTest('backing out of that question starts nothing at all', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2DownloadEntries'));

      await tapAndPump(tester, key('v2DownloadEntries'));
      await tapAndPump(tester, key('saveScopeFromHere'));
      await tester.enterText(key('saveCountField'), '4');
      await tapAndPump(tester, key('saveScopeAddToQueue'));
      await pumpUntil(tester, key('startOptionsCancel'));
      await tapAndPump(tester, key('startOptionsCancel'));

      expect(adds, isEmpty);
    });

    screenTest('the quieter range opens nothing, so it is never gated', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2DownloadEntries'));

      await tapAndPump(tester, key('v2DownloadEntries'));
      await tapAndPump(tester, key('saveScopeKnownOnly'));
      await tester.enterText(key('saveCountField'), '5');
      await tapAndPump(tester, key('saveScopeAddToQueue'));

      expect(key('startInBrowser'), findsNothing);
      expect(adds, hasLength(1));
      expect(adds.single.limits!.maxEntries, 5);
      expect(adds.single.discoverMissing, isFalse);
    });

    screenTest('this entry alone is never gated and discovers nothing', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);
      await pumpUntil(tester, key('v2DownloadEntry'));

      await tapAndPump(tester, key('v2DownloadEntry'));

      expect(
        key('startInBrowser'),
        findsNothing,
        reason: 'the page is already in front of the user; nothing is opened',
      );
      expect(adds.single.discoverMissing, isFalse);
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

      await pumpUntil(tester, key('v2AddAndDownloadEntry'));
      expect(key('v2AddAndDownloadEntries'), findsOneWidget);
      expect(find.text('Adds to Alpha.'), findsOneWidget);
      expect(
        key('v2SaveStandalone'),
        findsNothing,
        reason: 'the library knows where this belongs',
      );

      await tapAndPump(tester, key('v2AddAndDownloadEntry'));

      expect(adds, hasLength(1));
      expect(adds.single.collectionId, isNotNull);
      expect(adds.single.limits!.maxEntries, 1);
    });

    screenTest('does not offer Follow for a collection already followed', (
      tester,
    ) async {
      await seed();
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2AddAndDownloadEntry'));
      expect(key('v2FollowCollection'), findsNothing);
    });

    screenTest('offers Follow beside the download, never folded into it', (
      tester,
    ) async {
      await seed(archived: true);
      await openPanel(tester, _entryUrl, _entryTitle);

      await pumpUntil(tester, key('v2FollowCollection'));
      expect(
        key('v2AddAndDownloadEntry'),
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
        find.textContaining('adds this site as another source'),
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
      await tapAndPump(tester, key('saveScopeAddToQueue'));

      expect(adds, hasLength(1));
      expect(adds.single.collectionId, collection.id);
      expect(adds.single.newCollectionName, isNull);
      expect(adds.single.limits!.maxEntries, 1);
      expect(adds.single.discoverMissing, isFalse);
      expect(standalones, isEmpty);
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
}
