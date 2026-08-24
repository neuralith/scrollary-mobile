/// Getting a copy onto this device, and freeing it again (D5).
///
/// These run over the **real** `SaveQueueRepository`, because the properties
/// worth testing are its own: nothing runs without an explicit Start, a cancel
/// preserves the row, an Undo puts a waiting row back where it was, and only a
/// finished row can be removed from activity.
///
/// The negative assertions carry the weight. Asking for a download must leave
/// the queue holding a row that **nothing is eligible to run**, and freeing a
/// copy must leave the Entry, its reading state and the rest of the library
/// exactly where they were.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/save/queue_task.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  /// A Collection with one Entry that has an address, and one this device is
  /// already holding bytes for.
  Future<({CollectionRow collection, EntryRow plain, EntryRow held})>
  seed() async {
    final root = await h.root();
    final collection = await h.collection('Serial Alpha', folderId: root.id);
    final source = await h.source(collection.id);
    final plain = await h.entryIn(
      collection.id,
      title: 'The second one',
      ordinal: 2,
    );
    await h.location(
      plain.id,
      'https://reading.example.com/serial/2',
      sourceId: source.id,
    );
    final held = await h.entryIn(
      collection.id,
      title: 'The first one',
      ordinal: 1,
    );
    await h.copyFor(held.id);
    return (collection: collection, plain: plain, held: held);
  }

  Future<void> openEntryMenu(WidgetTester tester, String entryId) =>
      tapAndPump(tester, find.byKey(ValueKey('entryMenu-$entryId')));

  Future<void> openScreen(WidgetTester tester, String collectionId) async {
    await tester.pumpWidget(
      h.app(CollectionScreen(collectionId: collectionId)),
    );
    await pumpUntil(tester, find.text('The first one'));
  }

  /// Ask for a download through the menu, and wait for the row to say so.
  Future<void> askForDownload(WidgetTester tester, String entryId) async {
    await openEntryMenu(tester, entryId);
    await tapAndPump(tester, find.text('Download for offline'));
    await pumpUntil(tester, find.text('Waiting to start'));
  }

  screenTest('asking for a download queues it and starts nothing', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);

    await askForDownload(tester, s.plain.id);

    final task = await h.taskFor(s.plain.id);
    expect(task, isNotNull);
    expect(task!.state, SaveTaskState.queued);
    expect(task.locationUrl, 'https://reading.example.com/serial/2');
    expect(task.locationId, isNotNull);

    // No mode of its own, which is what lets the capture seam ask the
    // Collection what it is normally saved as (V2-D58). A row that arrived
    // with one baked in would freeze whichever answer was in force when the
    // menu was tapped.
    expect(task.captureMode, isNull);
    expect(task.captureModeIsUserSet, isFalse);

    // The whole point: a row exists and **nothing may run it**. Save is the
    // one kind of work that waits for an explicit Start.
    expect(await h.queue.eligible(), isEmpty);
    expect(h.queue.saveStartAuthorised, isFalse);
    expect(h.starts, 0);
    // And no copy appeared out of a queued row.
    expect(await h.offlineCopyRows(s.plain.id), 0);
  });

  screenTest('an entry with no address is told so, and nothing is queued', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);

    await openEntryMenu(tester, s.held.id);
    await tapAndPump(tester, find.text('Download for offline'));
    await pumpUntil(tester, find.textContaining('No address is recorded'));

    expect(await h.queue.all(), isEmpty);
  });

  screenTest('a queued entry is offered its row, never a second request', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);

    await openEntryMenu(tester, s.plain.id);
    expect(find.text('Download for offline'), findsNothing);
    expect(find.text('Start downloading'), findsOneWidget);
    expect(find.text('Remove from the download queue'), findsOneWidget);
    // A finished row's control is not offered for a live one.
    expect(find.text('Remove from activity'), findsNothing);
    expect(
      find.textContaining('Nothing starts until you start it'),
      findsWidgets,
    );
  });

  screenTest('Start authorises the waiting rows and hands them to the runner', (
    tester,
  ) async {
    final s = await seed();
    // Something else was already waiting, queued before this one.
    await h.queue.enqueue(
      entryId: s.held.id,
      locationUrl: 'https://reading.example.com/serial/1',
    );
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Start downloading'));
    await pumpUntil(tester, find.text('Starting 2 downloads.'));

    expect(h.queue.saveStartAuthorised, isTrue);
    expect(h.starts, 1);
    // One Start, one queue: starting from a row puts that row first rather
    // than running it on its own.
    final eligible = await h.queue.eligible();
    expect(eligible.length, 2);
    expect(eligible.first.entryId, s.plain.id);
  });

  screenTest('with no runner attached, a Start authorises nothing', (
    tester,
  ) async {
    // Set before the tree is built: the override is read there.
    h.starter = null;
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Start downloading'));
    await pumpUntil(tester, find.textContaining('Nothing was started'));

    expect(h.queue.saveStartAuthorised, isFalse);
    expect(await h.queue.eligible(), isEmpty);
    // The row is untouched — a Start that could not happen changes nothing.
    expect((await h.taskFor(s.plain.id))!.state, SaveTaskState.queued);
  });

  screenTest('removing a waiting row keeps its place, and Undo restores it', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);
    final queued = (await h.taskFor(s.plain.id))!;

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Remove from the download queue'));
    await pumpUntil(tester, find.byKey(const ValueKey('downloadRemoved')));

    // Cancelled preserves the row; it is not a deletion and not a sixth state.
    final cancelled = (await h.taskFor(s.plain.id))!;
    expect(cancelled.state, SaveTaskState.cancelled);
    expect(cancelled.outcome, kSaveTaskCancelledBeforeStart);
    expect(cancelled.orderIndex, queued.orderIndex);
    expect(
      find.textContaining('nothing on this device was deleted'),
      findsOneWidget,
    );

    await tapAndPump(tester, find.text('Undo'));
    await pumpUntil(tester, find.text('Waiting to start'));
    final restored = (await h.taskFor(s.plain.id))!;
    expect(restored.state, SaveTaskState.queued);
    // In place, not at the back of the queue.
    expect(restored.orderIndex, queued.orderIndex);
    expect(restored.finishedAt, isNull);
  });

  screenTest('stopping a running download is cooperative, and says so', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);

    // Claimed, as a runner would claim it.
    final claimed = await h.queue.claim((await h.taskFor(s.plain.id))!.id);
    expect(claimed, isNotNull);
    await pumpUntil(tester, find.text('Downloading'));

    await openEntryMenu(tester, s.plain.id);
    await tapAndPump(tester, find.text('Stop this download'));
    expect(
      find.textContaining('It stops at the next safe point'),
      findsOneWidget,
    );
    expect(find.textContaining('stays in your library'), findsOneWidget);
    await tapAndPump(tester, find.byKey(const ValueKey('confirmStopDownload')));
    await pumpUntil(tester, find.text('Stopping at the next safe point.'));

    // The row is written the moment it is asked for, and the run in flight is
    // asked to stop at its next boundary.
    final stopped = (await h.taskFor(s.plain.id))!;
    expect(stopped.state, SaveTaskState.cancelled);
    expect(stopped.outcome, kSaveTaskStopping);
    expect(h.queue.shouldContinue(stopped.id), isFalse);
  });

  screenTest('remove from activity takes a finished row and nothing else', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    await askForDownload(tester, s.plain.id);
    final id = (await h.taskFor(s.plain.id))!.id;
    expect(await h.queue.cancel(id), SaveCancelOutcome.cancelledBeforeStart);
    await pumpUntilGone(tester, find.text('Waiting to start'));

    await openEntryMenu(tester, s.plain.id);
    // A terminal row: the queue offers to forget it, and offers the download
    // again, because history never blocks an intentional re-request.
    expect(find.text('Download for offline'), findsOneWidget);
    await tapAndPump(tester, find.text('Remove from activity'));
    await pumpUntil(tester, find.textContaining('Removed from activity'));

    expect(await h.taskFor(s.plain.id), isNull);
    // The Entry is untouched by anything that happened to its queue row.
    expect(await h.entries.byId(s.plain.id), isNotNull);
    expect(find.text('The second one'), findsOneWidget);
  });

  screenTest('a failed download says so on the row and keeps its reason', (
    tester,
  ) async {
    final s = await seed();
    await h.queue.recordDirectOutcome(
      entryId: s.plain.id,
      locationUrl: 'https://reading.example.com/serial/2',
      state: SaveTaskState.failed,
      outcome: 'the site stopped us',
    );
    await openScreen(tester, s.collection.id);
    await pumpUntil(tester, find.text('Download failed'));

    await openEntryMenu(tester, s.plain.id);
    expect(find.text('the site stopped us'), findsOneWidget);
  });

  screenTest('freeing the copy takes the bytes and leaves everything else', (
    tester,
  ) async {
    final s = await seed();
    await openScreen(tester, s.collection.id);
    expect(h.bytesOnDisk(s.held.id), isTrue);

    await openEntryMenu(tester, s.held.id);
    await tapAndPump(tester, find.text('Remove offline copy'));
    expect(find.textContaining('no other device is affected'), findsOneWidget);
    await tapAndPump(tester, find.widgetWithText(TextButton, 'Remove copy'));
    await letFilesSettle(tester);
    await pumpUntil(
      tester,
      find.textContaining('Copy removed from this device'),
    );

    // Bytes first, rows second — both gone, and nothing else with them.
    expect(h.bytesOnDisk(s.held.id), isFalse);
    expect(await h.offlineCopyRows(s.held.id), 0);
    expect(await h.entries.byId(s.held.id), isNotNull);
    expect(find.text('The first one'), findsOneWidget);
  });
}
