import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kLongPressTimeout,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../save/save_preflight.dart';
import '../core/config.dart';
import '../providers.dart';
import '../reading/reading_position.dart';
import '../reading/reading_repository.dart';
import '../storage/cleanup.dart';
import '../storage/database.dart';
import '../storage/document.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import '../reading/decode_budget.dart';
import '../ui/palette.dart';
import 'document_reader.dart';
import 'save_queue_ui.dart';
import 'cleanup_dialogs.dart';
import 'library_screen.dart' show formatRelative;
import 'collection_detail_screen.dart' show sortEntriesForReading;

/// How long the reader waits before writing a scroll position.
///
/// Writing every frame would hammer SQLite for nothing; writing only on close
/// loses a whole session to a crash. A short debounce plus an unconditional
/// flush on close and on lifecycle change bounds the loss to this window.
const Duration kProgressSaveInterval = Duration(seconds: 2);

/// Blank space above the first panel, so content starts below the top chrome
/// instead of under it (design: a 104px lead-in).
const double kReaderTopSpacer = 104;

/// The partial-save banner scrolls with the content, so its height is part
/// of the leading extent. Fixed rather than measured: the copy is short and
/// known, and a variable leading extent would make the restore offset
/// unknowable before layout — which is exactly what lets the reader open AT
/// the saved position instead of jumping there afterwards.
const double kPartialBannerExtent = 88;

/// How long the transient reader notice stays on screen.
///
/// Two seconds: it reports something that has already happened and offers one
/// optional way out, so it is read at a glance and then gone. A notice that
/// outstays the glance competes with the page the reader came here for.
///
/// Deliberately inside [CleanupService.undoWindow], so Undo is still real for
/// the whole time the notice offers it. Lengthening this past that window would
/// put a dead button on screen.
const Duration kReaderNoticeDuration = Duration(seconds: 2);

/// Where the floating reader notice sits above the bottom chrome (a 48px
/// control row plus its padding) — the same band the jump chip uses, and it is
/// added to the safe-area inset rather than assuming one: Android's
/// three-button navigation bar reports ~48px there, enough to push the chrome
/// up under a fixed offset and cover the entry controls.
const double kReaderNoticeInset = 104;

/// The one condition under which the reader can open an entry: the package is
/// still on the device and the save got far enough to be readable.
///
/// This is the authority behind every entry-navigation control. A row whose
/// `contentPath` is null has had its downloads removed (by the user, by the
/// finished-entry flow, or by a collection deletion) or was never stored;
/// either way opening it lands on the unavailable screen, so nothing may offer
/// it as a destination. Deletion needs no separate test — a deleted row is not
/// in the collection's entries at all.
///
/// Deliberately **not** derived from a display flag or from a count: the file
/// column and the save status are what [_ReaderScreenState._load] itself
/// checks, so the control and the screen it leads to agree by construction.
bool readerCanOpen(Entry entry) =>
    entry.contentPath != null &&
    (entry.saveStatus == 'complete' || entry.saveStatus == 'partial');

/// What a forward move has undertaken to do to the entry it leaves behind.
///
/// Built before the reader moves, from questions asked while it was still on
/// that entry, and carried until the destination is open. Two fields, both
/// false by default, because the ordinary forward move — a skip ahead, a look
/// at the next entry, a mistap — promises nothing at all.
class _ForwardPlan {
  const _ForwardPlan({
    this.leaving,
    this.markComplete = false,
    this.remove = false,
  });

  /// Move, and change nothing about the entry being left.
  static const none = _ForwardPlan();

  /// The entry being left, when there is something to do to it.
  final Entry? leaving;

  /// The reader said it is finished. Only ever true for an entry that was not
  /// already complete and whose reader answered *Mark complete and continue*.
  final bool markComplete;

  /// The collection's decision is to remove a finished entry's downloads, and
  /// this entry is (or is about to be) finished.
  final bool remove;

  bool get hasWork => leaving != null && (markComplete || remove);
}

