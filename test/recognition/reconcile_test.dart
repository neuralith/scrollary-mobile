/// The one implementation of cross-source Entry equivalence (V2-D16).
///
/// `SourceDiscovery` already proves these rules over a Source's own listing
/// (`discovery_test.dart`). This suite asks the reconciler directly, because
/// every other way an address enters the library now goes through it and the
/// answer has to be the same one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/recognition/reconcile.dart';

import 'support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  EntryReconciler reconciler() =>
      EntryReconciler(entries: h.repos.entries, index: h.repos.recognition);

  test('an equal ordinal joins the Entry that already holds it', () async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: kHostA);
    final (entry, _) = await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: 5,
    );

    final result = await reconciler().entryFor(
      collectionId: collection.id,
      basis: OrderingBasis.explicitNumericIndex,
      printedNumber: 5,
      title: 'Part 5',
    );

    expect(result.action, ReconcileAction.mergedExisting);
    expect(result.entryId, entry.id);
    expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
  });

  test('100 and 99.5 stay two Entries', () async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: kHostA);
    await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: 100,
    );

    final result = await reconciler().entryFor(
      collectionId: collection.id,
      basis: OrderingBasis.explicitNumericIndex,
      printedNumber: 99.5,
      title: 'Part 99.5',
    );

    expect(result.action, ReconcileAction.createdPlaced);
    expect(await h.repos.entries.entriesOf(collection.id), hasLength(2));
  });

  test('no number leaves the Entry unplaced', () async {
    final collection = await h.collection();

    final result = await reconciler().entryFor(
      collectionId: collection.id,
      basis: OrderingBasis.explicitNumericIndex,
      printedNumber: null,
      title: 'Epilogue',
    );

    expect(result.action, ReconcileAction.createdUnplaced);
    final entry = await h.repos.entries.byId(result.entryId!);
    expect(entry!.ordinal, isNull);
    expect(entry.placement, 'unplaced');
  });

  test('a basis with no number line never merges', () async {
    final collection = await h.collection(basis: OrderingBasis.publicationDate);
    final first = await reconciler().entryFor(
      collectionId: collection.id,
      basis: OrderingBasis.publicationDate,
      printedNumber: 5,
      title: 'Part 5',
    );
    final second = await reconciler().entryFor(
      collectionId: collection.id,
      basis: OrderingBasis.publicationDate,
      printedNumber: 5,
      title: 'Part 5',
    );

    expect(first.action, ReconcileAction.createdUnplaced);
    expect(second.action, ReconcileAction.createdUnplaced);
    expect(second.entryId, isNot(first.entryId));
  });

  test('planning decides without writing a row', () async {
    final collection = await h.collection();

    final plan = await reconciler().planFor(
      collectionId: collection.id,
      basis: OrderingBasis.explicitNumericIndex,
      printedNumber: 7,
    );

    expect(plan.action, ReconcileAction.createdPlaced);
    expect(plan.ordinal, 7);
    expect(await h.repos.entries.entriesOf(collection.id), isEmpty);
  });
}
