import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library_ui/providers.dart';
import '../providers.dart' show cleanupProvider, forwardTransitionProvider;
import '../reading_v2/finished_cleanup.dart';
import '../reading_v2/forward_transition.dart';
import '../reading_v2/next_entry.dart';
import '../reading_v2/offline_read.dart';
import '../storage/cleanup.dart';
import 'cleanup_dialogs.dart';
import 'next_entry_sheets.dart';
import 'reader_screen.dart';

/// The V2 reader route: resolve the Entry's OfflineCopy first, then open the
/// real reader with its data provided — it never touches a V1 row on this
/// path, and an Entry with no copy renders the reader's honest
/// "not downloaded" state rather than a spinner that cannot end.
///
/// **It also owns the move to the next Entry**, because the reader cannot. The
/// screen is handed one package and this route *replaces* itself to move, so
/// the widget that asks "did you finish this?" is disposed before the answer is
/// owed. What survives the replacement is `ForwardTransitionService`, held for
/// the app; this route asks it what a move means on the way out, and reports
/// its own arrival to it on the way in. See
/// `lib/reading_v2/forward_transition.dart`.
class V2ReaderRoute extends ConsumerStatefulWidget {
  const V2ReaderRoute({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<V2ReaderRoute> createState() => _V2ReaderRouteState();
}

class _V2ReaderRouteState extends ConsumerState<V2ReaderRoute> {
  /// Read once, in `initState`, and held: every one of these is used after an
  /// `await`, where reading a provider off a state that may already have been
  /// disposed would throw — and the arrival that frees the last Entry's bytes
  /// must not be the thing that throws.
  late final LibraryUiServices _services;
  late final ForwardTransitionService _transitions;
  late final CleanupService _cleanup;

  /// What follows an Entry, asked of the library rather than of this route's
  /// last resolution — see [_requestNextEntry].
  late final NextEntryResolver _nextEntry;

  /// How this app opens a page, and how it checks a Collection for new
  /// Entries. Both are composition seams and both are read once, in
  /// `initState`, for the same reason everything else here is: they are used
  /// after an `await`, where a disposed state cannot read a provider.
  late final SourceOpener? _openSource;
  late final CollectionChecker? _checkCollection;

  /// True while a next-Entry request is being answered. One at a time: a second
  /// tap, or a pull arriving while a sheet is up, must not stack a duplicate
  /// question or start two moves.
  bool _requestingNext = false;

  /// Resolved once per Entry — and **not** in `build`, which would re-resolve
  /// the package on every rebuild and re-report the arrival with it.
  late Future<_ReaderRouteData> _data;

  /// Which Entry [_data] is about. Not always `widget.entryId`: this state is
  /// reused across the replacement (see [didUpdateWidget]), and the old
  /// resolution is still the one on screen until the new one lands.
  late String _resolving;

  @override
  void initState() {
    super.initState();
    _services = ref.read(libraryUiServicesProvider);
    _transitions = ref.read(forwardTransitionProvider);
    _cleanup = ref.read(cleanupProvider);
    _openSource = ref.read(sourceOpenerProvider);
    _checkCollection = ref.read(collectionCheckerProvider);
    _nextEntry = NextEntryResolver(
      entries: _services.entries,
      collections: _services.collections,
      offlineCopies: _services.offline,
    );
    _open(widget.entryId);
  }

  /// **Replacing this route reuses this state.** `pushReplacement` swaps one
  /// match of `/reader/:entryId` for another, and the router gives both the
  /// same page identity — so the arriving Entry arrives as a *widget update*,
  /// and `initState` is not run again. Everything that identifies the Entry
  /// being read has to be redone here, or the reader would go on holding the
  /// last one's package, its lock and its arrival.
  @override
  void didUpdateWidget(V2ReaderRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId == widget.entryId) return;
    _cleanup.leaveReader(oldWidget.entryId);
    _open(widget.entryId);
  }

  void _open(String entryId) {
    _resolving = entryId;
    // The bytes under this reader are not a sweep's to free.
    _cleanup.enterReader(entryId);
    _data = _resolve(entryId);
  }

  @override
  void dispose() {
    _cleanup.leaveReader(_resolving);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReaderRouteData>(
      future: _data,
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ReaderScreen(
          // Keyed by the Entry, so an arriving one is never drawn by the state
          // that was reading the last one. The spinner between two
          // resolutions already forces that today; the key is what makes it a
          // property of this route rather than of that gap.
          key: ValueKey('reader-${resolved.entryId}'),
          entryId: resolved.entryId,
          offline: resolved.read,
          collectionId: resolved.collectionId,
          previousEntryId: resolved.previousEntryId,
          // Offered wherever this Entry has a reading order at all — what
          // actually follows it is resolved when the reader asks, not when
          // the reader opened.
          onRequestNext: resolved.hasReadingOrder ? _requestNextEntry : null,
          onOpenEntry: _openEntry,
        );
      },
    );
  }

