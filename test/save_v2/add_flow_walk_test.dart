/// *Download the next N from here* — the second thing a typed count can mean
/// (docs/V2_SAVE_FLOW.md §4), as the add flow orders it.
///
/// The walk's own rules are proved in `test/recognition/walk_test.dart`. What
/// is asserted here is the orchestration's share, which is an order: the
/// library is planned against first and opens nothing, the Source is walked
/// only for what is missing, and the sentence the user reads says honestly how
/// each half went. Nothing in either half starts a run.
library;

import 'dart:io';

import 'package:drift/native.dart';
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
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/storage/file_store.dart';

import '../recognition/support/forward_pages_fake.dart';
import '../recognition/support/recognition_harness.dart';

/// A [SourceWalk] that records what it was asked, and answers with whatever it
/// was given — the real walk, or a scripted outcome.
class RecordingWalk implements SourceWalk {
  RecordingWalk({this.delegate, this.answer});

  final SourceWalk? delegate;
  final WalkOutcome? answer;
  final List<({String fromLocationId, int wanted})> calls = [];

  @override
  Future<WalkOutcome> forward({
    required String fromLocationId,
    required int wanted,
    required bool Function() shouldContinue,
    int maxPages = kMaxWalkPages,
  }) async {
    calls.add((fromLocationId: fromLocationId, wanted: wanted));
    final real = delegate;
    if (real != null) {
      return real.forward(
        fromLocationId: fromLocationId,
        wanted: wanted,
        shouldContinue: shouldContinue,
        maxPages: maxPages,
      );
    }
    return answer ??
        WalkOutcome(
          entries: const [],
          stop: WalkStop.endOfSource,
          pagesRead: 1,
          requested: wanted,
        );
  }
}

