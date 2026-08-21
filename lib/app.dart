import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'browser/browser_controller.dart';
import 'browser/browser_surface_policy.dart';
import 'capability/foreground_multitasking.dart';
import 'save/save_run.dart';
import 'features/activity_screen.dart';
import 'features/operation_indicator.dart';
import 'ui/app_page.dart';
import 'features/archived_screen.dart';
import 'core/local_reset.dart';
import 'features/browser_history_screen.dart';
import 'features/browser_screen.dart';
import 'features/developer_screen.dart';
import 'features/library_screen.dart';
import 'features/open_in_browser.dart';
import 'features/reader_screen.dart';
import 'features/page_hints_screen.dart';
import 'features/collection_detail_screen.dart';
import 'capability/foreground_gate.dart';
import 'features/foreground_gate_sheet.dart';
import 'features/settings_screen.dart';
import 'features/storage_screen.dart';
import 'library/update_checker.dart';
import 'core/device_capacity_provider.dart';
import 'providers.dart';
import 'queue/task_queue.dart';
import 'storage/cleanup.dart';
import 'ui/palette.dart';
import 'ui/theme.dart';

/// The browser tab keeps its WebView alive across tab switches — the session
/// the user browsed with is the session save runs in, so it must not be
/// rebuilt when they look at the library.
class WebReaderApp extends ConsumerStatefulWidget {
  const WebReaderApp({super.key});

  @override
  ConsumerState<WebReaderApp> createState() => _WebReaderAppState();
}

