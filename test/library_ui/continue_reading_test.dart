/// Continue Reading, over the logical Entries (D3).
///
/// Two properties the strip exists for, and they are separate.
///
/// **It is derived from reading state, never from downloads.** An Entry
/// someone is partway through belongs here whether or not this device is
/// holding a single byte of it — an Entry is in the library because the user
/// wants to read it, not because its content has been downloaded.
///
/// **It is derived from a reading, never from an access.** `reading_states`
/// stamps `last_read_at` for every completed navigation onto a recognised page
/// (I16, V2-D9), so browsing to the page a download is about to start from
/// looked exactly like finishing an Entry. What separates them is a
/// **position**: the one `SourceReadingMeter` writes when a person has moved
/// the page themselves, or the anchor this app's own reader leaves inside a
/// package. Downloading, capture, an update check and browsing past a page
/// write neither, so none of them can put a card here.
///
/// The rest is V1's `continue reading` group carried across the model change:
/// most-recently-read first, one card per work, bounded rather than a second
/// library screen, an honest name for an Entry that has none, and a strip that
/// takes no space at all when there is nothing to resume.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/library_ui/continue_reading_strip.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/reading_v2/source_reading.dart';
import 'package:web_reader/ui/status_style.dart';

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
  /// it can show, so counting rendered cards would measure the viewport.
  List<ContinueReadItem> stripItems(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ContinueReadingStrip)),
      ).read(continueReadingProvider).value ??
      const [];

  Finder card(String entryId) => find.byKey(ValueKey('continueRead-$entryId'));

  Future<CollectionRow> shelf(String name) async =>
      h.collection(name, folderId: (await h.root()).id);

  /// Pump long enough that a card would have appeared if one were coming.
  /// The absence of a card is only meaningful once the query has answered.
  Future<void> settleQuery(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  // ── what counts as a reading ───────────────────────────────────────────────

  screenTest('an entry being read appears with nothing downloaded for it', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final entry = await h.entryIn(
      collection.id,
      title: 'The second one',
      ordinal: 2,
    );
    await h.readAtSource(
      entry.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );

    await openStrip(tester);
    await pumpUntil(tester, card(entry.id));

    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('Serial Alpha'), findsOneWidget);
    // The point of the test: this device holds nothing for it, and the strip
    // is about reading rather than about bytes.
    expect(await h.offlineCopyRows(entry.id), 0);
    expect(h.bytesOnDisk(entry.id), isFalse);
  });

  screenTest('a page that was only opened is not a reading', (tester) async {
    final collection = await shelf('Serial Alpha');
    final browsed = await h.entryIn(collection.id, title: 'Passed', ordinal: 1);
    // Exactly what a completed navigation writes: unread lifted to reading and
    // a last-read stamp. No position, because nobody read anything.
    await h.openedAt(browsed.id, DateTime.utc(2026, 7, 20));

    await openStrip(tester);
    await settleQuery(tester);

    expect(stripItems(tester), isEmpty);
    expect(card(browsed.id), findsNothing);
  });

  screenTest('an entry that was downloaded but never read is not there', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final read = await h.entryIn(collection.id, title: 'Read', ordinal: 1);
    final downloaded = await h.entryIn(
      collection.id,
      title: 'Downloaded',
      ordinal: 2,
    );
    // The whole shape of a download: the user browsed onto the page — which
    // stamps an access — and the bytes arrived. Nobody read it.
    await h.openedAt(downloaded.id, DateTime.utc(2026, 7, 25));
    await h.copyFor(downloaded.id);
    await h.readAtSource(
      read.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );

    await openStrip(tester);
    await pumpUntil(tester, card(read.id));

    expect(h.bytesOnDisk(downloaded.id), isTrue, reason: 'it did download');
    expect([for (final item in stripItems(tester)) item.entryId], [read.id]);
    expect(card(downloaded.id), findsNothing);
  });

  screenTest('a reading in this app\'s own reader counts, and says no '
      'percentage it cannot measure', (tester) async {
    final collection = await shelf('Serial Alpha');
    final entry = await h.entryIn(collection.id, title: 'Offline', ordinal: 4);
    await h.copyFor(entry.id);
    await h.readInReader(entry.id, at: DateTime.utc(2026, 7, 20));

    await openStrip(tester);
    await pumpUntil(tester, card(entry.id));

    expect(stripItems(tester).single.entryId, entry.id);
    // An anchor indexes the bytes of one package; it is not a proportion of
    // anything, and no figure is invented from it.
    expect(stripItems(tester).single.progress, isNull);
    expect(
      find.descendant(of: card(entry.id), matching: find.textContaining('%')),
      findsNothing,
    );
  });

  screenTest('a scroll a download performed never reaches the strip, and the '
      'reader\'s own scroll does', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id, host: 'alpha.example');
    final entry = await h.entryIn(collection.id, title: 'Part 1', ordinal: 1);
    const url = 'https://alpha.example/works/serial-alpha/part-1';
    await h.location(entry.id, url, sourceId: source.id);
    // The access a completed navigation records, exactly as the app writes it.
    await h.openedAt(entry.id, DateTime.utc(2026, 7, 20));

    // The real meter over the real repository — the seam the strip's rule
    // rests on, rather than a hand-written row standing in for it.
    final meter = SourceReadingMeter(h.measurements);
    meter.watch(entryId: entry.id, sourceId: source.id, url: url);

    await openStrip(tester);
    await settleQuery(tester);
    expect(stripItems(tester), isEmpty, reason: 'opened, not read');

    // A capture takes the Browser and scrolls the page to the bottom to
    // enumerate it. That is the operation's position, not a person's.
    meter.noteAutomationScroll();
    await meter.record(
      const PageProbe(
        url: url,
        title: '',
        documentHeight: 4000,
        viewportHeight: 1000,
        scrollY: 3000,
      ),
    );
    await settleQuery(tester);

    expect(
      stripItems(tester),
      isEmpty,
      reason: 'downloading an Entry must never be what puts it here',
    );
    expect(card(entry.id), findsNothing);

    // The user scrolls it themselves. The seal lifts, a position is written,
    // and the same Entry becomes something to resume.
    meter.noteUserScroll();
    await meter.record(
      const PageProbe(
        url: url,
        title: '',
        documentHeight: 4000,
        viewportHeight: 1000,
        scrollY: 1000,
      ),
    );
    await pumpUntil(tester, card(entry.id));

    expect(stripItems(tester).single.entryId, entry.id);
    expect(stripItems(tester).single.progress, 0.5);
  });

  screenTest('only an entry being read appears, never an unread or a '
      'finished one', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
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
    await h.readAtSource(
      resuming.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.readAtSource(
      finished.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 21),
    );
    await h.reading.markRead(finished.id, at: DateTime.utc(2026, 7, 21));
    // Read and then deliberately lowered: it keeps its last-read stamp and its
    // position, and the strip must go by status rather than by either alone.
    await h.readAtSource(
      putBack.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 22),
    );
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

  // ── one card per work ──────────────────────────────────────────────────────

  screenTest('one collection shows the entry it was last read at, and reading '
      'on replaces it', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final first = await h.entryIn(collection.id, title: 'First', ordinal: 1);
    final second = await h.entryIn(collection.id, title: 'Second', ordinal: 2);
    final third = await h.entryIn(collection.id, title: 'Third', ordinal: 3);
    // Explicit timestamps rather than a wait: a widget test's clock is fake,
    // so wall-time ordering would never arrive.
    await h.readAtSource(
      first.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.readAtSource(
      second.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 21),
    );

    await openStrip(tester);
    await pumpUntil(tester, card(second.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [second.id],
      reason: 'a serial is one thing to resume, not one card per Entry',
    );
    expect(card(first.id), findsNothing);

    // Reading on inside the same work replaces the card rather than adding to
    // it — same tree, nothing rebuilt by hand.
    await h.readAtSource(
      third.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 22),
    );
    await pumpUntil(tester, card(third.id));

    expect([for (final item in stripItems(tester)) item.entryId], [third.id]);
    expect(card(second.id), findsNothing);
  });

  screenTest('a later browse of an older entry does not take the card from '
      'the one actually read most recently', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final browsedAgain = await h.entryIn(
      collection.id,
      title: 'Read long ago',
      ordinal: 1,
    );
    final actuallyRead = await h.entryIn(
      collection.id,
      title: 'Read most recently',
      ordinal: 2,
    );

    // Both were genuinely read, the second one later.
    await h.readAtSource(
      browsedAgain.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.readAtSource(
      actuallyRead.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 21),
    );

    // Then the reader passes back over the older one without reading it —
    // opening it to check a name, or landing on it on the way to a download.
    // That stamps `last_read_at` exactly as a reading would, and it is the
    // whole reason this strip cannot be ordered by that column.
    await h.openedAt(browsedAgain.id, DateTime.utc(2026, 7, 25));

    await openStrip(tester);
    await pumpUntil(tester, card(actuallyRead.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [actuallyRead.id],
      reason: 'revisiting a page is not reading it again',
    );
    expect(card(browsedAgain.id), findsNothing);
  });

  screenTest('a later browse does not outrank a later reading in this app\'s '
      'own reader either', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final browsedAgain = await h.entryIn(
      collection.id,
      title: 'Read at its site',
      ordinal: 1,
    );
    final readOffline = await h.entryIn(
      collection.id,
      title: 'Read on this device',
      ordinal: 2,
    );

    await h.readAtSource(
      browsedAgain.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.copyFor(readOffline.id);
    await h.readInReader(readOffline.id, at: DateTime.utc(2026, 7, 21));

    // The same revisit, against a reading whose position lives in a package on
    // this device rather than in a measurement.
    await h.openedAt(browsedAgain.id, DateTime.utc(2026, 7, 25));

    await openStrip(tester);
    await pumpUntil(tester, card(readOffline.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [readOffline.id],
    );
    expect(card(browsedAgain.id), findsNothing);
  });

  screenTest('a genuine reading after a browse takes the card, at a source '
      'and in the reader alike', (tester) async {
    final atSource = await shelf('Serial Alpha');
    final inReader = await shelf('Serial Beta');
    final source = await h.source(atSource.id, host: 'alpha.example');
    final browsedA = await h.entryIn(atSource.id, title: 'A one', ordinal: 1);
    final readA = await h.entryIn(atSource.id, title: 'A two', ordinal: 2);
    final browsedB = await h.entryIn(inReader.id, title: 'B one', ordinal: 1);
    final readB = await h.entryIn(inReader.id, title: 'B two', ordinal: 2);

    // In each Collection: one Entry read long ago and revisited since, and one
    // Entry genuinely read after that revisit.
    await h.readAtSource(
      browsedA.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.copyFor(browsedB.id);
    await h.readInReader(browsedB.id, at: DateTime.utc(2026, 7, 20));
    await h.openedAt(browsedA.id, DateTime.utc(2026, 7, 21));
    await h.openedAt(browsedB.id, DateTime.utc(2026, 7, 21));

    await h.readAtSource(
      readA.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 22),
    );
    await h.copyFor(readB.id);
    await h.readInReader(readB.id, at: DateTime.utc(2026, 7, 22));

    await openStrip(tester);
    await pumpUntil(tester, card(readA.id));
    await pumpUntil(tester, card(readB.id));

    expect([
      for (final item in stripItems(tester)) item.entryId,
    ], unorderedEquals([readA.id, readB.id]));
    expect(card(browsedA.id), findsNothing);
    expect(card(browsedB.id), findsNothing);
  });

  screenTest('each collection gets one card, most recently read first', (
    tester,
  ) async {
    final alpha = await shelf('Serial Alpha');
    final beta = await shelf('Serial Beta');
    final alphaSource = await h.source(alpha.id, host: 'alpha.example');
    final betaSource = await h.source(
      beta.id,
      host: 'beta.example',
      pathKey: 'serial-beta',
    );
    final alphaOld = await h.entryIn(alpha.id, title: 'A one', ordinal: 1);
    final alphaNew = await h.entryIn(alpha.id, title: 'A two', ordinal: 2);
    final betaOne = await h.entryIn(beta.id, title: 'B one', ordinal: 1);

    await h.readAtSource(
      alphaOld.id,
      sourceId: alphaSource.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.readAtSource(
      betaOne.id,
      sourceId: betaSource.id,
      at: DateTime.utc(2026, 7, 21),
    );
    await h.readAtSource(
      alphaNew.id,
      sourceId: alphaSource.id,
      at: DateTime.utc(2026, 7, 22),
    );

    await openStrip(tester);
    await pumpUntil(tester, card(alphaNew.id));
    await pumpUntil(tester, card(betaOne.id));

    expect(
      [for (final item in stripItems(tester)) item.entryId],
      [alphaNew.id, betaOne.id],
    );
    expect(card(alphaOld.id), findsNothing);
    expect(
      tester.getTopLeft(card(alphaNew.id)).dx,
      lessThan(tester.getTopLeft(card(betaOne.id)).dx),
    );
  });

  screenTest('the strip is bounded rather than a second library screen', (
    tester,
  ) async {
    final ids = <String>[];
    for (var n = 1; n <= 11; n++) {
      final collection = await shelf('Serial $n');
      final source = await h.source(
        collection.id,
        host: 'serial$n.example',
        pathKey: 'serial-$n',
      );
      final entry = await h.entryIn(collection.id, title: 'One', ordinal: 1);
      ids.add(entry.id);
      await h.readAtSource(
        entry.id,
        sourceId: source.id,
        at: DateTime.utc(2026, 7, n),
      );
    }

    await openStrip(tester);
    await pumpUntil(tester, card(ids.last));

    final items = stripItems(tester);
    expect(
      items.length,
      kContinueReadingLimit,
      reason: 'a strip, not a screen',
    );
    // The eight most recently read works, newest first — the bound drops the
    // oldest rather than an arbitrary eight.
    expect([
      for (final item in items) item.entryId,
    ], ids.reversed.take(kContinueReadingLimit).toList());
  });

  // ── what a card says ───────────────────────────────────────────────────────

  screenTest('a card names the work, the entry under it, and how far it got', (
    tester,
  ) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final entry = await h.entryIn(
      collection.id,
      title: 'Serial Alpha Part 12 — The Quiet Night',
      ordinal: 12,
    );
    await h.readAtSource(
      entry.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
      fraction: 0.42,
    );

    await openStrip(tester);
    await pumpUntil(tester, card(entry.id));

    // The work leads, because that is what a reader is coming back to.
    expect(
      find.descendant(of: card(entry.id), matching: find.text('Serial Alpha')),
      findsOneWidget,
    );
    // The Entry's own identity underneath: its position, and whatever its
    // stored title still says once the work and the number are taken out.
    expect(
      find.descendant(
        of: card(entry.id),
        matching: find.text('12 · The Quiet Night'),
      ),
      findsOneWidget,
    );
    // And the one number, beside them.
    expect(
      find.descendant(of: card(entry.id), matching: find.text('42%')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card(entry.id),
        matching: find.byType(EntryProgressRing),
      ),
      findsOneWidget,
    );
    final item = stripItems(tester).single;
    expect(item.title, 'Serial Alpha');
    expect(item.entryLabel, '12 · The Quiet Night');
    expect(item.progress, 0.42);
    expect(item.collectionId, collection.id);
  });

  screenTest('an entry whose title says nothing the position does not is just '
      'its position', (tester) async {
    final collection = await shelf('Serial Alpha');
    final source = await h.source(collection.id);
    final entry = await h.entryIn(
      collection.id,
      title: 'Serial Alpha Part 7',
      ordinal: 7,
    );
    await h.readAtSource(
      entry.id,
      sourceId: source.id,
      at: DateTime.utc(2026, 7, 20),
      fraction: 0.07,
    );

    await openStrip(tester);
    await pumpUntil(tester, card(entry.id));

    expect(stripItems(tester).single.entryLabel, '7');
    expect(
      find.descendant(of: card(entry.id), matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card(entry.id), matching: find.text('7%')),
      findsOneWidget,
    );
  });

  screenTest('a standalone entry names itself and claims no collection', (
    tester,
  ) async {
    final root = await h.root();
    final alone = await h.standaloneEntry(folderId: root.id, title: 'Alone');
    // A standalone Entry's Location belongs to no Source (I7), so the only
    // position it can have is the one this app's own reader leaves.
    await h.copyFor(alone.id);
    await h.readInReader(alone.id, at: DateTime.utc(2026, 7, 20));

    await openStrip(tester);
    await pumpUntil(tester, card(alone.id));

    final item = stripItems(tester).single;
    expect(item.title, 'Alone');
    expect(item.collectionId, isNull);
    expect(
      item.entryLabel,
      isNull,
      reason: 'there is no work above it for a position to be a position in',
    );
    expect(
      find.descendant(of: card(alone.id), matching: find.byType(Text)),
      findsOneWidget,
    );
  });

  screenTest('an entry with no title of its own is still named', (
    tester,
  ) async {
    final root = await h.root();
    final blank = await h.standaloneEntry(folderId: root.id, title: '   ');
    await h.copyFor(blank.id);
    await h.readInReader(blank.id, at: DateTime.utc(2026, 7, 20));

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

  // ── resuming ───────────────────────────────────────────────────────────────

  screenTest('tapping a card opens that entry', (tester) async {
    final alpha = await shelf('Serial Alpha');
    final beta = await shelf('Serial Beta');
    final alphaSource = await h.source(alpha.id, host: 'alpha.example');
    final betaSource = await h.source(
      beta.id,
      host: 'beta.example',
      pathKey: 'serial-beta',
    );
    final other = await h.entryIn(alpha.id, title: 'Other', ordinal: 1);
    final wanted = await h.entryIn(beta.id, title: 'Wanted', ordinal: 2);
    await h.readAtSource(
      other.id,
      sourceId: alphaSource.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await h.readAtSource(
      wanted.id,
      sourceId: betaSource.id,
      at: DateTime.utc(2026, 7, 25),
    );

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
    await settleQuery(tester);

    expect(stripItems(tester), isEmpty);
    expect(find.text('CONTINUE READING'), findsNothing);
    expect(find.byKey(const ValueKey('continueReadingStrip')), findsNothing);
    expect(tester.getSize(find.byType(ContinueReadingStrip)), Size.zero);
  });

  screenTest('a reading reaches the strip without a restart', (tester) async {
    final alpha = await shelf('Serial Alpha');
    final beta = await shelf('Serial Beta');
    final alphaSource = await h.source(alpha.id, host: 'alpha.example');
    final betaSource = await h.source(
      beta.id,
      host: 'beta.example',
      pathKey: 'serial-beta',
    );
    final first = await h.entryIn(alpha.id, title: 'First', ordinal: 1);
    final second = await h.entryIn(beta.id, title: 'Second', ordinal: 2);

    await openStrip(tester);
    await settleQuery(tester);
    expect(find.text('CONTINUE READING'), findsNothing);

    // Same tree, nothing rebuilt by hand.
    await h.readAtSource(
      first.id,
      sourceId: alphaSource.id,
      at: DateTime.utc(2026, 7, 20),
    );
    await pumpUntil(tester, card(first.id));
    expect([for (final item in stripItems(tester)) item.entryId], [first.id]);

    await h.readAtSource(
      second.id,
      sourceId: betaSource.id,
      at: DateTime.utc(2026, 7, 25),
    );
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
