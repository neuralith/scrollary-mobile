/// The panel docked under the WebView, over the V2 controllers.
///
/// Content-affecting source automation is *user-started, visible, bounded and
/// cancellable* (CLAUDE.md, "Two kinds of network work"). The Browser is the
/// one screen the operation indicator deliberately stays off, so this panel is
/// the whole of "visible" and the whole of "cancellable" there. Every test
/// below is one of those two words.
///
/// The two operations are held apart on purpose. A check downloads nothing, so
/// a panel saying "Downloading" while one ran would be the app telling a user
/// something untrue about their own device — the check wording is asserted,
/// and the download wording is asserted *absent*.
///
/// Both operations are driven for real rather than flagged, because "Never
/// offer a stop that does not stop" is only proven by a run that actually ends.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/features/check_controller.dart';
import 'package:web_reader/features/running_operation_panel.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'library_ui/support/ui_harness.dart' show screenTest;

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.close());

  /// The panel, docked at the bottom of an otherwise empty screen — the shape
  /// it has under the Browser, and the shape that makes "it takes no room"
  /// something to measure rather than assume.
  Widget app() => ProviderScope(
    overrides: [
      v2ServicesProvider.overrideWithValue(h.services),
      libui.libraryUiServicesProvider.overrideWithValue(h.ui),
      // A Start authorises rows and hands them on. With nothing attached it
      // deliberately authorises nothing, so the panel's Start needs a runner
      // here to be a Start at all.
      libui.saveQueueStarterProvider.overrideWithValue(
        ({decided}) async => h.starts++,
      ),
    ],
    child: MaterialApp(
      theme: appTheme(palette: AppPalette.light),
      home: const Scaffold(
        body: Column(children: [Spacer(), RunningOperationPanel()]),
      ),
    ),
  );

  final panel = find.byKey(const ValueKey('runningOperationPanel'));
  final stopDownload = find.byKey(const ValueKey('panelStopDownload'));
  final stopCheck = find.byKey(const ValueKey('panelStopCheck'));

  group('nothing running', () {
    screenTest('renders nothing at all, and takes no room', (tester) async {
      await tester.pumpWidget(app());
      await _turn(tester);

      expect(panel, findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester.getSize(find.byType(RunningOperationPanel)),
        Size.zero,
        reason:
            'an idle panel that reserved a strip would be a standing claim on '
            'the Browser for something that is not happening',
      );
    });
  });

  group('a download in flight', () {
    screenTest('names the operation and offers a stop', (tester) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startQueue();
      await _pumpUntil(tester, panel);

      expect(find.text('Downloading'), findsOneWidget);
      expect(
        find.textContaining('offline copy'),
        findsOneWidget,
        reason:
            'what the operation is, said whatever the progress happens to be — '
            'the sentence that stops a moving Browser reading as the site',
      );
      expect(stopDownload, findsOneWidget);
      expect(stopCheck, findsNothing);

      await h.releaseCapture(tester);
    });

    screenTest('names the entry it is working on', (tester) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startQueue();
      await _pumpUntil(tester, find.text('The second one'));

      await h.releaseCapture(tester);
    });

    screenTest('says something rather than nothing when the task has no name', (
      tester,
    ) async {
      await h.seed();
      await tester.pumpWidget(app());
      // A loop that is running with no row the panel can resolve: what a
      // pruned row, or a claim still in flight, leaves it looking at.
      h.runner.debugSetRunning(true);
      await _pumpUntil(tester, panel);

      expect(find.text('One item'), findsOneWidget);
      expect(find.text(''), findsNothing);
      expect(
        tester.widget<OutlinedButton>(stopDownload).onPressed,
        isNull,
        reason:
            'a stop with no row to act on does not pretend it can stop '
            'anything',
      );

      h.runner.debugSetRunning(false);
      await _turn(tester);
    });

    screenTest('the progress bar never claims a percentage', (tester) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startQueue();
      await _pumpUntil(tester, panel);

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
        reason:
            'neither operation knows how much is left, so a bar with a number '
            'in it would be inventing one',
      );

      await h.releaseCapture(tester);
    });

    screenTest('stopping asks first, and backing out stops nothing', (
      tester,
    ) async {
      final seed = await h.seed();
      await tester.pumpWidget(app());
      h.startQueue();
      await _pumpUntil(tester, find.text('The second one'));

      await tester.tap(stopDownload);
      await _turn(tester);
      await _turn(tester);
      expect(find.text('Stop this download?'), findsOneWidget);

      await tester.tap(find.text('Keep going'));
      await _turn(tester);
      await _turn(tester);

      expect((await h.taskFor(seed.entryId))!.state, SaveTaskState.running);

      await h.releaseCapture(tester);
    });

    screenTest('confirming cancels the queue row and touches nothing else', (
      tester,
    ) async {
      final seed = await h.seed();
      await h.ui.reading.markRead(seed.entryId);
      await h.recordCopy(seed.entryId);
      await tester.pumpWidget(app());
      h.startQueue();
      await _pumpUntil(tester, find.text('The second one'));

      await tester.tap(stopDownload);
      await _turn(tester);
      await _turn(tester);
      await tester.tap(find.byKey(const ValueKey('confirmStopDownload')));
      await _turn(tester);
      await _turn(tester);

      final task = (await h.taskFor(seed.entryId))!;
      expect(task.state, SaveTaskState.cancelled);
      expect(task.outcome, kSaveTaskStopping);
      expect(
        h.ui.queue.shouldContinue(task.id),
        isFalse,
        reason:
            'the offer of a stop is only honest if the run in flight is asked '
            'to end',
      );

      // A queue row is never the content: nothing a user has is smaller for
      // having stopped a download.
      expect(await h.ui.entries.byId(seed.entryId), isNotNull);
      expect(
        (await h.ui.reading.stateOf(seed.entryId)).status,
        ReadStatus.completed,
      );
      expect(await h.copyRows(seed.entryId), 1);
      expect(h.bytesOnDisk(seed.entryId), isTrue);

      await h.releaseCapture(tester);
    });
  });

  group('a check in flight', () {
    screenTest('says it is checking, and never says it is downloading', (
      tester,
    ) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startCheck();
      await _pumpUntil(tester, panel);

      expect(find.text('Checking'), findsOneWidget);
      expect(
        find.textContaining('Downloading'),
        findsNothing,
        reason:
            'the two operations have to be tellable apart at a glance, and '
            'only one of them puts bytes on the device',
      );
      expect(stopCheck, findsOneWidget);
      expect(stopDownload, findsNothing);

      await h.releaseObservation(tester);
    });

    screenTest('states that nothing is downloaded', (tester) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startCheck();
      await _pumpUntil(tester, panel);

      expect(find.textContaining('nothing is downloaded'), findsOneWidget);
      expect(
        find.textContaining('Entries already found are kept'),
        findsOneWidget,
      );

      await h.releaseObservation(tester);
    });

    screenTest('its progress bar never claims a percentage either', (
      tester,
    ) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startCheck();
      await _pumpUntil(tester, panel);

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );

      await h.releaseObservation(tester);
    });

    screenTest('stopping the check reaches the run, and the run ends', (
      tester,
    ) async {
      await h.seed();
      await tester.pumpWidget(app());
      h.startCheck();
      await _pumpUntil(tester, stopCheck);
      expect(h.check.isRunning, isTrue);

      await tester.tap(stopCheck);
      await _turn(tester);
      await h.releaseObservation(tester);

      expect(
        h.observations.allowedToCarryOn,
        isFalse,
        reason:
            'the panel\'s stop is the run\'s own cooperative stop, asked at '
            'the reading\'s next safe boundary',
      );
      expect(h.check.isRunning, isFalse);
      expect(
        stopCheck,
        findsNothing,
        reason: 'nothing is running, so nothing is offered a stop',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // What is left is the queue this seed enqueued, saying so. The panel is
      // the Browser's only account of the queue — the operation indicator
      // deliberately stays off this screen — so a row waiting here is
      // something the user is owed a sentence about, not silence.
      expect(find.byKey(const ValueKey('panelStartWaiting')), findsOneWidget);
      expect(
        find.text('1 download waiting for you to start it.'),
        findsOneWidget,
      );
    });
  });

  group('a queue nobody has started', () {
    // The Browser is the one screen the operation indicator stays off, on the
    // grounds that the panels here say it in full. They only ever said it
    // about a run *in flight* — so the ordinary end of a save flow, *Queue
    // only*, left the user standing on the Browser with no sign they had a
    // queue at all, and the way to start it three taps away on a screen they
    // had no reason to open.
    screenTest('says how much is waiting, and offers the Start', (
      tester,
    ) async {
      await h.seed();
      await tester.pumpWidget(app());
      await _pumpUntil(tester, find.byKey(const ValueKey('panelStartWaiting')));

      expect(
        find.text('1 download waiting for you to start it.'),
        findsOneWidget,
      );
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'a queue is not motion, and a bar here would claim it was',
      );

      await tester.tap(find.byKey(const ValueKey('panelStartWaiting')));
      await _turn(tester);
      expect(h.ui.queue.saveStartAuthorised, isTrue);
      expect(h.starts, 1);
    });
  });
}

