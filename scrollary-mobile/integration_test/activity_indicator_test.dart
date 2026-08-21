// Where the compact activity indicator actually lands, on a real device.
//
//   flutter test integration_test/activity_indicator_test.dart -d <device>
//
// Everything about *when* the pill appears is decided in Dart and proved by
// `test/operation_indicator_test.dart`, which needs no device at all. The one
// thing a widget test cannot answer is the question this file exists for:
// **does it clear the hardware.** A simulated view padding is a number someone
// typed; a notch is not. So this boots the real app, puts one waiting row in
// the queue, and measures the pill against the insets the platform reports and
// against the shell's own chrome.
//
// No fixture server, no WebView, no save: none of that is what is under test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/status_style.dart';

final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FileStore fileStore;
  var caseIndex = 0;

  Future<void> bootApp(WidgetTester tester) async {
    final tag = 'it_ind_${caseIndex++}_$kRunStamp';
    db = AppDatabase(name: tag);
    fileStore = await FileStore.open(folderName: 'webread_$tag');
    final browser = BrowserController();
    final services = AppServices(
      db: db,
      fileStore: fileStore,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: fileStore,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const WebReaderApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// One save waiting for an explicit Start: the quietest state that still puts
  /// the pill on screen, and the one that leaves nothing spinning to settle.
  Future<void> queueOne() => db.upsertQueueTask(
    QueueTask(
      id: 'waiting-1',
      taskType: QueueTaskType.entrySave.name,
      startUrl: 'https://x.example/guide/foo/1',
      captureModeIsUserSet: false,
      state: QueueTaskState.queued.name,
      origin: kQueueOriginQueue,
      orderIndex: 0,
      queuedAt: DateTime.now(),
    ),
  );

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  final pill = find.byKey(const ValueKey('operationIndicator'));

  tearDown(() async {
    await db.close();
  });

  testWidgets('it clears the hardware and the shell it floats over', (
    tester,
  ) async {
    await bootApp(tester);
    expect(pill, findsNothing, reason: 'an idle app says nothing');

    await queueOne();
    await pumpFor(tester, const Duration(seconds: 2));
    expect(pill, findsOneWidget);

    final view = tester.view;
    final insetTop = view.padding.top / view.devicePixelRatio;
    final insetBottom = view.padding.bottom / view.devicePixelRatio;
    final screen = tester.getSize(find.byType(MaterialApp));
    final box = tester.getRect(pill);

    debugPrint(
      '[IND] screen=$screen insetTop=$insetTop insetBottom=$insetBottom '
      'pill=$box',
    );

    expect(
      box.top,
      greaterThanOrEqualTo(insetTop),
      reason: 'never under the status bar, notch or Dynamic Island',
    );
    expect(
      box.top,
      greaterThanOrEqualTo(insetTop + kToolbarHeight),
      reason: 'and never on the row where app-bar actions sit',
    );
    expect(box.right, lessThanOrEqualTo(screen.width));
    expect(box.left, greaterThan(0));
    expect(
      box.height,
      greaterThanOrEqualTo(kHeaderActionSize),
      reason: 'the touch target survives the platform text size',
    );

    // The shell's bottom bar is the one piece of chrome that is always in the
    // same place. Nothing about the pill may reach it.
    expect(
      box.bottom,
      lessThan(screen.height - insetBottom - kShellBottomBarHeight),
    );

    // …and it is clear of the Library header's own actions, which live at the
    // top right of the screen it is floating over.
    final settings = tester.getRect(find.byTooltip('Settings'));
    expect(
      box.top,
      greaterThanOrEqualTo(settings.bottom),
      reason: 'the header owns the top right; the pill starts below it',
    );
  });

  testWidgets('tapping it lands on Activity, and it leaves with the work', (
    tester,
  ) async {
    await bootApp(tester);
    await queueOne();
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(pill);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(find.text('WAITING TO START'), findsOneWidget);

    // The row goes; so does the pill. Proved here rather than only in Dart
    // because this is the real stream, the real database and the real router.
    await db.deleteTerminalQueueTask('waiting-1');
    await db.upsertQueueTask(
      QueueTask(
        id: 'waiting-1',
        taskType: QueueTaskType.entrySave.name,
        startUrl: 'https://x.example/guide/foo/1',
        captureModeIsUserSet: false,
        state: QueueTaskState.cancelled.name,
        origin: kQueueOriginQueue,
        orderIndex: 0,
        queuedAt: DateTime.now(),
        finishedAt: DateTime.now(),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(pill, findsNothing);
  });
}
