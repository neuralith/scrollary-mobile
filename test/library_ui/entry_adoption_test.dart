/// *Add to a collection…* on a standalone Entry.
///
/// A standalone Entry is a first-class library item, not a mistake waiting to
/// be corrected — so this action exists where it means something and nowhere
/// else, and it cannot create a Collection of one Entry (I3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/library_ui/collection_actions.dart';
import 'package:web_reader/library_ui/collection_models.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  Future<void> openMenu(WidgetTester tester, EntryRowView view) async {
    await tester.pumpWidget(
      h.app(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showEntryMenu(context, ref, view),
                child: const Text('open the menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tapAndPump(tester, find.text('open the menu'));
  }

  EntryRowView viewOf(EntryRow row) => EntryRowView.from(
    row: row,
    status: ReadStatus.unread,
    availableOffline: false,
  );

  screenTest('a standalone entry can be put into a collection', (tester) async {
    final root = await h.root();
    await h.collection('Alpha', folderId: root.id);
    final entry = await h.standaloneEntry(
      folderId: root.id,
      title: 'A loose one',
    );

    await openMenu(tester, viewOf(entry));

    expect(find.byKey(const ValueKey('entryAddToCollection')), findsOneWidget);
  });

  screenTest('an entry already in a collection is not offered it', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Alpha', folderId: root.id);
    final entry = await h.entryIn(
      collection.id,
      title: 'Alpha 12',
      ordinal: 12,
    );

    await openMenu(tester, viewOf(entry));

    await pumpUntil(tester, find.byKey(const ValueKey('entryDownload')));
    expect(
      find.byKey(const ValueKey('entryAddToCollection')),
      findsNothing,
      reason: 'there is nothing to adopt an entry that is already placed',
    );
  });

  screenTest('the picker it opens cannot create a collection of one', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Alpha', folderId: root.id);
    final entry = await h.standaloneEntry(
      folderId: root.id,
      title: 'A loose one',
    );

    await openMenu(tester, viewOf(entry));
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('entryAddToCollection')),
    );

    await pumpUntil(
      tester,
      find.byKey(ValueKey('collectionOption-${collection.id}')),
    );
    expect(
      find.byKey(const ValueKey('collectionPickerNew')),
      findsNothing,
      reason: 'adopting moves an entry into a collection that already exists',
    );
  });
}
