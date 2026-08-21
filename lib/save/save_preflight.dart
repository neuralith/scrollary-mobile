import '../core/url_utils.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';

/// What already exists locally for an entry, decided *before* any bytes move.
enum EntryLocalState {
  /// Never saved. The ordinary case; save straight away.
  none,

  /// Saved, verified, files present.
  complete,

  /// Saved but knowingly incomplete.
  partial,

  /// A previous attempt failed. No usable local copy.
  failed,

  /// The database says saved, but the files are gone. Must not be reported
  /// as available offline.
  filesMissing,

  /// Another run — running or interrupted — already owns this entry.
  inActiveRun,
}

/// What to do when a bounded run meets an entry that already exists.
///
/// Persisted on the run so the answer is given once, not per entry.
enum DuplicatePolicy {
  /// Leave complete entries alone and move on. The default: re-downloading
  /// something already readable costs bandwidth and gains nothing.
  skipComplete,

  /// Skip complete ones, but re-attempt partial and failed ones.
  retryPartial,

  /// Re-save everything in range, replacing what is there.
  replaceAll,

  /// Stop and ask at each one.
  ask,
}

DuplicatePolicy duplicatePolicyFromName(String? name) =>
    DuplicatePolicy.values.firstWhere(
      (p) => p.name == name,
      orElse: () => DuplicatePolicy.skipComplete,
    );

/// Session-scoped answer to "this entry is already saved in full".
///
/// Lives on the running run — it survives an interrupted-session resume and
/// dies with the session. Never a global preference: the right answer to
/// "re-download?" is different for a broken entry today than for a routine
/// range save next week.
enum SessionDuplicateDecision {
  ask,
  skipCompleteForSession,
  replaceCompleteForSession,
}

SessionDuplicateDecision sessionDuplicateDecisionFromName(String? name) =>
    SessionDuplicateDecision.values.firstWhere(
      (d) => d.name == name,
      orElse: () => SessionDuplicateDecision.ask,
    );

/// Session-scoped answer for partial / failed / files-missing entries met
/// mid-run. Kept separate from the complete-duplicate answer: "skip what I
/// already have" and "fix what is broken" are independent choices.
enum SessionPartialDecision { ask, retryForSession, skipForSession }

SessionPartialDecision sessionPartialDecisionFromName(String? name) =>
    SessionPartialDecision.values.firstWhere(
      (d) => d.name == name,
      orElse: () => SessionPartialDecision.ask,
    );

/// What the save loop should do with the entry in front of it.
enum DuplicateAction {
  /// Save it (replacing local files when some exist).
  save,

  /// Leave it alone and walk on to the next entry.
  skip,

  /// Hold the run and ask the user.
  promptUser,
}

/// The one place the "already saved mid-run" decision is made.
///
/// Explicit policies (chosen in the preflight sheet before the run) answer
/// without prompting. Under [DuplicatePolicy.ask] the session decisions
/// answer, and where they are still [SessionDuplicateDecision.ask] /
/// [SessionPartialDecision.ask] the user is prompted — silently skipping or
/// silently re-downloading is exactly what this exists to prevent.
DuplicateAction resolveDuplicateAction({
  required EntryLocalState state,
  required DuplicatePolicy policy,
  SessionDuplicateDecision sessionComplete = SessionDuplicateDecision.ask,
  SessionPartialDecision sessionPartial = SessionPartialDecision.ask,
}) {
  switch (state) {
    case EntryLocalState.none:
      return DuplicateAction.save;
    case EntryLocalState.inActiveRun:
      // Owned by another run. Prompting could not offer anything safe.
      return DuplicateAction.skip;
    case EntryLocalState.complete:
      return switch (policy) {
        DuplicatePolicy.skipComplete ||
        DuplicatePolicy.retryPartial => DuplicateAction.skip,
        DuplicatePolicy.replaceAll => DuplicateAction.save,
        DuplicatePolicy.ask => switch (sessionComplete) {
          SessionDuplicateDecision.skipCompleteForSession =>
            DuplicateAction.skip,
          SessionDuplicateDecision.replaceCompleteForSession =>
            DuplicateAction.save,
          SessionDuplicateDecision.ask => DuplicateAction.promptUser,
        },
      };
    case EntryLocalState.partial:
      return switch (policy) {
        DuplicatePolicy.skipComplete => DuplicateAction.skip,
        DuplicatePolicy.retryPartial ||
        DuplicatePolicy.replaceAll => DuplicateAction.save,
        DuplicatePolicy.ask => switch (sessionPartial) {
          SessionPartialDecision.retryForSession => DuplicateAction.save,
          SessionPartialDecision.skipForSession => DuplicateAction.skip,
          SessionPartialDecision.ask => DuplicateAction.promptUser,
        },
      };
    case EntryLocalState.failed || EntryLocalState.filesMissing:
      // Nothing locally readable. Explicit policies always re-attempt these;
      // under ask the partial-session answer applies.
      return switch (policy) {
        DuplicatePolicy.ask => switch (sessionPartial) {
          SessionPartialDecision.retryForSession => DuplicateAction.save,
          SessionPartialDecision.skipForSession => DuplicateAction.skip,
          SessionPartialDecision.ask => DuplicateAction.promptUser,
        },
        _ => DuplicateAction.save,
      };
  }
}

