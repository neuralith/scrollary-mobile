import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../browser/browser_controller.dart';
import '../browser/page_data.dart';
import '../library/content_shape.dart';
import 'content_detection.dart';
import 'stop_conditions.dart';
import '../browser/history_repository.dart' show NavigationSource;
import '../core/config.dart';
import '../core/device_storage.dart';
import '../core/url_utils.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';
import 'asset_fetcher.dart';
import 'capture_mode.dart';
import 'capture_policy.dart';
import 'save_engine.dart';
import 'save_preflight.dart';
import 'save_state.dart';
import 'size_estimate.dart';
import '../library/collection_identity.dart';
import '../library/collection_repository.dart'
    show NewCollectionProposal, displayNameFor;
import '../library/entry_labels.dart' show kPlainEntryLabels;
import 'next_page.dart';
import 'page_hint_repository.dart';
import 'selection_request.dart';
import 'page_hint.dart';

const _uuid = Uuid();

/// The persisted pause reason for "the user left the Browser mid-save".
const kPauseBrowserHidden = 'browserHidden';

/// How a save run was launched (D58).
///
/// The distinction is not cosmetic: a `direct` run holds the Browser the user
/// is looking at right now and was never a pending queue entry, so it must not
/// become one — not when it is interrupted, and not when it finishes.
enum SaveOrigin {
  /// Started straight from the Browser's save sheet ("Start Save").
  direct,

  /// Released from the save queue by an explicit Start.
  queue,
}

SaveOrigin saveOriginFromName(String? name) => SaveOrigin.values.firstWhere(
  (o) => o.name == name,
  orElse: () => SaveOrigin.queue,
);

/// What a finished run *was*, kept after the run so the Browser can show a
/// result without the run's live progress standing in as the current state.
///
/// Page-scoped by construction: [pageSession] is the Browser page identity the
/// run ended on, and the Browser shows this only while that page is still the
/// page on screen (D59). Durable history lives in Activity, not here.
class SaveRunRecord {
  const SaveRunRecord({
    required this.runId,
    required this.origin,
    required this.state,
    required this.urlKey,
    required this.pageSession,
    required this.storedEntries,
    required this.skippedEntries,
    required this.message,
    this.error,
  });

  final String runId;
  final SaveOrigin origin;
  final SaveState state;

  /// Canonical identity of the page the run ended on.
  final String urlKey;
  final int pageSession;
  final int storedEntries;
  final int skippedEntries;
  final String message;
  final String? error;

  bool get succeeded =>
      state == SaveState.complete || state == SaveState.partial;
}

/// Drives a bounded multi-entry run: save, find next, validate, navigate,
/// repeat. Only one run runs at a time.
///
/// Run state is written to the database on every meaningful transition so an
/// interrupted run is recognisable after a restart. Resume is always offered,
/// never automatic — resuming navigates a WebView and hits a remote site,
/// which needs user intent.
class SaveRunController extends ChangeNotifier implements SelectionHost {
  SaveRunController({
    required this.browser,
    required this.db,
    required this.fileStore,
    PageHintRepository? rules,
    this.config = kDefaultSaveConfig,
    DeviceStorage? deviceStorage,
    this.asksForCollectionName = false,
  }) : rules = rules ?? PageHintRepository(db),
       deviceStorage = deviceStorage ?? DeviceStorage();

  @override
  final BrowserController browser;
  final AppDatabase db;
  final FileStore fileStore;
  final PageHintRepository rules;
  final SaveConfig config;
  final DeviceStorage deviceStorage;

  /// Whether a collection this run creates is named by the user before the row
  /// is written.
  ///
  /// True in the app, where the Browser renders `CollectionNamePanel` in the
  /// slot the duplicate prompt uses. Left false by default so a run with
  /// nothing able to answer — a unit test, an integration harness — keeps the
  /// detected title rather than holding forever for an answer that can never
  /// arrive. The only place that sets it is `main.dart`.
  final bool asksForCollectionName;

  SaveProgress _progress = const SaveProgress();
  SaveProgress get progress => _progress;

  final List<String> _log = [];
  List<String> get log => List.unmodifiable(_log);

  SaveEngine? _engine;
  String? _runId;
  bool _running = false;

  /// How the run in progress (or the last one) was launched.
  SaveOrigin origin = SaveOrigin.queue;

  SaveRunRecord? _lastRun;

  /// The finished run's result, or null when nothing has finished since the
  /// last start. Transient by design: the Browser presents it only for the
  /// page it belongs to, and Activity holds the durable copy (D59).
  SaveRunRecord? get lastRun => _lastRun;

  /// Drop the finished-run result — the user acknowledged it, or the Browser
  /// moved to another page.
  void clearLastRun() {
    if (_lastRun == null) return;
    _lastRun = null;
    notifyListeners();
  }

  /// Canonical identity of the page this run is working on, or empty when
  /// nothing is running. What "is this page saving?" is answered with.
  String get activePageKey =>
      _running || isPaused ? pageIdentityKey(_progress.currentUrl) : '';

  /// True while a run exists that owns the WebView or is holding mid-run —
  /// which includes a paused one. A finished run is not active, however
  /// recently it finished.
  bool get hasActiveRun => _running || isPaused;

  bool _skipRequested = false;
  bool _retryRequested = false;
  bool _stopRequested = false;
  final Set<String> _visited = {};

  /// Set while the run is holding for the user to point at a control.
  SelectionRequest? _pendingSelection;
  @override
  SelectionRequest? get pendingSelection => _pendingSelection;
  Completer<SelectionOutcome>? _selectionCompleter;

  /// Set while the run is holding on an already-saved entry, waiting for
  /// the user's skip / re-download / stop decision.
  DuplicateRequest? _pendingDuplicate;
  DuplicateRequest? get pendingDuplicate => _pendingDuplicate;
  Completer<DuplicateChoice>? _duplicateCompleter;

  /// Set while the run is holding for the user to name a collection it is
  /// about to create. Nothing has been written when this is non-null.
  NewCollectionProposal? _pendingCollectionName;
  NewCollectionProposal? get pendingCollectionName => _pendingCollectionName;
  Completer<String?>? _collectionNameCompleter;

  /// Session-scoped duplicate answers. Reset by [start], persisted with the
  /// run so an interrupted-session resume keeps them, never stored anywhere
  /// global.
  SessionDuplicateDecision sessionDuplicateDecision =
      SessionDuplicateDecision.ask;
  SessionPartialDecision sessionPartialDecision = SessionPartialDecision.ask;

  bool get isRunning => _running;
  bool get isPaused => _progress.state == SaveState.paused;
  String? get runId => _runId;

  void _addLog(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    // Driver exceptions carry the entire failing SQL statement; a log line that
    // long is unreadable in the panel and drowns everything around it.
    final trimmed = message.length > 300
        ? '${message.substring(0, 300)}… (truncated)'
        : message;
    _log.insert(0, '$stamp  $trimmed');
    if (_log.length > 300) _log.removeLast();
    notifyListeners();
  }

  void _setProgress(SaveProgress Function(SaveProgress) update) {
    final next = update(_progress);
    if (!isTransitionAllowed(_progress.state, next.state)) {
      // A rejected transition is a bug in the engine, not something to paper
      // over — surface it in the log rather than silently accepting it.
      _addLog(
        'illegal transition ${_progress.state.name} -> ${next.state.name}',
      );
    }
    _progress = next;
    notifyListeners();
  }

