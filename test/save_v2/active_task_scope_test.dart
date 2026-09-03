/// *Which row is being captured right now* — and the answer while none is.
///
/// **What this pins.** `QueueRunner.activeTaskId` is what the docked download
/// panel names on screen (`running_operation_panel.dart` reads the row, then
/// the Entry it points at, and puts that Entry's title beside *Downloading*).
/// It is set when a capture begins and it was cleared only when the whole run
/// ended — so between one Entry and the next it went on naming the row that
/// had just finished.
///
/// For an ordinary drain that gap is a database query. For a sequential
/// capture of a Source (V2-D56) it is **the whole page load** the walk makes
/// to find the next Entry: seconds of the Browser visibly moving to a new page
/// while the panel says the app is downloading the previous one. That is the
/// same complaint the stale page title produced, arriving by a second route.
///
/// So the invariant is stated in both directions, because only asserting the
/// second half would pass on a field that was never set at all:
///
/// * while a row is being captured, `activeTaskId` is **that** row;
/// * while the run is between rows — walking to the next page — it is null.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_adoption_providers.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/storage/file_store.dart';

import '../recognition/support/forward_pages_fake.dart';
import '../recognition/support/recognition_harness.dart';
import 'support/capture_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaptureHarness h;
  late LibraryUiServices services;
  late QueueRunner runner;
  late _Observed observed;

  setUp(() {
    h = CaptureHarness();
    services = LibraryUiServices(h.db, fileStore: h.fileStore);
    observed = _Observed();
    runner = QueueRunner(
      queue: services.queue,
      captureServiceFor: () =>
          h.captureWith(_ObservingCapture(observed, () => runner)),
    );
  });

  tearDown(() async {
    runner.dispose();
    await h.close();
  });

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  /// The library as the reader left it: one Collection, one Source, and only
  /// the Entry they are standing on.
  Future<CollectionRow> onEntry101() async {
    final root = await services.folders.ensureRoot();
    final (collection, _) = await services.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final keys = RecognitionKeys.of(partUrl(kHostA, 1));
    final (source, _) = await services.collections.addSource(
      collectionId: collection!.id,
      host: keys.host,
      pathKey: keys.pathKey!,
    );
    final (entry, _) = await services.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 101,
      title: 'Part 101',
    );
    await services.entries.addLocation(
      entryId: entry!.id,
      url: partUrl(kHostA, 101),
      urlKey: normalizeUrl(partUrl(kHostA, 101)),
      sourceId: source!.id,
      sourceNumber: 101,
    );
    return collection;
  }

  Future<WidgetRef> refOver(WidgetTester tester, FakeForwardPages site) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(services),
          queueRunnerProvider.overrideWithValue(runner),
          sourceWalkProvider.overrideWithValue(
            LibrarySourceWalk(
              entries: services.entries,
              collections: services.collections,
              index: RecognitionIndex(h.db),
              pages: _ObservingPages(site, observed, () => runner),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  /// Work the run through on the real event loop — `testWidgets` installs a
  /// fake clock the runner's file I/O never turns.
  Future<void> drain(WidgetTester tester) =>
      tester.runAsync(() => runner.start());

  testWidgets('walking to the next Entry names no row', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103, 104]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
      captureMode: CaptureMode.imageSequence,
      captureModeIsUserSet: true,
    );
    await drain(tester);

    // The journey really did walk — otherwise the assertion below is vacuous.
    expect(observed.duringWalk, hasLength(greaterThanOrEqualTo(2)));
    expect(
      observed.duringWalk,
      everyElement(isNull),
      reason:
          'no row is being captured while the Browser is being moved to the '
          'next page, so the panel has no Entry to name',
    );
  });

  testWidgets('capturing a row names that row', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(2),
      discoverMissing: true,
      captureMode: CaptureMode.imageSequence,
      captureModeIsUserSet: true,
    );
    await drain(tester);

    // Every capture ran under its own row's id — the half that makes the
    // null above a scoping rule rather than a field nobody sets.
    expect(observed.duringCapture, hasLength(2));
    for (final seen in observed.duringCapture) {
      expect(seen.taskId, isNotNull);
      final row = await services.queue.byId(seen.taskId!);
      expect(row, isNotNull);
      expect(
        row!.locationUrl,
        seen.url,
        reason: 'the row on screen is the page being read',
      );
    }
  });

  testWidgets('a finished run names nothing', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(1),
      discoverMissing: true,
    );
    await drain(tester);

    expect(runner.isRunning, isFalse);
    expect(runner.activeTaskId, isNull);
  });
}

/// What `activeTaskId` said, and when.
class _Observed {
  /// Its value each time the walk was asked to read a page — the window
  /// between one capture and the next.
  final List<String?> duringWalk = [];

  /// Its value each time a page was actually captured.
  final List<({String url, String? taskId})> duringCapture = [];
}

/// The scripted site, with `activeTaskId` read at the moment the walk moves
/// the Browser to another page.
class _ObservingPages implements ForwardPageSource {
  _ObservingPages(this._pages, this._observed, this._runner);

  final FakeForwardPages _pages;
  final _Observed _observed;
  final QueueRunner Function() _runner;

  @override
  Future<WalkedPage> read({
    required String url,
    required SourceRow source,
    required Set<String> visited,
    required bool Function() shouldContinue,
  }) {
    _observed.duringWalk.add(_runner().activeTaskId);
    return _pages.read(
      url: url,
      source: source,
      visited: visited,
      shouldContinue: shouldContinue,
    );
  }
}

/// The scripted capture, reading the same field from inside a capture.
class _ObservingCapture extends FakePageCaptureSource {
  _ObservingCapture(this._observed, this._runner)
    : super.images(pageCount: 2, title: 'A part');

  final _Observed _observed;
  final QueueRunner Function() _runner;

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) {
    _observed.duringCapture.add((url: url, taskId: _runner().activeTaskId));
    return super.capturePage(
      url: url,
      staging: staging,
      requestedMode: requestedMode,
      shouldContinue: shouldContinue,
      readerHint: readerHint,
      nextHint: nextHint,
      pageAlreadyLoaded: pageAlreadyLoaded,
    );
  }
}