  /// The package, where the reader's swipe-back goes, and the neighbours.
  ///
  /// The Collection is resolved here rather than inside the reader: it is a
  /// library fact and the reader is handed a package, so the one place that
  /// already holds the library services is the one that answers it.
  Future<_ReaderRouteData> _resolve(String entryId) async {
    final read = await openOfflineRead(
      entryId: entryId,
      offlineCopies: _services.offline,
      reading: _services.reading,
      fileStore: _services.fileStore,
    );
    final entry = await _services.entries.byId(entryId);
    final collectionId = entry?.collectionId;

    // Where back leads, by the Collection's own order — not the previous URL,
    // and not the previous thing this device happens to hold. An entry with no
    // copy is still a neighbour: the route for it renders the reader's honest
    // not-downloaded state, where downloading and opening at the source are
    // already offered.
    //
    // Only backwards. Forwards is [_requestNextEntry], resolved at the moment
    // it is asked, because "what comes next" changes under a reader who is
    // reading — a download lands, a check writes a row — and an answer worked
    // out when the Entry opened would be the stale one.
    String? previous;
    final hasReadingOrder = collectionId != null && entry?.ordinal != null;
    if (hasReadingOrder) {
      final placed = await placedEntriesOf(_services.entries, collectionId);
      final index = placed.indexWhere((e) => e.id == entryId);
      if (index > 0) previous = placed[index - 1].id;
    }

    // The destination has genuinely opened — or genuinely has not. Either way
    // this is the moment the last move's plan falls due, and the *only* one:
    // a package whose files are gone, or an Entry this device never
    // downloaded, applies nothing, so the Entry just left keeps its reading
    // state and its bytes and stays the one thing still readable.
    await _transitions.arrived(
      entryId: entryId,
      readable: read.read is! OfflineReadUnavailable,
    );

    return _ReaderRouteData(
      entryId: entryId,
      read: read,
      collectionId: collectionId,
      previousEntryId: previous,
      hasReadingOrder: hasReadingOrder,
    );
  }

  /// Leave for another Entry, [fraction] of the way through this one.
  ///
  /// Backward moves and moves out of a standalone Entry reach here too and are
  /// decided the same way — `begin` asks the **Collection's order** whether
  /// this is a forward move, and everything that is not one moves silently.
  Future<void> _openEntry(String entryId, double fraction) async {
    final mayMove = await _transitions.begin(
      fromEntryId: _resolving,
      toEntryId: entryId,
      fraction: fraction,
      askToComplete: _askToComplete,
      askForCleanupRule: _askForCleanupRule,
    );
    if (!mayMove) return;
    if (!mounted) {
      // The reader went away while the questions were up. Nothing has been
      // written, and the plan must go with it: it is owed on *arrival at this
      // destination as part of this move*, and that move is not happening. Left
      // standing it would fall due the next time this Entry was opened from
      // anywhere at all — which could be days later, from the Library — and
      // free the bytes of an Entry the user never actually read on from. V1
      // could not have this bug because its plan lived in the screen and died
      // with it; holding it a level up is what buys the route replacement, and
      // this is the price.
      _transitions.abandon();
      return;
    }
    // Replace rather than push: reading on is moving through one collection,
    // not stacking a screen per entry behind you, so the way back stays the
    // Collection however far you read.
    context.pushReplacement('/reader/$entryId');
  }

  /// **Read on** — the one next-Entry request, whichever way the reader asked.
  ///
  /// The *Next entry* control, the end of a finished Entry and the pull-up from
  /// the bottom edge all arrive here, so the three of them cannot grow three
  /// answers to the same question. What *is* next is resolved fresh, against
  /// the library as it stands now (`lib/reading_v2/next_entry.dart`); what a
  /// move *means* is still `ForwardTransitionService`'s, through [_openEntry].
  Future<void> _requestNextEntry(double fraction) async {
    if (_requestingNext) return;
    _requestingNext = true;
    try {
      await _actOnNext(await _nextEntry.after(_resolving), fraction);
    } finally {
      _requestingNext = false;
    }
  }

