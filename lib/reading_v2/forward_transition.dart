/// Reading on to the next Entry: completion, then the Collection's rule.
///
/// **Three decisions that look like one and are not:** has the reader finished
/// this Entry, where are they going, and what happens to the finished Entry's
/// downloaded copy. Collapsing them is how *Next* turns into a delete button,
/// so they are kept apart here exactly as V1 kept them apart.
///
/// ## Why this is a service and not reader state
///
/// V1 held the plan in the reader screen's `State` and applied it after the
/// destination finished loading — possible because that screen loaded the next
/// Entry into itself. V2's reader is handed a package and the route *replaces*
/// itself to move (`V2ReaderRoute`), so the widget that asked the questions is
/// gone before the answer is owed. The plan therefore lives one level up, in
/// something the route transition does not destroy, and the destination's own
/// route reports its arrival to it.
///
/// ## The order, and what it protects
///
/// 1. Work out whether this move even means anything — **forward**, inside one
///    **Collection**, out of an Entry this device is actually holding bytes for.
/// 2. Ask whatever has to be asked, while the reader is still on the Entry the
///    questions are about.
/// 3. Move.
/// 4. **Only once the destination has genuinely opened**, mark the outgoing
///    Entry read and free its copy.
///
/// Step 4 is the whole point. "Opened" means the package resolved to something
/// readable — not that a row looked right a moment earlier. A destination whose
/// files vanished between the tap and the read, or one this device never
/// downloaded, leaves the outgoing Entry with its reading state *and* its
/// bytes: that Entry is then the only thing the reader can still read. A move
/// that is cancelled, or that never arrives, writes nothing at all.
///
/// ## What is never touched
///
/// Applying a `remove` rule frees an **OfflineCopy**. The Entry, its Collection
/// membership, its Locations, its ordinal, its title, its reading history and
/// its read mark are all untouched, on this device and on every other one
/// (V2_SYNC.md §5 — the space is freed here only). Nothing in this file can
/// remove anything from the library.
library;

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/offline_copy_repository.dart';
import '../data/reading_state_repository.dart';
import '../domain/reading_state.dart';
import '../reading/reading_position.dart'
    show CompletionPolicy, kDefaultCompletionPolicy;
import '../save/entry_capture.dart' show removeOfflineCopies;
import '../storage/file_store.dart';
import 'finished_cleanup.dart';

/// What the reader should do with the Entry it is leaving, when that Entry is
/// close to the end but not finished.
///
/// Three outcomes and no fourth: continuing is not a decision about completion,
/// so "move on and leave it as it is" has to be a first-class answer rather
/// than something the user gets by dismissing a dialog.
enum EntryCompletionChoice {
  /// Mark it read, then apply the Collection's rule to it.
  completeAndContinue,

  /// Move on and change nothing about it — reading state, position and bytes
  /// all stay.
  continueWithout,

  /// Stay where you are.
  cancel,
}

/// What the completion question needs to say.
class CompletionQuestion {
  const CompletionQuestion({
    required this.entryName,
    required this.percentRead,
    required this.willRemoveCopy,
  });

  final String entryName;
  final int percentRead;

  /// Whether saying *complete* is also what frees this Entry's bytes.
  ///
  /// This is what turns the question from bookkeeping into a consequence, and
  /// it is answered **before** the tap rather than reported after it. False
  /// when the Collection has no rule yet, because the rule question comes next
  /// and explains itself.
  final bool willRemoveCopy;
}

/// What the Collection question needs to say.
class CleanupRuleQuestion {
  const CleanupRuleQuestion({
    required this.collectionId,
    required this.collectionName,
  });

  final String collectionId;
  final String collectionName;
}

/// Ask whether an unfinished Entry is finished. Null is *cancel*.
typedef AskToComplete =
    Future<EntryCompletionChoice?> Function(CompletionQuestion question);

/// Ask what this Collection does with a finished Entry's copy. Null stores
/// nothing and keeps the bytes.
typedef AskForCleanupRule =
    Future<FinishedCleanupRule?> Function(CleanupRuleQuestion question);

/// What a forward move owes the Entry it left behind.
class ForwardPlan {
  const ForwardPlan({
    required this.leavingEntryId,
    required this.targetEntryId,
    required this.markComplete,
    required this.removeCopy,
  });

  final String leavingEntryId;

  /// The Entry whose arrival makes this plan due. Any other arrival means the
  /// transition this plan belongs to did not happen.
  final String targetEntryId;

