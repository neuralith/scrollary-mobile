/// Activity: everything this device is doing on the user's behalf, and what
/// can be done about it.
///
/// The screen decides nothing, so these tests are about what it is allowed to
/// *offer*. The structural invariants are the queue's and are asserted through
/// it, not around it: cancelling preserves the row, an Undo puts a waiting row
/// back **where it was**, only a terminal row can be removed, and removing one
/// deletes no Entry, no file and no reading state.
///
/// The other half is honesty about outcomes. Every row prints the verdict the
/// queue recorded — "the site stopped us" and "you stopped it" are different
/// outcomes — and a task refused by the capture policy carries the policy's
/// own sentence and no other (STORE_PACKAGE.md §6.5.1).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/queue_task.dart';

import 'library_ui/support/ui_harness.dart';
import 'save_v2/support/capture_harness.dart' show restrictedUrl;

void main() {
  late UiHarness h;
  var seeded = 0;

  setUp(() {
    h = UiHarness();
    seeded = 0;
  });
  tearDown(() => h.close());

  Future<CollectionRow> shelf() async =>
      h.collection('Serial Alpha', folderId: (await h.root()).id);

  /// One Entry in the shelf. [title] is honoured as given — a blank one is a
  /// real case, not a seeding mistake.
  Future<EntryRow> entry(CollectionRow collection, {String? title}) async {
    final n = ++seeded;
    return h.entryIn(
      collection.id,
      title: title ?? 'Part $n',
      ordinal: n.toDouble(),
    );
  }

  String addressOf(EntryRow row) =>
      'https://reading.example.com/serial/${row.id}';

  /// A waiting row, through the real queue.
  Future<SaveTask> waiting(EntryRow row) async {
    final result = await h.queue.enqueue(
      entryId: row.id,
      locationUrl: addressOf(row),
    );
    expect(result.refusedReason, isNull, reason: 'seeding must not be refused');
    return result.task!;
  }

  /// A row a runner has claimed.
  Future<SaveTask> running(EntryRow row) async =>
      (await h.queue.claim((await waiting(row)).id))!;

  Future<SaveTask> failed(EntryRow row, String reason) async {
    final task = await running(row);
    await h.queue.finish(task.id, state: SaveTaskState.failed, outcome: reason);
    return (await h.queue.byId(task.id))!;
  }

  Future<SaveTask> completed(EntryRow row) async {
    final task = await running(row);
    await h.queue.finish(
      task.id,
      state: SaveTaskState.completed,
      outcome: 'Downloaded to this device.',
    );
    return (await h.queue.byId(task.id))!;
  }

  Future<void> openScreen(WidgetTester tester) =>
      tester.pumpWidget(h.app(const ActivityScreen()));

  screenTest('an empty queue says nothing is running and offers no Start', (
    tester,
  ) async {
    await shelf();
    await openScreen(tester);
    await pumpUntil(tester, find.text('Nothing is running'));

    expect(
      find.textContaining('Nothing on this device starts on its own'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activityStart')), findsNothing);
    expect(await h.queue.all(), isEmpty);
  });

  screenTest('rows are grouped by what can be done about them, with their '
      'counts', (tester) async {
    final collection = await shelf();
    final live = await running(await entry(collection));
    final queued = await waiting(await entry(collection));
    final broken = await failed(await entry(collection), 'the site stopped us');
    final done = await completed(await entry(collection));
    final stopped = await waiting(await entry(collection));
    expect(
      await h.queue.cancel(stopped.id),
      SaveCancelOutcome.cancelledBeforeStart,
    );

    await openScreen(tester);
    await pumpUntil(tester, find.text('RUNNING · 1'));

    expect(find.text('RUNNING · 1'), findsOneWidget);
    expect(find.text('WAITING · 1'), findsOneWidget);
    expect(find.text('FAILED · 1'), findsOneWidget);
    // Completed and cancelled are both over with, and both are history.
    expect(find.text('FINISHED · 2'), findsOneWidget);

    for (final task in [live, queued, broken, done, stopped]) {
      expect(find.byKey(ValueKey('activityRow-${task.id}')), findsOneWidget);
    }
  });

  screenTest('each row prints the queue\'s own verdict', (tester) async {
    final collection = await shelf();
    await waiting(await entry(collection));
    await running(await entry(collection));
    await failed(await entry(collection), 'the site stopped us');
    final beforeStart = await waiting(await entry(collection));
    await h.queue.cancel(beforeStart.id);
    final midRun = await running(await entry(collection));
    expect(await h.queue.cancel(midRun.id), SaveCancelOutcome.stoppingRunning);

    await openScreen(tester);
    await pumpUntil(tester, find.text('the site stopped us'));

    expect(
      find.text(
        'Waiting in the download queue. Nothing starts until you '
        'start it.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Downloading now. Stopping it takes effect at the next safe '
        'point.',
      ),
      findsOneWidget,
    );
    // A failure keeps its reason, and the two ways a row can be cancelled say
    // different things: one never started, the other was stopped by the user.
    expect(find.text('the site stopped us'), findsOneWidget);
    expect(find.text(kSaveTaskCancelledBeforeStart), findsOneWidget);
    expect(find.text(kSaveTaskStopping), findsOneWidget);
  });

  screenTest('a task refused by the capture policy shows the restricted-site '
      'sentence', (tester) async {
    final collection = await shelf();
    final row = await entry(collection);
    // Queued while its address was still permitted, then settled by the
    // policy — a refusal is a terminal named outcome, never a silent delete.
    final task = await waiting(row);
    await (h.db.update(h.db.saveQueue)..where((t) => t.id.equals(task.id)))
        .write(SaveQueueCompanion(locationUrl: Value(restrictedUrl())));
    expect(
      await h.queue.settleIfRestricted((await h.queue.byId(task.id))!),
      isTrue,
    );

    await openScreen(tester);
    await pumpUntil(tester, find.text('FAILED · 1'));

    expect(find.text(kCaptureRestrictedMessage), findsOneWidget);
    // Still a row, and the user can be told what became of what they asked
    // for.
    expect(find.byKey(ValueKey('activityRow-${task.id}')), findsOneWidget);
  });

  screenTest('a row whose entry has no title falls back to the address', (
    tester,
  ) async {
    final collection = await shelf();
    final named = await entry(collection, title: 'The second one');
    final nameless = await entry(collection, title: '  ');
    final namedTask = await waiting(named);
    final namelessTask = await waiting(nameless);

    await openScreen(tester);
    // Wait for the label to resolve, so the fallback is not just the frame
    // before the answer arrived.
    await pumpUntil(tester, find.text('The second one'));

    final row = tester.widget<Text>(
      find.byKey(ValueKey('activityRow-${namelessTask.id}')),
    );
    expect(row.data, namelessTask.locationUrl);
    expect(row.data, isNotEmpty);
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('activityRow-${namedTask.id}')))
          .data,
      'The second one',
    );
  });

  screenTest('a live row is never offered removal from activity', (
    tester,
  ) async {
    final collection = await shelf();
    final queued = await waiting(await entry(collection));
    final live = await running(await entry(collection));

    await openScreen(tester);
    await pumpUntil(tester, find.text('RUNNING · 1'));

    // A waiting row leaves the queue; a running one is asked to stop. Neither
    // is dropped.
    expect(
      find.byKey(ValueKey('activityRemoveWaiting-${queued.id}')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('activityStop-${live.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('activityRemove-${queued.id}')), findsNothing);
    expect(find.byKey(ValueKey('activityRemove-${live.id}')), findsNothing);

    // And the offer is absent because the repository would refuse it anyway.
    expect(await h.queue.removeTerminal(queued.id), isFalse);
    expect(await h.queue.removeTerminal(live.id), isFalse);
    expect((await h.queue.byId(queued.id))!.state, SaveTaskState.queued);
    expect((await h.queue.byId(live.id))!.state, SaveTaskState.running);
  });

  screenTest('removing a waiting row cancels it, and Undo puts it back in its '
      'place', (tester) async {
    final collection = await shelf();
    final first = await waiting(await entry(collection));
    final second = await waiting(await entry(collection));

    await openScreen(tester);
    await pumpUntil(tester, find.text('WAITING · 2'));

    await tapAndPump(
      tester,
      find.byKey(ValueKey('activityRemoveWaiting-${second.id}')),
    );
    await pumpUntil(tester, find.byKey(const ValueKey('downloadRemoved')));

    // Cancelled preserves the row: it moves to history rather than vanishing.
    final cancelled = (await h.queue.byId(second.id))!;
    expect(cancelled.state, SaveTaskState.cancelled);
    expect(cancelled.orderIndex, second.orderIndex);
    expect(
      find.textContaining('nothing on this device was deleted'),
      findsOneWidget,
    );
    await pumpUntil(
      tester,
      find.byKey(ValueKey('activityRemove-${second.id}')),
    );

    await tapAndPump(tester, find.text('Undo'));
    await pumpUntil(tester, find.text('WAITING · 2'));

    final restored = (await h.queue.byId(second.id))!;
    expect(restored.state, SaveTaskState.queued);
    expect(restored.finishedAt, isNull);
    // In its place, not at the back: the queue order is what it was.
    expect(restored.orderIndex, second.orderIndex);
    expect(
      [for (final t in await h.queue.pending()) t.id],
      [first.id, second.id],
    );
  });

  screenTest('a failed row offers Retry, and taking it queues the work '
      'again', (tester) async {
    final collection = await shelf();
    final row = await entry(collection);
    final gone = await failed(row, 'The download did not finish.');
    await openScreen(tester);
    await pumpUntil(tester, find.byKey(ValueKey('activityRetry-${gone.id}')));

    await tapAndPump(tester, find.byKey(ValueKey('activityRetry-${gone.id}')));

    // Recovery is Free and it is a *re-queue*, not a second kind of start:
    // the new row waits like every other one.
    final tasks = await h.queue.all();
    final waitingAgain = tasks.where((t) => t.state == SaveTaskState.queued);
    expect(waitingAgain, hasLength(1));
    expect(waitingAgain.single.entryId, row.id);
    expect(h.queue.saveStartAuthorised, isFalse);
  });

  screenTest('a finished row offers no Retry — there is nothing to try '
      'again', (tester) async {
    final collection = await shelf();
    final done = await completed(await entry(collection));
    await openScreen(tester);
    await pumpUntil(tester, find.byKey(ValueKey('activityRemove-${done.id}')));

    expect(find.byKey(ValueKey('activityRetry-${done.id}')), findsNothing);
  });

  screenTest('a finished row never prints a file path at the user', (
    tester,
  ) async {
    final collection = await shelf();
    final row = await entry(collection);
    final task = await running(row);
    // What the runner actually writes on a successful capture.
    await h.queue.finish(
      task.id,
      state: SaveTaskState.completed,
      outcome: 'Downloaded to this device · 18 images.',
    );
    await openScreen(tester);
    await pumpUntil(tester, find.textContaining('Downloaded to this device'));

    expect(find.textContaining('library/'), findsNothing);
    expect(find.textContaining('manifest.json'), findsNothing);
  });

  screenTest('removing a finished row deletes the row and nothing else', (
    tester,
  ) async {
    final collection = await shelf();
    final row = await entry(collection, title: 'The first one');
    await h.copyFor(row.id);
    await h.reading.recordSourceAccess(row.id, at: DateTime.utc(2026, 7, 20));
    final task = await completed(row);

    await openScreen(tester);
    await pumpUntil(tester, find.byKey(ValueKey('activityRemove-${task.id}')));

    await tapAndPump(tester, find.byKey(ValueKey('activityRemove-${task.id}')));
    await pumpUntil(tester, find.textContaining('Removed from activity'));

    expect(await h.queue.byId(task.id), isNull);
    expect(find.byKey(ValueKey('activityRow-${task.id}')), findsNothing);
    // Queue rows are never the content.
    expect(await h.entries.byId(row.id), isNotNull);
    expect(h.bytesOnDisk(row.id), isTrue);
    expect(await h.offlineCopyRows(row.id), 1);
    expect((await h.reading.stateOf(row.id)).lastReadAt, isNotNull);
  });

  screenTest('the Start control appears only when something is waiting', (
    tester,
  ) async {
    final collection = await shelf();
    final done = await completed(await entry(collection));

    await openScreen(tester);
    await pumpUntil(tester, find.text('FINISHED · 1'));

    expect(find.byKey(const ValueKey('activityStart')), findsNothing);
    expect(find.byKey(ValueKey('activityRow-${done.id}')), findsOneWidget);

    // Something to start, and the control arrives with it.
    await waiting(await entry(collection));
    await pumpUntil(tester, find.byKey(const ValueKey('activityStart')));
    expect(find.text('Start 1 download'), findsOneWidget);
  });

  screenTest('Start authorises the waiting rows and hands them to the runner', (
    tester,
  ) async {
    final collection = await shelf();
    await waiting(await entry(collection));
    await waiting(await entry(collection));

    await openScreen(tester);
    await pumpUntil(tester, find.byKey(const ValueKey('activityStart')));

    // Until then, nothing on this device may run the queue.
    expect(h.queue.saveStartAuthorised, isFalse);
    expect(await h.queue.eligible(), isEmpty);
    expect(find.text('Start 2 downloads'), findsOneWidget);

    await tapAndPump(tester, find.byKey(const ValueKey('activityStart')));
    await pumpUntil(tester, find.text('Starting 2 downloads.'));

    expect(h.queue.saveStartAuthorised, isTrue);
    expect(h.starts, 1);
    expect((await h.queue.eligible()).length, 2);
  });
}
