import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../browser/browser_controller.dart';
import '../save/capture_mode.dart';
import '../save/capture_policy.dart';
import '../save/save_run.dart';
import '../core/config.dart';
import '../core/url_utils.dart';
import '../save/save_preflight.dart';
import '../save/save_state.dart';
import '../save/stop_conditions.dart';
import '../library/collection_identity.dart';
import '../library/library_check.dart';
import '../library/update_checker.dart';
import '../storage/cleanup.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';

const _uuid = Uuid();

/// What a queue entry does.
///
/// Nothing writes `checkAllCollections`: a library-wide check expands into one
/// `collectionCheck` row per collection ([enqueueLibraryCheck]) rather than one
/// opaque mega-task, so progress, failure and cancellation are the queue's own
/// per-collection semantics. The value is kept because rows written by older
/// builds may still carry it, and it is handled exactly like `collectionCheck`
/// wherever it appears.
enum QueueTaskType {
  entrySave,
  sequenceSave,
  collectionCheck,
  checkAllCollections,

  /// Bulk offline-file removal (a whole collection, or every finished entry).
  /// Removal is never metadata deletion; see [CleanupService].
  removeOfflineFiles,
}

QueueTaskType queueTaskTypeFromName(String name) =>
    QueueTaskType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => QueueTaskType.collectionCheck,
    );

/// What a removeOfflineFiles task targets, encoded in `startUrl` (the column
/// is free-form text; a cleanup task has no URL): `collection` uses
/// collectionId; `finishedEverywhere` sweeps every completed offline
/// entry in the active library.
const kCleanupScopeCollection = 'cleanup:collection';
const kCleanupScopeFinished = 'cleanup:finishedEverywhere';

enum QueueTaskState { queued, running, completed, failed, cancelled }

/// `queue_tasks.origin` values (D58). Ordinary queued work carries
/// [kQueueOriginQueue]; a row written for a save the user started straight
/// from the Browser carries [kQueueOriginDirect] and is always terminal.
const kQueueOriginQueue = 'queue';
const kQueueOriginDirect = 'direct';

bool isDirectOriginTask(QueueTask task) => task.origin == kQueueOriginDirect;

/// Is there a save request still *waiting* for this exact page?
///
/// Queued rows only. A running one is the run's business (the Browser reads
/// that from the run itself), and a terminal one is history — an entry
/// saved last week must not make today's page look "queued" (D59).
bool pageHasQueuedSave(List<QueueTask> tasks, String pageKey) {
  if (pageKey.isEmpty) return false;
  for (final task in tasks) {
    if (task.state != QueueTaskState.queued.name) continue;
    if (!taskWaitsForExplicitStart(queueTaskTypeFromName(task.taskType))) {
      continue;
    }
    final url = task.startUrl;
    if (url != null && pageIdentityKey(url) == pageKey) return true;
  }
  return false;
}

/// Whether a save task is Browser-dependent from the queue's point of
/// view. Checks drive the WebView too; cleanup never does.
bool taskNeedsBrowser(QueueTaskType type) => switch (type) {
  QueueTaskType.entrySave ||
  QueueTaskType.sequenceSave ||
  QueueTaskType.collectionCheck ||
  QueueTaskType.checkAllCollections => true,
  QueueTaskType.removeOfflineFiles => false,
};

/// Update-check work, of either granularity. One predicate rather than the
/// same two-armed `||` repeated wherever checks have to be told apart from
/// saves and cleanup.
bool isCheckTask(QueueTaskType type) =>
    type == QueueTaskType.collectionCheck ||
    type == QueueTaskType.checkAllCollections;

/// Save is the only work that waits for an explicit start.
///
/// Update checks and cleanup are cheap, bounded, and already user-initiated
/// per action; making them wait behind a second confirmation would be
/// ceremony. Save is the one that opens the Browser, holds it for minutes
/// and downloads megabytes — so it is the one the user gets to batch up and
/// start deliberately (D46).
bool taskWaitsForExplicitStart(QueueTaskType type) =>
    type == QueueTaskType.entrySave || type == QueueTaskType.sequenceSave;

/// Why a direct start did not begin. `started` is the only success.
enum DirectStartResult {
  started,

  /// Something else already owns the WebView (a save, an update check).
  /// Not an error — the queue is still open to the same request.
  browserBusy,

  /// The Browser could not be brought forward / has no attached WebView.
  browserUnavailable,

  /// No page to save.
  noPage,

  /// The address is on a commercial content service this app does not save
  /// from (`save/capture_policy.dart`). Browsing it is unaffected.
  restrictedSite,
}

/// What [TaskQueueController.cancelTask] did (D64).
///
/// Four outcomes rather than void, because "it had already started" and "it
/// never started" are different things to tell the user, and because a tap
/// that lost the race with the pump must not be reported as a clean removal.
enum CancelResult {
  /// It was still waiting; it is now a cancelled history row and will not run.
  cancelledBeforeStart,

  /// It was already running. The worker has been asked to stop at its next
  /// safe boundary; the row is cancelled from this moment on.
  stoppingRunning,

  /// Already terminal — there was nothing left to cancel.
  alreadyFinished,

  /// No such row (pruned, cleared, or cancelled by something else first).
  gone,
}

/// Whatever is holding the shared WebView right now, named for the UI.
class BrowserOwnerState {
  const BrowserOwnerState({
    required this.label,
    required this.pageKey,
    required this.needsBrowser,
  });

  /// "A save is running", "An update check is running".
  final String label;

  /// Canonical identity of the page it is working on; empty when unknown.
  final String pageKey;

  /// True while it genuinely needs the rendered surface. False during a
  /// download/save phase, when it is only moving bytes.
  final bool needsBrowser;
}

/// What [TaskQueueController.enqueueSave] did.
///
/// `alreadyQueued` is not a failure: the entry is in the queue, which is
/// what the user wanted. It exists so the caller can say "already in the
/// queue" instead of a second "added".
class QueueEnqueueResult {
  const QueueEnqueueResult({
    required this.id,
    required this.alreadyQueued,
    this.restricted = false,
  });

  /// Nothing was queued: the address is on a restricted service. No row is
  /// written, so there is nothing to start, retry or clean up later.
  const QueueEnqueueResult.restricted()
    : id = '',
      alreadyQueued = false,
      restricted = true;

  final String id;
  final bool alreadyQueued;

  /// True when the request was refused by the restricted-site capture policy.
  final bool restricted;
}

/// The counts the Activity screen and the Library strip both quote.
class QueueSummary {
  const QueueSummary({
    required this.queuedSaves,
    required this.queuedOther,
    required this.running,
    required this.failed,
    required this.completed,
    required this.cancelled,
  });

  final int queuedSaves;
  final int queuedOther;
  final int running;
  final int failed;
  final int completed;
  final int cancelled;

  int get queued => queuedSaves + queuedOther;
  int get remaining => queued + running;
  bool get hasQueuedSaves => queuedSaves > 0;