/// What the user can do with a duplicate met mid-run.
enum DuplicateChoiceAction {
  /// Keep the local copy, continue with the next entry.
  skip,

  /// Replace a complete local copy (atomic replacement, reading state kept).
  redownload,

  /// Re-attempt a partial save, keeping the row.
  retryMissing,

  /// Re-save a failed / files-missing entry from scratch.
  restartEntry,

  /// End the run cleanly. Never becomes a session policy.
  stopSave,
}

/// The user's answer to a mid-run duplicate prompt.
class DuplicateChoice {
  const DuplicateChoice(this.action, {this.applyToSession = false});

  final DuplicateChoiceAction action;

  /// "Use this choice for all already saved entries in this save
  /// session." Ignored for [DuplicateChoiceAction.stopSave].
  final bool applyToSession;
}

/// A mid-run duplicate the run is holding on, waiting for the user.
class DuplicateRequest {
  const DuplicateRequest({required this.preflight, required this.ordinal});

  final EntryPreflight preflight;

  /// 1-based position in the walk, for "entry N of this run" phrasing.
  final int ordinal;

  EntryLocalState get state => preflight.state;
  Entry? get entry => preflight.entry;

  /// Actions that make sense for this state — the sheet must not offer
  /// "retry missing files" on an entry that is complete.
  List<DuplicateChoiceAction> get availableActions => switch (preflight.state) {
    EntryLocalState.complete => const [
      DuplicateChoiceAction.skip,
      DuplicateChoiceAction.redownload,
      DuplicateChoiceAction.stopSave,
    ],
    EntryLocalState.partial => const [
      DuplicateChoiceAction.retryMissing,
      DuplicateChoiceAction.restartEntry,
      DuplicateChoiceAction.skip,
      DuplicateChoiceAction.stopSave,
    ],
    _ => const [
      DuplicateChoiceAction.restartEntry,
      DuplicateChoiceAction.skip,
      DuplicateChoiceAction.stopSave,
    ],
  };

  String get title => switch (preflight.state) {
    EntryLocalState.complete => 'This entry is already available offline.',
    EntryLocalState.partial =>
      'This entry is saved, but incomplete — some images are missing.',
    EntryLocalState.filesMissing =>
      'This entry is listed, but its local files are gone.',
    _ => 'A previous save of this entry failed.',
  };
}

class EntryPreflight {
  const EntryPreflight({
    required this.state,
    required this.url,
    this.entry,
    this.blockingRun,
  });

  final EntryLocalState state;
  final String url;
  final Entry? entry;

  /// The run that already owns this entry, when [state] is `inActiveRun`.
  final SaveRun? blockingRun;

  bool get existsLocally =>
      state == EntryLocalState.complete || state == EntryLocalState.partial;

  bool get needsUserDecision => state != EntryLocalState.none;

  /// Whether this entry should be saved under [policy], with no user
  /// present to ask.
  bool shouldSaveUnder(DuplicatePolicy policy) => switch (state) {
    EntryLocalState.none => true,
    EntryLocalState.failed || EntryLocalState.filesMissing => true,
    EntryLocalState.partial => policy != DuplicatePolicy.skipComplete,
    EntryLocalState.complete => policy == DuplicatePolicy.replaceAll,
    EntryLocalState.inActiveRun => false,
  };
}

/// Summary of a bounded range, so the user can decide once for the whole run.
class RangePreflight {
  const RangePreflight({required this.entries, required this.requestedCount});

  final List<EntryPreflight> entries;
  final int requestedCount;

