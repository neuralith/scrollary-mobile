/// Pull up from the bottom of an Entry to ask for the next one.
///
/// The one-handed twin of pull-to-refresh, at the other edge. It exists because
/// the *Next entry* control lives in chrome the reader has usually tapped away,
/// and reaching a top-of-screen control at the end of a long scroll is the one
/// moment a reader is least able to.
///
/// ## What it is watching, and why that is the safe thing to watch
///
/// Scroll notifications, exactly as `RefreshIndicator` does — never a raw
/// gesture recogniser of its own. A recogniser would have to enter the arena
/// beside the scroll view's vertical drag and the reader's horizontal
/// entry-navigation drag, and reading is a vertical gesture: the arena is the
/// last place this should be arguing. Watching notifications instead means the
/// scroll view keeps exactly the ownership it has today, and this hears about
/// the *result* — which is all it needs, because the only thing it is
/// interested in is motion the scroll view could not absorb.
///
/// That is also what makes the safety properties true rather than tuned:
///
///  * **Only at the true bottom.** Overscroll at the end is the only thing
///    that starts a pull. Mid-entry scrolling produces none, so there is
///    nothing to accumulate.
///  * **A fling into the bottom is not a pull.** A ballistic overscroll
///    carries no `dragDetails`; only motion a finger is driving is counted, so
///    arriving at the end at speed reveals nothing and advances nothing.
///  * **Release decides, not crossing.** Passing the threshold arms the
///    gesture and says so; the request is made when the finger lifts.
///  * **Reversing cancels.** Dragging back below the threshold — or off the
///    edge altogether — disarms it, and releasing then does nothing at all.
///
/// ## What it does when it fires
///
/// Nothing of its own. It calls back, and the callback is the reader's **one**
/// next-Entry request — the same one the *Next entry* control makes. This
/// widget has no opinion about whether a next Entry exists, is downloaded, or
/// needs its Source: it is a way of asking, and the answer is resolved in one
/// place (`lib/reading_v2/next_entry.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../ui/palette.dart';

/// How far past the end the reader must be dragged before releasing means
/// *next entry*.
///
/// Deliberately well past a touch slop and past any accidental thumb travel at
/// the end of a scroll: the whole point of a threshold here is that reaching it
/// cannot be something the reader did without meaning to.
const double kPullUpThreshold = 88;

/// Where the affordance stops growing. Past the threshold the pull is already
/// decided, so further travel is rubber rather than progress.
const double kPullUpMaxExtent = 132;

/// How far the reader has pulled past the end, in logical pixels.
///
/// Its own object so the gesture and the thing that draws it can sit in
/// different parts of the reader's stack: the affordance has to be painted
/// **above** the reader chrome, and the gesture has to wrap the scroll view.
class PullUpController extends ValueNotifier<double> {
  PullUpController() : super(0);

  bool get armed => value >= kPullUpThreshold;

  /// 0 → 1 as the pull approaches the threshold, then held at 1.
  double get progress => (value / kPullUpThreshold).clamp(0.0, 1.0);
}

/// Watches [child]'s scrolling for a deliberate pull past the end.
class PullUpForNext extends StatefulWidget {
  const PullUpForNext({
    super.key,
    required this.controller,
    required this.onRequest,
    required this.child,
  });

  final PullUpController controller;

  /// Ask for the next Entry. Null leaves the gesture inert — an Entry with no
  /// reading order has nothing to ask for.
  final Future<void> Function()? onRequest;

  final Widget child;

  @override
  State<PullUpForNext> createState() => _PullUpForNextState();
}

class _PullUpForNextState extends State<PullUpForNext> {
  /// True while a finger is driving the scroll. What separates "dragged back
  /// below the threshold" from "let go past it and the view is settling".
  bool _dragging = false;

  /// The threshold has been announced for this pull. Cleared when the pull
  /// falls back below it, so dragging over the line twice buzzes twice.
  bool _buzzed = false;

  /// A request is in flight. A second one cannot be started on top of it — the
  /// first may be a sheet, or a route replacing this reader.
  bool _running = false;

  bool get _live => widget.onRequest != null && !_running;

  void _cancel() {
    _dragging = false;
    _buzzed = false;
    widget.controller.value = 0;
  }

  /// Take the pull to [extent], announcing the threshold as it is crossed.
  void _pullTo(double extent) {
    final next = extent.clamp(0.0, kPullUpMaxExtent);
    if (next <= 0) {
      _cancel();
      return;
    }
    widget.controller.value = next;
    if (next >= kPullUpThreshold) {
      if (!_buzzed) {
        _buzzed = true;
        // The one moment the answer changes, so the one moment worth a tap on
        // the hand — and light, because this is a hint that releasing will now
        // do something, not an alert.
        unawaited(HapticFeedback.lightImpact());
      }
    } else {
      _buzzed = false;
    }
  }

