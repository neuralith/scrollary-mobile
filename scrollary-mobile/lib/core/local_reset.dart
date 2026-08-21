import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show TableInfo;
import 'package:flutter/foundation.dart';

import '../browser/browser_controller.dart';
import '../capability/internal_build.dart';

import '../save/save_run.dart';
import '../library/update_checker.dart';
import '../queue/task_queue.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';

/// Whether the destructive development reset may be shown at all.
///
/// A **compile-time** constant, not a setting, a gesture or a flavour string
/// that could be typo'd into production (D50). Every entry point checks it, and
/// the widget test asserts a normal release build has no way in.
///
/// `kDebugMode` alone would have been too narrow: profile and release builds
/// are exactly where device performance, energy and accessibility work happens,
/// and that work needs these tools. So an internal build is either debug or one
/// launched with `--dart-define=SCROLLARY_INTERNAL_BUILD=true`. A Store build
/// passes neither, both halves fold to `false` at compile time, and the screens
/// and routes are tree-shaken out. See lib/capability/internal_build.dart.
bool get developerToolsAvailable => kInternalBuild;

/// One area of the wipe, and whether it worked.
class ResetStep {
  ResetStep(this.area, {this.detail = '', this.error});

  final String area;
  final String detail;
  final Object? error;

  bool get ok => error == null;

  @override
  String toString() =>
      '${ok ? 'ok' : 'FAILED'}  $area${detail.isEmpty ? '' : ' — $detail'}'
      '${error == null ? '' : ' — $error'}';
}

/// What a reset actually did, area by area.
///
/// A single bool would let a half-finished wipe report success, which is the
/// one thing a "start clean" button must never do. The dev screen prints this
/// verbatim.
class ResetReport {
  ResetReport(this.steps);

  final List<ResetStep> steps;

  bool get ok => steps.every((s) => s.ok);
  List<ResetStep> get failures => [
    for (final s in steps)
      if (!s.ok) s,
  ];

  String get summary => ok
      ? 'Reset complete · ${steps.length} areas cleared'
      : 'Reset INCOMPLETE · ${failures.length} of ${steps.length} areas failed';

  @override
  String toString() => [summary, ...steps.map((s) => '  $s')].join('\n');
}

/// Returns the app to a first-launch state without an uninstall.
///
/// **Development only.** Guarded by [developerToolsAvailable] at every entry
/// point; this class exists to make "start from nothing" a two-second action
/// while the product is being built.
///
/// ### Why the database file is emptied rather than deleted
///
/// Deleting the file means disposing the live `AppDatabase` — and every
/// provider, stream and service in the running app holds it. Tearing that
/// graph down mid-session and rebuilding it is exactly the kind of
/// half-initialised state that produces bugs which look like product bugs.
/// Emptying every table inside one transaction, then `VACUUM`, gives the user
/// the same observable result (empty library, empty queue, default settings,
/// reclaimed disk) with live streams that simply emit empty — so the UI walks
/// itself back to the first-launch screen with no restart (D49).
class LocalResetService {
  LocalResetService({
    required this.db,
    required this.fileStore,
    required this.browser,
    required this.saveRun,
    required this.checker,
    required this.taskQueue,
    this.clearCookies,
  });

  final AppDatabase db;
  final FileStore fileStore;
  final BrowserController browser;
  final SaveRunController saveRun;
  final UpdateChecker checker;
  final TaskQueueController taskQueue;

  /// The WebView cookie store in the app; a spy in tests. Null means "this
  /// build has no cookie store", which is reported as skipped rather than
  /// silently counted as cleared.
  final Future<void> Function()? clearCookies;

  /// The order matters: stop the machines, then the rows, then the bytes.
  ///
  /// Files last on purpose — a crash between the two leaves orphaned files
  /// that startup recovery already knows how to sweep, whereas orphaned rows
  /// pointing at deleted files would surface as broken entries.
  Future<ResetReport> resetEverything() async {
    final steps = <ResetStep>[];

    steps.add(await _step('active work', _stopEverything));
    steps.add(await _step('database rows', _wipeDatabase));
    steps.add(await _step('saved files', _wipeFiles));
    steps.add(await _step('browser session', _wipeBrowserSession));

    final report = ResetReport(steps);
    debugPrint('[reset] $report');
    return report;
  }

  Future<ResetStep> _step(String area, Future<String> Function() body) async {
    try {
      return ResetStep(area, detail: await body());
    } catch (e) {
      return ResetStep(area, error: e);
    }
  }

  /// Nothing may be mid-write when the tables go.
  Future<String> _stopEverything() async {
    taskQueue.ensureBrowserVisible = null;
    await taskQueue.stopQueuedSaves();
    saveRun.stop();
    checker.cancel();
    browser.automationOwner = null;
    // Let the stop propagate through the running loops before the rows they
    // are writing to disappear underneath them.
    for (var i = 0; i < 40 && saveRun.isRunning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return saveRun.isRunning
        ? 'save still winding down'
        : 'queue stopped, browser released';
  }

  /// Every table, in one transaction. Listed from the schema rather than by
  /// name so a table added later cannot be quietly missed.
  ///
  /// Foreign keys are suspended for the wipe. `entries` references
  /// `collections`, so deleting in schema order trips constraint 787 — and
  /// relying on declaration order to happen to be dependency order is the
  /// kind of thing that breaks silently the next time a table is added.
  /// The pragma is a no-op inside a transaction, hence outside it.
  Future<String> _wipeDatabase() async {
    final tables = db.allTables.toList();
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction(() async {
        for (final TableInfo table in tables.reversed) {
          await db.delete(table).go();
        }
      });
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
    // Give the space back, so "reset" is visible in the storage figure too.
    try {
      await db.customStatement('VACUUM');
    } catch (_) {
      // Vacuum is a courtesy; a locked database is not a failed reset.
    }
    return '${tables.length} tables emptied';
  }

  /// The whole asset tree: committed entries, staging, and the `.previous`
  /// backups a replacement leaves behind.
  Future<String> _wipeFiles() async {
    final root = fileStore.rootDir;
    if (!root.existsSync()) return 'nothing on disk';
    var removed = 0;
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
      removed++;
    }
    // Put the empty skeleton back so the next save does not have to.
    Directory(
      '${root.path}/${FileStore.libraryFolderName}',
    ).createSync(recursive: true);
    Directory(
      '${root.path}/${FileStore.tmpFolderName}',
    ).createSync(recursive: true);
    return '$removed entr${removed == 1 ? 'y' : 'ies'} deleted';
  }

  /// Cookies and cached web session state. Application-owned: these are the
  /// logins the app's own WebView made, not anything the OS shares.
  Future<String> _wipeBrowserSession() async {
    final clear = clearCookies;
    if (clear == null) return 'skipped (no cookie store)';
    await clear();
    return 'cookies cleared';
  }
}
