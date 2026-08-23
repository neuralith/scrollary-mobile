/// The restored journey end to end: Collection context, then how much
/// (V2_SAVE_FLOW.md §3–§4).
///
/// The orchestration owns no rules — adoption, reconciliation, planning and
/// enqueueing are each tested on their own — so what is asserted here is the
/// order they happen in, and the two answers the matrix insists on: a listing
/// never becomes an Entry, and nothing is downloaded until Start.
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
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/storage/file_store.dart';

import '../recognition/support/recognition_harness.dart';

void main() {
  late LibraryDatabase db;
  late Directory storeRoot;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    storeRoot = Directory.systemTemp.createTempSync('scrollary_add_flow');
  });
  tearDown(() async {
    await db.close();
    if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
  });

  /// A `WidgetRef` over the library, built inside the test body — the
  /// repositories hold `Future` chains, and one created outside the fake async
  /// zone never completes.
  Future<WidgetRef> refOver(WidgetTester tester) async {
    final services = LibraryUiServices(db, fileStore: FileStore(storeRoot));
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryUiServicesProvider.overrideWithValue(services)],
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

  SaveLimits count(int n) =>
      SaveLimits.forScope(SaveScope.fixedCount, requestedCount: n);

  testWidgets('an unknown site becomes a Collection and queues its '
      'entry', (tester) async {
    final ref = await refOver(tester);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 5),
      pageTitle: 'Part 5',
      newCollectionName: 'Quiet Harbour',
      limits: count(3),
    );

    expect(report.succeeded, isTrue);
    expect(report.queued, 1);
    expect(report.shortfall, 2);
    expect(
      report.sentence,
      contains(
        'nothing is downloaded until you press '
        'Start',
      ),
    );
    expect(report.sentence, contains('checking this collection'));

    final entries = await db.select(db.entries).get();
    expect(entries, hasLength(1));
    expect(entries.single.collectionId, report.collectionId);
    expect(entries.single.ordinal, 5);
    expect(
      entries.where((e) => e.collectionId == null),
      isEmpty,
      reason: 'a serialized page never becomes standalone silently',
    );
    expect(await db.select(db.saveQueue).get(), hasLength(1));
  });

  testWidgets('a listing is added as a Source, and no Entry is '
      'invented for it', (tester) async {
    final ref = await refOver(tester);

    final report = await v2AddAndDownload(
      ref,
      url: 'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
      newCollectionName: 'Quiet Harbour',
      // The sheet asked; the orchestration is told. A count asked for
      // alongside it is discarded rather than honoured, because a listing has
      // no entry on it to download.
      isListing: true,
      limits: count(5),
    );

    expect(report.succeeded, isTrue);
    expect(report.entryId, isNull);
    expect(report.queued, 0);
    expect(report.sentence, contains('A list is not an entry'));
    expect(await db.select(db.sources).get(), hasLength(1));
    expect(await db.select(db.entries).get(), isEmpty);
    expect(await db.select(db.saveQueue).get(), isEmpty);
  });

  testWidgets('a Collection to join and one to create are not both '
      'given', (tester) async {
    final ref = await refOver(tester);

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 5),
      pageTitle: 'Part 5',
      collectionId: 'anything',
      newCollectionName: 'Quiet Harbour',
      limits: count(1),
    );

    expect(report.succeeded, isFalse);
    expect(report.sentence, contains('not both'));
    expect(await db.select(db.collections).get(), isEmpty);
  });

  testWidgets('a page already in the library only queues', (tester) async {
    final ref = await refOver(tester);
    final first = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 5),
      pageTitle: 'Part 5',
      newCollectionName: 'Quiet Harbour',
    );
    expect(first.queued, 0, reason: 'no limits means nothing is queued');

    final report = await v2AddAndDownload(
      ref,
      url: partUrl(kHostA, 5),
      pageTitle: 'Part 5',
      limits: count(1),
    );

    expect(report.entryId, first.entryId);
    expect(report.queued, 1);
    expect(await db.select(db.collections).get(), hasLength(1));
  });

  testWidgets('a loose Entry is adopted into a Collection', (tester) async {
    final ref = await refOver(tester);
    final services = ref.read(libraryUiServicesProvider);
    final root = await services.folders.ensureRoot();
    final (collection, _) = await services.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (entry, _) = await services.entries.createStandalone(
      folderId: root.id,
      title: 'Part 7',
    );
    final url = partUrl(kHostB, 7);
    await services.entries.addLocation(
      entryId: entry!.id,
      url: url,
      urlKey: url,
    );

    final report = await v2AdoptStandalone(
      ref,
      entryId: entry.id,
      collectionId: collection!.id,
    );

    expect(report.succeeded, isTrue);
    expect(report.sentence, contains('Moved into Quiet Harbour'));
    final moved = await services.entries.byId(entry.id);
    expect(moved!.collectionId, collection.id);
    expect(moved.ordinal, 7);
  });
}
