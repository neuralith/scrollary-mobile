/// Where a save is, right now. Exposed in the UI so a long autonomous run
/// is observable rather than a spinner.
enum SaveState {
  idle,
  inspecting,
  scrolling,
  waitingForAssets,
  verifying,
  extracting,
  fetchingAssets,
  saving,
  detectingNext,
  navigating,
  paused,

  /// Automatic detection was not confident. The run is holding while the user
  /// points at the real control — a prompt is better than a wrong guess that
  /// walks the run into another collection.
  awaitingSelection,

  /// The WebView surface is not rendered (hidden tab: zero viewport, frozen
  /// scroll). The run is holding until the Browser is visible again — an
  /// unrendered page measures garbage, and saving garbage is worse than
  /// waiting.
  waitingForBrowser,
  complete,
  partial,
  failed,
  cancelled;

  bool get isTerminal =>
      this == complete ||
      this == partial ||
      this == failed ||
      this == cancelled;

  bool get isRunning =>
      !isTerminal &&
      this != idle &&
      this != paused &&
      this != awaitingSelection &&
      this != waitingForBrowser;

  String get label => switch (this) {
    SaveState.idle => 'Idle',
    SaveState.inspecting => 'Inspecting page',
    SaveState.scrolling => 'Scrolling',
    SaveState.waitingForAssets => 'Waiting for page content',
    SaveState.verifying => 'Verifying',
    SaveState.extracting => 'Extracting',
    SaveState.fetchingAssets => 'Fetching page content',
    SaveState.saving => 'Saving offline copy',
    SaveState.detectingNext => 'Looking for a next page',
    SaveState.navigating => 'Opening the next page',
    SaveState.paused => 'Paused',
    SaveState.awaitingSelection => 'Waiting for your selection',
    SaveState.waitingForBrowser => 'Open the Browser to continue',
    SaveState.complete => 'Complete',
    SaveState.partial => 'Partial',
    SaveState.failed => 'Failed',
    SaveState.cancelled => 'Cancelled',
  };
}

