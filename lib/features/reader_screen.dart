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

import '../library_ui/providers.dart'
    show libraryUiServicesProvider, primaryLocation;
import '../providers.dart';
import '../reading/reading_position.dart';
import '../reading_v2/offline_read.dart';
import '../storage/document.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import '../reading/decode_budget.dart';
import '../ui/palette.dart';
import 'document_reader.dart';

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

/// Vertical image reader over **local files only**.
///
/// No remote-URL fallback exists anywhere in this screen: if a file is missing
/// the reader says so. Falling back to the source would make "offline" a lie
/// that only surfaces once the network is gone.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.entryId,
    required this.offline,
    this.collectionId,
  });

  final String entryId;

  /// Where the swipe-back lands, when the caller knows.
  ///
  /// Supplied by the route rather than looked up here: a Collection is a
  /// library fact, this screen is handed a package, and a reader that reached
  /// for the library to answer a navigation question would be a library
  /// dependency smuggled in through the back door. Null — a standalone Entry,
  /// or a caller that has no route to go back to — leaves the gesture with
  /// nowhere to land, and it does nothing.
  final String? collectionId;

  /// The Entry's package, resolved by the caller, and the session its reading
  /// goes back through (`lib/reading_v2/offline_read.dart`).
  ///
  /// **Required.** This screen loads nothing itself: the package is resolved
  /// from an OfflineCopy before the route builds, the open is recorded through
  /// the session, and the anchor comes from the copy. There is no library row
  /// behind any of it.
  ///
  /// **Position restore is unchanged.** The image reader opens *at* its
  /// position, because panel geometry comes from the manifest; the document
  /// reader restores *to* its position on the first measurement, because a
  /// paragraph has no offset until it has been laid out. The anchor simply
  /// arrives from the copy instead of from a column.
  final OfflineReaderData offline;

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

  /// Whether [_measureRestoredPosition] has run. Once per open: the restored
  /// position is where the reader *started*, and a second measurement after
  /// they have scrolled would quietly redefine it as wherever they are now.
  bool _restoredMeasured = false;

  Timer? _saveTimer;
  DateTime? _pastThresholdSince;
  bool _completed = false;
  bool _restored = false;
  String? _entryId;

  static const _policy = kDefaultCompletionPolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryId = widget.entryId;
    _chromeVisibility = ref.read(readerChromeVisibleProvider);
    _future = _load(widget.offline);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    // Fire-and-forget: dispose cannot await, but the write is a single row.
    unawaited(_flush());
    _scrollController?.dispose();
    _livePosition.dispose();
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
  }

  // --- loading -------------------------------------------------------------

  /// The package was resolved from an OfflineCopy before this screen was
  /// built, so there is nothing to look up and nothing to re-derive.
  ///
  /// What still happens is what an *open* means: the access is recorded
  /// through the session, and the reader starts from the copy's own anchor.
  /// There is deliberately no neighbour list: neighbours are a fact about a
  /// Collection's entries, which is a question for a library and not for a
  /// package on this device, so no entry-navigation control is offered and
  /// none can be taken.
  Future<_ReaderData> _load(OfflineReaderData offline) async {
    switch (offline.read) {
      case OfflineReadUnavailable(:final refusal):
        return _ReaderData.unavailable(
          _refusalMessage(refusal),
          // Only a copy whose bytes have vanished is "gone". An Entry this
          // device never held a copy of has lost nothing — it is simply not
          // downloaded here, which is an ordinary state of a first-class
          // library item and not a failure of one.
          filesGone: refusal == OfflineReadRefusal.filesMissing,
        );
      case OfflineImageRead(:final manifest, :final pages, :final restored):
        _completed = await offline.recordOpen();
        _position = restored;
        return _ReaderData(
          manifest: manifest,
          pages: [
            for (final page in pages)
              _ReaderPage(
                file: page.file,
                exists: page.exists,
                width: page.width,
                height: page.height,
              ),
          ],
        );
      case OfflineDocumentRead(
        :final manifest,
        :final entryDir,
        :final document,
        :final restored,
      ):
        _completed = await offline.recordOpen();
        _position = restored;
        return _ReaderData(
          manifest: manifest,
          pages: const [],
          document: document,
          entryDir: entryDir,
        );
    }
  }

  /// Why the copy cannot be opened, in the reader's own words. Each is a
  /// state, not a failure: nothing is demoted and the Entry stays listed with
  /// its reading history.
  static String _refusalMessage(
    OfflineReadRefusal refusal,
  ) => switch (refusal) {
    OfflineReadRefusal.noCopy =>
      'This entry is not downloaded on this device. It is still in your '
          'library with your reading history — save it again to read it here.',
    OfflineReadRefusal.filesMissing =>
      'The local files for this entry are gone. The entry is still listed, '
          'but it is not available offline.',
    OfflineReadRefusal.manifestUnreadable =>
      'The entry package is unreadable (missing manifest).',
    OfflineReadRefusal.unknownArtifact =>
      'This entry was saved in a format this version of the app cannot open. '
          'Updating the app should fix it; the files are untouched.',
    OfflineReadRefusal.documentUnreadable =>
      'The saved text for this entry is unreadable.',
  };

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
    _measureRestoredPosition();
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
      _measureRestoredPosition();
    });
  }

  /// Measure how far through the entry the restored position actually is.
  ///
  /// The **anchor** is what restore uses, and it arrives on the OfflineCopy —
  /// an index into these bytes. The **fraction** is a different thing: it is a
  /// fact about this rendering, at this width, and there is deliberately no
  /// stored one to read (`lib/reading_v2/offline_read.dart`). So it is
  /// measured, on the frame after the reader has opened — the first moment the
  /// geometry and the viewport both exist and the scroll view is still exactly
  /// where it was put.
  ///
  /// It feeds the jump chip and nothing else. The chip offers a way back to
  /// where reading left off once the reader has wandered away from it, and
  /// "how far away" is a comparison of two fractions; with no restored
  /// fraction to compare against the chip could never appear.
  void _measureRestoredPosition() {
    if (_restoredMeasured) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      final layout = _geometry;
      if (!mounted ||
          _restoredMeasured ||
          controller == null ||
          layout == null ||
          !controller.hasClients) {
        return;
      }
      _restoredMeasured = true;
      final panelOffset = (controller.offset - _leadingExtent).clamp(
        0.0,
        double.infinity,
      );
      final measured = layout.positionForOffset(
        panelOffset,
        viewportHeight: controller.position.viewportDimension,
      );
      if (measured.fraction <= 0) return;
      setState(() => _restoredPosition = measured);
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
      await widget.offline.saveProgress(_position, completed: _completed);
    } catch (_) {
      // The dispose-time flush is fire-and-forget; if the database is
      // already shutting down there is nowhere left to save to, and an
      // unhandled zone error would be the only result.
    }
  }

  // --- actions -------------------------------------------------------------

  Future<void> _toggleRead() async {
    if (_entryId == null) return;
    // A debounced save queued before the tap would land after it and write
    // the status straight back. The user's explicit choice is the newer
    // fact, so the pending write is dropped rather than allowed to race.
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_completed) {
      await widget.offline.markUnread();
      _completed = false;
      _pastThresholdSince = null;
    } else {
      await widget.offline.markRead();
      _completed = true;
    }
    if (mounted) setState(() {});
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
    final collectionId = widget.collectionId;
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

  /// Re-download this entry to fill in the panels a partial save missed.
  ///
  /// The queue owns the work and the Browser is where it becomes visible, so
  /// this only asks: a row is written and **nothing starts** until the user
  /// presses Start. Offering a retry that did not retry would be the same
  /// failure as offering a stop that does not stop.
  Future<void> _retryMissing(_ReaderData data) async {
    final id = _entryId;
    if (id == null) return;
    final services = ref.read(libraryUiServicesProvider);
    final location = await primaryLocation(services.db, id);
    if (!mounted) return;
    if (location == null) {
      _say('This entry has no address to download from.');
      return;
    }
    final result = await services.queue.enqueue(
      entryId: id,
      locationId: location.id,
      locationUrl: location.url,
    );
    if (!mounted) return;
    _say(
      result.refusedReason ??
          (result.alreadyQueued
              ? 'Already in the download queue, waiting for Start.'
              : 'Added to the download queue. Nothing starts until you '
                    'start it.'),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Near-black, not `#000000`: a pure-black canvas smears under this
      // screen's continuous vertical scrolling on OLED and maximises the halo
      // around the overlaid chrome (D62). Still dark enough that a panel's own
      // black borders read as part of the artwork.
      backgroundColor: ReaderColors.canvas,
      body: _body(),
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
          return _Unavailable(
            message: data?.unavailableReason ?? 'Could not open the entry.',
            filesGone: data?.filesGone ?? false,
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
                          trailing: _EndOfEntry(data: data),
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
                              return _EndOfEntry(data: data);
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
              completed: _completed,
              position: _livePosition,
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
    required this.completed,
    required this.position,
    required this.onToggleRead,
  });

  final bool visible;
  final _ReaderData data;
  final bool completed;
  final ValueListenable<ReadingPosition> position;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);

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
                            // The manifest names the package, and it carries
                            // the same two facts in the same order the V1 row
                            // did.
                            data.manifest?.sourceMarker ??
                                data.manifest?.title ??
                                'Reader',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'IBM Plex Mono',
                              fontSize: 14,
                              color: ReaderColors.ink,
                            ),
                          ),
                          Text(
                            data.manifest?.title ?? '',
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
                    // The percentage, centred and alone. The two entry
                    // controls that used to flank it were the read side of a
                    // neighbour list, and neighbours are a fact about a
                    // Collection rather than about a package on this device.
                    _ReadingPercent(position: position, completed: completed),
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
  const _EndOfEntry({required this.data});

  final _ReaderData data;

  @override
  Widget build(BuildContext context) {
    final label = data.manifest?.sourceMarker ?? data.manifest?.title ?? '';

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
  const _Unavailable({required this.message, this.filesGone = false});

  final String message;

  /// The copy row said where the bytes are and they are not there. Every other
  /// refusal — no copy on this device, an unreadable package, a format a newer
  /// build wrote — is an ordinary state of a first-class library item, so it
  /// gets the message and none of the alarm.
  final bool filesGone;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filesGone ? Icons.folder_off : Icons.cloud_off,
            size: 34,
            color: ReaderColors.inkFaint,
          ),
          const SizedBox(height: 10),
          if (filesGone)
            Text(
              'The files for this entry are gone',
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
              filesGone
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
          const SizedBox(height: 16),
          Builder(
            builder: (context) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
    required this.manifest,
    required this.pages,
    this.document,
    this.entryDir,
  }) : unavailableReason = null,
       filesGone = false;

  const _ReaderData.unavailable(
    this.unavailableReason, {
    this.filesGone = false,
  }) : manifest = null,
       pages = const [],
       document = null,
       entryDir = null;

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

  /// The Entry is intact but the bytes this copy names are not on the device
  /// any more.
  final bool filesGone;

  final String? unavailableReason;
}

/// Re-exported so the reader route can resolve files without importing
/// `file_store.dart` in the router.
typedef ReaderFileStore = FileStore;
