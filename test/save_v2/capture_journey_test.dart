/// *I am on entry 101 — give me the next three.* The whole way through, in
/// the order it actually happens.
///
/// **Why a journey test.** Every step of this path had its own passing suite
/// while the path itself was broken: the sheet asked for a count, the walk
/// resolved the pages, and what reached the device was one download. Each
/// half was doing its job; the joint between them dropped the answer. So this
/// file asserts the thing a person actually asked for — **N entries on this
/// device** — over the real walk, the real reconciler, the real queue and the
/// real runner, with a scripted site and a scripted page capture standing in
/// for the two things a widget test cannot have.
///
/// It also asserts the *order*, which is the second regression this path had.
/// A count used to be answered by reading the whole range first and
/// downloading afterwards: a hundred pages opened before the first byte was
/// kept, and every one of them opened again to capture it. The journal below
/// is what proves that is gone — each entry is captured on the page that was
/// opened to identify it, and the entry after it is not looked for until then
/// (V2-D56).
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
import 'package:web_reader/library_ui/run_summary.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../recognition/support/forward_pages_fake.dart';
import '../recognition/support/recognition_harness.dart';
import 'support/capture_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaptureHarness h;
  late LibraryUiServices services;
  late _Journal journal;
  late _WatchedCapture pages;
  late QueueRunner runner;

  setUp(() {
    h = CaptureHarness();
    services = LibraryUiServices(h.db, fileStore: h.fileStore);
    journal = _Journal();
    // The engine half is proved in `entry_capture_test.dart`; what matters
    // here is only that a target becomes bytes on this device, so every page
    // answers the same way and the addresses it was asked for are the record.
    pages = _WatchedCapture(journal);
    runner = QueueRunner(
      queue: services.queue,
      captureServiceFor: () => h.captureWith(pages),
    );
  });

  tearDown(() async {
    runner.dispose();
    await h.close();
  });

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  /// The library as the reader left it: one Collection, one Source, and only
  /// the entry they are standing on.
  Future<CollectionRow> onEntry101({
    OrderingBasis basis = OrderingBasis.explicitNumericIndex,
  }) async {
    final root = await services.folders.ensureRoot();
    final (collection, _) = await services.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: basis,
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

  /// A `WidgetRef` over these services, with the real walk over [site] and the
  /// one runner this test drains through.
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
              pages: _WatchedPages(site, journal),
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

  /// Work the run through, on the **real** event loop.
  ///
  /// `testWidgets` installs a fake clock, and the runner's loop and the
  /// capture underneath it await ordinary futures and file I/O that a fake
  /// clock never turns — awaited inside the test zone it simply never
  /// returns. `runAsync` is the framework's own way out, and the harness next
  /// door already uses it for the same reason.
  Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(() => runner.start());
  }

  Future<List<OfflineCopyRow>> copies() async => (h.db.select(
    h.db.offlineCopies,
  )..where((c) => c.active.equals(true))).get();

  String read(Object part) => 'read ${partUrl(kHostA, part)}';
  String captured(Object part) => 'capture ${partUrl(kHostA, part)}';

  testWidgets('a count of three from here puts three entries on this '
      'device', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103, 104]),
    );

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
      captureMode: CaptureMode.imageSequence,
      captureModeIsUserSet: true,
    );
    expect(
      report.queued,
      1,
      reason:
          'the entry in front of the user is the only one there is an '
          'address for yet — the rest are found as it downloads',
    );

    // Queued is not downloaded, and nothing has been *read* either: the
    // journey opens its first page on the user's Start and not before.
    expect(await copies(), isEmpty);
    expect(journal.steps, isEmpty);

    await drain(tester);

    expect(
      pages.requested,
      [partUrl(kHostA, 101), partUrl(kHostA, 102), partUrl(kHostA, 103)],
      reason:
          'three captures, in reading order, from the page they started '
          'at',
    );
    final held = await copies();
    expect(
      held,
      hasLength(3),
      reason:
          'the deliverable is entries on this '
          'device, not entries discovered',
    );
    for (final copy in held) {
      expect(copy.artifactFormat, ArtifactFormat.imageSequence.name);
      expect(h.fileStore.entryExists(copy.contentPath), isTrue);
    }
    expect(await services.queue.pending(), isEmpty);
  });

  testWidgets('each entry is captured before the one after it is looked '
      'for', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103, 104, 105]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );
    await drain(tester);

    // The whole journey, in the order it happened. A pre-walk would read 102
    // and 103 — and, for a count of a hundred, ninety-nine pages — before the
    // first capture appeared in this list at all.
    expect(journal.steps, [
      captured(101),
      read(101),
      read(102),
      captured(102),
      read(103),
      captured(103),
    ]);
    expect(
      journal.steps.indexOf(read(103)),
      greaterThan(journal.steps.indexOf(captured(101))),
      reason: 'entry 103 is not visited until 101 is on the device',
    );
    expect(
      journal.steps.where((s) => s.startsWith('read')),
      hasLength(3),
      reason:
          'one page opened per entry, not one to find it and one to '
          'capture it',
    );
    expect(
      pages.reusedLoadedPage,
      [false, true, true],
      reason:
          'every entry after the first is captured on the page the walk '
          'had just opened to identify it',
    );
  });

  testWidgets('a source that ends before the count delivers what there was, '
      'and says so', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );
    await drain(tester);

    expect(await copies(), hasLength(2));
    expect(journal.steps.where((s) => s.startsWith('capture')), [
      captured(101),
      captured(102),
    ], reason: 'nothing after the end of the source was invented');

    final run = runner.lastRun!;
    expect(
      run.requested,
      5,
      reason:
          'the run knows what was asked for from the first entry, not '
          'from what the queue happened to hold',
    );
    expect(run.downloaded, 2);
    expect(runSummaryHeadline(run), '2 of 5 entries downloaded');
    expect(runSummaryDetail(run), contains('No next entry found'));
    expect(run.failed, 0, reason: 'the end of a source is not a failure');
  });

  testWidgets('one Start runs the whole operation', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]),
    );

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );

    // What *Start now* has to work with: a row to authorise, and a journey
    // waiting on the runner that names the whole bound.
    expect(report.queued, greaterThan(0));
    expect(runner.pendingJourneyEntries, 3);

    await drain(tester);

    expect(
      await copies(),
      hasLength(3),
      reason: 'one start, three entries — nothing else has to be pressed',
    );
    expect(
      runner.pendingJourneyEntries,
      0,
      reason: 'a journey is taken once; the next Start has none',
    );
  });

  testWidgets('queue only stays waiting until it is started', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );

    // *Queue only.* A row exists, the journey is arranged, and this device has
    // done nothing at all — no page opened, nothing downloaded, and the queue
    // unauthorised.
    expect(journal.steps, isEmpty);
    expect(pages.requested, isEmpty);
    expect(await copies(), isEmpty);
    expect(services.queue.saveStartAuthorised, isFalse);
    expect([
      for (final t in await services.queue.pending()) t.state,
    ], everyElement(SaveTaskState.queued));
    expect(
      await services.queue.eligible(),
      isEmpty,
      reason: 'nothing may be claimed until somebody presses Start',
    );
    expect(runner.pendingJourneyEntries, 3);
  });

  testWidgets('stopping the entry being downloaded stops the operation', (
    tester,
  ) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103, 104, 105]),
    );
    // The user presses Stop while the third entry is being read.
    pages.interrupt = (url) async {
      if (url != partUrl(kHostA, 103)) return null;
      for (final task in await services.queue.pending()) {
        if (task.state == SaveTaskState.running) {
          await services.queue.cancel(task.id);
        }
      }
      return PageCaptureOutcome.failed(
        pageUrl: url,
        error: 'cancelled',
        stopReason: StopReason.cancelledByUser,
      );
    };

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );
    await drain(tester);

    expect(
      journal.steps.contains(read(104)),
      isFalse,
      reason: 'a stopped operation opens no further page',
    );
    expect(journal.steps.where((s) => s.contains('part-104')), isEmpty);
    expect(journal.steps.where((s) => s.startsWith('capture')), [
      captured(101),
      captured(102),
      captured(103),
    ]);
    expect(
      await copies(),
      hasLength(2),
      reason: 'the two that finished stay on this device',
    );
    final rows = await services.queue.all();
    expect(rows, hasLength(3), reason: 'no further row was written');
    expect(rows.last.state, SaveTaskState.cancelled);
  });

  testWidgets('and still three when the collection numbers nothing', (
    tester,
  ) async {
    // The regression's own shape: a Collection whose ordering basis does not
    // support cross-source merging leaves every walked Entry unplaced, and a
    // capture list re-derived from the library could not see one of them.
    await onEntry101(basis: OrderingBasis.detectedNextLink);
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
    );
    await drain(tester);

    expect(await copies(), hasLength(3));
    final entries = await h.db.select(h.db.entries).get();
    expect(
      entries.where((e) => e.ordinal == null),
      hasLength(2),
      reason:
          'unplaced, and downloaded anyway — position is organisation, '
          'not permission',
    );
  });

  testWidgets('an entry the walk merged into a placed one is captured once', (
    tester,
  ) async {
    // 102 is already in the library at its position, with no address on this
    // Source yet. The walk reconciles onto it rather than making a twin, and
    // the journey captures it once.
    final collection = await onEntry101();
    await services.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 102,
      title: 'Part 102',
    );
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]),
    );

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );
    await drain(tester);

    expect(await h.db.select(h.db.entries).get(), hasLength(3));
    expect(await copies(), hasLength(3));
    final rows = await services.queue.all();
    expect(
      {for (final row in rows) row.entryId},
      hasLength(3),
      reason: 'one row per entry — a merge is not a second target',
    );
  });

  testWidgets('the collection\'s remembered mode is what gets captured', (
    tester,
  ) async {
    final collection = await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102]),
    );

    // What the sheet would have loaded and passed on, without asking again.
    final preferences = CapturePreferenceStore(h.db);
    await preferences.remember(collection.id, CaptureMode.imageSequence);
    final remembered = await preferences.of(collection.id);
    expect(remembered, CaptureMode.imageSequence);

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(2),
      discoverMissing: true,
      captureMode: remembered,
      captureModeIsUserSet: true,
    );
    await drain(tester);

    final rows = await services.queue.all();
    expect(rows, hasLength(2));
    for (final task in rows) {
      expect(task.captureMode, CaptureMode.imageSequence);
      expect(
        task.captureModeIsUserSet,
        isTrue,
        reason: '"the person chose this" travels with the row',
      );
    }
    expect(pages.modes, everyElement(CaptureMode.imageSequence));
  });
}