class _WebReaderAppState extends ConsumerState<WebReaderApp>
    with WidgetsBindingObserver {
  /// Every screen above the shell is built through this, so "a screen that
  /// keeps the Browser working underneath it" is one decision in one place
  /// rather than a property each route has to remember.
  ///
  /// **Adding a route? Use `pageBuilder:` and call this. Not `builder:`.**
  ///
  /// `builder:` gets go_router's default page, which is an *opaque* route.
  /// Flutter does not paint what an opaque route covers, and a platform view
  /// that is not painted is a WebView whose `requestAnimationFrame` stops — so
  /// a save or check the user started would hold, silently, until they
  /// navigated back. Nothing about that fails to compile or fails analysis; it
  /// fails on a device, minutes in, as a hang.
  ///
  /// `test/route_paint_invariant_test.dart` reads this file and fails the build
  /// if a route above the shell bypasses this helper. If it fails, route the
  /// new screen through here rather than adding an exception.
  Page<void> _page(GoRouterState state, Widget child) => AppPage<void>(
    key: state.pageKey,
    name: state.name ?? state.uri.path,
    keepBelowPainted: _keepPainted,
    child: child,
  );

  // Built per app instance, not as a top-level singleton: a global router
  // keeps its navigation stack across app restarts inside a test process, so
  // a second boot would come up on whatever route the first one ended on.
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _Shell()),
      GoRoute(
        path: '/reader/:entryId',
        pageBuilder: (context, state) => _page(
          state,
          ReaderScreen(entryId: state.pathParameters['entryId']!),
        ),
      ),
      GoRoute(
        path: '/collection/:collectionId',
        pageBuilder: (context, state) => _page(
          state,
          CollectionDetailScreen(
            collectionId: state.pathParameters['collectionId']!,
            startInSelectionMode: state.uri.queryParameters['select'] == '1',
          ),
        ),
      ),
      GoRoute(
        path: '/rules',
        pageBuilder: (context, state) => _page(state, const PageHintsScreen()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            _page(state, const BrowserHistoryScreen()),
      ),
      GoRoute(
        path: '/activity',
        pageBuilder: (context, state) => _page(state, const ActivityScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _page(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/archived',
        pageBuilder: (context, state) => _page(state, const ArchivedScreen()),
      ),
      GoRoute(
        path: '/storage',
        pageBuilder: (context, state) => _page(state, const StorageScreen()),
      ),
      // Registered only in debug: in release the route does not exist, so
      // even a hand-typed deep link cannot reach it (D50).
      if (developerToolsAvailable)
        GoRoute(
          path: '/developer',
          pageBuilder: (context, state) =>
              _page(state, const DeveloperScreen()),
        ),
    ],
  );

  late final ValueNotifier<bool> _keepPainted;
  late final ValueNotifier<bool> _browserOnScreen;
  late final ValueNotifier<int> _tab;
  late final BrowserController _browser;
  late final SaveRunController _run;
  late final UpdateChecker _checker;
  late final ForegroundMultitasking _capability;
  late final ValueNotifier<bool> _pendingSurfaceClaim;

  @override
  void initState() {
    super.initState();
    _keepPainted = ref.read(keepBrowserPaintedProvider);
    _browserOnScreen = ref.read(browserOnScreenProvider);
    _tab = ref.read(shellTabProvider);
    _browser = ref.read(browserProvider);
    _run = ref.read(saveRunProvider);
    _checker = ref.read(updateCheckerProvider);
    _capability = ref.read(foregroundMultitaskingProvider);
    _pendingSurfaceClaim = ref.read(pendingSurfaceClaimProvider);
    _pendingSurfaceClaim.addListener(_recomputeSurface);
    for (final source in [_run, _checker, _capability, _browser]) {
      source.addListener(_recomputeSurface);
    }
    _tab.addListener(_recomputeSurface);
    _router.routerDelegate.addListener(_recomputeSurface);
    WidgetsBinding.instance.addObserver(this);
    _recomputeSurface();
  }

  /// The app leaving the foreground is not a background hand-off; it is the
  /// app no longer drawing anything, including its WebView. Recorded as
  /// exactly that, so a running operation holds through the existing guard
  /// rather than needing a state of its own — and resumes on the way back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _recomputeSurface();
  }

  bool _foreground = true;

  @override
  void dispose() {
    for (final source in [_run, _checker, _capability, _browser]) {
      source.removeListener(_recomputeSurface);
    }
    _pendingSurfaceClaim.removeListener(_recomputeSurface);
    _tab.removeListener(_recomputeSurface);
    _router.routerDelegate.removeListener(_recomputeSurface);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The one place that decides whether the app is painting its WebView, and
  /// tells the controller so.
  ///
  /// Three inputs, and all three have to hold:
  ///
  /// * the shell is showing the Browser child — either because the user is on
  ///   that tab, or because an operation asked for it to stay painted;
  /// * nothing opaque is stacked above the shell — true at the shell route, and
  ///   true above it exactly when [_keepPainted] made those routes non-opaque;
  /// * an operation is what wants it, or the user is simply there.
  ///
  /// Published to [BrowserController.surfaceIsPainted] because the page cannot
  /// answer this for itself: an unpainted WebView keeps a full viewport and
  /// keeps scrolling on both platforms, and on Android it goes on calling
  /// itself visible (docs/FOREGROUND_MULTITASKING.md §3.1).
  void _recomputeSurface() {
    final owns =
        _run.isRunning ||
        _checker.isRunning ||
        _browser.isAutomating ||
        _pendingSurfaceClaim.value;
    // Latched for the lifetime of this operation's ownership: a setting the
    // user changes mid-task must not take the surface away from a run that is
    // in the middle of reading a page (see TaskCapabilitySnapshot).
    final capabilityForTask = _capability.taskSnapshot.resolve(
      operationOwnsBrowser: owns,
      liveEnabled: _capability.enabled,
    );
    final resolved = resolveBrowserSurface(
      capabilityEnabled: capabilityForTask,
      operationOwnsBrowser: owns,
      appInForeground: _foreground,
      browserTabSelected: _tab.value == 1,
      atShellRoute:
          _router.routerDelegate.currentConfiguration.matches.length <= 1,
    );
    _keepPainted.value = resolved.keepPainted;
    _browser.surfaceIsPainted = resolved.isPainted;
    _browserOnScreen.value = resolved.browserOnScreen;
  }

  /// Everything the compact activity indicator does not say itself: progress,
  /// logs, failures, retry, reorder, stop, and the way back to the Browser for
  /// a run that needs one.
  ///
  /// Pushed from the router the app owns rather than from a context: the
  /// indicator is built in [MaterialApp.router]'s builder, which sits *above*
  /// the router's own inherited widget, so nothing there can look one up. The
  /// no-op when Activity is already on top is what stops a repeated tap from
  /// stacking the same screen on itself.
  void _openActivity() {
    final matches = _router.routerDelegate.currentConfiguration.matches;
    if (matches.isNotEmpty && matches.last.matchedLocation == '/activity') {
      return;
    }
    _router.push('/activity');
  }

  /// Where a "Needs you" goes: the Browser, on the page the held operation is
  /// already on. The same one mechanism every other "open the Browser" in the
  /// app uses, handed the router directly because this call site is above it.
  void _openBrowserForOperation() => showBrowserSurfaceWith(_router, ref);

  @override
  Widget build(BuildContext context) {
    // Read as a value, not awaited: the app must render on the first frame,
    // and the persisted preference arriving a microsecond later re-themes it
    // without a flash of the wrong appearance being possible to notice.
    final appearance =
        ref.watch(appearanceProvider).value ?? AppearanceMode.system;
    return MaterialApp.router(
      title: 'Scrollary',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      darkTheme: appDarkTheme(),
      themeMode: themeModeFor(appearance),
      routerConfig: _router,
      // Above the router, so a running operation is legible from every screen
      // — including the ones the router pushes over the shell.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          ?child,
          OperationIndicator(
            onOpenDetails: _openActivity,
            onOpenBrowser: _openBrowserForOperation,
          ),
        ],
      ),
    );
  }
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _index = 0;

  // Held as fields: listeners must be removed in dispose, where Riverpod
  // forbids `ref`.
  late final SaveRunController _run;
  late final UpdateChecker _checker;
  bool _wasBusy = false;

  late final ValueNotifier<int?> _tabRequest;

  /// The read side of the tab: published so anything that needs to know
  /// where the user *is* — rather than ask them to move — can read it. The
  /// Library-check foreground flow records it at the start of a run.
  late final ValueNotifier<int> _tab;
  late final CleanupService _cleanup;
  late final TaskQueueController _queue;

  /// Set by [_WebReaderAppState]; read here to decide what the shell paints.
  late final ValueNotifier<bool> _keepPainted;

  /// The Browser child is drawn when the user is on that tab, or when an
  /// operation needs it to go on working while they are elsewhere.
  bool get _browserOnstage => _index == 1 || _keepPainted.value;

  /// Held as a field for the same reason the controllers are: the leave gate is
  /// asked from `dispose`-adjacent paths and from `PopScope`.
  late final ForegroundMultitasking _capability;

  /// Files just went away: the device figure the Library shows is stale by
  /// exactly the amount that was freed.
  void _onStorageChanged() {
    unawaited(ref.read(deviceCapacityProvider.notifier).refresh(force: true));
  }

  @override
  void initState() {
    super.initState();
    _run = ref.read(saveRunProvider);
    _checker = ref.read(updateCheckerProvider);
    _tabRequest = ref.read(shellTabRequestProvider);
    _tab = ref.read(shellTabProvider);
    _tab.value = _index;
    _keepPainted = ref.read(keepBrowserPaintedProvider);
    _keepPainted.addListener(_onKeepPaintedChanged);
    _run.addListener(_onAutomationChanged);
    _checker.addListener(_onAutomationChanged);
    _tabRequest.addListener(_onTabRequested);
    _cleanup = ref.read(cleanupProvider);
    _cleanup.removals.addListener(_onStorageChanged);
    _capability = ref.read(foregroundMultitaskingProvider);
    // The queue asks the shell to bring the Browser forward before it drives
    // the WebView. The shell is the only thing that can switch tabs, and the
    // ordering — navigate, THEN automate — is the whole contract (D47).
    _queue = ref.read(taskQueueProvider);
    _queue.ensureBrowserVisible = _ensureBrowserVisible;
  }

  /// Show the Browser — on [url] when the caller named one — and wait for its
  /// WebView to attach.
  ///
  /// *Show*, not "select the tab": queued work is started from Activity, from
  /// Collection Detail and from the reader, all of which are routes pushed
  /// **above** this shell. Moving the index underneath one of them left the
  /// user watching a passive screen while the save drove a Browser they could
  /// not see — so the pop is as load-bearing as the tab, and
  /// [showBrowserSurface] owns both.
  ///
  /// Showing the *tab* is still not showing the *page*: Browser Home and the
  /// address editor are layers over the WebView, so work could drive a page
  /// that was covered the whole time. A named [url] therefore goes through
  /// [BrowserNavigator] — the one mechanism the whole app opens pages with —
  /// which reveals the website surface and loads it once the WebView is live.
  ///
  /// Attachment is not the same as *rendered*: the save engine still runs
  /// its own zero-viewport guard (D32). This only guarantees the user is
  /// looking at the Browser before anything starts, so automation is never a
  /// surprise happening behind another screen.
  Future<bool> _ensureBrowserVisible({String? url}) async {
    if (!mounted) return false;
    // Stored before the tab switch, exactly as "open in Browser" does: the
    // Browser drains it when it is mounted with an attached WebView, so
    // nothing is lost to the pop or to a WebView that is not there yet.
    final target = url?.trim() ?? '';
    if (target.isNotEmpty) ref.read(browserNavigatorProvider).request(target);
    if (_capability.enabled) {
      // The capability's whole point: the page must be *drawn*, not *shown*.
      // Nothing owns the Browser yet — the run starts after this returns — so
      // the claim is what makes the shell keep the child on stage in the
      // meantime. It is released the moment a real owner appears, and by a
      // fallback timer if one never does, so a start that fizzles cannot leave
      // the Browser painted under the Library forever.
      _claimSurfaceForStart();
    } else {
      showBrowserSurface(context, ref);
    }
    final browser = ref.read(browserProvider);
    for (var i = 0; i < 100; i++) {
      if (!mounted) return false;
      if (browser.isAttached) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return browser.isAttached;
  }

  /// Set while a multitasking start is bringing the surface up, before the
  /// operation that asked for it exists. Counted as ownership by
  /// [_WebReaderAppState._recomputeSurface] via [pendingSurfaceClaim].
  bool _surfaceClaim = false;
  Timer? _surfaceClaimTimer;

  void _claimSurfaceForStart() {
    _surfaceClaim = true;
    _surfaceClaimTimer?.cancel();
    // Long enough for a queue pump to claim a task and start it; short enough
    // that a start which never happened stops holding the surface.
    _surfaceClaimTimer = Timer(
      const Duration(seconds: 20),
      _releaseSurfaceClaim,
    );
    ref.read(pendingSurfaceClaimProvider).value = true;
  }

  void _releaseSurfaceClaim() {
    _surfaceClaimTimer?.cancel();
    _surfaceClaimTimer = null;
    if (!_surfaceClaim) return;
    _surfaceClaim = false;
    ref.read(pendingSurfaceClaimProvider).value = false;
  }

  void _onKeepPaintedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _keepPainted.removeListener(_onKeepPaintedChanged);
    _run.removeListener(_onAutomationChanged);
    _checker.removeListener(_onAutomationChanged);
    _tabRequest.removeListener(_onTabRequested);
    _cleanup.removals.removeListener(_onStorageChanged);
    _queue.ensureBrowserVisible = null;
    _surfaceClaimTimer?.cancel();
    super.dispose();
  }

  /// True when leaving the Browser right now would strand a phase that needs
  /// the page on screen.
  ///
  /// Downloading and committing phases are deliberately excluded — they were
  /// safe away from the Browser before any of this existed and stay safe for
  /// everyone — and so is an already-paused run. The modal must not cry wolf.
  bool get _phaseNeedsBrowser =>
      _index == 1 && (_run.needsRenderedBrowser || _checker.isRunning);

  /// Who decides, and it is never this widget: what the user has, what they
  /// asked for and what the running task started with all resolve in
  /// [ForegroundMultitasking.leaveGate].
  LeaveGate get _leaveGate =>
      _capability.leaveGate(phaseNeedsBrowser: _phaseNeedsBrowser);

  /// The leave-Browser decision. Returns true when navigation may proceed —
  /// either nothing was at risk, or the user chose to hold the work here.
  ///
  /// Dismissing the sheet is *stay*: walking away from a question about work in
  /// flight must never be read as permission to strand it.
  Future<bool> confirmLeaveBrowser() async {
    final gate = _leaveGate;
    if (gate == LeaveGate.allowed) return true;
    final choice = await showLeaveBrowserSheet(
      context: context,
      ref: ref,
      gate: gate,
      progressLine: _run.isRunning
          ? _run.progressSummary
          : 'Checking for new entries',
    );
    if (choice != LeaveChoice.pauseAndLeave) return false;
    // Pause the WebView-dependent phase before anything moves. The task
    // stays active and queued work is untouched: this is a hold, not a stop.
    if (_run.isRunning) _run.pauseForBrowserHidden();
    return true;
  }

  /// A widget inside a tab asked for a tab switch (e.g. "Open Browser" on a
  /// save that is holding on a hidden WebView).
  ///
  /// Deliberately does **not** call [_onEnteredBrowser]. "Open in Browser"
  /// arrives here having just paused a save on purpose, and auto-resuming
  /// it on the way in would restart the run one frame before the page is
  /// navigated out from under it. Only a *user-initiated* tab tap ([_select])
  /// lifts a leave-pause.
  void _onTabRequested() {
    final requested = _tabRequest.value;
    if (requested == null) return;
    _tabRequest.value = null;
    if (requested != _index && requested >= 0 && requested <= 1) {
      setState(() => _index = requested);
      _tab.value = _index;
    }
  }

  /// When a save or update check starts, bring the Browser tab forward —
  /// what the design's prototype does, and also load-bearing: an offstage
  /// WKWebView throttles rAF and lazy-loading, so a save driving a hidden
  /// WebView (e.g. started from collection detail) would stall mid-scroll.
  /// Transition-edge only: once the user has seen the switch they are free to
  /// go back to the Library without the shell fighting them.
  void _onAutomationChanged() {
    final busy = _run.isRunning || _checker.isRunning;
    // A real owner has appeared: the start claim has done its job.
    if (busy) _releaseSurfaceClaim();
    // With the capability on, an operation starting is not a reason to move
    // the user. The surface is kept drawn underneath whatever they are looking
    // at, which is the entire product difference.
    if (busy && !_wasBusy && _index != 1 && !_capability.enabledForActiveTask) {
      setState(() => _index = 1);
      _tab.value = _index;
    }
    // Falling idle is the moment the disk actually changed: a save just
    // wrote (or a check just did not). Re-read then, rather than polling —
    // the Library's percentage is otherwise as stale as its throttle allows.
    if (!busy && _wasBusy) {
      unawaited(ref.read(deviceCapacityProvider.notifier).refresh(force: true));
    }
    _wasBusy = busy;
  }

  /// Returning to the Browser: the save engine's own render guard does
  /// the validating (viewport, then the page it was on). Here we only lift
  /// the leave-pause; if the page changed, the engine keeps holding and the
  /// Browser shows why.
  void _onEnteredBrowser() {
    if (_run.pauseReason == kPauseBrowserHidden) {
      _run.resumeAfterBrowserVisible();
    }
  }

  Future<void> _select(int i) async {
    if (i == _index) return;
    if (i != 1 && !await confirmLeaveBrowser()) return;
    if (!mounted) return;
    setState(() => _index = i);
    _tab.value = _index;
    if (i == 1) _onEnteredBrowser();
  }

  @override
  Widget build(BuildContext context) {
    return LeaveBrowserGuard(
      confirm: confirmLeaveBrowser,
      // System back out of the shell is a leave too: block it while a
      // WebView-dependent phase is running, then let it through once the
      // user has answered.
      child: PopScope(
        canPop: _leaveGate == LeaveGate.allowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (await confirmLeaveBrowser() && mounted) {
            navigator.maybePop();
          }
        },
        child: Scaffold(
          // A Stack whose children are never added or removed, not a swapped
          // child and no longer an IndexedStack: switching tabs must not
          // dispose the WebView or a running save dies with it, *and* the
          // Browser has to be able to keep painting underneath the Library
          // while an operation is using it. `StackFit.expand` is load-bearing
          // — an offstage child is still laid out, and it must be laid out at
          // the full size, or the WebView would come back at a different
          // viewport from the one it was working at.
          body: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: !_browserOnstage,
                // Onstage but covered: the Library owns every touch and every
                // announcement. `Offstage` already blocks both when it is off;
                // this is the case it cannot cover.
                child: IgnorePointer(
                  ignoring: _index != 1,
                  child: ExcludeSemantics(
                    excluding: _index != 1,
                    child: const BrowserScreen(),
                  ),
                ),
              ),
              Offstage(offstage: _index != 0, child: const LibraryScreen()),
            ],
          ),
          bottomNavigationBar: _BottomNav(index: _index, onSelect: _select),
        ),
      ),
    );
  }
}

