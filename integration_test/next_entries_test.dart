// "Download the next N from here", end to end against the in-process fixture
// on a real WebView.
//
//   flutter test integration_test/next_entries_test.dart -d <device-id>
//
// Nothing here is hand-built. The page is opened through the Browser the app
// opens every page through, the save control is the Browser's own, the
// Collection is created through the picker, the count is typed into the
// recovered scope sheet, the run is authorised through the same start sheet
// the update check uses, and every Entry, Location and queue row asserted
// afterwards was written by the orchestration rather than by this file.
//
// ## What this suite is for
//
// A typed count is a claim about the **Source**, not about the library
// (docs/V2_SAVE_FLOW.md §4). On a site nothing has been read from, the library
// knows one entry — the one in front of the reader — so "five from here" can
// only be answered by reading this site forward. These cases are that answer:
// entries 1..5 arrive as Entries of one Collection with Locations on that
// Source, five queue rows wait, no Entry appears twice, and **not a byte is
// captured until an explicit Start**.
//
// The count is inclusive: five from entry 1 is entries 1 through 5. That is
// asserted here rather than described, because an off-by-one in that rule is
// the difference between what the user asked for and what they got.
//
// ## Why `/text/N` and not `/entry/N`
//
// Both are chained by `rel="next"`, and only one of them can carry a Source.
// A Source's identity is `(host, path_key)`, and the path key of
// `/entry/1` collapses to `/` — `collectionFingerprint` strips the number and
// then strips `entry` as an entry word, leaving nothing. Adoption refuses that
// in words ("this address does not identify a site section this app can
// follow", I5), which is the correct product answer and was reproduced on
// device while writing this suite. `/text/1` keeps `/text`, so the Collection
// the walk belongs to can exist. The prose pages carry both a `<link
// rel="next">` and an anchor, and nothing here captures, so what the page
// holds beyond that does not matter.
//
// ## AT MERGE — this suite fails until the walk half lands
//
// The reading forward is `SourceWalk` (`lib/recognition/walk.dart`) and the
// `discoverMissing` branch of `v2AddAndDownload`, which are the other half of
// this change. Until both are on the branch the flow is real and complete up
// to the run itself — save control, picker, count, gate, authorisation — and
// then only the page the user was on is added. Measured on the iPhone 17
// simulator against this fixture, that is: Collection *Fixture text*, Source
// `127.0.0.1`, Entry 1, one queue row waiting and no copy. So every count
// assertion below reports one Entry where it wanted five, which is the
// correct failure, and it turns green with no edit to this file when the walk
// lands.
//
// One sentence has to change with it: the panel currently reports "Your
// library knows 1 of the 5 asked for; checking this collection for updates
// can find more", which is the library-only answer and is the wrong thing to
// say about a count that just read the site forward.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/queue_task.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A chain longer than any count typed below, so *reaching the count* and
  /// *running out of Source* are two different cases rather than one.
  /// `kEntryCount` itself is left alone — other suites are written against it.
  final fixture = FixtureSite(entryCount: 8);
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  /// One entry of the fixture's prose collection — the shape a Source can be
  /// made from. See the header.
  String entry(int n) => '${fixture.base}/text/$n';

  Future<void> boot(WidgetTester tester, {required String startUrl}) async {
    app = V2App(tag: 'next_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    // A WKWebView that has never been painted reports zero layout metrics, and
    // `openPage` also dismisses Browser Home — so the page the save controls
    // describe is the page on screen.
    await showBrowser(tester);
    await openPage(tester, app, startUrl);
  }

  tearDown(() => app.shutdown());

  Finder key(String value) => find.byKey(ValueKey(value));

  /// Poll the library while the tree keeps pumping.
  ///
  /// [pumpUntil] takes a synchronous predicate and every question here is a
  /// database read, so this is that helper with an awaited condition. It
  /// returns what it last saw rather than failing, and the case says what a
  /// short answer means.
  Future<T> pumpUntilAsync<T>(
    WidgetTester tester,
    Future<T> Function() read,
    bool Function(T) done, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var seen = await read();
    while (!done(seen) && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      seen = await read();
    }
    return seen;
  }

  /// Browser → Save → *Add to a Collection…* → a new Collection → the count.
  ///
  /// Every step is the control a user would press. Ends with the scope sheet
  /// on screen and the count typed, ready for one of its two launches.
  Future<void> askForEntriesFromHere(WidgetTester tester, int count) async {
    final saveAction = key('browserSaveAction');
    expect(saveAction, findsOneWidget);
    await tester.tap(saveAction, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    // A numbered fixture entry on a site the library knows nothing about reads
    // as one entry of a collection, so the sheet leads with the Collection.
    expect(
      key('v2AddToCollection'),
      findsOneWidget,
      reason: 'a serialized page is never standalone by default',
    );
    await tester.tap(key('v2AddToCollection'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(key('collectionPickerNew'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(key('collectionCreateConfirm'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(
      key('saveScopeFromHere'),
      findsOneWidget,
      reason: 'the count is the second question the sheet asks',
    );
    await tester.tap(key('saveScopeFromHere'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(key('saveCountField'), '$count');
    await pumpFor(tester, const Duration(seconds: 1));

    // OK, exactly as an iOS user has to: the number pad has no return key, so
    // this is the way out of it — and the bar it sits on is taking the room
    // the launches need until it goes.
    expect(key('saveCountOk'), findsOneWidget);
    await tester.tap(key('saveCountOk'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
  }

  /// *Add to queue*, then the start sheet — the same one the update check
  /// shows, because this run may open pages too.
  ///
  /// *Start in Browser* rather than the multitasking start: it is offered
  /// whatever the build's entitlement, so it is the one a harness may press.
  Future<void> queueAndAuthorise(WidgetTester tester) async {
    await tester.ensureVisible(key('saveScopeAddToQueue'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(key('saveScopeAddToQueue'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(
      key('startInBrowser'),
      findsOneWidget,
      reason:
          'a count taken from the Source may open a page, so it is gated the '
          'way the check is — before anything is opened',
    );
    await tester.tap(key('startInBrowser'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));
  }

  /// The one Collection this suite's flow creates, once it exists.
  Future<CollectionRow?> theCollection() async {
    final root = await app.ui.folders.ensureRoot();
    final rows = await app.ui.collections.inFolder(root.id);
    return rows.isEmpty ? null : rows.single;
  }

  testWidgets(
    'five from here reads this site forward and queues entries 1 to 5',
    (tester) async {
      await boot(tester, startUrl: entry(1));

      await askForEntriesFromHere(tester, 5);

      // Nothing has been asked for yet: the sheet is open, and the count is
      // typed into it.
      expect(await app.ui.queue.all(), isEmpty);

      await queueAndAuthorise(tester);

      final queued = await pumpUntilAsync(
        tester,
        () => app.ui.queue.all(),
        (rows) => rows.length >= 5,
        timeout: const Duration(minutes: 4),
      );
      expect(
        queued,
        hasLength(5),
        reason:
            'five was a claim about the Source: the library knew one of them, '
            'and reading forward is how the other four were found',
      );

      final collection = await theCollection();
      expect(collection, isNotNull, reason: 'one Collection, created once');
      final sources = await app.ui.collections.sourcesOf(collection!.id);
      expect(sources, hasLength(1), reason: 'one site was read, so one Source');

      final entries = await app.ui.entries.entriesOf(collection.id);
      expect(
        entries,
        hasLength(5),
        reason:
            'entries 1..5, each once — the count includes the page the '
            'user was on',
      );

      // Every Entry is on this Source, at the address the site itself linked.
      final urls = <String>[];
      for (final entry in entries) {
        final locations = await app.ui.entries.locationsOf(entry.id);
        expect(
          locations,
          hasLength(1),
          reason: 'a walked page is reconciled, so no Entry gains a twin',
        );
        expect(
          locations.single.sourceId,
          sources.single.id,
          reason: 'the Source is the one being read, never another',
        );
        urls.add(locations.single.url);
      }
      expect(
        urls.toSet(),
        {for (var n = 1; n <= 5; n++) entry(n)},
        reason: 'inclusive of this page, and no address was invented',
      );

      // One queue row per Entry, and no row for anything else.
      expect(
        queued.map((t) => t.entryId).toSet(),
        entries.map((e) => e.id).toSet(),
      );
      for (final task in queued) {
        expect(
          task.state,
          SaveTaskState.queued,
          reason: 'a queued download waits for Start; nothing here started it',
        );
      }

      // The half of the rule that matters most: reading a site forward is not
      // downloading it.
      expect(
        await app.ui.offline.allCopies(),
        isEmpty,
        reason: 'nothing captures until an explicit Start',
      );
      expect(app.runner.isRunning, isFalse);
      expect(
        app.ui.queue.saveStartAuthorised,
        isFalse,
        reason: 'authorising the reading is not authorising the downloads',
      );

      debugPrint('[next] queued ${queued.length} rows for $urls');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a Source that ends first is an answer, not a failure',
    (tester) async {
      // Six of eight, asking for five: the chain ends after 8, so three is
      // everything there is. "There were only three" is a fact about the
      // Source, and the entries it did resolve stay resolved.
      await boot(tester, startUrl: entry(6));

      await askForEntriesFromHere(tester, 5);
      await queueAndAuthorise(tester);

      final queued = await pumpUntilAsync(
        tester,
        () => app.ui.queue.all(),
        (rows) => rows.length >= 3,
        timeout: const Duration(minutes: 4),
      );
      expect(
        queued,
        hasLength(3),
        reason: 'entries 6, 7 and 8 — and nothing beyond the end of the chain',
      );

      final collection = await theCollection();
      final entries = await app.ui.entries.entriesOf(collection!.id);
      expect(entries, hasLength(3));

      final urls = <String>{};
      for (final entry in entries) {
        final locations = await app.ui.entries.locationsOf(entry.id);
        urls.add(locations.single.url);
      }
      expect(urls, {for (var n = 6; n <= 8; n++) entry(n)});

      expect(
        await app.ui.offline.allCopies(),
        isEmpty,
        reason: 'a short walk still downloads nothing on its own',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  // ------------------------------------------------------------- AT MERGE
  //
  // **The stop.** Reading a Source forward is content-affecting source
  // automation, so it is user-started, visible, bounded *and cancellable* —
  // and the cancellation seam does not exist on this branch. The compact
  // running surface is `running_operation_panel.dart`, which draws its Stop
  // over a controller publishing *is it running* and *stop it*
  // (`QueueRunner`, `CheckController`). The walk needs the same two things
  // published by whatever owns it, plus a third branch in that panel wired to
  // its cancel, exactly as `_CheckRunning` is.
  //
  // This case is written against that seam and skipped until it lands. It
  // asks for eight from entry 1 — a walk long enough to still be reading when
  // the Stop is pressed — and asserts the two halves of a cooperative stop:
  // it ends, and what it had already resolved is still in the library.
  //
  // Un-skip in the same change that adds `panelStopReadingForward` to the
  // running panel.
  testWidgets(
    'stopping a walk keeps what it had already found',
    (tester) async {
      await boot(tester, startUrl: entry(1));

      await askForEntriesFromHere(tester, 8);
      await queueAndAuthorise(tester);

      // The panel is docked under the WebView, so the walk is named and
      // stoppable while it runs.
      await pumpUntil(
        tester,
        () => key('panelStopReadingForward').evaluate().isNotEmpty,
        timeout: const Duration(minutes: 2),
        reason: 'a run that opens pages is visible while it does',
      );
      await tester.tap(key('panelStopReadingForward'), warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 3));

      final settled = await pumpUntilAsync(
        tester,
        () => app.ui.queue.all(),
        (rows) => rows.isNotEmpty,
        timeout: const Duration(minutes: 2),
      );
      expect(
        settled.length,
        lessThan(8),
        reason: 'the stop was asked for before the count was reached',
      );

      final collection = await theCollection();
      final entries = await app.ui.entries.entriesOf(collection!.id);
      expect(
        entries.length,
        settled.length,
        reason: 'a stopped walk keeps every Entry it had already resolved',
      );
      expect(await app.ui.offline.allCopies(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: true,
  );
}
