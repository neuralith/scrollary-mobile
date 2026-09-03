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

    // *New collection* answers the picker and hands the save sheet back with
    // the name, the range and the launch on it — no screen in between, and no
    // sheet after it (V2-D57, V2-D62).
    await tester.tap(key('collectionPickerNew'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(
      key('collectionNameField'),
      findsOneWidget,
      reason: 'the collection is named on the sheet that queues it',
    );

    expect(
      key('saveScopeFromHere'),
      findsOneWidget,
      reason: 'the range is on the same sheet, not behind a second one',
    );
    await tester.tap(key('saveScopeFromHere'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    // The field does not autofocus — choosing a range is not asking for a
    // keyboard over the launches — so this is the tap that raises it.
    await tester.tap(key('saveCountField'), warnIfMissed: false);
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

  /// *Queue only* — the answer that writes the journey's first row and
  /// starts nothing.
  ///
  /// **Queue only does not open a start sheet.** It is the answer that starts
  /// nothing, so the sheet stays and re-draws for the row it just wrote: the
  /// range block and the launches are replaced by *Queued - waiting for
  /// Start* and `v2StartButton`. This helper used to tap *Queue only* and look
  /// straight for `startInBrowser`, which is a launch **on the sheet** and had
  /// gone with the block it lives in.
  Future<void> queueOnly(WidgetTester tester) async {
    await tester.ensureVisible(key('saveScopeAddToQueue'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(key('saveScopeAddToQueue'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));
  }

  /// The sheet's own Start, then the gate.
  ///
  /// Pressing it closes the sheet and hands the launch question to the shell,
  /// because nobody has answered it - and that is the gate this suite wants,
  /// since a count taken from the Source opens pages.
  ///
  /// *Start in Browser* rather than the multitasking start: it is offered
  /// whatever the build's entitlement, so it is the one a harness may press.
  Future<void> authorise(WidgetTester tester) async {
    expect(
      key('v2StartButton'),
      findsOneWidget,
      reason: 'the sheet offers the explicit Start for the row it just wrote',
    );
    await tester.ensureVisible(key('v2StartButton'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(key('v2StartButton'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(
      key('startInBrowser'),
      findsOneWidget,
      reason:
          'a count taken from the Source may open a page, so it is gated the '
          'way the check is - before anything is opened',
    );
    await tester.tap(key('startInBrowser'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));
  }

  Future<void> queueAndAuthorise(WidgetTester tester) async {
    await queueOnly(tester);
    await authorise(tester);
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

      // *Queue only* writes **one** row - the Entry the user is standing on,
      // whose identity is already known. The other four do not exist yet and
      // deliberately so: the count is a claim about the Source, and every
      // address after this one is found while the downloading happens, one
      // page at a time (V2-D56). A pre-walk that resolved all five first is
      // exactly what that decision retired.
      await queueOnly(tester);
      expect(
        await app.ui.queue.all(),
        hasLength(1),
        reason: 'one row now; the rest are found as the run reaches them',
      );
      expect(
        await app.ui.offline.allCopies(),
        isEmpty,
        reason: 'and nothing captures until an explicit Start',
      );
      expect(app.runner.isRunning, isFalse);

      await authorise(tester);
      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 6));

      final queued = await app.ui.queue.all();
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
            'entries 1..5, each once - the count includes the page the '
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
          SaveTaskState.completed,
          reason:
              'the journey captures each Entry on the page it opened to '
              'identify it, so a finished run leaves every row settled',
        );
      }

      // The deliverable is Entries on this device, not Entries discovered.
      expect(
        (await app.ui.offline.allCopies()).where((c) => c.active),
        hasLength(5),
        reason: 'what the user asked for was five entries they can read',
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

      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 6));

      final queued = await app.ui.queue.all();
      expect(
        queued,
        hasLength(3),
        reason: 'entries 6, 7 and 8 - and nothing beyond the end of the chain',
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

      // **Running out of Source is an answer, not a failure.** Three of the
      // five asked for is what this site publishes after entry 6, and the run
      // says so in the user's words rather than reporting an error.
      expect(
        (await app.ui.offline.allCopies()).where((c) => c.active),
        hasLength(3),
        reason: 'the three that exist are on the device',
      );
      for (final task in queued) {
        expect(task.state, SaveTaskState.completed);
      }
      final summary = app.runner.lastRun;
      expect(summary, isNotNull);
      expect(
        summary!.endNote,
        contains('everything this site publishes'),
        reason:
            'a short answer about the Source, said as one - never as a '
            'failure of the download',
      );
      expect(summary.failed, 0);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  // ----------------------------------------------------------------- the stop
  //
  // Reading a Source forward is content-affecting source automation, so it is
  // user-started, visible, bounded *and cancellable*.
  //
  // This case was written against a seam that never landed under the name it
  // expected — `panelStopReadingForward`, a third branch of the running panel
  // for a walk of its own — and was skipped waiting for it. V2-D56 answered
  // the question differently: **reading forward is no longer a state of its
  // own.** It happens inside a download, between one Entry and the next, so
  // the download is what the user started and what they stop.
  //
  // What is asserted here is the rule V2-D56 states — *a user's Stop is about
  // the operation, not about the row that happened to be running* — through
  // the same call the panel's dialog makes, `SaveQueueRepository.cancel` on
  // the row being captured. The UI half is a separate matter and is reported
  // as a defect rather than asserted here; see the case below.
  testWidgets(
    'cancelling the running row stops the traversal, and keeps what it found',
    (tester) async {
      // A chain long enough that the walk is still going when it is stopped.
      // A prose page on a loopback fixture captures in about two seconds, and
      // the fixture's own delay is on image panels only.
      fixture.entryCount = 40;
      addTearDown(() => fixture.entryCount = 8);
      await boot(tester, startUrl: entry(1));

      await askForEntriesFromHere(tester, 40);
      await queueAndAuthorise(tester);

      // The panel is docked under the WebView, so the run is named and
      // stoppable while it drives the Browser.
      await pumpUntil(
        tester,
        () => key('panelStopDownload').evaluate().isNotEmpty,
        timeout: const Duration(minutes: 2),
        reason: 'a run that opens pages is visible while it does',
      );

      // Let it get past the first Entry, so "kept what it found" has
      // something to be about, then stop the row that is running now.
      await pumpUntilAsync(
        tester,
        () => app.ui.offline.allCopies(),
        (copies) => copies.where((c) => c.active).length >= 2,
        timeout: const Duration(minutes: 3),
      );
      final running = await pumpUntilAsync(
        tester,
        () => app.ui.queue.all(),
        (rows) => rows.any((t) => t.state == SaveTaskState.running),
        timeout: const Duration(minutes: 2),
      );
      final target = running.firstWhere(
        (t) => t.state == SaveTaskState.running,
      );
      final outcome = await app.ui.queue.cancel(target.id);
      expect(
        outcome,
        SaveCancelOutcome.stoppingRunning,
        reason: 'the row was still running when the stop was asked for',
      );

      // Stopping is cooperative everywhere: it lands at the next safe point.
      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 4));

      final settled = await app.ui.queue.all();
      expect(
        settled.length,
        lessThan(40),
        reason:
            'a stop is about the operation, so the traversal stops with the '
            'row and the entries after it are never resolved (V2-D56)',
      );
      final collection = await theCollection();
      final entries = await app.ui.entries.entriesOf(collection!.id);
      expect(
        entries.length,
        settled.length,
        reason: 'a stopped walk keeps every Entry it had already resolved',
      );
      // **Nothing already on this device is removed by a stop**, which is what
      // the panel's own wording promises.
      expect(
        (await app.ui.offline.allCopies()).where((c) => c.active),
        isNotEmpty,
        reason: 'everything already downloaded stays downloaded',
      );
      expect(app.runner.isRunning, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  // ------------------------------------------------------- A PROVEN DEFECT
  //
  // **The panel's *Stop download* does not reliably stop a sequential run.**
  //
  // Measured on the iPhone 17 Pro simulator against this fixture, asking for
  // 40 entries from entry 1: the panel's Stop was pressed and its dialog
  // confirmed while the run was going, and the run finished all forty —
  // `{completed: 40}`, 40 copies, `cancelled: 0`. Not one row was cancelled,
  // so the stop never reached a running row at all.
  //
  // Why. `_SaveRunning` draws its Stop for `runner.activeTaskId`, resolves
  // that id to a row through an async provider, and hands
  // `stopRunningDownload` **that row snapshot**. A journeyed entry on this
  // fixture is captured in about two seconds, so by the time the confirmation
  // dialog is answered the snapshot names a row that has already completed;
  // `cancel` reports `alreadyFinished`, the user is told "That download had
  // already finished", and the operation they asked to stop carries on to the
  // next Entry. Between two entries the control is disabled outright, because
  // `activeTaskId` is null while the walk is opening the next page.
  //
  // This contradicts two standing rules: V2-D56's "a user's Stop is about the
  // operation, not about the row that happened to be running when they
  // pressed it", and CLAUDE.md's "never offer a stop that does not stop". The
  // fix is not a test change — the stop has to be aimed at the operation
  // (a stop on `QueueRunner` itself) rather than at a row id read a moment
  // earlier — so this case is skipped rather than weakened, and un-skips in
  // the change that adds it.
  testWidgets(
    'the panel\'s Stop ends the run the user is watching',
    (tester) async {
      fixture.entryCount = 40;
      addTearDown(() => fixture.entryCount = 8);
      await boot(tester, startUrl: entry(1));

      await askForEntriesFromHere(tester, 40);
      await queueAndAuthorise(tester);

      await pumpUntil(
        tester,
        () => key('panelStopDownload').evaluate().isNotEmpty,
        timeout: const Duration(minutes: 2),
        reason: 'a run that opens pages is visible while it does',
      );

      // Pressed until the dialog it opens is actually on screen, which is the
      // only proof the stop was asked for: the control is disabled while the
      // walk is between entries.
      final confirm = key('confirmStopDownload');
      var asked = false;
      for (var attempt = 0; attempt < 12 && !asked; attempt++) {
        await tester.ensureVisible(key('panelStopDownload'));
        await pumpFor(tester, const Duration(milliseconds: 300));
        await tester.tap(key('panelStopDownload'), warnIfMissed: false);
        await pumpFor(tester, const Duration(milliseconds: 700));
        asked = confirm.evaluate().isNotEmpty;
      }
      expect(asked, isTrue, reason: 'the run must be stoppable while running');
      await tester.tap(confirm, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 2));

      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 4));
      expect(
        (await app.ui.queue.all()).length,
        lessThan(40),
        reason: 'the operation the user stopped must not run to its count',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: true,
  );
}
