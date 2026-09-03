import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'browser/browser_controller.dart';
import 'browser/browser_presentation.dart';
import 'browser/browser_surface_policy.dart';
import 'capability/foreground_multitasking.dart';
import 'features/operation_indicator.dart';
import 'features/operation_lane.dart';
import 'ui/app_page.dart';

import 'core/local_reset.dart';
import 'data/collection_preference_adoption.dart';
import 'features/activity_screen.dart';
import 'features/browser_history_screen.dart';
import 'features/browser_screen.dart';
import 'features/developer_screen.dart';

import 'features/open_in_browser.dart';
import 'features/page_hints_screen.dart';
import 'features/check_controller.dart';
import 'features/v2_reader_route.dart';
import 'library_ui/collection_screen.dart';
import 'library_ui/shelf_screen.dart';
import 'reading_v2/source_reading.dart';
import 'save/queue_runner.dart';
import 'sync/scheduler.dart';
import 'capability/foreground_gate.dart';
import 'library_ui/providers.dart';
import 'save/queue_task.dart';
import 'features/foreground_gate_sheet.dart';
import 'features/v2_check_flow.dart';
import 'features/settings_screen.dart';
import 'features/storage_screen.dart';
import 'core/device_capacity_provider.dart';
import 'providers.dart';
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
          V2ReaderRoute(entryId: state.pathParameters['entryId']!),
        ),
      ),
      GoRoute(
        path: '/collection/:collectionId',
        pageBuilder: (context, state) => _page(
          state,
          CollectionScreen(collectionId: state.pathParameters['collectionId']!),
        ),
      ),
      GoRoute(
        path: '/activity',
        pageBuilder: (context, state) => _page(state, const ActivityScreen()),
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
        path: '/settings',
        pageBuilder: (context, state) => _page(state, const SettingsScreen()),
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
  late final ValueNotifier<bool> _surfacePainted;
  late final ValueNotifier<int> _tab;
  late final BrowserController _browser;
  late final QueueRunner _queueRunner;
  late final CheckController _sourceCheck;
  late final ForegroundMultitasking _capability;
  late final ValueNotifier<bool> _pendingSurfaceClaim;

  /// Where a reading at a Source is recorded. Held rather than read from the
  /// provider each time: the scroll callback runs on every frame of a drag.
  late final SourceReadingMeter _sourceReading;

  /// When metadata sync takes an opportunity. The app root drives it because
  /// the app root is what knows whether the app is in front — the scheduler
  /// reaches for no platform signal of its own (V2-D20).
  late final SyncScheduler _sync;

  @override
  void initState() {
    super.initState();
    _keepPainted = ref.read(keepBrowserPaintedProvider);
    _browserOnScreen = ref.read(browserOnScreenProvider);
    _surfacePainted = ref.read(browserSurfacePaintedProvider);
    _tab = ref.read(shellTabProvider);
    _browser = ref.read(browserProvider);
    _queueRunner = ref.read(queueRunnerProvider);
    _sourceCheck = ref.read(checkControllerProvider);
    final v2 = ref.read(v2ServicesProvider);
    v2.openEntry = (id) async {
      _router.push('/reader/$id');
    };
    // Two steps, and only one of them was here. Storing the request sends the
    // Browser somewhere; **showing** it is what puts the user in front of the
    // page they asked to open. The Browser is a tab inside the shell route and
    // Collection Detail, Activity and the reader are pushed above it, so
    // flipping the tab underneath one of them changed nothing anybody could
    // see — the page loaded and the user stayed where they were.
    // `showBrowserSurfaceWith` owns the pop and the tab together, which is
    // exactly why it exists (`features/open_in_browser.dart`).
    v2.openSource = (url) async => showBrowserAt(_router, ref, url);
    _sourceReading = v2.sourceReading;
    // The page moved. The WebView reports every scroll, ours included, so this
    // is where a person's scrolling is told from an operation's — the app root
    // is the one place that knows which operations hold the Browser.
    _browser.onScrolled = _onPageScrolled;
    _capability = ref.read(foregroundMultitaskingProvider);
    _sync = v2.sync.scheduler;
    _pendingSurfaceClaim = ref.read(pendingSurfaceClaimProvider);
    _pendingSurfaceClaim.addListener(_recomputeSurface);
    for (final source in [_queueRunner, _sourceCheck, _capability, _browser]) {
      source.addListener(_recomputeSurface);
    }
    _tab.addListener(_recomputeSurface);
    _tab.addListener(_onTabChangedForReading);
    _router.routerDelegate.addListener(_recomputeSurface);
    WidgetsBinding.instance.addObserver(this);
    _recomputeSurface();
    // Preferences an older build wrote as settings rows move onto the
    // Collections that now own them, before the first drain: adopting one
    // writes an outbox intent, and doing it after the drain would leave the
    // answer sitting on this device until the next mutation happened to wake
    // the scheduler. Ordinarily a no-op — there is nothing to move — so it is
    // not awaited and a failure is not fatal to launch.
    unawaited(
      adoptLegacyCollectionPreferences(
        v2.library,
      ).catchError((Object _) => const AdoptedPreferences()),
    );
    // The app is up and in front. Nothing before this frame is an opportunity:
    // a scheduler that assumed a foreground would run before anything told it
    // to.
    v2.sync.start();
    _sync.onAppLaunch();
  }

  /// The app leaving the foreground is not a background hand-off; it is the
  /// app no longer drawing anything, including its WebView. Recorded as
  /// exactly that, so a running operation holds through the existing guard
  /// rather than needing a state of its own — and resumes on the way back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _recomputeSurface();
    // The same signal, read for the other thing it decides. Sync stops when
    // the app is not in front and picks up when it comes back — never a
    // promise of background execution, because no platform offers one.
    if (_foreground) {
      _sync.onAppResumed();
    } else {
      _sync.onAppPaused();
      // The reader has stopped reading. The page is still loaded, so this is
      // the last honest chance to record how far a reading at a Source got —
      // once the app is back, the site may well have reloaded to the top.
      unawaited(_measureSourceReading());
    }
  }

  bool _foreground = true;

  /// Record where the page currently on screen has been read to.
  ///
  /// Called at the moments the app has and nothing is invented in between: the
  /// meter refuses a probe of a page it is not watching, a page with no
  /// position to be at, and a reading that has not got further than the one
  /// already recorded.
  ///
  /// Those moments are the reader settling after a scroll, the Browser being
  /// left, and the app going away. The scroll one was added because the two
  /// leaving moments miss the one that matters most: following the site's own
  /// way on to the next Entry never leaves the Browser at all, and the page
  /// the reading was of is gone by the time the app hears about it.
  ///
  /// **Never while automation owns the Browser.** A capture scrolls the page
  /// to the bottom to enumerate it, and recording that as a reading would
  /// mark an Entry read by downloading it — exactly the conflation
  /// PRODUCT.md §2.3 forbids.
  Future<void> _measureSourceReading() async {
    _measureDebounce?.cancel();
    _measureDebounce = null;
    final meter = _sourceReading;
    if (!meter.isWatching) return;
    if (_somethingIsDrivingTheBrowser) return;
    if (!_browser.isAttached) return;
    try {
      _lastMeasuredAt = DateTime.now();
      // Geometry and images, without the content, media and access signals —
      // the same light probe the scroll loop takes, because that is all a
      // position and a content band are read from.
      await meter.record(await _browser.probe(withSignals: false));
    } catch (_) {
      // A WebView mid-teardown, a page that will not answer: a measurement
      // that could not be taken is not an error anybody needs to see.
    }
  }

  /// True while a save run, a check or anything else is driving the Browser.
  ///
  /// The latched copy exists so the *transition* into automation can be seen;
  /// [_somethingIsDrivingTheBrowser] is what anything asking about **now**
  /// reads, because `automationOwner` is a plain field that notifies nobody.
  bool _automationOwnsBrowser = false;

  bool get _somethingIsDrivingTheBrowser =>
      _automationOwnsBrowser ||
      _queueRunner.isRunning ||
      _sourceCheck.isRunning ||
      _browser.isAutomating;

  Timer? _measureDebounce;
  DateTime? _lastMeasuredAt;

  /// How long the page has to be still before its position is read.
  ///
  /// Short, because the position at the moment the reader taps the site's own
  /// *next* link is the one the completion decision is made from, and that tap
  /// follows the last scroll closely.
  static const Duration _scrollSettle = Duration(milliseconds: 300);

  /// …and how long a continuous scroll may run without being measured at all,
  /// so a reader who never pauses is still measured on the way down.
  static const Duration _scrollMeasureInterval = Duration(seconds: 2);

  /// The page scrolled. Decide whose scroll it was, then measure once it
  /// settles.
  void _onPageScrolled() {
    final meter = _sourceReading;
    if (!meter.isWatching) return;
    // A scroll an operation performed says nothing about a reading. It seals
    // the meter rather than lifting the seal: the position the page is left in
    // is the operation's, and it stays that way until a person moves it.
    if (_somethingIsDrivingTheBrowser) {
      meter.noteAutomationScroll();
      return;
    }
    meter.noteUserScroll();

    final last = _lastMeasuredAt;
    if (last != null &&
        DateTime.now().difference(last) >= _scrollMeasureInterval) {
      unawaited(_measureSourceReading());
      return;
    }
    _measureDebounce?.cancel();
    _measureDebounce = Timer(_scrollSettle, () {
      unawaited(_measureSourceReading());
    });
  }

  @override
  void dispose() {
    _measureDebounce?.cancel();
    _browser.onScrolled = null;
    for (final source in [_queueRunner, _sourceCheck, _capability, _browser]) {
      source.removeListener(_recomputeSurface);
    }
    _pendingSurfaceClaim.removeListener(_recomputeSurface);
    _tab.removeListener(_recomputeSurface);
    _tab.removeListener(_onTabChangedForReading);
    _router.routerDelegate.removeListener(_recomputeSurface);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The Browser tab index, remembered so leaving it can be told from
  /// arriving at it. Only the leaving is a moment worth measuring at.
  int _lastTab = 0;

  void _onTabChangedForReading() {
    final was = _lastTab;
    _lastTab = _tab.value;
    if (was == kBrowserTabIndex && _tab.value != kBrowserTabIndex) {
      unawaited(_measureSourceReading());
    }
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
    final automating =
        _queueRunner.isRunning ||
        _sourceCheck.isRunning ||
        _browser.isAutomating;
    if (automating != _automationOwnsBrowser) {
      _automationOwnsBrowser = automating;
      // Taking the Browser seals the meter: capture scrolls a page to the
      // bottom to enumerate it and leaves it there, and a measurement taken
      // afterwards would mark an Entry read *by downloading it*. The seal
      // lifts when the user scrolls the page themselves.
      if (automating) _sourceReading.noteAutomationScroll();
    }
    final owns = automating || _pendingSurfaceClaim.value;
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
    _surfacePainted.value = resolved.isPainted;
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
    // The no-op when Activity is already on top is what stops a repeated tap
    // from stacking the same screen on itself.
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
  late final QueueRunner _queueRunner;
  late final CheckController _sourceCheck;
  bool _wasBusy = false;

  late final ValueNotifier<int?> _tabRequest;

  /// The read side of the tab: published so anything that needs to know
  /// where the user *is* — rather than ask them to move — can read it. The
  /// Library-check foreground flow records it at the start of a run.
  late final ValueNotifier<int> _tab;
  late final CleanupService _cleanup;

  /// Set by [_WebReaderAppState]; read here to decide what the shell paints.
  late final ValueNotifier<bool> _keepPainted;

  /// The Browser is showing a website with its chrome hidden, so the tab bar
  /// goes too. Mirrored into a field and rebuilt on change only: a `Provider`
  /// read does not deliver the presentation's own notifications, and the shell
  /// must not rebuild for every unrelated one it sends.
  late final BrowserPresentation _browserPresentation;
  bool _browserChromeHidden = false;

  void _onBrowserChromeChanged() {
    final hidden = _browserPresentation.chromeHidden;
    if (hidden == _browserChromeHidden || !mounted) return;
    setState(() => _browserChromeHidden = hidden);
  }

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
    _queueRunner = ref.read(queueRunnerProvider);
    _sourceCheck = ref.read(checkControllerProvider);
    _queueRunner.addListener(_onAutomationChanged);
    _sourceCheck.addListener(_onAutomationChanged);
    ref.read(v2ServicesProvider)
      ..startQueue = _startQueuedDownloads
      ..askRenderedFallback = _askRenderedFallback
      ..checkCollection = (id, name) =>
          startCollectionCheck(context, ref, id, collectionName: name);
    _tabRequest = ref.read(shellTabRequestProvider);
    _tab = ref.read(shellTabProvider);
    _tab.value = _index;
    _keepPainted = ref.read(keepBrowserPaintedProvider);
    _keepPainted.addListener(_onKeepPaintedChanged);
    _browserPresentation = ref.read(browserPresentationProvider)
      ..addListener(_onBrowserChromeChanged);
    _tabRequest.addListener(_onTabRequested);
    _cleanup = ref.read(cleanupProvider);
    _cleanup.removals.addListener(_onStorageChanged);
    _capability = ref.read(foregroundMultitaskingProvider);
  }

  /// The explicit Start, and **the only place V2 Browser automation is
  /// authorised from** — every caller reaches it through
  /// `saveQueueStarterProvider`.
  ///
  /// Two things happen here and nowhere else. The queue is told the user
  /// pressed Start, which is an in-memory authorisation that is never
  /// persisted; and the foreground-multitasking gate is asked, because
  /// *where the user waits* is the one thing Pro buys
  /// (docs/FOREGROUND_MULTITASKING.md §10.0). The gate never decides whether
  /// the work happens: dismissing it, or *Not now*, leaves every row queued
  /// exactly where it was, and the visible-Browser start is fully functional
  /// without Pro.
  /// Ask whether this site may be kept as a rendering of its pages.
  ///
  /// Reached only when a capture has already established that the site will
  /// not hand over its files, and only about a page that could actually be
  /// rendered — so the question is never hypothetical. Asked **once per
  /// Source**: `RenderedFallbackGate` stores the answer, and the next Entry
  /// from the same site is not asked again either way.
  ///
  /// The wording says what the app would keep and what is lost by keeping it.
  /// It does not characterise the site, and it does not suggest that saying no
  /// can be worked around — because it cannot.
  Future<bool> _askRenderedFallback(String pageUrl) async {
    if (!mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this site as pictures of the page?'),
        content: const Text(
          'This site sends its images to the browser and nowhere else, so they '
          'cannot be downloaded. Scrollary can instead keep the pages as they '
          'appear on screen — readable offline and in order, but re-encoded '
          'and at screen quality rather than the original files.\n\n'
          'Your answer is remembered for this site, on this device.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('declineRenderedFallback'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, skip it'),
          ),
          TextButton(
            key: const ValueKey('allowRenderedFallback'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save as pictures'),
          ),
        ],
      ),
    );
    // A dismissed dialog is not consent. It is recorded as a decline by the
    // gate, which is the honest reading of "the user closed the question" —
    // and the Collection menu is where an answer is changed.
    return answer ?? false;
  }

  Future<void> _startQueuedDownloads({StartWhere? decided}) async {
    if (!mounted) return;
    final queue = ref.read(saveQueueRepoProvider);
    final waiting = [
      for (final task in await queue.pending())
        if (task.state == SaveTaskState.queued) task,
    ];
    if (!mounted) return;
    if (waiting.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Nothing is waiting to be downloaded.')),
      );
      return;
    }

    // The user may already have answered this. A save flow that offered the
    // three launches in the sheet that asked *how many* has taken exactly
    // this decision, and asking it a second time here was the second modal on
    // a path that is supposed to have none (docs/V2_SAVE_FLOW.md §4).
    // What the user asked for, not what the queue happens to hold: a
    // sequential capture writes one row at a time and finds the rest as it
    // goes (V2-D56).
    final journeyed = ref.read(queueRunnerProvider).pendingJourneyEntries;
    final n = journeyed > waiting.length ? journeyed : waiting.length;
    final choice = switch (decided) {
      StartWhere.inBrowser => StartChoice.inBrowser,
      StartWhere.keepWorking => StartChoice.keepUsingApp,
      null => await showStartOptionsSheet(
        context: context,
        ref: ref,
        action: ForegroundGateAction.startQueuedSaves,
        title: n == 1
            ? 'Start the waiting download?'
            : 'Start $n waiting downloads?',
        summary:
            'Each page has to be read in the Browser before its images can be '
            'downloaded. Nothing runs once you close the app.',
      ),
    };
    // Dismissed, or *Not now*: nothing was authorised.
    if (choice == null || !mounted) return;

    if (choice == StartChoice.enableAndKeepUsingApp) {
      await setKeepWorkingPreference(ref, true);
      if (!mounted) return;
    }

    // Browser first, automation second — never the other way round. With the
    // capability chosen the surface is still brought up, but the *user* is
    // left where they are; that is the whole of the difference.
    if (!await _ensureBrowserVisible(
      forceVisible: choice == StartChoice.inBrowser,
    )) {
      return;
    }
    // Through the one lane. A check reading a listing holds the Browser, and
    // the run waits for it rather than navigating the page out from under it —
    // the rows are already written, so nothing is lost by waiting. The user
    // has already been told which of the two happened: `startQueuedDownloads`
    // says *starting* or *queued* from the state of this same lane.
    await ref
        .read(operationLaneProvider)
        .submit(
          key: kDownloadWorkKey,
          label: kDownloadWorkLabel,
          body: ref.read(queueRunnerProvider).start,
        );
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
  Future<bool> _ensureBrowserVisible({
    String? url,
    bool forceVisible = false,
  }) async {
    if (!mounted) return false;
    // Stored before the tab switch, exactly as "open in Browser" does: the
    // Browser drains it when it is mounted with an attached WebView, so
    // nothing is lost to the pop or to a WebView that is not there yet.
    final target = url?.trim() ?? '';
    if (target.isNotEmpty) ref.read(browserNavigatorProvider).request(target);
    if (_capability.enabled && !forceVisible) {
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
    _browserPresentation.removeListener(_onBrowserChromeChanged);
    _queueRunner.removeListener(_onAutomationChanged);
    _sourceCheck.removeListener(_onAutomationChanged);
    _tabRequest.removeListener(_onTabRequested);
    _cleanup.removals.removeListener(_onStorageChanged);
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
      _index == 1 &&
      (_queueRunner.needsRenderedBrowser || _sourceCheck.isRunning);

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
      progressLine: _queueRunner.isRunning
          ? 'Saving an entry'
          : 'Checking for new entries',
    );
    if (choice != LeaveChoice.pauseAndLeave) return false;
    // Nothing to pause explicitly: the ported engine's own render guards hold
    // a capture the moment its surface stops painting, and resume when it
    // returns — the same hardware-validated behaviour the V1 pause wrapped.
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
    final busy = _queueRunner.isRunning || _sourceCheck.isRunning;
    // A real owner has appeared: the start claim has done its job.
    if (busy) _releaseSurfaceClaim();
    // Work the user can watch outranks reading with the chrome away: the
    // panel, the tab bar and the toolbar all come back for the duration. It
    // also keeps the Browser's viewport still while a phase is measuring one
    // — the only other way to change it mid-run is a tab switch, and the bar
    // this restores is what the shell lays the Browser out around.
    if (busy && !_wasBusy) _browserPresentation.setChromeHidden(false);
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
    // The engine resumes on its own once the surface paints again.
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
              Offstage(offstage: _index != 0, child: const ShelfScreen()),
            ],
          ),
          // The tab bar goes with the Browser's own toolbar while a website
          // is being read with the chrome hidden: half a chrome is not the
          // screen space that was asked for, and the Browser draws the one
          // control that brings both back. Only ever on the Browser tab — the
          // Library never loses its bar. Null rather than a zero-height box,
          // so the body keeps the bottom safe-area inset the bar was
          // consuming and nothing lands under the home indicator.
          bottomNavigationBar: _index == 1 && _browserChromeHidden
              ? null
              : _BottomNav(index: _index, onSelect: _select),
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