  factory QueueSummary.of(List<QueueTask> tasks) {
    var qc = 0, qo = 0, r = 0, f = 0, c = 0, x = 0;
    for (final t in tasks) {
      switch (queueTaskStateFromName(t.state)) {
        case QueueTaskState.queued:
          if (taskWaitsForExplicitStart(queueTaskTypeFromName(t.taskType))) {
            qc++;
          } else {
            qo++;
          }
        case QueueTaskState.running:
          r++;
        case QueueTaskState.failed:
          f++;
        case QueueTaskState.completed:
          c++;
        case QueueTaskState.cancelled:
          x++;
      }
    }
    return QueueSummary(
      queuedSaves: qc,
      queuedOther: qo,
      running: r,
      failed: f,
      completed: c,
      cancelled: x,
    );
  }
}

QueueTaskState queueTaskStateFromName(String name) => QueueTaskState.values
    .firstWhere((s) => s.name == name, orElse: () => QueueTaskState.failed);

/// How one task run ended, as the scheduler records it.
class QueueOutcome {
  const QueueOutcome.success(this.summary) : failed = false;
  const QueueOutcome.failure(this.summary) : failed = true;

  final String summary;
  final bool failed;
}

/// Schedules autonomous work — it never performs any.
///
/// The design line that keeps this from becoming a second run system: the
/// queue owns *ordering, persistence and history*; the work itself stays in
/// [SaveRunController] and [UpdateChecker], which already know how to
/// save, check, pause, and clean up after themselves. One task runs at a
/// time — the shared WebView (`automationOwner`) makes concurrency structurally
/// impossible anyway, so the scheduler simply respects that.
///
/// Restart semantics: queued work is **offered, never auto-resumed**
/// ([OPEN_QUESTIONS.md] Q24) — the same rule the interrupted-save card has
/// always followed. Nothing navigates a WebView at launch because a row said
/// so yesterday.
class TaskQueueController extends ChangeNotifier {
  TaskQueueController({
    required this.db,
    required this.saveRun,
    required this.checker,
    required this.browser,
    CleanupService? cleanup,
    this.historyLimit = 50,
    @visibleForTesting this.saveRunner,
    @visibleForTesting this.checkRunner,
  }) : cleanup =
           cleanup ??
           CleanupService(
             db: db,
             fileStore: FileStore(Directory.systemTemp),
             saveRun: saveRun,
           ) {
    // The pump defers while someone else owns the WebView (a resumed save,
    // a directly-started check). Ownership release does not notify by itself,
    // but both controllers notify at the end of their runs — after clearing
    // the owner — so listening to them closes the stall: queued work drains
    // as soon as the browser frees, not at the next enqueue.
    saveRun.addListener(_maybePump);
    checker.addListener(_maybePump);
  }

  @override
  void dispose() {
    saveRun.removeListener(_maybePump);
    checker.removeListener(_maybePump);
    super.dispose();
  }

  void _maybePump() {
    if (_pumping || _resumeOffered) return;
    // A direct save has claimed the Browser but may not have taken
    // `automationOwner` yet (start() does a disk check first). Without this the
    // pump could slip a queued check in through that window and the direct
    // start would then refuse itself.
    if (_directSaveClaimed) return;
    if (browser.automationOwner != null) return;
    unawaited(_pump());
  }

  /// Is this entry already spoken for?
  ///
  /// Matches on the normalised start URL across queued and running save
  /// rows only. History is deliberately excluded: an entry saved last
  /// week must not block an intentional re-fetch today.
  Future<QueueTask?> pendingSaveFor(String startUrl) async {
    final key = normalizeUrl(startUrl);
    if (key.isEmpty) return null;
    final pending = await db.pendingQueueTasks();
    for (final task in pending) {
      if (!taskWaitsForExplicitStart(queueTaskTypeFromName(task.taskType))) {
        continue;
      }
      final url = task.startUrl;
      if (url != null && normalizeUrl(url) == key) return task;
    }
    return null;
  }

  final AppDatabase db;
  final SaveRunController saveRun;
  final UpdateChecker checker;
  final BrowserController browser;
  final CleanupService cleanup;
  final int historyLimit;

  /// Test seams: replace the real work while keeping the real scheduler.
  final Future<QueueOutcome> Function(QueueTask task)? saveRunner;
  final Future<QueueOutcome> Function(QueueTask task)? checkRunner;

  bool _pumping = false;
  bool get isRunning => _pumping;

  String? _runningTaskId;
  String? get runningTaskId => _runningTaskId;

  /// True after construction when persisted queued work exists but has not
  /// been resumed. The UI offers a single "resume queue" action; nothing
  /// runs until it is taken (or new work is enqueued, which is fresh user
  /// intent).
  bool _resumeOffered = false;
  bool get resumeOffered => _resumeOffered;

  final Set<String> _cancelRequested = {};

  /// True between "the user pressed Start Save" and the save queue
  /// running dry.
  ///
  /// **Not persisted, deliberately.** Queued rows survive a restart; the
  /// permission to drive the Browser does not. A relaunch that resumed
  /// scrolling because a row existed yesterday is exactly what Q24 forbids,
  /// and D46 makes it a product rule rather than an accident of timing.
  bool _saveStartAuthorised = false;
  bool get saveStartAuthorised => _saveStartAuthorised;

  /// True from "the user pressed Start Save in the Browser" until that one
  /// run ends.
  ///
  /// Deliberately **not** [_saveStartAuthorised]: a direct save is one
  /// run the user pointed at, not permission to drain the queue behind it
  /// (D58). Pending saves stay pending, in their existing order, and are
  /// released only by [startQueuedSaves] / [startQueuedTask].
  bool _directSaveClaimed = false;
  bool get directSaveRunning => _directSaveClaimed;

  /// Asked before a Browser-dependent task runs: bring the Browser forward
  /// and tell us whether its WebView is actually there.
  ///
  /// Injected by the shell, which is the thing that owns tab switching. Null
  /// in tests and headless contexts, where it degrades to "assume visible" —
  /// the save engine's own render guard is the real safety net, this is
  /// the *navigation*.
  ///
  /// [url], when given, is the page the work is about to open. Passing it is
  /// what makes the Browser show *that* page: selecting the tab alone leaves
  /// whatever was there on screen — including Browser Home or the address
  /// editor, which cover the WebView entirely — so the user watches the wrong
  /// thing while automation drives the right one. The shell routes it through
  /// the same `BrowserNavigator` every "open in Browser" action uses.
  Future<bool> Function({String? url})? ensureBrowserVisible;

  /// Queued save work the user has not started yet.
  Future<List<QueueTask>> queuedSaves() async {
    final pending = await db.pendingQueueTasks();
    return [
      for (final t in pending)
        if (t.state == QueueTaskState.queued.name &&
            taskWaitsForExplicitStart(queueTaskTypeFromName(t.taskType)))
          t,
    ];
  }

  /// The user pressed Start Save. Authorises Browser automation for the
  /// queued saves and starts draining; returns how many were released.
  Future<int> startQueuedSaves() async {
    final waiting = await queuedSaves();
    if (waiting.isEmpty) return 0;
    _saveStartAuthorised = true;
    _resumeOffered = false;
    notifyListeners();
    unawaited(_pump());
    return waiting.length;
  }

