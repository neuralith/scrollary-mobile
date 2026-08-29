import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_controller.dart';
import '../capability/foreground_gate.dart';
import '../core/config.dart';
import '../data/recognition_index.dart';
import '../domain/domain.dart';
import '../library/collection_identity.dart' show PageHints;
import '../library_ui/collection_picker.dart';
import '../library_ui/providers.dart';
import '../library_ui/save_scope_section.dart';
import '../providers.dart';
import '../recognition/history.dart';
import '../recognition/page_kind.dart';
import '../recognition/recognise.dart';
import '../recognition/reconcile.dart';
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

  /// True when the run has just opened this address to find out which Entry
  /// it is, and the browser is still on it (V2-D56). Passed straight through
  /// to the capture, including on the second attempt after the user points at
  /// the reading area — that assistance happens on the same loaded page.
  bool pageAlreadyLoaded = false,
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
      pageAlreadyLoaded: pageAlreadyLoaded,
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

/// What the sheet asks the Browser to do **once it has closed itself**.
///
/// The save sheet is a modal route over the Browser, and a start it performs
/// itself runs behind it: `QueueRunner.start` does not return until the batch
/// is done, so the sheet that awaited it stayed on screen over the page it had
/// just sent the app to read. *Start now* only ever appeared to work because
/// `showBrowserSurface` pops every route above the shell on its way past —
/// which dismissed this sheet as a side effect, and did nothing at all for
/// *Start and keep using*, whose whole promise is that the user
/// carries on where they are.
///
/// So the sheet answers and closes, and [BrowserScreen] — which is still
/// mounted, and owns the surface the run needs — performs the Start with this.
/// [where] is what the user already decided; null means nobody has asked yet,
/// which is the queue's own Start button and the one place the gate should
/// still ask.
class SaveSheetStart {
  const SaveSheetStart({this.where});

