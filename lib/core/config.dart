/// Tuning constants for autonomous save.
///
/// Every value here is a starting point measured on the iOS Simulator against
/// the local fixture. The Simulator's network and disk are the host Mac's, so
/// these are optimistic — re-measure on a device before trusting them.
class SaveConfig {
  const SaveConfig({
    this.scrollStepFraction = 0.8,
    this.scrollDelay = const Duration(milliseconds: 300),
    this.fastScrollStepViewports = 3.5,
    this.fastScrollDelay = const Duration(milliseconds: 70),
    this.fastModeAfterStableProbes = 2,
    this.lookaheadViewports = 2.0,
    this.quietPeriod = const Duration(milliseconds: 900),
    this.requiredStableChecks = 3,
    this.maxScrollIterations = 300,
    this.maxScrollPasses = 2,
    this.maxSaveDuration = const Duration(seconds: 150),
    this.maxAssetWait = const Duration(seconds: 30),
    this.domReadyTimeout = const Duration(seconds: 20),
    this.downloadRetries = 2,
    this.downloadConcurrency = 3,
    this.minImageEdge = 300,
    this.maxAspectRatio = 4.0,
    this.minCandidates = 3,
    this.minClusterSize = 3,
    this.widthClusterTolerance = 0.12,
    this.maxEnumeratedImages = 6000,
    this.minAssetBytes = 512,
    this.cooldownBetweenEntries = const Duration(milliseconds: 1200),
    this.maxEntriesPerRun = 500,
    this.maxRunDuration = const Duration(minutes: 45),
    this.maxSkippedPerRun = 50,
    this.minFreeSpaceToStart = 500 * 1024 * 1024,
    this.emergencyReserve = 200 * 1024 * 1024,
    this.unknownEntryEstimate = 50 * 1024 * 1024,
  });

  /// Fraction of the viewport height to advance per scroll step. Below 1.0 so
  /// consecutive steps overlap and no lazy-load trigger is jumped over.
  /// This is the CAREFUL pace, used near unloaded content.
  final double scrollStepFraction;
  final Duration scrollDelay;

  // --- adaptive traversal ---------------------------------------------------
  // The audit measured scrolling at 90–98% of real save time while the
  // page content was often already loaded. When everything within
  // [lookaheadViewports] below the position is resolved and the document
  // height is not moving, the engine jumps [fastScrollStepViewports] per step
  // with [fastScrollDelay] between steps; any pending image nearby, height
  // growth, or non-moving scroll drops it straight back to the careful pace.

  /// Step size in fast mode, in viewport heights.
  final double fastScrollStepViewports;

  /// Delay between fast-mode steps.
  final Duration fastScrollDelay;

  /// Consecutive fully-resolved probes required before fast mode engages.
  final int fastModeAfterStableProbes;

  /// How far below the current position must be resolved for fast mode.
  final double lookaheadViewports;

  /// How long the page must stay unchanged before it counts as settled.
  final Duration quietPeriod;

  /// Consecutive unchanged probes required at the bottom of the page.
  final int requiredStableChecks;
  final int maxScrollIterations;

  /// A second downward pass catches lazy loaders that only fire when an
  /// element is scrolled *into* view from above.
  final int maxScrollPasses;
  final Duration maxSaveDuration;
  final Duration maxAssetWait;
  final Duration domReadyTimeout;

  final int downloadRetries;
  final int downloadConcurrency;

  /// Images smaller than this on either edge are chrome, not content.
  final int minImageEdge;

  /// Wider-than-tall beyond this ratio is a banner, not a content page.
  final double maxAspectRatio;

  /// Below this many candidates the page did not yield an entry.
  final int minCandidates;

  /// A width cluster must hold at least this many images to be trusted as
  /// "the content column".
  final int minClusterSize;

  /// Relative width tolerance when grouping images into the content column.
  final double widthClusterTolerance;

  /// Ceiling on how many images one entry's **final** enumeration may collect.
  ///
  /// The bridge returns images a slice at a time, because a probe's cost is
  /// linear in the number of records it serialises — measured at ~24µs each on
  /// an iPhone 17 simulator, so 800 images cost ~24ms and the scroll loop takes
  /// one such probe per step. That per-call cap is a traversal concern and
  /// stays. Completeness is a *save* concern, so the settled probe walks the
  /// remaining slices instead of stopping at the first one.
  ///
  /// This bounds that walk. It is not a target: a page holding more `<img>`
  /// elements than this is not a readable entry, and the save says so rather
  /// than quietly keeping the first [maxEnumeratedImages] of them.
  final int maxEnumeratedImages;

  final int minAssetBytes;
  final Duration cooldownBetweenEntries;