  // --- controls -----------------------------------------------------------

  /// Test seams: put the controller in a running state without standing up
  /// a real run, so the leave-Browser rules can be exercised per phase.
  @visibleForTesting
  void debugSetRunning(bool value) => _running = value;

  @visibleForTesting
  void debugSetProgress(SaveProgress progress) {
    _runId ??= _uuid.v4();
    _progress = progress;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> debugPersist() => _persistRun(
    _progress.state,
    _progress.currentUrl,
    _progress.storedEntries,
  );

  /// Why the run is paused, when it is paused for a reason worth persisting
  /// and naming in the UI. `browserHidden` is the leave-the-Browser pause.
  String? pauseReason;

  void pause() {
    pauseReason = null;
    _engine?.pause();
    _addLog('paused by user');
    notifyListeners();
  }

  /// The user left the Browser while a rendered-WebView phase was running.
  /// The run holds exactly where it is: nothing scrolls, nothing extracts,
  /// nothing is marked complete, and the queue task keeps the reason so
  /// Activity can say "Browser required" instead of a bare "paused".
  void pauseForBrowserHidden() {
    if (!_running || isPaused) return;
    pauseReason = kPauseBrowserHidden;
    _engine?.pause();
    _addLog('paused — the Browser was left while save needed it');
    unawaited(
      _persistRun(
        _progress.state,
        _progress.currentUrl,
        _progress.storedEntries,
      ),
    );
    notifyListeners();
  }

  /// Back on the Browser and the surface is usable again.
  void resumeAfterBrowserVisible() {
    if (pauseReason != kPauseBrowserHidden) return;
    pauseReason = null;
    _engine?.resume();
    _addLog('resumed — the Browser is visible again');
    final id = _runId;
    unawaited(() async {
      await _persistRun(
        _progress.state,
        _progress.currentUrl,
        _progress.storedEntries,
      );
      // Explicit: a null on the data class would be treated as "leave it".
      if (id != null) await db.clearRunPauseReason(id);
    }());
    notifyListeners();
  }

  /// True while a phase that genuinely needs a rendered WebView is running:
  /// inspecting, scrolling, waiting for page assets, verifying, extracting,
  /// detecting the next link, or navigating. Downloading and saving read
  /// bytes over HTTP and touch no layout — leaving during those is safe, so
  /// the confirmation must not appear.
  bool get needsRenderedBrowser {
    // Already held for this exact reason: asking again would be noise.
    if (!_running || isPaused || pauseReason != null) return false;
    return switch (_progress.state) {
      SaveState.inspecting ||
      SaveState.scrolling ||
      SaveState.waitingForAssets ||
      SaveState.verifying ||
      SaveState.extracting ||
      SaveState.detectingNext ||
      SaveState.navigating => true,
      _ => false,
    };
  }

  /// One line for the leave dialog: what this run has done so far.
  String get progressSummary {
    final p = _progress;
    final parts = <String>[
      if (p.entryTitle.isNotEmpty) p.entryTitle,
      '${p.storedEntries} saved',
      if (p.skippedEntries > 0) '${p.skippedEntries} skipped',
      if (p.requestedEntries > p.storedEntries)
        '${p.requestedEntries - p.storedEntries} remaining',
    ];
    return parts.join(' · ');
  }

  void resume() {
    _engine?.resume();
    _addLog('resumed by user');
    notifyListeners();
  }

  void stop() {
    // Held on the controller, not only forwarded to the engine: between
    // entries there is no engine to cancel, and Stop must still be honoured.
    _stopRequested = true;
    _engine?.cancel();
    // A run holding for a name is not inside the engine and not at the loop
    // head — it is parked on a completer nothing else will finish. Stop has to
    // release it, or "stop" from Activity leaves the run holding the Browser
    // and the wakelock forever. Declining is the right answer: no row is
    // written, which is what stopping here means.
    if (_pendingCollectionName != null) {
      _pendingCollectionName = null;
      _collectionNameCompleter?.complete(null);
      _collectionNameCompleter = null;
    }
    _addLog('stop requested');
    notifyListeners();
  }

  void skipCurrentEntry() {
    _skipRequested = true;
    _engine?.cancel();
    _addLog('skip requested');
  }

  /// The user picked an element in the WebView.
  @override
  Future<void> submitSelection(
    SelectedElement element, {
    HintScope scope = HintScope.collection,
  }) async {
    final request = _pendingSelection;
    if (request == null) return;

    if (request.kind == HintKind.nextLink) {
      // A user-selected control is a strong signal about one link — it is not
      // permission to follow it anywhere. Validate exactly as if the page had
      // offered it automatically.
      final check = validateNextUrl(
        candidate: element.href,
        currentUrl: request.sourceUrl,
        visited: _visited,
      );
      if (!check.isAccepted) {
        _addLog('selection rejected: ${check.rejection?.name}');
        _pendingSelection = request.withError(
          'That link is not usable here (${check.rejection?.name}). '
          'Pick the control that opens the next entry.',
        );
        notifyListeners();
        return;
      }
    }

    final rule = request.kind == HintKind.nextLink
        ? await rules.createNextLinkHint(
            element: element,
            sourceUrl: request.sourceUrl,
            scope: scope,
          )
        : await rules.createReaderAreaHint(
            element: element,
            sourceUrl: request.sourceUrl,
            scope: scope,
          );

    _addLog(
      'saved ${rule.kind.name} rule for ${rule.host}'
      '${rule.hintPath ?? ""} (scope: ${rule.scope.label}, '
      '${rule.locator.signalCount} signal(s)'
      '${rule.locator.isWeak ? ", weak" : ""})',
    );

    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(SelectionOutcome.rule(rule, element));
    _selectionCompleter = null;
    notifyListeners();
  }

  /// The user gave up on selecting; end the run rather than guess.
  @override
  Future<void> cancelSelection() async {
    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(const SelectionOutcome.cancelled());
    _selectionCompleter = null;
    _addLog('selection cancelled by user');
    notifyListeners();
  }

  /// Let the user teach a rule mid-run, before detection has failed.
  void requestNextLinkSelection() =>
      _manualSelectionRequest = HintKind.nextLink;

  void requestReaderAreaSelection() =>
      _manualSelectionRequest = HintKind.readerArea;

  HintKind? _manualSelectionRequest;

  /// Try automatic detection once more instead of picking by hand.
  @override
  Future<void> retryAutomaticDetection() async {
    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(const SelectionOutcome.retryAuto());
    _selectionCompleter = null;
    _addLog('retrying automatic detection');
    notifyListeners();
  }

  Future<SelectionOutcome> _askUser(SelectionRequest request) async {
    _pendingSelection = request;
    _selectionCompleter = Completer<SelectionOutcome>();
    _setProgress(
      (p) => p.copyWith(
        state: SaveState.awaitingSelection,
        message: request.prompt,
      ),
    );
    _addLog('asking the user: ${request.prompt} — ${request.reason}');
    await browser.startSelection(
      mode: request.kind == HintKind.nextLink ? 'link' : 'reader',
    );
    return _selectionCompleter!.future;
  }

  void retryCurrentEntry() {
    _retryRequested = true;
    _engine?.cancel();
    _addLog('retry requested');
  }

  /// The user answered the mid-run duplicate prompt.
  void resolveDuplicate(DuplicateChoice choice) {
    if (_pendingDuplicate == null) return;
    _pendingDuplicate = null;
    _duplicateCompleter?.complete(choice);
    _duplicateCompleter = null;
    notifyListeners();
  }

  /// The user answered the mid-run collection-naming prompt.
  ///
  /// A null [name] is a cancel, and a cancel goes through [stop] like every
  /// other one: the repository writes no row, and the loop head ends the run
  /// before the first entry is inspected.
  void resolveCollectionName(String? name) {
    if (_pendingCollectionName == null) return;
    _pendingCollectionName = null;
    if (name == null) {
      _addLog('naming cancelled — nothing was saved');
      stop();
    }
    _collectionNameCompleter?.complete(name);
    _collectionNameCompleter = null;
    notifyListeners();
  }

  Future<String?> _askCollectionName(NewCollectionProposal proposal) {
    _pendingCollectionName = proposal;
    _collectionNameCompleter = Completer<String?>();
    _setProgress(
      (p) => p.copyWith(
        state: SaveState.awaitingSelection,
        message: 'Name this collection',
      ),
    );
    // Deliberately no `browser.startSelection` — this hold wants a keyboard,
    // not a tap on the page.
    _addLog(
      'holding: naming a new collection from ${proposal.host} '
      '(suggested "${proposal.suggestedName}")',
    );
    return _collectionNameCompleter!.future;
  }

  Future<DuplicateChoice> _askDuplicate(DuplicateRequest request) async {
    _pendingDuplicate = request;
    _duplicateCompleter = Completer<DuplicateChoice>();
    _setProgress(
      (p) => p.copyWith(
        state: SaveState.awaitingSelection,
        message: request.title,
        currentUrl: request.preflight.url,
      ),
    );
    _addLog(
      'holding: ${request.title} '
      '(${request.entry?.sourceMarker ?? request.preflight.url})',
    );
    return _duplicateCompleter!.future;
  }

  /// Turn the user's answer into the loop action, recording it for the rest
  /// of the session when asked to. Stop is deliberately not recordable.
  DuplicateAction _applyDuplicateChoice(
    DuplicateChoice choice,
    EntryLocalState state,
  ) {
    final isComplete = state == EntryLocalState.complete;
    switch (choice.action) {
      case DuplicateChoiceAction.stopSave:
        return DuplicateAction.skip; // unreachable; stop handled by caller
      case DuplicateChoiceAction.skip:
        if (choice.applyToSession) {
          if (isComplete) {
            sessionDuplicateDecision =
                SessionDuplicateDecision.skipCompleteForSession;
            _addLog('session policy: skip already-saved entries');
          } else {
            sessionPartialDecision = SessionPartialDecision.skipForSession;
            _addLog('session policy: skip partial/failed entries');
          }
        }
        return DuplicateAction.skip;
      case DuplicateChoiceAction.redownload:
      case DuplicateChoiceAction.retryMissing:
      case DuplicateChoiceAction.restartEntry:
        if (choice.applyToSession) {
          if (isComplete) {
            sessionDuplicateDecision =
                SessionDuplicateDecision.replaceCompleteForSession;
            _addLog('session policy: re-download already-saved entries');
          } else {
            sessionPartialDecision = SessionPartialDecision.retryForSession;
            _addLog('session policy: re-attempt partial/failed entries');
          }
        }
        return DuplicateAction.save;
    }
  }

  // --- running ------------------------------------------------------------

  /// How this run treats entries that already exist. Chosen by the user in
  /// the preflight sheet, then applied without asking again.
  DuplicatePolicy duplicatePolicy = DuplicatePolicy.skipComplete;

  /// How much the current run was asked to save. Persisted with the run so a
  /// resume keeps the same scope.
  ///
  /// Defaults to [SaveScope.currentPageOnly]: the safe answer, so a caller that
  /// forgets to pass one saves the page in front of the user and nothing else.
  SaveScope scope = SaveScope.currentPageOnly;

  /// The bounded ceilings this run is operating under.
  SaveLimits limits = SaveLimits.forScope(SaveScope.currentPageOnly);

  // --- capture mode ---------------------------------------------------------

  /// What the user asked this run to produce, or null to decide per page.
  ///
  /// A **request**, not a decision. Every entry re-measures its own page and
  /// runs this through `CaptureCapabilities.resolve`, because a multi-entry
  /// run walks pages it has never seen: entry 1 can be an illustrated article
  /// and entry 7 a bare image gallery, and forcing entry 7 into a text mode
  /// would save nothing and call it success.
  CaptureMode? requestedCaptureMode;

  /// True when a person chose [requestedCaptureMode].
  bool captureModeIsUserSet = false;

  /// Write the mode onto the collection once one is resolved.
  bool rememberForCollection = false;

  /// Which condition ended the run, once one has. Null while it is going.
  StopReason? stopReason;

  /// Origins the user explicitly approved for *this run*.
  ///
  /// Starts empty on every run and is never persisted: a host allowed while
  /// browsing is not thereby allowed for unattended navigation.
  final Set<String> _approvedOrigins = {};

  /// Canonical URLs already seen. The other half of loop detection — a site that
  /// paginates with a session parameter gives a fresh URL every time and the
  /// same canonical every time.
  final Set<String> _visitedCanonicals = {};

  /// The first page's structure, to compare later pages against.
  PageContentSignals? _firstPageSignals;

  /// True once collection membership has been decided for this run — including
  /// when the answer was "no collection". Without this a standalone save would
  /// re-ask on every page of the loop.
  bool _collectionResolved = false;

  /// Start a run.
  ///
  /// [range] is **required**, deliberately. A default here is a default about
  /// how much of somebody else's website this app touches, and a caller that
  /// forgets to say would inherit it silently. Making it explicit is what
  /// guarantees the scope shown in the review step is the scope that runs.
  Future<void> start({
    required int entryLimit,
    required SaveScope range,
    String? startUrl,
    DuplicatePolicy policy = DuplicatePolicy.skipComplete,
    SessionDuplicateDecision sessionDuplicate = SessionDuplicateDecision.ask,
    SessionPartialDecision sessionPartial = SessionPartialDecision.ask,
    SaveOrigin origin = SaveOrigin.direct,
    int? maxBytes,

    /// What to produce. Null means "decide per page from detection" — the
    /// honest answer for a queued task whose page had not been analysed yet.
    /// A stated mode is still validated against each page before it is used.
    CaptureMode? captureMode,

    /// True when a person chose [captureMode]. Carried so a resume does not
    /// re-detect over a deliberate choice.
    bool captureModeIsUserSet = false,

    /// Write the chosen mode onto the collection once one is resolved, so
    /// later saves start from it.
    bool rememberForCollection = false,
  }) async {
    if (_running) return;
    if (browser.automationOwner != null) {
      _addLog('cannot start: ${browser.automationOwner} is using the browser');
      return;
    }
    // The flag flips before the first await: `isRunning` must be true from
    // the moment start() is called, or a caller can observe a started run
    // that claims to be idle.
    _running = true;
    this.origin = origin;
    // A new run replaces the previous run's result — never accumulates with
    // it, and never leaves it to be read as this run's outcome.
    _lastRun = null;
    // Identity from the first moment, not from the first entry: a run that
    // refuses to start is still a run, and it still has a result to report.
    _runId = _uuid.v4();

    // The restricted-site policy, before the disk preflight and before the
    // WebView is claimed. A run that cannot legitimately start must not take
    // the Browser, write a `save_runs` row, or enable the wakelock — so this
    // is the first thing asked, and it returns without touching any of them.
    final beginTarget = startUrl ?? browser.currentUrl;
    if (isCaptureRestricted(beginTarget)) {
      _running = false;
      _log.clear();
      stopReason = StopReason.captureRestrictedForSite;
      _addLog('refused to start: $kCaptureRestrictedMessage ($beginTarget)');
      _setProgress(
        (_) => const SaveProgress().copyWith(
          state: SaveState.failed,
          currentUrl: beginTarget,
          lastError: StopReason.captureRestrictedForSite.name,
          message: kCaptureRestrictedMessage,
        ),
      );
      _publishRunRecord(beginTarget);
      return;
    }

    // Disk preflight: starting a save that cannot write is worse than
    // refusing one. Unknown free space is allowed through (the rolling
    // per-entry check will also try, and refusing to save because a
    // platform call failed would be policy by accident).
    final free = await deviceStorage.freeBytes();
    if (free != null && free < config.minFreeSpaceToStart) {
      _running = false;
      _log.clear();
      _addLog(
        'refused to start: ${_mb(free)} free, '
        'minimum ${_mb(config.minFreeSpaceToStart)} (insufficientStorage)',
      );
      _setProgress(
        (_) => const SaveProgress().copyWith(
          state: SaveState.failed,
          lastError: 'insufficientStorage',
          message:
              'Not enough space to start — existing downloads are not '
              'affected.',
        ),
      );
      _publishRunRecord(startUrl ?? browser.currentUrl);
      return;
    }

    _stopRequested = false;
    _skipRequested = false;
    _retryRequested = false;
    _visited.clear();
    _visitedCanonicals.clear();
    _approvedOrigins.clear();
    _firstPageSignals = null;
    _collectionResolved = false;
    stopReason = null;
    _log.clear();

    duplicatePolicy = policy;
    // Session decisions are per-run. A resume passes the interrupted run's
    // answers back in; a fresh run always starts at "ask".
    sessionDuplicateDecision = sessionDuplicate;
    sessionPartialDecision = sessionPartial;
    scope = range;
    // Every scope, including the open-ended one, comes out of here with a
    // positive entry ceiling. There is no code path to an unbounded run.
    requestedCaptureMode = captureMode;
    this.captureModeIsUserSet = captureModeIsUserSet;
    this.rememberForCollection = rememberForCollection;
    limits = SaveLimits.forScope(
      range,
      requestedCount: entryLimit,
      maxBytes: maxBytes,
      config: config,
    );
    final limit = limits.maxEntries;
    final beginUrl = startUrl ?? browser.currentUrl;

    _setProgress(
      (_) => SaveProgress(
        state: SaveState.inspecting,
        currentUrl: beginUrl,
        requestedEntries: limit,
        entryIndex: 1,
      ),
    );

    await _persistRun(SaveState.inspecting, beginUrl, 0);
    _addLog(
      'run ${_runId!.substring(0, 8)} start · ${range.name} · '
      'bounds $limits · $beginUrl',
    );

    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Not fatal — the run just needs the user to keep the screen alive.
    }

    // While the run runs the page may not navigate itself. A user-selected
    // control is a strong signal about one link, not permission to follow
    // whatever the page does next.
    browser.navigationLocked = true;
    browser.automationOwner = 'a save run';
    // The entry chain is the app walking the site, not the user browsing
    // it: these pages never enter browsing history (D53).
    browser.navigationSource = NavigationSource.saveAutomation;
    // A host the user allowed while browsing is not thereby allowed for an
    // unattended run — make the run earn its own consent.
    browser.clearAllowedHostChanges();
    browser.allowNextNavigation(beginUrl);
    // As with the checker: claiming the WebView is what makes the app draw it
    // again, and a document created before that lands is born hidden and stays
    // hidden. See `BrowserController.awaitPaintedSurface`.
    await browser.awaitPaintedSurface();

    try {
      await _runLoop(limit: limit, startUrl: beginUrl);
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      browser.navigationLocked = false;
      browser.automationOwner = null;
      browser.navigationSource = NavigationSource.manual;
      _running = false;
      _engine = null;
      _pendingDuplicate = null;
      _duplicateCompleter = null;
      _pendingCollectionName = null;
      _collectionNameCompleter = null;
      pauseReason = null;
      _publishRunRecord(_progress.currentUrl);
      notifyListeners();
    }
  }