  /// Start one queued save ahead of the rest: it moves to the front, and
  /// the queue is authorised as if Start Save had been pressed.
  Future<bool> startQueuedTask(String id) async {
    final task = await db.queueTaskById(id);
    if (task == null || task.state != QueueTaskState.queued.name) return false;
    // A row queued before this host joined the policy does not get to jump the
    // queue into a run. It is settled here instead, exactly as the pump would.
    if (await _settleIfRestricted(task)) return false;
    await moveQueuedToFront(id);
    _saveStartAuthorised = true;
    _resumeOffered = false;
    notifyListeners();
    unawaited(_pump());
    return true;
  }

  // --- direct save (D58) --------------------------------------------------

  /// Who owns the shared WebView right now, or null when it is free.
  ///
  /// One driver at a time is structural — there is one WebView and one
  /// [SaveRunController] — so this is what the save sheet consults before
  /// offering **Start Save** at all.
  BrowserOwnerState? get browserOwner {
    if (saveRun.hasActiveRun) {
      return BrowserOwnerState(
        label: saveRun.isPaused
            ? 'A save is paused'
            : (saveRun.needsRenderedBrowser
                  ? 'A save is using the Browser'
                  : 'A save is finishing its downloads'),
        pageKey: saveRun.activePageKey,
        needsBrowser: saveRun.needsRenderedBrowser,
      );
    }
    if (checker.isRunning) {
      return const BrowserOwnerState(
        label: 'An update check is using the Browser',
        pageKey: '',
        needsBrowser: true,
      );
    }
    // Something took the WebView without going through either controller.
    final owner = browser.automationOwner;
    if (owner != null) {
      return BrowserOwnerState(
        label: 'The Browser is busy with $owner',
        pageKey: '',
        needsBrowser: true,
      );
    }
    return null;
  }

  /// Save [startUrl] **now**, in the Browser the user is looking at.
  ///
  /// Creates no queue row: nothing is added to the pending queue, nothing
  /// already queued is released, reordered or consumed, and the batch
  /// authorisation is untouched (D58). The persistent `save_runs` record is
  /// still written — that is what progress, pause, recovery and resume stand
  /// on — and a **terminal** queue row is written when the run ends, so the
  /// result appears in Activity history like any other work.
  ///
  /// Returns as soon as the run has begun; the run itself is observable on
  /// [saveRun], never awaited by the caller.
  Future<DirectStartResult> startDirectSave({
    required String startUrl,
    required int entryLimit,
    DuplicatePolicy policy = DuplicatePolicy.ask,
    SaveScope range = SaveScope.fixedCount,
    String? collectionId,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
    bool rememberForCollection = false,
  }) async {
    if (startUrl.trim().isEmpty) return DirectStartResult.noPage;
    // Asked before the WebView is claimed, so a refusal leaves the Browser
    // exactly as the user left it.
    if (isCaptureRestricted(startUrl)) return DirectStartResult.restrictedSite;
    if (_directSaveClaimed || browserOwner != null) {
      return DirectStartResult.browserBusy;
    }
    // Claimed before the first await: two taps in the same frame must not both
    // get through, and the pump must not take the WebView in between.
    _directSaveClaimed = true;
    notifyListeners();

    // Rendered-Browser validation before anything starts (D47): the same hook
    // the queue uses, so a direct start cannot skip the step queued work takes.
    final ready = await ensureBrowserVisible?.call() ?? browser.isAttached;
    if (!ready) {
      _directSaveClaimed = false;
      notifyListeners();
      return DirectStartResult.browserUnavailable;
    }

    unawaited(
      _runDirect(
        collectionId: collectionId,
        startUrl: startUrl,
        entryLimit: entryLimit,
        range: range,
        run: () => saveRun.start(
          entryLimit: entryLimit,
          startUrl: startUrl,
          policy: policy,
          range: range,
          captureMode: captureMode,
          captureModeIsUserSet: captureModeIsUserSet,
          rememberForCollection: rememberForCollection,
          origin: SaveOrigin.direct,
        ),
      ),
    );
    return DirectStartResult.started;
  }

  /// Resume an interrupted run. A direct save resumes **directly**; it is
  /// never converted into a pending queue task (D58).
  Future<DirectStartResult> resumeInterruptedSave(SaveRun run) async {
    // A run interrupted before the policy existed — or before this host joined
    // it — must not come back through the resume door. Both ends are checked:
    // where it would continue from, and where it originally began.
    if (isCaptureRestricted(run.currentUrl) ||
        isCaptureRestricted(run.startUrl)) {
      return DirectStartResult.restrictedSite;
    }
    if (_directSaveClaimed || browserOwner != null) {
      return DirectStartResult.browserBusy;
    }
    _directSaveClaimed = true;
    notifyListeners();
    final ready = await ensureBrowserVisible?.call() ?? browser.isAttached;
    if (!ready) {
      _directSaveClaimed = false;
      notifyListeners();
      return DirectStartResult.browserUnavailable;
    }
    unawaited(
      _runDirect(
        collectionId: run.collectionId,
        startUrl: run.currentUrl ?? run.startUrl,
        entryLimit: run.requestedEntries,
        range: saveScopeFromName(run.scope),
        resumed: true,
        run: () => saveRun.resumeRun(run),
      ),
    );
    return DirectStartResult.started;
  }

  /// Run a direct save and record how it ended.
  Future<void> _runDirect({
    required String startUrl,
    required int entryLimit,
    required SaveScope range,
    required Future<void> Function() run,
    String? collectionId,
    bool resumed = false,
  }) async {
    try {
      await run();
    } catch (e) {
      await _recordDirectOutcome(
        startUrl: startUrl,
        entryLimit: entryLimit,
        range: range,
        collectionId: collectionId,
        resumed: resumed,
        outcome: QueueOutcome.failure(e.toString()),
      );
      return;
    } finally {
      _directSaveClaimed = false;
      notifyListeners();
      // The Browser is free again. Work that drains on its own (checks,
      // cleanup) may now run; pending *saves* still may not — they are
      // released by an explicit Start and by nothing else (D46, D58).
      _maybePump();
    }
    final p = saveRun.progress;
    final summary =
        '${p.storedEntries} saved'
        '${p.skippedEntries > 0 ? ', ${p.skippedEntries} skipped' : ''}';
    await _recordDirectOutcome(
      startUrl: startUrl,
      entryLimit: entryLimit,
      range: range,
      collectionId: collectionId,
      resumed: resumed,
      outcome: p.state == SaveState.failed
          ? QueueOutcome.failure(p.lastError ?? summary)
          : QueueOutcome.success(
              p.state == SaveState.cancelled ? 'stopped · $summary' : summary,
            ),
      cancelled: p.state == SaveState.cancelled,
    );
  }

  /// One **terminal** row for a direct run — history, never a plan.
  Future<void> _recordDirectOutcome({
    required String startUrl,
    required int entryLimit,
    required SaveScope range,
    required QueueOutcome outcome,
    String? collectionId,
    bool resumed = false,
    bool cancelled = false,
    CaptureMode? captureMode,
    int? maxBytes,
    StopReason? stopReason,
  }) async {
    final now = DateTime.now();
    await db.upsertQueueTask(
      QueueTask(
        id: _uuid.v4(),
        taskType: range != SaveScope.currentPageOnly && entryLimit > 1
            ? QueueTaskType.sequenceSave.name
            : QueueTaskType.entrySave.name,
        collectionId: collectionId,
        startUrl: startUrl,
        entryLimit: entryLimit,
        maxBytes: maxBytes,
        captureMode: captureMode?.name,
        captureModeIsUserSet: false,
        scope: range.name,
        stopReason: stopReason?.name,
        origin: kQueueOriginDirect,
        state: cancelled
            ? QueueTaskState.cancelled.name
            : (outcome.failed
                  ? QueueTaskState.failed.name
                  : QueueTaskState.completed.name),
        outcome: resumed ? 'resumed · ${outcome.summary}' : outcome.summary,
        lastError: outcome.failed ? outcome.summary : null,
        orderIndex: await db.nextQueueOrderIndex(),
        queuedAt: now,
        startedAt: now,
        finishedAt: DateTime.now(),
      ),
    );
    await db.pruneQueueHistory(keep: historyLimit);
    notifyListeners();
  }