/// Exposes the shell's leave-Browser confirmation to anything that can
/// navigate away from it — route pushes (Settings, Activity, Storage,
/// Archived, Rules) and system back.
///
/// An InheritedWidget rather than a provider so a widget deep in the Library
/// or Browser tab can ask "may I navigate?" without knowing the shell exists.
class LeaveBrowserGuard extends InheritedWidget {
  const LeaveBrowserGuard({
    super.key,
    required this.confirm,
    required super.child,
  });

  /// Resolves true when navigation may proceed.
  final Future<bool> Function() confirm;

  static LeaveBrowserGuard? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LeaveBrowserGuard>();

  /// Ask before leaving. Safe to call from anywhere — with no guard in the
  /// tree (tests, deep routes) it simply allows the navigation.
  static Future<bool> confirmLeave(BuildContext context) async {
    final guard = maybeOf(context);
    if (guard == null) return true;
    return guard.confirm();
  }

  /// Guarded `context.push`: confirms first when a save needs the
  /// Browser, then navigates. Used by every route that leaves the Browser.
  static Future<void> push(BuildContext context, String location) async {
    if (!await confirmLeave(context)) return;
    if (context.mounted) context.push(location);
  }

  @override
  bool updateShouldNotify(LeaveBrowserGuard oldWidget) =>
      confirm != oldWidget.confirm;
}

/// How tall [_BottomNav] is, excluding the bottom safe-area inset: 6 + 6
/// padding around a 6/3/2-padded 22pt glyph and its 11pt label. Published so
/// anything floating over the shell can clear it rather than guess.
const double kShellBottomBarHeight = 62;

/// The design's two-item bar: a filled pill behind the selected glyph rather
/// than Material's default indicator, and no ripple sprawl. Plain Material
/// widgets only, so it renders identically on iOS and Android; the bottom
/// inset comes from [MediaQuery] rather than an assumed iPhone home bar.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.collections_bookmark, 'Library'),
      (Icons.public, 'Browser'),
    ];

    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                key: ValueKey('navTab-${items[i].$2}'),
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(16),
                child: _NavItem(
                  icon: items[i].$1,
                  label: items[i].$2,
                  selected: i == index,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = selected ? palette.onPrimaryContainer : palette.inkMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? palette.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontVariations: wght(selected ? 600 : 400),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
