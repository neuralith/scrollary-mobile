/// *Download the next N from here* — the second thing a typed count can mean
/// (docs/V2_SAVE_FLOW.md §4), as the add flow orders it.
///
/// The journey itself is proved end to end in `capture_journey_test.dart` and
/// the walk's own rules in `test/recognition/walk_test.dart`. What is asserted
/// here is the orchestration's share, and it is small on purpose: this call
/// writes the row for the entry the user is standing on, hands the runner the
/// journey that continues from it, and **opens nothing at all**. A count that
/// asks about the Source no longer resolves a range before the user has
/// started anything (V2-D56).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_adoption_providers.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/storage/file_store.dart';

import '../recognition/support/forward_pages_fake.dart';
import '../recognition/support/recognition_harness.dart';
import 'support/capture_harness.dart';

/// A [SourceWalk] that records what it was asked and reads nothing.
///
/// Whether it is *called* is most of what this file asserts: queueing must not
/// walk, and the journey the runner takes later must start where the user was
/// standing.
class RecordingWalk implements SourceWalk {
  final List<({String fromLocationId, int wanted})> calls = [];

  @override
  Future<WalkOutcome> forward({
    required String fromLocationId,
    required int wanted,
    required bool Function() shouldContinue,
    Future<bool> Function(WalkedEntry entry)? onEntry,
    int maxPages = kMaxWalkPages,
  }) async {
    calls.add((fromLocationId: fromLocationId, wanted: wanted));
    return WalkOutcome(
      entries: const [],
      stop: WalkStop.endOfSource,
      pagesRead: 1,
      requested: wanted,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryDatabase db;
  late Directory storeRoot;
  late FileStore fileStore;
  late LibraryUiServices services;
  late QueueRunner runner;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    storeRoot = Directory.systemTemp.createTempSync('scrollary_add_walk');
    fileStore = FileStore(storeRoot);
    services = LibraryUiServices(db, fileStore: fileStore);
    // Never started in this file: what a Start does with a journey belongs to
    // `capture_journey_test.dart`. It is here so the flow has somewhere real
    // to hand one.
    runner = QueueRunner(
      queue: services.queue,
      captureServiceFor: () => EntryCaptureService(
        entries: services.entries,
        collections: services.collections,
        offlineCopies: services.offline,
        fileStore: fileStore,
        capturePreferences: CapturePreferenceStore(db),
        source: FakePageCaptureSource.images(),
      ),
    );
  });
  tearDown(() async {
    runner.dispose();
    await db.close();
    if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
  });

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  /// The parts the library already holds, on one Source of one Collection.
  Future<({CollectionRow collection, SourceRow source, LocationRow first})>
  seed(List<num> parts) async {
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
    LocationRow? first;
    for (final part in parts) {
      final label = plainNumber(part);
      final (entry, _) = await services.entries.createInCollection(
        collectionId: collection.id,
        ordinal: part.toDouble(),
        title: 'Part $label',
      );
      final url = partUrl(kHostA, label);
      final (location, _) = await services.entries.addLocation(
        entryId: entry!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
        sourceId: source!.id,
        sourceNumber: part.toDouble(),
      );
      first ??= location;
    }
    return (collection: collection, source: source!, first: first!);
  }

  /// A `WidgetRef` over the library with [walk] standing in for the real one.
  Future<WidgetRef> refWith(WidgetTester tester, SourceWalk walk) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(services),
          sourceWalkProvider.overrideWithValue(walk),
          queueRunnerProvider.overrideWithValue(runner),
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

  testWidgets('a count from here queues this entry and arranges the rest, '
      'opening nothing', (tester) async {
    final it = await seed([101, 102, 103, 104, 105]);
    final walk = RecordingWalk();
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );

    expect(
      walk.calls,
      isEmpty,
      reason: 'queueing reads no page — the journey does that on Start',
    );
    expect(report.queued, 1);
    expect(report.shortfall, 2);
    final rows = await db.select(db.saveQueue).get();
    expect(rows, hasLength(1));
    expect(
      rows.single.locationUrl,
      it.first.url,
      reason: 'the entry in front of the user, at the address it is read at',
    );
    expect(
      runner.pendingJourneyEntries,
      3,
      reason: 'the typed count is what the run will be measured against',
    );
    expect(report.sentence, contains('up to 3 entries'));
    expect(
      report.sentence,
      contains('nothing is downloaded until you press Start'),
    );
  });

  testWidgets('the library-only range plans the whole count and takes no '
      'journey', (tester) async {
    await seed([101, 102]);
    final walk = RecordingWalk();
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
    );

    expect(walk.calls, isEmpty);
    expect(report.queued, 2);
    expect(report.shortfall, 3);
    expect(report.sentence, contains('checking this collection'));
    expect(
      runner.pendingJourneyEntries,
      0,
      reason:
          'this range is a claim about the library, so nothing reads a '
          'site on its behalf',
    );
    expect(await db.select(db.saveQueue).get(), hasLength(2));
  });

  testWidgets('a count of one is the page in front of the user, whichever '
      'range was chosen', (tester) async {
    await seed([101, 102]);
    final ref = await refWith(tester, RecordingWalk());

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(1),
      discoverMissing: true,
    );

    expect(report.queued, 1);
    expect(
      runner.pendingJourneyEntries,
      0,
      reason: 'there is nothing after this page to go and find',
    );
    expect(await db.select(db.saveQueue).get(), hasLength(1));
  });

  testWidgets('a second count arranges a second journey rather than losing '
      'the first', (tester) async {
    await seed([101, 102]);
    final ref = await refWith(tester, RecordingWalk());

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );
    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 102),
      pageTitle: 'Part 102',
      limits: count(4),
      discoverMissing: true,
    );

    expect(
      runner.pendingJourneyEntries,
      7,
      reason: 'two things were asked for and both are waiting for the Start',
    );
  });
}