// ─── driving two real operations ────────────────────────────────────────────

/// One turn of the real event loop, then one frame.
///
/// Both operations here are *started and left running*, and their queries land
/// on the real event loop, which a `testWidgets` fake clock never turns.
/// Pumped frames alone leave the runner parked on its first query — the same
/// reason `letFilesSettle` exists in the library UX harness, for the same kind
/// of work.
Future<void> _turn(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2)),
  );
  await tester.pump(const Duration(milliseconds: 25));
}

/// Turn until [finder] matches. Far longer than an in-memory query takes, and
/// short enough to fail a hang quickly.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await _turn(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

// ─── the composition under test ─────────────────────────────────────────────

/// The V2 stack with both operations held open on demand.
///
/// Built lazily, and that is load-bearing: `setUp` runs outside the fake async
/// zone `testWidgets` installs, and a [Completer] built there completes onto a
/// queue this test never drains.
class _Harness {
  _Harness()
    : storeRoot = Directory.systemTemp.createTempSync('scrollary_panel') {
    Directory(
      '${storeRoot.path}/${FileStore.libraryFolderName}',
    ).createSync(recursive: true);
    Directory(
      '${storeRoot.path}/${FileStore.tmpFolderName}',
    ).createSync(recursive: true);
  }

  final Directory storeRoot;