  /// Turn the run that just ended into a page-scoped result.
  ///
  /// [progress] is deliberately left alone: it is the run's own record, which
  /// Activity, the copy-log and the integration suites all read after the fact.
  /// What changes is that the Browser no longer *derives page state from it* —
  /// it reads this record, and only while its page is still on screen (D59).
  void _publishRunRecord(String endedAtUrl) {
    final id = _runId;
    if (id == null) return;
    _lastRun = SaveRunRecord(
      runId: id,
      origin: origin,
      state: _progress.state,
      urlKey: pageIdentityKey(
        endedAtUrl.isEmpty ? _progress.currentUrl : endedAtUrl,
      ),
      pageSession: browser.pageSession,
      storedEntries: _progress.storedEntries,
      skippedEntries: _progress.skippedEntries,
      message: _progress.message,
      error: _progress.lastError,
    );
  }

  Future<void> _runLoop({required int limit, required String startUrl}) async {
    final runDeadline = DateTime.now().add(config.maxRunDuration);
    var url = startUrl;
    var stored = 0;
    var diskStop = false;
    // The chain ended before the requested number did. A different outcome
    // from stopping at the user's ceiling, and they must not share a
    // sentence: one says "that is all there is", the other "that is all you
    // asked for".
    var ranOutOfEntries = false;

    /// New save attempts. This — not pages walked — is what the requested
    /// count means: "save 3 entries" starting inside saved territory
    /// saves 3 new ones, it does not spend the request on skips.
    var attempts = 0;

    /// Pages walked, including skips. Drives `sequence` (chain order).
    var traversed = 0;
    var skipped = 0;
    Collection? item;
    var attemptsForCurrent = 0;
    var isRetry = false;

    while (attempts < limit) {
      if (_stopRequested) {
        _setProgress((p) => p.copyWith(state: SaveState.cancelled));
        await _persistRun(SaveState.cancelled, url, stored);
        _addLog('run cancelled after $stored entry(s)');
        return;
      }
      if (DateTime.now().isAfter(runDeadline)) {
        _addLog('run duration bound reached');
        break;
      }
      if (skipped >= config.maxSkippedPerRun) {
        _addLog(
          'skipped ${config.maxSkippedPerRun} entries without finding new '
          'ones — stopping rather than walking further',
        );
        break;
      }

      // The restricted-site policy, re-asked for every entry the chain reaches.
      // A multi-entry run walks addresses nobody has seen, so the check that
      // cleared entry 1 says nothing about entry 7. Nothing is probed,
      // scrolled, inspected or downloaded for this address: the loop stops here
      // and everything already committed stays exactly as it is.
      final siteGate = checkCaptureSite(url);
      if (siteGate.isBlocked) {
        stopReason = siteGate.reason;
        _addLog('stopped (${siteGate.reason!.name}): ${siteGate.evidence}');
        break;
      }

      // Rolling disk check: multi-entry and until-end runs must not write
      // the device into the ground. Estimated from this collection's own entries
      // when it has any; the conservative default otherwise.
      final free = await deviceStorage.freeBytes();
      if (free != null) {
        final estimate = await _estimateEntryBytes(item);
        if (free < config.emergencyReserve + estimate) {
          _addLog(
            'stopping before the next entry: ${_mb(free)} free, need '
            '~${_mb(estimate)} plus the ${_mb(config.emergencyReserve)} '
            'reserve (insufficientStorage)',
          );
          diskStop = true;
          break;
        }
      }

      // A retry re-saves the page the browser is already on; everything
      // about it (preflight, navigation, ordinal) has already happened.
      if (!isRetry) {
        traversed++;

        // What already exists here, and what to do about it — decided BEFORE
        // navigating, so a skip with a stored next-URL costs no page load,
        // and before anything downloads either way.
        final decision = await _decideDuplicate(url, item, traversed);
        if (decision == null) return; // user stopped the run at the prompt
        if (decision.action == DuplicateAction.skip) {
          skipped++;
          final moved = await _continueAfterSkip(decision.preflight, url);
          if (moved == null) break;
          url = moved;
          continue;
        }
        attempts++;
      }
      isRetry = false;

      _setProgress(
        (p) => p.copyWith(
          entryIndex: attempts,
          currentUrl: url,
          detectedImages: 0,
          storedImages: 0,
          failedImages: 0,
          scrollPercent: 0,
          retryCount: attemptsForCurrent,
          clearError: true,
        ),
      );

      // Navigate unless the browser is already showing this page. That is
      // usually true for the first walked entry (save started from the
      // page on screen) — but not when the run was started from the library
      // ("Save new entries") with the WebView parked somewhere else.
      final alreadyOnPage =
          browser.currentUrl.isNotEmpty &&
          normalizeUrl(browser.currentUrl) == normalizeUrl(url);
      if (traversed > 1 || !alreadyOnPage) {
        _setProgress((p) => p.copyWith(state: SaveState.navigating));
        await _persistRun(SaveState.navigating, url, stored);
        _addLog('opening $url');
        browser.allowNextNavigation(url);
        await browser.loadAndWait(url);
        await Future<void>.delayed(config.cooldownBetweenEntries);

        // Where we landed after redirects is what matters, not where we aimed.
        final landed = browser.currentUrl;

        // A redirect into a restricted service ends the run immediately, before
        // the page is probed, before the duplicate decision, and before the
        // engine is handed the page. Committed entries and reading progress are
        // untouched; only this attempt stops.
        final landedGate = checkCaptureSite(landed);
        if (landedGate.isBlocked) {
          stopReason = landedGate.reason;
          _addLog(
            'stopped (${landedGate.reason!.name}) after a redirect: '
            '${landedGate.evidence}',
          );
          break;
        }

        if (landed.isNotEmpty && normalizeUrl(landed) != normalizeUrl(url)) {
          final check = validateNextUrl(
            candidate: landed,
            currentUrl: url,
            visited: _visited,
          );
          if (!check.isAccepted) {
            _addLog(
              'redirected to an unsafe destination '
              '(${check.rejection?.name}): $landed',
            );
            break;
          }
          if (collectionFingerprint(landed) != collectionFingerprint(url)) {
            _addLog(
              'redirect left the collection '
              '(${collectionFingerprint(url)} -> ${collectionFingerprint(landed)}) — '
              'stopping rather than saving something else',
            );
            break;
          }
          _addLog('followed redirect to $landed');
          url = check.normalized!;

          // The redirect may have landed on an entry we already hold — the
          // duplicate decision applies to where we ARE, not where we aimed.
          final landedDecision = await _decideDuplicate(url, item, traversed);
          if (landedDecision == null) return;
          if (landedDecision.action == DuplicateAction.skip) {
            attempts--; // nothing was attempted here after all
            skipped++;
            final moved = await _continueAfterSkip(
              landedDecision.preflight,
              url,
            );
            if (moved == null) break;
            url = moved;
            continue;
          }
        }
      }

      _visited.add(normalizeUrl(url));

      final probeUrl = browser.currentUrl.isEmpty ? url : browser.currentUrl;

      // Read the page once, and use that one read for every decision below:
      // is this page gated, what is it, does it continue, and have we been here
      // before under a different address.
      PageProbe? pageProbe;
      try {
        pageProbe = await browser.probe(withLinks: true);
      } catch (_) {
        // A failed probe is not fatal: identity falls back to the URL
        // fingerprint and the gate checks are skipped rather than guessed.
      }

      if (pageProbe != null) {
        // 1. Did the site put something in the way? Detected and reported —
        //    never retried, never worked around.
        final gate = detectAccessGate(pageProbe.access);
        if (gate.isBlocked) {
          stopReason = gate.reason;
          _addLog('stopped (${gate.reason!.name}): ${gate.evidence}');
          break;
        }

        // 2. A different address serving a document we already saved.
        final canonical = pageProbe.canonicalUrl;
        final repeat = checkRepeat(
          candidate: probeUrl,
          candidateCanonical: canonical,
          // The current URL was just added to `_visited`, so only the
          // canonical half can fire here.
          visitedUrls: const {},
          visitedCanonicals: _visitedCanonicals,
        );
        if (repeat.isBlocked) {
          stopReason = repeat.reason;
          _addLog('stopped (${repeat.reason!.name}): ${repeat.evidence}');
          break;
        }
        if (canonical != null && canonical.trim().isNotEmpty) {
          _visitedCanonicals.add(normalizeUrl(canonical));
        }

        // 3. Has the sequence changed into something else?
        final first = _firstPageSignals;
        if (first == null) {
          _firstPageSignals = pageProbe.content;
        } else {
          final structure = checkStructure(
            first: first,
            current: pageProbe.content,
          );
          if (structure.isBlocked) {
            stopReason = structure.reason;
            _addLog(
              'stopped (${structure.reason!.name}): ${structure.evidence}',
            );
            break;
          }
        }

        // 4. Audio and video are never saved as offline media. Logged so the
        //    entry can show an honest placeholder and a link to the original.
        if (pageProbe.media.hasMedia) {
          _addLog(
            'audio/video on this page is not saved '
            '(${pageProbe.media.videoCount} video, '
            '${pageProbe.media.audioCount} audio) — the offline copy links to '
            'the original page instead',
          );
        }
      }

      // Where this entry belongs, decided **once** per run.
      //
      // An entry we already hold keeps the place it already has: identity is the
      // URL, so re-saving a page that lives in a collection must land back in
      // that collection. Taking a fresh membership decision here inserted a
      // second, standalone row beside the first and orphaned its reading
      // position — the run "replaced" the entry and the user lost their place.
      // `null` on an existing row is a real answer and is honoured as one.
      //
      // Only a genuinely new page lets the detected sequence decide, which is
      // what keeps a one-off save out of a collection of one.
      if (!_collectionResolved) {
        _collectionResolved = true;
        final held = await db.findEntryByUrlKeyAnywhere(normalizeUrl(probeUrl));
        if (held != null) {
          final heldIn = held.collectionId;
          item = heldIn == null ? null : await db.collectionById(heldIn);
          _addLog(
            item == null
                ? 'already held as a standalone entry — keeping it standalone'
                : 'already held in "${displayNameFor(item)}" — keeping it there',
          );
        } else {
          final sequence = pageProbe == null
              ? const SequenceShape()
              : detectSequence(
                  pageProbe,
                  currentUrl: probeUrl,
                  visitedNormalized: _visited,
                );
          item = await ensureCollection(
            db: db,
            url: probeUrl,
            title: browser.title,
            sequence: limits.isSinglePage
                ? sequence
                // A multi-entry run is itself evidence of a sequence: the user
                // asked to follow one, and the review step showed them what was
                // found. Never downgrade that to "standalone".
                : (sequence.kind == SequenceKind.none
                      ? const SequenceShape(
                          kind: SequenceKind.openEndedNext,
                          ordering: OrderingBasis.detectedNextLink,
                          confidence: ShapeConfidence.low,
                          basis: 'multi-entry save requested by the user',
                        )
                      : sequence),
            hints: pageProbe?.pageHints ?? const PageHints(),
            log: _addLog,
            // A group about to exist is named by the person making it. Asked
            // here and nowhere else, because this is the only place a
            // collection is created — and only when one actually is: joining
            // an existing collection and saving a standalone entry both return
            // before the prompt.
            confirmNewName: asksForCollectionName ? _askCollectionName : null,
          );
        }

        // "Remember this mode for this collection." Written once, here, and
        // only once a collection actually exists — a standalone entry has no
        // collection to remember anything on, and inventing one to hold a
        // preference would put a group in the library the user never made.
        final remembered = requestedCaptureMode;
        if (rememberForCollection && remembered != null && item != null) {
          await db.setCollectionPreferredCaptureMode(item.id, remembered.name);
          _addLog(
            'remembered "${remembered.label}" for '
            '"${displayNameFor(item)}"',
          );
        }
      }

      // Cancelling the naming prompt is a way out of the whole run, and this
      // is the last point where that is still free: the preflight below is
      // what first reaches for the disk. The loop head writes the cancelled
      // state and returns.
      if (_stopRequested) continue;

      final preflight = await SavePreflight(
        db: db,
        fileStore: fileStore,
      ).inspect(probeUrl, collectionId: item?.id, ignoreRunId: _runId);
      final existing = preflight.entry;

      final replacing = preflight.existsLocally;
      if (replacing) {
        // Replacement holds the old and new copy simultaneously — that
        // moment needs headroom for BOTH, or a failed rename could meet a
        // full disk with the readable copy stepped aside.
        final free = await deviceStorage.freeBytes();
        final oldSize = existing?.byteSize ?? 0;
        if (free != null && free < config.emergencyReserve + oldSize) {
          _addLog(
            'not replacing "${existing?.title ?? probeUrl}": ${_mb(free)} '
            'free cannot hold both copies (insufficientStorage) — the '
            'existing save is kept',
          );
          diskStop = true;
          break;
        }
        _addLog(
          'replacing existing ${preflight.state.name} save: '
          '${existing?.title ?? probeUrl}',
        );
        _setProgress((p) => p.copyWith(message: 'Replacing existing save'));
      }

      _engine = SaveEngine(
        browser: browser,
        db: db,
        fileStore: fileStore,
        downloader: AssetFetcher(browser: browser, config: config),
        config: config,
        onProgress: _setProgress,
        onLog: _addLog,
      );

      await _persistRun(SaveState.inspecting, url, stored);

      // The user asked to teach a rule before anything failed.
      if (_manualSelectionRequest != null) {
        final kind = _manualSelectionRequest!;
        _manualSelectionRequest = null;
        final outcome = await _askUser(
          SelectionRequest(
            kind: kind,
            sourceUrl: url,
            prompt: kind == HintKind.nextLink
                ? 'Select the next entry button'
                : 'Select the reader area',
            reason: 'requested by you',
          ),
        );
        if (outcome.cancelled) {
          _setProgress((p) => p.copyWith(state: SaveState.cancelled));
          await _persistRun(SaveState.cancelled, url, stored);
          return;
        }
      }

      // Narrowest applicable rule the user taught us for this page, if any.
      var readerHint = await rules.findFor(url, HintKind.readerArea);
      final nextHint = await rules.findFor(url, HintKind.nextLink);
      if (readerHint != null) {
        _addLog('using saved reader-area rule (${readerHint.scope.label})');
      }
      if (nextHint != null) {
        _addLog('using saved next-link rule (${nextHint.scope.label})');
      }

      // What to ask for. The engine decides the *actual* mode from the
      // settled page — see `saveCurrentPage` — because the probe available
      // here was taken before scrolling, and on the second entry of a run a
      // lazy image page has barely loaded at that point.
      //
      // Precedence: the user's explicit choice, then the collection's
      // remembered preference, then null for "decide from the page". A stated
      // mode is still validated against the settled page and falls back with
      // an explanation rather than forcing an impossible save.
      final requested =
          requestedCaptureMode ??
          captureModeFromName(item?.preferredCaptureMode);

      var result = await _engine!.saveCurrentPage(
        collectionId: item?.id,
        entryOrder: traversed,
        visitedNormalized: _visited,
        captureMode: requested,
        captureModeIsUserSet: captureModeIsUserSet,
        // A reader-area rule is a rule about *images*; it has nothing to say
        // about a text save, and the engine only consults it on the image
        // path anyway.
        readerHint: requested?.isDocument == true ? null : readerHint,
        nextHint: nextHint,
        replaceExisting: replacing,
      );

      // Nothing on this page could be stored — most often a video page with
      // no readable text. Reported and walked past: there is nothing to
      // retry, and sweeping up the page's thumbnails instead is exactly what
      // this refuses to do.
      if (result.nothingToSave) {
        _addLog(
          result.videoDominant
              ? 'skipped: this page is a video, and video is not saved. It '
                    'has no readable text to save instead.'
              : 'skipped: nothing on this page could be saved',
        );
      }

      // A text extraction that found nothing is reported and walked past. It
      // deliberately does NOT go to reader-area selection: that assistance
      // hands back a container of images, which cannot help a page whose
      // problem is that it has no prose.
      if (result.documentFailure != null) {
        _addLog(
          'text extraction found nothing on this page '
          '(${result.documentFailure!.name}) — not offering image selection',
        );
      }

      // Extraction failed, or a saved reader rule stopped matching. Ask the
      // user to point at the reader area rather than guessing at another
      // container.
      if (!_stopRequested && result.needsReaderAreaAssist) {
        if (result.readerHintFailed && readerHint != null) {
          await rules.recordUse(readerHint.id, success: false);
        }
        final outcome = await _askUser(
          SelectionRequest(
            kind: HintKind.readerArea,
            sourceUrl: result.pageUrl.isEmpty ? url : result.pageUrl,
            prompt: 'Select the reader area',
            reason: result.error ?? 'automatic extraction found too little',
            isHintFailure: result.readerHintFailed,
            failedHintId: readerHint?.id,
          ),
        );
        if (outcome.cancelled) {
          _setProgress((p) => p.copyWith(state: SaveState.cancelled));
          await _persistRun(SaveState.cancelled, url, stored);
          _addLog('run ended: user cancelled the reader-area selection');
          return;
        }
        if (outcome.hasRule && result.readerHintFailed && readerHint != null) {
          await rules.delete(readerHint.id);
          _addLog('replaced the broken reader-area rule');
        }
        readerHint = outcome.rule ?? readerHint;
        _engine?.reset();
        result = await _engine!.saveCurrentPage(
          collectionId: item?.id,
          entryOrder: traversed,
          visitedNormalized: _visited,
          // Reader-area assistance only ever produces an image sequence — the
          // user pointed at a container of images.
          captureMode: CaptureMode.imageSequence,
          captureModeIsUserSet: true,
          readerHint: readerHint,
          nextHint: nextHint,
        );
      }

      // Skip / retry / stop are surfaced through cancellation.
      if (_skipRequested) {
        _skipRequested = false;
        _addLog('entry skipped by user');
        _engine?.reset();
        final next = await _peekNextFromPage(url);
        if (next == null) break;
        url = next;
        attemptsForCurrent = 0;
        continue;
      }
      if (_retryRequested) {
        _retryRequested = false;
        attemptsForCurrent++;
        _engine?.reset();
        _addLog('retrying entry (attempt ${attemptsForCurrent + 1})');
        isRetry = true; // same entry, same attempt — no re-preflight
        continue;
      }
      if (result.error == 'cancelled') {
        _setProgress((p) => p.copyWith(state: SaveState.cancelled));
        await _persistRun(SaveState.cancelled, url, stored);
        _addLog('run cancelled after $stored entry(s)');
        return;
      }

      if (result.isUsable) {
        stored++;
        attemptsForCurrent = 0;
        _setProgress((p) => p.copyWith(storedEntries: stored));
        await _persistRun(SaveState.saving, url, stored);
      } else {
        _addLog('entry failed: ${result.error}');
        await _persistRun(SaveState.failed, url, stored, error: result.error);
        // An entry failure is not a run failure: try to keep walking.
        final next = await _peekNextFromPage(url);
        if (next == null) {
          _setProgress(
            (p) => p.copyWith(state: SaveState.failed, lastError: result.error),
          );
          await _persistRun(SaveState.failed, url, stored, error: result.error);
          return;
        }
        url = next;
        continue;
      }

      if (attempts >= limit) {
        _addLog(
          result.nextUrl != null
              // Stopping at the user's number with the chain still going is a
              // different fact from reaching the end of a collection, and the
              // two must not share a sentence.
              ? 'reached the $limit entries you asked for, with more still '
                    'available'
              : 'requested entry limit reached',
        );
        break;
      }

      if (nextHint != null && result.nextResult != null) {
        await rules.recordUse(nextHint.id, success: result.nextResult!.hasNext);
      }

      var next = result.nextUrl;
      final nextResult = result.nextResult;

      if (next == null &&
          nextResult != null &&
          nextResult.needsUserSelection &&
          !_stopRequested) {
        final outcome = await _askUser(
          SelectionRequest(
            kind: HintKind.nextLink,
            sourceUrl: result.pageUrl.isEmpty ? url : result.pageUrl,
            prompt: 'Select the next entry button',
            reason: nextResult.reason,
            candidates: nextResult.considered,
            isHintFailure: nextHint != null,
            failedHintId: nextHint?.id,
          ),
        );

        if (outcome.cancelled) {
          // The user gave up on picking the control: the run ends as
          // cancelled — what was already stored stays stored, but "complete"
          // would claim an ending the user never reached.
          _addLog('run ended: user cancelled the next-entry selection');
          _setProgress(
            (p) =>
                p.copyWith(state: SaveState.cancelled, storedEntries: stored),
          );
          await _persistRun(SaveState.cancelled, url, stored);
          if (_runId != null) await db.deleteRun(_runId!);
          return;
        }
        if (outcome.retryAutomatic) {
          final retry = await _peekNextFromPage(url);
          if (retry == null) {
            _addLog('automatic retry still found nothing — end of chain');
            break;
          }
          next = retry;
        } else if (outcome.hasRule) {
          if (nextHint != null && result.nextResult?.hasNext != true) {
            await rules.delete(nextHint.id);
            _addLog('replaced the broken next-link rule');
          }
          // Resolve through the freshly saved rule so the stored signals are
          // exercised immediately rather than trusted on faith.
          final match = await browser.applyLocator(
            outcome.rule!.locator.toJson(),
          );
          final href = match?.isMatch == true
              ? match!.href
              : (outcome.element?.href ?? '');
          final check = validateNextUrl(
            candidate: href,
            currentUrl: url,
            visited: _visited,
          );
          if (!check.isAccepted) {
            _addLog(
              'selected link failed validation: ${check.rejection?.name}',
            );
            break;
          }
          next = check.normalized;
        }
      }

      if (next == null) {
        _addLog('no valid next entry — end of chain');
        ranOutOfEntries = true;
        break;
      }
      url = next;
    }

    final finalState = diskStop && stored == 0
        ? SaveState.failed
        : stored == 0 && skipped == 0
        ? SaveState.failed
        : (_progress.state == SaveState.partial
              ? SaveState.partial
              : SaveState.complete);
    // The requested count means new save attempts; skips and traversal are
    // reported alongside it so "3 requested, 3 saved, 2 skipped, 5 walked" is
    // one honest sentence rather than a puzzle.
    final counts =
        'saved $stored'
        '${skipped > 0 ? ' · skipped $skipped existing' : ''}'
        ' · traversed $traversed';

    // Every ceiling is now a number the user typed, so there is one honest
    // sentence for stopping at it. The app no longer has an internal bound it
    // could hit and have to explain — that was the "safety limit" wording, and
    // it existed only for the open-ended scope this app no longer offers.
    stopReason ??= diskStop
        ? StopReason.insufficientStorage
        : ranOutOfEntries
        ? StopReason.noNextPage
        : StopReason.userLimitReached;

    final message = diskStop
        ? 'Stopped: not enough disk space. $counts. '
              'Existing downloads are unaffected.'
        : ranOutOfEntries
        ? 'Reached the end of the collection. $counts.'
        : skipped > 0
        ? 'Requested $limit new · $counts'
        : 'Saved ${kPlainEntryLabels.count(stored)}';
    _setProgress(
      (p) => p.copyWith(
        state: finalState,
        storedEntries: stored,
        lastError: diskStop ? 'insufficientStorage' : null,
        message: message,
      ),
    );
    await _persistRun(SaveState.complete, url, stored);
    if (_runId != null) await db.deleteRun(_runId!);
    _addLog(
      'run finished (${scope.name}'
      '${diskStop ? ', disk stop' : ''}): '
      '$stored new entry(s) stored of $limit requested'
      '${skipped > 0 ? ' · $skipped skipped as already saved' : ''}'
      ' · $traversed page(s) traversed',
    );
  }

