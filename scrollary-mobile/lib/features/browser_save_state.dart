import '../save/save_run.dart';
import '../save/save_preflight.dart';
import '../save/save_state.dart';

/// What the Browser's save control is, for the page that is on screen.
///
/// The rule this file exists to enforce (D59): **the Browser's save state is
/// page state, not run state.** It is derived from the page identity currently
/// showing, the work that genuinely matches it, and what that page already has
/// locally. A run that finished — however recently, whatever it did — is a
/// *result*, and a result belongs to the page it happened on. It is never the
/// standing state of the next page the user opens.
enum BrowserSaveStatus {
  /// Nothing here yet.
  save,

  /// This page is on a commercial content service the app does not save from
  /// (`save/capture_policy.dart`). The save control is **absent** — not
  /// disabled, not explained, not a warning. Browsing is untouched.
  restricted,

  /// This page is already saved locally.
  availableOffline,

  /// A pending queue task covers this page. It has not started.
  queued,

  /// The active run is working on this page and needs the rendered surface.
  saving,

  /// The active run is on this page but only moving bytes now.
  downloading,

  /// The active run is holding until the Browser is visible again.
  waitingForBrowser,

  /// The active run is asking the user something.
  needsInput,

  /// Something else owns the Browser, and it is not this page's work.
  busyElsewhere,
}

/// The resolved control state, plus what the save sheet may offer.
class BrowserSaveState {
  const BrowserSaveState({
    required this.status,
    required this.label,
    this.detail,
    this.busyLabel,
    this.canStartDirect = false,
    this.canQueue = false,
    this.result,
  });

  final BrowserSaveStatus status;

  /// The control's own words ("Save", "Saving…").
  final String label;

  /// One short line under it, when there is something worth saying.
  final String? detail;

  /// Why **Start Save** is not on offer, when it is not.
  final String? busyLabel;

  /// Whether a direct start may be offered for this page right now.
  final bool canStartDirect;

  /// Whether queueing may be offered. Queueing is almost always available:
  /// it starts nothing, so nothing can conflict with it.
  final bool canQueue;

  /// The finished run this page is entitled to show, or null. Already
  /// page-scoped — the resolver only passes one through when it belongs here.
  final SaveRunRecord? result;

  /// True while the run panel (phase, counters, controls) is the right thing
  /// to show under the page.
  bool get showsRunPanel => switch (status) {
    BrowserSaveStatus.saving ||
    BrowserSaveStatus.downloading ||
    BrowserSaveStatus.waitingForBrowser ||
    BrowserSaveStatus.needsInput => true,
    _ => false,
  };

  /// True when tapping the control should start the save flow rather than
  /// take the user to the work that is already happening.
  bool get opensSaveSheet => switch (status) {
    BrowserSaveStatus.save ||
    BrowserSaveStatus.availableOffline ||
    BrowserSaveStatus.busyElsewhere => true,
    _ => false,
  };

  /// Whether the Browser should draw a save control for this page at all.
  ///
  /// False means **nothing is rendered** — no button, no disabled button and no
  /// reserved space. Everything else in the Browser stays exactly where it was.
  bool get offersCapture => status != BrowserSaveStatus.restricted;
}

