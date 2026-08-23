import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_controller.dart';
import '../capability/foreground_gate.dart';
import '../core/config.dart';
import '../data/recognition_index.dart';
import '../domain/domain.dart';
import '../library_ui/collection_picker.dart';
import '../library_ui/entry_offline.dart';
import '../library_ui/providers.dart';
import '../library_ui/save_scope_sheet.dart';
import '../providers.dart';
import '../recognition/history.dart';
import '../recognition/page_kind.dart';
import '../recognition/recognise.dart';
import '../recognition/reconcile.dart';
import '../recognition/walk.dart';
import '../save/capture_mode.dart';
import '../save/capture_policy.dart';
import '../save/entry_capture.dart';
import '../save/page_hint.dart';
import '../save/page_hint_repository.dart';
import '../save/queue_task.dart';
import '../save/selection_request.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'capture_mode_section.dart';
import 'foreground_gate_sheet.dart';
import 'selection_overlay.dart';
// STUB IMPORT — switch to 'v2_add_flow.dart' at merge.
import 'v2_add_flow.dart';
import 'v2_adoption_providers.dart';
import 'v2_check_flow.dart';

/// The Browser's save flow over the V2 library.
///
/// The rule carried over from V1 unchanged: on a restricted host the save
/// control is **absent** — not disabled, not a warning — which is why
/// [v2SaveAvailable] is asked before the control is even built. Everything
/// else is new underneath: the page is recognised against the V2 library, the
/// save enqueues a V2 task for `(entry, location)`, and nothing captures
/// until the user's explicit Start.
bool v2SaveAvailable(String url) =>
    url.startsWith('http') && !isCaptureRestricted(url);

/// What the sheet knows about the page it was opened for.
class V2PageStatus {
  const V2PageStatus({
    required this.result,
    this.entryId,
    this.hasCopy = false,
    this.task,
  });

  final RecognitionResult result;

  /// The Entry this page already is, when the address is known.
  final String? entryId;

  /// This device already holds readable bytes for it.
  final bool hasCopy;

  /// The open or most recent queue row covering it.
  final SaveTask? task;
}

Future<V2PageStatus> v2PageStatusFor(WidgetRef ref, String url) async {
  final services = ref.read(libraryUiServicesProvider);
  final recogniser = Recogniser(
    index: RecognitionIndexOf(services).index,
    collections: services.collections,
    reading: services.reading,
  );
  final result = await recogniser.recognise(url);
  if (result is! RecognisedLocation) {
    return V2PageStatus(result: result);
  }
  final entryId = result.entry.id;
  return V2PageStatus(
    result: result,
    entryId: entryId,
    hasCopy: await services.offline.activeCopyOf(entryId) != null,
    task: await services.queue.openTaskFor(entryId),
  );
}

/// Saving this page: make sure the library holds it, then queue the capture.
///
/// Returns the sentence the sheet shows, or null when everything is queued
/// and there is nothing to explain.
Future<String?> v2SavePage(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  CaptureMode? captureMode,
  bool captureModeIsUserSet = false,
}) async {
  if (!v2SaveAvailable(url)) return kCaptureRestrictedMessage;
  final services = ref.read(libraryUiServicesProvider);
  final status = await v2PageStatusFor(ref, url);

  String entryId;
  String? locationId;
  switch (status.result) {
    case RecognisedLocation(:final entry, :final location):
      entryId = entry.id;
      locationId = location.id;
    case RecognisedSource(:final source, :final collection, :final keys):
      // The page sits on a known Source at a new address, so the Entry joins
      // its Collection — through the **same** reconciliation a reading of
      // that Source's listing would go through. This branch used to create an
      // unplaced Entry unconditionally, which meant a part the Collection
      // already held at that number arrived a second time and could then
      // never be placed there (I8). The entry point differs from discovery's;
      // the rule does not (V2_SAVE_FLOW.md §5).
      final printed = readPageShape(url, pageTitle: pageTitle).printedNumber;
      final reconciled =
          await EntryReconciler(
            entries: services.entries,
            index: RecognitionIndexOf(services).index,
          ).entryFor(
            collectionId: collection.id,
            basis: OrderingBasis.values.byName(collection.orderingBasis),
            printedNumber: printed,
            title: pageTitle,
          );
      if (!reconciled.succeeded) {
        return 'Could not add this page: ${reconciled.violation?.message}';
      }
      final (location, locViolation) = await services.entries.addLocation(
        entryId: reconciled.entryId!,
        url: url,
        urlKey: keys.urlKey,
        sourceId: source.id,
        sourceNumber: printed,
        discoveryBasis: 'userSave',
      );
      if (location == null) {
        return 'Could not add this page: ${locViolation?.message}';
      }
      entryId = reconciled.entryId!;
      locationId = location.id;
    case Unrecognised():
      // A page the library knows nothing about becomes a standalone item,
      // through the same promotion path history uses.
      final history = HistoryStore(services.db);
      final (row, violation) = await history.recordVisit(
        url: url,
        title: pageTitle,
        userInitiated: true,
      );
      if (row == null) return 'This page can’t be saved: ${violation?.message}';
      final promotion = LibraryPromotion(
        folders: services.folders,
        collections: services.collections,
        entries: services.entries,
      );
      final outcome = await promotion.promoteToLibrary(
        row: row,
        result: status.result,
      );
      if (outcome.entryId == null) {
        return 'Could not add this page: ${outcome.violation?.message}';
      }
      entryId = outcome.entryId!;
      locationId = outcome.locationId;
  }

  final enqueue = await services.queue.enqueue(
    entryId: entryId,
    locationId: locationId,
    locationUrl: url,
    // Carried onto the row, never re-derived later: what the user asked for is
    // decided here, on the page they were looking at. Null is a real answer —
    // "decide from the settled page" — and never a default about what to take.
    captureMode: captureMode,
    captureModeIsUserSet: captureModeIsUserSet,
  );
  if (enqueue.refusedReason != null) return enqueue.refusedReason;
  return null;
}