  final bool markComplete;
  final bool removeCopy;

  bool get hasWork => markComplete || removeCopy;
}

/// Orchestrates one forward move at a time, and holds what it owes until the
/// destination opens.
class ForwardTransitionService {
  ForwardTransitionService({
    required this.entries,
    required this.collections,
    required this.reading,
    required this.offlineCopies,
    required this.fileStore,
    required this.preferences,
    this.policy = kDefaultCompletionPolicy,
  });

  final EntryRepository entries;
  final CollectionRepository collections;
  final ReadingStateRepository reading;
  final OfflineCopyRepository offlineCopies;
  final FileStore fileStore;
  final FinishedCleanupPreferenceStore preferences;

  /// Where "near enough to the end to be worth asking about" comes from —
  /// `CompletionPolicy.nearEnd`, 0.90, which has meant exactly this since it
  /// was introduced and has had no caller since `b1be16d`.
  final CompletionPolicy policy;

  ForwardPlan? _pending;

  /// True while a question is on screen. One at a time: a second tap arriving
  /// mid-question must not stack a duplicate dialog, plan the same move twice,
  /// or race a conflicting write.
  bool _asking = false;

  /// What the next arrival owes. Read-only, and read only by tests: the plan is
  /// this service's to hold, and a caller that could inspect it would soon be a
  /// caller that decided when it falls due.
  ForwardPlan? get pending => _pending;

  /// Decide what leaving [fromEntryId] for [toEntryId] means, asking whatever
  /// has to be asked.
  ///
  /// Returns **whether the reader may move**. False means the user cancelled,
  /// and nothing at all has been written on the way here — staying put is
  /// simply not doing the rest of it.
  ///
  /// [fraction] is how far through the outgoing Entry the reader is *now*. It
  /// comes from the live position rather than from a row because an offline
  /// read stores an anchor, not a fraction: the rendering the fraction is
  /// about is the one on screen.
  Future<bool> begin({
    required String fromEntryId,
    required String toEntryId,
    required double fraction,
    AskToComplete? askToComplete,
    AskForCleanupRule? askForCleanupRule,
  }) async {
    if (_asking) return false;

    // A plan belongs to exactly one transition. Starting another one abandons
    // whatever the last one was owed rather than letting it fall due later on
    // an Entry it was never about.
    _pending = null;
    if (fromEntryId == toEntryId) return true;

    _asking = true;
    try {
      final plan = await _plan(
        fromEntryId: fromEntryId,
        toEntryId: toEntryId,
        fraction: fraction,
        askToComplete: askToComplete,
        askForCleanupRule: askForCleanupRule,
      );
      if (plan == null) return false;
      if (plan.hasWork) _pending = plan;
      return true;
    } finally {
      _asking = false;
    }
  }

  /// Null means *cancel*; a plan with no work means *move and change nothing*.
  Future<ForwardPlan?> _plan({
    required String fromEntryId,
    required String toEntryId,
    required double fraction,
    required AskToComplete? askToComplete,
    required AskForCleanupRule? askForCleanupRule,
  }) async {
    ForwardPlan nothing() => ForwardPlan(
      leavingEntryId: fromEntryId,
      targetEntryId: toEntryId,
      markComplete: false,
      removeCopy: false,
    );

    final leaving = await entries.byId(fromEntryId);
    final target = await entries.byId(toEntryId);
    if (leaving == null || target == null) return nothing();

    // Forward, in reading order, inside one Collection. A standalone Entry has
    // no reading order to move forward through, and two Collections have no
    // shared one — so neither is a transition this rule is about.
    final collectionId = leaving.collectionId;
    if (collectionId == null || target.collectionId != collectionId) {
      return nothing();
    }
    // The Collection's own order, asked of the Collection — never inferred
    // from ids, titles or the order rows happened to be written.
    final placed = [
      for (final entry in await entries.entriesOf(collectionId))
        if (entry.ordinal != null) entry,
    ];
    final from = placed.indexWhere((e) => e.id == fromEntryId);
    final to = placed.indexWhere((e) => e.id == toEntryId);
    if (from < 0 || to < 0 || to <= from) return nothing();

    // Nothing to free, so nothing to ask. A question whose only honest answer
    // changes nothing is a modal for its own sake, and this app has been
    // removing those (V2-D52).
    if (await offlineCopies.activeCopyOf(fromEntryId) == null) {
      return nothing();
    }

    var markComplete = false;
    final finished =
        (await reading.stateOf(fromEntryId)).status == ReadStatus.completed;
    if (!finished) {
      // Moving forward is not evidence of finishing: a reader looks ahead,
      // compares two Entries, mistaps, or means to come back. Below the near
      // threshold there is too much left for the question to be anything but a
      // nag, so the move is silent and changes nothing.
      if (!policy.nearEnd(fraction)) return nothing();
      if (askToComplete == null) return nothing();

      // Read the rule before asking, so the question can name its consequence:
      // where the Collection already removes, saying *complete* is also what
      // frees this Entry's bytes.
      final stored = await preferences.of(collectionId);
      final choice = await askToComplete(
        CompletionQuestion(
          entryName: leaving.title.trim(),
          percentRead: (fraction * 100).clamp(0, 100).round(),
          willRemoveCopy: stored == FinishedCleanupRule.remove,
        ),
      );
      switch (choice) {
        // Dismissed by the barrier or the back gesture is the same answer as
        // Cancel: the reader asked for nothing, so nothing happens — the
        // navigation included.
        case null:
        case EntryCompletionChoice.cancel:
          return null;
        // Move on with the Entry left as it is. No completion, no rule
        // question, and the stored rule is deliberately **not** consulted: it
        // is a rule about finished Entries, and this one is not finished.
        case EntryCompletionChoice.continueWithout:
          return nothing();
        case EntryCompletionChoice.completeAndContinue:
          markComplete = true;
      }
    }

    final rule = await _resolveRule(collectionId, askForCleanupRule);
    return ForwardPlan(
      leavingEntryId: fromEntryId,
      targetEntryId: toEntryId,
      markComplete: markComplete,
      removeCopy: rule == FinishedCleanupRule.remove,
    );
  }