  /// Stop the batch: the running task is asked to stop and the remaining
  /// queued saves go back to waiting. They are **not** cancelled — the
  /// user stopped the run, not the plan.
  Future<void> stopQueuedSaves() async {
    _saveStartAuthorised = false;
    final id = _runningTaskId;
    if (id != null) await cancelTask(id);
    notifyListeners();
  }

  /// Call once at startup: discovers leftover work and turns it into an
  /// offer. A row left `running` by a kill is demoted to `queued` — it never
  /// ran to completion, and it must not pretend it did.
  Future<void> restore() async {
    final pending = await db.pendingQueueTasks();
    for (final task in pending.where((t) => t.state == 'running')) {
      await db.upsertQueueTask(
        task.copyWith(state: 'queued', startedAt: const Value(null)),
      );
    }
    _resumeOffered = pending.isNotEmpty;
    notifyListeners();
  }

  /// The user accepted the resume offer. Starts the pump and returns — the
  /// queue drains in the background; progress is observable, not awaited.
  void resumeQueue() {
    _resumeOffered = false;
    notifyListeners();
    unawaited(_pump());
  }

  // --- enqueueing -----------------------------------------------------------

  /// Add a save request. It **waits** — nothing navigates, nothing
  /// scrolls, no WebView is touched until the user starts the queue (D46).
  ///
  /// Deduplicated against queued and running save rows by start URL, so a
  /// second tap on the same entry reports "already queued" rather than
  /// stacking an identical run behind the first.
  Future<QueueEnqueueResult> enqueueSave({
    required String startUrl,
    required int entryLimit,
    String? collectionId,
    DuplicatePolicy policy = DuplicatePolicy.ask,
    // The safe default, so a caller that forgets to say saves one page.
    SaveScope range = SaveScope.currentPageOnly,
    int? maxBytes,

    /// What to produce. Null means the page had not been analysed when this
    /// was queued, so the run decides per page from detection.
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    // No row is written for a restricted address. Queueing one and failing it
    // later would leave a permanently-failing record the user has to tidy up,
    // for a request that was never going to run.
    if (isCaptureRestricted(startUrl)) {
      return const QueueEnqueueResult.restricted();
    }
    final existing = await pendingSaveFor(startUrl);
    if (existing != null) {
      return QueueEnqueueResult(id: existing.id, alreadyQueued: true);
    }
    final id = await _enqueue(
      QueueTask(
        id: _uuid.v4(),
        taskType: range != SaveScope.currentPageOnly && entryLimit > 1
            ? QueueTaskType.sequenceSave.name
            : QueueTaskType.entrySave.name,
        collectionId: collectionId,
        startUrl: startUrl,
        entryLimit: entryLimit,
        maxBytes: maxBytes,
        captureMode: captureMode?.name,
        captureModeIsUserSet: captureModeIsUserSet,
        duplicatePolicy: policy.name,
        scope: range.name,
        origin: kQueueOriginQueue,
        state: QueueTaskState.queued.name,
        orderIndex: 0, // assigned in _enqueue
        queuedAt: DateTime.now(),
      ),
    );
    return QueueEnqueueResult(id: id, alreadyQueued: false);
  }

  /// Queue a set of entries for save, oldest first.
  ///
  /// [entries] arrives in whatever order the screen was displaying — which
  /// is usually newest-first — and is re-sorted into **reading order** here.
  /// Save walks forward through a collection; queueing 490, 489, 488 in that
  /// order would fight the chain-following the engine does on its own.
  ///
  /// Each entry becomes its own single-entry task against its own stored
  /// URL, so one bad page cannot strand the rest, and every row keeps its
  /// existing entry record (D48).
  Future<BatchQueueResult> enqueueEntries(
    List<Entry> entries, {
    DuplicatePolicy policy = DuplicatePolicy.replaceAll,
  }) async {
    final ordered = sortEntriesForSaveOrder(entries);
    final queued = <String>[];
    final already = <Entry>[];
    final noSource = <Entry>[];
    final restricted = <Entry>[];

    for (final entry in ordered) {
      if (!entryHasCapturableUrl(entry)) {
        noSource.add(entry);
        continue;
      }
      final result = await enqueueSave(
        startUrl: entry.sourceUrl.trim(),
        entryLimit: 1,
        collectionId: entry.collectionId,
        policy: policy,
        range: SaveScope.currentPageOnly,
      );
      if (result.restricted) {
        // Counted and reported, never silently dropped — and the entry itself,
        // its files and its reading state are untouched.
        restricted.add(entry);
      } else if (result.alreadyQueued) {
        already.add(entry);
      } else {
        queued.add(result.id);
      }
    }
    return BatchQueueResult(
      queuedIds: queued,
      alreadyQueued: already,
      missingSource: noSource,
      restricted: restricted,
    );
  }

  /// Idempotent per collection: a check is a metadata read, so a second tap while
  /// one is already queued or running for the same collection returns the
  /// existing task instead of stacking a duplicate behind it.
  /// Returns the task id, or **null** when the collection's source is on a
  /// restricted service: an update check discovers entries in order to save
  /// them, so it is capture work and is refused with everything else.
  Future<String?> enqueueCollectionCheck(String collectionId) async {
    if (await _collectionIsRestricted(collectionId)) return null;
    final pending = await db.pendingQueueTasks();
    final existing = pending
        .where(
          (t) =>
              t.taskType == QueueTaskType.collectionCheck.name &&
              t.collectionId == collectionId,
        )
        .firstOrNull;
    if (existing != null) {
      // Re-offer nothing, but make sure a queued row actually gets pumped.
      _maybePump();
      return existing.id;
    }
    return _enqueue(
      QueueTask(
        id: _uuid.v4(),
        taskType: QueueTaskType.collectionCheck.name,
        captureModeIsUserSet: false,
        collectionId: collectionId,
        // Metadata only: a check never writes a file, so there is nothing to
        // capture and no storage ceiling to apply.
        origin: kQueueOriginQueue,
        state: QueueTaskState.queued.name,
        orderIndex: 0,
        queuedAt: DateTime.now(),
      ),
    );
  }

  /// The collections a Library-wide check would visit, in library order.
  ///
  /// Asked by the queue before it schedules anything **and** by the Library
  /// screen before it offers to start, through the one predicate in
  /// `library/library_check.dart` — so the number the user is shown and the
  /// number that actually runs cannot drift apart. Archived collections are
  /// asleep (M16), restricted sources are refused, and a collection with no
  /// page to start from is left out rather than given a row that could only
  /// fail.
  Future<List<Collection>> checkableCollections() async {
    final items = await db.allCollections();
    final out = <Collection>[];
    for (final item in items) {
      final entries = await db.entriesForCollection(item.id);
      if (collectionCheckBlock(collection: item, entries: entries) == null) {
        out.add(item);
      }
    }
    return out;
  }

  /// M15: "check everything" expands into one [QueueTaskType.collectionCheck] row
  /// per collection rather than one opaque mega-task. That choice does the heavy
  /// lifting for free: a kill mid-run leaves the remainder as queued rows the
  /// restart offer picks up, one collection's failure is its own history row with
  /// its own reason, and progress is just the queue's own counts.
  ///
  /// Idempotent via [enqueueCollectionCheck]'s per-collection dedupe: collection already
  /// pending are not stacked again.
  ///
  /// Returns the pairing, so a Library-wide run can follow its own rows without
  /// re-deriving which collection a task belongs to.
  Future<List<({String collectionId, String taskId})>>
  enqueueLibraryCheck() async {
    final scheduled = <({String collectionId, String taskId})>[];
    for (final item in await checkableCollections()) {
      final id = await enqueueCollectionCheck(item.id);
      if (id != null) scheduled.add((collectionId: item.id, taskId: id));
    }
    return scheduled;
  }

  /// The task ids [enqueueLibraryCheck] scheduled, existing or new.
  Future<List<String>> enqueueCheckAll() async => [
    for (final t in await enqueueLibraryCheck()) t.taskId,
  ];

  /// Everything still pending for one collection — the number the archive dialog
  /// quotes before it cancels them.
  Future<List<QueueTask>> pendingTasksForCollection(String collectionId) async {
    final pending = await db.pendingQueueTasks();
    return pending.where((t) => t.collectionId == collectionId).toList();
  }

  /// M16 (Q25): archiving a collection takes its pending work with it — queued
  /// rows are cancelled outright, a running one is asked to stop. Returns how
  /// many tasks were affected.
  Future<int> cancelTasksForCollection(String collectionId) async {
    final affected = await pendingTasksForCollection(collectionId);
    for (final task in affected) {
      await cancelTask(task.id);
    }
    return affected.length;
  }

  /// Cancel *queued* checks, leaving the in-flight one to finish — the M15
  /// cancel semantic: "stop after the current collection".
  ///
  /// [onlyTaskIds] narrows it to one run's own rows. A library-wide run passes
  /// its plan's ids, because stopping *that* run must not also drop a
  /// single-collection check the user queued separately from a collection
  /// screen — it was never part of what they asked to stop. Activity's bulk
  /// "cancel queued checks" passes nothing and keeps the wider meaning it
  /// advertises.
  Future<int> cancelQueuedChecks({Iterable<String>? onlyTaskIds}) async {
    final scope = onlyTaskIds?.toSet();
    final pending = await db.pendingQueueTasks();
    final queuedChecks = pending
        .where(
          (t) =>
              t.state == QueueTaskState.queued.name &&
              (scope == null || scope.contains(t.id)) &&
              (t.taskType == QueueTaskType.collectionCheck.name ||
                  t.taskType == QueueTaskType.checkAllCollections.name),
        )
        .toList();
    var cancelled = 0;
    for (final task in queuedChecks) {
      // The count is what was actually dropped: one of these may have just
      // been claimed by the pump, and it keeps running.
      if (await _cancelQueued(task, 'cancelled before it started')) cancelled++;
    }
    return cancelled;
  }

  /// Bulk offline-file removal as an observable task: a whole collection
  /// (pass [collectionId]) or every finished offline entry everywhere.
  /// Small single-entry removals stay inline (toast + undo) — a queue row
  /// for an instant is noise.
  Future<String> enqueueCleanup({String? collectionId}) => _enqueue(
    QueueTask(
      id: _uuid.v4(),
      taskType: QueueTaskType.removeOfflineFiles.name,
      captureModeIsUserSet: false,
      collectionId: collectionId,
      startUrl: collectionId != null
          ? kCleanupScopeCollection
          : kCleanupScopeFinished,
      origin: kQueueOriginQueue,
      state: QueueTaskState.queued.name,
      orderIndex: 0,
      queuedAt: DateTime.now(),
    ),
  );

  Future<String> _enqueue(QueueTask task) async {
    final order = await db.nextQueueOrderIndex();
    await db.upsertQueueTask(task.copyWith(orderIndex: order));
    notifyListeners();
    // Saves wait for an explicit start (D46); checks and cleanup are
    // cheap and already one-action-one-intent, so they drain immediately.
    if (!taskWaitsForExplicitStart(queueTaskTypeFromName(task.taskType))) {
      unawaited(_pump());
    }
    return task.id;
  }

  // --- controls ---------------------------------------------------------------

  /// Cancel a queued task outright, or ask the running one to stop.
  ///
  /// Returns what actually happened, because the caller has different things
  /// to say for each — and because "it had already started" is a real outcome
  /// of pressing Remove on a row the pump claimed in the same instant.
  Future<CancelResult> cancelTask(String id) async {
    final task = await db.queueTaskById(id);
    if (task == null) return CancelResult.gone;
    if (task.state == QueueTaskState.queued.name) {
      final cancelled = await _cancelQueued(
        task,
        'cancelled before it started',
      );
      if (cancelled) return CancelResult.cancelledBeforeStart;
      // Lost the race with the pump's claim. Fall through and read the row
      // again rather than reporting a cancellation that did not happen.
      final now = await db.queueTaskById(id);
      if (now == null || now.state != QueueTaskState.running.name) {
        return CancelResult.gone;
      }
      return _stopRunning(now);
    }
    if (task.state == QueueTaskState.running.name) return _stopRunning(task);
    return CancelResult.alreadyFinished;
  }

  /// Ask the worker driving [task] to stop, and record the request durably.
  ///
  /// The row moves to `cancelled` **now**, not when the worker gets round to
  /// noticing. That is what makes a cancellation survive a kill: a row left
  /// `running` is demoted back to `queued` by [restore], so an in-memory-only
  /// request would hand the user their cancelled work back on relaunch. The
  /// pump writes the real summary over it when the run unwinds.
  Future<CancelResult> _stopRunning(QueueTask task) async {
    // Conditional for the same reason the claim is: the run may have ended
    // between reading this row and writing to it, and stamping `cancelled`
    // over a finished run would misreport work that actually completed.
    final marked = await db.updateQueueTaskIfState(
      id: task.id,
      expected: [QueueTaskState.running.name],
      values: QueueTasksCompanion(
        state: Value(QueueTaskState.cancelled.name),
        outcome: const Value('stopping — cancelled by you'),
        lastError: const Value(null),
        finishedAt: Value(DateTime.now()),
      ),
    );
    if (!marked) return CancelResult.alreadyFinished;
    // Only now: a flag set for a task the pump has already finished with would
    // never be cleared.
    _cancelRequested.add(task.id);
    switch (queueTaskTypeFromName(task.taskType)) {
      case QueueTaskType.entrySave:
      case QueueTaskType.sequenceSave:
        saveRun.stop();
      case QueueTaskType.collectionCheck:
      case QueueTaskType.checkAllCollections:
        checker.cancel();
      case QueueTaskType.removeOfflineFiles:
        // Nothing to interrupt mid-entry; the batch reads _cancelRequested
        // between entries and stops there (see _runCleanup).
        break;
    }
    notifyListeners();
    return CancelResult.stoppingRunning;
  }

  /// Cancel a row **only while it is still queued**. False means the pump
  /// claimed it first, and the caller must not pretend otherwise.
  Future<bool> _cancelQueued(QueueTask task, String reason) async {
    final won = await db.updateQueueTaskIfState(
      id: task.id,
      expected: [QueueTaskState.queued.name],
      values: QueueTasksCompanion(
        state: Value(QueueTaskState.cancelled.name),
        outcome: Value(reason),
        lastError: const Value(null),
        finishedAt: Value(DateTime.now()),
      ),
    );
    if (won) {
      await db.pruneQueueHistory(keep: historyLimit);
      notifyListeners();
    }
    return won;
  }

  /// Put a cancelled row back where it was — the Undo behind "removed from the
  /// queue".
  ///
  /// In place, keeping its `orderIndex`: [retryTask] would clone it to the back
  /// of the queue, which is a different thing to offer for an accidental tap.
  /// Only a `cancelled` row qualifies, so an undo racing a retry or a history
  /// clear does nothing rather than resurrecting work twice.
  Future<bool> restoreQueuedTask(String id) async {
    final restored = await db.updateQueueTaskIfState(
      id: id,
      expected: [QueueTaskState.cancelled.name],
      values: QueueTasksCompanion(
        state: Value(QueueTaskState.queued.name),
        outcome: const Value(null),
        lastError: const Value(null),
        startedAt: const Value(null),
        finishedAt: const Value(null),
      ),
    );
    if (!restored) return false;
    notifyListeners();
    // Checks and cleanup drain on their own; a restored save waits for a
    // Start exactly as it did before it was cancelled (D46).
    final task = await db.queueTaskById(id);
    if (task != null &&
        !taskWaitsForExplicitStart(queueTaskTypeFromName(task.taskType))) {
      unawaited(_pump());
    }
    return true;
  }

  /// Drop one **terminal** row from Activity — the single-row [clearHistory].
  ///
  /// Deletion, not a sixth state: the row is already history, history is
  /// already bounded and already wholesale-deletable, and a "dismissed" state
  /// would only be a history row the history screen has to learn to hide. A
  /// queued or running row is refused here; those go through [cancelTask]
  /// (D64). Queue rows are never the content, so this deletes no entry, no
  /// file and no reading progress.
  Future<bool> removeTask(String id) async {
    final removed = await db.deleteTerminalQueueTask(id);
    if (removed) notifyListeners();
    return removed;
  }

  // --- reordering and queue management --------------------------------------

  /// Move a queued task to the front of the queue.
  Future<void> moveQueuedToFront(String id) async {
    final queued = await _queuedInOrder();
    final ordered = [
      ...queued.where((t) => t.id == id),
      ...queued.where((t) => t.id != id),
    ];
    await _writeOrder(ordered);
  }

  /// Shift a queued task by [delta] places (-1 up, +1 down). Clamped: the
  /// ends are ends, not wrap-arounds.
  Future<void> moveQueued(String id, int delta) async {
    final queued = await _queuedInOrder();
    final from = queued.indexWhere((t) => t.id == id);
    if (from < 0) return;
    final to = (from + delta).clamp(0, queued.length - 1);
    if (to == from) return;
    final ordered = [...queued];
    ordered.insert(to, ordered.removeAt(from));
    await _writeOrder(ordered);
  }

  Future<List<QueueTask>> _queuedInOrder() async {
    final pending = await db.pendingQueueTasks();
    return [
      for (final t in pending)
        if (t.state == QueueTaskState.queued.name) t,
    ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// Renumber from a base above every existing row, so a reorder can never
  /// collide with a running task's index or with history.
  Future<void> _writeOrder(List<QueueTask> ordered) async {
    var next = await db.nextQueueOrderIndex();
    for (final task in ordered) {
      await db.upsertQueueTask(task.copyWith(orderIndex: next++));
    }
    notifyListeners();
  }

  /// Drop every queued save. Metadata and offline files are untouched —
  /// this cancels *plans*, never content.
  Future<int> clearQueuedSaves() async {
    final waiting = await queuedSaves();
    var cleared = 0;
    for (final task in waiting) {
      if (await _cancelQueued(
        task,
        'removed from the queue before it started',
      )) {
        cleared++;
      }
    }
    if (cleared > 0) notifyListeners();
    return cleared;
  }

  /// Pause/resume forward to the save run (checks have no pause).
  void pauseRunning() => saveRun.pause();
  void resumeRunning() => saveRun.resume();

  /// Re-enqueue a terminal task as a fresh entry at the back of the queue.
  ///
  /// Returns null when the retry is refused — including by the restricted-site
  /// policy, which is what stops a history row on a restricted service from
  /// being turned back into work that runs.
  Future<String?> retryTask(String id) async {
    final task = await db.queueTaskById(id);
    if (task == null) return null;
    final terminal = const ['completed', 'failed', 'cancelled'];
    if (!terminal.contains(task.state)) return null;
    if (isCaptureRestricted(task.startUrl)) return null;
    if (await _collectionIsRestricted(task.collectionId)) return null;
    return _enqueue(
      task.copyWith(
        id: _uuid.v4(),
        // Retrying the record of a direct save puts a fresh request in the
        // *queue*, where it waits for a Start like everything else — a history
        // row must not become a plan that runs itself.
        origin: kQueueOriginQueue,
        state: QueueTaskState.queued.name,
        outcome: const Value(null),
        lastError: const Value(null),
        queuedAt: DateTime.now(),
        startedAt: const Value(null),
        finishedAt: const Value(null),
      ),
    );
  }

  /// Delete terminal history. Never touches queued/running rows, and queue
  /// rows are never the content — saved entries are unaffected.
  Future<void> clearHistory() async {
    await db.clearQueueHistory();
    notifyListeners();
  }

  // --- the pump ---------------------------------------------------------------

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    notifyListeners();
    try {
      while (true) {
        final pending = await db.pendingQueueTasks();
        // Eligible = queued, and either not save work or save work the
        // user has explicitly started. A queued save sitting behind an
        // un-pressed Start button must not block a check behind it.
        final next = pending
            .where(
              (t) =>
                  t.state == 'queued' &&
                  (_saveStartAuthorised ||
                      !taskWaitsForExplicitStart(
                        queueTaskTypeFromName(t.taskType),
                      )),
            )
            .firstOrNull;
        if (next == null) break;

        // The restricted-site policy, asked before the row is claimed and
        // before the Browser is brought forward. This is where a *stale* task
        // is stopped: a row queued when its host was permitted, or one that
        // survived a restart, reaches the pump like any other and is settled
        // here as a terminal failure with the policy's own reason. The row is
        // kept (never silently deleted), nothing re-runs it on its own, and no
        // entry, file or reading position is touched.
        if (await _settleIfRestricted(next)) continue;

        // One driver on the shared WebView. Someone else (a directly-started
        // save, a manual check) owning it is not an error — wait our turn
        // by stopping the pump; the next enqueue or resume pumps again.
        if (_directSaveClaimed || browser.automationOwner != null) break;

        // The Browser comes forward BEFORE any WebView automation, never as
        // a side effect of it (D47). A queue task must not begin scrolling
        // while the user is still looking at the Library.
        if (taskNeedsBrowser(queueTaskTypeFromName(next.taskType))) {
          final ready =
              await ensureBrowserVisible?.call(
                url: await _browserTargetFor(next),
              ) ??
              true;
          if (!ready) {
            // Not an error and not a cancellation: the Browser could not be
            // brought up, so the work stays queued for the next attempt.
            break;
          }
        }

        // Claim it conditionally — this is the cancellation race (D64). The
        // row was read before the `ensureBrowserVisible` await above, and a
        // cancel landing in that window has already moved it out of `queued`.
        // Losing the claim means someone else settled this row: skip it and
        // look for the next one, rather than reviving it into `running`.
        final claimed = await db.updateQueueTaskIfState(
          id: next.id,
          expected: [QueueTaskState.queued.name],
          values: QueueTasksCompanion(
            state: Value(QueueTaskState.running.name),
            startedAt: Value(DateTime.now()),
          ),
        );
        if (!claimed) {
          _cancelRequested.remove(next.id);
          continue;
        }

        _runningTaskId = next.id;
        notifyListeners();

        QueueOutcome outcome;
        try {
          outcome = await _run(next);
        } catch (e) {
          outcome = QueueOutcome.failure(e.toString());
        }

        final wasCancelled = _cancelRequested.remove(next.id);
        // Gone means history was cleared under the run; there is nothing left
        // to write an outcome onto, and re-creating the row would resurrect an
        // entry the user deleted.
        final row = await db.queueTaskById(next.id);
        if (row != null) {
          await _finish(
            row,
            wasCancelled
                ? QueueTaskState.cancelled
                : (outcome.failed
                      ? QueueTaskState.failed
                      : QueueTaskState.completed),
            outcome,
          );
        }
        _runningTaskId = null;
        notifyListeners();
      }
    } finally {
      _pumping = false;
      _runningTaskId = null;
      // A drained save queue revokes its own permission: adding more work
      // later is a new decision and gets a new Start.
      if (_saveStartAuthorised && (await queuedSaves()).isEmpty) {
        _saveStartAuthorised = false;
      }
      notifyListeners();
    }
  }

  /// The page the Browser should be showing when [task] starts, or null when
  /// there is nothing specific to show.
  ///
  /// Only checks answer this today. A check names a *collection*, not an
  /// address, so without asking the checker where its walk begins the Browser
  /// has nothing to open and the user is left looking at the page they were on
  /// — the bug this exists to close. A save already names its own start URL and
  /// its engine drives the page from the first frame, so it is deliberately
  /// left alone here rather than given a second navigation path.
  Future<String?> _browserTargetFor(QueueTask task) async {
    if (!isCheckTask(queueTaskTypeFromName(task.taskType))) return null;
    final collectionId = task.collectionId;
    if (collectionId == null) return null;
    try {
      return await checker.firstPageToInspect(collectionId);
    } catch (_) {
      // Never a reason not to start: the check does its own navigation, and
      // this is only about what the user sees first.
      return null;
    }
  }

  /// Stop the update check that is running now, from wherever it was started.
  ///
  /// Goes through the queue when the check is queue work so the row lands in
  /// `cancelled` rather than being written up as a completed check that
  /// happens to say "cancelled" — [cancelTask] is what makes the outcome and
  /// the row agree. Falls back to the checker for a check with no row.
  ///
  /// Nothing is deleted either way: discovered entries, saved packages and
  /// reading positions are untouched by a stopped check.
  Future<void> stopRunningCheck() async {
    if (!checker.isRunning) return;
    final id = _runningTaskId;
    if (id != null) {
      final task = await db.queueTaskById(id);
      if (task != null && isCheckTask(queueTaskTypeFromName(task.taskType))) {
        await cancelTask(id);
        return;
      }
    }
    checker.cancel();
  }

  // --- the restricted-site policy, at the queue's boundary ------------------

  /// Is this task's target on a restricted service?
  ///
  /// Both halves are asked because the two task families carry their target
  /// differently: a save names an address, a check names a collection. Cleanup
  /// names neither and never captures anything, so it is never restricted.
  Future<bool> _taskIsRestricted(QueueTask task) async {
    if (isCaptureRestricted(task.startUrl)) return true;
    return _collectionIsRestricted(task.collectionId);
  }

  /// A collection whose source is on a restricted service — asked through
  /// [collectionSourceIsRestricted], which is the one place the three columns a
  /// collection carries its source in are tested together.
  Future<bool> _collectionIsRestricted(String? collectionId) async {
    if (collectionId == null) return false;
    final item = await db.collectionById(collectionId);
    if (item == null) return false;
    return collectionSourceIsRestricted(item);
  }

  /// Turn a queued row whose target is restricted into a terminal failure, in
  /// place. True when it did.
  ///
  /// Deliberately a `failed` row rather than a deletion: the user queued
  /// something and is owed a record of what became of it. Nothing re-runs it —
  /// the pump settles it again if it ever returns to `queued`, and [retryTask]
  /// refuses to clone it.
  Future<bool> _settleIfRestricted(QueueTask task) async {
    if (!await _taskIsRestricted(task)) return false;
    final settled = await db.updateQueueTaskIfState(
      id: task.id,
      expected: [QueueTaskState.queued.name],
      values: QueueTasksCompanion(
        state: Value(QueueTaskState.failed.name),
        outcome: const Value(kCaptureRestrictedMessage),
        lastError: const Value(kCaptureRestrictedMessage),
        stopReason: Value(StopReason.captureRestrictedForSite.name),
        finishedAt: Value(DateTime.now()),
      ),
    );
    if (settled) {
      await db.pruneQueueHistory(keep: historyLimit);
      notifyListeners();
    }
    return true;
  }

  Future<QueueOutcome> _run(QueueTask task) async {
    // Independently of the pump's own check: a runner reached by any other
    // route must still not begin work on a restricted target.
    if (await _taskIsRestricted(task)) {
      return const QueueOutcome.failure(kCaptureRestrictedMessage);
    }
    switch (queueTaskTypeFromName(task.taskType)) {
      case QueueTaskType.entrySave:
      case QueueTaskType.sequenceSave:
        final outcome = await _runSave(task);
        // Asked of the outcome rather than of the engine, so the note is taken
        // however the work was carried out.
        if (outcome.failed) {
          await _noteDiscoveryCaptureFailure(task, outcome.summary);
        }
        return outcome;
      case QueueTaskType.removeOfflineFiles:
        if (checkRunner != null) return checkRunner!(task);
        return _runCleanup(task);
      case QueueTaskType.collectionCheck:
      case QueueTaskType.checkAllCollections:
        if (checkRunner != null) return checkRunner!(task);
        final itemId = task.collectionId;
        if (itemId == null) {
          return const QueueOutcome.failure(
            'no collection attached to the task',
          );
        }
        final result = await checker.check(itemId);
        // Stated separately from the discovery count, never folded into it:
        // "found" and "no longer there" are opposite facts about the source,
        // and one number for both would be unreadable.
        final retracted = result.staleRemoved > 0
            ? ', ${result.staleRemoved} no longer at the source'
            : '';
        final summary = switch (result.state) {
          UpdateCheckState.upToDate => 'up to date$retracted',
          UpdateCheckState.updatesAvailable =>
            '${result.newEntries} new entry(s)$retracted',
          UpdateCheckState.cancelled => 'cancelled',
          _ => result.error ?? result.state.name,
        };
        return result.state == UpdateCheckState.failed
            ? QueueOutcome.failure(summary)
            : QueueOutcome.success(summary);
    }
  }

  Future<QueueOutcome> _runSave(QueueTask task) async {
    if (saveRunner != null) return saveRunner!(task);
    await saveRun.start(
      entryLimit: task.entryLimit ?? 1,
      startUrl: task.startUrl,
      policy: duplicatePolicyFromName(task.duplicatePolicy),
      range: saveScopeFromName(task.scope),
      maxBytes: task.maxBytes,
      // Restored from the row, so work that waited in the queue produces what
      // the user asked for rather than what today's detection thinks.
      captureMode: captureModeFromName(task.captureMode),
      captureModeIsUserSet: task.captureModeIsUserSet,
      origin: SaveOrigin.queue,
    );
    final p = saveRun.progress;
    final summary =
        '${p.storedEntries} saved'
        '${p.skippedEntries > 0 ? ', ${p.skippedEntries} skipped' : ''}';
    return p.state == SaveState.failed
        ? QueueOutcome.failure(p.lastError ?? summary)
        : QueueOutcome.success(summary);
  }

  /// A single-entry save failed. If it was aimed at an entry this app only
  /// ever *discovered*, note that on the row.
  ///
  /// Deliberately narrow. Only a one-entry task, because that is the only kind
  /// whose failure names one address: a sequence save that stops part way says
  /// nothing about the entry it started on. And it is a note about an attempt,
  /// never a conclusion about the source — this app cannot tell a withdrawn
  /// page from a dropped connection, and a row is never removed on the
  /// strength of a failure. What it buys is that "save the new entries" stops
  /// queueing the same failing address on every press; the entry stays listed
  /// and stays retryable on its own.
  Future<void> _noteDiscoveryCaptureFailure(
    QueueTask task,
    String error,
  ) async {
    if (queueTaskTypeFromName(task.taskType) != QueueTaskType.entrySave) return;
    final url = task.startUrl;
    if (url == null || url.trim().isEmpty) return;
    try {
      await db.recordDiscoveryCaptureFailure(
        urlKey: normalizeUrl(url),
        collectionId: task.collectionId,
        error: error,
      );
    } catch (_) {
      // History, not the operation. A failure to record one must not turn a
      // failed save into a crashed queue.
    }
  }

  /// Removal never touches metadata; locked entries (open reader, active
  /// save) are kept and counted. Progress lands on the task row so the
  /// Activity screen can show "18 / 42 · 1.2 GB freed" live.
  Future<QueueOutcome> _runCleanup(QueueTask task) async {
    final all = task.collectionId != null
        ? await db.entriesForCollection(task.collectionId!)
        : await _finishedOfflineEverywhere();
    final targets = [
      for (final c in all)
        if (cleanup.isRemovable(c) &&
            (task.collectionId != null || c.readStatus == 'completed'))
          c.id,
    ];
    if (targets.isEmpty) {
      return const QueueOutcome.success('nothing to remove');
    }
    final result = await cleanup.removeOfflineNow(
      targets,
      // Cancelling a running removal genuinely stops it, between entries —
      // the queue does not offer a Cancel it cannot honour (D64).
      shouldContinue: () => !_cancelRequested.contains(task.id),
      onProgress: (processed, freed) async {
        if (processed % 5 != 0) return;
        final row = await db.queueTaskById(task.id);
        if (row == null) return;
        await db.upsertQueueTask(
          row.copyWith(
            outcome: Value(
              '$processed / ${targets.length} · ${_fmtBytes(freed)} freed',
            ),
          ),
        );
        notifyListeners();
      },
    );
    final kept = result.keptLocked.isEmpty
        ? ''
        : ' · ${result.keptLocked.length} kept (in use)';
    // A stopped sweep says what it did, not what it was asked to do: the
    // entries it never reached still have their files.
    final stopped = result.stoppedEarly ? 'stopped · ' : '';
    return QueueOutcome.success(
      '$stopped${result.removed} entry(s) removed · '
      '${_fmtBytes(result.freedBytes)} freed$kept',
    );
  }

  /// Completed offline entries across the ACTIVE library (archived collection
  /// are asleep; their files are removed per-collection if the user wants).
  Future<List<Entry>> _finishedOfflineEverywhere() async {
    final items = await db.allCollections();
    final active = {
      for (final i in items)
        if (i.lifecycle != 'archived') i.id,
    };
    final entries = await db.allEntries();
    return [
      for (final c in entries)
        if (active.contains(c.collectionId) && c.readStatus == 'completed') c,
    ];
  }

  static String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).round()} MB';
    return '${(bytes / 1024).round()} KB';
  }

  Future<void> _finish(
    QueueTask task,
    QueueTaskState state,
    QueueOutcome outcome,
  ) async {
    await db.upsertQueueTask(
      task.copyWith(
        state: state.name,
        outcome: Value(outcome.summary),
        lastError: Value(outcome.failed ? outcome.summary : null),
        finishedAt: Value(DateTime.now()),
      ),
    );
    await db.pruneQueueHistory(keep: historyLimit);
    notifyListeners();
  }
}