  /// The finger has lifted. Past the threshold this is the request; below it,
  /// nothing happened.
  void _release() {
    if (!_dragging) return;
    _dragging = false;
    final pulled = widget.controller.value;
    if (pulled < kPullUpThreshold || !_live) {
      _cancel();
      return;
    }
    unawaited(_fire());
  }

  Future<void> _fire() async {
    final request = widget.onRequest;
    if (request == null) return;
    _running = true;
    // Held at the threshold while the request is being answered, so the
    // affordance does not snap away under a sheet that is still opening.
    widget.controller.value = kPullUpThreshold;
    try {
      await request();
    } finally {
      _running = false;
      if (mounted) _cancel();
    }
  }

  bool _onNotification(ScrollNotification notification) {
    // Depth 0 only: a nested scroll view inside the page is its own business,
    // and the axis check keeps a horizontal carousel out of this entirely.
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_live) {
      if (widget.controller.value != 0) _cancel();
      return false;
    }

    final metrics = notification.metrics;
    switch (notification) {
      case ScrollStartNotification(:final dragDetails):
        // A new finger starts a new pull; a ballistic start is the tail of the
        // one that just ended and must not clear its verdict.
        if (dragDetails != null) _cancel();

      case OverscrollNotification(:final dragDetails, :final overscroll):
        // Clamping physics (Android) reports the motion it refused here. A
        // ballistic overscroll is a fling arriving at the end, which is not
        // somebody asking for anything.
        if (dragDetails == null) {
          _release();
          break;
        }
        _dragging = true;
        // The other end of the entry. Overscrolling into the *start* is not a
        // request to go forward.
        if (metrics.extentAfter > 0) {
          _cancel();
          break;
        }
        if (overscroll <= 0 && widget.controller.value <= 0) break;
        _pullTo(widget.controller.value + overscroll);

      case ScrollUpdateNotification(:final dragDetails, :final scrollDelta):
        if (dragDetails == null) {
          _release();
          break;
        }
        _dragging = true;
        final delta = scrollDelta ?? 0;
        // A pull already in flight moves with every delta, in either
        // direction. Under clamping physics this is the *only* thing that
        // unwinds one, because the position itself cannot express a pull; under
        // bouncing physics it is the position's own travel, friction and all.
        if (widget.controller.value > 0) {
          _pullTo(widget.controller.value + delta);
          break;
        }
        // Starting one. Bouncing physics lets the position travel past the
        // end, but only the part of *this* movement that went past it is a
        // pull — never the absolute overshoot, which a lazily built list can
        // leave behind on its own when a scroll correction lands. Reading that
        // absolute number is how a pull appears that nobody made.
        if (metrics.extentAfter > 0 || delta <= 0) break;
        final past = (metrics.pixels - metrics.maxScrollExtent).clamp(
          0.0,
          delta,
        );
        if (past > 0) _pullTo(past);

      case ScrollEndNotification():
        _release();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}

/// How tall the revealed panel is. Shorter than [kPullUpThreshold] so it is
/// fully on screen — and readable — a moment *before* the pull arms.
const double kPullUpPanelHeight = 84;

/// What the pull reveals from below the reader.
///
/// A [Positioned] for the reader's stack, drawn above the chrome so the two
/// never fight over the bottom of the screen, and never hit-testable: this is
/// the gesture reporting on itself, not a second control.
///
/// It slides rather than grows. The panel is one fixed height that starts
/// entirely below the bottom edge and is carried up by the pull, so the words
/// on it are the same size the whole way in; a label that stretched as it
/// appeared would read as something going wrong. Once it has fully arrived it
/// stops, and the rest of the pull is rubber.
class PullUpAffordance extends StatelessWidget {
  const PullUpAffordance({super.key, required this.controller});

  final PullUpController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: controller,
    builder: (context, extent, _) => Positioned(
      left: 0,
      right: 0,
      bottom: (extent - kPullUpPanelHeight).clamp(-kPullUpPanelHeight, 0.0),
      height: kPullUpPanelHeight,
      child: IgnorePointer(
        child: extent <= 0
            ? const SizedBox.shrink()
            : _PullUpPanel(
                progress: controller.progress,
                armed: controller.armed,
              ),
      ),
    ),
  );
}

class _PullUpPanel extends StatelessWidget {
  const _PullUpPanel({required this.progress, required this.armed});

  final double progress;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final ink = armed ? ReaderColors.chipInk : ReaderColors.buttonInk;
    return Container(
      decoration: BoxDecoration(
        color: armed ? ReaderColors.chipSurface : ReaderColors.buttonSurface,
        border: const Border(top: BorderSide(color: ReaderColors.buttonBorder)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  backgroundColor: ReaderColors.track,
                  valueColor: AlwaysStoppedAnimation<Color>(ink),
                ),
                Icon(
                  armed ? Icons.check : Icons.arrow_upward,
                  size: 13,
                  color: ink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            armed ? 'Release for next entry' : 'Pull up for next entry',
            key: const ValueKey('pullUpNextLabel'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
