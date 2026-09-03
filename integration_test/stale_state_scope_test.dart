// State the app shows about a page belongs to that page — on a real WebView.
//
//   flutter test integration_test/stale_state_scope_test.dart -d <device-id>
//
// Three scoping rules, each of which had a host-side regression test and none
// of which a host can finish proving, because all three turn on timing a real
// WKWebView produces and a fake cannot:
//
//   1. **The Browser's title is the current document's.** `_title` was written
//      once at `onLoadStop` and never taken back, so between committing to a
//      new page and that page's load finishing, `title` was the previous
//      page's while `currentUrl` was already the new one — and that pair is
//      what the save sheet is opened with. Here the navigations are real, the
//      loads take real time, and the pair is sampled *through* them.
//
//   2. **`activeTaskId` names a row only while that row is being captured.**
//      The download panel reads it, resolves the Entry and puts its title on
//      screen. Held open between rows, it named the Entry that had just
//      finished for the whole page load the run makes to reach the next one.
//
//   3. **The save sheet analyses its own page, or says it did not.** The sheet
//      is handed `(url, pageTitle)` as a snapshot and then probes the live
//      Browser; a probe taken somewhere else is discarded. The *risk* in that
//      rule is not the bug it fixes — the host test covers that — it is the
//      guard misfiring on an ordinary page whose real address, redirects and
//      normalisation only exist on a device. So this asserts the sheet does
//      analyse a real page: if the comparison were wrong, the sheet would say
//      the page could not be analysed, and it must not.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/save/queue_task.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite(entryCount: 6);
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester, {required String startUrl}) async {
    app = V2App(tag: 'scope_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    await showBrowser(tester);
    await openPage(tester, app, startUrl);
  }

  tearDown(() => app.shutdown());

  Finder key(String value) => find.byKey(ValueKey(value));

  /// The entry number an address names, or null for a page that names none.
  int? entryNumberOf(String url) =>
      int.tryParse(RegExp(r'/entry/(\d+)').firstMatch(url)?.group(1) ?? '');

  /// The entry number a fixture page's own `<title>` names.
  int? titleNumberOf(String title) =>
      int.tryParse(RegExp(r'Entry (\d+)').firstMatch(title)?.group(1) ?? '');

  testWidgets('rapid navigation never leaves the previous page\'s name beside '
      'the new address', (tester) async {
    await boot(tester, startUrl: fixture.entry(1));

    expect(
      titleNumberOf(app.browser.title),
      1,
      reason: 'a finished load is named by its own document',
    );

    // **The window, held open.** A loopback fixture answers faster than any
    // sampler, so the interesting moment — committed to a new document, that
    // document not yet loaded — is caught by navigating to an address the
    // fixture never answers. `onLoadStart` has fired, `currentUrl` is the new
    // address, and nothing will ever arrive to name it.
    final hanging = '${fixture.base}/hang/page.html';
    unawaited(app.browser.load(hanging));
    await pumpUntil(
      tester,
      () => normalizeUrl(app.browser.currentUrl) == normalizeUrl(hanging),
      timeout: const Duration(seconds: 30),
      reason: 'the Browser never committed to the page that never answers',
    );
    expect(
      app.browser.isLoading,
      isTrue,
      reason: 'this address is never answered, so the load is still in flight',
    );
    expect(
      titleNumberOf(app.browser.title),
      isNull,
      reason:
          'the Browser is on a page that has not named itself — carrying the '
          'previous page\'s name here is what a save then persisted',
    );

    // What the Browser said about itself, sampled straight through several
    // real loads rather than after them.
    final samples = <({String url, String title, bool loading})>[];
    var sawALoad = false;

    for (final n in [2, 3, 4, 5]) {
      // Deliberately not `loadAndWait`: the point is to be looking while the
      // load is in flight, which is the window the bug lived in.
      unawaited(app.browser.load(fixture.entry(n)));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final url = app.browser.currentUrl;
        if (url.isEmpty) continue;
        if (app.browser.isLoading) sawALoad = true;
        samples.add((
          url: url,
          title: app.browser.title,
          loading: app.browser.isLoading,
        ));
        if (!app.browser.isLoading &&
            entryNumberOf(url) == n &&
            app.browser.title.isNotEmpty) {
          break;
        }
      }
    }

    // The hang above is what proves the window was entered; this sweep is the
    // same rule over four ordinary back-to-back navigations, where a loopback
    // fixture may well answer between two samples.
    expect(samples, isNotEmpty);
    debugPrint(
      '[scope] ${samples.length} samples, a load was caught in flight: '
      '$sawALoad',
    );

    // The invariant: a title, when there is one, describes the address it is
    // sitting next to. Empty is always allowed — it is what a page that has
    // not said yet honestly looks like.
    final mismatches = <String>[];
    for (final sample in samples) {
      if (sample.title.isEmpty) continue;
      final onPage = entryNumberOf(sample.url);
      final named = titleNumberOf(sample.title);
      if (onPage == null || named == null) continue;
      if (onPage != named) {
        mismatches.add('${sample.url} was called "${sample.title}"');
      }
    }
    expect(
      mismatches,
      isEmpty,
      reason:
          'the Browser named a page after a different one — which is what the '
          'save sheet would then have persisted',
    );

    // And it does settle on the truth rather than merely staying blank.
    expect(titleNumberOf(app.browser.title), 5);
  });

  /// Browser → Save → *Add to a Collection…* → *New collection* → *from
  /// here* → a typed count. Every step is the control a user presses; this is
  /// the "new Collection → immediate download" flow.
  ///
  /// The pages are `/text/N` rather than `/entry/N` because only one of them
  /// can carry a Source: `collectionFingerprint` strips the number and then
  /// `entry` as an entry word, leaving nothing to key a Source by, and
  /// adoption refuses that in words. `/text` survives.
  Future<void> askForEntriesFromHere(WidgetTester tester, int count) async {
    expect(key('browserSaveAction'), findsOneWidget);
    await tester.tap(key('browserSaveAction'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    await tester.tap(key('v2AddToCollection'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.tap(key('collectionPickerNew'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(key('collectionNameField'), findsOneWidget);
    await tester.tap(key('saveScopeFromHere'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(key('saveCountField'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(key('saveCountField'), '$count');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(key('saveCountOk'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));

    // *Queue only*: a complete answer that opens nothing and starts nothing.
    await tester.ensureVisible(key('saveScopeAddToQueue'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(key('saveScopeAddToQueue'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));
  }

  testWidgets('a download names the row it is capturing, and no row between '
      'them', (tester) async {
    // A Source-capable address, so the count can be the sequential journey —
    // which is where the gap between two Entries is a whole page load rather
    // than a database query.
    await boot(tester, startUrl: '${fixture.base}/text/1');
    await askForEntriesFromHere(tester, 2);

    // Every reading of the field while the run is going, with the state of
    // the row it pointed at. A row that has already settled must never be the
    // one the panel is naming.
    final namedSettled = <String>[];
    var sawNull = false;
    var sawRunning = false;

    // Started before the Start, and it has to wait for the run to begin
    // rather than read `isRunning` once: at this point nothing is running, so
    // a plain `while (isRunning)` would end before the first capture.
    var everRan = false;
    final sampling = () async {
      final deadline = DateTime.now().add(const Duration(minutes: 6));
      while (DateTime.now().isBefore(deadline)) {
        if (app.runner.isRunning) {
          everRan = true;
        } else if (everRan) {
          return;
        }
        if (app.runner.isRunning) {
          final id = app.runner.activeTaskId;
          if (id == null) {
            sawNull = true;
          } else {
            final row = await app.ui.queue.byId(id);
            if (row != null) {
              if (row.state == SaveTaskState.running) sawRunning = true;
              if (row.isTerminal) {
                namedSettled.add('$id was named while ${row.state.name}');
              }
            }
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }();

    await startQueue(tester, app);
    await awaitQueueIdle(tester, app);
    await sampling;

    expect(
      sawRunning,
      isTrue,
      reason: 'the sampler must have caught a capture, or it proves nothing',
    );
    expect(
      namedSettled,
      isEmpty,
      reason:
          'between one Entry and the next the panel has no row to name — it '
          'must not go on naming the one that finished',
    );
    expect(
      sawNull,
      isTrue,
      reason:
          'a run of two Entries passes through the gap between them, and the '
          'gap is what the field has to be able to express',
    );

    // The run itself still did what it was for: the journey walked, and both
    // Entries are on this device.
    final copies = await app.ui.offline.allCopies();
    expect(
      copies.where((c) => c.active).length,
      2,
      reason: 'two Entries were asked for and the Source has them',
    );
    expect(app.runner.activeTaskId, isNull);
  });

  testWidgets('the save sheet analyses the real page it was opened for', (
    tester,
  ) async {
    await boot(tester, startUrl: fixture.entry(1));

    // The sheet's own identity, as `BrowserScreen` takes it.
    final opened = app.browser.currentUrl;
    expect(opened, isNotEmpty);

    await tester.tap(key('browserSaveAction'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 4));

    // The guard's real risk: a comparison that rejects a legitimate probe.
    // A real address on a real WebView — loopback, an explicit port, whatever
    // the platform hands back from `location.href` — must still match the
    // address the sheet was opened with.
    expect(
      normalizeUrl(app.browser.currentUrl),
      normalizeUrl(opened),
      reason: 'nothing moved the page; the probe is about this address',
    );
    expect(
      find.textContaining('could not be analysed'),
      findsNothing,
      reason:
          'the probe was taken at this sheet\'s own address, so it counts — a '
          'guard that rejected it would degrade every ordinary save',
    );
  });
}