  /// How many times the panel's Start handed the queue to a runner.
  int starts = 0;

  final BrowserController browser = BrowserController();

  late final LibraryDatabase library = LibraryDatabase.forTesting(
    NativeDatabase.memory(),
  );
  late final FileStore fileStore = FileStore(storeRoot);
  late final libui.LibraryUiServices ui = libui.LibraryUiServices(
    library,
    fileStore: fileStore,
  );

  /// The save, held open until the test lets go, so "a download is running" is
  /// a real run rather than a flag.
  late final Completer<void> capture = Completer<void>();

  late final _HeldObservations observations = _HeldObservations();

  late final QueueRunner runner = QueueRunner(
    queue: ui.queue,
    captureServiceFor: () => _HeldCapture(
      capture,
      entries: ui.entries,
      collections: ui.collections,
      offlineCopies: ui.offline,
      fileStore: fileStore,
      source: const _UnusedCaptureSource(),
    ),
  );

  late final CheckController check = CheckController(
    browser: browser,
    collections: CollectionRepository(library),
    entries: EntryRepository(library),
    index: RecognitionIndex(library),
    observations: observations,
  );

  late final ForegroundMultitasking capability = ForegroundMultitasking();

  late final SyncComposition sync = SyncComposition(
    db: library,
    queue: ui.queue,
    cloudSyncAvailable: () => capability.cloudSyncAvailable,
    capabilityChanges: capability,
    transport: null,
  );

  late final V2Services services = V2Services(
    library: library,
    ui: ui,
    runner: runner,
    check: check,
    recogniser: Recogniser(
      index: RecognitionIndex(library),
      collections: CollectionRepository(library),
      reading: ReadingStateRepository(library),
    ),
    history: BrowsingHistoryStore(library),
    assist: V2AssistController(
      browser: browser,
      hints: PageHintRepository.forLibrary(library),
    ),
    sync: sync,
  );

  String _collectionId = '';

  static const _entryUrl = 'https://reading.example.com/serial/2';