  /// Planning estimate for the next entry: the typical size of this
  /// collection's own **finished** saves, the conservative default otherwise.
  ///
  /// This is the disk-safety check, not the figure shown before a save, so the
  /// fallback stays deliberately generous — the cost of over-estimating here is
  /// stopping one entry early, and the cost of under-estimating is writing the
  /// device full mid-entry. What is shared with the sheet is which rows count
  /// as evidence and how the typical one is picked; see `size_estimate.dart`.
  Future<int> _estimateEntryBytes(Collection? item) async {
    if (item == null) return config.unknownEntryEstimate;
    final sizes = CollectionSizeHistory.fromEntries(
      await db.entriesForCollection(item.id),
    ).forArtifact(null);
    return typicalEntryBytes(sizes) ?? config.unknownEntryEstimate;
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  /// Preflight + policy + (when needed) the user prompt for the entry at
  /// [url]. Returns null when the user chose to stop the run.
  Future<({DuplicateAction action, EntryPreflight preflight})?>
  _decideDuplicate(String url, Collection? item, int ordinal) async {
    final preflight = await SavePreflight(
      db: db,
      fileStore: fileStore,
    ).inspect(url, collectionId: item?.id, ignoreRunId: _runId);

    var action = resolveDuplicateAction(
      state: preflight.state,
      policy: duplicatePolicy,
      sessionComplete: sessionDuplicateDecision,
      sessionPartial: sessionPartialDecision,
    );

    if (action == DuplicateAction.promptUser && !_stopRequested) {
      final choice = await _askDuplicate(
        DuplicateRequest(preflight: preflight, ordinal: ordinal),
      );
      if (choice.action == DuplicateChoiceAction.stopSave) {
        _setProgress((p) => p.copyWith(state: SaveState.cancelled));
        await _persistRun(SaveState.cancelled, url, _progress.storedEntries);
        _addLog('run stopped by user at the duplicate prompt');
        return null;
      }
      action = _applyDuplicateChoice(choice, preflight.state);
      await _persistRun(_progress.state, url, _progress.storedEntries);
    } else if (action == DuplicateAction.skip &&
        preflight.state == EntryLocalState.inActiveRun) {
      _addLog('skipped (owned by another run): $url');
    }

    return (action: action, preflight: preflight);
  }

  /// Walk past an entry that stays as it is: prefer its stored (and
  /// re-validated) next URL — costing no page load — else open the page and
  /// read the next link off it. Returns null at the end of the chain.
  Future<String?> _continueAfterSkip(
    EntryPreflight preflight,
    String url,
  ) async {
    final existing = preflight.entry;
    final reason = switch (preflight.state) {
      EntryLocalState.complete => 'already saved',
      EntryLocalState.partial => 'partial, kept as-is',
      EntryLocalState.inActiveRun => 'owned by another run',
      _ => preflight.state.name,
    };
    _addLog('skipped ($reason): ${existing?.title ?? url}');
    _setProgress(
      (p) => p.copyWith(
        skippedEntries: p.skippedEntries + 1,
        message: 'Skipped — $reason',
      ),
    );
    _visited.add(normalizeUrl(url));

    var next = existing?.nextSourceUrl;
    if (next != null) {
      final check = validateNextUrl(
        candidate: next,
        currentUrl: url,
        visited: _visited,
      );
      next = check.isAccepted ? check.normalized : null;
    }
    if (next == null && !_stopRequested) {
      // Only now is a page load needed: the stored chain ends here.
      _setProgress((p) => p.copyWith(state: SaveState.navigating));
      browser.allowNextNavigation(url);
      await browser.loadAndWait(url);
      next = await _peekNextFromPage(url);
    }
    if (next == null) _addLog('no next entry beyond the skipped one');
    return next;
  }

  /// After a skip or failure we still want the chain to continue, so read the
  /// next link straight off whatever page is on screen.
  Future<String?> _peekNextFromPage(String currentUrl) async {
    try {
      final probe = await browser.probe(withLinks: true);
      final result = resolveNextPage(
        probe,
        currentUrl: currentUrl,
        visitedNormalized: _visited,
      );
      if (result.hasNext) _addLog('continuing at ${result.chosen!.href}');
      return result.chosen?.href;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistRun(
    SaveState state,
    String currentUrl,
    int completed, {
    String? error,
  }) async {
    final id = _runId;
    if (id == null) return;
    final now = DateTime.now();
    await db.upsertRun(
      SaveRun(
        id: id,
        collectionId: null,
        startUrl: _progress.currentUrl,
        currentUrl: currentUrl,
        requestedEntries: _progress.requestedEntries,
        completedEntries: completed,
        state: state.name,
        lastError: error,
        stopReason: stopReason?.name,
        visitedUrls: _visited.join('\n'),
        visitedCanonicals: _visitedCanonicals.join('\n'),
        duplicatePolicy: duplicatePolicy.name,
        // Session answers ride on the run row so an interrupted-session
        // resume keeps them — and die with it, never becoming a preference.
        sessionDuplicateDecision: sessionDuplicateDecision.name,
        sessionPartialDecision: sessionPartialDecision.name,
        scope: scope.name,
        maxBytes: limits.maxBytes,
        captureMode: requestedCaptureMode?.name,
        captureModeIsUserSet: captureModeIsUserSet,
        pauseReason: pauseReason,
        // Carried so an interrupted direct save is resumed as one, rather
        // than being folded into the pending queue (D58).
        origin: origin.name,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Resume an interrupted run: continue from its recorded current URL with
  /// the visited set restored, so completed entries are not re-saved —
  /// under the same duplicate policy and session decisions it was running
  /// with.
  Future<void> resumeRun(SaveRun run) async {
    _visited
      ..clear()
      ..addAll(run.visitedUrls.split('\n').where((s) => s.isNotEmpty));
    _addLog(
      'resuming run ${run.id.substring(0, 8)} '
      'at ${run.currentUrl ?? run.startUrl}',
    );
    final mode = saveScopeFromName(run.scope);
    final remaining = run.requestedEntries - run.completedEntries;
    await db.deleteRun(run.id);
    await start(
      // A resume continues with what is left of the number the user typed;
      // the visited set is what prevents re-saving what already landed.
      entryLimit: remaining <= 0 ? 1 : remaining,
      startUrl: run.currentUrl ?? run.startUrl,
      policy: duplicatePolicyFromName(run.duplicatePolicy),
      sessionDuplicate: sessionDuplicateDecisionFromName(
        run.sessionDuplicateDecision,
      ),
      sessionPartial: sessionPartialDecisionFromName(
        run.sessionPartialDecision,
      ),
      range: mode,
      maxBytes: run.maxBytes,
      // The mode is restored, not re-decided: a resume that quietly switched
      // from "text and images" to an image sequence would give one collection
      // two different artifacts and the user no way to tell why.
      captureMode: captureModeFromName(run.captureMode),
      captureModeIsUserSet: run.captureModeIsUserSet,
      // A resumed run keeps the launch it was interrupted mid-way through: a
      // direct save resumes directly and never joins the pending queue.
      origin: saveOriginFromName(run.origin),
    );
  }

  Future<void> discardRun(SaveRun run) async {
    await db.deleteRun(run.id);
    _addLog('discarded interrupted run ${run.id.substring(0, 8)}');
  }
}
