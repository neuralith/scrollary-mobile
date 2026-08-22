/// Placing an unplaced Entry (D6).
///
/// Every assertion here is about a refusal being *visible* and a position never
/// being invented. The two refusals — the one this device already knows about
/// and the one that comes back from the transport — name the Entry holding the
/// position and leave the row exactly as it was. Nothing anywhere in this flow
/// moves a placement to the next free number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/placement_models.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// A Collection with two placed Entries and one whose position nobody could
  /// establish.
  Future<({CollectionRow collection, EntryRow first, EntryRow unplaced})>
  seed() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final first = await h.entryIn(
      collection.id,
      title: 'The first one',
      ordinal: 1,
    );
    await h.entryIn(collection.id, title: 'The second one', ordinal: 2);
    final unplaced = await h.entryIn(
      collection.id,
      title: 'A stray one',
      placement: Placement.unplaced,
    );
    return (collection: collection, first: first, unplaced: unplaced);
  }

  Future<void> openScreen(WidgetTester tester, String collectionId) async {
    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: collectionId)),
    );
    await pumpUntil(tester, find.text('NEEDS PLACEMENT · 1'));
  }

  Future<void> openPlacement(WidgetTester tester, String entryId) async {
    await tapAndPump(tester, find.byKey(ValueKey('placeEntry-$entryId')));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('placementOrdinalField')),
    );
  }

  Future<void> typePosition(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('placementOrdinalField')),
      text,
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  ButtonStyleButton placeButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('confirmPlacement')),
      );

  screenTest('the affordance is on the unplaced row and on no other', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);

    expect(find.text('Set position'), findsOneWidget);
    expect(find.byKey(ValueKey('placeEntry-${s.unplaced.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('placeEntry-${s.first.id}')), findsNothing);
  });

  screenTest('a position this device knows is taken is named, and refused '
      'before anything is sent', (tester) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '1');
    await pumpUntil(tester, find.byKey(const ValueKey('placementDuplicate')));
    expect(
      find.textContaining(
        'Position 1 in this collection is already taken by “The first one”',
      ),
      findsOneWidget,
    );
    // Refused, with the reason printed directly above the control — never a
    // number quietly moved to the next free one.
    expect(placeButton(tester).onPressed, isNull);
    expect(h.placements, isEmpty);

    // A free position clears it again.
    await typePosition(tester, '3');
    await pumpUntilGone(
      tester,
      find.byKey(const ValueKey('placementDuplicate')),
    );
    expect(placeButton(tester).onPressed, isNotNull);
  });

  screenTest('a conflict from the transport names the entry holding the '
      'position, and writes nothing', (tester) async {
    final s = await seed();
    h.placement = (request) async {
      h.placements.add(request);
      return PlacementOutcome.conflict(
        ordinal: request.ordinal,
        occupyingEntryId: s.first.id,
      );
    };
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '5');
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(
      tester,
      find.textContaining(
        'Position 5 in this collection is already taken by “The first one”',
      ),
    );

    expect(h.placements.single.ordinal, 5);
    final row = (await h.entries.byId(s.unplaced.id))!;
    expect(row.placement, Placement.unplaced.name);
    expect(row.ordinal, isNull);
    expect(find.text('NEEDS PLACEMENT · 1'), findsOneWidget);
  });

  screenTest('a refusal is shown in the words it came back with', (
    tester,
  ) async {
    final s = await seed();
    h.placement = (request) async => const PlacementOutcome.refused(
      'That collection moved while you typed.',
    );
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '4');
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(
      tester,
      find.text('That collection moved while you typed.'),
    );

    final row = (await h.entries.byId(s.unplaced.id))!;
    expect(row.placement, Placement.unplaced.name);
    expect(row.ordinal, isNull);
  });

  screenTest('a placement the transport accepts is applied here, decimals '
      'included', (tester) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '7.5');
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(tester, find.text('Placed at 7.5.'));

    final row = (await h.entries.byId(s.unplaced.id))!;
    expect(row.ordinal, 7.5);
    // The user chose it, and the row records that rather than pretending the
    // app derived it.
    expect(row.placement, Placement.userPlaced.name);
    await pumpUntilGone(tester, find.text('NEEDS PLACEMENT · 1'));
    expect(find.text('Set position'), findsNothing);
  });

  screenTest('what is applied is what came back, not what was typed', (
    tester,
  ) async {
    final s = await seed();
    h.placement = (request) async {
      h.placements.add(request);
      return const PlacementOutcome.applied(9);
    };
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '3');
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(tester, find.text('Placed at 9.'));

    expect(h.placements.single.ordinal, 3);
    expect((await h.entries.byId(s.unplaced.id))!.ordinal, 9);
  });

  screenTest('a local write that loses the position refuses in the same '
      'words', (tester) async {
    final s = await seed();
    // Applied elsewhere, but the position was taken here in the meantime —
    // the schema refuses it (I8) and the user is told which entry has it.
    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);

    await typePosition(tester, '6');
    // Taken between the dialog opening and the answer coming back.
    await h.entries.placeEntry(s.first.id, 6);
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(
      tester,
      find.textContaining('is already taken by “The first one”'),
    );

    final row = (await h.entries.byId(s.unplaced.id))!;
    expect(row.placement, Placement.unplaced.name);
    expect(row.ordinal, isNull);
  });

  screenTest('with no service in the picture the position is an ordinary '
      'local write', (tester) async {
    // The default submitter, not the harness's recorder: this is the app a
    // user runs for a week with no backend, and placement is a local write
    // (V2-D7). Server arbitration exists for a contradiction between devices,
    // and with one device there is none.
    h.placement = localPlacementSubmit;
    final before = await h.outboxRows();
    final s = await seed();
    final seeded = (await h.outboxRows()) - before;

    await openScreen(tester, s.collection.id);
    await openPlacement(tester, s.unplaced.id);
    await typePosition(tester, '3');
    await tapAndPump(tester, find.byKey(const ValueKey('confirmPlacement')));
    await pumpUntil(tester, find.text('Placed at 3.'));

    final row = (await h.entries.byId(s.unplaced.id))!;
    expect(row.ordinal, 3);
    expect(
      row.placement,
      Placement.userPlaced.name,
      reason: 'the user chose this position, and the row records that',
    );
    expect(
      (await h.outboxRows()) - before - seeded,
      1,
      reason:
          'one write, one intent — waiting in the journal for a service that '
          'may never arrive',
    );
  });
}