/// Follow the Collection this page's Source belongs to.
Future<void> v2FollowCollection(WidgetRef ref, String collectionId) =>
    ref.read(libraryUiServicesProvider).collections.follow(collectionId);

/// A small helper so the recogniser can be built from the one services
/// object without the panel importing the index type directly.
class RecognitionIndexOf {
  RecognitionIndexOf(this.services);
  final LibraryUiServices services;
  RecognitionIndex get index => RecognitionIndex(services.db);
}

/// Holds a capture while the user points at the reading area.
///
/// The V2 counterpart of what V1's save run did between two calls to the
/// engine, and it keeps V1's three rules exactly:
///
/// * **A rule is only ever written from an explicit tap.** Nothing here
///   infers one, and no capture result creates one on its own.
/// * **The page is put into selection mode first**, so the tap teaches
///   instead of navigating.
/// * **Scope is the user's choice**, defaulting to the narrowest one — this
///   collection on this host.
///
/// Only reader-area holds exist on this side. A V2 capture is one page per
/// queue row, so there is no next-entry traversal here for a next-link rule
/// to serve; `PageHintRepository` still stores and matches both kinds,
/// because a hint taught in V1 outlives the run that asked for it.
class V2AssistController extends ChangeNotifier implements SelectionHost {
  V2AssistController({required this.browser, required this.hints});

  @override
  final BrowserController browser;

  /// Over the V2 library's `page_hints` table.
  final PageHintRepository hints;

  SelectionRequest? _pending;
  Completer<SelectionOutcome>? _answer;

  @override
  SelectionRequest? get pendingSelection => _pending;

  /// Hold until the user answers. Returns what they decided.
  Future<SelectionOutcome> ask(SelectionRequest request) async {
    _pending = request;
    _answer = Completer<SelectionOutcome>();
    notifyListeners();
    await browser.startSelection(mode: 'reader');
    return _answer!.future;
  }

  /// The user picked an element in the page.
  @override
  Future<void> submitSelection(
    SelectedElement element, {
    HintScope scope = HintScope.collection,
  }) async {
    final request = _pending;
    if (request == null) return;
    final rule = await hints.createReaderAreaHint(
      element: element,
      sourceUrl: request.sourceUrl,
      scope: scope,
    );
    await _settle(SelectionOutcome.rule(rule, element));
  }

  /// The user gave up on selecting; the capture keeps the failure it had.
  @override
  Future<void> cancelSelection() => _settle(const SelectionOutcome.cancelled());

  /// Try automatic detection once more instead of picking by hand.
  @override
  Future<void> retryAutomaticDetection() =>
      _settle(const SelectionOutcome.retryAuto());

  Future<void> _settle(SelectionOutcome outcome) async {
    if (_pending == null) return;
    await browser.stopSelection();
    _pending = null;
    _answer?.complete(outcome);
    _answer = null;
    notifyListeners();
  }
}

/// The V2 assist host, one per app.
/// The hold the operation indicator draws *Needs you* from.
///
/// A separate, nullable seam rather than [v2AssistProvider] itself: the
/// indicator is mounted on surfaces that have no Browser and no library —
/// reading [v2AssistProvider] there would make every one of them build the
/// whole capture stack to ask one question. Null means "nothing can hold a
/// run here", which is the honest answer on those surfaces. `main.dart`
/// overrides it with the one controller the queue actually holds on.
final assistHoldProvider = Provider<V2AssistController?>((ref) => null);