void main() {
  late LibraryDatabase db;
  late Directory storeRoot;
  late LibraryUiServices services;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    storeRoot = Directory.systemTemp.createTempSync('scrollary_add_walk');
    services = LibraryUiServices(db, fileStore: FileStore(storeRoot));
  });
  tearDown(() async {
    await db.close();
    if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
  });

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  /// The parts the library already holds, on one Source of one Collection.
  Future<({CollectionRow collection, SourceRow source, LocationRow last})> seed(
    List<num> parts,
  ) async {
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
    LocationRow? last;
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
      last = location;
    }
    return (collection: collection, source: source!, last: last!);
  }

  /// A `WidgetRef` over the library with [walk] standing in for the real one.
  Future<WidgetRef> refWith(WidgetTester tester, SourceWalk walk) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(services),
          sourceWalkProvider.overrideWithValue(walk),
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

  /// The real walk, over these repositories and a scripted site.
  SourceWalk realWalkOver(FakeForwardPages pages) => LibrarySourceWalk(
    entries: services.entries,
    collections: services.collections,
    index: RecognitionIndex(db),
    pages: pages,
  );

  testWidgets('a request the library can answer in full never opens '
      'anything', (tester) async {
    await seed([101, 102, 103, 104, 105]);
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
      reason: 'a fully known request is planned, never traversed',
    );
    expect(report.queued, 3);
    expect(report.shortfall, 0);
    expect(report.walkStop, isNull);
    expect(await db.select(db.saveQueue).get(), hasLength(3));
  });

  testWidgets('the older answer opens nothing at all', (tester) async {
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
  });

  testWidgets('a short request walks the shortfall, then queues the '
      'total', (tester) async {
    await seed([101, 102]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [102, 103, 104, 105, 106, 107],
    );
    final walk = RecordingWalk(delegate: realWalkOver(pages));
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );

    expect(walk.calls, hasLength(1));
    expect(
      walk.calls.single.wanted,
      3,
      reason: 'the walk is asked for the shortfall, not the whole count',
    );
    expect(report.queued, 5);
    expect(report.shortfall, 0);
    expect(report.walkStop, WalkStop.countReached);
    expect(report.sentence, contains('5 entries queued'));
    expect(
      report.sentence,
      contains('nothing is downloaded until you press Start'),
    );

    final entries = await db.select(db.entries).get();
    expect([for (final e in entries) e.ordinal], [101, 102, 103, 104, 105]);
    expect(await db.select(db.saveQueue).get(), hasLength(5));
  });

  testWidgets('the walk starts from the furthest entry the library already '
      'holds', (tester) async {
    final it = await seed([101, 102]);
    final walk = RecordingWalk();
    final ref = await refWith(tester, walk);

    await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(4),
      discoverMissing: true,
    );

    expect(walk.calls.single.fromLocationId, it.last.id);
  });

  testWidgets('a source with fewer than were asked for says so', (
    tester,
  ) async {
    await seed([101, 102]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [102, 103, 104]);
    final walk = RecordingWalk(delegate: realWalkOver(pages));
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(10),
      discoverMissing: true,
    );

    expect(report.queued, 4);
    expect(report.shortfall, 6);
    expect(report.walkStop, WalkStop.endOfSource);
    expect(report.sentence, contains('were only 4'));
    expect(await db.select(db.saveQueue).get(), hasLength(4));
  });

  testWidgets('a stopped walk keeps what it found and says who stopped '
      'it', (tester) async {
    await seed([101, 102]);
    final walk = RecordingWalk(
      answer: const WalkOutcome(
        entries: [],
        stop: WalkStop.cancelledByUser,
        pagesRead: 2,
        requested: 3,
      ),
    );
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );

    expect(report.queued, 2);
    expect(report.walkStop, WalkStop.cancelledByUser);
    expect(report.sentence, contains('You stopped the search'));
  });

  testWidgets('a next control nobody could identify asks the user rather '
      'than guessing', (tester) async {
    await seed([101, 102]);
    final walk = RecordingWalk(
      answer: const WalkOutcome(
        entries: [],
        stop: WalkStop.needsUserAssist,
        pagesRead: 1,
        requested: 3,
      ),
    );
    final ref = await refWith(tester, walk);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(5),
      discoverMissing: true,
    );

    expect(report.walkStop, WalkStop.needsUserAssist);
    expect(report.sentence, contains('Point at it once'));
  });

  test('the cancellation seam is armed per walk and stops the next '
      'boundary', () {
    final cancellation = SourceWalkCancellation()..begin();
    expect(cancellation.shouldContinue(), isTrue);
    cancellation.cancel();
    expect(cancellation.shouldContinue(), isFalse);
    expect(cancellation.isCancelled, isTrue);
    cancellation.begin();
    expect(
      cancellation.shouldContinue(),
      isTrue,
      reason: 'a new walk does not inherit the last one\'s stop',
    );
  });

  testWidgets('a count of N captures N, even where the entries have no '
      'position', (tester) async {
    // The regression this pins. A Collection ordered by the site\'s own next
    // links does not support cross-source merging, so `EntryReconciler`
    // refuses to place anything the walk reads — every resolved Entry is
    // `unplaced`, which is a real, addressed, downloadable state. Re-planning
    // over the library after the walk could not see those Entries at all, so
    // a count the Source had just satisfied came back with one row queued.
    final root = await services.folders.ensureRoot();
    final (collection, _) = await services.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.detectedNextLink,
    );
    final keys = RecognitionKeys.of(partUrl(kHostA, 1));
    final (source, _) = await services.collections.addSource(
      collectionId: collection!.id,
      host: keys.host,
      pathKey: keys.pathKey!,
    );
    final (first, _) = await services.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 101,
      title: 'Part 101',
    );
    await services.entries.addLocation(
      entryId: first!.id,
      url: partUrl(kHostA, 101),
      urlKey: RecognitionKeys.of(partUrl(kHostA, 101)).urlKey,
      sourceId: source!.id,
      sourceNumber: 101,
    );

    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104],
    );
    final ref = await refWith(tester, realWalkOver(pages));

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );

    expect(
      report.queued,
      3,
      reason: 'three captures were asked for and three are queued',
    );
    expect(report.shortfall, 0);
    final rows = await db.select(db.saveQueue).get();
    expect(rows, hasLength(3));
    expect(
      {for (final row in rows) row.locationUrl},
      {partUrl(kHostA, 101), partUrl(kHostA, 102), partUrl(kHostA, 103)},
    );
    // And the Entries the walk wrote are unplaced — the point being that a
    // position is not what makes an Entry downloadable.
    final entries = await db.select(db.entries).get();
    expect(entries, hasLength(3));
    expect(
      entries.where((e) => e.ordinal == null),
      hasLength(2),
      reason: 'this collection does not number, and nothing invented one',
    );
  });

  testWidgets('an entry the walk merged into a placed one is queued once', (
    tester,
  ) async {
    // 102 is already in the library, unaddressed on this Source. The walk
    // reads it, reconciles onto the Entry that is already there, and the
    // capture list must not carry it twice.
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
    final (first, _) = await services.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 101,
      title: 'Part 101',
    );
    await services.entries.addLocation(
      entryId: first!.id,
      url: partUrl(kHostA, 101),
      urlKey: RecognitionKeys.of(partUrl(kHostA, 101)).urlKey,
      sourceId: source!.id,
      sourceNumber: 101,
    );
    // Known at 102, with no address on this Source yet.
    await services.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 102,
      title: 'Part 102',
    );

    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]);
    final ref = await refWith(tester, realWalkOver(pages));

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 101),
      pageTitle: 'Part 101',
      limits: count(3),
      discoverMissing: true,
    );

    expect(report.queued, 3);
    final rows = await db.select(db.saveQueue).get();
    expect(rows, hasLength(3));
    expect(
      {for (final row in rows) row.entryId},
      hasLength(3),
      reason: 'one row per entry — a merge is not a second target',
    );
  });
}