  final StartWhere? where;
}

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

  /// The Collection an index page was just added as, so the check can be
  /// offered in the same breath — the listing itself is not an Entry, so
  /// finding what is on it is a separate, visible act.
  ({String id, String name})? _added;

  /// *How much*, held here rather than returned by a sheet after this one
  /// (V2-D62). Built when the sheet learns there is something to download —
  /// which is as soon as recognition settles for a page already in a
  /// Collection, and when the picker answers for one that is not.
  SaveScopeController? _scope;

  /// The Collection this save is going to, once the user has said. Null while
  /// the answer is the page's own — a known Entry or a known Source needs no
  /// picker — and null again for a page nobody has chosen a Collection for.
  CollectionChoice? _chosen;

  /// What this page can honestly be saved as. Measured once, when the sheet
  /// opens, so it offers what is actually possible rather than failing after
  /// the choice. A probe that fails degrades to "not analysed", which offers
  /// every mode and says so — not being able to classify a page is a normal
  /// outcome and must never stop the user saving it.
  CaptureCapabilities _capabilities = const CaptureCapabilities.unanalysed();
  CaptureMode? _mode;

  /// What the page volunteered about itself — its `h1`, its `og:title`, its
  /// breadcrumb trail. Read from the same probe the capabilities come from,
  /// and fed back into [readPageShape]: the number and the name a site prints
  /// in a heading are evidence the address alone does not carry.
  PageHints _hints = const PageHints();

  /// True once the user has moved the selection off the detected default. It
  /// travels onto the queue row, because "the page chose this" and "the person
  /// chose this" are different facts about the same value.
  bool _modeIsUserSet = false;

  /// What this Collection is normally captured as, when the user has said.
  ///
  /// A *proposal*: `CaptureCapabilities.resolve` decides whether this page can
  /// honour it, and a page that cannot falls back and asks. The preference is
  /// left alone either way — it was an answer about the work, not about the
  /// page in front of the user.
  CaptureMode? _remembered;

  /// The Collection this sheet's answer belongs to, once the library has said
  /// which one that is. Null for a page that is not in a Collection, and a
  /// standalone save never writes a preference for anything.
  String? _preferenceCollectionId;

  /// True while the user has the *What to save* block open.
  ///
  /// It used to be a one-way door — opened by the collapsed line and closed by
  /// nothing — so a user who tapped it to look at the options had no way back
  /// to the one-line answer and the sheet grew by three rows for the rest of
  /// its life. It is a dropdown; the control that opens it closes it.
  bool _modesExpanded = false;

  /// Whether there is a settled answer for this work that the block can be
  /// collapsed to. **Not** whether it currently is — see [_modesCollapsed].
  ///
  /// **What this deliberately does not do is trust an unscrolled page about
  /// images** (V2-D65). This sheet probes before anything has been scrolled,
  /// so on a lazy reader almost none of the page's images have loaded and
  /// *Images only* measures as impossible. Vetoing the Collection's settled
  /// answer on that put the full block back on every save of a work the user
  /// had already answered for — while the engine, which measures the settled
  /// page, would have honoured it. So only a block the unscrolled page can
  /// actually vouch for counts: no readable text is a fact, not enough images
  /// *yet* is not.
  bool get _modeIsRemembered {
    final remembered = _remembered;
    if (remembered == null) return false;
    if (_capabilities.allows(remembered)) return true;
    return !(_capabilities.blocked[remembered]?.survivesAnUnscrolledPage ??
        false);
  }

  /// Whether the one-line answer is standing in for the block right now.
  ///
  /// A tap on a mode row opens the question for good on this sheet: what is on
  /// screen is then the person's answer, not the work's, and collapsing it
  /// back to a line that reads like a remembered one would misdescribe it.
  bool get _modesCollapsed =>
      _modeIsRemembered && !_modesExpanded && !_modeIsUserSet;

  @override
  void dispose() {
    _scope?.dispose();
    super.dispose();
  }

  /// Build (or rebuild) the *how much* state for what this save is going to.
  ///
  /// Rebuilt rather than mutated when the target changes, because a Collection
  /// about to be created is named inside it and that is fixed at construction.
  /// Null where there is no range to ask about: a listing is not an Entry, a
  /// standalone Entry has no order to count along, and a page whose Collection
  /// nobody has chosen yet has nothing to count *of*.
  void _settleScope({NewCollectionNaming? naming, required bool wanted}) {
    if (!wanted) {
      if (_scope == null) return;
      _scope!.dispose();
      setState(() => _scope = null);
      return;
    }
    if (_scope != null &&
        _scope!.naming?.suggestedName == naming?.suggestedName &&
        (_scope!.naming == null) == (naming == null)) {
      return;
    }
    final replaced = _scope;
    setState(() => _scope = SaveScopeController(naming: naming));
    replaced?.dispose();
  }

  /// What this Collection's entries have already cost, fetched **after** the
  /// sheet is usable (V2-D62). It walks every Entry of the Collection, and no
  /// save should wait on that to be able to choose a range; the estimate line
  /// appears when the answer arrives.
  Future<void> _loadEstimate(String? collectionId) async {
    final scope = _scope;
    if (scope == null || collectionId == null) return;
    final costs = await _downloadedBytesOf(collectionId);
    if (!mounted || _scope != scope) return;
    scope.alreadyDownloadedBytes = costs;
  }

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
    var hints = const PageHints();
    try {
      final probe = await browser.probe(withLinks: true);
      capabilities = detectCaptureCapabilities(
        probe,
        config: kDefaultSaveConfig,
      );
      hints = probe.pageHints;
    } catch (_) {
      capabilities = const CaptureCapabilities.unanalysed();
    }
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _hints = hints;
      _settleMode();
    });
    await _refresh();
  }

  /// What this save will produce, given everything the sheet knows so far.
  ///
  /// Called whenever either input settles — the page's capabilities, or the
  /// Collection's remembered answer — because they arrive from two async
  /// reads in no fixed order and whichever lands second must not undo the
  /// first. A choice the **user** made outranks both and is never recomputed.
  void _settleMode() {
    if (_modeIsUserSet) return;
    // A remembered answer the sheet is still standing behind is passed on as
    // it is: `CaptureCapabilities.resolve` runs again inside the engine, on
    // the settled page, and falls back there with an explanation if the mode
    // genuinely cannot be honoured (V2-D65). Resolving it here as well would
    // substitute a fallback chosen from a measurement the engine itself
    // refuses to decide from.
    _mode = _modeIsRemembered
        ? _remembered
        : _capabilities.resolve(_remembered).mode;
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
        hints: _hints,
        sourcePathKey: onSource is RecognisedSource
            ? onSource.source.pathKey
            : null,
      );
    });
    final collectionId = switch (status.result) {
      RecognisedLocation(:final collection) => collection?.id,
      RecognisedSource(:final collection) => collection.id,
      Unrecognised() => null,
    };
    _settleScopeFor(status);
    unawaited(_loadEstimate(collectionId));
    await _loadPreference(collectionId);
  }

  /// Whether this page has a range to ask about at all, and under what name.
  void _settleScopeFor(V2PageStatus status) {
    final shape = _shape?.kind ?? PageKind.unknownPage;
    final listing = shape == PageKind.collectionIndex;
    switch (status.result) {
      // A Collection's own order is what "the ones after this" counts along.
      // A standalone Entry has none, so it is offered its one page and no
      // range — asking anyway would be a control that quietly means "just
      // this one".
      case RecognisedLocation(:final collection):
        _settleScope(wanted: collection != null);
      case RecognisedSource():
        _settleScope(wanted: !listing);
      case Unrecognised():
        // Nothing to count of until the user has said which Collection this
        // belongs to. The picker is still first (V2-D45, V2-D57).
        _settleScope(
          wanted: !listing && _chosen != null,
          naming: switch (_chosen) {
            NewCollectionChoice(:final name) => NewCollectionNaming(
              suggestedName: name,
              host: Uri.tryParse(widget.url)?.host ?? '',
            ),
            _ => null,
          },
        );
    }
  }

  /// What this Collection is normally captured as — asked once the library has
  /// said which Collection this page belongs to, and not before.
  Future<void> _loadPreference(String? collectionId) async {
    final remembered = await ref
        .read(capturePreferenceProvider)
        .of(collectionId);
    if (!mounted) return;
    setState(() {
      _preferenceCollectionId = collectionId;
      _remembered = remembered;
      _settleMode();
    });
  }

  /// Keep what this save was made with, for the Collection it went to.
  ///
  /// **Proceeding is accepting** (V2-D61). The rule used to be that only a tap
  /// on a mode row counted, which asked a user who was already looking at
  /// *Images only* to tap *Images only* before the app would believe them —
  /// so a work saved as images fifty times running still asked on the
  /// fifty-first. Starting or queueing a save with the mode on screen is an
  /// answer about the work, and it is recorded as one.
  ///
  /// Four things it will not do.
  ///
  /// * **Nothing is written unless something was queued** — [queued] is the
  ///   caller's answer to *did a capture actually get asked for*. A sheet
  ///   opened and dismissed, a listing that writes no row, and a refusal all
  ///   say nothing about the work.
  /// * **An answer already given is only changed by a tap.** When the
  ///   Collection has one, an untouched mode is left alone — and it has to be,
  ///   because the mode on screen may be the *fallback* for a page that could
  ///   not honour the standing answer (V2-D53). Overwriting a Collection kept
  ///   as images because one entry of it had no images is precisely the
  ///   mistake that rule exists to prevent.
  /// * **A standalone save writes nothing**: no Collection, no work to be a
  ///   standing answer for (I3).
  /// * **One Collection's answer is never written by an Entry that landed
  ///   somewhere else** — the id comes from the report, which names where
  ///   this save actually went.
  Future<void> _rememberMode(
    String? collectionId, {
    required int queued,
  }) async {
    final mode = _mode;
    if (mode == null || collectionId == null || queued == 0) return;
    final preferences = ref.read(capturePreferenceProvider);
    if (!_modeIsUserSet && await preferences.isAnswered(collectionId)) return;
    await preferences.remember(collectionId, mode);
    if (!mounted) return;
    setState(() {
      _preferenceCollectionId = collectionId;
      _remembered = mode;
    });
  }

  /// What entries of [collectionId] have already cost on this device.
  ///
  /// The estimate's only input. Empty is the honest answer for a Collection
  /// nothing has been downloaded from, and the sheet then says nothing about
  /// size rather than inventing a figure.
  Future<List<int>> _downloadedBytesOf(String? collectionId) async {
    if (collectionId == null) return const [];
    final services = ref.read(libraryUiServicesProvider);
    final entries = await services.entries.entriesOf(collectionId);
    final held = <int>[];
    for (final entry in entries) {
      final copy = await services.offline.activeCopyOf(entry.id);
      if (copy != null && copy.byteSize > 0) held.add(copy.byteSize);
    }
    return held;
  }

  /// The title to suggest for a Collection: what the page named the work,
  /// falling back to the page's own title. A suggestion, never a match key —
  /// it pre-fills a field and filters a list, and selects nothing.
  String get _suggestedTitle {
    final detected = _shape?.detectedTitle?.trim() ?? '';
    return detected.isNotEmpty ? detected : widget.pageTitle.trim();
  }

  /// Run one domain call, show what it said, and hand the Start back to the
  /// Browser if the user asked for one in the same tap.
  ///
  /// **The sheet closes before anything runs.** It used to await
  /// `startQueuedDownloads` itself, and that call does not return until the
  /// whole batch has been captured — so the sheet sat over the Browser for the
  /// length of the run. *Start now* escaped that only because
  /// `showBrowserSurface` pops the routes above the shell on its way to the
  /// Browser; *Start and keep using* has no such pop and left the
  /// user staring at the sheet they had just answered. Both now answer,
  /// dismiss, and let [BrowserScreen] start the queue on the surface that
  /// outlives this route ([SaveSheetStart]).
  ///
  /// Everything this sheet still owns is done **before** the pop: the message
  /// is shown, and the work's standing answer is written (V2-D61). What is
  /// dropped is the refresh, which is a re-read for a sheet that is leaving.
  Future<AddToLibraryReport?> _run(
    Future<AddToLibraryReport> Function() call, {
    SaveStartMode start = SaveStartMode.queueOnly,
  }) async {
    setState(() => _busy = true);
    final report = await call();
    if (!mounted) return report;
    setState(() {
      _busy = false;
      _message = report.sentence ?? _fallbackSentence(report);
    });
    await _rememberMode(
      report.collectionId ?? _preferenceCollectionId,
      queued: report.queued,
    );
    if (!mounted) return report;
    // The explicit Start, and the only one. Nothing about queueing implies it
    // — and the launch the user already chose travels with the answer, so
    // nothing asks them a second time where they would like to wait.
    if (start.starts && report.queued > 0) {
      _closeWith(SaveSheetStart(where: start.where));
      return report;
    }
    await _refresh();
    return report;
  }

  /// Close this sheet, telling the Browser what to do next.
  ///
  /// `maybePop` rather than `pop`: the panel is also pumped directly in a
  /// widget test, where there is no route of its own to dismiss, and a sheet
  /// that has already gone must not take the Browser with it.
  void _closeWith(SaveSheetStart start) {
    Navigator.of(context).maybePop(start);
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
    SaveStartMode start = SaveStartMode.queueOnly,
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
      start: start,
    );
  }

  /// The range, and the launch under it — the whole of what this sheet asks
  /// once the target is known (V2-D62).
  ///
  /// It replaces *Download this entry* and *Download entries…*, which were two
  /// buttons for one question: the first said what the range block's first row
  /// says, and the second opened a second sheet to ask the rest of it.
  List<Widget> _scopeAndLaunch() {
    final scope = _scope;
    if (scope == null) return const [];
    return [
      SaveScopeSection(controller: scope),
      const SizedBox(height: 10),
      ..._captureBlock(),
      const SizedBox(height: 12),
      _launchActions(context, _submitScope),
    ];
  }

  /// *What to save*: one line once the Collection has answered, the full block
  /// until it has.
  ///
  /// Everything the block says stays one tap away, and the line is only drawn
  /// for an answer this page has not reliably ruled out (V2-D65).
  List<Widget> _captureBlock() => [
    if (_modesCollapsed)
      RememberedCaptureLine(
        mode: _remembered!,
        onChange: () => setState(() => _modesExpanded = true),
      )
    else
      CaptureModeSection(
        capabilities: _capabilities,
        selected: _mode,
        // The heading is the way back to the line, and only where there is a
        // line to go back to: on a work with no settled answer this block is
        // the question itself and closing it would hide it.
        onCollapse: _modeIsRemembered && !_modeIsUserSet
            ? () => setState(() => _modesExpanded = false)
            : null,
        onSelect: (mode) => setState(() {
          _mode = mode;
          _modeIsUserSet = true;
        }),
      ),
  ];

  /// One launch, validated where it was typed and routed by what the page is.
  ///
  /// Null from [SaveScopeController.choiceFor] means a refusal is on screen
  /// with the keyboard back under the thumb — nothing is queued and nothing
  /// closes.
  Future<void> _submitScope(SaveStartMode start) async {
    final scope = _scope;
    final status = _status;
    if (scope == null || status == null || _busy) return;
    final choice = scope.choiceFor(start);
    if (choice == null) return;
    _prepareLaunch(choice);
    switch (status.result) {
      case RecognisedLocation():
        await _download(
          limits: choice.limits,
          start: choice.start,
          discoverMissing: choice.discoverMissing,
        );
      case RecognisedSource(:final collection):
        await _addToKnownCollection(collection.id, choice: choice);
      case Unrecognised():
        await _addToChosenCollection(choice);
    }
  }

  /// The launch row the scope sheet draws — **the whole of the start
  /// decision, asked once**.
  ///
  /// **Why it lives here and not in the sheet.** Where the user waits is the
  /// one thing the foreground boundary owns (CLAUDE.md, "Free and Pro"), and
  /// `library_ui/` may not reach it. So the sheet that asks *how many* is
  /// handed these rows and asks *how many and what happens next* in one
  /// breath, and the queue's own Start is told the answer rather than asking
  /// for it again.
  ///
  /// What this replaces: a *Start now* button in the sheet, a gate sheet
  /// before the run asking where to wait, and a second gate sheet from the
  /// Start afterwards asking the same thing. Three questions about one
  /// decision, and one combination of them — *Add to queue*, then *Start in
  /// Browser* — started nothing at all while showing the user the Browser.
  ///
  /// The gate decides where the user waits, never whether the work happens:
  /// dismissing the sheet starts nothing and changes nothing, and *Queue only*
  /// is a full answer that needs no capability.
  Widget _launchActions(
    BuildContext sheetContext,
    void Function(SaveStartMode) submit,
  ) {
    final gate = ref.read(foregroundMultitaskingProvider).startGate;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ForegroundStartActions(
          gate: gate,
          action: ForegroundGateAction.startEntrySave,
          inBrowserLabel: 'Start now',
          keepUsingAppLabel: 'Start and keep using',
          // The rows are the tallest thing on a sheet that now asks three
          // questions above them, and each one's sentence was a variation on
          // the same rule. Said once, below (V2-D65), and still spoken in
          // full by every row.
          dense: true,
          onChoice: (choice) async {
            if (choice == StartChoice.enableAndKeepUsingApp) {
              await setKeepWorkingPreference(ref, true);
            }
            submit(switch (choice) {
              StartChoice.inBrowser => SaveStartMode.startNow,
              StartChoice.keepUsingApp ||
              StartChoice.enableAndKeepUsingApp => SaveStartMode.keepWorking,
            });
          },
        ),
        const SizedBox(height: 7),
        // The same row the starts are drawn as (`GateActionRow`), for the same
        // reason they are dense here: this is the third answer to one
        // question, and an outlined button beside two cards read as a
        // different kind of control rather than as the option that starts
        // nothing.
        GateActionRow(
          optionKey: 'saveScopeAddToQueue',
          icon: Icons.schedule,
          label: 'Queue only',
          sub: 'The work waits in your library until you start it.',
          dense: true,
          onTap: () => submit(SaveStartMode.queueOnly),
        ),
        const SizedBox(height: 7),
        // The rule the rows above no longer each repeat, stated once where it
        // still has to be visible: nothing runs on its own, and nothing runs
        // at all once the app is not in front of the user. One line, because
        // it is the only supporting sentence left under this group.
        Text(
          'Nothing runs on its own, or while the app is not in front of you.',
          key: const ValueKey('saveLaunchNote'),
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppPalette.of(sheetContext).inkFaint,
          ),
        ),
      ],
    );
  }

  /// Browser first, automation second — the order `startCollectionCheck`
  /// starts in, and for its reason: the surface has to be there before
  /// anything opens a page on it.
  ///
  /// Only the tab, and only for the launch that means *watch it happen*.
  /// Whether anything is authorised at all is [SaveScopeChoice.start]'s, and
  /// it is answered where the user answered it.
  void _prepareLaunch(SaveScopeChoice scope) {
    if (scope.start == SaveStartMode.startNow) {
      ref.read(shellTabRequestProvider).value = kBrowserTabIndex;
    }
  }

  /// Add this page to a Collection that already holds it as a Source.
  Future<void> _addToKnownCollection(
    String collectionId, {
    required SaveScopeChoice choice,
  }) async {
    await _run(
      () => ref.read(v2AddAndDownloadProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        collectionId: collectionId,
        limits: choice.limits,
        discoverMissing: choice.discoverMissing,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
      start: choice.start,
    );
  }

  /// *Add to a Collection…* — the picker, and then **this same sheet**.
  ///
  /// [indexOnly] is the listing case: a Source is established and **no Entry
  /// is created for the index page itself**, so there is nothing to download,
  /// no range to ask about, and the whole thing is done in one call.
  ///
  /// **The picker is always first** (V2-D45, V2-D57): the Collections the user
  /// already has must be visible before another is started, or a work held
  /// from a second site quietly becomes a duplicate. What it answers does not
  /// open anything — it turns the sheet the user is already looking at into
  /// the one that saves, with the range block and, for a Collection about to
  /// exist, its name (V2-D62).
  Future<void> _chooseCollection({required bool indexOnly}) async {
    final choice = await showCollectionPicker(
      context,
      ref,
      suggestedTitle: _suggestedTitle,
      confirmNameHere: indexOnly,
    );
    if (choice == null || !mounted) return;

    if (!indexOnly) {
      setState(() => _chosen = choice);
      final status = _status;
      if (status != null) _settleScopeFor(status);
      unawaited(
        _loadEstimate(switch (choice) {
          ExistingCollectionChoice(:final id) => id,
          NewCollectionChoice() => null,
        }),
      );
      return;
    }

    // A listing: no Entry, no range, nothing queued. Answered and done.
    final name = switch (choice) {
      ExistingCollectionChoice(:final name) => name,
      NewCollectionChoice(:final name) => name,
    };
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
          NewCollectionChoice() => name,
        },
        // Null is not "no limit" — it is *queue nothing*, which is what a
        // listing asks for.
        isListing: true,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
    );
    final collectionId = report?.collectionId;
    if (collectionId != null && mounted) {
      setState(() => _added = (id: collectionId, name: name));
    }
  }

  /// The Collection the picker answered, with the range this sheet then asked
  /// for. A new one is created by the same atomic call it always was; the name
  /// is whatever the field on this sheet ended up holding.
  Future<void> _addToChosenCollection(SaveScopeChoice choice) async {
    final chosen = _chosen;
    if (chosen == null) return;
    final name =
        choice.collectionName ??
        switch (chosen) {
          ExistingCollectionChoice(:final name) => name,
          NewCollectionChoice(:final name) => name,
        };
    await _run(
      () => ref.read(v2AddAndDownloadProvider)(
        ref,
        url: widget.url,
        pageTitle: widget.pageTitle,
        collectionId: switch (chosen) {
          ExistingCollectionChoice(:final id) => id,
          NewCollectionChoice() => null,
        },
        newCollectionName: switch (chosen) {
          ExistingCollectionChoice() => null,
          NewCollectionChoice() => name,
        },
        limits: choice.limits,
        discoverMissing: choice.discoverMissing,
        captureMode: _mode,
        captureModeIsUserSet: _modeIsUserSet,
      ),
      start: choice.start,
    );
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

  /// The queue's own Start, for a row that is already waiting.
  ///
  /// Nobody has been asked where they would like to wait, so no answer travels
  /// with it and the gate asks — which is right here, and only here. The sheet
  /// closes first for the same reason every other launch does.
  void _start() => _closeWith(const SaveSheetStart());

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
    final scope = _scope;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        // The keyboard inset pads the sheet, so anything below the scrolling
        // body sits on the line directly above the keyboard. That is where the
        // number pad's OK belongs, and pinning it there is why this is a
        // column rather than a bare scroll view (V2-D62).
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
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
            ),
            // Offered only while the number pad is up, and reachable whatever
            // the sheet above it is scrolled to.
            if (scope != null)
              AnimatedBuilder(
                animation: scope,
                builder: (context, _) => scope.showsOkBar
                    ? SaveCountOkBar(onPressed: scope.confirmCount)
                    : const SizedBox.shrink(),
              ),
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
      // No Stop here, and no running note: a start closes this sheet, so what
      // it started is watched and stopped on the panel docked under the
      // Browser — the one surface that is there for the whole run.
      if (_message != null) _note(palette, _message!),
      const SizedBox(height: 12),
      // A listing writes no queue row, so what to take off a page is not a
      // question it has. Everywhere else it is.
      // Where there is a range, *what to save* is drawn under it, because the
      // range is the decision the user came to make and the mode is usually
      // already settled (V2-D65). Where there is not — a standalone Entry, a
      // page whose Collection nobody has chosen yet — it is drawn here, above
      // whatever single action there is.
      if (_scope == null &&
          !(result is Unrecognised && shape == PageKind.collectionIndex)) ...[
        ..._captureBlock(),
        const SizedBox(height: 10),
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
      case RecognisedLocation(:final entry, :final collection):
        final ordinal = entry.ordinal;
        // **One line, not three** (V2-D62). Where this is and what it is are
        // one fact — *Alpha · Entry 12* — and the site was three lines above
        // it in the address bar of the Browser the sheet is sitting on.
        final position = ordinal != null
            ? 'Entry ${_ordinalLabel(ordinal)}'
            : entry.placement == Placement.unplaced.name
            ? 'position not known'
            : null;
        if (collection == null) {
          return [_note(palette, 'In your library, on its own.')];
        }
        return [
          _fact(
            palette,
            null,
            position == null
                ? collection.name
                : '${collection.name} · $position',
          ),
        ];
      case RecognisedSource(:final collection):
        return [_note(palette, 'Adds to ${collection.name}.')];
      case Unrecognised():
        return [
          _note(palette, 'Not in your library yet.'),
          _note(palette, _shapeSentence()),
        ];
    }
  }

  /// What the page said about itself — never what it is going to become.
  String _shapeSentence() => switch (_shape?.kind ?? PageKind.unknownPage) {
    PageKind.entryPage => 'Looks like one entry of a collection.',
    PageKind.collectionIndex => 'Looks like a collection\'s own listing.',
    PageKind.unknownPage => 'Scrollary could not tell what this page is.',
  };

  // ─── the matrix ───────────────────────────────────────────────────────────

  /// An Entry the library already holds: the range and the launch, here.
  List<Widget> _knownEntryActions(
    RecognisedLocation result, {
    required bool canDownload,
  }) {
    if (!canDownload) return const [];
    // A standalone Entry has no Collection order to count along, so it is
    // offered its one page and nothing else — the range block would be a
    // control that quietly meant "just this one".
    if (result.collection == null) {
      return [
        FilledButton(
          key: const ValueKey('v2DownloadEntry'),
          onPressed: () =>
              _download(limits: SaveLimits.forScope(SaveScope.currentPageOnly)),
          child: const Text('Download this entry'),
        ),
      ];
    }
    return _scopeAndLaunch();
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
        _note(palette, 'The listing — check it to find new entries.'),
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
    return [if (canDownload) ..._scopeAndLaunch(), ..._followAction(result)];
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
        // The picker is still first — the Collections already held must be
        // visible before another is started (V2-D45, V2-D57) — and what it
        // answers turns this same sheet into the one that saves (V2-D62).
        if (canDownload && _scope == null)
          FilledButton(
            key: const ValueKey('v2AddToCollection'),
            onPressed: () => _chooseCollection(indexOnly: false),
            child: const Text('Add to a Collection…'),
          ),
        if (_scope == null) _adoptionNote(palette),
        if (canDownload && _scope != null) ..._scopeAndLaunch(),
        if (canDownload && _scope == null)
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
            onPressed: _busy ? null : () => _chooseCollection(indexOnly: true),
            child: const Text('Add this collection to your library'),
          ),
        _adoptionNote(palette),
        _note(palette, 'Nothing is downloaded — checking finds the entries.'),
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
        if (canDownload && _scope == null)
          FilledButton(
            key: const ValueKey('v2SaveStandalone'),
            onPressed: _saveStandalone,
            child: const Text('Save as a standalone entry'),
          ),
        if (canDownload && _scope == null)
          TextButton(
            key: const ValueKey('v2AddToCollection'),
            onPressed: () => _chooseCollection(indexOnly: false),
            child: const Text('Add to a Collection…'),
          ),
        if (canDownload && _scope != null) ..._scopeAndLaunch(),
        if (_scope == null && (_shape?.couldBeListing ?? false)) ...[
          _note(
            palette,
            'If this page lists a collection\'s entries rather than being '
            'one of them, add the site itself instead — nothing is '
            'downloaded, and checking the collection is how its entries are '
            'found.',
          ),
          TextButton(
            key: const ValueKey('v2AddCollection'),
            onPressed: _busy ? null : () => _chooseCollection(indexOnly: true),
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
    'An existing collection gains this site as another source.',
  );

  // ─── small pieces ─────────────────────────────────────────────────────────

  Widget _note(AppPalette palette, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.inkMuted),
    ),
  );

  Widget _fact(AppPalette palette, String? label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      label == null ? value : '$label · $value',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(size: 12, color: palette.inkFaint),
    ),
  );

  /// `12`, not `12.0`; `99.5` stays `99.5`, because 100 and 99.5 are two
  /// Entries and printing them the same would say otherwise.
  static String _ordinalLabel(double ordinal) =>
      ordinal == ordinal.roundToDouble()
      ? ordinal.toStringAsFixed(0)
      : '$ordinal';
}