final v2AssistProvider = Provider<V2AssistController>((ref) {
  final controller = V2AssistController(
    browser: ref.watch(browserProvider),
    hints: PageHintRepository.forLibrary(ref.watch(libraryDatabaseProvider)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Capture one Entry, asking the user to point at the reading area if the
/// page needs it.
///
/// The order is V1's. The narrowest rule the user already taught for this
/// address goes *in*; what comes back says whether pointing at the container
/// could help; a tap writes one rule and the capture is run again with it.
/// The counters move exactly as V1 moved them: a rule that was applied and
/// produced a copy counts a success, a rule the page stopped matching counts
/// a failure, and a capture that failed for some other reason counts neither.
///
/// **Wired.** `main.dart` builds the one [V2AssistController], hands it to
/// `QueueRunner` as its capture hook and publishes it through
/// [v2AssistProvider], so a queued capture that cannot find the reading area
/// holds and asks rather than failing — and the sheet that renders the request
/// is watching the same controller the worker is holding on.
Future<EntryCaptureResult> v2CaptureWithAssist({
  required EntryCaptureService capture,
  required V2AssistController assist,
  required String entryId,
  required String locationUrl,
  required CaptureMode? captureMode,
  String? locationId,
  bool captureModeIsUserSet = false,
  bool Function()? shouldContinue,
}) async {
  final hints = assist.hints;
  final nextHint = await hints.findFor(locationUrl, HintKind.nextLink);
  var readerHint = await hints.findFor(locationUrl, HintKind.readerArea);

  Future<EntryCaptureResult> run({
    required CaptureMode? mode,
    required bool modeIsUserSet,
  }) async {
    final result = await capture.capture(
      entryId: entryId,
      locationId: locationId,
      locationUrl: locationUrl,
      captureMode: mode,
      captureModeIsUserSet: modeIsUserSet,
      shouldContinue: shouldContinue,
      readerHint: readerHint,
      nextHint: nextHint,
    );
    final applied = readerHint;
    if (applied != null) {
      if (result.isCaptured) {
        await hints.recordUse(applied.id, success: true);
      } else if (result.needsReaderAreaAssist) {
        await hints.recordUse(applied.id, success: false);
      }
    }
    return result;
  }

  final first = await run(
    mode: captureMode,
    modeIsUserSet: captureModeIsUserSet,
  );
  if (!first.needsReaderAreaAssist) return first;

  final failed = readerHint;
  final outcome = await assist.ask(
    SelectionRequest(
      kind: HintKind.readerArea,
      sourceUrl: locationUrl,
      prompt: 'Select the reader area',
      reason: first.error ?? 'automatic extraction found too little',
      isHintFailure: failed != null,
      failedHintId: failed?.id,
    ),
  );
  // Nothing was taught, so there is nothing new to try: the capture keeps the
  // failure it already had.
  if (outcome.cancelled) return first;

  if (outcome.hasRule) {
    // The rule the page stopped matching is gone, replaced by the one the
    // user just pointed at. Its counters went with it; what survives is the
    // rule that works.
    if (failed != null) await hints.delete(failed.id);
    readerHint = outcome.rule;
    // Reader-area assistance only ever produces an image sequence — the user
    // pointed at a container of images — and a person chose it.
    return run(mode: CaptureMode.imageSequence, modeIsUserSet: true);
  }

  // "Retry auto": run detection again with no rule in the way, including the
  // one that just stopped matching.
  readerHint = null;
  return run(mode: captureMode, modeIsUserSet: captureModeIsUserSet);
}

// ─── the seams the panel calls the domain through ──────────────────────────
//
// Providers rather than direct calls, for the same reason
// `saveQueueStarterProvider` is one: the panel decides *what to ask for* and
// the domain decides what that writes, and a widget test has to be able to
// stand in for the second half without a database behind it. The default is
// the real function; nothing here changes what it does.

typedef V2AddAndDownloadFn =
    Future<AddToLibraryReport> Function(
      WidgetRef ref, {
      required String url,
      required String pageTitle,
      String? collectionId,
      String? newCollectionName,
      String? folderId,
      SaveLimits? limits,
      bool isListing,

      /// The count is a claim about the **Source**: queue what the library
      /// holds and, for whatever is missing, read forward on the Source the
      /// user is on to find it (docs/V2_SAVE_FLOW.md §4).
      bool discoverMissing,
      CaptureMode? captureMode,
      bool captureModeIsUserSet,
    });

final v2AddAndDownloadProvider = Provider<V2AddAndDownloadFn>(
  (ref) => v2AddAndDownload,
);

typedef V2SaveStandaloneFn =
    Future<AddToLibraryReport> Function(
      WidgetRef ref, {
      required String url,
      required String pageTitle,
      CaptureMode? captureMode,
      bool captureModeIsUserSet,
    });

final v2SaveStandaloneProvider = Provider<V2SaveStandaloneFn>(
  (ref) => v2SaveStandalone,
);

/// The sheet behind the Browser's save control.
///
/// It asks the two questions V1 asked on the way in and V2 lost: **which
/// Collection is this?** and **how much of it?** — and it asks them in the
/// order the decision matrix in docs/V2_SAVE_FLOW.md §3 sets out. Three rules
/// bind every branch of it:
///
/// * **A serialized page never becomes standalone silently.** Standalone is
///   offered and chosen; it is never the fallback for "recognition could not
///   tell".
/// * **A listing is never an Entry.** The index of a collection is where a
///   Source lives, so adding one writes no Entry and queues no download; the
///   Entries are found by a check the user starts.
/// * **Library membership and downloading are separate acts.** A tap may do
///   both, and the sentences never merge them.
class V2SavePanel extends ConsumerStatefulWidget {
  const V2SavePanel({super.key, required this.url, required this.pageTitle});

  final String url;
  final String pageTitle;

  @override
  ConsumerState<V2SavePanel> createState() => _V2SavePanelState();
}

class _V2SavePanelState extends ConsumerState<V2SavePanel> {
  V2PageStatus? _status;

  /// What the page said about itself, kept apart from what the library knows.
  /// Read once, from the address and the page's own title, and never allowed
  /// to override recognition.
  PageShape? _shape;

  String? _message;
  bool _busy = false;

  /// True while a run that may read this Source forward is in flight.
  ///
  /// **AT MERGE.** The compact running surface for content-affecting source
  /// automation is `running_operation_panel.dart`, which draws *Downloading*
  /// over `QueueRunner` and *Checking* over `CheckController` — each of which
  /// publishes exactly *is it running* and *stop it*. The walk needs the same
  /// two things published by whatever owns it, and then a third branch in that
  /// panel with a Stop wired to its cancel, exactly as `_CheckRunning` does.
  /// Until that seam exists this sentence is what names the operation while it
  /// happens; it claims nothing the app cannot do yet, and it is not a second
  /// status surface.
  bool _readingForward = false;

  /// Test hook, mirroring `QueueRunner.debugSetRunning`: the in-sheet Stop is
  /// exercised without driving a real walk over a real site.
  @visibleForTesting
  void debugSetReadingForward(bool value) =>
      setState(() => _readingForward = value);

  /// The Collection an index page was just added as, so the check can be
  /// offered in the same breath — the listing itself is not an Entry, so
  /// finding what is on it is a separate, visible act.
  ({String id, String name})? _added;

  /// What this page can honestly be saved as. Measured once, when the sheet
  /// opens, so it offers what is actually possible rather than failing after
  /// the choice. A probe that fails degrades to "not analysed", which offers
  /// every mode and says so — not being able to classify a page is a normal
  /// outcome and must never stop the user saving it.
  CaptureCapabilities _capabilities = const CaptureCapabilities.unanalysed();
  CaptureMode? _mode;

  /// True once the user has moved the selection off the detected default. It
  /// travels onto the queue row, because "the page chose this" and "the person
  /// chose this" are different facts about the same value.
  bool _modeIsUserSet = false;

  @override
  void initState() {
    super.initState();
    // The shape that needs no library: enough to describe the page while
    // recognition is still running. `_refresh` settles it.
    _shape = readPageShape(widget.url, pageTitle: widget.pageTitle);
    _refresh();
    _analyse();
  }

  Future<void> _analyse() async {
    final browser = ref.read(browserProvider);
    CaptureCapabilities capabilities;
    try {
      final probe = await browser.probe(withLinks: true);
      capabilities = detectCaptureCapabilities(
        probe,
        config: kDefaultSaveConfig,
      );
    } catch (_) {
      capabilities = const CaptureCapabilities.unanalysed();
    }
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _mode = capabilities.defaultMode;
    });
  }

  Future<void> _refresh() async {
    final status = await v2PageStatusFor(ref, widget.url);
    if (!mounted) return;
    // A listing is claimed only where the library can vouch for it — the
    // address is a Source's own path. On a site nothing is known about there
    // is no such evidence, and an address alone cannot tell a work's listing
    // from an about page, so the sheet asks instead of announcing.
    final onSource = status.result;
    setState(() {
      _status = status;
      _shape = readPageShape(
        widget.url,
        pageTitle: widget.pageTitle,
        sourcePathKey: onSource is RecognisedSource
            ? onSource.source.pathKey
            : null,
      );
    });
  }

  /// The title to suggest for a Collection: what the page named the work,
  /// falling back to the page's own title. A suggestion, never a match key —
  /// it pre-fills a field and filters a list, and selects nothing.
  String get _suggestedTitle {
    final detected = _shape?.detectedTitle?.trim() ?? '';
    return detected.isNotEmpty ? detected : widget.pageTitle.trim();
  }

  /// Run one domain call, show what it said, and start the queue if the user
  /// asked for that in the same tap.
  Future<AddToLibraryReport?> _run(
    Future<AddToLibraryReport> Function() call, {
    bool startNow = false,
    bool readsForward = false,
  }) async {
    setState(() {
      _busy = true;
      _readingForward = readsForward;
    });
    final report = await call();
    if (!mounted) return report;
    setState(() {
      _busy = false;
      _readingForward = false;
      _message = report.sentence ?? _fallbackSentence(report);
    });
    // The explicit Start, and the only one: `startQueuedDownloads` authorises
    // the waiting rows and hands them to whatever runs them. Nothing about
    // queueing implies it.
    if (startNow && report.queued > 0) {
      await startQueuedDownloads(context, ref);
    }
    if (!mounted) return report;
    await _refresh();
    return report;
  }

  /// Only for a domain answer that carried no sentence of its own: a silent
  /// success reads as nothing having happened.
  String _fallbackSentence(AddToLibraryReport report) {
    if (!report.succeeded) return 'Nothing was added.';
    if (report.queued == 0) return 'Added to your library.';
    final queued = report.queued == 1
        ? '1 download'
        : '${report.queued} downloads';
    final short = report.shortfall == 0
        ? ''
        : ' Your library knows ${report.shortfall} fewer than you asked for.';
    return 'Added to your library · $queued waiting for Start.$short';
  }

  Future<void> _download({
    required SaveLimits limits,
    bool startNow = false,
    bool discoverMissing = false,
  }) {
    return _run(
      () => ref.read(v2AddAndDownloadProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        limits: limits,
        discoverMissing: discoverMissing,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
      startNow: startNow,
      readsForward: discoverMissing,
    );
  }

  /// *Download entries…* — the count, then the rows.
  Future<void> _downloadRange(String collectionName) async {
    final scope = await showSaveScopeSheet(
      context,
      collectionName: collectionName,
    );
    if (scope == null || !mounted) return;
    if (!await _authoriseReadingForward(scope)) return;
    await _download(
      limits: scope.limits,
      startNow: scope.startNow,
      discoverMissing: scope.discoverMissing,
    );
  }

  /// A run that may open pages asks the same question the check asks.
  ///
  /// **Why it is asked before the run rather than at the first page.** Whether
  /// anything has to be opened is what the walk finds out; a sheet that
  /// appeared once a gap was found would be asking permission after the app
  /// had already gone to the site. So the question is asked whenever the
  /// answer *could* involve opening one: the count is a claim about the Source
  /// and it is more than the page in front of the user. A count of one opens
  /// nothing and is never gated, and neither is the quieter range, which reads
  /// the library and stops.
  ///
  /// The gate decides **where the user waits**, never whether the work
  /// happens: backing out of the sheet starts nothing and changes nothing, and
  /// this file asks no question of its own about what a person may do — it
  /// reuses the one sheet that asks, exactly as `startCollectionCheck` does.
  Future<bool> _authoriseReadingForward(SaveScopeChoice scope) async {
    final wanted = scope.limits.maxEntries;
    if (!scope.discoverMissing || wanted <= 1) return true;
    final choice = await showStartOptionsSheet(
      context: context,
      ref: ref,
      action: ForegroundGateAction.startEntrySave,
      title: 'Download $wanted entries from here?',
      summary:
          'Scrollary downloads up to $wanted entries, from this page onward — '
          'counting this one. For any your library does not have yet, it '
          'opens this site in the Browser and reads forward to find them, at '
          'most $kMaxWalkPages pages. Nothing else is downloaded, and you can '
          'stop it at any point.',
    );
    if (choice == null || !mounted) return false;
    if (choice == StartChoice.enableAndKeepUsingApp) {
      await setKeepWorkingPreference(ref, true);
      if (!mounted) return false;
    }
    // Browser first, automation second — the order `startCollectionCheck`
    // starts in, and for its reason: the surface has to be there before
    // anything opens a page on it.
    if (choice == StartChoice.inBrowser) {
      ref.read(shellTabRequestProvider).value = 1;
    }
    return true;
  }

  /// Add this page to a Collection that already holds it as a Source.
  Future<void> _addToKnownCollection(
    String collectionId, {
    required String collectionName,
    required bool askHowMany,
  }) async {
    SaveScopeChoice? scope;
    if (askHowMany) {
      scope = await showSaveScopeSheet(context, collectionName: collectionName);
      if (scope == null || !mounted) return;
      if (!await _authoriseReadingForward(scope)) return;
    }
    final discoverMissing = scope?.discoverMissing ?? false;
    await _run(
      () => ref.read(v2AddAndDownloadProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        collectionId: collectionId,
        limits: scope?.limits ?? SaveLimits.forScope(SaveScope.currentPageOnly),
        discoverMissing: discoverMissing,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
      startNow: scope?.startNow ?? false,
      readsForward: discoverMissing,
    );
  }

  /// *Add to a Collection…* — the picker, then (unless this page is a
  /// listing) the count.
  ///
  /// [indexOnly] is the listing case: a Source is established and **no Entry
  /// is created for the index page itself**, so there is nothing to download
  /// and no count to ask for.
  Future<void> _addToCollection({required bool indexOnly}) async {
    final choice = await showCollectionPicker(
      context,
      ref,
      suggestedTitle: _suggestedTitle,
    );
    if (choice == null || !mounted) return;
    final name = switch (choice) {
      ExistingCollectionChoice(:final name) => name,
      NewCollectionChoice(:final name) => name,
    };

    SaveScopeChoice? scope;
    if (!indexOnly) {
      scope = await showSaveScopeSheet(context, collectionName: name);
      if (scope == null || !mounted) return;
      if (!await _authoriseReadingForward(scope)) return;
    }
    final discoverMissing = scope?.discoverMissing ?? false;

    final report = await _run(
      () => ref.read(v2AddAndDownloadProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        collectionId: switch (choice) {
          ExistingCollectionChoice(:final id) => id,
          NewCollectionChoice() => null,
        },
        newCollectionName: switch (choice) {
          ExistingCollectionChoice() => null,
          NewCollectionChoice(:final name) => name,
        },
        // Null is not "no limit" — it is *queue nothing*, which is what a
        // listing asks for.
        limits: scope?.limits,
        discoverMissing: discoverMissing,
        // The sheet already asked the library whether this address is a
        // Source's own page; the orchestration is told rather than guessing
        // it a second time from the URL.
        isListing: indexOnly,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
      startNow: scope?.startNow ?? false,
      readsForward: discoverMissing,
    );

    final collectionId = report?.collectionId;
    if (indexOnly && collectionId != null && mounted) {
      setState(() => _added = (id: collectionId, name: name));
    }
  }

  Future<void> _saveStandalone() {
    return _run(
      () => ref.read(v2SaveStandaloneProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
    );
  }

  Future<void> _start() async {
    await startQueuedDownloads(context, ref);
    if (mounted) await _refresh();
  }

  Future<void> _check(String collectionId, String collectionName) async {
    await startCollectionCheck(
      context,
      ref,
      collectionId,
      collectionName: collectionName,
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final assist = ref.watch(v2AssistProvider);
    return AnimatedBuilder(
      animation: assist,
      builder: (context, _) {
        final request = assist.pendingSelection;
        // A capture holding for the user takes over this slot rather than
        // opening a second surface: the page above stays visible, and the tap
        // that teaches lands on it.
        if (request != null) {
          return RuleSelectionOverlay(run: assist, request: request);
        }
        return _sheet(context);
      },
    );
  }

  Widget _sheet(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = _status;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.pageTitle.isEmpty ? widget.url : widget.pageTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (status == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._body(context, palette, status),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppPalette palette,
    V2PageStatus status,
  ) {
    final task = status.task;
    final live = task != null && !task.state.isTerminal;
    final canDownload = !live && !_busy && _capabilities.canSaveAnything;
    final canStart =
        task != null && task.state == SaveTaskState.queued && !_busy;
    final shape = _shape?.kind ?? PageKind.unknownPage;
    final result = status.result;

    return [
      ..._context(palette, status),
      if (status.hasCopy) _note(palette, 'On this device.'),
      if (live)
        _note(
          palette,
          task.state == SaveTaskState.queued
              ? 'Queued — waiting for Start.'
              : 'Downloading now.',
        ),
      if (_readingForward) ...[
        _note(
          palette,
          'Reading this site forward from this page to find the entries you '
          'asked for. Nothing else is downloaded.',
        ),
        const SizedBox(height: 8),
        // The Stop belongs *here*, not only on the panel underneath. The panel
        // is docked at the bottom of the Browser — which is exactly where this
        // sheet sits — so a user who started the walk from the sheet would
        // have had to dismiss it to find the control for the thing the sheet
        // had just started.
        TextButton.icon(
          key: const ValueKey('sheetStopReadingForward'),
          onPressed: () => ref.read(sourceWalkCancellationProvider).cancel(),
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('Stop finding entries'),
        ),
        _note(
          palette,
          'Stops at the next page. Entries already found stay in your '
          'library.',
        ),
      ],
      if (_message != null) _note(palette, _message!),
      const SizedBox(height: 12),
      // A listing writes no queue row, so what to take off a page is not a
      // question it has. Everywhere else it is.
      if (!(result is Unrecognised && shape == PageKind.collectionIndex)) ...[
        CaptureModeSection(
          capabilities: _capabilities,
          selected: _mode,
          onSelect: (mode) => setState(() {
            _mode = mode;
            _modeIsUserSet = true;
          }),
        ),
        const SizedBox(height: 8),
      ],
      ...switch (result) {
        RecognisedLocation() => _knownEntryActions(
          result,
          canDownload: canDownload,
        ),
        RecognisedSource() => _knownSourceActions(
          palette,
          result,
          shape: shape,
          canDownload: canDownload,
        ),
        Unrecognised() => _unknownActions(
          palette,
          shape: shape,
          canDownload: canDownload,
        ),
      },
      if (canStart)
        FilledButton.tonal(
          key: const ValueKey('v2StartButton'),
          onPressed: _start,
          child: const Text('Start'),
        ),
    ];
  }

  /// What the library knows about this page, in the product's own nouns.
  List<Widget> _context(AppPalette palette, V2PageStatus status) {
    switch (status.result) {
      case RecognisedLocation(:final entry, :final collection, :final location):
        final ordinal = entry.ordinal;
        return [
          _note(
            palette,
            collection == null
                ? 'In your library, on its own.'
                : 'In your library.',
          ),
          if (collection != null) _fact(palette, 'Collection', collection.name),
          if (ordinal != null)
            _fact(palette, 'Entry', _ordinalLabel(ordinal))
          else if (entry.placement == Placement.unplaced.name)
            _fact(palette, 'Entry', 'position not known'),
          ?_hostFact(palette, location.url),
        ];
      case RecognisedSource(:final collection, :final source):
        return [
          _note(palette, 'Adds to ${collection.name}.'),
          _fact(palette, 'Collection', collection.name),
          _fact(palette, 'Source', source.host),
        ];
      case Unrecognised():
        return [
          _note(palette, 'Not in your library yet.'),
          _note(palette, _shapeSentence()),
        ];
    }
  }

  /// What the page said about itself — never what it is going to become.
  String _shapeSentence() => switch (_shape?.kind ?? PageKind.unknownPage) {
    PageKind.entryPage =>
      'This page looks like one entry of a collection, so it is not saved on '
          'its own unless you say so.',
    PageKind.collectionIndex =>
      'This page looks like a collection\'s own listing.',
    PageKind.unknownPage =>
      'Scrollary could not tell what this page is, so it is asking.',
  };

  // ─── the matrix ───────────────────────────────────────────────────────────

  /// An Entry the library already holds: queue rows, and nothing else.
  List<Widget> _knownEntryActions(
    RecognisedLocation result, {
    required bool canDownload,
  }) {
    final collection = result.collection;
    return [
      if (canDownload)
        FilledButton(
          key: const ValueKey('v2DownloadEntry'),
          onPressed: () =>
              _download(limits: SaveLimits.forScope(SaveScope.currentPageOnly)),
          child: const Text('Download this entry'),
        ),
      // "The ones after this" is a question only a Collection's own order can
      // answer; a standalone Entry has none, and asking anyway would be a
      // control that quietly means "just this one".
      if (canDownload && collection != null)
        TextButton(
          key: const ValueKey('v2DownloadEntries'),
          onPressed: () => _downloadRange(collection.name),
          child: const Text('Download entries…'),
        ),
    ];
  }

  /// A page on a Source the library holds: the Entry joins that Collection.
  List<Widget> _knownSourceActions(
    AppPalette palette,
    RecognisedSource result, {
    required PageKind shape,
    required bool canDownload,
  }) {
    final collection = result.collection;
    // A listing is where this Source lives, not a unit of reading: adding an
    // Entry for it would invent one the site never published.
    if (shape == PageKind.collectionIndex) {
      return [
        _note(
          palette,
          'This is this collection\'s listing, so there is no entry here to '
          'add. Checking it is how its entries are found.',
        ),
        const SizedBox(height: 4),
        FilledButton(
          key: const ValueKey('v2CheckCollection'),
          onPressed: _busy
              ? null
              : () => _check(collection.id, collection.name),
          child: Text('Check ${collection.name} for new entries'),
        ),
        ..._followAction(result),
      ];
    }
    return [
      if (canDownload)
        FilledButton(
          key: const ValueKey('v2AddAndDownloadEntry'),
          onPressed: () => _addToKnownCollection(
            collection.id,
            collectionName: collection.name,
            askHowMany: false,
          ),
          child: const Text('Add & download this entry'),
        ),
      if (canDownload)
        TextButton(
          key: const ValueKey('v2AddAndDownloadEntries'),
          onPressed: () => _addToKnownCollection(
            collection.id,
            collectionName: collection.name,
            askHowMany: true,
          ),
          child: const Text('Add & download…'),
        ),
      ..._followAction(result),
    ];
  }

  /// Following is library membership and downloads nothing — the two verbs
  /// are offered side by side and never folded together (PRODUCT.md §2.4).
  List<Widget> _followAction(RecognisedSource result) => [
    if (!result.followed)
      TextButton(
        key: const ValueKey('v2FollowCollection'),
        onPressed: _busy
            ? null
            : () async {
                await v2FollowCollection(ref, result.collection.id);
                await _refresh();
              },
        child: Text('Follow ${result.collection.name}'),
      ),
  ];

  /// A site the library knows nothing about. What is offered depends on what
  /// the page said it is — and the user answers, either way.
  List<Widget> _unknownActions(
    AppPalette palette, {
    required PageKind shape,
    required bool canDownload,
  }) {
    final added = _added;
    return switch (shape) {
      // An entry of something. Collection first, standalone demoted to the
      // deliberate choice it is.
      PageKind.entryPage => [
        if (canDownload)
          FilledButton(
            key: const ValueKey('v2AddToCollection'),
            onPressed: () => _addToCollection(indexOnly: false),
            child: const Text('Add to a Collection…'),
          ),
        _adoptionNote(palette),
        if (canDownload)
          TextButton(
            key: const ValueKey('v2SaveStandalone'),
            onPressed: _saveStandalone,
            child: const Text('Save as a standalone entry'),
          ),
      ],
      // The listing itself. A Source, no Entry, and the check offered after.
      PageKind.collectionIndex => [
        if (added == null)
          FilledButton(
            key: const ValueKey('v2AddCollection'),
            onPressed: _busy ? null : () => _addToCollection(indexOnly: true),
            child: const Text('Add this collection to your library'),
          ),
        _adoptionNote(palette),
        _note(
          palette,
          'A listing is not an entry, so nothing is downloaded by adding it. '
          'Checking the collection is how its entries are found, and you '
          'start that yourself.',
        ),
        if (added != null) ...[
          const SizedBox(height: 4),
          FilledButton(
            key: const ValueKey('v2CheckAfterAdd'),
            onPressed: _busy ? null : () => _check(added.id, added.name),
            child: Text('Check ${added.name} for new entries'),
          ),
        ],
      ],
      // The page did not say. Standalone is the honest answer, and every
      // other answer is offered rather than assumed — including the one the
      // app cannot tell from an about page on a site it knows nothing about.
      PageKind.unknownPage => [
        if (canDownload)
          FilledButton(
            key: const ValueKey('v2SaveStandalone'),
            onPressed: _saveStandalone,
            child: const Text('Save as a standalone entry'),
          ),
        if (canDownload)
          TextButton(
            key: const ValueKey('v2AddToCollection'),
            onPressed: () => _addToCollection(indexOnly: false),
            child: const Text('Add to a Collection…'),
          ),
        if (_shape?.couldBeListing ?? false) ...[
          _note(
            palette,
            'If this page lists a collection\'s entries rather than being '
            'one of them, add the site itself instead — nothing is '
            'downloaded, and checking the collection is how its entries are '
            'found.',
          ),
          TextButton(
            key: const ValueKey('v2AddCollection'),
            onPressed: _busy ? null : () => _addToCollection(indexOnly: true),
            child: const Text('Add this site as a collection\'s source'),
          ),
        ],
        if (added != null) ...[
          const SizedBox(height: 4),
          FilledButton(
            key: const ValueKey('v2CheckAfterAdd'),
            onPressed: _busy ? null : () => _check(added.id, added.name),
            child: Text('Check ${added.name} for new entries'),
          ),
        ],
      ],
    };
  }

  /// The one sentence that keeps the two answers apart. Choosing a Collection
  /// you already have and starting a new one are different operations, and the
  /// picker's rows do not say which is which on their own.
  Widget _adoptionNote(AppPalette palette) => _note(
    palette,
    'Choosing a collection you already have adds this site as another source '
    'of it. Creating one starts a new collection with this site as its first '
    'source.',
  );

  // ─── small pieces ─────────────────────────────────────────────────────────

  Widget _note(AppPalette palette, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.inkMuted),
    ),
  );

  Widget _fact(AppPalette palette, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      '$label · $value',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(size: 12, color: palette.inkFaint),
    ),
  );

  /// The site this address sits on, when the address has one.
  Widget? _hostFact(AppPalette palette, String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? null : _fact(palette, 'Source', host);
  }

  /// `12`, not `12.0`; `99.5` stays `99.5`, because 100 and 99.5 are two
  /// Entries and printing them the same would say otherwise.
  static String _ordinalLabel(double ordinal) =>
      ordinal == ordinal.roundToDouble()
      ? ordinal.toStringAsFixed(0)
      : '$ordinal';
}
