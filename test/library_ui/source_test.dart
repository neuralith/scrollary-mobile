/// Source presentation and the preferred-source switch (D4).
///
/// The load-bearing assertions are the ones about the sites that are *gone*: a
/// dead Source is on the screen saying it is dead, and a moved one names where
/// it went. A section that quietly listed only the live sites would leave a
/// Collection whose history had been edited — and the whole point of a
/// Collection having Sources is that it outlives them (V2-D14).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/source_section.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// One Collection published in four states at once: a live site, one that
  /// has gone quiet, one that is gone, and one that moved to the live one.
  Future<
    ({
      CollectionRow collection,
      SourceRow active,
      SourceRow dormant,
      SourceRow dead,
      SourceRow moved,
    })
  >
  seed() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final active = await h.source(
      collection.id,
      host: 'reading.example.com',
      pathKey: 'serial-alpha',
    );
    final dormant = await h.source(
      collection.id,
      host: 'mirror.example.com',
      pathKey: 'serial-alpha',
      language: 'fr',
      lifecycle: SourceLifecycle.dormant,
    );
    final dead = await h.source(
      collection.id,
      host: 'gone.example.org',
      pathKey: 'serial-alpha',
      lifecycle: SourceLifecycle.dead,
    );
    final moved = await h.source(
      collection.id,
      host: 'old.example.test',
      pathKey: 'serial-alpha',
      lifecycle: SourceLifecycle.resolvedInto,
      resolvedIntoSourceId: active.id,
    );
    return (
      collection: collection,
      active: active,
      dormant: dormant,
      dead: dead,
      moved: moved,
    );
  }

  Future<void> openSource(WidgetTester tester, String sourceId) =>
      tapAndPump(tester, find.byKey(ValueKey('sourceRow-$sourceId')));

  screenTest('every source is listed, in the state it is actually in', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('SOURCES · 4'));

    expect(find.text('reading.example.com'), findsOneWidget);
    expect(find.text('mirror.example.com'), findsOneWidget);
    expect(find.text('gone.example.org'), findsOneWidget);
    expect(find.text('old.example.test'), findsOneWidget);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Dormant'), findsOneWidget);
    // Stated, not hidden.
    expect(find.text('Dead'), findsOneWidget);
    expect(
      find.textContaining('This site no longer carries this collection'),
      findsOneWidget,
    );
    // And a move names where it went.
    expect(find.text('Moved'), findsOneWidget);
    expect(
      find.textContaining('This site moved to reading.example.com'),
      findsOneWidget,
    );
    // Language is the tag that was recorded, never a name invented for it.
    expect(find.text('fr'), findsOneWidget);
  });

  screenTest('nothing in the section promises to check or fetch anything', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('SOURCES · 4'));

    for (final word in ['check', 'Check', 'fetch', 'Fetch', 'watch']) {
      expect(
        find.descendant(
          of: find.byType(CollectionSourcesSection),
          matching: find.textContaining(word),
        ),
        findsNothing,
        reason: 'the sources section must not promise $word',
      );
    }
  });

  screenTest('preferring a source round-trips, and clearing it does too', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('SOURCES · 4'));
    expect(find.text('Preferred'), findsNothing);

    await openSource(tester, s.active.id);
    await tapAndPump(tester, find.text('Prefer this source'));
    await pumpUntil(tester, find.text('Preferred'));
    expect(
      (await h.collections.byId(s.collection.id))!.preferredSourceId,
      s.active.id,
    );

    await openSource(tester, s.active.id);
    await tapAndPump(tester, find.text('Clear preferred source'));
    await pumpUntilGone(tester, find.text('Preferred'));
    expect(
      (await h.collections.byId(s.collection.id))!.preferredSourceId,
      isNull,
    );
  });

  screenTest('a site that cannot be read from is not offered as a preference', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('SOURCES · 4'));

    await openSource(tester, s.dead.id);
    // Absent, not disabled — and the sheet still says why it is gone.
    expect(find.text('Prefer this source'), findsNothing);
    expect(
      find.textContaining('This site no longer carries this collection'),
      findsWidgets,
    );
  });

  screenTest('a preference the repository refuses is said out loud', (
    tester,
  ) async {
    final s = await seed();

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: s.collection.id)),
    );
    await pumpUntil(tester, find.text('SOURCES · 4'));

    await openSource(tester, s.dormant.id);
    // The Source goes while the sheet is open — the shape of a removal that
    // happened on another device.
    expect(await h.collections.removeSource(s.dormant.id), isNull);
    await tapAndPump(tester, find.text('Prefer this source'));
    await pumpUntil(
      tester,
      find.textContaining('no longer one of this collection’s sources'),
    );

    expect(
      (await h.collections.byId(s.collection.id))!.preferredSourceId,
      isNull,
    );
  });

  screenTest('a collection with no sources shows no section at all', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await h.collection(
      'Assembled by hand',
      folderId: root.id,
    );
    await h.entryIn(collection.id, title: 'The first one', ordinal: 1);

    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: collection.id)),
    );
    await pumpUntil(tester, find.text('The first one'));

    expect(find.textContaining('SOURCES'), findsNothing);
  });
}