  int get savedCount =>
      entries.where((e) => e.state == EntryLocalState.complete).length;
  int get partialCount =>
      entries.where((e) => e.state == EntryLocalState.partial).length;
  int get brokenCount => entries
      .where(
        (e) =>
            e.state == EntryLocalState.failed ||
            e.state == EntryLocalState.filesMissing,
      )
      .length;

  /// How much of the range we could actually see ahead of time. The rest is
  /// only discoverable by visiting each page, so the run applies the chosen
  /// policy entry by entry.
  int get knownCount => entries.length;
  int get newCount => (requestedCount - savedCount - partialCount - brokenCount)
      .clamp(0, requestedCount);

  bool get hasExisting => savedCount + partialCount + brokenCount > 0;

  /// Human summary, only listing what is actually true.
  List<String> get lines => [
    if (savedCount > 0)
      '$savedCount entry${savedCount == 1 ? ' is' : 's are'} already saved.',
    if (partialCount > 0)
      '$partialCount saved entry${partialCount == 1 ? ' is' : 's are'} '
          'partial.',
    if (brokenCount > 0)
      '$brokenCount saved entry${brokenCount == 1 ? ' has' : 's have'} '
          'missing or failed files.',
    if (newCount > 0) '$newCount entry${newCount == 1 ? ' is' : 's are'} new.',
  ];
}

/// Decides what already exists before a save starts.
///
/// Nothing here downloads: the point is that the decision is made — and the
/// user asked — before a single byte moves.
class SavePreflight {
  SavePreflight({required this.db, required this.fileStore});

  final AppDatabase db;
  final FileStore fileStore;

  Future<EntryPreflight> inspect(
    String url, {
    String? collectionId,
    String? ignoreRunId,
  }) async {
    final key = normalizeUrl(url);

    // A run that already owns this entry wins over anything else: starting a
    // second save of the same page would race the first for the same files.
    //
    // `ignoreRunId` is the running run's own id. Without it a run collides with
    // itself the moment it persists its first state — its own row is
    // non-terminal and its own start URL matches — and skips every entry it
    // was asked to save.
    final run = await db.findResumableRun();
    if (run != null && run.id != ignoreRunId) {
      final visited = run.visitedUrls.split('\n').where((s) => s.isNotEmpty);
      final owns =
          visited.contains(key) ||
          normalizeUrl(run.currentUrl ?? '') == key ||
          normalizeUrl(run.startUrl) == key;
      if (owns) {
        return EntryPreflight(
          state: EntryLocalState.inActiveRun,
          url: url,
          blockingRun: run,
        );
      }
    }

    final entry = collectionId == null
        ? await db.findEntryByUrlKeyAnywhere(key)
        : await db.findEntryByUrlKey(collectionId, key);

    if (entry == null) {
      return EntryPreflight(state: EntryLocalState.none, url: url);
    }

    final path = entry.contentPath;
    final onDisk = path != null && fileStore.entryExists(path);

    // The database claiming a save is not the same as the files being
    // there. Reporting an entry as offline when it is not is the failure this
    // check exists to prevent.
    if (!onDisk &&
        (entry.saveStatus == 'complete' || entry.saveStatus == 'partial')) {
      return EntryPreflight(
        state: EntryLocalState.filesMissing,
        url: url,
        entry: entry,
      );
    }

    return EntryPreflight(
      state: switch (entry.saveStatus) {
        'complete' => EntryLocalState.complete,
        'partial' => EntryLocalState.partial,
        // Known to exist on the source, never attempted locally: free to
        // save, no decision needed — this is not a failed save.
        'knownRemote' => EntryLocalState.none,
        _ => EntryLocalState.failed,
      },
      url: url,
      entry: entry,
    );
  }

  /// Look ahead over a bounded range using the next-URL chain already stored
  /// from previous saves.
  ///
  /// Only reaches as far as the chain is known — the rest of a range is not
  /// discoverable without visiting each page, which is why the run also
  /// applies the policy per entry.
  Future<RangePreflight> inspectRange(String startUrl, int count) async {
    final entries = <EntryPreflight>[];
    var url = startUrl;
    final seen = <String>{};

    for (var i = 0; i < count; i++) {
      final key = normalizeUrl(url);
      if (!seen.add(key)) break;

      final entry = await inspect(url);
      entries.add(entry);

      final next = entry.entry?.nextSourceUrl;
      if (next == null) break;
      url = next;
    }
    return RangePreflight(entries: entries, requestedCount: count);
  }
}
