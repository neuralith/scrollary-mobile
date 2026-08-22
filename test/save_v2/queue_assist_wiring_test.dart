/// The queue's worker and the user-assist host, wired the way the app wires
/// them (roadmap §10, the composition step `v2_save_flow.dart` recorded as
/// blocked).
///
/// The property under test is a *composition* one, and it is exactly one
/// sentence: **a queued capture that cannot find the reading area asks,
/// instead of failing.** Both halves already existed and were tested —
/// `user_assist_test.dart` owns what the hold does, `queue_runner_test.dart`
/// owns what the loop does — and neither could see the other. What could
/// break here is the wire between them, so that is all this file drives:
/// the same [QueueRunner] capture hook `main.dart` composes, over the real
/// queue rows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/browser/browser_controller.dart'
    show SelectedElement;
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/save/queue_task.dart';

import '../helpers/fake_browser.dart';
import 'support/capture_harness.dart';

/// What the JS picker reports for a tapped reading area.
const _readerContainer = SelectedElement(
  mode: 'reader',
  tag: 'div',
  classes: 'reading-content',
  selector: 'div.reading-content',
  imageCount: 12,
  minImageEdge: 800,
  imageSelector: 'img',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CaptureHarness h;
  late FakeBrowser browser;
  late PageHintRepository hints;
  late V2AssistController assist;
  late String collectionId;

  setUp(() async {
    h = CaptureHarness();
    browser = FakeBrowser();
    hints = PageHintRepository.forLibrary(h.db);
    assist = V2AssistController(browser: browser, hints: hints);
    collectionId = (await h.repos.seedLibrary()).collection.id;
  });

  tearDown(() async {
    assist.dispose();
    await h.close();
  });

  String urlFor(int ordinal) =>
      'https://reading.example.com/serial-alpha/part-$ordinal';

  /// A fresh Entry with a task waiting on it.
  Future<SaveTask> queueEntry(int ordinal) async {
    final (entry, violation) = await h.repos.entries.createInCollection(
      collectionId: collectionId,
      ordinal: ordinal.toDouble(),
      title: 'Part $ordinal',
    );
    expect(violation, isNull);
    final result = await h.queue.enqueue(
      entryId: entry!.id,
      locationUrl: urlFor(ordinal),
      captureMode: CaptureMode.imageSequence,
    );
    return result.task!;
  }

  /// The runner the app builds: the assist-aware capture hook, over this
  /// harness's queue and capture service.
  QueueRunner assistedRunner(FakePageCaptureSource source) => QueueRunner(
    queue: h.queue,
    captureServiceFor: () => h.captureWith(source),
    capture: (capture, task, {shouldContinue}) => v2CaptureWithAssist(
      capture: capture,
      assist: assist,
      entryId: task.entryId,
      locationId: task.locationId,
      locationUrl: task.locationUrl,
      captureMode: task.captureMode,
      captureModeIsUserSet: task.captureModeIsUserSet,
      shouldContinue: shouldContinue,
    ),
  );

  Future<void> pumpUntil(bool Function() done, String what) async {
    for (var i = 0; i < 2000; i++) {
      if (done()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('timed out waiting for $what');
  }

  test('a queued capture that needs the reading area holds and asks', () async {
    final task = await queueEntry(102);
    final source = FakePageCaptureSource.needingReaderAreaAssist();
    final runner = assistedRunner(source);
    addTearDown(runner.dispose);

    final draining = runner.start();
    await pumpUntil(
      () => assist.pendingSelection != null,
      'the hold the queued capture opens',
    );

    final request = assist.pendingSelection!;
    expect(request.kind, HintKind.readerArea);
    expect(request.sourceUrl, urlFor(102));
    expect(
      (await h.queue.byId(task.id))!.state,
      SaveTaskState.running,
      reason: 'the row is still the one being worked on while it asks',
    );

    await assist.submitSelection(_readerContainer);
    await draining;

    expect(assist.pendingSelection, isNull);
    expect((await h.queue.byId(task.id))!.state, SaveTaskState.completed);
    expect(
      source.readerHints.last?.id,
      (await hints.all()).single.id,
      reason: 'the retry carried what the tap taught',
    );
  });

  test('cancelling the hold leaves the row with its own failure', () async {
    final task = await queueEntry(103);
    final runner = assistedRunner(
      FakePageCaptureSource.needingReaderAreaAssist(),
    );
    addTearDown(runner.dispose);

    final draining = runner.start();
    await pumpUntil(() => assist.pendingSelection != null, 'the hold');
    await assist.cancelSelection();
    await draining;

    final row = (await h.queue.byId(task.id))!;
    expect(row.state, SaveTaskState.failed);
    expect(await hints.all(), isEmpty, reason: 'nothing was taught');
  });

  test(
    'without the hook the same row fails without ever asking — which is what '
    'the wiring changes',
    () async {
      final task = await queueEntry(104);
      final runner = QueueRunner(
        queue: h.queue,
        captureServiceFor: () =>
            h.captureWith(FakePageCaptureSource.needingReaderAreaAssist()),
      );
      addTearDown(runner.dispose);

      await runner.start();

      expect(assist.pendingSelection, isNull);
      expect((await h.queue.byId(task.id))!.state, SaveTaskState.failed);
    },
  );
}