  /// One Collection with one Source, one Entry with an address, and a download
  /// waiting in the queue for it.
  Future<({String collectionId, String entryId})> seed() async {
    final root = await ui.folders.ensureRoot();
    final (collection, _) = await ui.collections.create(
      name: 'Serial Alpha',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    _collectionId = collection!.id;
    final (source, _) = await ui.collections.addSource(
      collectionId: collection.id,
      host: 'reading.example.com',
      pathKey: 'serial-alpha',
      language: 'en',
    );
    final (entry, _) = await ui.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 2,
      placement: Placement.placed,
      title: 'The second one',
    );
    await ui.entries.addLocation(
      entryId: entry!.id,
      sourceId: source!.id,
      url: _entryUrl,
      urlKey: _entryUrl,
    );
    await ui.queue.enqueue(entryId: entry.id, locationUrl: _entryUrl);
    return (collectionId: collection.id, entryId: entry.id);
  }

  /// The explicit Start, as the shell performs it.
  void startQueue() => unawaited(runner.start());

  void startCheck() => unawaited(
    check.run(
      _collectionId,
      limits: const SourceCheckLimits(maxPages: 3, maxNewEntries: 50),
    ),
  );

  Future<SaveTask?> taskFor(String entryId) async {
    for (final task in await ui.queue.all()) {
      if (task.entryId == entryId) return task;
    }
    return null;
  }

  String copyPath(String entryId) => 'library/$entryId';

  Future<void> recordCopy(String entryId) async {
    final directory = Directory(fileStore.resolve(copyPath(entryId)))
      ..createSync(recursive: true);
    File(
      '${directory.path}/${FileStore.manifestFileName}',
    ).writeAsStringSync('{}');
    await ui.offline.recordCopy(
      entryId: entryId,
      locationUrl: _entryUrl,
      artifactFormat: 'imageSequence',
      contentPath: copyPath(entryId),
      byteSize: 2048,
    );
  }

  bool bytesOnDisk(String entryId) =>
      Directory(fileStore.resolve(copyPath(entryId))).existsSync();

  Future<int> copyRows(String entryId) async {
    final rows = await (library.select(
      library.offlineCopies,
    )..where((c) => c.entryId.equals(entryId))).get();
    return rows.length;
  }

  /// Let the held save end and the runner's loop unwind. A cancel poll is live
  /// for as long as one capture is, and a test that ends with it running fails
  /// on pending timers.
  Future<void> releaseCapture(WidgetTester tester) async {
    if (!capture.isCompleted) capture.complete();
    await _drain(tester);
  }

  Future<void> releaseObservation(WidgetTester tester) async {
    observations.release();
    await _drain(tester);
  }

  Future<void> _drain(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await _turn(tester);
    }
  }

  Future<void> close() async {
    runner.dispose();
    check.dispose();
    await library.close();
    if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
  }
}

/// A capture that never ends until the test says so, and never touches a page,
/// a file or a WebView on the way.
class _HeldCapture extends EntryCaptureService {
  _HeldCapture(
    this.gate, {
    required super.entries,
    required super.collections,
    required super.offlineCopies,
    required super.fileStore,
    required super.source,
  });

  final Completer<void> gate;

  @override
  Future<EntryCaptureResult> capture({
    required String entryId,
    required String locationUrl,
    required CaptureMode? captureMode,
    String? locationId,
    bool captureModeIsUserSet = false,
    bool Function()? shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
  }) async {
    await gate.future;
    return const EntryCaptureResult.failed(
      'held open by the test',
      stopReason: StopReason.cancelledByUser,
    );
  }
}

class _UnusedCaptureSource implements PageCaptureSource {
  const _UnusedCaptureSource();

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
  }) => throw UnimplementedError('the capture itself is overridden');
}

/// A reading held at its first page, which then reports whether the run was
/// still allowed to carry on.
///
/// [allowedToCarryOn] is the check's own cooperative stop, read at the
/// reading's safe boundary — the observable that proves a tap on the panel
/// reached the run rather than merely being handled.
class _HeldObservations implements SourceObservationSource {
  final Completer<void> _gate = Completer<void>();

  bool allowedToCarryOn = true;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) async {
    await _gate.future;
    allowedToCarryOn = shouldContinue();
    return SourceObservation.unreadable(
      url: pageUrl ?? '',
      stop: SourceCheckStop.listingUnreadable,
    );
  }
}
