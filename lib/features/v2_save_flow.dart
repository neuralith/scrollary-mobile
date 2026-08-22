import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_controller.dart';
import '../core/config.dart';
import '../data/recognition_index.dart';
import '../domain/domain.dart';
import '../library_ui/providers.dart';
import '../providers.dart';
import '../recognition/history.dart';
import '../recognition/recognise.dart';
import '../save/capture_mode.dart';
import '../save/capture_policy.dart';
import '../save/entry_capture.dart';
import '../save/page_hint.dart';
import '../save/page_hint_repository.dart';
import '../save/queue_task.dart';
import '../save/selection_request.dart';
import '../ui/palette.dart';
import 'capture_mode_section.dart';
import 'selection_overlay.dart';

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
      // The page sits on a known Source at a new address: the Entry joins its
      // Collection, honestly unplaced until something numbers it.
      final (entry, violation) = await services.entries.createInCollection(
        collectionId: collection.id,
        placement: Placement.unplaced,
        title: pageTitle,
      );
      if (entry == null) {
        return 'Could not add this page: ${violation?.message}';
      }
      final (location, locViolation) = await services.entries.addLocation(
        entryId: entry.id,
        url: url,
        urlKey: keys.urlKey,
        sourceId: source.id,
        discoveryBasis: 'userSave',
      );
      if (location == null) {
        return 'Could not add this page: ${locViolation?.message}';
      }
      entryId = entry.id;
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
/// **Blocked state, recorded here so the next lane finds it.** The queue's
/// worker still calls [EntryCaptureService.capture] directly: the capture
/// service is built inside `main.dart`'s composition and the shell's hooks
/// are attached in `app.dart`, neither of which this lane may edit. Routing
/// `QueueRunner` through this function — handing it the [V2AssistController]
/// from [v2AssistProvider] — is the one composition step left, and until it
/// is taken a capture that needs the reading area fails instead of asking.
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

/// The sheet behind the Browser's save control.
class V2SavePanel extends ConsumerStatefulWidget {
  const V2SavePanel({super.key, required this.url, required this.pageTitle});

  final String url;
  final String pageTitle;

  @override
  ConsumerState<V2SavePanel> createState() => _V2SavePanelState();
}

class _V2SavePanelState extends ConsumerState<V2SavePanel> {
  V2PageStatus? _status;
  String? _message;
  bool _busy = false;

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
    if (mounted) setState(() => _status = status);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final message = await v2SavePage(
      ref,
      url: widget.url,
      pageTitle: widget.pageTitle,
      captureMode: _mode,
      captureModeIsUserSet: _modeIsUserSet,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    await _refresh();
  }

  Future<void> _start() async {
    final starter = ref.read(saveQueueStarterProvider);
    if (starter != null) await starter();
    await _refresh();
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
    final task = status?.task;
    final result = status?.result;

    final lines = <Widget>[];
    if (status == null) {
      lines.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else {
      final describe = switch (result) {
        RecognisedLocation(:final collection) =>
          collection == null
              ? 'In your library.'
              : 'In your library — ${collection.name}.',
        RecognisedSource(:final collection) =>
          'On a site you know — ${collection.name}.',
        _ => 'Not in your library yet.',
      };
      lines.add(Text(describe, style: TextStyle(color: palette.inkMuted)));
      if (status.hasCopy) {
        lines.add(
          Text('On this device.', style: TextStyle(color: palette.inkMuted)),
        );
      }
      if (task != null && !task.state.isTerminal) {
        lines.add(
          Text(
            task.state == SaveTaskState.queued
                ? 'Queued — waiting for Start.'
                : 'Saving…',
            style: TextStyle(color: palette.inkMuted),
          ),
        );
      }
      if (_message != null) {
        lines.add(Text(_message!, style: TextStyle(color: palette.inkMuted)));
      }
    }

    // A page that can hold nothing offers no save — the sheet says so in the
    // detection line instead of putting up a button that would refuse.
    final canSave =
        status != null &&
        (task == null || task.state.isTerminal) &&
        !_busy &&
        _capabilities.canSaveAnything;
    final canStart =
        task != null && task.state == SaveTaskState.queued && !_busy;
    final source = result is RecognisedSource ? result : null;

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
            const SizedBox(height: 8),
            ...[
              for (final line in lines)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: line),
            ],
            const SizedBox(height: 12),
            CaptureModeSection(
              capabilities: _capabilities,
              selected: _mode,
              onSelect: (mode) => setState(() {
                _mode = mode;
                _modeIsUserSet = true;
              }),
            ),
            const SizedBox(height: 8),
            if (source != null && !source.followed)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await v2FollowCollection(ref, source.collection.id);
                        await _refresh();
                      },
                child: Text('Follow ${source.collection.name}'),
              ),
            if (canSave)
              FilledButton(
                key: const ValueKey('v2SaveButton'),
                onPressed: _save,
                child: const Text('Save for offline'),
              ),
            if (canStart)
              FilledButton.tonal(
                key: const ValueKey('v2StartButton'),
                onPressed: _start,
                child: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }
}
