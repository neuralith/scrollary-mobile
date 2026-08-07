import '../save/capture_policy.dart';
import '../storage/database.dart';
import 'collection_repository.dart' show displayNameFor;

/// A Library-wide check: **many collections, one visible operation**.
///
/// This file holds two things and no work of its own:
///
/// 1. [collectionCheckBlock] — the single authoritative answer to "can this
///    collection be checked?". The queue asks it before it schedules anything
///    and the Library screen asks it to count what a run would cover, so the
///    number the user is shown and the number that actually runs are the same
///    number.
/// 2. [computeLibraryCheckReport] — a pure reading of a started run, derived
///    from rows that already exist: the queue's own task states, each
///    collection's own `last_check_*` columns, and the `discovered_at` stamps
///    the checker writes. Nothing here is persisted, and nothing here decides
///    anything — the check itself stays in `UpdateChecker`, and the ordering,
///    serialisation and cancellation stay in `TaskQueueController`.
///
/// A Library-wide run **is** a set of ordinary per-collection checks. There is
/// no second checker, no second eligibility rule and no second cancel path;
/// what is added is the ability to see them as one piece of work.

/// Why a collection takes no part in a Library-wide check.
///
/// Every value is a fact about existing state, not a preference. A durable
/// "track this collection" flag would need a schema column, and the honest
/// answer is already derivable: archived collections are asleep, restricted
/// sources are never captured from, and a collection with no page to start
/// from is one the checker itself refuses.
enum CollectionCheckBlock {
  /// A standalone entry, which belongs to no collection and so has no entry
  /// list to ask about.
  standalone,

  /// Archived: asleep until restored.
  archived,

  /// Its source is a service this app does not save from.
  restrictedSource,

  /// Nothing to start the walk from — no usable collection page, and no saved
  /// entry with a page address.
  nothingToCheckYet,
}

/// One line for the user, per exclusion. Deliberately about the collection,
/// never about what the user was trying to do.
String collectionCheckBlockLabel(CollectionCheckBlock block) => switch (block) {
  CollectionCheckBlock.standalone => 'Saved on its own, not in a collection',
  CollectionCheckBlock.archived => 'Archived',
  CollectionCheckBlock.restrictedSource => kCaptureRestrictedMessage,
  CollectionCheckBlock.nothingToCheckYet => 'Nothing saved to check from yet',
};

/// Is this collection's source on a restricted service?
///
/// The one place the three columns a collection carries its source in are
/// asked together. `host` is the identity column it was created with; the two
/// URLs are asked as well so a row written before that column was reliable is
/// still caught.
bool collectionSourceIsRestricted(Collection collection) =>
    isRestrictedCaptureHost(collection.host) ||
    isCaptureRestricted(collection.sourceUrl) ||
    isCaptureRestricted(collection.collectionIndexUrl);

/// Null when this collection can be checked; otherwise why not.
///
/// The last clause mirrors [UpdateChecker] step for step, because a rule that
/// disagreed with the checker would either hide checkable collections or
/// schedule work that can only fail: the walk starts at the collection page
/// when there is a usable one, and otherwise at the newest saved entry's own
/// page. A collection with neither has nothing to open.
CollectionCheckBlock? collectionCheckBlock({
  required Collection? collection,
  required List<Entry> entries,
}) {
  if (collection == null) return CollectionCheckBlock.standalone;
  if (collection.lifecycle == 'archived') return CollectionCheckBlock.archived;
  if (collectionSourceIsRestricted(collection)) {
    return CollectionCheckBlock.restrictedSource;
  }
  if (entries.isEmpty) return CollectionCheckBlock.nothingToCheckYet;

  final indexUrl = collection.collectionIndexUrl?.trim() ?? '';
  if (indexUrl.isNotEmpty && collection.collectionKey != null) return null;
  // `captureHostOf` is the app's existing "is this a web page address at all"
  // answer — parseable, http/https, with a host. Reused rather than restated.
  final hasStartPage = entries.any((e) => captureHostOf(e.sourceUrl) != null);
  return hasStartPage ? null : CollectionCheckBlock.nothingToCheckYet;
}

