/// Folder management (D2): create, rename, move — and the delete that moves
/// children up rather than destroying them.
///
/// The delete test is the one that matters. A confirmation that says "delete"
/// about a folder's contents would be a lie about what the repository does
/// (I5), and this file fails if the sentence or the outcome drifts apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/shelf_screen.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// Every Folder is a section on the one Library page, with its own menu.
  Future<void> openFolderMenu(WidgetTester tester, String folderId) async {
    await tapAndPump(tester, find.byKey(ValueKey('folderMenu-$folderId')));
  }

  screenTest('creating a folder names it and puts it in this folder', (
    tester,
  ) async {
    await h.root();

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Your library is empty'));

    // New folder sits beside the MY LIBRARY heading — one tap, no menu.
    await tapAndPump(tester, find.byTooltip('New folder'));
    await tester.enterText(
      find.byKey(const ValueKey('folderNameField')),
      'Reference',
    );
    await tapAndPump(tester, find.text('Create'));
    await pumpUntil(tester, find.text('Reference'));

    expect(find.text('MY LIBRARY · 0'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget); // the new section's own count
  });

  screenTest('renaming a folder changes what its section is called', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Weekly'));

    await openFolderMenu(tester, weekly.id);
    await tapAndPump(tester, find.text('Rename folder'));
    await tester.enterText(
      find.byKey(const ValueKey('folderNameField')),
      'Weekly reading',
    );
    await tapAndPump(tester, find.text('Rename'));
    await pumpUntil(tester, find.text('Weekly reading'));
  });

  screenTest('moving a folder puts it under the one that was picked', (
    tester,
  ) async {
    final root = await h.root();
    final moving = await h.folder('Weekly', parentId: root.id);
    final target = await h.folder('Reference', parentId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Weekly'));

    await openFolderMenu(tester, moving.id);
    await tapAndPump(tester, find.text('Move folder'));
    await pumpUntil(tester, find.byKey(ValueKey('folderOption-${target.id}')));
    await tapAndPump(tester, find.byKey(ValueKey('folderOption-${target.id}')));

    var moved = false;
    for (var i = 0; i < 20 && !moved; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      moved = (await h.folders.byId(moving.id))!.parentId == target.id;
    }
    expect(moved, isTrue, reason: 'the folder was never moved under the pick');
  });

  screenTest('a move that would make a folder contain itself is refused, '
      'in the repository\'s own words', (tester) async {
    final root = await h.root();
    final parent = await h.folder('Weekly', parentId: root.id);
    final child = await h.folder('Monday', parentId: parent.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Monday'));

    await openFolderMenu(tester, parent.id);
    await tapAndPump(tester, find.text('Move folder'));
    await pumpUntil(tester, find.byKey(ValueKey('folderOption-${child.id}')));
    await tapAndPump(tester, find.byKey(ValueKey('folderOption-${child.id}')));

    await pumpUntil(tester, find.textContaining('cannot be moved into itself'));
    // Refused, and nothing moved.
    expect((await h.folders.byId(parent.id))!.parentId, root.id);
  });

  screenTest('deleting a folder says its contents move up, and they do', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);
    await h.folder('Monday', parentId: weekly.id);
    final collection = await h.collection('Serial Alpha', folderId: weekly.id);
    final entry = await h.standaloneEntry(
      folderId: weekly.id,
      title: 'A one-off piece',
    );

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Serial Alpha'));

    await openFolderMenu(tester, weekly.id);
    await tapAndPump(tester, find.text('Delete folder'));

    // The confirmation states the reparent in the repository's own counts,
    // and never claims anything is deleted except the folder.
    expect(
      find.textContaining('1 folder, 1 collection and 1 item'),
      findsOneWidget,
    );
    expect(find.textContaining('moves up to Library'), findsOneWidget);
    expect(
      find.textContaining('Nothing in your library is deleted'),
      findsOneWidget,
    );

    await tapAndPump(tester, find.widgetWithText(TextButton, 'Delete folder'));
    await pumpUntil(tester, find.textContaining('moved to Library'));

    expect(await h.folders.byId(weekly.id), isNull);
    expect((await h.collections.byId(collection.id))!.folderId, root.id);
    expect((await h.entries.byId(entry.id))!.folderId, root.id);
  });

  screenTest('an empty folder is deleted without a sentence about contents', (
    tester,
  ) async {
    final root = await h.root();
    final empty = await h.folder('Reference', parentId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.byKey(ValueKey('folderEmpty-${empty.id}')));

    await openFolderMenu(tester, empty.id);
    await tapAndPump(tester, find.text('Delete folder'));
    expect(find.textContaining('This folder is empty'), findsWidgets);
    expect(find.textContaining('moves up to'), findsNothing);

    await tapAndPump(tester, find.widgetWithText(TextButton, 'Delete folder'));
    await pumpUntil(tester, find.text('Folder deleted.'));
    expect(await h.folders.byId(empty.id), isNull);
  });
}
