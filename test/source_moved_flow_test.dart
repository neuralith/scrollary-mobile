/// *This collection's site has moved* — the question the user is asked, and
/// the three writes their answer authorises.
///
/// The rule these tests exist for: **persistent Source identity is never
/// changed without an answer.** `(host, path_key)` is what recognition,
/// traversal and every guard key on, so a check that finds strong evidence of
/// a move stops and asks; nothing here may write a Source identity on its own,
/// and backing out has to leave the library byte-for-byte as it was.
///
/// Hosts are the reserved `.example` names. No real provider is named.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/location.dart';
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/relocation.dart';

import 'library_ui/support/ui_harness.dart';

const String kHost = 'reading.example.com';
const String kOldPath = '/serial-alpha-08677664';
const String kNewPath = '/serial-alpha-a728349g';

String oldEntryUrl(int n) => 'https://$kHost$kOldPath/part-$n';
String newEntryUrl(int n) => 'https://$kHost$kNewPath/part-$n';

void main() {
  group('the sentence a moved listing gets', () {
    test('never says up to date, because nothing was read', () {
      final sentence = checkOutcomeSentence(
        const SourceCheckOutcome(
          sourceId: 's1',
          state: SourceCheckState.stopped,
          stopReason: SourceCheckStop.sourceListingMoved,
        ),
      );
      expect(sentence, contains('appears to have moved'));
      expect(sentence, isNot(contains('Up to date')));
    });
  });

  group('the sheet', () {
    late UiHarness h;
    late String collectionId;
    late SourceRow source;

    Future<void> seed() async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      collectionId = collection.id;
      source = await h.source(collectionId, host: kHost, pathKey: kOldPath);
    }

    SourceRelocationCandidate candidate({int seen = 3}) =>
        SourceRelocationCandidate(
          sourceId: source.id,
          host: kHost,
          previousPathKey: kOldPath,
          pathKey: kNewPath,
          listingsSeen: seen,
        );

    Widget host() => h.app(
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            key: const ValueKey('askMove'),
            onPressed: () => resolveSourceMove(
              context,
              ref,
              collectionId: collectionId,
              collectionName: 'Serial Alpha',
              candidate: candidate(),
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('askMove')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    setUp(() async {
      h = UiHarness();
    });
    tearDown(() => h.close());

    screenTest('states the move, both addresses, and changes nothing yet', (
      tester,
    ) async {
      await seed();
      await open(tester);

      expect(find.text('This collection\'s site has moved'), findsOneWidget);
      expect(find.textContaining('$kHost$kOldPath'), findsOneWidget);
      expect(find.textContaining('$kHost$kNewPath'), findsOneWidget);
      expect(
        find.textContaining('Nothing has been changed yet'),
        findsOneWidget,
      );
    });

    screenTest('offers the three answers and a way out', (tester) async {
      await seed();
      await open(tester);

      expect(find.byKey(const ValueKey('sourceMovedUpdate')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sourceMovedAddSource')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sourceMovedDifferent')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sourceMovedNotNow')), findsOneWidget);
    });

    screenTest('Not now writes nothing at all', (tester) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedNotNow')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 1);
      expect(rows.single.pathKey, kOldPath);
      expect(rows.single.lifecycle, SourceLifecycle.active.name);
      expect(h.opened, isEmpty);
    });

    // --- update this source ------------------------------------------------

    screenTest('Update this source points the old row forward and keeps it', (
      tester,
    ) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedUpdate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 2, reason: 'the old row is kept, not replaced');
      final before = rows.firstWhere((s) => s.id == source.id);
      final now = rows.firstWhere((s) => s.id != source.id);
      expect(before.lifecycle, SourceLifecycle.resolvedInto.name);
      expect(before.resolvedIntoSourceId, now.id);
      expect(now.pathKey, kNewPath);
      expect(now.collectionId, collectionId);
    });

    screenTest('Update this source keeps entries, progress and downloads', (
      tester,
    ) async {
      await seed();
      final entry = await h.entryIn(
        collectionId,
        title: 'Part 101',
        ordinal: 101,
      );
      await h.location(
        entry.id,
        oldEntryUrl(101),
        sourceId: source.id,
        sourceNumber: 101,
      );
      await h.reading.recordSourceAccess(entry.id);
      final copy = await h.offline.recordCopy(
        entryId: entry.id,
        locationUrl: oldEntryUrl(101),
        artifactFormat: 'imageSequence',
        contentPath: 'packages/${entry.id}',
        byteSize: 2048,
      );

      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedUpdate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect((await h.entries.entriesOf(collectionId)).length, 1);
      expect((await h.reading.stateOf(entry.id)).lastReadAt, isNotNull);
      final held = await h.offline.activeCopyOf(entry.id);
      expect(held?.id, copy.id);
      expect(held?.byteSize, 2048);
    });

    screenTest('Update this source refiles rows an earlier build misplaced', (
      tester,
    ) async {
      await seed();
      final entry = await h.entryIn(
        collectionId,
        title: 'Part 102',
        ordinal: 102,
      );
      // What the buggy build wrote: an address on the NEW path, filed on the
      // Source that still claims the old one.
      final misfiled = await h.location(
        entry.id,
        newEntryUrl(102),
        sourceId: source.id,
        sourceNumber: 102,
      );
      // And an ordinary row, on the path its Source really does claim.
      final ordinary = await h.location(
        entry.id,
        oldEntryUrl(102),
        sourceId: source.id,
        sourceNumber: 102,
      );

      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedUpdate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final moved = (await h.collections.sourcesOf(
        collectionId,
      )).firstWhere((s) => s.id != source.id);
      expect(
        (await h.entries.locationById(misfiled.id))!.sourceId,
        moved.id,
        reason: 'its address provably belongs to the destination',
      );
      expect(
        (await h.entries.locationById(ordinary.id))!.sourceId,
        source.id,
        reason: 'a row on its own Source\'s path is left where it is',
      );
      expect(
        (await h.entries.locationById(misfiled.id))!.lifecycle,
        LocationLifecycle.active.name,
        reason: 'refiling is not a lifecycle change',
      );
    });

    screenTest('Update this source is refused when the address belongs to '
        'another collection', (tester) async {
      await seed();
      final root = await h.root();
      final other = await h.collection('Another Work', folderId: root.id);
      await h.source(other.id, host: kHost, pathKey: kNewPath);

      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedUpdate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 1);
      expect(rows.single.lifecycle, SourceLifecycle.active.name);
      expect(rows.single.pathKey, kOldPath);
    });

    // --- add as another source ---------------------------------------------

    screenTest('Add as another source keeps both, and leaves the old one '
        'active', (tester) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedAddSource')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 2);
      expect(
        rows.every((s) => s.lifecycle == SourceLifecycle.active.name),
        isTrue,
      );
      expect(rows.map((s) => s.pathKey), containsAll([kOldPath, kNewPath]));
      expect(
        rows.firstWhere((s) => s.id == source.id).resolvedIntoSourceId,
        isNull,
        reason: 'nothing was pointed anywhere',
      );
    });

    screenTest('Add as another source is refused when the address belongs to '
        'another collection', (tester) async {
      await seed();
      final root = await h.root();
      final other = await h.collection('Another Work', folderId: root.id);
      await h.source(other.id, host: kHost, pathKey: kNewPath);

      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedAddSource')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect((await h.collections.sourcesOf(collectionId)).length, 1);
      expect((await h.collections.sourcesOf(other.id)).length, 1);
    });

    // --- it's different content --------------------------------------------

    screenTest('It\'s different content opens the address and writes nothing', (
      tester,
    ) async {
      await seed();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sourceMovedDifferent')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(h.opened, ['https://$kHost$kNewPath']);
      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 1);
      expect(rows.single.pathKey, kOldPath);
      expect(rows.single.lifecycle, SourceLifecycle.active.name);
    });
  });
}