/// One Library-wide run, as the user started it.
///
/// In memory for the session, deliberately. The *results* it reports are all
/// read back from durable rows, so nothing is lost by not persisting this —
/// what does not survive a restart is only the framing of "these collections
/// were one run", and inventing a schema column to carry that would be storage
/// for a heading.
class LibraryCheckPlan {
  const LibraryCheckPlan({
    required this.startedAt,
    required this.collectionIds,
    required this.taskIds,
    this.stopRequested = false,
    this.preparing = false,
  });

  /// The moment before the first row was written. Everything discovered or
  /// checked at or after it belongs to this run.
  const LibraryCheckPlan.preparing(this.startedAt)
    : collectionIds = const [],
      taskIds = const [],
      stopRequested = false,
      preparing = true;

  final DateTime startedAt;

  /// Parallel lists: `collectionIds[i]` is checked by `taskIds[i]`.
  final List<String> collectionIds;
  final List<String> taskIds;

  /// The user asked to stop. Waiting collections were cancelled; the one in
  /// flight was left to finish, which is the queue's own stop semantic.
  final bool stopRequested;

  /// Between the tap and the rows existing.
  final bool preparing;

  int get total => collectionIds.length;

  LibraryCheckPlan asStopping() => LibraryCheckPlan(
    startedAt: startedAt,
    collectionIds: collectionIds,
    taskIds: taskIds,
    stopRequested: true,
  );
}

/// How one collection of a run ended, or where it is.
enum CollectionCheckOutcome {
  /// Queued behind the others; nothing has opened yet.
  waiting,
  checking,
  upToDate,
  newEntries,

  /// Failed, or stopped by a condition the app honours. Never merged with
  /// "up to date" — "we could not ask" and "we asked and there was nothing"
  /// are different answers.
  needsAttention,

  /// Cancelled or dropped before it ran. Not a failure: it simply was not
  /// checked.
  notChecked,
}

/// One collection's line in the run.
class CollectionCheckLine {
  const CollectionCheckLine({
    required this.collectionId,
    required this.title,
    required this.outcome,
    this.newEntries = 0,
    this.staleRemoved = 0,
    this.detail,
  });

  final String collectionId;
  final String title;
  final CollectionCheckOutcome outcome;

  /// Entries this run discovered for this collection. Discovered, not saved.
  final int newEntries;

  /// Entries this run took *off* the list, because the source no longer
  /// carries them and none had ever been downloaded.
  ///
  /// A separate number from [newEntries] and never added to it. They are
  /// opposite facts about the same source, and a collection can perfectly well
  /// report both — one entry published, one withdrawn, in the same check.
  final int staleRemoved;

  /// Why it needs attention, when it does.
  final String? detail;
}

/// Where the whole run is.
enum LibraryCheckPhase {
  idle,
  preparing,
  checking,

  /// Nothing can start yet: something else is holding the Browser. Not an
  /// error — the rows are queued and drain when it frees.
  blocked,

  /// Every collection was checked and none needed attention.
  completed,

  /// Some collections were checked and some were not, or some need attention.
  /// A technical problem with one collection never erases the rest.
  partiallyCompleted,

  /// Stopped by the user. What had been checked is kept.
  cancelled,

  /// The run was started but no collection was ever scheduled.
  failedBeforeAnyCheck,
}

/// A run, read off the rows.
class LibraryCheckReport {
  const LibraryCheckReport({
    required this.phase,
    required this.lines,
    this.startedAt,
    this.stopRequested = false,
  });

  static const idle = LibraryCheckReport(
    phase: LibraryCheckPhase.idle,
    lines: [],
  );

  final LibraryCheckPhase phase;
  final List<CollectionCheckLine> lines;
  final DateTime? startedAt;
  final bool stopRequested;

  int get total => lines.length;
  int _count(CollectionCheckOutcome o) =>
      lines.where((l) => l.outcome == o).length;

