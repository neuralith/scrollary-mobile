// Source-scoped update checking, end to end against the in-process fixture on
// a real WebView.
//
//   flutter test integration_test/update_check_test.dart -d <device-id>
//
// The check discovers Entries and downloads nothing. That is the whole product
// claim, it is Free, and this suite proves it on a device: the source publishes
// two more entries, a check finds them, they arrive as library rows with no
// OfflineCopy behind them, and a re-check says up to date.
//
// ## What the V2 port changed
//
// **One ordinary check reads one Source.** V1's `UpdateChecker` asked "has this
// collection published anything since?", because a V1 Collection had exactly
// one site. A V2 Collection has several Sources, and `checkPreferredSource`
// reads the preferred one and no other — a Collection with several Sources and
// no preference is *refused* rather than having one picked for it, and checking
// another Source is `checkSource`, a separate act the user performs. Nothing
// iterates. The second case here is that refusal, and it is the case a port
// most easily loses.
//
// **"Finished" and "the reading was cut short" stay different outcomes.** A
// check may only say `upToDate` after a reading it can vouch for; anything else
// is `stopped` with a named `SourceCheckStop`.
//
// ## The seam this suite had to work around — read this before changing it
//
// `BrowserSourceObservationSource.observe` reconstructs a Source's listing
// address as `'https://${source.host}${source.pathKey}'`. A Source's identity
// is `(host, path_key)` and carries **neither the scheme nor the port**, so
// there is no way to name an origin that is not default-port HTTPS — including
// this project's own in-process fixture, which is `http://127.0.0.1:<port>`.
// Every other device suite drives the production path unmodified; this one
// cannot, because the production path cannot express where the fixture is.
//
// [FixtureOriginObservations] therefore substitutes **exactly that one string**
// and delegates everything else to the production implementation: the real
// navigation, the real landed-URL policy boundary, the real settled-page probe,
// the real listing extraction and the real ordering-confidence judgement all run
// on the device against the real WebView. Nothing about what a check *decides*
// is stubbed. The missing seam is reported as a blocker rather than papered
// over here, and if `lib` ever lets a Source name its own origin this wrapper
// should be deleted in the same change.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/operation_lane.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/recognition/check.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Delays off: nothing here downloads an image, so the slow panel would only
  // make the run longer.
  final fixture = FixtureSite(applyDelays: false, entryCount: 2);
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(
    WidgetTester tester,
    String tag, {
    void Function()? beforeObserve,
  }) async {
    app = V2App(
      tag: tag,
      observationsOver: fixtureObservations(
        fixture,
        beforeObserve: beforeObserve,
      ),
    );
    await app.boot(tester);
    await showBrowser(tester);
    await openPage(tester, app, fixture.base);
  }

  tearDown(() => app.shutdown(dumpLog: false));

  /// A Collection on the fixture's index page, holding entries 1..[held] as
  /// Locations of its one Source — the state a check measures novelty against.
  Future<({String collectionId, String sourceId})> seedCollection({
    required int held,
  }) async {
    final root = await app.ui.folders.ensureRoot();
    final (collection, violation) = await app.ui.collections.create(
      name: 'Fixture image sequence',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(collection, isNotNull, reason: '${violation?.message}');
    final (source, sourceViolation) = await app.ui.collections.addSource(
      collectionId: collection!.id,
      host: '127.0.0.1',
      pathKey: '/',
    );
    expect(source, isNotNull, reason: '${sourceViolation?.message}');
    await app.ui.collections.setPreferredSource(collection.id, source!.id);

    for (var n = 1; n <= held; n++) {
      final (entry, entryViolation) = await app.ui.entries.createInCollection(
        collectionId: collection.id,
        ordinal: n.toDouble(),
        title: 'Entry $n',
      );
      expect(entry, isNotNull, reason: '${entryViolation?.message}');
      final (location, locationViolation) = await app.ui.entries.addLocation(
        entryId: entry!.id,
        url: fixture.entry(n),
        urlKey: normalizeUrl(fixture.entry(n)),
        sourceId: source.id,
        sourceLabel: 'Entry $n',
        sourceNumber: n.toDouble(),
        discoveryBasis: 'userSave',
      );
      expect(location, isNotNull, reason: '${locationViolation?.message}');
    }
    return (collectionId: collection.id, sourceId: source.id);
  }

  testWidgets(
    'a check discovers new Entries and downloads nothing',
    (tester) async {
      fixture.entryCount = 2;
      await boot(tester, 'check_${caseIndex++}_$kRunStamp');
      final seeded = await seedCollection(held: 2);

      // The source publishes entries 3 and 4.
      fixture.entryCount = 4;

      final outcome = await app.check.run(
        seeded.collectionId,
        limits: kCollectionCheckLimits,
      );
      expect(outcome, isNotNull, reason: 'the check did not run at all');
      expect(
        outcome!.stopReason,
        isNull,
        reason:
            'a reading cut short cannot be reported as a clean result — it '
            'stopped on ${outcome.stopReason?.name}',
      );
      expect(outcome.state, SourceCheckState.updatesAvailable);
      expect(outcome.pagesRead, 1);
      expect(
        outcome.newEntryIds,
        hasLength(2),
        reason: 'entries 3 and 4 are the only ones above the checkpoint',
      );
      expect(
        outcome.checkpoint,
        2,
        reason:
            'novelty is measured against the highest number this Source has '
            'already shown, so the back catalogue is left where it is',
      );

      // The claim that matters: rows, not bytes.
      for (final entryId in outcome.newEntryIds) {
        expect(
          await app.ui.offline.activeCopyOf(entryId),
          isNull,
          reason: 'a check discovers; it never downloads',
        );
        final locations = await app.ui.entries.locationsOf(entryId);
        expect(locations, hasLength(1));
        expect(locations.single.discoveryBasis, isNotEmpty);
      }
      expect(
        await app.ui.queue.all(),
        isEmpty,
        reason: 'and it queues nothing on the user\'s behalf either',
      );
      expect(
        app.browser.automationOwner,
        isNull,
        reason: 'the check released the Browser',
      );

      // A second check over the same listing: up to date, and no duplicate rows.
      final second = await app.check.run(
        seeded.collectionId,
        limits: kCollectionCheckLimits,
      );
      expect(second!.state, SourceCheckState.upToDate);
      expect(second.newEntryIds, isEmpty);
      expect(
        await app.ui.entries.entriesOf(seeded.collectionId),
        hasLength(4),
        reason: 'a re-listed address is a fill-in, never a second Entry',
      );
      expect(
        checkOutcomeSentence(second),
        'Up to date. Nothing new on this collection\'s site.',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'one ordinary check reads one Source, and never picks for you',
    (tester) async {
      fixture.entryCount = 2;
      await boot(tester, 'check_${caseIndex++}_$kRunStamp');
      final seeded = await seedCollection(held: 2);

      // A second Source on the same Collection, and no preference between them.
      await app.ui.collections.setPreferredSource(seeded.collectionId, null);
      final (second, violation) = await app.ui.collections.addSource(
        collectionId: seeded.collectionId,
        host: '127.0.0.1',
        pathKey: '/other',
      );
      expect(second, isNotNull, reason: '${violation?.message}');

      final outcome = await app.check.run(
        seeded.collectionId,
        limits: kCollectionCheckLimits,
      );
      expect(
        outcome!.state,
        SourceCheckState.stopped,
        reason: 'with two sites and no preference there is nothing to read',
      );
      expect(
        outcome.stopReason,
        SourceCheckStop.preferredSourceNotChosen,
        reason:
            'picking one here would be the app choosing which site to open on '
            'the user\'s behalf — and iterating both would be a check whose '
            'bound is not the number the user chose',
      );
      expect(outcome.newEntryIds, isEmpty, reason: 'a refusal writes no row');
      expect(
        app.browser.automationOwner,
        isNull,
        reason: 'and it never took the Browser',
      );

      // Naming a Source explicitly is a separate act, and it works.
      final named = await app.check.run(
        seeded.collectionId,
        checkSourceId: seeded.sourceId,
        limits: kCollectionCheckLimits,
      );
      expect(named!.sourceId, seeded.sourceId);
      expect(named.state, SourceCheckState.upToDate);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'a cancelled check keeps what it found and claims nothing more',
    (tester) async {
      fixture.entryCount = 2;
      // Stop is pressed at the boundary immediately before the first page is
      // read — a real safe point, and a deterministic one. A wall-clock delay
      // racing a page load would make this assertion about how fast the device
      // is rather than about the cooperative stop.
      //
      // Note what is *not* asserted here: a cancel raised before `run` is
      // deliberately not honoured, because `CheckController.run` clears the
      // flag as it starts so a stale request can never kill the next check.
      await boot(
        tester,
        'check_${caseIndex++}_$kRunStamp',
        beforeObserve: () => app.check.cancel(),
      );
      final seeded = await seedCollection(held: 2);
      fixture.entryCount = 4;

      final outcome = await app.check.run(
        seeded.collectionId,
        limits: kCollectionCheckLimits,
      );

      expect(outcome!.state, SourceCheckState.stopped);
      expect(outcome.stopReason, SourceCheckStop.cancelledByUser);
      expect(
        outcome.newEntryIds,
        isEmpty,
        reason: 'nothing was read, so nothing was claimed',
      );
      expect(
        await app.ui.entries.entriesOf(seeded.collectionId),
        hasLength(2),
        reason: 'and nothing was removed either',
      );
      expect(
        checkOutcomeSentence(outcome),
        'Stopped. Nothing was added, and nothing was removed.',
      );
      expect(app.browser.automationOwner, isNull);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'the discovered rows are durable, and still hold no copy',
    (tester) async {
      fixture.entryCount = 2;
      await boot(tester, 'check_${caseIndex++}_$kRunStamp');
      final seeded = await seedCollection(held: 2);
      fixture.entryCount = 4;

      final outcome = await app.check.run(
        seeded.collectionId,
        limits: kCollectionCheckLimits,
      );
      expect(outcome!.newEntryIds, hasLength(2));

      // Read back through repositories built after the check, which is the
      // durability claim this suite can honestly make in-process: these rows came
      // out of the database, not out of the objects that wrote them. (A cold
      // start over an existing container is a separate `flutter test`
      // invocation — see the note in the harness's `boot`.)
      final fresh = app.freshLibraryReads();
      final entries = await fresh.entries.entriesOf(seeded.collectionId);
      expect(entries, hasLength(4), reason: 'the discovered rows are durable');
      for (final entry in entries) {
        final copy = await fresh.offline.activeCopyOf(entry.id);
        expect(
          copy,
          isNull,
          reason:
              'and they are still Entries nobody has downloaded — being in the '
              'library is not being on the device',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'a check asked for during a download waits for it, and then runs',
    (tester) async {
      // **The single-operation invariant, on a real WebView.** There is one
      // WebView, and before `OperationLane` a check started while a download
      // was running read a listing through the page the capture was driving.
      // Every start surface now goes through the lane, so the check is queued
      // and told, and it runs when its turn comes.
      //
      // The delay is the fixture's own: panel 4 is served two seconds late, so
      // the download is still going when the check is asked for. Without a
      // window this case could pass by accident on a fast device, which is
      // worse than not having it.
      fixture.applyDelays = true;
      fixture.entryCount = 2;
      await boot(tester, 'lane_${caseIndex++}_$kRunStamp');
      final seeded = await seedCollection(held: 2);
      fixture.entryCount = 4;

      final container = ProviderScope.containerOf(tester.element(libraryTab));
      final lane = container.read(operationLaneProvider);

      // A real download, started the way the app starts one — through
      // `V2Services.startQueue`, which is the only place V2 Browser automation
      // is authorised from.
      await openPage(tester, app, fixture.entry(1));
      await app.queueSaveOf(fixture.entry(1), title: 'Entry 1');
      await startQueue(tester, app);
      await pumpUntil(
        tester,
        () => app.runner.isRunning,
        timeout: const Duration(seconds: 60),
        reason:
            'the download never started, so there is nothing to queue '
            'behind',
      );

      // …and, while it is running, the user asks for a check through the real
      // control the Collection screen puts up.
      unawaited(
        app.v2.checkCollection!(seeded.collectionId, 'Fixture image sequence'),
      );
      await pumpFor(tester, const Duration(seconds: 2));
      await tester.tap(
        find.byKey(const ValueKey('startInBrowser')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 1));

      if (!app.runner.isRunning) {
        // The download beat us to the finish. Say so rather than assert
        // something this run did not measure.
        fixture.applyDelays = false;
        markTestSkipped(
          'the download finished before the check could be asked for — this '
          'device is too fast for the fixture window',
        );
        return;
      }
      expect(
        app.check.isRunning,
        isFalse,
        reason: 'two operations may not drive the one WebView',
      );
      expect(
        lane.waiting,
        1,
        reason: 'the request was kept, not refused and not started',
      );
      expect(
        app.browser.automationOwner,
        isNotNull,
        reason: 'the download holds the Browser while it drives it',
      );

      // Both finish, in order, and the check the user asked for happened.
      await pumpUntil(
        tester,
        () => !lane.isBusy && !app.runner.isRunning && !app.check.isRunning,
        timeout: const Duration(minutes: 3),
        reason: 'the queued check never got its turn',
      );
      expect(
        app.check.lastOutcome,
        isNotNull,
        reason:
            'queueing is only better than refusing because the request '
            'actually runs',
      );
      expect(app.browser.automationOwner, isNull);
      fixture.applyDelays = false;
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