/// Vertical image reader over **local files only**.
///
/// No remote-URL fallback exists anywhere in this screen: if a file is missing
/// the reader says so. Falling back to the source would make "offline" a lie
/// that only surfaces once the network is gone.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  ScrollController? _scrollController;
  Future<_ReaderData>? _future;

  /// Image-panel geometry, for the image reader only.
  EntryLayout? _layout;

  /// Whichever geometry the open entry uses. The scroll listener, the flush,
  /// the completion rule and the jump chip all go through this, so they are
  /// written once and work for both artifacts.
  ReadingGeometry? _geometry;

  /// A document's position cannot be applied before layout exists — a
  /// paragraph has no offset until it has been laid out — so the document
  /// reader restores on the first measurement instead of at construction.
  bool _documentRestorePending = false;

  /// The live position, updated on every scroll event. The footer listens to
  /// this directly (M12) so the visible percentage moves *while* scrolling;
  /// persistence stays debounced and reads the same value at flush time.
  /// Nothing else listens — the panel list must not rebuild per scroll tick.
  final ValueNotifier<ReadingPosition> _livePosition = ValueNotifier(
    ReadingPosition.start,
  );
  ReadingPosition get _position => _livePosition.value;
  set _position(ReadingPosition value) => _livePosition.value = value;

  /// Height of everything above panel 1 inside the scroll view. Every
  /// offset conversion goes through this, in both directions.
  double _leadingExtent = kReaderTopSpacer;

  /// Where the entry was restored to, so the jump chip can offer a way
  /// back once the reader has wandered off. The position is what the chip
  /// scrolls to (the anchor is what restore actually used); the fraction is
  /// what it shows.
  ReadingPosition _restoredPosition = ReadingPosition.start;
  double get _restoredFraction => _restoredPosition.fraction;

  Timer? _saveTimer;
  DateTime? _pastThresholdSince;
  bool _completed = false;
  bool _restored = false;
  String? _entryId;

  /// The collection this entry belongs to — the destination of the swipe-back.
  String? _collectionId;

  /// Locally readable siblings of the open entry, in reading order.
  ///
  /// A notifier rather than a field of [_ReaderData] because the list can go
  /// stale *while the reader is open*: the finished-entry flow removes the
  /// downloads of the entry just left, and a collection deletion elsewhere can
  /// take a sibling with it. Both bump [CleanupService.removals], which is what
  /// [_refreshSiblings] listens to — so the entry controls disable themselves
  /// the moment their target stops being openable, instead of staying lit until
  /// the next load and then landing on the unavailable screen.
  final ValueNotifier<List<Entry>> _siblings = ValueNotifier(const <Entry>[]);

  /// Held in a field, not read through `ref`, because the last flush runs
  /// from [dispose] — where Riverpod forbids `ref`. Reading it there threw,
  /// which silently lost the final position on every ordinary reader close.
  late final ReadingRepository _reading;
  late final CleanupService _cleanup;

  /// The transient notice on screen, or null when there is none.
  ///
  /// Screen state and nothing else: never written to the database, never
  /// restored. It is dropped when the entry changes, when the app leaves the
  /// foreground, when the user closes it, and with the screen itself — so a
  /// notice can only ever be seen once, for as long as its own timeout.
  _ReaderNotice? _notice;

  /// Identity for the notice widget, so a second removal *replaces* the first
  /// (fresh countdown, one notice) instead of reusing its element and
  /// inheriting the timeout already half spent.
  int _noticeSeq = 0;

  /// The collection whose cleanup question is on screen, or null when none is.
  ///
  /// Screen state, and the reason a burst of "next entry" taps cannot open a
  /// second dialog or race two decisions into the database.
  String? _cleanupAskCollectionId;

  /// True from the moment a move is asked for until the destination is loading.
  ///
  /// A transition can now sit on an open dialog for as long as the reader takes
  /// to answer it, and every entry control is still on screen behind it. One
  /// transition at a time is what stops the same move being planned — and
  /// applied — twice.
  bool _navigating = false;

  static const _policy = kDefaultCompletionPolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reading = ref.read(readingRepositoryProvider);
    _cleanup = ref.read(cleanupProvider);
    _entryId = widget.entryId;
    _chromeVisibility = ref.read(readerChromeVisibleProvider);
    // The open entry is locked against offline-file removal for as long
    // as this screen exists.
    _cleanup.openReaderEntryId.value = widget.entryId;
    _cleanup.removals.addListener(_onRemovals);
    _future = _load(widget.entryId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanup.removals.removeListener(_onRemovals);
    _saveTimer?.cancel();
    // Fire-and-forget: dispose cannot await, but the write is a single row.
    unawaited(_flush());
    _scrollController?.dispose();
    _livePosition.dispose();
    _siblings.dispose();
    if (_cleanup.openReaderEntryId.value == _entryId) {
      _cleanup.openReaderEntryId.value = null;
    }
    // Whatever this reader hid, it stops hiding on the way out — otherwise the
    // running-operation indicator would stay gone on every screen after it.
    //
    // Deferred rather than written here: `dispose` runs with the element tree
    // locked, where a listener that rebuilds is an error the framework asserts
    // on, and this flag exists precisely to make something else rebuild. A
    // microtask rather than a post-frame callback, because
    // `addPostFrameCallback` does not schedule a frame — a reader disposed on
    // the last frame of a teardown would leave the flag stuck false and the
    // indicator hidden for good. The microtask queue drains at the end of this
    // same frame whether another frame comes or not.
    final chrome = _chromeVisibility;
    scheduleMicrotask(() => chrome.publish(true));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded or about to be killed: write now rather than hoping the
    // debounce fires first.
    if (state != AppLifecycleState.resumed) unawaited(_flush());
    // A notice is a moment, not a state. Cleared on *every* transition rather
    // than only on the way out, so coming back has nothing left to show even
    // if the app was suspended before the timeout could run.
    _clearNotice();
  }

  // --- transient notice ----------------------------------------------------

  /// Show (or replace) the transient notice. There is at most one, ever.
  void _showNotice(
    String text, {
    required IconData icon,
    Future<void> Function()? undo,
  }) {
    if (!mounted) return;
    setState(() {
      _notice = _ReaderNotice(
        id: ++_noticeSeq,
        text: text,
        icon: icon,
        undo: undo,
      );
    });
  }

  void _clearNotice() {
    if (!mounted || _notice == null) return;
    setState(() => _notice = null);
  }

  /// Put the files back, then say so — the confirmation is itself transient
  /// and carries no action.
  Future<void> _undoRemoval(_ReaderNotice notice) async {
    final undo = notice.undo;
    if (undo == null) return;
    // Cleared first: the offer has been taken, and leaving the countdown
    // running would let the timeout fire mid-restore.
    _clearNotice();
    await undo();
    // The files are back, so the entry is a destination again — the controls
    // have to hear about it, since a restore frees nothing and so bumps no
    // removal counter.
    await _refreshSiblings();
    if (!mounted) return;
    // Parallel to the removal copy, and equally short: the verb first, the same
    // noun after it, so the pair reads as one action and its reversal.
    _showNotice('Restored downloads', icon: Icons.undo);
  }

  // --- loading -------------------------------------------------------------

  /// Locally readable siblings, in reading order.
  ///
  /// A standalone entry has none: there is no previous or next, and the reader
  /// says so rather than showing an empty strip where controls were.
  Future<List<Entry>> _siblingsFor(AppDatabase db, Entry entry) async {
    final collectionId = entry.collectionId;
    if (collectionId == null) return const <Entry>[];
    return sortEntriesForReading(
      (await db.entriesForCollection(
        collectionId,
      )).where(readerCanOpen).toList(),
    );
  }

  /// Re-read the neighbours from the database.
  ///
  /// Called whenever something removed offline files anywhere, because the
  /// reader itself is one of the things that does that: finishing an entry and
  /// moving on removes the downloads of the one left behind, which is exactly
  /// the entry the *Previous entry* control was pointing at.
  Future<void> _refreshSiblings() async {
    final id = _entryId;
    if (id == null) return;
    final db = ref.read(databaseProvider);
    final entry = await db.entryById(id);
    if (entry == null) return;
    final siblings = await _siblingsFor(db, entry);
    // The reader may have moved on across those awaits; a list resolved for an
    // entry that is no longer open must not be published.
    if (_entryId != id) return;
    _publishSiblings(siblings);
  }

  /// The only writer of [_siblings].
  ///
  /// Every list is resolved across an await, and the screen can be popped
  /// inside one — so the guard belongs here rather than at each call site,
  /// where forgetting it writes to a disposed notifier.
  void _publishSiblings(List<Entry> siblings) {
    if (!mounted) return;
    _siblings.value = siblings;
  }

  void _onRemovals() => unawaited(_refreshSiblings());

  Future<_ReaderData> _load(String entryId) async {
    final db = ref.read(databaseProvider);
    final store = ref.read(fileStoreProvider);
    final reading = _reading;

    final entry = await db.entryById(entryId);
    if (entry == null) {
      return const _ReaderData.unavailable('This entry is no longer listed.');
    }
    final relative = entry.contentPath;
    if (relative == null && entry.offlineRemovedAt != null) {
      // The USER removed these files. That is a state, not a failure —
      // nothing gets demoted, and the copy says "save again", not
      // "something went wrong".
      return _ReaderData.unavailable(
        'You removed this entry\'s offline files. It\'s still in your '
        'library with your reading history — save it again to read it '
        'here.',
        filesGone: true,
        removedByUser: true,
        unavailableMeta:
            'removed ${formatRelative(entry.offlineRemovedAt)}'
            '${entry.detectedAssetCount > 0 ? ' · ${entry.detectedAssetCount} pages' : ''}',
        unavailableEntry: entry,
      );
    }
    if (relative == null || !store.entryExists(relative)) {
      await db.markEntryContentMissing(entry.id);
      return _ReaderData.unavailable(
        'The local files for "${entry.title}" are gone. The entry is '
        'still listed, but it is not available offline.',
        filesGone: true,
        unavailableMeta: '0 of ${entry.detectedAssetCount} files present',
        unavailableEntry: entry,
      );
    }

    var manifest = await store.readManifest(relative);
    if (manifest == null) {
      return const _ReaderData.unavailable(
        'The entry package is unreadable (missing manifest).',
      );
    }

    // Page geometry is built **only** from dimensions decoded out of the stored
    // bytes at save time (`dimensionsVerified`). There is no repair pass: a
    // version-1 library records verified dimensions when it saves, and re-reading
    // every file on every open to fix manifests this build never wrote would be
    // migration machinery for a shape no library has.
    //
    // What can still happen is a file whose header the decoder does not
    // understand. Then the manifest holds the *page's own claim* about the size,
    // which is a layout assertion and not a pixel fact — panels sized from it
    // laid out at the wrong aspect ratio, which is what "the saved page looks
    // squashed" was. Such a page gets no recorded size at all, so the reader
    // falls back to a fixed box and crops from the top rather than stretching.
    //
    // A package saved by a newer build. Say so rather than misreading it as
    // one of the formats this version does know.
    if (!manifest.artifact.isReadable) {
      return const _ReaderData.unavailable(
        'This entry was saved in a format this version of the app cannot '
        'open. Updating the app should fix it; the files are untouched.',
      );
    }

    if (manifest.isDocument) {
      final document = await store.readDocument(
        relative,
        fileName: manifest.document?.relativePath ?? FileStore.documentFileName,
      );
      if (document == null || document.isEmpty) {
        return const _ReaderData.unavailable(
          'The saved text for this entry is unreadable.',
        );
      }
      _publishSiblings(await _siblingsFor(db, entry));
      await reading.markOpened(entry.id);
      if (entry.collectionId != null) {
        await db.touchCollection(entry.collectionId!);
      }
      _position = reading.positionOf(entry);
      _completed = entry.readStatus == ReadStatus.completed.name;
      _collectionId = entry.collectionId;
      return _ReaderData(
        entry: entry,
        manifest: manifest,
        pages: const [],
        document: document,
        entryDir: Directory(store.resolve(relative)),
      );
    }

    // Manifest order is DOM order, which is reading order.
    final pages = <_ReaderPage>[];
    for (final asset in manifest.storedAssets) {
      final file = store.assetFile(relative, asset.relativePath!);
      pages.add(
        _ReaderPage(
          file: file,
          exists: file.existsSync(),
          width: asset.dimensionsVerified ? asset.width : null,
          height: asset.dimensionsVerified ? asset.height : null,
        ),
      );
    }

    final collectionId = entry.collectionId;
    _publishSiblings(await _siblingsFor(db, entry));

    await reading.markOpened(entry.id);
    if (collectionId != null) await db.touchCollection(collectionId);

    _position = reading.positionOf(entry);
    _completed = entry.readStatus == ReadStatus.completed.name;
    _collectionId = entry.collectionId;

    return _ReaderData(entry: entry, manifest: manifest, pages: pages);
  }

  // --- moving on: completion, then cleanup ---------------------------------

  /// What a forward move should do to the entry it leaves behind — or null
  /// when the user said no and the reader must stay exactly where it is.
  ///
  /// **Completion, navigation and cleanup are three decisions, not one.**
  /// Moving forward is not evidence of finishing: a reader looks ahead,
  /// compares two entries, mistaps, or means to come back. So the only entries
  /// this can plan anything for are the ones already finished, and the ones
  /// the reader has explicitly *said* are finished when asked. Everything else
  /// moves and changes nothing — which is what keeps a collection's remove
  /// preference away from an entry that is still being read.
  ///
  /// Nothing here writes to the entry being left. The questions are asked
  /// while the reader is still on it, and the answers are carried in the plan
  /// until the destination is genuinely open — see [_applyOnArrival].
  Future<_ForwardPlan?> _planForForward(Entry target) async {
    final leavingId = _entryId;
    if (leavingId == null || leavingId == target.id) return _ForwardPlan.none;

    final db = ref.read(databaseProvider);
    final leaving = await db.entryById(leavingId);
    if (leaving == null) return _ForwardPlan.none;

    // Forward only: reading order, not tap order. A standalone entry has no
    // reading order to move forward through, so none of this applies to one.
    final collectionId = leaving.collectionId;
    if (collectionId == null) return _ForwardPlan.none;
    final ordered = sortEntriesForReading(
      await db.entriesForCollection(collectionId),
    );
    final from = ordered.indexWhere((c) => c.id == leaving.id);
    final to = ordered.indexWhere((c) => c.id == target.id);
    if (from < 0 || to < 0 || to <= from) return _ForwardPlan.none;

    final item = await db.collectionById(collectionId);
    if (item == null) return _ForwardPlan.none;

    var markComplete = false;
    if (leaving.readStatus != ReadStatus.completed.name) {
      // The live position rather than the row: [_flush] has just written it,
      // but an entry whose geometry never materialised has nothing to flush
      // and the restored position is still the honest answer.
      if (!_policy.nearEnd(_position.fraction)) return _ForwardPlan.none;
      if (!mounted) return _ForwardPlan.none;

      // Read before the question so the dialog can name the consequence: when
      // this collection already removes downloads after continuing, saying
      // "mark complete" is also what removes this entry's files.
      final stored = collectionCleanupFromName(item.cleanupPreference);
      final choice = await showEntryCompletionDialog(
        context: context,
        entryName: leaving.sourceMarker ?? leaving.title,
        percentRead: (_position.fraction * 100).clamp(0, 100).round(),
        willRemoveDownloads: stored == CollectionCleanupPreference.remove,
      );
      switch (choice) {
        // Dismissed by the barrier or the back gesture is the same answer as
        // Cancel: the reader asked for nothing, so nothing happens — including
        // the navigation.
        case null:
        case EntryCompletionChoice.cancel:
          return null;
        // Moving on with the entry left as it is. No completion, no cleanup
        // question, and the collection's stored preference is deliberately
        // NOT consulted: it is a rule about finished entries, and this one is
        // not finished.
        case EntryCompletionChoice.continueWithout:
          return _ForwardPlan.none;
        case EntryCompletionChoice.completeAndContinue:
          markComplete = true;
      }
    }

    final decision = await _resolveCleanupPreference(item);
    return _ForwardPlan(
      leaving: leaving,
      markComplete: markComplete,
      remove: decision == CollectionCleanupPreference.remove,
    );
  }

  /// The collection's decision about a finished entry's downloaded files,
  /// asking for it once if the collection has none (D37).
  ///
  /// Null means *there is no decision to apply*: the question was dismissed
  /// without an answer, or one is already on screen for this collection.
  /// Both keep the files and store nothing, and the question comes back on the
  /// next eligible transition.
  ///
  /// An answer is persisted the moment it is given, before the reader moves.
  /// That is the existing contract of this question everywhere it is asked —
  /// the dialog's button says *Save choice*, and the collection sheet writes on
  /// each tap — and it is a rule about the collection, not about this
  /// transition. What waits for the destination is the *removal*, never the
  /// rule.
  Future<CollectionCleanupPreference?> _resolveCleanupPreference(
    Collection item,
  ) async {
    final stored = collectionCleanupFromName(item.cleanupPreference);
    if (stored != null) return stored;

    // One question at a time. A second transition arriving while the dialog is
    // open must not stack a duplicate or race a conflicting write.
    if (_cleanupAskCollectionId != null || !mounted) return null;
    _cleanupAskCollectionId = item.id;
    final CollectionCleanupPreference? decision;
    try {
      decision = await showCollectionCleanupDialog(
        context: context,
        collectionName: item.userTitle ?? item.title,
      );
    } finally {
      _cleanupAskCollectionId = null;
    }
    if (decision == null) return null;
    // The collection was captured before the dialog opened, so an answer can
    // only ever be written to the collection it was asked about.
    await ref
        .read(databaseProvider)
        .setCollectionCleanupPreference(item.id, decision.name);
    return decision;
  }

  /// Carry out a plan — but only once the destination is genuinely open.
  ///
  /// "Open" means the load resolved to something readable, not merely that the
  /// row passed [readerCanOpen] a moment earlier. A manifest that turns out to
  /// be unreadable, files that vanished between the check and the read, and a
  /// package written by a newer build all land on the unavailable screen, and
  /// none of them is a reason to finish or empty the entry the reader just
  /// left. That entry is then the only readable thing they had.
  Future<void> _applyOnArrival(
    _ForwardPlan plan,
    Future<_ReaderData> arriving,
    String targetId,
  ) async {
    final leaving = plan.leaving;
    if (leaving == null) return;

    final _ReaderData data;
    try {
      data = await arriving;
    } catch (_) {
      // The destination could not even be read. Nothing was promised about the
      // outgoing entry that has to be honoured now.
      return;
    }
    if (data.unavailableReason != null) return;
    if (!data.isDocument && data.pages.isEmpty) return;
    // The reader moved on again, or left, while the destination was loading:
    // this plan belongs to a transition that is no longer the current one.
    if (_entryId != targetId) return;

    if (plan.markComplete) {
      // [ReadingRepository.markRead] keeps the anchor and only lifts the
      // fraction to 1, so the spot this entry would resume at survives being
      // finished. A progress write still in flight cannot undo it either:
      // `saveProgress` reads the row first and keeps a completed entry
      // completed, whatever the flag it was called with says.
      await _reading.markRead(leaving.id);
    }
    if (plan.remove) await _removeFinished(leaving);
  }

  /// Remove and offer an undo. A failure here never blocks reading — the new
  /// entry is already open; the worst case is that files stay.
  ///
  /// The notice is deliberately minimal: which entry it was is obvious (the
  /// user just left it) and how many megabytes came back is not a decision
  /// anyone makes mid-read. All that matters, for the moment it is up, is that
  /// something was removed and that it can be put back.
  ///
  /// The copy names the *downloads*, never the entry. Removing offline files is
  /// not deleting an entry — the row, the reading position and the history all
  /// survive — so "Removed previous entry" would say the opposite of what
  /// happened. It is the short form of the phrase the cleanup question already
  /// uses ("Keep downloaded files"), so the answer and its consequence read as
  /// one thing, and it is the longest of the honest phrasings that still sets
  /// on one line at 320pt.
  Future<void> _removeFinished(Entry leaving) async {
    try {
      final result = await _cleanup.removeOffline([leaving.id]);
      if (!mounted || result.removed == 0) return;
      _showNotice(
        'Removed downloads',
        icon: Icons.delete_outline,
        undo: result.canUndo ? result.undo.undo : null,
      );
    } catch (e) {
      debugPrint('[cleanup] finished-entry removal failed: $e');
    }
  }

  // --- position ------------------------------------------------------------

  /// Build the layout and open the list already at the saved offset.
  ///
  /// Panel heights come from the manifest, so the geometry is known before any
  /// image decodes — which is what lets the reader open *at* the position
  /// rather than visibly jumping there afterwards.
  ScrollController _controllerFor(_ReaderData data, double viewportWidth) {
    final layout = EntryLayout(
      viewportWidth: viewportWidth,
      panels: [for (final p in data.pages) (width: p.width, height: p.height)],
    );
    if (_layout != null &&
        _layout!.viewportWidth == viewportWidth &&
        _scrollController != null) {
      return _scrollController!;
    }
    _layout = layout;
    _geometry = layout;

    final initial = _restored
        ? 0.0
        : _leadingExtent + layout.offsetForPosition(_position);
    if (!_restored) _restoredPosition = _position;
    _restored = true;

    _scrollController?.dispose();
    final controller = ScrollController(initialScrollOffset: initial)
      ..addListener(_onScroll);
    _scrollController = controller;
    return controller;
  }

  /// The document reader's controller.
  ///
  /// Unlike the image reader this one **cannot** open at the saved offset: a
  /// paragraph has no offset until it has been laid out at this width, in this
  /// font, at this text scale. So it opens at the top and restores on the
  /// first measurement — see [_onDocumentLayout].
  ScrollController _documentController() {
    final existing = _scrollController;
    // Keyed off `_restored`, not off "is there a controller", for the same
    // reason [_controllerFor] is keyed off `_layout`: moving to another entry
    // resets `_restored`, and reusing the previous controller would keep the
    // old scroll offset and — since `_goTo` removed its listener — stop
    // recording progress entirely.
    if (existing != null && _restored) return existing;
    existing?.dispose();

    _restoredPosition = _position;
    _restored = true;
    _documentRestorePending = !_position.isAtStart;

    final controller = ScrollController()..addListener(_onScroll);
    _scrollController = controller;
    return controller;
  }

  /// The document has been measured: adopt its geometry, and restore the
  /// reading position the first time.
  void _onDocumentLayout(DocumentLayout layout) {
    _geometry = layout;
    if (!_documentRestorePending) return;
    _documentRestorePending = false;

    final position = _restoredPosition;
    if (position.isAtStart) return;

    // After the frame that produced this measurement, so the scroll view has
    // the extent to move within.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      if (!mounted || controller == null || !controller.hasClients) return;
      final target = (_leadingExtent + layout.offsetForPosition(position))
          .clamp(0.0, controller.position.maxScrollExtent);
      controller.jumpTo(target);
    });
  }

  void _onScroll() {
    final controller = _scrollController;
    final layout = _geometry;
    if (controller == null || layout == null || !controller.hasClients) return;

    final viewportHeight = controller.position.viewportDimension;
    // Panel geometry starts after the lead-in; convert before asking the
    // layout where we are.
    final panelOffset = (controller.offset - _leadingExtent).clamp(
      0.0,
      double.infinity,
    );
    _position = layout.positionForOffset(
      panelOffset,
      viewportHeight: viewportHeight,
    );

    // The jump chip earns its place only when the reader is genuinely
    // somewhere else — a chip pointing at where you already are is noise.
    final drifted =
        _restoredFraction > 0.02 &&
        (_position.fraction - _restoredFraction).abs() > 0.12;
    if (drifted != _showJump && mounted) {
      setState(() => _showJump = drifted);
    }

    // Completion needs dwell: a fling to the bottom is not reading.
    if (_policy.reachedEnd(_position.fraction)) {
      _pastThresholdSince ??= DateTime.now();
      if (!_completed &&
          DateTime.now().difference(_pastThresholdSince!) >= _policy.dwell) {
        _completed = true;
        unawaited(_flush());
        if (mounted) setState(() {});
      }
    } else {
      _pastThresholdSince = null;
    }

    _saveTimer ??= Timer(kProgressSaveInterval, () {
      _saveTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final id = _entryId;
    if (id == null || _geometry == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _reading.saveProgress(id, _position, completed: _completed);
    } catch (_) {
      // The dispose-time flush is fire-and-forget; if the database is
      // already shutting down there is nowhere left to save to, and an
      // unhandled zone error would be the only result.
    }
  }

  // --- actions -------------------------------------------------------------

  Future<void> _toggleRead() async {
    final id = _entryId;
    if (id == null) return;
    final reading = _reading;
    // A debounced save queued before the tap would land after it and write
    // the status straight back. The user's explicit choice is the newer
    // fact, so the pending write is dropped rather than allowed to race.
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_completed) {
      await reading.markUnread(id);
      _completed = false;
      _pastThresholdSince = null;
    } else {
      await reading.markRead(id);
      _completed = true;
    }
    if (mounted) setState(() {});
  }

  /// Save first, then move.
  ///
  /// The order is the safety property, and it is worth reading as one list:
  /// flush the position of the entry being left; confirm the destination can
  /// be opened at all; ask whatever this transition has to ask, while the
  /// reader is still on the entry the questions are about; move; and only once
  /// the destination has actually opened, apply anything that changes the
  /// entry left behind. A transition that fails or is cancelled at any point
  /// leaves that entry with its progress, its status and its files.
  ///
  /// One at a time, because the questions are awaited: a second tap arriving
  /// mid-transition would otherwise plan the same move twice and could apply
  /// completion or removal twice over.
  Future<void> _goTo(Entry target) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await _navigateTo(target);
    } finally {
      _navigating = false;
    }
  }

  Future<void> _navigateTo(Entry target) async {
    await _flush();

    // The control was drawn from a list; between that frame and this tap the
    // target's downloads may have gone. Ask the row itself before moving, so a
    // stale control can never land the reader on the unavailable screen — and
    // republish the neighbours, which is what disables the control that just
    // failed rather than leaving it lit for the next tap.
    final fresh = await ref.read(databaseProvider).entryById(target.id);
    if (fresh == null || !readerCanOpen(fresh)) {
      await _refreshSiblings();
      return;
    }

    final plan = await _planForForward(fresh);
    // Cancelled. Nothing has been written on the way here, so staying put is
    // simply not doing the rest of this.
    if (plan == null || !mounted) return;

    _saveTimer?.cancel();
    _scrollController?.removeListener(_onScroll);
    // The lock follows the reader: the entry being LEFT is no longer open,
    // and the one arriving is. Without this the entry just finished stays
    // locked against its own cleanup.
    _cleanup.openReaderEntryId.value = target.id;
    final arriving = _load(target.id);
    setState(() {
      // Anything the last transition had to say is about an entry that is no
      // longer on screen. A new removal will post its own notice.
      _notice = null;
      _entryId = target.id;
      _restored = false;
      _layout = null;
      _geometry = null;
      _documentRestorePending = false;
      _completed = false;
      _pastThresholdSince = null;
      _position = ReadingPosition.start;
      _future = arriving;
    });
    if (plan.hasWork) unawaited(_applyOnArrival(plan, arriving, target.id));
  }

  // --- leaving for the entry list ----------------------------------------

  /// Accumulated travel of the drag currently in flight, used to decide
  /// whether it was meant horizontally.
  Offset _dragTravel = Offset.zero;

  /// A right-swipe must clear this much horizontal distance…
  static const double _kSwipeDistance = 72;

  /// …or be flicked at least this fast (logical px/s)…
  static const double _kSwipeVelocity = 420;

  /// …and in either case be at least this much more horizontal than vertical.
  /// Reading is a vertical gesture; anything ambiguous belongs to the scroll
  /// view, not to navigation.
  static const double _kSwipeRatio = 2;

  void _onDragStart(DragStartDetails _) => _dragTravel = Offset.zero;

  void _onDragUpdate(DragUpdateDetails details) {
    _dragTravel += details.delta;
  }

  void _onDragEnd(DragEndDetails details) {
    final dx = _dragTravel.dx;
    final dy = _dragTravel.dy;
    _dragTravel = Offset.zero;
    // Rightwards only: a left-swipe means nothing here, and treating it as
    // "back" would fire on any sloppy drag.
    if (dx <= 0) return;
    if (dx.abs() <= dy.abs() * _kSwipeRatio) return;
    final velocity = details.velocity.pixelsPerSecond;
    final decisive =
        dx >= _kSwipeDistance ||
        (velocity.dx >= _kSwipeVelocity &&
            velocity.dx.abs() > velocity.dy.abs() * _kSwipeRatio);
    if (!decisive) return;
    unawaited(_leaveToCollection());
  }

  /// Swipe right: back to this collection's entry list.
  ///
  /// The position is flushed **before** navigating — this is a way out of the
  /// reader like any other, and losing the last few seconds of scroll because
  /// the user left by gesture rather than by button would be indefensible.
  ///
  /// Where it lands is the same either way. If the entry list is already the
  /// route underneath, pop onto it; otherwise (opened from Continue Reading,
  /// Activity, a deep link) replace the reader with it. Both leave exactly one
  /// entry-list route on the stack, so repeated in-and-out never piles up.
  Future<void> _leaveToCollection() async {
    final collectionId = _collectionId;
    if (collectionId == null) return;
    await _flush();
    if (!mounted) return;

    final target = '/collection/$collectionId';
    final matches = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.matches;
    final below = matches.length >= 2 ? matches[matches.length - 2] : null;
    if (below != null && below.matchedLocation == target) {
      context.pop();
    } else {
      context.pushReplacement(target);
    }
  }

  /// Chrome starts visible so the way out is never hidden, then gets out of
  /// the way on the first tap. Tapping the page toggles it.
  bool _chromeVisible = true;

  /// Where [_chromeVisible] is published for anything drawn above the router.
  ///
  /// The reader's bars are the app's statement about whether the page is being
  /// read or being managed, so the running-operation indicator follows them
  /// rather than keeping a second opinion.
  late final ReaderChromeVisibility _chromeVisibility;

  /// True once the reader has scrolled far enough from the restored position
  /// that offering a way back is useful rather than confusing.
  bool _showJump = false;

  // --- telling a deliberate tap from a reading gesture ---------------------
  //
  // The chrome is toggled by one thing and one thing only: a tap on the body.
  // The trouble is what Flutter counts as a tap. The scroll view's drag
  // recogniser only claims a gesture once it has cleared the touch slop, and on
  // pointer-up a drag that never claimed anything **rejects itself** — so the
  // tap recogniser is left alone in the arena and wins by default. Every
  // pointer sequence the scroll view declines is therefore promoted to a tap,
  // including ones that plainly were not: a finger put down to stop a fling, a
  // thumb resting on the page, a small back-and-forth shuffle.
  //
  // The policy this implements: *toggle only for a brief, stationary,
  // single-pointer contact that began while the content was at rest.* It is
  // enforced by watching the physical pointer sequence through a [Listener],
  // which observes without joining the arena — the tap, the vertical scroll and
  // the horizontal entry-navigation recognisers all keep exactly the ownership
  // they have today.

  /// The pointer being judged, or null between sequences.
  int? _tapPointer;

  /// When [_tapPointer] went down, and where it was last seen.
  Duration? _tapDownAt;
  Offset? _tapLastPosition;

  /// Total **unsigned** travel of the sequence so far.
  ///
  /// Path length rather than final displacement, because the scroll view's own
  /// accept test accumulates travel *with sign* along its axis: a finger that
  /// wanders 30px down and 28px back nets out to almost nothing, never
  /// convinces the scroll view, and is then swept up as a tap. Net displacement
  /// cannot see that gesture at all; path length is what makes it visible.
  double _tapPath = 0;

  /// The slop this sequence is judged against, read once at pointer-down.
  double _tapSlop = kTouchSlop;

  /// Evidence that this sequence was not a deliberate tap.
  bool _tapDisqualified = false;

  /// The verdict on the physical sequence that has just ended, waiting for the
  /// tap it belongs to.
  ///
  /// Null means *nothing physical is awaiting judgement* — which is exactly the
  /// state an assistive activation arrives in, so those are never judged.
  bool? _pendingTapVerdict;

  /// True only for the remainder of the event dispatch in which a scroll ended.
  ///
  /// Read at pointer-down, that is precisely "this finger just stopped content
  /// that was still moving". It cannot be answered by asking the scroll view
  /// what it is doing: the scroll view sits *below* this screen's [Listener] in
  /// the hit-test path, so it handles the pointer first and has already put
  /// itself on hold by the time the event reaches us — at which point a live
  /// fling and perfectly still content look exactly alike. Landing on still
  /// content ends no scroll and so raises nothing here, while a fling that ends
  /// on its own does so in a frame callback, whose flag is dropped by the
  /// microtask below long before any finger arrives.
  bool _scrollEndedInThisDispatch = false;

  /// The device's own slop where it reports one, the framework's otherwise.
  double get _effectiveTouchSlop =>
      MediaQuery.gestureSettingsOf(context).touchSlop ?? kTouchSlop;

  bool _onScrollEnd(ScrollEndNotification notification) {
    _scrollEndedInThisDispatch = true;
    scheduleMicrotask(() => _scrollEndedInThisDispatch = false);
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    final arrestedMotion = _scrollEndedInThisDispatch;

    if (_tapPointer != null) {
      // A second finger is down. Whatever this is, it is not a single-pointer
      // tap, and the sequence already in flight can no longer become one.
      _tapDisqualified = true;
      return;
    }

    _tapPointer = event.pointer;
    _tapDownAt = event.timeStamp;
    _tapLastPosition = event.position;
    _tapPath = 0;
    _tapSlop = _effectiveTouchSlop;
    _pendingTapVerdict = null;

    // A touch that lands on moving content is there to stop it — that is how
    // you halt a fling at the panel you actually wanted. Toggling the chrome as
    // well would answer a question the reader never asked, and this is the case
    // they meet most often.
    _tapDisqualified = arrestedMotion;
  }

  /// Deliberately does no [setState]: nothing here is drawn, and rebuilding the
  /// reader on every pointer move would cost far more than the decision is
  /// worth.
  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _tapPointer) return;
    final last = _tapLastPosition;
    if (last != null) _tapPath += (event.position - last).distance;
    _tapLastPosition = event.position;
    if (_tapPath > _tapSlop) _tapDisqualified = true;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _tapPointer) return;
    final downAt = _tapDownAt;
    // Held, not tapped. kLongPressTimeout is the framework's own boundary for
    // when a contact has stopped being a tap, so the reader does not invent a
    // second number for the same idea.
    if (downAt != null && event.timeStamp - downAt > kLongPressTimeout) {
      _tapDisqualified = true;
    }
    _endTapSequence(verdict: !_tapDisqualified);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _tapPointer) return;
    // A cancelled sequence produces no tap, so it leaves no verdict behind
    // either.
    _endTapSequence(verdict: null);
  }

  void _endTapSequence({required bool? verdict}) {
    _tapPointer = null;
    _tapDownAt = null;
    _tapLastPosition = null;
    _tapPath = 0;
    _tapDisqualified = false;
    _pendingTapVerdict = verdict;
    // The gesture arena resolves synchronously, later in this same event
    // dispatch, so the tap this verdict belongs to has already read it by the
    // time a microtask runs. Dropping it here is what stops a verdict from
    // outliving its own gesture and blocking a later assistive activation.
    scheduleMicrotask(() => _pendingTapVerdict = null);
  }

  /// The only thing that shows or hides the chrome.
  ///
  /// Taps reach this from two places. The tap recogniser sends one after a
  /// physical sequence this screen has been watching, and that sequence leaves
  /// its verdict in [_pendingTapVerdict]. The semantics layer sends one when
  /// assistive technology activates the body, and there is no pointer sequence
  /// behind it at all — so it carries no verdict, is never judged, and can
  /// never be blocked by evidence left over from someone's thumb.
  void _handleBodyTap() {
    final verdict = _pendingTapVerdict;
    _pendingTapVerdict = null;
    if (verdict == false) return;
    setState(() => _chromeVisible = !_chromeVisible);
    _chromeVisibility.publish(_chromeVisible);
  }

  /// Bring an entry back that has no local files — the same queued save
  /// as anywhere else, so it shows up in Activity like any other run.
  Future<void> _saveAgain(Entry entry) async {
    final result = await ref
        .read(taskQueueProvider)
        .enqueueSave(
          startUrl: entry.sourceUrl,
          entryLimit: 1,
          collectionId: entry.collectionId,
          policy: DuplicatePolicy.replaceAll,
          range: SaveScope.currentPageOnly,
        );
    if (!mounted) return;
    showQueuedConfirmation(context, result);
  }

  /// Re-save this entry to fill in the panels a partial save missed.
  /// The queue owns the work; the Browser is where it becomes visible.
  Future<void> _retryMissing(_ReaderData data) async {
    final entry = data.entry;
    if (entry == null) return;
    final result = await ref
        .read(taskQueueProvider)
        .enqueueSave(
          startUrl: entry.sourceUrl,
          entryLimit: 1,
          collectionId: entry.collectionId,
          policy: DuplicatePolicy.retryPartial,
          range: SaveScope.currentPageOnly,
        );
    if (!mounted) return;
    showQueuedConfirmation(context, result, what: 'missing pages');
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    return Scaffold(
      // Near-black, not `#000000`: a pure-black canvas smears under this
      // screen's continuous vertical scrolling on OLED and maximises the halo
      // around the overlaid chrome (D62). Still dark enough that a panel's own
      // black borders read as part of the artwork.
      backgroundColor: ReaderColors.canvas,
      // The notice sits outside the FutureBuilder: it is posted as the *next*
      // entry starts loading, and rebuilding it with the page would restart
      // its countdown (or flicker it away) on every load state.
      body: Stack(
        children: [
          _body(),
          if (notice != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: kReaderNoticeInset + MediaQuery.paddingOf(context).bottom,
              child: _TransientNotice(
                // A new removal is a new notice, with a full countdown.
                key: ValueKey(notice.id),
                text: notice.text,
                icon: notice.icon,
                duration: kReaderNoticeDuration,
                // Two seconds is not a reachable window with a screen reader:
                // getting to the Undo takes longer than the notice lasts. The
                // same exception the cleanup snack bar already makes — and the
                // notice is still dropped by an entry change, by leaving the
                // app, and by the Dismiss button, so it cannot become permanent.
                persist:
                    MediaQuery.maybeOf(context)?.accessibleNavigation ?? false,
                actionLabel: notice.undo == null ? null : 'Undo',
                onAction: notice.undo == null
                    ? null
                    : () => unawaited(_undoRemoval(notice)),
                onDismissed: _clearNotice,
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<_ReaderData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null || data.unavailableReason != null) {
          final missing = data?.unavailableEntry;
          return _Unavailable(
            message: data?.unavailableReason ?? 'Could not open the entry.',
            filesGone: data?.filesGone ?? false,
            removedByUser: data?.removedByUser ?? false,
            meta: data?.unavailableMeta,
            onSaveAgain: missing == null ? null : () => _saveAgain(missing),
          );
        }
        if (!data.isDocument && data.pages.isEmpty) {
          return const _Unavailable(
            message: 'This entry has no stored images.',
          );
        }

        final manifest = data.manifest!;
        final width = MediaQuery.of(context).size.width;
        final partial = manifest.status == SaveStatus.partial;
        // For an image sequence the partial banner sits *above* panel 1 as a
        // fixed extent the layout does not know about, so it has to be added
        // here. A document measures its own children, banner included, so its
        // leading extent is the top spacer alone — adding the banner twice
        // would offset every restore by its height.
        _leadingExtent = data.isDocument
            ? kReaderTopSpacer
            : kReaderTopSpacer + (partial ? kPartialBannerExtent : 0);
        final controller = data.isDocument
            ? _documentController()
            : _controllerFor(data, width);

        return Stack(
          children: [
            // Watches the physical pointer sequence without joining the gesture
            // arena, so the tap, the scroll view's vertical drag and the
            // horizontal entry-navigation recogniser below keep exactly the
            // ownership they had. It only supplies the evidence that
            // [_handleBodyTap] weighs. Wrapping here covers both reader bodies
            // at once — the policy is written once, not per artifact.
            NotificationListener<ScrollEndNotification>(
              onNotification: _onScrollEnd,
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBodyTap,
                  // Horizontal-only recogniser: it and the list's vertical drag
                  // enter the same arena, so a reading scroll never reaches it
                  // and a deliberate sideways drag never scrolls the page.
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  // Everything above panel 1 lives INSIDE the scroll view, so the
                  // banner scrolls away with the content instead of permanently
                  // eating a band of the page. Its extent is a known constant,
                  // and every offset conversion goes through [_leadingExtent].
                  child: data.isDocument
                      ? DocumentBody(
                          document: data.document!,
                          manifest: manifest,
                          entryDir: data.entryDir!,
                          controller: controller,
                          leadingExtent: kReaderTopSpacer,
                          onLayout: _onDocumentLayout,
                          banner: partial
                              ? _PartialBanner(
                                  stored: manifest.storedAssetCount,
                                  detected: manifest.detectedAssetCount,
                                  reason: manifest.statusReason,
                                  onRetry: () => _retryMissing(data),
                                )
                              : null,
                          trailing: _EndOfEntry(
                            data: data,
                            entryId: _entryId!,
                            siblings: _siblings,
                            onGoTo: _goTo,
                          ),
                        )
                      : ListView.builder(
                          controller: controller,
                          // The lead-in is list PADDING, not a child: padding adds its
                          // extent exactly, while a short first child would skew
                          // ListView's running estimate of total extent and leave the
                          // scrollable's own maxScrollExtent short of the real bottom.
                          padding: const EdgeInsets.only(top: kReaderTopSpacer),
                          // One trailing row for the end-of-entry block, plus the
                          // partial banner when there is one.
                          itemCount: data.pages.length + 1 + (partial ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (partial && index == 0) {
                              return _PartialBanner(
                                stored: manifest.storedAssetCount,
                                detected: manifest.detectedAssetCount,
                                reason: manifest.statusReason,
                                onRetry: () => _retryMissing(data),
                              );
                            }
                            final panel = index - (partial ? 1 : 0);
                            if (panel == data.pages.length) {
                              return _EndOfEntry(
                                data: data,
                                entryId: _entryId!,
                                siblings: _siblings,
                                onGoTo: _goTo,
                              );
                            }
                            return _PanelView(
                              page: data.pages[panel],
                              index: panel + 1,
                              height: _layout?.heightOf(panel),
                            );
                          },
                        ),
                ),
              ),
            ),
            // A jump back to where reading left off, offered only once the
            // reader has actually wandered away from it — the app restores
            // the position on open, so an always-on chip would point at
            // where you already are.
            _JumpToSavedChip(
              visible: _chromeVisible && _showJump,
              fraction: _restoredFraction,
              onTap: () {
                final layout = _geometry;
                if (layout == null) return;
                controller.animateTo(
                  _leadingExtent + layout.offsetForPosition(_restoredPosition),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                );
                setState(() => _showJump = false);
              },
            ),
            _ReaderChrome(
              visible: _chromeVisible,
              data: data,
              entryId: _entryId!,
              completed: _completed,
              position: _livePosition,
              siblings: _siblings,
              onGoTo: _goTo,
              onToggleRead: _toggleRead,
            ),
          ],
        );
      },
    );
  }
}

