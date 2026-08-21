/// Why a Browser-dependent phase may not read the page yet.
enum SurfaceHold {
  /// The app is not compositing the WebView. The authoritative reason.
  notPainted,

  /// The page has no measurable layout — it has never been laid out, or it is
  /// mid-navigation.
  unmeasurable,

  /// The page says it is not being shown, while the app says it is drawing it.
  /// A contradiction, and a *temporary* one: see [kPageHiddenGrace].
  pageReportsHidden,
}

/// How long a page is allowed to insist it is hidden while the app is drawing
/// it, before the app's own knowledge wins.
///
/// **This is not a tuned timeout; it is the resolution of a contradiction.**
/// WebKit fixes `document.visibilityState` when a document is created, and a
/// document created in a view that is not yet composited starts life `hidden`
/// and can stay that way after the view *is* composited. That is exactly what
/// happens when an operation starts while the user is already on another
/// screen: the operation asks for the surface to be drawn and navigates in the
/// same breath, and the new document is born hidden.
///
/// Measured on a physical iPhone against a real site: the check held on
/// `pageReportsHidden` for its entire budget and failed, on a page the app was
/// drawing the whole time. An unbounded page-side veto is therefore a permanent
/// stall — the worst failure this feature can have — so the page gets a settle
/// window to correct itself and then the app decides.
const Duration kPageHiddenGrace = Duration(seconds: 6);

/// May a Browser-dependent phase read the page? Null means yes.
///
/// [heldFor] is how long this particular hold has already lasted; it is what
/// bounds the page-side veto. The two app-side reasons are never bounded — if
/// the app is not drawing the WebView, or the page has no layout, waiting is
/// the only correct thing to do and it waits as long as it takes.
SurfaceHold? surfaceHoldReason({
  required bool surfaceIsPainted,
  required bool pageHidden,
  required int viewportHeight,
  required Duration heldFor,
  Duration hiddenGrace = kPageHiddenGrace,
}) {
  if (!surfaceIsPainted) return SurfaceHold.notPainted;
  if (viewportHeight <= 0) return SurfaceHold.unmeasurable;
  if (pageHidden && heldFor < hiddenGrace) return SurfaceHold.pageReportsHidden;
  return null;
}

/// What to write in the log when [hold] is why a phase is waiting.
///
/// Only two of the three are the user's problem. When the app *is* drawing the
/// WebView and the page simply has not caught up, telling someone to open the
/// Browser is a wrong instruction — nothing they can do would help, and the
/// wait resolves itself within [kPageHiddenGrace].
String surfaceHoldMessage(SurfaceHold hold) => switch (hold) {
  SurfaceHold.notPainted => 'the app is not drawing it — open the Browser',
  SurfaceHold.unmeasurable => 'it has no measurable layout — open the Browser',
  SurfaceHold.pageReportsHidden =>
    'the page has not registered that it is on screen yet — settling',
};

/// Whether [hold] is something the user can act on.
///
/// A settling page is not a "Needs you": nothing is wrong, nobody is required,
/// and it clears itself. Surfacing it as an instruction would teach users to
/// distrust the one that matters.
bool holdNeedsTheUser(SurfaceHold hold) =>
    hold != SurfaceHold.pageReportsHidden;

/// What the app is doing with its one WebView, resolved in one place.
///
/// Pulled out of the widget that owns it so the rule can be read, argued with
/// and tested without a platform view. See docs/FOREGROUND_MULTITASKING.md §6.
class BrowserSurfaceState {
  const BrowserSurfaceState({
    required this.isPainted,
    required this.keepPainted,
    required this.browserOnScreen,
  });

  /// The app is compositing the WebView, so a Browser-dependent phase may
  /// read the page. Published to `BrowserController.surfaceIsPainted`.
  final bool isPainted;

  /// The shell must keep the Browser child drawn, and screens above the shell
  /// must not be opaque, because an operation is using the page.
  final bool keepPainted;

  /// The Browser is what the user is actually looking at. The running-operation
  /// indicator stays out of its way, because the Browser reports the same run
  /// in full.
  final bool browserOnScreen;
}

/// The whole rule.
///
/// [operationOwnsBrowser] — a save, a check or anything else holding
/// `automationOwner`. [atShellRoute] — nothing is stacked over the shell.
///
/// Three things have to be true for the surface to count as painted:
///
/// * the app is in front. Leaving the foreground is not a background
///   hand-off; it is the app drawing nothing, and an operation holds through
///   the same guard as any other reason for not drawing.
/// * the shell is showing the Browser child — because the user is on that tab,
///   or because an operation asked for it to stay drawn.
/// * nothing opaque covers the shell. True at the shell route, and true above
///   it exactly when [keepPainted] made those screens non-opaque — the same
///   flag decides both, so the two can never disagree.
BrowserSurfaceState resolveBrowserSurface({
  required bool capabilityEnabled,
  required bool operationOwnsBrowser,
  required bool appInForeground,
  required bool browserTabSelected,
  required bool atShellRoute,
}) {
  final keepPainted = capabilityEnabled && operationOwnsBrowser;
  final browserOnstage = browserTabSelected || keepPainted;
  return BrowserSurfaceState(
    isPainted:
        appInForeground && browserOnstage && (atShellRoute || keepPainted),
    keepPainted: keepPainted,
    browserOnScreen: browserTabSelected && atShellRoute,
  );
}