/// Legal transitions. Enforced by the engine so an impossible state pair is a
/// test failure, not a UI oddity.
const Map<SaveState, Set<SaveState>> kAllowedTransitions = {
  SaveState.idle: {SaveState.inspecting, SaveState.cancelled},
  SaveState.inspecting: {
    SaveState.waitingForBrowser,
    SaveState.scrolling,
    SaveState.verifying,
    // A run whose every entry was already saved ends without saving.
    SaveState.complete,
    SaveState.partial,
    SaveState.navigating,
    SaveState.paused,
    // The very first entry of a run can already be saved — the duplicate
    // prompt holds the run before anything else happens.
    SaveState.awaitingSelection,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.scrolling: {
    SaveState.waitingForBrowser,
    SaveState.scrolling,
    SaveState.waitingForAssets,
    SaveState.verifying,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.waitingForAssets: {
    SaveState.waitingForBrowser,
    SaveState.scrolling,
    SaveState.verifying,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.verifying: {
    SaveState.waitingForBrowser,
    SaveState.extracting,
    SaveState.awaitingSelection,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.extracting: {
    SaveState.fetchingAssets,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.fetchingAssets: {
    // The next link is read while we are still on the page, before the
    // entry is committed — leaving the page first would lose it.
    SaveState.detectingNext,
    SaveState.saving,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.detectingNext: {
    SaveState.saving,
    SaveState.awaitingSelection,
    SaveState.navigating,
    SaveState.complete,
    SaveState.partial,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.saving: {
    SaveState.complete,
    SaveState.partial,
    SaveState.detectingNext,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.navigating: {
    SaveState.waitingForBrowser,
    SaveState.inspecting,
    SaveState.paused,
    // A skip walked onto an entry that needs a duplicate decision.
    SaveState.awaitingSelection,
    // A run can end while walking: skipped entries ran out of chain, or a
    // bound was reached between saves.
    SaveState.complete,
    SaveState.partial,
    SaveState.failed,
    SaveState.cancelled,
  },
  // The WebView went unrendered mid-phase; resumes into whatever it
  // interrupted once the Browser surface is visible again.
  SaveState.waitingForBrowser: {
    SaveState.inspecting,
    SaveState.scrolling,
    SaveState.waitingForAssets,
    SaveState.verifying,
    SaveState.extracting,
    SaveState.navigating,
    SaveState.detectingNext,
    SaveState.paused,
    SaveState.failed,
    SaveState.cancelled,
  },
  // Resumes into whatever it interrupted, or ends if the user gives up.
  SaveState.awaitingSelection: {
    SaveState.inspecting,
    SaveState.detectingNext,
    SaveState.verifying,
    SaveState.extracting,
    SaveState.navigating,
    SaveState.saving,
    SaveState.complete,
    SaveState.partial,
    SaveState.failed,
    SaveState.cancelled,
  },
  SaveState.paused: {
    SaveState.inspecting,
    SaveState.scrolling,
    SaveState.waitingForAssets,
    SaveState.verifying,
    SaveState.extracting,
    SaveState.fetchingAssets,
    SaveState.saving,
    SaveState.detectingNext,
    SaveState.navigating,
    SaveState.cancelled,
  },
  // An entry ending is not the run ending: the loop moves on to the next one.
  SaveState.complete: {
    SaveState.idle,
    SaveState.inspecting,
    SaveState.navigating,
    SaveState.detectingNext,
    // The entry is saved; the *next* link is what is ambiguous.
    SaveState.awaitingSelection,
  },
  SaveState.partial: {
    SaveState.idle,
    SaveState.inspecting,
    SaveState.navigating,
    SaveState.detectingNext,
    SaveState.awaitingSelection,
    SaveState.complete,
  },
  SaveState.failed: {
    SaveState.idle,
    SaveState.inspecting,
    SaveState.navigating,
    // Extraction failed -> ask the user to point at the reader area.
    SaveState.awaitingSelection,
  },
  SaveState.cancelled: {SaveState.idle, SaveState.inspecting},
};

bool isTransitionAllowed(SaveState from, SaveState to) =>
    from == to || (kAllowedTransitions[from]?.contains(to) ?? false);

/// Live snapshot for the save UI.
class SaveProgress {
  const SaveProgress({
    this.state = SaveState.idle,
    this.currentUrl = '',
    this.entryTitle = '',
    this.entryIndex = 0,
    this.requestedEntries = 1,
    this.storedEntries = 0,
    this.skippedEntries = 0,
    this.detectedImages = 0,
    this.storedImages = 0,
    this.failedImages = 0,
    this.scrollPercent = 0,
    this.retryCount = 0,
    this.lastError,
    this.message = '',
  });

  final SaveState state;
  final String currentUrl;
  final String entryTitle;

  /// 1-based position of the entry being saved within this run.
  final int entryIndex;
  final int requestedEntries;
  final int storedEntries;

  /// Entries left alone because they already existed. Surfaced so "nothing
  /// downloaded" is distinguishable from "nothing happened".
  final int skippedEntries;
  final int detectedImages;
  final int storedImages;
  final int failedImages;
  final double scrollPercent;
  final int retryCount;
  final String? lastError;
  final String message;

  SaveProgress copyWith({
    SaveState? state,
    String? currentUrl,
    String? entryTitle,
    int? entryIndex,
    int? requestedEntries,
    int? storedEntries,
    int? skippedEntries,
    int? detectedImages,
    int? storedImages,
    int? failedImages,
    double? scrollPercent,
    int? retryCount,
    String? lastError,
    bool clearError = false,
    String? message,
  }) => SaveProgress(
    state: state ?? this.state,
    currentUrl: currentUrl ?? this.currentUrl,
    entryTitle: entryTitle ?? this.entryTitle,
    entryIndex: entryIndex ?? this.entryIndex,
    requestedEntries: requestedEntries ?? this.requestedEntries,
    storedEntries: storedEntries ?? this.storedEntries,
    skippedEntries: skippedEntries ?? this.skippedEntries,
    detectedImages: detectedImages ?? this.detectedImages,
    storedImages: storedImages ?? this.storedImages,
    failedImages: failedImages ?? this.failedImages,
    scrollPercent: scrollPercent ?? this.scrollPercent,
    retryCount: retryCount ?? this.retryCount,
    lastError: clearError ? null : (lastError ?? this.lastError),
    message: message ?? this.message,
  );
}