/// The overlaid reader chrome: a top bar that identifies the entry and owns
/// the read toggle, and a bottom bar with entry movement and position.
///
/// Both fade rather than reflow, so toggling them never moves a single panel —
/// the reader must not jump under the reader's thumb.
///
/// The progress readout listens to the live position notifier, so it moves
/// while the user scrolls (M12) — only the bar and the percentage rebuild per
/// tick, never the panel list and never the entry controls beside them.
class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.visible,
    required this.data,
    required this.entryId,
    required this.completed,
    required this.position,
    required this.siblings,
    required this.onGoTo,
    required this.onToggleRead,
  });

  final bool visible;
  final _ReaderData data;
  final String entryId;
  final bool completed;
  final ValueListenable<ReadingPosition> position;

  /// The live neighbour list. Listened to rather than captured, so a removal
  /// that happens while this screen is up disables the control it invalidated.
  final ValueListenable<List<Entry>> siblings;
  final Future<void> Function(Entry) onGoTo;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final entry = data.entry;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(6, insets.top + 6, 6, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ReaderColors.chromeStrong,
                      ReaderColors.chromeSoft,
                      ReaderColors.chromeClear,
                    ],
                    stops: [0, 0.7, 1],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back, size: 24),
                      color: ReaderColors.ink,
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry?.sourceMarker ?? entry?.title ?? 'Reader',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'IBM Plex Mono',
                              fontSize: 14,
                              color: ReaderColors.ink,
                            ),
                          ),
                          Text(
                            entry?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ReaderColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ReadPill(completed: completed, onPressed: onToggleRead),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(10, 8, 10, insets.bottom + 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ReaderColors.chromeClear,
                      ReaderColors.chromeSoft,
                      ReaderColors.chromeStrong,
                    ],
                    stops: [0, 0.3, 1],
                  ),
                ),
                // Bar across the full width, then one row: where you can go
                // back to, how far through you are, where you can go next.
                // The two ends are entry navigation and say so; the middle is
                // the only thing that is not a button.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: ValueListenableBuilder<ReadingPosition>(
                        valueListenable: position,
                        builder: (context, live, _) => LinearProgressIndicator(
                          value: live.fraction.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: ReaderColors.track,
                          color: ReaderColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<List<Entry>>(
                      valueListenable: siblings,
                      builder: (context, ordered, _) {
                        final index = ordered.indexWhere(
                          (c) => c.id == entryId,
                        );
                        final previous = index > 0 ? ordered[index - 1] : null;
                        final next = (index >= 0 && index + 1 < ordered.length)
                            ? ordered[index + 1]
                            : null;
                        // Equal flex on both sides is what actually centres the
                        // percentage: whatever the two labels turn out to be,
                        // the middle keeps the same place on screen, so the one
                        // element that changes every frame is the one that
                        // never moves.
                        return Row(
                          children: [
                            Expanded(
                              child: _EntryStepButton(
                                step: _Step.previous,
                                target: previous,
                                onGoTo: onGoTo,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: _ReadingPercent(
                                position: position,
                                completed: completed,
                              ),
                            ),
                            Expanded(
                              child: _EntryStepButton(
                                step: _Step.next,
                                target: next,
                                onGoTo: onGoTo,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _readerMeta = TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontSize: 10.5,
  color: ReaderColors.inkFaint,
);

/// Which way an [_EntryStepButton] moves.
enum _Step { previous, next }

/// How far through the entry the reader is, and nothing else.
///
/// Its own widget because it is the only part of the bottom bar that changes
/// while scrolling: keeping it separate means a scroll tick rebuilds one Text
/// and leaves the two entry controls beside it alone.
class _ReadingPercent extends StatelessWidget {
  const _ReadingPercent({required this.position, required this.completed});

  final ValueListenable<ReadingPosition> position;
  final bool completed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReadingPosition>(
    valueListenable: position,
    builder: (context, live, _) {
      final pct = (live.fraction * 100).clamp(0, 100).round();
      return Text(
        completed ? 'Completed' : '$pct%',
        maxLines: 1,
        // Larger, brighter and heavier than the labels on either side, so the
        // middle of the bar reads as a *readout* rather than a third button.
        style: const TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ReaderColors.ink,
        ),
      );
    },
  );
}

/// One end of the bottom bar: the control that moves to the previous or the
/// next entry.
///
/// It says "entry" in words. A bare arrow beside a panel counter is read as a
/// step *within* the page — which is what the old pair of skip glyphs was, and
/// why moving between entries was guesswork. The direction is the chevron, the
/// unit is the label, and the destination is named underneath it.
///
/// [target] being null **is** the disabled state, and it comes from the live
/// neighbour list, which only ever contains entries [readerCanOpen] accepts. So
/// a control is lit exactly when tapping it can succeed; there is no separate
/// enabled flag to fall out of step with the entry it points at.
class _EntryStepButton extends StatelessWidget {
  const _EntryStepButton({
    required this.step,
    required this.target,
    required this.onGoTo,
  });

  final _Step step;

  /// The entry this control opens, or null when there is no openable one in
  /// that direction — the end of the collection, a standalone entry, or a
  /// neighbour whose downloads have been removed.
  final Entry? target;
  final Future<void> Function(Entry) onGoTo;

  /// Comfortable one-handed target, kept at the platform minimum even though
  /// the label only needs about 26 of it.
  static const double _minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final entry = target;
    final enabled = entry != null;
    final forward = step == _Step.next;
    final ink = enabled ? ReaderColors.ink : ReaderColors.inkDisabled;
    final title = forward ? 'Next entry' : 'Previous entry';
    final name = entry == null
        ? null
        : (entry.sourceMarker?.trim().isNotEmpty ?? false)
        ? entry.sourceMarker!.trim()
        : entry.title;

    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: forward
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: forward ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        if (name != null) ...[
          const SizedBox(height: 1),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: forward ? TextAlign.right : TextAlign.left,
            style: _readerMeta,
          ),
        ],
      ],
    );

    final chevron = Icon(
      forward ? Icons.chevron_right : Icons.chevron_left,
      size: 22,
      color: ink,
    );

    return Tooltip(
      // Unchanged wording: the tooltip is the long form of the same action,
      // and it is what assistive navigation and the tests reach the control by.
      message: forward ? 'Next saved entry' : 'Previous saved entry',
      child: Semantics(
        button: true,
        enabled: enabled,
        // One spoken phrase instead of three fragments, and it says outright
        // when there is nowhere to go.
        label: name == null ? '$title, unavailable' : '$title, $name',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onGoTo(entry) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisAlignment: forward
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (!forward) chevron,
                    Flexible(child: label),
                    if (forward) chevron,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadPill extends StatelessWidget {
  const _ReadPill({required this.completed, required this.onPressed});

  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: completed ? ReaderColors.pillActive : ReaderColors.pill,
    borderRadius: BorderRadius.circular(999),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              completed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17,
              color: completed ? ReaderColors.accent : ReaderColors.ink,
            ),
            const SizedBox(width: 6),
            Text(
              completed ? 'Read' : 'Mark read',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: completed ? ReaderColors.accent : ReaderColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// What happens after the last panel: the entry is over, and the next one is
/// one tap away. "Continue" skips ahead to the next thing actually unread.
class _EndOfEntry extends StatelessWidget {
  const _EndOfEntry({
    required this.data,
    required this.entryId,
    required this.siblings,
    required this.onGoTo,
  });

  final _ReaderData data;
  final String entryId;
  final ValueListenable<List<Entry>> siblings;
  final Future<void> Function(Entry) onGoTo;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Entry>>(
    valueListenable: siblings,
    builder: (context, ordered, _) => _build(context, ordered),
  );

  Widget _build(BuildContext context, List<Entry> siblings) {
    final index = siblings.indexWhere((c) => c.id == entryId);
    final next = (index >= 0 && index + 1 < siblings.length)
        ? siblings[index + 1]
        : null;
    final nextUnread = siblings
        .skip(index < 0 ? 0 : index + 1)
        .where((c) => c.readStatus != ReadStatus.completed.name)
        .firstOrNull;
    final target = nextUnread ?? next;
    final label = data.entry?.sourceMarker ?? data.entry?.title ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 110),
      child: Column(
        children: [
          Text(
            'END OF ${label.toUpperCase()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontSize: 11,
              letterSpacing: 0.66,
              color: ReaderColors.inkFaint,
            ),
          ),
          if (target != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => onGoTo(target),
              style: OutlinedButton.styleFrom(
                backgroundColor: ReaderColors.buttonSurface,
                foregroundColor: ReaderColors.buttonInk,
                side: const BorderSide(color: ReaderColors.buttonBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
              ),
              child: Text(
                'Next entry · ${target.sourceMarker ?? target.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelView extends StatelessWidget {
  const _PanelView({required this.page, required this.index, this.height});

  final _ReaderPage page;
  final int index;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (!page.exists) {
      return Container(
        height: height ?? 160,
        color: ReaderColors.brokenPanel,
        alignment: Alignment.center,
        child: Text(
          'Image $index is missing from local storage',
          style: const TextStyle(
            color: ReaderColors.brokenPanelInk,
            fontSize: 12,
          ),
        ),
      );
    }

    // Decode at display width, not full resolution: a 60-panel entry would
    // otherwise be hundreds of MB of bitmaps. And never *wider* than the file
    // actually is — long-strip art is commonly narrower than the screen, and
    // asking for more than it has upscales at decode time, which costs
    // (display/natural)² memory for no extra detail (see decode_budget.dart).
    final media = MediaQuery.of(context);
    final decodeWidth = decodeWidthWithinBudget(
      width:
          decodeWidthFor(
            displayWidth: media.size.width,
            devicePixelRatio: media.devicePixelRatio,
            naturalWidth: page.width,
          ) ??
          1,
      naturalWidth: page.width,
      naturalHeight: page.height,
    );

    final image = Image.file(
      page.file,
      width: double.infinity,
      height: height,
      // fitWidth + a height derived from the file's own aspect ratio paints
      // the panel exactly, with no stretch in either axis. Never BoxFit.fill:
      // if the recorded ratio is ever wrong, fill distorts, fitWidth merely
      // crops — and topCenter makes that failure show the top of the panel
      // rather than an arbitrary middle slice.
      fit: BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      cacheWidth: decodeWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, _) => Container(
        height: height ?? 160,
        color: ReaderColors.brokenPanel,
        alignment: Alignment.center,
        child: Text(
          'Image $index could not be decoded',
          style: const TextStyle(
            color: ReaderColors.brokenPanelInk,
            fontSize: 12,
          ),
        ),
      ),
    );

    // A fixed box keeps the list's geometry identical to the layout the saved
    // offset was computed against, so restoring cannot drift.
    return height == null ? image : SizedBox(height: height, child: image);
  }
}

/// The partial-save banner. It scrolls away with the content rather than
/// occupying a permanent band, and its height is a fixed constant because the
/// restore offset is computed from it before any layout happens.
class _PartialBanner extends StatelessWidget {
  const _PartialBanner({
    required this.stored,
    required this.detected,
    required this.reason,
    required this.onRetry,
  });

  final int stored;
  final int detected;
  final String? reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final missing = detected - stored;
    return SizedBox(
      height: kPartialBannerExtent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: ReaderColors.warnSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ReaderColors.warnBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.arrow_circle_down,
              size: 19,
              color: ReaderColors.warn,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Partial save — $stored of $detected images',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ReaderColors.warnInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$missing page${missing == 1 ? ' is' : 's are'} '
                    'missing${reason == null ? '' : ' ($reason)'}. '
                    'You can read the rest now.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: ReaderColors.warnInkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: ReaderColors.warn,
                foregroundColor: ReaderColors.onWarn,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text('Retry $missing'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the reader currently has to say, for as long as its notice lasts.
class _ReaderNotice {
  const _ReaderNotice({
    required this.id,
    required this.text,
    required this.icon,
    this.undo,
  });

  final int id;
  final String text;
  final IconData icon;

  /// Present only while the removal can genuinely be taken back.
  final Future<void> Function()? undo;
}

/// A short-lived notice that owns its own timeout and shows it draining.
///
/// Deliberately **not** a `SnackBar`: the messenger's queue lives above the
/// router, outlives this screen and survives being backgrounded, so a snack bar
/// posted here can resurface on a later page or after a resume. This lives and
/// dies inside the reader — when the owner drops it, it is gone, and there is
/// nowhere for it to come back from.
///
/// It owns exactly one controller and no timers, and the controller goes with
/// the widget.
///
/// It is drawn from the same tokens as the app's snack bars — [AppPalette]'s
/// toast surface, ink and accent, the snack bar theme's 14px radius and 13px
/// body — because it is the same kind of object. The only thing it does not
/// share is the messenger.
class _TransientNotice extends StatefulWidget {
  const _TransientNotice({
    super.key,
    required this.text,
    required this.icon,
    required this.duration,
    required this.onDismissed,
    this.persist = false,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Duration duration;

  /// Wait for the Dismiss button instead of timing out. Set only for assistive
  /// navigation, where [duration] is shorter than reaching the action takes.
  final bool persist;

  /// Called once, when the notice is finished with itself — the timeout ran
  /// out, or the user closed it. The owner drops it from the tree.
  final VoidCallback onDismissed;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_TransientNotice> createState() => _TransientNoticeState();
}

class _TransientNoticeState extends State<_TransientNotice>
    with SingleTickerProviderStateMixin {
  /// How long the notice takes to fade in, and again to fade out.
  ///
  /// A fixed duration rather than a fraction of [widget.duration]: the fade is
  /// a property of the animation, not of how long the message is worth reading,
  /// and a percentage silently re-times itself whenever the duration moves.
  static const _fade = Duration(milliseconds: 140);

  /// Both interactive boxes, at the size the rest of the app gives a tappable
  /// glyph (`kHeaderActionSize`). Not that constant itself: it is scoped to the
  /// screen-header row and must stay free to move with it.
  static const _actionSize = 40.0;

  late final AnimationController _timeout;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timeout = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _close();
      });
    // Left at rest when persisting, so nothing is counting down and the
    // hairline has nothing to show.
    if (!widget.persist) _timeout.forward();
  }

  @override
  void dispose() {
    _timeout.dispose();
    super.dispose();
  }

  /// Idempotent: the timeout and the close button race by design, and the
  /// loser must not report a second dismissal.
  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onDismissed();
  }

  void _act() {
    if (_closed) return;
    _closed = true;
    widget.onAction?.call();
  }

  /// Fades in over the first [_fade] and out over the last, so the notice
  /// neither appears nor vanishes as a hard cut. Capped at a third of the
  /// timeout each way, so a very short duration still has a moment at full
  /// opacity rather than being one continuous fade.
  double _opacityAt(double t) {
    final ms = widget.duration.inMilliseconds;
    if (ms <= 0) return 1;
    final fade = (_fade.inMilliseconds / ms).clamp(0.001, 1 / 3);
    final value = t < fade ? t / fade : (t > 1 - fade ? (1 - t) / fade : 1.0);
    return value.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // The reader is a permanently dark surface whatever the app appearance is,
    // so the notice reads from the dark palette rather than the ambient one.
    const palette = AppPalette.dark;

    // The app's own transient-surface radius (`snackBarTheme`), so the reader's
    // notice and every snack bar elsewhere read as the same object on two
    // screens.
    final radius = BorderRadius.circular(14);

    return AnimatedBuilder(
      animation: _timeout,
      builder: (context, _) {
        final t = _timeout.value;
        return Opacity(
          opacity: widget.persist ? 1 : _opacityAt(t),
          child: Material(
            color: palette.toastSurface,
            borderRadius: radius,
            elevation: 6,
            shadowColor: palette.shadow,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 19, color: palette.toastAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.text,
                          // One line, always: the copy is two words, and a
                          // notice that changes height between messages reads
                          // as two different components.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.toastInk,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: _act,
                          // Only the colour is overridden; the label's size and
                          // weight are the app's text-button type. The shorter
                          // the notice, the more the action has to be hit first
                          // time.
                          style: TextButton.styleFrom(
                            foregroundColor: palette.toastAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, _actionSize),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(widget.actionLabel!),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: _close,
                        icon: const Icon(Icons.close, size: 18),
                        color: palette.inkFaint,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: _actionSize,
                          height: _actionSize,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                // The timeout, made visible: a hairline that empties as the
                // notice runs out. Painted directly rather than with
                // LinearProgressIndicator, whose Material 3 track and stop dot
                // read as progress towards something. Absent when persisting,
                // where there is no countdown to draw.
                if (!widget.persist)
                  SizedBox(
                    height: 2,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (1 - t).clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(color: palette.toastAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Continue · N%" — the way back to where reading left off.
class _JumpToSavedChip extends StatelessWidget {
  const _JumpToSavedChip({
    required this.visible,
    required this.fraction,
    required this.onTap,
  });

  final bool visible;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      right: 14,
      bottom: 104,
      child: Material(
        color: ReaderColors.chipSurface,
        borderRadius: BorderRadius.circular(999),
        elevation: 6,
        shadowColor: Colors.black,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.south, size: 18, color: ReaderColors.chipInk),
                const SizedBox(width: 7),
                Text(
                  'Continue · ${(fraction * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ReaderColors.chipInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The entry cannot be shown. When its files are gone this is the state the
/// user actually hits — the row is still in the library, the position is still
/// saved, and the only thing missing is the bytes.
class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.message,
    this.filesGone = false,
    this.removedByUser = false,
    this.meta,
    this.onSaveAgain,
  });

  final String message;
  final bool filesGone;

  /// The user removed the files deliberately: cloud glyph and "Not available
  /// offline", never the alarming folder_off/"files are gone" wording.
  final bool removedByUser;

  /// One mono line of fact under the explanation ("removed 3 days ago",
  /// "0 of 41 files present").
  final String? meta;

  /// Offered when the entry can be brought back.
  final VoidCallback? onSaveAgain;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            removedByUser
                ? Icons.cloud
                : (filesGone ? Icons.folder_off : Icons.cloud_off),
            size: 34,
            color: ReaderColors.inkFaint,
          ),
          const SizedBox(height: 10),
          if (filesGone)
            Text(
              removedByUser
                  ? 'Not available offline'
                  : 'The files for this entry are gone',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ReaderColors.ink,
              ),
            ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              removedByUser
                  ? message
                  : filesGone
                  ? 'The entry is still listed, but its images are not on '
                        'the device any more. Your reading position is kept — '
                        'save it again to read it.'
                  : message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: ReaderColors.inkMuted,
              ),
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 10),
            Text(
              meta!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 11,
                color: ReaderColors.inkFaint,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Builder(
            builder: (context) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSaveAgain != null) ...[
                  FilledButton(
                    onPressed: onSaveAgain,
                    style: FilledButton.styleFrom(
                      backgroundColor: ReaderColors.chipSurface,
                      foregroundColor: ReaderColors.chipInk,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Save again'),
                  ),
                  const SizedBox(width: 9),
                ],
                OutlinedButton(
                  onPressed: () => context.pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ReaderColors.outlineInk,
                    side: const BorderSide(color: ReaderColors.outlineBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Back to collection'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReaderPage {
  const _ReaderPage({
    required this.file,
    required this.exists,
    this.width,
    this.height,
  });

  final File file;
  final bool exists;
  final int? width;
  final int? height;
}

class _ReaderData {
  const _ReaderData({
    required this.entry,
    required this.manifest,
    required this.pages,
    this.document,
    this.entryDir,
  }) : unavailableReason = null,
       filesGone = false,
       removedByUser = false,
       unavailableMeta = null,
       unavailableEntry = null;

  const _ReaderData.unavailable(
    this.unavailableReason, {
    this.filesGone = false,
    this.removedByUser = false,
    this.unavailableMeta,
    this.unavailableEntry,
  }) : entry = null,
       manifest = null,
       pages = const [],
       document = null,
       entryDir = null;

  final Entry? entry;
  final EntryManifest? manifest;

  /// Image pages. Empty for a structured document.
  final List<_ReaderPage> pages;

  /// The saved text. Null for an image sequence.
  final StructuredDocument? document;

  /// Where this entry's files live, for resolving a document's inline images.
  final Directory? entryDir;

  /// Which reader path this entry takes. Derived from what was loaded, which
  /// came from the manifest's artifact discriminator — never from counting
  /// files or reading extensions.
  bool get isDocument => document != null;

  /// The row is intact but its images are not on the device any more.
  final bool filesGone;

  /// …because the user removed them (not because the system lost them).
  final bool removedByUser;

  /// One line of fact for the unavailable state.
  final String? unavailableMeta;

  /// The row behind an unavailable entry, so it can be saved again.
  final Entry? unavailableEntry;

  final String? unavailableReason;
}

/// Re-exported so the reader route can resolve files without importing
/// `file_store.dart` in the router.
typedef ReaderFileStore = FileStore;
