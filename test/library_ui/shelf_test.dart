/// The Library shelf (D1): what is on it, what it says when it is empty, and
/// how it moves between Folders.
///
/// The property this file guards hardest: **an item is on the shelf because it
/// is in the library**. Nothing here is downloaded, and everything renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/shelf_screen.dart';
import 'package:web_reader/ui/status_style.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  screenTest('shows folders, collections and standalone entries', (
    tester,
  ) async {
    final root = await h.root();
    await h.folder('Weekly', parentId: root.id);
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    await h.entryIn(collection.id, title: 'The first one', ordinal: 1);
    await h.entryIn(collection.id, title: 'The second one', ordinal: 2);
    final third = await h.entryIn(
      collection.id,
      title: 'The third one',
      ordinal: 3,
    );
    await h.reading.markRead(third.id);
    await h.standaloneEntry(folderId: root.id, title: 'A one-off piece');

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Serial Alpha'));

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('FOLDERS · 1'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('COLLECTIONS · 1'), findsOneWidget);
    // The reading signal: what is in the library, and how much is unread.
    // Not what has been downloaded — nothing here has.
    expect(find.text('3 items · 2 unread'), findsOneWidget);
    expect(find.text('ITEMS · 1'), findsOneWidget);
    expect(find.text('A one-off piece'), findsOneWidget);
  });

  screenTest('a collection with nothing downloaded is an ordinary row', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    await h.entryIn(collection.id, title: 'The only one', ordinal: 1);
    await h.standaloneEntry(folderId: root.id, title: 'A one-off piece');

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Serial Alpha'));

    expect(find.text('1 item · 1 unread'), findsOneWidget);
    expect(find.text('A one-off piece'), findsOneWidget);
    // Availability is a row state and this row has none of it.
    expect(find.text('On this device'), findsNothing);
  });

  screenTest('a brand-new library says so honestly', (tester) async {
    await h.root();

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Your library is empty'));

    expect(find.textContaining('not because this device'), findsOneWidget);
  });

  screenTest('tapping a folder navigates into it, scoped to that folder', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);
    await h.collection('Root Work', folderId: root.id);
    await h.collection('Inside Work', folderId: weekly.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Root Work'));

    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${weekly.id}')));
    await pumpUntil(tester, find.text('Inside Work'));

    expect(find.text('Weekly'), findsOneWidget); // now the title
    expect(find.text('Root Work'), findsNothing);
  });

  screenTest('an empty folder says it is empty, not that the library is', (
    tester,
  ) async {
    final root = await h.root();
    final empty = await h.folder('Reference', parentId: root.id);
    await h.collection('Root Work', folderId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Root Work'));
    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${empty.id}')));
    await pumpUntil(tester, find.text('This folder is empty'));

    expect(find.text('Your library is empty'), findsNothing);
  });

  screenTest('nesting is navigable to any depth, one shelf per level', (
    tester,
  ) async {
    final root = await h.root();
    final a = await h.folder('Weekly', parentId: root.id);
    final b = await h.folder('Monday', parentId: a.id);
    final c = await h.folder('Morning', parentId: b.id);
    await h.collection('Deep Work', folderId: c.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Weekly'));

    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${a.id}')));
    await pumpUntil(tester, find.byKey(ValueKey('folderRow-${b.id}')));
    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${b.id}')));
    await pumpUntil(tester, find.byKey(ValueKey('folderRow-${c.id}')));
    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${c.id}')));
    await pumpUntil(tester, find.text('Deep Work'));

    expect(find.text('Morning'), findsOneWidget); // the title, at depth three
    // No tree widget anywhere: each level is its own shelf, and the way back
    // is the route stack.
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  screenTest('header actions are HeaderIconButtons at the header size', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Weekly'));

    // Root: new folder only. Renaming, moving and deleting the root are not
    // offered at all, so the control that would carry them is absent.
    expect(find.byTooltip('New folder'), findsOneWidget);
    expect(find.byTooltip('Folder actions'), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);

    for (final element in find.byType(HeaderIconButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)),
        const Size(kHeaderActionSize, kHeaderActionSize),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.size, kHeaderIconSize);
    }

    await tapAndPump(tester, find.byKey(ValueKey('folderRow-${weekly.id}')));
    await pumpUntil(tester, find.byTooltip('Folder actions'));
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}
