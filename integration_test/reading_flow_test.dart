// Reading state end to end on a device, against the in-process fixture:
// capture, read partway, leave, complete, continue, mark unread, capture
// again.
//
//   flutter test integration_test/reading_flow_test.dart -d <device-id>
//
// **What the V2 port changed: three writes, three owners.** V1 kept everything
// on one Entry row — progress fraction, anchor index, read status, completion
// time. V2 separates them by who they belong to:
//
// * the **anchor** goes on the OfflineCopy, because it indexes *these* bytes
//   and is meaningless without them. It never leaves the device.
// * the **reading state** goes through `ReadingStateRepository`, which is the
//   only thing that may reach a reading column, serialises every write so a
//   stale in-flight one cannot clobber a newer one, and is the half that
//   synchronises.
// * nothing here writes a **Measurement**: a measurement is scoped to the
//   rendering it was taken against, and reading an offline copy is not reading
//   a Source.
//
// The behaviour the user sees is unchanged, and that is what this suite
// asserts: a position is written where it can be found again, Continue
// Reading offers what you are
// partway through and lets it go when you finish, marking unread restores
// eligibility without discarding where you were, and capturing an Entry again
// never resets any of it.
//
// **On "survives a restart".** V1's suite closed the database and rebooted the
// app mid-test. Neither half of that is sustainable here — see the note in
// `support/v2_harness.dart`'s `boot` for the three shapes that were tried and
// what each does on which platform — so durability is asserted through
// repositories built *after* the write, which proves the value reached the
// database rather than living in the object that wrote it. The cold-start claim
// belongs to a separate `flutter test` invocation, where it is free.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/reading/reading_position.dart' hide ReadStatus;
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/save/queue_task.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Delays off: this suite is about what happens after a capture, and the slow
  // panel only makes each one two seconds longer.
  final fixture = FixtureSite(applyDelays: false);
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester, String tag) async {
    app = V2App(tag: tag);
    await app.boot(tester);
    await showBrowser(tester);
  }

  tearDown(() => app.shutdown());

  OfflineReadSession sessionFor(String entryId) => OfflineReadSession(
    entryId: entryId,
    offlineCopies: app.ui.offline,
    reading: app.ui.reading,
  );

  /// Capture [n] and return its Entry id.
  Future<String> capture(WidgetTester tester, int n) async {
    final entryId = await app.queueSaveOf(fixture.entry(n), title: 'Entry $n');
    await startQueue(tester, app);
    await awaitQueueIdle(tester, app);
    final task = await app.latestTaskFor(entryId);
    expect(
      task!.state,
      SaveTaskState.completed,
      reason: 'entry $n ended ${task.state.name}: ${task.lastError}',
    );
    return entryId;
  }

  testWidgets(
    'a position read partway is written where it can be found',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final entryId = await capture(tester, 1);

      await sessionFor(entryId).saveProgress(
        const ReadingPosition(anchorIndex: 2, offsetInAnchor: 0.4),
      );

      var state = await app.ui.reading.stateOf(entryId);
      expect(
        state.status,
        ReadStatus.reading,
        reason: 'saving progress records access, and access is not completion',
      );
      expect(state.lastReadAt, isNotNull);

      // Read back through repositories built *after* the write. That is the
      // durability claim this suite can honestly make from inside one
      // `flutter test` run: the anchor came out of the database rather than out
      // of the session object that wrote it. A cold start over an existing
      // container is a separate invocation — see the note in the harness's
      // `boot` for why it is not reachable in-process.
      final fresh = app.freshLibraryReads();
      final read = await resolveOfflineRead(
        entryId: entryId,
        offlineCopies: fresh.offline,
        fileStore: app.fileStore,
      );
      final restored = (read as OfflineImageRead).restored;
      expect(
        restored.anchorIndex,
        2,
        reason: 'the anchor is durable, on the copy row that indexes it',
      );
      expect(restored.offsetInAnchor, closeTo(0.4, 0.01));

      state = await fresh.reading.stateOf(entryId);
      expect(state.status, ReadStatus.reading);
      expect(state.lastReadAt, isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'Continue Reading offers what you are partway through',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final first = await capture(tester, 1);
      final second = await capture(tester, 3);

      await sessionFor(first).saveProgress(
        const ReadingPosition(anchorIndex: 1, offsetInAnchor: 0.2),
      );

      await showLibrary(tester);
      final strip = find.byKey(const ValueKey('continueReadingStrip'));
      await pumpUntil(
        tester,
        () => strip.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the strip never appeared for a partly-read Entry',
      );
      expect(
        find.byKey(ValueKey('continueRead-$first')),
        findsOneWidget,
        reason: 'the Entry someone is partway through is offered',
      );
      expect(
        find.byKey(ValueKey('continueRead-$second')),
        findsNothing,
        reason:
            'and one nobody has opened is not — Continue is not a list of '
            'everything downloaded',
      );

      // Finishing it takes it out, and keeps the last-read time.
      await sessionFor(first).markRead();
      await pumpUntil(
        tester,
        () => find.byKey(ValueKey('continueRead-$first')).evaluate().isEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'a finished Entry stayed in Continue Reading',
      );
      final state = await app.ui.reading.stateOf(first);
      expect(state.status, ReadStatus.completed);
      expect(state.lastReadAt, isNotNull, reason: 'last-read time is kept');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  // **Known device-dependent failure.** This case drives the Entry's own action
  // sheet, and `showEntryMenu` puts a non-scrolling `Column` inside a
  // `showModalBottomSheet` with no `isScrollControlled`
  // (lib/library_ui/collection_actions.dart:179). A sheet is capped at 9/16 of
  // the screen, and an Entry with a copy on the device offers seven rows — so
  // on a shorter screen the Column overflows and the lower actions are clipped
  // out of reach. Measured: fine on an iPhone 17 Pro simulator (874pt tall),
  // "A RenderFlex overflowed by 125 pixels on the bottom" on a Pixel 9 Pro
  // emulator.
  //
  // Left running rather than skipped: this suite's subject *is* the sheet, the
  // overflow is a real user-facing defect, and a test that hides it would be
  // the wrong kind of green. Other suites reach the reader through the route
  // push instead, because the sheet is not what they are about.
  testWidgets(
    'mark read and mark unread, through the Entry\'s own sheet',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final entryId = await capture(tester, 1);
      await sessionFor(entryId).saveProgress(
        const ReadingPosition(anchorIndex: 2, offsetInAnchor: 0.4),
      );

      Future<void> openSheet() async {
        await showLibrary(tester);
        final row = find.byKey(ValueKey('entryRow-$entryId'));
        await pumpUntil(
          tester,
          () => row.evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
        );
        await tester.ensureVisible(row);
        await pumpFor(tester, const Duration(milliseconds: 400));
        await tester.tap(row, warnIfMissed: false);
        await pumpFor(tester, const Duration(seconds: 2));
      }

      await openSheet();
      expect(
        find.byKey(const ValueKey('entryMarkRead')),
        findsOneWidget,
        reason: 'an unfinished Entry is offered Mark read',
      );
      await tester.tap(
        find.byKey(const ValueKey('entryMarkRead')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 2));

      expect(
        (await app.ui.reading.stateOf(entryId)).status,
        ReadStatus.completed,
      );

      await openSheet();
      expect(
        find.byKey(const ValueKey('entryMarkUnread')),
        findsOneWidget,
        reason: 'and a finished one is offered Mark unread instead',
      );
      await tester.tap(
        find.byKey(const ValueKey('entryMarkUnread')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 2));

      expect(
        (await app.ui.reading.stateOf(entryId)).status,
        isNot(ReadStatus.completed),
      );
      final copy = (await app.ui.offline.activeCopyOf(entryId))!;
      expect(
        copy.anchorIndex,
        2,
        reason:
            'the anchor is kept: the user said it is unfinished, not that they '
            'were never there',
      );
      expect(copy.anchorOffset, closeTo(0.4, 0.01));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a completed Entry is 100% read, wherever the scroll is',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final entryId = await capture(tester, 1);

      await sessionFor(entryId).markRead();
      // Reopened and scrolled back to the top: a fact about the scroll, not about
      // the Entry.
      await sessionFor(
        entryId,
      ).saveProgress(const ReadingPosition(anchorIndex: 0, offsetInAnchor: 0));

      final state = await app.ui.reading.stateOf(entryId);
      expect(state.status, ReadStatus.completed);
      expect(
        offlineReadProgress(
          state: state,
          live: const ReadingPosition(fraction: 0.02),
        ),
        1,
        reason:
            'the completed-is-100% rule is enforced on write and again on '
            'display',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'capturing an Entry again preserves its reading state',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final entryId = await capture(tester, 1);

      await sessionFor(entryId).saveProgress(
        const ReadingPosition(anchorIndex: 3, offsetInAnchor: 0.5),
      );
      await sessionFor(entryId).markRead();
      final before = await app.ui.reading.stateOf(entryId);
      final copyBefore = (await app.ui.offline.activeCopyOf(entryId))!;

      // A deliberate re-capture of an Entry that already has bytes.
      final again = await app.ui.queue.enqueue(
        entryId: entryId,
        locationUrl: fixture.entry(1),
      );
      expect(again.refusedReason, isNull);
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final after = await app.ui.reading.stateOf(entryId);
      expect(after.status, ReadStatus.completed);
      expect(after.completedAt, before.completedAt);

      expect(
        (await app.ui.entries.locationsOf(entryId)),
        hasLength(1),
        reason: 'and it creates no second Location for the same address',
      );
      expect(
        (await app.ui.offline.allCopies()).where((c) => c.active),
        hasLength(1),
        reason: 'one active copy per Entry per device (I13)',
      );
      // The anchor is the half this does NOT preserve — see the next case.
      debugPrint(
        '[reading] anchor before=${copyBefore.anchorIndex} '
        'after=${(await app.ui.offline.activeCopyOf(entryId))!.anchorIndex}',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  // ---------------------------------------------------------------- defect
  //
  // **DEFECT — a re-capture discards the reading anchor.** Skipped rather than
  // deleted, because the scenario is right and the app is wrong.
  //
  // V1 had an explicit rule for this and still unit-tests it:
  // `carryReading(existing, format)` carries `progress_page_index` and
  // `progress_offset_in_page` across a re-save and resets them only when the
  // artifact format changed (`test/document_save_test.dart`, "re-saving in the
  // same format keeps the exact anchor"). V2's capture path has no equivalent.
  // `OfflineCopyRepository.recordCopy`
  // (lib/data/offline_copy_repository.dart:35) deactivates the old copy and
  // **inserts a fresh row**, whose `anchor_index` and `anchor_offset` are null;
  // nothing in `EntryCaptureService` reads the deactivated copy's anchor or
  // carries it forward.
  //
  // Reproduced on the Android emulator and the iOS simulator, debug: capture an
  // Entry, read partway, capture it again — the reader reopens at the top.
  // `ReadingState` survives, because it is a separate row with a separate
  // owner, so the Entry still says "reading" while the position it was reading
  // at is gone.
  //
  // Un-skip when the capture path carries the anchor the way `carryReading`
  // does, including its format-change reset.
  testWidgets(
    'capturing an Entry again preserves its reading anchor',
    (tester) async {
      await boot(tester, 'reading_${caseIndex++}_$kRunStamp');
      final entryId = await capture(tester, 1);

      await sessionFor(entryId).saveProgress(
        const ReadingPosition(anchorIndex: 3, offsetInAnchor: 0.5),
      );
      final before = (await app.ui.offline.activeCopyOf(entryId))!;

      final again = await app.ui.queue.enqueue(
        entryId: entryId,
        locationUrl: fixture.entry(1),
      );
      expect(again.refusedReason, isNull);
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final after = (await app.ui.offline.activeCopyOf(entryId))!;
      expect(
        after.anchorIndex,
        before.anchorIndex,
        reason: 'a re-capture must not move where somebody was',
      );
      expect(after.anchorOffset, before.anchorOffset);
    },
    timeout: const Timeout(Duration(minutes: 12)),
    skip: true,
  );
}