  int get upToDateCount => _count(CollectionCheckOutcome.upToDate);
  int get withNewEntriesCount => _count(CollectionCheckOutcome.newEntries);
  int get needsAttentionCount => _count(CollectionCheckOutcome.needsAttention);
  int get notCheckedCount => _count(CollectionCheckOutcome.notChecked);
  int get waitingCount => _count(CollectionCheckOutcome.waiting);
  int get checkingCount => _count(CollectionCheckOutcome.checking);

  /// Collections this run actually asked the source about.
  int get checkedCount =>
      upToDateCount + withNewEntriesCount + needsAttentionCount;
  int get remainingCount => waitingCount + checkingCount;

  /// Entries discovered across the whole run. Discovered — none of them was
  /// downloaded, and none of them will be without an explicit save.
  int get newEntryCount => lines.fold(0, (sum, l) => sum + l.newEntries);

  /// Entries taken off the lists across the whole run, because their sources
  /// no longer carry them. Kept apart from [newEntryCount] everywhere.
  int get staleRemovedCount => lines.fold(0, (sum, l) => sum + l.staleRemoved);

  /// The collection being checked right now, when one is.
  String? get currentTitle => lines
      .where((l) => l.outcome == CollectionCheckOutcome.checking)
      .map((l) => l.title)
      .firstOrNull;

  List<CollectionCheckLine> get withNewEntries => lines
      .where((l) => l.outcome == CollectionCheckOutcome.newEntries)
      .toList();
  List<CollectionCheckLine> get needingAttention => lines
      .where((l) => l.outcome == CollectionCheckOutcome.needsAttention)
      .toList();

  bool get isRunning =>
      phase == LibraryCheckPhase.preparing ||
      phase == LibraryCheckPhase.checking ||
      phase == LibraryCheckPhase.blocked;

  bool get isTerminal =>
      phase == LibraryCheckPhase.completed ||
      phase == LibraryCheckPhase.partiallyCompleted ||
      phase == LibraryCheckPhase.cancelled ||
      phase == LibraryCheckPhase.failedBeforeAnyCheck;
}

/// How a finished check ended, from the collection's own `last_check_result`.
/// Falling back to what this run discovered keeps the reading honest for a row
/// written before that column existed.
CollectionCheckOutcome _outcomeFromStoredResult(String? stored, int found) =>
    switch (stored) {
      'upToDate' => CollectionCheckOutcome.upToDate,
      'updatesAvailable' => CollectionCheckOutcome.newEntries,
      'cancelled' => CollectionCheckOutcome.notChecked,
      'failed' => CollectionCheckOutcome.needsAttention,
      _ =>
        found > 0
            ? CollectionCheckOutcome.newEntries
            : CollectionCheckOutcome.upToDate,
    };

