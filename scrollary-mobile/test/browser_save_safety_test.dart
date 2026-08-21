import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_presentation.dart';
import 'package:web_reader/browser/history_repository.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';

/// Browser Home, History and the queue, against the save rules (§15, §16).
///
/// The rule under test: **hiding the rendered WebView is leaving the
/// Browser**, whether that is a tab switch, a route push, or a local overlay
/// going up over the page. All three ask the same question, and only when a
/// phase genuinely needs the surface.
void main() {
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;
  late SaveRunController run;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_browser_safety');
    browser = FakeBrowser();
    run = SaveRunController(
      browser: browser,
      db: db,
      fileStore: FileStore(root),
      config: const SaveConfig(),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void inState(SaveState state) {
    run.debugSetRunning(true);
    run.debugSetProgress(
      SaveProgress(
        state: state,
        currentUrl: 'https://x.example/guide/foo/1',
        entryTitle: 'Entry 1',
        storedEntries: 4,
        skippedEntries: 2,
        requestedEntries: 8,
      ),
    );
  }

  /// A guard that records whether it was consulted, and answers [allow].
  Widget guarded({
    required List<String> asked,
    required bool allow,
    required Widget child,
  }) => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      theme: appTheme(),
      home: LeaveBrowserGuard(
        confirm: () async {
          // The shell only asks when a phase is at risk; mirror that here so
          // the test exercises the real predicate.
          if (!run.needsRenderedBrowser) return true;
          asked.add('confirm');
          if (allow) run.pauseForBrowserHidden();
          return allow;
        },
        child: Scaffold(body: child),
      ),
    ),
  );

  group('opening a local surface during a Browser-dependent phase', () {
    for (final state in const [
      SaveState.inspecting,
      SaveState.scrolling,
      SaveState.extracting,
      SaveState.detectingNext,
    ]) {
      testWidgets('${state.name}: opening Home asks first', (tester) async {
        inState(state);
        final asked = <String>[];
        final presentation = BrowserPresentation();
        addTearDown(presentation.dispose);

        await tester.pumpWidget(
          guarded(
            asked: asked,
            allow: true,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  if (await LeaveBrowserGuard.confirmLeave(context)) {
                    presentation.openHome();
                  }
                },
                child: const Text('Home'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(asked, ['confirm']);
        expect(presentation.isHome, isTrue);
        // A hold, not a stop: the run is paused with a named reason.
        expect(run.pauseReason, kPauseBrowserHidden);
      });
    }

    testWidgets('choosing Stay leaves the page on screen and the run running', (
      tester,
    ) async {
      inState(SaveState.scrolling);
      final asked = <String>[];
      final presentation = BrowserPresentation();
      addTearDown(presentation.dispose);

      await tester.pumpWidget(
        guarded(
          asked: asked,
          allow: false,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await LeaveBrowserGuard.confirmLeave(context)) {
                  presentation.openHome();
                }
              },
              child: const Text('Home'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(asked, ['confirm']);
      expect(presentation.isHome, isFalse, reason: 'the page stays visible');
      expect(run.pauseReason, isNull);
    });

    testWidgets('opening full History asks the same question', (tester) async {
      inState(SaveState.extracting);
      final asked = <String>[];
      var pushed = false;

      await tester.pumpWidget(
        guarded(
          asked: asked,
          allow: true,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await LeaveBrowserGuard.confirmLeave(context)) {
                  pushed = true;
                }
              },
              child: const Text('History'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(asked, ['confirm']);
      expect(pushed, isTrue);
    });
  });

  group('when the confirmation must NOT appear', () {
    testWidgets('a queued-only save never warns', (tester) async {
      // Queued is not running: the user may browse, open Home, go to Settings
      // — nothing is at risk because nothing has started (D46).
      await db.upsertQueueTask(
        QueueTask(
          origin: 'queue',
          id: 'q1',
          captureModeIsUserSet: false,
          taskType: QueueTaskType.sequenceSave.name,
          startUrl: 'https://x.example/guide/foo/1',
          entryLimit: 8,
          state: QueueTaskState.queued.name,
          orderIndex: 1,
          queuedAt: DateTime.now(),
        ),
      );
      expect(run.isRunning, isFalse);
      expect(run.needsRenderedBrowser, isFalse);

      final asked = <String>[];
      final presentation = BrowserPresentation();
      addTearDown(presentation.dispose);

      await tester.pumpWidget(
        guarded(
          asked: asked,
          allow: true,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await LeaveBrowserGuard.confirmLeave(context)) {
                  presentation.openHome();
                }
              },
              child: const Text('Home'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(asked, isEmpty, reason: 'nothing is running');
      expect(presentation.isHome, isTrue);
    });

    for (final state in const [SaveState.fetchingAssets, SaveState.saving]) {
      testWidgets('${state.name}: the download-only phase does not warn', (
        tester,
      ) async {
        // After extraction only bytes and manifests remain; the Browser is no
        // longer required, so opening Home must be silent.
        inState(state);
        final asked = <String>[];
        final presentation = BrowserPresentation();
        addTearDown(presentation.dispose);

        await tester.pumpWidget(
          guarded(
            asked: asked,
            allow: true,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  if (await LeaveBrowserGuard.confirmLeave(context)) {
                    presentation.openHome();
                  }
                },
                child: const Text('Home'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(asked, isEmpty);
        expect(presentation.isHome, isTrue);
        expect(run.pauseReason, isNull);
      });
    }

    testWidgets('an already-paused run is not asked about twice', (
      tester,
    ) async {
      inState(SaveState.scrolling);
      run.pauseForBrowserHidden();
      expect(run.needsRenderedBrowser, isFalse);

      final asked = <String>[];
      await tester.pumpWidget(
        guarded(
          asked: asked,
          allow: true,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => LeaveBrowserGuard.confirmLeave(context),
              child: const Text('Home'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(asked, isEmpty);
    });
  });

  group('returning', () {
    test('resuming clears the pause reason and the persisted row', () async {
      inState(SaveState.scrolling);
      await run.debugPersist();
      run.pauseForBrowserHidden();
      await Future<void>.delayed(Duration.zero);

      run.resumeAfterBrowserVisible();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(run.pauseReason, isNull);
      final persisted = await db.findResumableRun();
      expect(persisted?.pauseReason, isNull);
    });
  });

  group('automation never enters manual history', () {
    test('the whole entry chain leaves the history empty', () async {
      final history = HistoryRepository(db);

      // What a save run looks like from the controller's side.
      browser.automationOwner = 'a save run';
      browser.navigationSource = NavigationSource.saveAutomation;
      for (var i = 1; i <= 8; i++) {
        await history.recordVisit(
          url: 'https://x.example/guide/foo/$i',
          title: 'Entry $i',
          source: browser.effectiveNavigationSource,
        );
      }
      browser.automationOwner = null;
      browser.navigationSource = NavigationSource.manual;

      expect(await db.visits(), isEmpty);

      // The user then browses to the same site themselves: that one counts.
      await history.recordVisit(
        url: 'https://x.example/guide/foo/9',
        title: 'Entry 9',
        source: browser.effectiveNavigationSource,
      );
      final rows = await db.visits();
      expect(rows, hasLength(1));
      expect(rows.single.url, 'https://x.example/guide/foo/9');
    });
  });

  group('queued saves are reflected, never started', () {
    test('the Browser only ever counts them', () async {
      final tasks = <QueueTask>[
        QueueTask(
          origin: 'queue',
          id: 'q1',
          captureModeIsUserSet: false,
          taskType: QueueTaskType.sequenceSave.name,
          startUrl: 'https://x.example/1',
          state: QueueTaskState.queued.name,
          orderIndex: 1,
          queuedAt: DateTime.now(),
        ),
        QueueTask(
          origin: 'queue',
          id: 'q2',
          captureModeIsUserSet: false,
          taskType: QueueTaskType.entrySave.name,
          startUrl: 'https://x.example/2',
          state: QueueTaskState.queued.name,
          orderIndex: 2,
          queuedAt: DateTime.now(),
        ),
        QueueTask(
          origin: 'queue',
          id: 'q3',
          captureModeIsUserSet: false,
          taskType: QueueTaskType.collectionCheck.name,
          state: QueueTaskState.queued.name,
          orderIndex: 3,
          queuedAt: DateTime.now(),
        ),
      ];
      // The chip counts save work only — a queued check is not something
      // the user has to start.
      expect(QueueSummary.of(tasks).queuedSaves, 2);
    });
  });
}
