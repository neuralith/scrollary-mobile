/// Continue Reading, over the logical Entries (D3).
///
/// The property the whole strip exists for: **it is derived from reading
/// state, never from downloads.** An Entry someone is partway through belongs
/// here whether or not this device is holding a single byte of it — an Entry
/// is in the library because the user wants to read it, not because its
/// content has been downloaded.
///
/// The rest is V1's `continue reading` group carried across the model change:
/// most-recently-read first, only what is actually being read, bounded rather
/// than a second library screen, an honest name for an Entry that has none,
/// and a strip that takes no space at all when there is nothing to resume.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/library_ui/continue_reading_strip.dart';
import 'package:web_reader/library_ui/providers.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  /// Every Entry id the injected opener was handed, in order.
  final opened = <String>[];

  setUp(() {
    h = UiHarness();
    opened.clear();
  });
  tearDown(() => h.close());

  /// The strip on its own, with a reader attached.
  ///
  /// A nested scope rather than a second harness: the strip's data comes from
  /// the harness's services in the outer scope, and only the seam this test
  /// owns — where a tap goes — is overridden here.
  Future<void> openStrip(WidgetTester tester) => tester.pumpWidget(
    h.app(
      ProviderScope(
        overrides: [
          entryOpenerProvider.overrideWithValue((id) async => opened.add(id)),
        ],
        child: const Scaffold(body: ContinueReadingStrip()),
      ),
    ),
  );

  /// What the provider actually resolved to, read from the live tree. Used
  /// where the answer is a *count* — a horizontal strip only builds the cards
  /// it can show, so counting rendered chips would measure the viewport.
  List<ContinueReadItem> stripItems(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ContinueReadingStrip)),
      ).read(continueReadingProvider).value ??
      const [];

  Finder card(String entryId) => find.byKey(ValueKey('continueRead-$entryId'));

  Future<CollectionRow> shelf(String name) async =>
      h.collection(name, folderId: (await h.root()).id);

  /// Someone opened this Entry at [at]: unread → reading, last-read stamped.
  Future<void> openedAt(String entryId, DateTime at) async {
    final (state, violation) = await h.reading.recordSourceAccess(
      entryId,
      at: at,
    );
    expect(violation, isNull, reason: 'seeding a read must not be refused');
    expect(state, isNotNull);
  }

  screenTest('an entry being read appears with nothing downloaded for it', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final entry = await h.entryIn(
      collection.id,
      title: 'The second one',
      ordinal: 2,
    );
    await openedAt(entry.id, DateTime.utc(2026, 7, 20));

    await openStrip(tester);
    await pumpUntil(tester, card(entry.id));

    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('The second one'), findsOneWidget);
    // The point of the test: this device holds nothing for it, and the strip
    // is about reading rather than about bytes.
    expect(await h.offlineCopyRows(entry.id), 0);
    expect(h.bytesOnDisk(entry.id), isFalse);
  });

  screenTest('the strip is ordered most recently read first', (tester) async {
    final collection = await shelf('Serial Alpha');
    final older = await h.entryIn(collection.id, title: 'Older', ordinal: 1);
    final newer = await h.entryIn(collection.id, title: 'Newer', ordinal: 2);
    // Explicit timestamps rather than a wait: a widget test's clock is fake,
    // so wall-time ordering would never arrive.
    await openedAt(older.id, DateTime.utc(2026, 7, 20));
    await openedAt(newer.id, DateTime.utc(2026, 7, 25));

    await openStrip(tester);
    await pumpUntil(tester, card(newer.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [newer.id, older.id],
    );
    expect(
      tester.getTopLeft(card(newer.id)).dx,
      lessThan(tester.getTopLeft(card(older.id)).dx),
    );
  });

  screenTest('only an entry being read appears, never an unread or a '
      'finished one', (tester) async {
    final collection = await shelf('Serial Alpha');
    final resuming = await h.entryIn(
      collection.id,
      title: 'Resuming',
      ordinal: 1,
    );
    final untouched = await h.entryIn(
      collection.id,
      title: 'Untouched',
      ordinal: 2,
    );
    final finished = await h.entryIn(
      collection.id,
      title: 'Finished',
      ordinal: 3,
    );
    final putBack = await h.entryIn(
      collection.id,
      title: 'Put back',
      ordinal: 4,
    );
    await openedAt(resuming.id, DateTime.utc(2026, 7, 20));
    await h.reading.markRead(finished.id, at: DateTime.utc(2026, 7, 21));
    // Read and then deliberately lowered: it keeps its last-read stamp, and
    // the strip must go by status rather than by the stamp alone.
    await h.reading.markRead(putBack.id, at: DateTime.utc(2026, 7, 22));
    await h.reading.markUnread(putBack.id, at: DateTime.utc(2026, 7, 23));

    await openStrip(tester);
    await pumpUntil(tester, card(resuming.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [resuming.id],
    );
    expect(card(untouched.id), findsNothing);
    expect(card(finished.id), findsNothing);
    expect(card(putBack.id), findsNothing);
  });

  screenTest('the strip is bounded rather than a second library screen', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final ids = <String>[];
    for (var n = 1; n <= 11; n++) {
      final entry = await h.entryIn(
        collection.id,
        title: 'Part $n',
        ordinal: n.toDouble(),
      );
      ids.add(entry.id);
      await openedAt(entry.id, DateTime.utc(2026, 7, n));
    }

    await openStrip(tester);
    await pumpUntil(tester, card(ids.last));

    final items = stripItems(tester);
    expect(items.length, 8, reason: 'a strip, not a screen');
    // The eight most recently read, newest first — the bound drops the oldest
    // rather than an arbitrary eight.
    expect([
      for (final item in items) item.entryId,
    ], ids.reversed.take(8).toList());
  });

  screenTest('an entry in a collection names it, a standalone one does not', (
    tester,
  ) async {
    final root = await h.root();
    final collection = await shelf('Serial Alpha');
    final inside = await h.entryIn(collection.id, title: 'Inside', ordinal: 1);
    final alone = await h.standaloneEntry(folderId: root.id, title: 'Alone');
    await openedAt(alone.id, DateTime.utc(2026, 7, 20));
    await openedAt(inside.id, DateTime.utc(2026, 7, 25));

    await openStrip(tester);
    await pumpUntil(tester, card(inside.id));
    await pumpUntil(tester, card(alone.id));

    expect(
      find.descendant(of: card(inside.id), matching: find.text('Serial Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card(inside.id), matching: find.byType(Text)),
      findsNWidgets(2),
    );
    // A standalone Entry belongs to no Collection, so the card says nothing
    // about one rather than inventing a home for it.
    expect(
      find.descendant(of: card(alone.id), matching: find.byType(Text)),
      findsOneWidget,
    );
    expect(find.text('Alone'), findsOneWidget);
  });

  screenTest('an entry with no title of its own is still named', (
    tester,
  ) async {
    final root = await h.root();
    final blank = await h.standaloneEntry(folderId: root.id, title: '   ');
    await openedAt(blank.id, DateTime.utc(2026, 7, 20));

    await openStrip(tester);
    await pumpUntil(tester, card(blank.id));

    final labels = [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: card(blank.id), matching: find.byType(Text)),
      ))
        text.data,
    ];
    expect(labels, [
      'Item',
    ], reason: 'a card with no words on it is not a card');
    expect(stripItems(tester).single.title, 'Item');
  });

  screenTest('tapping a card opens that entry', (tester) async {
    final collection = await shelf('Serial Alpha');
    final other = await h.entryIn(collection.id, title: 'Other', ordinal: 1);
    final wanted = await h.entryIn(collection.id, title: 'Wanted', ordinal: 2);
    await openedAt(other.id, DateTime.utc(2026, 7, 20));
    await openedAt(wanted.id, DateTime.utc(2026, 7, 25));

    await openStrip(tester);
    await pumpUntil(tester, card(wanted.id));
    await tapAndPump(tester, card(wanted.id));

    expect(opened, [wanted.id]);
  });

  screenTest('nothing to continue takes no space at all', (tester) async {
    final collection = await shelf('Serial Alpha');
    // In the library, and never opened: there is nothing to resume.
    await h.entryIn(collection.id, title: 'Never opened', ordinal: 1);

    await openStrip(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }

    expect(stripItems(tester), isEmpty);
    expect(find.text('CONTINUE READING'), findsNothing);
    expect(find.byKey(const ValueKey('continueReadingStrip')), findsNothing);
    expect(tester.getSize(find.byType(ContinueReadingStrip)), Size.zero);
  });

  screenTest('reading progress reaches the strip without a restart', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final first = await h.entryIn(collection.id, title: 'First', ordinal: 1);
    final second = await h.entryIn(collection.id, title: 'Second', ordinal: 2);

    await openStrip(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('CONTINUE READING'), findsNothing);

    // Same tree, nothing rebuilt by hand.
    await openedAt(first.id, DateTime.utc(2026, 7, 20));
    await pumpUntil(tester, card(first.id));
    expect([for (final item in stripItems(tester)) item.entryId], [first.id]);

    await openedAt(second.id, DateTime.utc(2026, 7, 25));
    await pumpUntil(tester, card(second.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [second.id, first.id],
    );
    expect(
      tester.getTopLeft(card(second.id)).dx,
      lessThan(tester.getTopLeft(card(first.id)).dx),
    );
  });
}