/// Both halves of the journey, writing into one list.
///
/// The order *between* reading a page and capturing one is the whole claim
/// this file makes, and two separate recordings cannot state it.
class _Journal {
  final List<String> steps = [];
}

/// The scripted site, with every page it is asked for written down.
class _WatchedPages implements ForwardPageSource {
  _WatchedPages(this._pages, this._journal);

  final FakeForwardPages _pages;
  final _Journal _journal;

  @override
  Future<WalkedPage> read({
    required String url,
    required SourceRow source,
    required Set<String> visited,
    required bool Function() shouldContinue,
  }) {
    _journal.steps.add('read $url');
    return _pages.read(
      url: url,
      source: source,
      visited: visited,
      shouldContinue: shouldContinue,
    );
  }
}

/// The scripted capture, written down in the same list — and able to stand in
/// for the user pressing Stop half way through one.
class _WatchedCapture extends FakePageCaptureSource {
  _WatchedCapture(this._journal) : super.images(pageCount: 2, title: 'A part');

  final _Journal _journal;

  /// Answers for one address instead of capturing it. Null carries on.
  Future<PageCaptureOutcome?> Function(String url)? interrupt;

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) async {
    _journal.steps.add('capture $url');
    final interrupted = await interrupt?.call(url);
    if (interrupted != null) {
      requested.add(url);
      modes.add(requestedMode);
      readerHints.add(readerHint);
      nextHints.add(nextHint);
      reusedLoadedPage.add(pageAlreadyLoaded);
      return interrupted;
    }
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