/// Resolve the save control for the page on screen.
///
/// Every input is about *now*: which page is showing, what is genuinely
/// active, what this page already has. Nothing here reads a previous run's
/// progress — that is the bug this replaces.
BrowserSaveState resolveBrowserSaveState({
  /// Canonical identity of the page on screen (empty when there is no page).
  required String pageKey,

  /// The Browser's page-session counter for that page.
  required int pageSession,

  /// True while a save run exists that owns or is holding the WebView.
  required bool hasActiveRun,

  /// Canonical identity of the page the active run is working on.
  required String activePageKey,

  /// The active run's phase.
  required SaveState activeState,

  /// True while the active run needs the rendered surface.
  required bool needsRenderedBrowser,

  /// True while the active run is holding on the user (selection, duplicate).
  required bool awaitingUser,

  /// True while the run is paused because the Browser was hidden.
  required bool pausedForBrowser,

  /// True while an update check owns the WebView.
  required bool checkerRunning,

  /// Whether the user is what put this page on screen. False when automation
  /// navigated here — in which case the run that navigated here owns the page,
  /// whatever the two keys say about each other mid-hop.
  bool pageEnteredManually = true,

  /// The last finished run, whatever page it belonged to.
  required SaveRunRecord? lastRun,

  /// What this page already has locally, when it has been looked up.
  required EntryLocalState? pageEntryState,

  /// True when a queued (not started) save task covers this page.
  required bool pageIsQueued,

  /// True when the restricted-site capture policy covers the page on screen.
  required bool captureRestricted,
}) {
  // First, and before every other question. A stale result, a queued row from
  // before this host joined the list, or a run working elsewhere must not be
  // able to put a save control back on a restricted page — so none of those
  // branches is even reached. It is also why this is recomputed per page: the
  // answer is a property of the address on screen and of nothing else, so it
  // follows every navigation, redirect, reload and history move for free.
  if (captureRestricted) {
    return const BrowserSaveState(
      status: BrowserSaveStatus.restricted,
      label: 'Save',
      canStartDirect: false,
      canQueue: false,
    );
  }

  if (hasActiveRun) {
    // Three ways this page can be the run's page, and all three are needed:
    // the keys agree; the run is *between* pages, where they are supposed to
    // disagree; or automation put this page here, which only the run does.
    final isThisPage =
        (activePageKey.isNotEmpty && activePageKey == pageKey) ||
        activeState == SaveState.navigating ||
        !pageEnteredManually;
    if (isThisPage) {
      if (awaitingUser) {
        return const BrowserSaveState(
          status: BrowserSaveStatus.needsInput,
          label: 'Needs you',
          detail: 'This save is waiting for your answer',
        );
      }
      if (pausedForBrowser || activeState == SaveState.waitingForBrowser) {
        return const BrowserSaveState(
          status: BrowserSaveStatus.waitingForBrowser,
          label: 'Waiting for Browser',
          detail: 'Stay on this page to continue',
        );
      }
      if (needsRenderedBrowser) {
        return const BrowserSaveState(
          status: BrowserSaveStatus.saving,
          label: 'Saving…',
        );
      }
      return const BrowserSaveState(
        status: BrowserSaveStatus.downloading,
        label: 'Downloading…',
        detail: 'Images are still being saved',
      );
    }
    // Active, but somewhere else. Queueing still works — it starts nothing.
    return const BrowserSaveState(
      status: BrowserSaveStatus.busyElsewhere,
      label: 'Save',
      busyLabel: 'Another save is running',
      canQueue: true,
    );
  }

  if (checkerRunning) {
    return const BrowserSaveState(
      status: BrowserSaveStatus.busyElsewhere,
      label: 'Save',
      busyLabel: 'An update check is using the Browser',
      canQueue: true,
    );
  }

  // Nothing is running. Only a result that belongs to *this* page session may
  // be shown — a completed run from the page before it is history, not state.
  final result =
      lastRun != null &&
          lastRun.pageSession == pageSession &&
          lastRun.urlKey == pageKey &&
          pageKey.isNotEmpty
      ? lastRun
      : null;

  final hasPage = pageKey.isNotEmpty;
  if (pageIsQueued) {
    return BrowserSaveState(
      status: BrowserSaveStatus.queued,
      label: 'Queued',
      detail: 'Waiting to start',
      canQueue: false,
      canStartDirect: hasPage,
      result: result,
    );
  }

  final saved =
      pageEntryState == EntryLocalState.complete ||
      pageEntryState == EntryLocalState.partial;
  if (saved) {
    return BrowserSaveState(
      status: BrowserSaveStatus.availableOffline,
      label: 'Save again',
      detail: pageEntryState == EntryLocalState.partial
          ? 'Saved, but incomplete'
          : 'Already available offline',
      canStartDirect: hasPage,
      canQueue: hasPage,
      result: result,
    );
  }

  return BrowserSaveState(
    status: BrowserSaveStatus.save,
    label: 'Save',
    canStartDirect: hasPage,
    canQueue: hasPage,
    result: result,
  );
}
