/// The Library shelf (D1): what is on it, what it says when it is empty, and
/// how Folders group it on the one page without hiding any of it.
///
/// The property this file guards hardest: **an item is on the shelf because it
/// is in the library**. Nothing here is downloaded, and everything renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/storage_screen.dart' show StoragePill;
import 'package:web_reader/library_ui/shelf_screen.dart';
import 'package:web_reader/ui/status_style.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  screenTest('an archived collection stays on the shelf, marked as archived', (
    tester,
  ) async {
    // Archived content remains discoverable — V2-D48. V1 had a separate
    // Archived screen; V2 has one Library page, so archiving marks a row
    // rather than moving it somewhere the user has to know about.
    final root = await h.root();
    final kept = await h.collection('Still reading', folderId: root.id);
    final done = await h.collection('Finished with', folderId: root.id);
    expect(await h.collections.archive(done.id), isNull);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Still reading'));

    expect(find.text('Still reading'), findsOneWidget);
    expect(
      find.text('Finished with'),
      findsOneWidget,
      reason: 'archiving is not hiding',
    );
    expect(find.text('Archived'), findsOneWidget);
    expect(
      find.byKey(ValueKey('collectionCheckChip-${kept.id}')),
      findsNothing,
      reason: 'a collection nobody has checked says nothing about checking',
    );
  });

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
    // One count for the library: what is in it, wherever it is filed.
    expect(find.text('MY LIBRARY · 2'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
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

  screenTest('a folder is a section on the same page, never a screen', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);
    await h.collection('Root Work', folderId: root.id);
    await h.collection('Inside Work', folderId: weekly.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Inside Work'));

    // Both Collections are on the page at once: the one at the root and the
    // one filed under Weekly, under Weekly's header.
    expect(find.text('Root Work'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('1 collection'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Library'), findsOneWidget);
    final header = tester.getTopLeft(
      find.byKey(ValueKey('folderSection-${weekly.id}')),
    );
    expect(
      tester.getTopLeft(find.text('Inside Work')).dy,
      greaterThan(header.dy),
    );
    // Filed, and drawn in from the edge to say so.
    expect(
      tester.getTopLeft(find.text('Inside Work')).dx,
      greaterThan(tester.getTopLeft(find.text('Root Work')).dx),
    );
  });

  screenTest('an empty folder says it is empty, not that the library is', (
    tester,
  ) async {
    final root = await h.root();
    final empty = await h.folder('Reference', parentId: root.id);
    await h.collection('Root Work', folderId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Root Work'));

    expect(find.byKey(ValueKey('folderEmpty-${empty.id}')), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
  });

  screenTest('nesting is drawn to any depth, one section inside another', (
    tester,
  ) async {
    final root = await h.root();
    final a = await h.folder('Weekly', parentId: root.id);
    final b = await h.folder('Monday', parentId: a.id);
    final c = await h.folder('Morning', parentId: b.id);
    await h.collection('Deep Work', folderId: c.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Deep Work'));

    // Every level is on the page, and no navigation happened to get there.
    for (final folder in [a, b, c]) {
      expect(
        find.byKey(ValueKey('folderSection-${folder.id}')),
        findsOneWidget,
      );
    }
    expect(find.byTooltip('Back'), findsNothing);
    // Each header counts everything beneath it.
    expect(find.text('1 collection'), findsNWidgets(3));
  });

  screenTest('header actions are HeaderIconButtons at the header size', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Weekly'));

    // The header is the app's doors and nothing else: no storage telemetry,
    // no overflow menu. Making a Folder sits beside the MY LIBRARY heading,
    // and the root is not the user's to rename, move or delete, so no folder
    // menu stands beside the title.
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Activity'), findsOneWidget);
    expect(find.byTooltip('Library actions'), findsNothing);
    expect(find.byKey(const ValueKey('libraryMenu')), findsNothing);
    expect(find.byType(StoragePill), findsNothing);
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

    // The Folder's own actions sit on its section; New folder on the heading,
    // below the app header and at a touch-target size.
    expect(find.byKey(ValueKey('folderMenu-${weekly.id}')), findsOneWidget);
    final newFolder = find.byTooltip('New folder');
    expect(newFolder, findsOneWidget);
    expect(
      tester.getTopLeft(newFolder).dy,
      greaterThan(tester.getBottomLeft(find.text('Library')).dy),
    );
    expect(tester.getSize(newFolder).shortestSide, greaterThanOrEqualTo(44));
  });
}