  /// Carry out one resolved answer.
  ///
  /// [mayCheck] is false on the second pass — the one after a check has run —
  /// so a Collection whose site had nothing new asks the user nothing a second
  /// time and simply says so.
  Future<void> _actOnNext(
    NextEntryOutcome outcome,
    double fraction, {
    bool mayCheck = true,
  }) async {
    if (!mounted) return;
    switch (outcome) {
      // Nothing to move forward through. The control is not offered in this
      // state, so this is the belt to that braces.
      case NoReadingOrder():
        return;

      // The ordinary case, and deliberately unchanged: the same move, with the
      // same questions, made the same way it has always been made.
      case NextEntryDownloaded(:final entryId):
        await _openEntry(entryId, fraction);

      // In the library, not on this device. The Entry is first-class and the
      // way on is its Source — offered, never taken without being asked.
      case NextEntryAtSourceOnly(
        :final entryId,
        :final entryName,
        :final sourceUrl,
      ):
        final go = await showContinueAtSourceSheet(
          context: context,
          entryName: entryName,
        );
        if (!go || !mounted) return;
        if (sourceUrl == null) {
          _say('No address is recorded for the next entry.');
          return;
        }
        final opener = _openSource;
        if (opener == null) {
          // Honest rather than silent: nothing opened, so nothing is recorded
          // as having been opened.
          _say('Opening a source is not available yet.');
          return;
        }
        await opener(sourceUrl);
        // Opening at the source is two facts, in this order: the page opens,
        // and the library records that it was opened (I16 — never that it was
        // finished).
        await _services.reading.recordSourceAccess(entryId);

      // The library knows of nothing after this one. That is a fact about the
      // library, so the offer is to go and look — never an announcement that
      // the Collection has ended.
      case NoNextEntryYet(:final collectionId, :final collectionName):
        final checker = _checkCollection;
        if (!mayCheck) {
          _say('Nothing new — there is still no next entry in your library.');
          return;
        }
        final go = await showCheckForNewEntriesSheet(
          context: context,
          collectionName: collectionName,
          canCheck: checker != null,
        );
        if (!go || checker == null || !mounted) return;
        // The app's own Collection check, whole: it asks where the user will
        // wait, it is visible, bounded and cancellable, and it downloads
        // nothing. Nothing about a check is reimplemented here.
        await checker(collectionId, collectionName);
        if (!mounted) return;
        // Ask the library again, once. A check writes rows and downloads
        // nothing, so an Entry it found lands on the offer above rather than
        // moving the reader anywhere on its own.
        await _actOnNext(
          await _nextEntry.after(_resolving),
          fraction,
          mayCheck: false,
        );
    }
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<EntryCompletionChoice?> _askToComplete(
    CompletionQuestion question,
  ) async {
    if (!mounted) return EntryCompletionChoice.cancel;
    return showEntryCompletionDialog(
      context: context,
      entryName: question.entryName,
      percentRead: question.percentRead,
      willRemoveCopy: question.willRemoveCopy,
    );
  }

  Future<FinishedCleanupRule?> _askForCleanupRule(
    CleanupRuleQuestion question,
  ) async {
    // Null is the dismissal answer: nothing is stored, the files stay, and the
    // question comes back on the next eligible move.
    if (!mounted) return null;
    return showFinishedCleanupDialog(
      context: context,
      collectionName: question.collectionName,
    );
  }
}

/// The entries either side of one, in its Collection's order.
class ReaderNeighbours {
  const ReaderNeighbours({this.previousEntryId, this.nextEntryId});

  final String? previousEntryId;
  final String? nextEntryId;
}

/// What "the next entry" means in V2: the next one in the **Collection's own
/// order**, not the next URL and not the next thing this device happens to
/// hold.
///
/// An Entry with no copy is still a neighbour — opening one lands on the
/// reader's honest not-downloaded state, where downloading and opening at the
/// source are already offered. A standalone or unplaced Entry has no
/// neighbours by construction, not by omission.
Future<ReaderNeighbours> readerNeighbours(
  LibraryUiServices services,
  String entryId,
) async {
  final entry = await services.entries.byId(entryId);
  final collectionId = entry?.collectionId;
  if (collectionId == null || entry?.ordinal == null) {
    return const ReaderNeighbours();
  }

  final placed = await placedEntriesOf(services.entries, collectionId);
  final index = placed.indexWhere((e) => e.id == entryId);
  if (index < 0) return const ReaderNeighbours();
  return ReaderNeighbours(
    previousEntryId: index > 0 ? placed[index - 1].id : null,
    nextEntryId: index < placed.length - 1 ? placed[index + 1].id : null,
  );
}

class _ReaderRouteData {
  const _ReaderRouteData({
    required this.entryId,
    required this.read,
    required this.collectionId,
    required this.hasReadingOrder,
    this.previousEntryId,
  });

  /// The Entry this resolution is about. Carried rather than read off the
  /// widget: a resolution still in flight belongs to the Entry it started for.
  final String entryId;

  final OfflineReaderData read;
  final String? collectionId;

  /// The entry before this one in the Collection's order. Null at the start,
  /// and for a standalone or unplaced Entry — which has no neighbours by
  /// construction, not by omission.
  final String? previousEntryId;

  /// Whether this Entry is placed in a Collection at all, and so whether
  /// *reading on* is a thing that can be asked for here. False for a
  /// standalone or unplaced Entry.
  ///
  /// Deliberately not "is there a next Entry": that is a question about the
  /// library at the moment it is asked, and this is a question about this
  /// Entry.
  final bool hasReadingOrder;
}
