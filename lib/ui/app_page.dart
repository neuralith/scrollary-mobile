import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Every screen the router pushes **above** the shell.
///
/// Identical to a `MaterialPage` in every respect a user can see — same
/// transition, same gestures, same background — with one difference: its route
/// stops being *opaque* while [keepBelowPainted] is true.
///
/// That single bit is the whole of the foreground-multitasking mechanism.
/// Flutter does not paint what an opaque route covers, and a platform view that
/// is not painted is a WebView whose `requestAnimationFrame` stops (iOS) or is
/// throttled to a fifth of the display rate (Android) — which is how a page's
/// lazy content silently fails to arrive
/// (docs/FOREGROUND_MULTITASKING.md §3.1). A non-opaque route keeps the shell
/// beneath it painted, so the one WebView carries on at the same rect, in the
/// same session, with the same viewport.
///
/// What it does **not** change: the route still covers the screen visually
/// (its own scaffold is opaque), its modal barrier still absorbs every pointer,
/// and that barrier still wraps the content in `BlockSemantics` — so the
/// WebView underneath stays untouchable and unreadable by assistive
/// technology. Occlusion is Flutter's, not hand-rolled.
class AppPage<T> extends Page<T> {
  const AppPage({
    required this.child,
    required this.keepBelowPainted,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;

  /// True while the app must keep painting whatever is under this route.
  ///
  /// Read live: toggling it while the route is on screen updates the route's
  /// opacity in place, so the capability can be turned on or off without a
  /// restart and without a stale screen deciding whether a run keeps working.
  final ValueListenable<bool> keepBelowPainted;

  @override
  Route<T> createRoute(BuildContext context) => _AppPageRoute<T>(this);
}

class _AppPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  /// `allowSnapshotting: false` on purpose. A snapshotted transition rasterises
  /// the route into a texture for the length of the animation, and this is the
  /// one route type in the app that may have a live WebView underneath it —
  /// freezing that into a still, even for 300 ms, is exactly the class of thing
  /// this file exists to prevent. The cost is one ordinary transition.
  _AppPageRoute(AppPage<T> page)
    : _keepBelowPainted = page.keepBelowPainted,
      super(settings: page, allowSnapshotting: false) {
    _keepBelowPainted.addListener(_onKeepChanged);
  }

  /// Held rather than read back off [settings]: the page object is replaced on
  /// every router rebuild, and a listener has to be removed from the same
  /// object it was added to.
  final ValueListenable<bool> _keepBelowPainted;

  AppPage<T> get _page => settings as AppPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => !_keepBelowPainted.value;

  void _onKeepChanged() {
    // Not on screen yet: `install` reads `opaque` for itself, and there is no
    // internal state to tell about a change.
    if (overlayEntries.isEmpty) return;
    // `TransitionRoute` writes this itself when its animation completes; while
    // the route is already settled, nothing else will, so do it here.
    if (animation?.isCompleted ?? false) {
      overlayEntries.first.opaque = opaque;
    }
    changedInternalState();
  }

  @override
  void dispose() {
    _keepBelowPainted.removeListener(_onKeepChanged);
    super.dispose();
  }
}
