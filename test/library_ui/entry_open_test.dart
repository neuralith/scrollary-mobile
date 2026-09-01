/// What a tap on an Entry row does (V2-D71).
///
/// The behaviour this file exists to pin: **a tap opens the Entry**. It used
/// to open the actions menu from both of the row's controls, which meant the
/// most ordinary thing a person can want from a reading list — read this one —
/// was two taps behind a sheet whose other rows delete things.
///
/// So the negative assertion is as load-bearing as the positive ones: a plain
/// tap must never put the Entry menu on screen, and the three-dot control must
/// still be the thing that does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/shelf_screen.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> tapRow(WidgetTester tester, String entryId) =>
      tapAndPump(tester, key('entryRow-$entryId'));

  group('a tap opens the entry', () {
    screenTest('a downloaded entry opens the copy on this device', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'The first one',
        ordinal: 1,
      );
      await h.copyFor(entry.id);
      await h.location(
        entry.id,
        'https://alpha.example/serial/1',
        sourceId: source.id,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapRow(tester, entry.id);

      expect(h.readEntries, [entry.id]);
      expect(
        h.opened,
        isEmpty,
        reason: 'the bytes are here, so the website is not what was meant',
      );
    });

    screenTest('an entry this device does not hold opens at its website', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'The second one',
        ordinal: 2,
      );
      await h.location(
        entry.id,
        'https://alpha.example/serial/2',
        sourceId: source.id,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapRow(tester, entry.id);

      expect(h.opened, ['https://alpha.example/serial/2']);
      expect(h.readEntries, isEmpty);
      expect(
        key('entrySourcePicker'),
        findsNothing,
        reason: 'one place to read it is not a question',
      );
    });

    screenTest('opening at a website records that it was opened, never that '
        'it was finished', (tester) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'The second one',
        ordinal: 2,
      );
      await h.location(
        entry.id,
        'https://alpha.example/serial/2',
        sourceId: source.id,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapRow(tester, entry.id);

      final state = await h.reading.stateOf(entry.id);
      expect(state.firstOpenedAt, isNotNull);
      expect(state.status, ReadStatus.reading);
      expect(
        state.completedAt,
        isNull,
        reason: 'position is not measured on a website (I16)',
      );
    });

    screenTest('an entry with no address recorded says so and opens nothing', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'Nowhere in particular',
        ordinal: 1,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapRow(tester, entry.id);

      expect(h.opened, isEmpty);
      expect(h.readEntries, isEmpty);
      expect(find.text('No address is recorded for this entry.'), findsWidgets);
    });

    screenTest('a standalone entry on the shelf opens the same way', (
      tester,
    ) async {
      final root = await h.root();
      final entry = await h.standaloneEntry(
        folderId: root.id,
        title: 'On its own',
      );
      await h.location(entry.id, 'https://alpha.example/loose');

      await tester.pumpWidget(h.app(const ShelfScreen()));
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapRow(tester, entry.id);

      expect(h.opened, ['https://alpha.example/loose']);
      expect(key('entryRemove'), findsNothing);
    });
  });

  group('when the entry is published in more than one place', () {
    /// One Entry, listed on both of its Collection's sites.
    Future<({String collectionId, String entryId, String alpha, String beta})>
    seedTwoSources() async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final alpha = await h.source(
        collection.id,
        host: 'alpha.example',
        pathKey: 'serial-alpha',
      );
      final beta = await h.source(
        collection.id,
        host: 'beta.example',
        pathKey: 'serial-beta',
      );
      final entry = await h.entryIn(
        collection.id,
        title: 'The first one',
        ordinal: 1,
      );
      await h.location(
        entry.id,
        'https://alpha.example/serial/1',
        sourceId: alpha.id,
      );
      await h.location(
        entry.id,
        'https://beta.example/serial/1',
        sourceId: beta.id,
      );
      return (
        collectionId: collection.id,
        entryId: entry.id,
        alpha: alpha.id,
        beta: beta.id,
      );
    }

    screenTest('with no preferred source it asks which site to open', (
      tester,
    ) async {
      final s = await seedTwoSources();

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: s.collectionId)),
      );
      await pumpUntil(tester, key('entryRow-${s.entryId}'));
      await tapRow(tester, s.entryId);

      expect(key('entrySourcePicker'), findsOneWidget);
      expect(
        h.opened,
        isEmpty,
        reason: 'nothing is opened until the question is answered',
      );

      await tapAndPump(
        tester,
        key('entrySourceOption-https://beta.example/serial/1'),
      );
      expect(h.opened, ['https://beta.example/serial/1']);
    });

    screenTest('the collection’s preferred source is the answer, unasked', (
      tester,
    ) async {
      final s = await seedTwoSources();
      expect(
        await h.collections.setPreferredSource(s.collectionId, s.beta),
        isNull,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: s.collectionId)),
      );
      await pumpUntil(tester, key('entryRow-${s.entryId}'));
      await tapRow(tester, s.entryId);

      expect(key('entrySourcePicker'), findsNothing);
      expect(h.opened, ['https://beta.example/serial/1']);
    });

    screenTest('a downloaded copy still wins over any of them', (tester) async {
      final s = await seedTwoSources();
      await h.copyFor(s.entryId);

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: s.collectionId)),
      );
      await pumpUntil(tester, key('entryRow-${s.entryId}'));
      await tapRow(tester, s.entryId);

      expect(key('entrySourcePicker'), findsNothing);
      expect(h.readEntries, [s.entryId]);
      expect(h.opened, isEmpty);
    });
  });

  group('the menu is the three-dot control’s alone', () {
    Future<({String collectionId, String entryId})> seedOne() async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'The first one',
        ordinal: 1,
      );
      await h.copyFor(entry.id);
      await h.location(
        entry.id,
        'https://alpha.example/serial/1',
        sourceId: source.id,
      );
      return (collectionId: collection.id, entryId: entry.id);
    }

    screenTest('a plain tap never opens it', (tester) async {
      final s = await seedOne();

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: s.collectionId)),
      );
      await pumpUntil(tester, key('entryRow-${s.entryId}'));
      await tapRow(tester, s.entryId);

      for (final action in const [
        'entryRead',
        'entryDetails',
        'entryOpenAtSource',
        'entryDownload',
        'entryRemoveCopy',
        'entryRemove',
      ]) {
        expect(key(action), findsNothing, reason: '$action is not a tap away');
      }
    });

    screenTest('the three-dot control still opens it, whole', (tester) async {
      final s = await seedOne();

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: s.collectionId)),
      );
      await pumpUntil(tester, key('entryRow-${s.entryId}'));
      await tapAndPump(tester, key('entryMenu-${s.entryId}'));

      for (final action in const [
        'entryRead',
        'entryDetails',
        'entryOpenAtSource',
        'entryDownload',
        'entryRemoveCopy',
        'entryRemove',
      ]) {
        expect(key(action), findsOneWidget, reason: '$action is in the menu');
      }
      expect(
        h.readEntries,
        isEmpty,
        reason: 'opening the menu is not opening the entry',
      );
    });

    screenTest('*Open at source* asks the same question the row would', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final alpha = await h.source(
        collection.id,
        host: 'alpha.example',
        pathKey: 'serial-alpha',
      );
      final beta = await h.source(
        collection.id,
        host: 'beta.example',
        pathKey: 'serial-beta',
      );
      final entry = await h.entryIn(
        collection.id,
        title: 'The first one',
        ordinal: 1,
      );
      await h.location(
        entry.id,
        'https://alpha.example/serial/1',
        sourceId: alpha.id,
      );
      await h.location(
        entry.id,
        'https://beta.example/serial/1',
        sourceId: beta.id,
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, key('entryRow-${entry.id}'));
      await tapAndPump(tester, key('entryMenu-${entry.id}'));
      await tapAndPump(tester, key('entryOpenAtSource'));

      expect(key('entrySourcePicker'), findsOneWidget);
      await tapAndPump(
        tester,
        key('entrySourceOption-https://alpha.example/serial/1'),
      );
      expect(h.opened, ['https://alpha.example/serial/1']);
    });
  });
}