  /// The Collection's rule, asking for it once if it has none.
  ///
  /// Null means *there is no rule to apply*: the question was dismissed without
  /// an answer, or there was nobody to ask. Both keep the bytes and store
  /// nothing, and the question comes back on the next eligible move.
  ///
  /// An answer is persisted the moment it is given, before the reader moves. It
  /// is a rule about the Collection, not about this transition — what waits for
  /// the destination is the *removal*, never the rule.
  Future<FinishedCleanupRule?> _resolveRule(
    String collectionId,
    AskForCleanupRule? ask,
  ) async {
    final stored = await preferences.of(collectionId);
    if (stored != null) return stored;
    if (ask == null) return null;

    final collection = await collections.byId(collectionId);
    final decision = await ask(
      CleanupRuleQuestion(
        collectionId: collectionId,
        collectionName: collection?.name ?? '',
      ),
    );
    if (decision == null) return null;
    // The Collection was captured before the question opened, so an answer can
    // only ever be written to the Collection it was asked about.
    await preferences.remember(collectionId, decision);
    return decision;
  }

  /// The destination opened. Carry out whatever the move owes.
  ///
  /// [readable] is the destination resolving to something the reader can
  /// actually show. False — a package whose files are gone, an Entry this
  /// device never downloaded, a manifest a newer build wrote — applies
  /// nothing: the Entry just left is then the only readable thing there is,
  /// and it keeps its reading state and its bytes.
  Future<void> arrived({
    required String entryId,
    required bool readable,
  }) async {
    final plan = _pending;
    if (plan == null) return;
    // Due once, whatever happens next.
    _pending = null;
    if (plan.targetEntryId != entryId || !readable) return;

    if (plan.markComplete) {
      // Reading state only. `markRead` keeps `firstOpenedAt`, and a later
      // access write cannot undo it — `recordSourceAccess` only ever lifts
      // unread to reading.
      await reading.markRead(plan.leavingEntryId);
    }
    if (plan.removeCopy) {
      // Bytes only, on this device only: the package, then the copy rows.
      // Nothing else about the Entry is named by this call, which is what
      // makes "the Entry survives" a property of the code rather than a claim
      // in a comment.
      await removeOfflineCopies(
        entryId: plan.leavingEntryId,
        offlineCopies: offlineCopies,
        fileStore: fileStore,
      );
    }
  }

  /// Forget anything owed, because the move it belongs to is not happening.
  ///
  /// Called when [begin] said the reader may move and then it did not — the
  /// reader was gone by the time the questions were answered. A plan is owed on
  /// arrival at *this destination as part of this move*; left standing, it
  /// would fall due the next time that Entry was opened from anywhere, and free
  /// the bytes of an Entry the user never read on from.
  void abandon() => _pending = null;
}
