/// One lane for everything that drives the Browser.
///
/// Capture and update checking are the same scarce thing: there is exactly one
/// WebView, and two operations navigating it at once corrupt both. The rule the
/// product asks for is not *refuse the second* — it is **queue the second, and
/// say so**. A user who taps *Check for new entries* while a download is
/// running has asked for something reasonable; the answer is "that is queued",
/// never a silent second run and never a flat refusal.
///
/// Before [OperationLane] existed each start surface knew only about its own
/// kind of work: `startCollectionCheck` asked whether *a check* was running,
/// `startQueuedDownloads` asked nothing at all, and neither asked the other. A
/// Collection check started while a download run was going read a listing
/// through the same WebView the capture was driving, and a second Start over a
/// live run announced "Starting 3 downloads" for work that never began.
///
/// These tests drive the ways a second start can be asked for, and the one
/// thing that makes queueing better than refusing: the request is **kept**, and
/// it runs when its turn comes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/operation_lane.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/library_ui/entry_offline.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/library_ui/run_summary.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/v2_harness.dart';
import 'library_ui/support/ui_harness.dart' show screenTest;

void main() {
  group('the lane itself', () {
    test(
      'runs one thing at a time, in the order they were asked for',
      () async {
        final lane = OperationLane();
        addTearDown(lane.dispose);
        final order = <String>[];
        final first = Completer<void>();

        final a = lane.submit(
          key: 'a',
          label: 'a download',
          body: () async {
            order.add('a:start');
            await first.future;
            order.add('a:end');
          },
        );
        // Asked for while `a` holds the lane, so both wait — and both are kept.
        var queuedBehind = <String>[];
        final b = lane.submit(
          key: 'b',
          label: 'a check',
          whenQueued: queuedBehind.add,
          body: () async => order.add('b'),
        );
        final c = lane.submit(
          key: 'c',
          label: 'a check',
          whenQueued: queuedBehind.add,
          body: () async => order.add('c'),
        );

        expect(lane.isBusy, isTrue);
        expect(lane.activeLabel, 'a download');
        expect(lane.waiting, 2);
        expect(queuedBehind, ['a download', 'a download']);

        first.complete();
        await Future.wait([a, b, c]);

        expect(order, ['a:start', 'a:end', 'b', 'c']);
        expect(lane.isBusy, isFalse);
        expect(lane.waiting, 0);
      },
    );

    test('a request whose work throws still hands the lane on', () async {
      final lane = OperationLane();
      addTearDown(lane.dispose);
      var ran = false;

      final failing = lane.submit<void>(
        key: 'a',
        label: 'a download',
        body: () async => throw StateError('the capture blew up'),
      );
      final next = lane.submit(
        key: 'b',
        label: 'a check',
        body: () async => ran = true,
      );

      await expectLater(failing, throwsStateError);
      await next;
      expect(ran, isTrue);
      expect(lane.isBusy, isFalse);
    });

    test('the same work asked for twice is one request', () async {
      final lane = OperationLane();
      addTearDown(lane.dispose);
      final held = Completer<void>();
      final running = lane.submit(
        key: 'downloads',
        label: 'a download',
        body: () => held.future,
      );

      expect(lane.holds('downloads'), isTrue);
      expect(lane.holds('check:one'), isFalse);

      held.complete();
      await running;
      expect(lane.holds('downloads'), isFalse);
    });
  });

  group('two features, one Browser', () {
    late V2Harness v2;
    late OperationLane lane;
    late ValueNotifier<int?> tabRequest;
    late String collectionId;
    late String entryId;
    var starts = 0;

    setUp(() {
      v2 = V2Harness(browser: BrowserController(), fileStore: tempFileStore());
      lane = OperationLane();
      tabRequest = ValueNotifier<int?>(null);
      starts = 0;
    });

    tearDown(() async {
      lane.dispose();
      tabRequest.dispose();
      await v2.close();
    });

    /// A Collection with one Source and one Entry with an address — enough to
    /// be checkable and enough to be downloadable.
    Future<void> seed() async {
      final root = await v2.ui.folders.ensureRoot();
      final (collection, _) = await v2.ui.collections.create(
        name: 'Serial Alpha',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      collectionId = collection!.id;
      final (source, _) = await v2.ui.collections.addSource(
        collectionId: collectionId,
        host: 'reading.example.com',
        pathKey: 'serial-alpha',
        language: 'en',
      );
      final (entry, _) = await v2.ui.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 1,
        title: 'Part 1',
      );
      entryId = entry!.id;
      const url = 'https://reading.example.com/serial-alpha/part-1';
      final (location, _) = await v2.ui.entries.addLocation(
        entryId: entryId,
        sourceId: source!.id,
        url: url,
        urlKey: url,
      );
      final queued = await v2.ui.queue.enqueue(
        entryId: entryId,
        locationId: location!.id,
        locationUrl: location.url,
      );
      expect(queued.task, isNotNull);
    }

    /// What the shell attaches to `saveQueueStarterProvider`: the run goes
    /// **through the lane**, exactly as `_startQueuedDownloads` does in
    /// `app.dart` once its gate sheet has been answered.
    Future<void> startTheQueue({libui.StartWhere? decided}) async {
      starts++;
      await lane.submit(
        key: kDownloadWorkKey,
        label: kDownloadWorkLabel,
        body: () async {},
      );
    }

    Widget app(Widget home) => ProviderScope(
      overrides: [
        v2ServicesProvider.overrideWithValue(v2.services),
        libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        runSummarySourceProvider.overrideWithValue(v2.runner),
        operationLaneProvider.overrideWithValue(lane),
        libui.saveQueueStarterProvider.overrideWithValue(startTheQueue),
      ],
      child: MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Scaffold(body: home),
      ),
    );

    /// The control the shell puts behind `V2Services.checkCollection`.
    Widget checkButton() => Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () async => startCollectionCheck(
          context,
          ref,
          collectionId,
          collectionName: 'Serial Alpha',
        ),
        child: const Text('check'),
      ),
    );

    /// The control every *Start the waiting downloads* surface puts up.
    Widget downloadButton() => Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () async => startQueuedDownloads(context, ref),
        child: const Text('download'),
      ),
    );

    final inBrowser = find.byKey(const ValueKey('startInBrowser'));

    /// The one sentence a queued request has to produce, in whatever words.
    Finder queuedNotice() => find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? '';
      return text.contains('already running') && text.contains('queue');
    }, description: 'a message saying work is running and this one is queued');

    /// Hold the lane the way a download run holds it, and hand back the way to
    /// let it finish.
    Completer<void> holdADownloadRun() {
      final held = Completer<void>();
      unawaited(
        lane.submit(
          key: kDownloadWorkKey,
          label: kDownloadWorkLabel,
          body: () => held.future,
        ),
      );
      return held;
    }

    /// The same, for a check.
    Completer<void> holdACheck() {
      final held = Completer<void>();
      unawaited(
        lane.submit(
          key: collectionCheckWorkKey('another'),
          label: kCheckWorkLabel,
          body: () => held.future,
        ),
      );
      return held;
    }

    screenTest('a check asked for while a download is running waits for it, '
        'and then runs', (tester) async {
      await seed();
      final downloading = holdADownloadRun();
      await tester.pumpWidget(app(checkButton()));

      await tester.tap(find.text('check'));
      await _settle(tester);
      await tester.tap(inBrowser);
      await _settle(tester);

      // Nothing read a listing while the download held the Browser…
      expect(
        v2.check.lastOutcome,
        isNull,
        reason: 'two things may not drive the one WebView',
      );
      expect(queuedNotice(), findsOneWidget);
      expect(lane.waiting, 1, reason: 'the request was kept, not dropped');

      // …and the moment the download is done, the check the user asked for
      // happens. Queueing is only better than refusing because of this.
      downloading.complete();
      await _settle(tester);
      expect(v2.check.lastOutcome, isNotNull);
      expect(lane.isBusy, isFalse);
    });

    screenTest('a download start asked for while a check is running never '
        'claims to be starting', (tester) async {
      await seed();
      final checking = holdACheck();
      await tester.pumpWidget(app(downloadButton()));

      await tester.tap(find.text('download'));
      await _settle(tester);

      expect(
        find.textContaining('Starting'),
        findsNothing,
        reason: 'nothing started — a check holds the Browser',
      );
      expect(queuedNotice(), findsOneWidget);
      expect(starts, 1, reason: 'the request reached the starter');
      expect(lane.waiting, 1, reason: 'and is waiting its turn');

      checking.complete();
      await _settle(tester);
      expect(lane.isBusy, isFalse);
    });

    screenTest('a second download start while a run is going says it is '
        'queued, not that it is starting', (tester) async {
      await seed();
      final downloading = holdADownloadRun();
      await tester.pumpWidget(app(downloadButton()));

      await tester.tap(find.text('download'));
      await _settle(tester);

      expect(starts, 0, reason: 'the run already going is the one pipeline');
      expect(find.textContaining('Starting'), findsNothing);
      expect(queuedNotice(), findsOneWidget);
      expect(
        lane.waiting,
        0,
        reason:
            'a second Start is not a second run — the rows it authorised '
            'are drained by the run that is already going',
      );

      downloading.complete();
      await _settle(tester);
    });

    screenTest('the same collection asked for twice is one check', (
      tester,
    ) async {
      await seed();
      final downloading = holdADownloadRun();
      await tester.pumpWidget(app(checkButton()));

      await tester.tap(find.text('check'));
      await _settle(tester);
      await tester.tap(inBrowser);
      await _settle(tester);
      expect(lane.waiting, 1);

      await tester.tap(find.text('check'));
      await _settle(tester);
      await _settle(tester);

      expect(lane.waiting, 1, reason: 'the duplicate was not stacked');
      expect(
        find.text('This collection is already waiting to be checked.'),
        findsOneWidget,
      );
      expect(
        inBrowser,
        findsNothing,
        reason: 'and no second sheet was opened for it',
      );

      downloading.complete();
      await _settle(tester);
    });
  });
}

Future<void> _turn(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await _turn(tester);
  }
}
