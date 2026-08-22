// The product claim, end to end: a save and a check the user started keep
// running while the user reads an Entry they already have.
//
//   flutter test integration_test/foreground_multitasking_test.dart -d <device>
//
// Nothing is mocked. A real WebView loads the in-process fixture, the ported
// engine scrolls it, the IntersectionObserver panels arrive, bytes are
// downloaded and a manifest is written — all while the Reader route is on
// screen above the shell.
//
// **The control arm matters as much as the claim.** With the capability off,
// the same run must *hold* rather than read a page the app is no longer
// drawing, and it must resume, whole, when the user comes back. A suite that
// only proved the Pro arm would be proving that something happens, not that the
// boundary is where the product says it is.
//
// ## What the V2 port changed, and what it did not
//
// * **The capability is entitlement AND preference.** `ForegroundMultitasking`
//   resolves `enabled` from both, so a Pro arm sets the internal entitlement
//   override *and* the preference. Only a debug build can do the first, which
//   is exactly the point of `kInternalBuild`.
// * **There is no pause flag to read, and deliberately not one.** V1 published
//   `SaveState.waitingForBrowser` on a controller the shell could watch. V2's
//   `QueueRunner` publishes only *running*, and "held" is read as the condition
//   itself — the run is live and the app is not drawing the WebView. So the
//   indicator's honesty is asserted against `browserSurfacePaintedProvider`,
//   and the engine's own hold is read through the `onProgress` hook the
//   harness subscribes to.
// * **A bounded multi-Entry run became a queue that drains.** Same property,
//   V2's shape: several Entries settled from one authorisation, with the
//   Library tab in front the whole time.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/save_state.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  /// [multitasking] true boots the Pro arm: the internal entitlement override
  /// *and* the preference, because either alone is honestly "off".
  Future<void> boot(WidgetTester tester, {required bool multitasking}) async {
    app = V2App(
      tag: 'fg_${caseIndex++}_$kRunStamp',
      multitaskingPreference: multitasking,
      entitlement: multitasking
          ? EntitlementOverride.forcePro
          : EntitlementOverride.forceFree,
      observationsOver: fixtureObservations(fixture),
    );
    await app.boot(tester);
    expect(
      app.capability.enabled,
      multitasking,
      reason: 'the arm was not set up as intended',
    );
    await showBrowser(tester);
  }

  tearDown(() => app.shutdown());

  bool surfacePainted(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(libraryTab),
  ).read(browserSurfacePaintedProvider).value;

  /// Queue [n] and start, then wait until the capture is genuinely reading the
  /// page — a hold asserted before the page phase began would prove nothing.
  Future<String> startCaptureOf(WidgetTester tester, int n) async {
    final entryId = await app.queueSaveOf(fixture.entry(n), title: 'Entry $n');
    await startQueue(tester, app);
    await pumpUntil(
      tester,
      () => app.engineStates.contains(SaveState.scrolling),
      timeout: const Duration(seconds: 90),
      reason: 'the capture never reached a Browser phase',
    );
    return entryId;
  }

  testWidgets(
    'a save runs to completion while the Reader is open',
    (tester) async {
      await boot(tester, multitasking: true);

      // One Entry captured the ordinary way, so there is something to read.
      await openPage(tester, app, fixture.entry(1));
      final first = await app.queueSaveOf(fixture.entry(1), title: 'Entry 1');
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);
      expect((await app.latestTaskFor(first))!.state, SaveTaskState.completed);

      // Now start a second capture and leave for the Reader immediately.
      app.resetObservations();
      await openPage(tester, app, fixture.entry(3));
      final second = await startCaptureOf(tester, 3);
      await openReader(tester, first);
      expect(find.byType(ReaderScreen), findsOneWidget);

      await awaitQueueIdle(tester, app);

      expect(
        find.byType(ReaderScreen),
        findsOneWidget,
        reason: 'the user was never pulled off the Entry they were reading',
      );
      expect(
        app.everHeldForBrowser,
        isFalse,
        reason: 'the run never had to ask for the Browser back',
      );
      expect(
        surfacePainted(tester),
        isTrue,
        reason:
            'the WebView kept being drawn under the Reader — the whole of the '
            'mechanism, and what the occlusion gate measured',
      );
      expect((await app.latestTaskFor(second))!.state, SaveTaskState.completed);
      expect(
        await app.storedImagesOf(second),
        kFixtureImagesPerEntry,
        reason: 'the same bytes a watched run would have stored',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'with the capability off, the same save holds instead',
    (tester) async {
      await boot(tester, multitasking: false);

      await openPage(tester, app, fixture.entry(1));
      final first = await app.queueSaveOf(fixture.entry(1), title: 'Entry 1');
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      app.resetObservations();
      await openPage(tester, app, fixture.entry(3));
      final second = await startCaptureOf(tester, 3);
      await openReader(tester, first);

      // It must hold, not push on. Give it long enough that a run which was
      // going to carry on would have finished.
      await pumpFor(tester, const Duration(seconds: 30));

      expect(
        surfacePainted(tester),
        isFalse,
        reason: 'without the capability the app stops drawing the WebView',
      );
      expect(
        app.everHeldForBrowser,
        isTrue,
        reason: 'a run must not read a page the app has stopped drawing',
      );
      expect(app.runner.isRunning, isTrue, reason: 'and it is still live');
      expect(
        (await app.latestTaskFor(second))!.state,
        SaveTaskState.running,
        reason: 'holding is not finishing, and never a failure',
      );

      // The indicator is honest about it: held, not moving. Read from the real
      // semantics tree, because that is where a screen reader reads it — and it
      // has to be asked for, since nothing on the device is running one.
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'Background work paused — 1 running. Opens Activity.',
        ),
        findsOneWidget,
        reason:
            'the pill says paused rather than spinning at a run that is not '
            'moving',
      );
      // Disposed inline, not through `addTearDown`: flutter_test verifies that
      // no handle outlived the body *before* it runs tear-downs.
      semantics.dispose();

      // And coming back releases it, with nothing lost.
      await popRoute(tester);
      await pumpUntil(
        tester,
        () => surfacePainted(tester),
        timeout: const Duration(seconds: 20),
        reason: 'returning to the Browser did not resume the surface',
      );
      await awaitQueueIdle(tester, app);

      expect((await app.latestTaskFor(second))!.state, SaveTaskState.completed);
      expect(
        await app.storedImagesOf(second),
        kFixtureImagesPerEntry,
        reason: 'a held run resumes whole — the Free flow is never degraded',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'the leave gate asks a Free user, and never a multitasking one',
    (tester) async {
      // Free first: leaving the Browser mid-capture must offer the choice.
      await boot(tester, multitasking: false);
      await openPage(tester, app, fixture.entry(1));
      await startCaptureOf(tester, 1);

      expect(
        await showLibrary(tester),
        isTrue,
        reason:
            'a Browser-dependent phase would be stranded, so the gate asks — '
            'and *Pause and leave* is the answer offered to everyone',
      );
      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 3));
      await app.shutdown();

      // Pro, preference on: nothing is at risk, so nothing is asked.
      await boot(tester, multitasking: true);
      await openPage(tester, app, fixture.entry(1));
      await startCaptureOf(tester, 1);

      expect(
        await showLibrary(tester),
        isFalse,
        reason:
            'the task carries on, so the modal must not cry wolf — a gate that '
            'asks when nothing is at risk is one people learn to dismiss',
      );
      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 3));
      expect(app.everHeldForBrowser, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );

  testWidgets(
    'a queue drains from the Library tab, and holds without the capability',
    (tester) async {
      // The other half of the mechanism: not a pushed route, but the shell's
      // own tab. The Browser child has to stay drawn underneath the Library.
      await boot(tester, multitasking: true);
      await openPage(tester, app, fixture.entry(1));

      final ids = <int, String>{};
      for (final n in [1, 2, 3]) {
        ids[n] = await app.queueSaveOf(fixture.entry(n), title: 'Entry $n');
      }
      await startQueue(tester, app);
      await pumpUntil(
        tester,
        () => app.engineStates.contains(SaveState.scrolling),
        timeout: const Duration(seconds: 90),
      );

      expect(
        await showLibrary(tester),
        isFalse,
        reason: 'a multitasking task is not stranded by a tab switch',
      );
      expect(surfacePainted(tester), isTrue);

      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 6));

      expect(
        app.everHeldForBrowser,
        isFalse,
        reason: 'the Library tab must not strand the queue',
      );
      for (final n in [1, 2, 3]) {
        final task = await app.latestTaskFor(ids[n]!);
        expect(
          task!.state,
          SaveTaskState.completed,
          reason: 'entry $n ended ${task.state.name}: ${task.lastError}',
        );
      }
      expect(
        await app.storedImagesOf(ids[3]!),
        kFixtureImagesPerEntry,
        reason: 'several Entries settled from one authorisation',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'a Collection check runs while the Reader is open',
    (tester) async {
      await boot(tester, multitasking: true);
      await openPage(tester, app, fixture.base);

      // Something to read, and a Collection with a Source to check.
      final root = await app.ui.folders.ensureRoot();
      final (collection, _) = await app.ui.collections.create(
        name: 'Fixture image sequence',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      final (source, _) = await app.ui.collections.addSource(
        collectionId: collection!.id,
        host: '127.0.0.1',
        pathKey: '/',
      );
      await app.ui.collections.setPreferredSource(collection.id, source!.id);

      await openPage(tester, app, fixture.entry(1));
      final readable = await app.queueSaveOf(
        fixture.entry(1),
        title: 'Entry 1',
        collectionId: collection.id,
      );
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);
      expect(
        (await app.latestTaskFor(readable))!.state,
        SaveTaskState.completed,
      );

      await openReader(tester, readable);
      expect(find.byType(ReaderScreen), findsOneWidget);

      final outcome = await app.check.run(
        collection.id,
        limits: kCollectionCheckLimits,
      );
      await pumpFor(tester, const Duration(seconds: 2));

      expect(
        find.byType(ReaderScreen),
        findsOneWidget,
        reason: 'the check never moved the user',
      );
      expect(outcome, isNotNull);
      expect(
        outcome!.stopReason,
        isNull,
        reason:
            'it read the listing whole with the Reader on screen — it stopped '
            'on ${outcome.stopReason?.name}',
      );
      expect(outcome.pagesRead, greaterThan(0));
      expect(
        outcome.state,
        SourceCheckState.updatesAvailable,
        reason: 'entries 2 and 3 are new to this Collection',
      );
      expect(
        app.browser.automationOwner,
        isNull,
        reason: 'and it released the Browser at the end',
      );
      for (final entryId in outcome.newEntryIds) {
        expect(
          await app.ui.offline.activeCopyOf(entryId),
          isNull,
          reason: 'a check downloads nothing, wherever the user is standing',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