/// Read a started run off the rows it produced.
///
/// Pure, and deliberately derived rather than accumulated: a counter kept in
/// memory would disagree with the database the first time a check ended while
/// the screen was not built. Three durable sources answer three questions —
/// the queue row says where the collection is, the collection's own
/// `last_check_result` says how its check ended, and `discovered_at` says what
/// this run found.
/// [staleRemoved] is the one number that cannot be derived: the rows it counts
/// were deleted, so nothing is left to read it off. It is passed in from the
/// checker's own session record — see `UpdateChecker.staleRemovedFor` — and an
/// absent collection simply reports zero, which is what "nothing can still say"
/// should look like.
LibraryCheckReport computeLibraryCheckReport({
  required LibraryCheckPlan? plan,
  required List<QueueTask> tasks,
  required List<Collection> collections,
  required List<Entry> entries,
  Map<String, int> staleRemoved = const {},
  bool browserBusyElsewhere = false,
}) {
  if (plan == null) return LibraryCheckReport.idle;
  if (plan.preparing) {
    return LibraryCheckReport(
      phase: LibraryCheckPhase.preparing,
      lines: const [],
      startedAt: plan.startedAt,
    );
  }
  if (plan.taskIds.isEmpty) {
    return LibraryCheckReport(
      phase: LibraryCheckPhase.failedBeforeAnyCheck,
      lines: const [],
      startedAt: plan.startedAt,
    );
  }

  // Timestamps come back from the database in whole seconds. Comparing them
  // against a start time that carries milliseconds would drop everything
  // written in the same second the run began — which, for a check that starts
  // immediately, is most of the first collection.
  final since = DateTime.fromMillisecondsSinceEpoch(
    (plan.startedAt.millisecondsSinceEpoch ~/ 1000) * 1000,
  );

  final taskById = {for (final t in tasks) t.id: t};
  final collectionById = {for (final c in collections) c.id: c};
  final discovered = <String, int>{};
  for (final entry in entries) {
    final id = entry.collectionId;
    final at = entry.discoveredAt;
    if (id == null || at == null) continue;
    if (at.isBefore(since)) continue;
    discovered[id] = (discovered[id] ?? 0) + 1;
  }

  final lines = <CollectionCheckLine>[];
  for (var i = 0; i < plan.collectionIds.length; i++) {
    final collectionId = plan.collectionIds[i];
    final collection = collectionById[collectionId];
    final task = taskById[plan.taskIds[i]];
    final found = discovered[collectionId] ?? 0;
    final lastCheckAt = collection?.lastCheckAt;
    final checkedThisRun = lastCheckAt != null && !lastCheckAt.isBefore(since);

    // The collection's stored result is only about *this* run when it was
    // stamped during it; an older one describes some earlier check and must
    // not be reported as today's answer.
    final stored = checkedThisRun ? collection?.lastCheckResult : null;
    final outcome = switch (task?.state) {
      'queued' => CollectionCheckOutcome.waiting,
      'running' => CollectionCheckOutcome.checking,
      'cancelled' => CollectionCheckOutcome.notChecked,
      'failed' => CollectionCheckOutcome.needsAttention,
      // A completed row is itself the evidence the collection was asked; the
      // stored result only says what the answer was.
      'completed' => _outcomeFromStoredResult(stored, found),
      // No row in this snapshot. Either it has not appeared yet — the rows are
      // written and read through separate streams, so a just-started run sees
      // exactly this for an instant — or history was cleared under the run.
      // Without the collection's own stamp there is no result to report, and
      // **waiting** is what "nothing is known yet" means: reading it as "not
      // checked" would make a run that has barely started look finished, and
      // finished means a completion the user is shown once.
      _ =>
        checkedThisRun
            ? _outcomeFromStoredResult(stored, found)
            : CollectionCheckOutcome.waiting,
    };

    lines.add(
      CollectionCheckLine(
        collectionId: collectionId,
        title: collection == null
            ? 'This collection is no longer listed'
            : displayNameFor(collection),
        outcome: outcome,
        newEntries: outcome == CollectionCheckOutcome.newEntries ? found : 0,
        // Reported for any collection this run actually asked, including one
        // that ended `upToDate`: withdrawing an entry is a real result even
        // when nothing was published.
        staleRemoved: checkedThisRun ? (staleRemoved[collectionId] ?? 0) : 0,
        detail: outcome == CollectionCheckOutcome.needsAttention
            ? (collection?.lastCheckError ?? task?.lastError)
            : null,
      ),
    );
  }

  final report = LibraryCheckReport(
    phase: LibraryCheckPhase.checking,
    lines: lines,
    startedAt: plan.startedAt,
    stopRequested: plan.stopRequested,
  );

  final LibraryCheckPhase phase;
  if (report.remainingCount > 0) {
    phase =
        report.checkedCount == 0 &&
            report.checkingCount == 0 &&
            browserBusyElsewhere
        ? LibraryCheckPhase.blocked
        : LibraryCheckPhase.checking;
  } else if (report.checkedCount == 0) {
    phase = LibraryCheckPhase.cancelled;
  } else if (plan.stopRequested && report.notCheckedCount > 0) {
    phase = LibraryCheckPhase.cancelled;
  } else if (report.needsAttentionCount > 0 || report.notCheckedCount > 0) {
    phase = LibraryCheckPhase.partiallyCompleted;
  } else {
    phase = LibraryCheckPhase.completed;
  }

  return LibraryCheckReport(
    phase: phase,
    lines: lines,
    startedAt: plan.startedAt,
    stopRequested: plan.stopRequested,
  );
}

extension on Iterable<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