  /// Upper bound on a user-entered entry count. **Input validation, not a
  /// preset**: the save sheet refuses anything above it, and nothing ever
  /// selects it on the user's behalf.
  ///
  /// This is now the only ceiling. The app used to also offer "until there is
  /// no next page", bounded by a separate internal limit — an open-ended scope
  /// whose real bound the user never saw. A typed number is the same guarantee
  /// stated plainly: the run stops where the person said it would.
  final int maxEntriesPerRun;

  /// Hard duration bound for a run, whatever it was asked for.
  final Duration maxRunDuration;

  /// The requested entry count means *new save attempts*; entries
  /// skipped as already saved do not consume it. This caps how many skips a
  /// run may walk through so a fully-saved collection cannot turn a small
  /// request into an unbounded crawl.
  final int maxSkippedPerRun;

  // --- disk-space policy ------------------------------------------------
  // Centralised here on purpose: widgets and the run read the same numbers.

  /// A save refuses to start below this much free space (bytes).
  final int minFreeSpaceToStart;

  /// Never write into the last [emergencyReserve] bytes — an entry that
  /// would cross it stops with a distinct disk-full error instead.
  final int emergencyReserve;

  /// Planning estimate for an entry whose size is unknown (bytes), used by the
  /// run's **rolling disk check** and nowhere else.
  ///
  /// Deliberately generous, and deliberately not the number the user is shown.
  /// Here the two errors are asymmetric: over-estimating stops a run one entry
  /// early, under-estimating writes the device full mid-entry. On screen they
  /// are not — multiplying this constant by an entry count is what reported
  /// "up to ~1.0 GB" for twenty ordinary entries. What the user sees comes from
  /// `save/size_estimate.dart`, which measures the collection instead.
  final int unknownEntryEstimate;
}

/// How much the user asked to save. Persisted, so a resume continues in the
/// same mode.
///
/// **The default is [currentPageOnly].** That is the product's central safety
/// property, not a UI preference: the ordinary action saves the one page in front
/// of the user, and every scope beyond it is chosen deliberately, shown before it
/// starts, and bounded.
enum SaveScope {
  /// The page on screen. Nothing is followed.
  currentPageOnly,

  /// Items the user picked from a review list.
  selectedEntries,

  /// A number of entries the user typed. The only multi-entry scope: there is
  /// deliberately no open-ended one, so every run stops at a number a person
  /// chose and can see.
  fixedCount;

  static SaveScope fromName(String? name) => SaveScope.values.firstWhere(
    (m) => m.name == name,
    // An unrecognised value reads as the *safest* scope, not the last one used.
    orElse: () => SaveScope.currentPageOnly,
  );

  bool get isMultiEntry => this != SaveScope.currentPageOnly;
}

SaveScope saveScopeFromName(String? name) => SaveScope.fromName(name);

/// The ceilings a multi-entry run runs under.
///
/// Constructed only through [SaveLimits.forScope], which cannot produce an
/// unbounded run: `maxEntries` is always a positive number, clamped to the
/// configured safety ceiling.
///
/// **Bounds only.** What a save *produces* is `CaptureMode`, which travels
/// beside these limits rather than inside them: "how many entries and how many
/// bytes" and "images or text" are independent questions, and the old
/// `includeImages` boolean living here was what made the second one look like
/// a limit and then never get read by anything.
class SaveLimits {
  const SaveLimits._({required this.maxEntries, this.maxBytes});

  /// The bounded limits for [scope].
  ///
  /// [requestedCount] is what the user typed; it is clamped rather than
  /// trusted. There is no scope without a count, so there is no path to an
  /// unbounded run.
  factory SaveLimits.forScope(
    SaveScope scope, {
    int? requestedCount,
    int? maxBytes,
    SaveConfig config = kDefaultSaveConfig,
  }) {
    final entries = switch (scope) {
      SaveScope.currentPageOnly => 1,
      SaveScope.selectedEntries => (requestedCount ?? 1).clamp(
        1,
        config.maxEntriesPerRun,
      ),
      SaveScope.fixedCount => (requestedCount ?? 1).clamp(
        1,
        config.maxEntriesPerRun,
      ),
    };
    return SaveLimits._(maxEntries: entries, maxBytes: maxBytes);
  }

  /// Always a positive number. There is no representation of "no limit".
  final int maxEntries;

  /// The user's storage ceiling in bytes, when they set one.
  final int? maxBytes;

  bool get isSinglePage => maxEntries == 1;

  @override
  String toString() =>
      '$maxEntries entries'
      '${maxBytes == null ? '' : ', ${(maxBytes! / (1024 * 1024)).round()} MB'}';
}

const kDefaultSaveConfig = SaveConfig();

/// What the Browser's WebView holds before the user goes anywhere.
///
/// Blank on purpose. The alternatives are both worse: a search engine makes
/// the app's first act a network request to a third party, and silently
/// re-loading the last page the user was on would look like a fresh manual
/// visit — a history row nobody created (§17, D57). Instead, a cold start
/// shows Browser Home, where the last page is one tap away under Recently
/// visited.
const String kBrowserStartUrl = 'about:blank';