/// An entry can be saved automatically only when it still knows where it
/// came from. Removing offline files never touches `source_url` (D42), so a
/// removed entry normally does; a row written blank by an older build does
/// not, and must be reported rather than silently dropped.
bool entryHasCapturableUrl(Entry entry) {
  final url = entry.sourceUrl.trim();
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}

/// Reading order — the order save should run in, whatever the list was
/// showing. Decimal-safe, because [compareEntriesForReading] is.
List<Entry> sortEntriesForSaveOrder(List<Entry> entries) {
  final sorted = [...entries];
  sorted.sort(
    (a, b) => compareEntriesForReading(
      (number: a.entryNumber, entryOrder: a.entryOrder, savedAt: a.savedAt),
      (number: b.entryNumber, entryOrder: b.entryOrder, savedAt: b.savedAt),
    ),
  );
  return sorted;
}

/// What a multi-select "add to save queue" actually did.
///
/// Three outcomes rather than a bool, because a selection of eight entries
/// where two have no source page is a *partial* success and the sheet has to
/// be able to say so (D48).
class BatchQueueResult {
  const BatchQueueResult({
    required this.queuedIds,
    required this.alreadyQueued,
    required this.missingSource,
    this.restricted = const [],
  });

  final List<String> queuedIds;
  final List<Entry> alreadyQueued;
  final List<Entry> missingSource;

  /// Entries whose source is on a restricted service. Nothing was queued for
  /// them and nothing about them was changed.
  final List<Entry> restricted;

  int get queued => queuedIds.length;
  int get skipped =>
      alreadyQueued.length + missingSource.length + restricted.length;
  bool get didNothing => queuedIds.isEmpty;
}

extension on Iterable<QueueTask> {
  QueueTask? get firstOrNull => isEmpty ? null : first;
}
