/// The Library as the home screen: Collections at the root listed directly,
/// Folders as collapsible sections on the same page, Continue Reading above
/// it all, and the app-level doors — Settings and Activity — in the header.
///
/// The property this file guards: **a Folder organises the library without
/// hiding it.** Nothing disappears from the page because a Folder exists,
/// and nothing has to be entered to be browsed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/library_ui/shelf_screen.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  Finder section(String folderId) =>
      find.byKey(ValueKey('folderSection-$folderId'));

  screenTest('ungrouped collections are listed at the library level', (
    tester,
  ) async {
    final root = await h.root();
    await h.collection('Alpha', folderId: root.id);
    await h.collection('Beta', folderId: root.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Beta'));

    expect(find.text('MY LIBRARY · 2'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  screenTest('collections do not disappear because folders exist', (
    tester,
  ) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);
    final novels = await h.folder('Novels', parentId: root.id);
    await h.collection('Alpha', folderId: root.id);
    final gamma = await h.collection('Gamma', folderId: weekly.id);
    await h.collection('Delta', folderId: weekly.id);
    await h.collection('Epsilon', folderId: novels.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Epsilon'));

    // Every Collection is on the page, and each under its own Folder.
    for (final name in ['Alpha', 'Gamma', 'Delta', 'Epsilon']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('MY LIBRARY · 4'), findsOneWidget);
    // Each filed Collection sits below its own Folder's header and above the
    // next header down the page, whichever order the Folders sort in.
    final tops = {
      weekly.id: tester.getTopLeft(section(weekly.id)).dy,
      novels.id: tester.getTopLeft(section(novels.id)).dy,
    };
    void under(String name, String folderId) {
      final y = tester.getTopLeft(find.text(name)).dy;
      expect(y, greaterThan(tops[folderId]!), reason: name);
      for (final other in tops.entries) {
        if (other.key != folderId && other.value > tops[folderId]!) {
          expect(y, lessThan(other.value), reason: name);
        }
      }
    }

    under('Gamma', weekly.id);
    under('Delta', weekly.id);
    under('Epsilon', novels.id);
    // The root Collection stands above every section.
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tops.values.reduce((a, b) => a < b ? a : b)),
    );
    // Nothing about the data changed to draw it this way.
    expect((await h.collections.byId(gamma.id))!.folderId, weekly.id);
  });

  screenTest('a folder collapses and expands in place', (tester) async {
    final root = await h.root();
    final weekly = await h.folder('Weekly', parentId: root.id);
    await h.collection('Alpha', folderId: root.id);
    await h.collection('Gamma', folderId: weekly.id);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Gamma'));

    // Open by default: a Folder shows what it holds without being asked.
    expect(
      find.byKey(ValueKey('folderChevron-${weekly.id}-expanded')),
      findsOneWidget,
    );

    await tapAndPump(tester, section(weekly.id));
    expect(find.text('Gamma'), findsNothing);
    expect(find.text('Weekly'), findsOneWidget); // the header stays
    expect(find.text('1 collection'), findsOneWidget); // and says what it hides
    expect(find.text('Alpha'), findsOneWidget); // the rest of the page too
    expect(
      find.byKey(ValueKey('folderChevron-${weekly.id}-collapsed')),
      findsOneWidget,
    );

    await tapAndPump(tester, section(weekly.id));
    await pumpUntil(tester, find.text('Gamma'));
  });

  screenTest('continue reading sits above the library and says when it is '
      'empty', (tester) async {
    final root = await h.root();
    final collection = await h.collection('Alpha', folderId: root.id);
    final source = await h.source(collection.id);
    final entry = await h.entryIn(collection.id, title: 'One', ordinal: 1);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Alpha'));
    expect(find.byKey(const ValueKey('continueReadingEmpty')), findsOneWidget);
    expect(find.text('CONTINUE READING'), findsNothing);

    // A reading, not merely an open: the strip is derived from where a reading
    // got to, so an access on its own leaves the hint standing.
    await h.openedAt(entry.id, DateTime.utc(2026, 8, 1));
    await pumpUntil(tester, find.byKey(const ValueKey('continueReadingEmpty')));
    expect(find.text('CONTINUE READING'), findsNothing);

    await h.readAtSource(
      entry.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 8, 1),
    );
    await pumpUntil(tester, find.byKey(ValueKey('continueRead-${entry.id}')));

    expect(find.byKey(const ValueKey('continueReadingEmpty')), findsNothing);
    expect(
      tester.getTopLeft(find.text('CONTINUE READING')).dy,
      lessThan(tester.getTopLeft(find.text('MY LIBRARY · 1')).dy),
    );
  });

  screenTest('an empty library has no continue-reading hint, only its own '
      'empty state', (tester) async {
    await h.root();
    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Your library is empty'));
    expect(find.byKey(const ValueKey('continueReadingEmpty')), findsNothing);
  });

  screenTest('the activity door marks an outstanding queue', (tester) async {
    final root = await h.root();
    final collection = await h.collection('Alpha', folderId: root.id);
    final entry = await h.entryIn(collection.id, title: 'One', ordinal: 1);

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Alpha'));
    expect(find.byTooltip('Activity'), findsOneWidget);
    expect(find.byKey(const ValueKey('activityDot')), findsNothing);

    await h.queue.enqueue(
      entryId: entry.id,
      locationUrl: 'https://example.com/one',
    );
    await pumpUntil(tester, find.byKey(const ValueKey('activityDot')));
  });

  screenTest('settings and activity open their routes', (tester) async {
    await h.root();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ShelfScreen()),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('settings route')),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Scaffold(body: Text('activity route')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryUiServicesProvider.overrideWithValue(h.services)],
        child: MaterialApp.router(
          theme: appTheme(palette: AppPalette.light),
          routerConfig: router,
        ),
      ),
    );
    await pumpUntil(tester, find.text('Your library is empty'));

    await tapAndPump(
      tester,
      find.byKey(const ValueKey('libraryAction-settings')),
    );
    await pumpUntil(tester, find.text('settings route'));
    router.pop();
    await pumpUntil(tester, find.byTooltip('Activity'));

    await tapAndPump(
      tester,
      find.byKey(const ValueKey('libraryAction-activity')),
    );
    await pumpUntil(tester, find.text('activity route'));
  });
}
