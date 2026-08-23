/// *I am on entry 101 — give me the next three.* The whole way through.
///
/// **Why a journey test.** Every step of this path had its own passing suite
/// while the path itself was broken: the sheet asked for a count, the walk
/// resolved the pages, and what reached the device was one download. Each
/// half was doing its job; the joint between them dropped the answer. So this
/// file asserts the thing a person actually asked for — **N entries on this
/// device** — over the real planner, the real walk, the real reconciler, the
/// real queue and the real runner, with a scripted site and a scripted page
/// capture standing in for the two things a widget test cannot have.
///
/// The count is a claim about the Source and the deliverable is captures, not
/// discoveries. A test that stops at "three rows were queued" would have gone
/// green throughout the regression this exists to prevent.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_adoption_providers.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/manifest.dart';

import '../recognition/support/forward_pages_fake.dart';
import '../recognition/support/recognition_harness.dart';
import 'support/capture_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaptureHarness h;
  late LibraryUiServices services;
  late FakePageCaptureSource pages;
  late QueueRunner runner;

  setUp(() {
    h = CaptureHarness();
    services = LibraryUiServices(h.db, fileStore: h.fileStore);
    // The engine half is proved in `entry_capture_test.dart`; what matters
    // here is only that a queued row becomes bytes on this device, so every
    // page answers the same way and the addresses it was asked for are the
    // record.
    pages = FakePageCaptureSource.images(pageCount: 2, title: 'A part');
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

  /// A `WidgetRef` over these services, with the real walk over [site].
  Future<WidgetRef> refOver(WidgetTester tester, FakeForwardPages site) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(services),
          sourceWalkProvider.overrideWithValue(
            LibrarySourceWalk(
              entries: services.entries,
              collections: services.collections,
              index: RecognitionIndex(h.db),
              pages: site,
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

  /// Work the queue through, on the **real** event loop.
  ///
  /// `testWidgets` installs a fake clock, and the runner's loop and the
  /// capture underneath it await ordinary futures and file I/O that a fake
  /// clock never turns — awaited inside the test zone it simply never
  /// returns. `runAsync` is the framework's own way out, and the harness next
  /// door already uses it for the same reason.
  Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(() => runner.start());
  }

  Future<List<OfflineCopyRow>> copies() async =>
      (h.db.select(h.db.offlineCopies)..where((c) => c.active.equals(true)))
          .get();

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
    expect(report.queued, 3);

    // Queued is not downloaded. Nothing has run, and nothing may until the
    // user says so.
    expect(await copies(), isEmpty);
    expect(pages.requested, isEmpty);

    await drain(tester);

    expect(
      pages.requested,
      [partUrl(kHostA, 101), partUrl(kHostA, 102), partUrl(kHostA, 103)],
      reason: 'three captures, in reading order, from the page they started '
          'at',
    );
    final held = await copies();
    expect(held, hasLength(3), reason: 'the deliverable is entries on this '
        'device, not entries discovered');
    for (final copy in held) {
      expect(copy.artifactFormat, ArtifactFormat.imageSequence.name);
      expect(h.fileStore.entryExists(copy.contentPath), isTrue);
    }
    expect(await services.queue.pending(), isEmpty);
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
      reason: 'unplaced, and downloaded anyway — position is organisation, '
          'not permission',
    );
  });

  testWidgets('a source with fewer than were asked for delivers what there '
      'was, and says so', (tester) async {
    await onEntry101();
    final ref = await refOver(
      tester,
      FakeForwardPages.chain(host: kHostA, parts: [101, 102]),
    );

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );

    expect(report.queued, 2);
    expect(report.walkStop, WalkStop.endOfSource);
    expect(report.sentence, contains('were only 2'));

    await drain(tester);
    expect(await copies(), hasLength(2));
  });

  testWidgets('the collection\'s remembered mode is what gets captured', (
    tester,
  ) async {
    final collection = await onEntry101();
    final site = FakeForwardPages.chain(host: kHostA, parts: [101, 102]);
    final ref = await refOver(tester, site);

    // What the sheet would have loaded and passed on, without asking again.
    final preferences = CapturePreferenceStore(LocalSettingsStore(h.db));
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

    final queued = await services.queue.pending();
    expect(queued, hasLength(2));
    for (final task in queued) {
      expect(task.captureMode, CaptureMode.imageSequence);
      expect(
        task.captureModeIsUserSet,
        isTrue,
        reason: '"the person chose this" travels with the row',
      );
    }
  });

  testWidgets('queueing starts nothing', (tester) async {
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
    );

    // *Queue only.* The rows exist, the library has grown, and this device has
    // done nothing — `v2AddAndDownload` never reaches the runner, and the
    // runner is the thing that authorises the queue.
    expect(pages.requested, isEmpty);
    expect(await copies(), isEmpty);
    expect(services.queue.saveStartAuthorised, isFalse);
    expect(
      [for (final t in await services.queue.pending()) t.state],
      everyElement(SaveTaskState.queued),
    );
    expect(
      await services.queue.eligible(),
      isEmpty,
      reason: 'nothing may be claimed until somebody presses Start',
    );
  });

}
