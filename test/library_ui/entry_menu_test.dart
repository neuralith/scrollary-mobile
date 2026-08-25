/// The Entry menu: what it offers, and whether any of it can be reached
/// (V2-D64).
///
/// Two failures live here, and they had the same cause — nobody had asked the
/// menu a question about *size*.
///
/// 1. **It was capped and could not scroll.** `showModalBottomSheet` limits a
///    sheet to nine sixteenths of the window unless it is scroll-controlled,
///    and a `Column` given less height than it needs overflows rather than
///    scrolling. On a 390×844 phone the Entry menu was cut at 474.8pt with
///    four of its nine items below the fold and no way down. It survived
///    review because [kListWindow] is 1400pt tall and everything fitted.
/// 2. **The download control lied in one state.** A copy already on the
///    device never blocked a re-request and never should — but the row said
///    *Puts a copy on this device* and then asked to overwrite one.
///
/// So the size assertions run at [kPhoneWindow] and check *rects*, not just
/// finders: `find.byKey` matches a widget 400pt below the sheet perfectly
/// happily, which is exactly why the suite stayed green.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/providers.dart' show primaryLocation;
import 'package:web_reader/save/queue_task.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// A Collection with one Entry this device holds and one it does not. Both
  /// have an address, so a download is a real request rather than a refusal.
  Future<({CollectionRow collection, EntryRow held, EntryRow plain})>
  seed() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final source = await h.source(collection.id, host: 'alpha.example');
    final held = await h.entryIn(
      collection.id,
      title: 'The first one',
      ordinal: 1,
    );
    await h.copyFor(held.id);
    await h.location(
      held.id,
      'https://alpha.example/serial/1',
      sourceId: source.id,
    );
    final plain = await h.entryIn(
      collection.id,
      title: 'The second one',
      ordinal: 2,
    );
    await h.location(
      plain.id,
      'https://alpha.example/serial/2',
      sourceId: source.id,
    );
    return (collection: collection, held: held, plain: plain);
  }

  Future<void> openScreen(WidgetTester tester, String collectionId) async {
    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: collectionId)),
    );
    await pumpUntil(tester, find.text('The second one'));
  }

  Future<void> openMenu(WidgetTester tester, String entryId) =>
      tapAndPump(tester, find.byKey(ValueKey('entryMenu-$entryId')));

  /// Put a row in the queue for [entryId] and leave it in [state].
  ///
  /// A live row is made the way the app makes one — enqueue, then claim —
  /// rather than written straight to `running`, so the states under test are
  /// states the queue can actually be in.
  Future<void> queueRow(String entryId, SaveTaskState state) async {
    if (state.isTerminal) {
      await h.queue.recordDirectOutcome(
        entryId: entryId,
        locationUrl: 'https://alpha.example/serial/x',
        state: state,
        outcome: state == SaveTaskState.failed ? 'the site stopped us' : null,
      );
      return;
    }
    final location = await primaryLocation(h.db, entryId);
    await h.queue.enqueue(
      entryId: entryId,
      locationId: location!.id,
      locationUrl: location.url,
    );
    if (state == SaveTaskState.running) {
      await h.queue.claim((await h.taskFor(entryId))!.id);
    }
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  /// Wait for something that is behind real file I/O.
  ///
  /// [pumpUntil] alone cannot reach it: the download preflight reads the
  /// copy's manifest off the disk, and a `testWidgets` fake clock never turns
  /// a real `readAsString`. Alternating [letFilesSettle] — which runs the
  /// actual loop — with ordinary pumps gives the I/O its turns and the
  /// framework the frames to draw the result.
  Future<void> pumpThroughFiles(WidgetTester tester, Finder finder) async {
    for (var round = 0; round < 10; round++) {
      await letFilesSettle(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        if (finder.evaluate().isNotEmpty) return;
      }
    }
    fail('timed out waiting for $finder');
  }

  // ─── the matrix ───────────────────────────────────────────────────────────

  /// Two independent facts (PRODUCT.md §2.3): whether this device holds a
  /// copy, and what the queue is doing. Neither is derivable from the other —
  /// a copy can exist with no queue row at all, and a completed row can
  /// outlive the copy it made.
  ///
  /// `download` is the **title** the download control carries, or null where
  /// it is not offered at all.
  const matrix =
      <
        ({
          String name,
          bool copy,
          SaveTaskState? task,
          String? download,
          bool removeCopy,
          List<String> queueKeys,
        })
      >[
        (
          name: 'no copy, no queue row',
          copy: false,
          task: null,
          download: 'Download for offline',
          removeCopy: false,
          queueKeys: [],
        ),
        (
          name: 'no copy, waiting',
          copy: false,
          task: SaveTaskState.queued,
          download: null,
          removeCopy: false,
          queueKeys: ['entryStartDownload', 'entryRemoveWaiting'],
        ),
        (
          name: 'no copy, running',
          copy: false,
          task: SaveTaskState.running,
          download: null,
          removeCopy: false,
          queueKeys: ['entryStopDownload'],
        ),
        (
          name: 'no copy, failed',
          copy: false,
          task: SaveTaskState.failed,
          download: 'Download for offline',
          removeCopy: false,
          queueKeys: ['entryRemoveActivity'],
        ),
        (
          // The copy was made and then freed. History is not a copy.
          name: 'no copy, completed',
          copy: false,
          task: SaveTaskState.completed,
          download: 'Download for offline',
          removeCopy: false,
          queueKeys: ['entryRemoveActivity'],
        ),
        (
          name: 'copy, no queue row',
          copy: true,
          task: null,
          download: 'Download again',
          removeCopy: true,
          queueKeys: [],
        ),
        (
          // Nothing has started, so freeing the copy is still an ordinary choice.
          name: 'copy, waiting',
          copy: true,
          task: SaveTaskState.queued,
          download: null,
          removeCopy: true,
          queueKeys: ['entryStartDownload', 'entryRemoveWaiting'],
        ),
        (
          // The one place the copy's control goes: those bytes are being replaced
          // right now, and *Stop this download* is the verb for changing that.
          name: 'copy, running',
          copy: true,
          task: SaveTaskState.running,
          download: null,
          removeCopy: false,
          queueKeys: ['entryStopDownload'],
        ),
        (
          name: 'copy, failed',
          copy: true,
          task: SaveTaskState.failed,
          download: 'Download again',
          removeCopy: true,
          queueKeys: ['entryRemoveActivity'],
        ),
        (
          name: 'copy, completed',
          copy: true,
          task: SaveTaskState.completed,
          download: 'Download again',
          removeCopy: true,
          queueKeys: ['entryRemoveActivity'],
        ),
      ];

  group('what the menu offers', () {
    for (final row in matrix) {
      screenTest(row.name, (tester) async {
        final s = await seed();
        final entry = row.copy ? s.held : s.plain;
        if (row.task != null) await queueRow(entry.id, row.task!);

        await openScreen(tester, s.collection.id);
        await openMenu(tester, entry.id);

        if (row.download == null) {
          expect(
            key('entryDownload'),
            findsNothing,
            reason: 'a live row is acted on, never asked for a second time',
          );
        } else {
          expect(key('entryDownload'), findsOneWidget);
          expect(
            find.descendant(
              of: key('entryDownload'),
              matching: find.text(row.download!),
            ),
            findsOneWidget,
            reason: 'the control has to say which of the two it is',
          );
        }

        expect(
          key('entryRemoveCopy'),
          row.removeCopy ? findsOneWidget : findsNothing,
        );

        for (final k in const [
          'entryStartDownload',
          'entryRemoveWaiting',
          'entryStopDownload',
          'entryRemoveActivity',
        ]) {
          expect(
            key(k),
            row.queueKeys.contains(k) ? findsOneWidget : findsNothing,
            reason: '$k in ${row.name}',
          );
        }

        // Unchanged by any of it: an Entry is in the library whatever this
        // device holds, and *Remove from library* is never the copy's verb.
        expect(key('entryRemove'), findsOneWidget);
        expect(key('entryDetails'), findsOneWidget);
      });
    }

    screenTest('replacing a copy says so before it queues anything', (
      tester,
    ) async {
      final s = await seed();
      await openScreen(tester, s.collection.id);
      await openMenu(tester, s.held.id);

      await tapAndPump(tester, find.text('Download again'));

      // The confirmation `downloadForOffline` has always shown, now reached
      // from a control that agrees with it rather than from one that had just
      // promised to *put* a copy here. Declining queues nothing.
      await pumpThroughFiles(
        tester,
        find.text('Already downloaded — download it again?'),
      );
      expect(
        find.textContaining('replaces it'),
        findsOneWidget,
        reason: 'the dialog and the control now say the same thing',
      );

      await tapAndPump(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(await h.queue.all(), isEmpty);
    });

    screenTest('the copy of a running download is not offered for freeing', (
      tester,
    ) async {
      final s = await seed();
      await queueRow(s.held.id, SaveTaskState.running);
      await openScreen(tester, s.collection.id);
      await openMenu(tester, s.held.id);

      expect(key('entryRemoveCopy'), findsNothing);
      expect(
        key('entryStopDownload'),
        findsOneWidget,
        reason: 'stopping is what changes a run, and it is offered instead',
      );
      // Nothing about the copy itself changed: it is still on the device and
      // still what the row draws.
      expect(await h.offlineCopyRows(s.held.id), 1);
      expect(find.byKey(ValueKey('entryOffline-${s.held.id}')), findsOneWidget);
    });
  });

  // ─── reachability ─────────────────────────────────────────────────────────

  group('on a phone', () {
    /// Every action, at the tallest the Entry menu gets, on a real handset.
    Future<void> openTheTallestMenu(WidgetTester tester) async {
      final root = await h.root();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(
        collection.id,
        title: 'A stray one',
        placement: Placement.unplaced,
      );
      await h.copyFor(entry.id);
      await h.location(
        entry.id,
        'https://alpha.example/serial/1',
        sourceId: source.id,
      );
      await h.queue.recordDirectOutcome(
        entryId: entry.id,
        locationUrl: 'https://alpha.example/serial/1',
        state: SaveTaskState.failed,
        outcome: 'the site stopped us',
      );

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, find.byKey(ValueKey('entryRow-${entry.id}')));
      await openMenu(tester, entry.id);
    }

    screenTest('the menu scrolls rather than clipping', (tester) async {
      await openTheTallestMenu(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'a clipped Column throws; a scrolling one does not',
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
        reason: 'the sheet had no scroll view at all, at any height',
      );
    }, window: kPhoneWindow);

    screenTest('every action can be scrolled to and tapped', (tester) async {
      await openTheTallestMenu(tester);

      final sheet = find.byType(BottomSheet);
      final scrollable = find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first;

      for (final action in const [
        'entryRead',
        'entryMarkRead',
        'entryDetails',
        'entryOpenAtSource',
        'entryPlace',
        'entryDownload',
        'entryRemoveActivity',
        'entryRemoveCopy',
        'entryRemove',
      ]) {
        expect(key(action), findsOneWidget, reason: '$action is in this menu');
        // `findsOneWidget` was true of all nine before this change, four of
        // them 400pt below the sheet. Scrolling to it and reading its rect is
        // the assertion that was missing.
        await tester.scrollUntilVisible(
          key(action),
          80,
          scrollable: scrollable,
        );
        await tester.pump();
        final rect = tester.getRect(key(action));
        final within = tester.getRect(sheet);
        expect(
          rect.top >= within.top - 0.5 && rect.bottom <= within.bottom + 0.5,
          isTrue,
          reason:
              '$action sits at ${rect.top}..${rect.bottom}, sheet is '
              '${within.top}..${within.bottom}',
        );
        expect(
          tester.getSize(key(action)).height,
          greaterThanOrEqualTo(48),
          reason: '$action is still a real target',
        );
      }
    }, window: kPhoneWindow);

    screenTest('a short menu is still short', (tester) async {
      final s = await seed();
      await openScreen(tester, s.collection.id);
      await openMenu(tester, s.plain.id);

      // Scroll-controlled is not full-height: `MainAxisSize.min` inside the
      // scroll view means the sheet is exactly as tall as its contents, so a
      // five-item menu did not become a page.
      final sheet = tester.getSize(find.byType(BottomSheet)).height;
      expect(sheet, lessThan(kPhoneWindow.height * 0.75));
      expect(tester.takeException(), isNull);
    }, window: kPhoneWindow);
  });
}
