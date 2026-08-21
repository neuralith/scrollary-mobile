import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// Leaving the Browser mid-save: which phases are actually at risk, what
/// pausing persists, and what returning restores.
void main() {
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;
  late SaveRunController run;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_leave');
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

  /// Put the controller in a given running state without a real run.
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

  group('which phases need the Browser', () {
    for (final state in const [
      SaveState.inspecting,
      SaveState.scrolling,
      SaveState.waitingForAssets,
      SaveState.verifying,
      SaveState.extracting,
      SaveState.detectingNext,
      SaveState.navigating,
    ]) {
      test('${state.name} does need it', () {
        inState(state);
        expect(run.needsRenderedBrowser, isTrue);
      });
    }

    for (final state in const [SaveState.fetchingAssets, SaveState.saving]) {
      test('${state.name} does NOT — bytes over HTTP touch no layout', () {
        inState(state);
        expect(
          run.needsRenderedBrowser,
          isFalse,
          reason: 'the modal must not cry wolf during downloads',
        );
      });
    }

    test('an idle controller never needs it', () {
      expect(run.needsRenderedBrowser, isFalse);
    });

    test('an already-paused run never asks again', () {
      inState(SaveState.scrolling);
      run.pauseForBrowserHidden();
      expect(run.needsRenderedBrowser, isFalse);
    });
  });

  test('pausing records the reason and stops nothing else', () {
    inState(SaveState.scrolling);
    run.pauseForBrowserHidden();

    expect(run.pauseReason, kPauseBrowserHidden);
    expect(run.isRunning, isTrue, reason: 'held, not stopped');
    expect(
      run.log.join('\n'),
      contains('Browser was left'),
      reason: 'the reason is visible, not silent',
    );
  });

  test('the pause reason is persisted on the run row', () async {
    inState(SaveState.scrolling);
    await run.debugPersist();
    run.pauseForBrowserHidden();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final row = await db.findResumableRun();
    expect(row, isNotNull);
    expect(row!.pauseReason, kPauseBrowserHidden);
  });

  test('returning to the Browser clears the pause', () async {
    inState(SaveState.scrolling);
    await run.debugPersist();
    run.pauseForBrowserHidden();
    expect(run.pauseReason, kPauseBrowserHidden);

    run.resumeAfterBrowserVisible();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(run.pauseReason, isNull);
    expect(run.log.join('\n'), contains('Browser is visible again'));
    final row = await db.findResumableRun();
    expect(row?.pauseReason, isNull);
  });

  test('resuming only lifts a browser-hidden pause', () {
    inState(SaveState.scrolling);
    run.pause(); // a plain user pause
    expect(run.pauseReason, isNull);

    run.resumeAfterBrowserVisible();
    // Nothing to lift: the user's own pause is untouched by the browser
    // lifecycle.
    expect(run.pauseReason, isNull);
  });

  test('the leave dialog gets a truthful progress line', () {
    inState(SaveState.scrolling);
    final line = run.progressSummary;
    expect(line, contains('Entry 1'));
    expect(line, contains('4 saved'));
    expect(line, contains('2 skipped'));
    expect(line, contains('4 remaining'));
  });
}
