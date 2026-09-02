import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../browser/browser_controller.dart';
import '../browser/browser_navigator.dart';
import '../browser/browser_presentation.dart';
import '../browser/browser_url.dart';
import '../core/url_utils.dart';
import '../library_ui/entry_offline.dart';
import '../save/capture_policy.dart';
import '../core/config.dart';
import '../core/connectivity.dart';
import '../providers.dart';
import '../ui/palette.dart';
import 'check_controller.dart';
import 'selection_overlay.dart';
import 'v2_save_flow.dart';
import '../save/queue_runner.dart';
import '../save/queue_task.dart';
import 'browser_home.dart';
import 'browser_page_actions.dart';
import 'browser_states.dart';
import 'browser_toolbar.dart';
import 'browser_url_editor.dart';
import 'running_operation_panel.dart';
import 'saved_site_sheets.dart';

/// The browser *and* the save surface. One WebView, kept alive and mounted
/// for the whole session: save runs in exactly the environment the user
/// browsed in, and there is something to watch while it works.
///
/// Browser Home and the URL editor are **layers over** that WebView, never
/// replacements for it (D52). Nothing in this file constructs a second
/// `InAppWebView`, and nothing removes the one it has from the tree — which
/// is what makes "open Home, come back, the page is still there, still
/// scrolled, still signed in" true rather than merely likely.
/// The V2 save queue, as the Browser shows it.
final v2SaveTasksProvider = StreamProvider<List<SaveTask>>(
  (ref) => ref.watch(v2ServicesProvider).ui.queue.watch(),
);

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  bool _findOpen = false;
  BrowserController? _browser;
  BrowserPresentation? _presentation;
  BrowserNavigator? _navigator;
  late final String _initialUrl;

  /// True while a post-frame drain is already scheduled, so the three things
  /// that can trigger one (a new request, a WebView attach, a rebuild) do not
  /// schedule three.
  bool _drainScheduled = false;

  /// The page identity everything transient on this screen is scoped to (D59).
  ///
  /// Not a convenience copy of the URL: it is what distinguishes "the page
  /// changed" from "the same page said something again". When it moves, every
  /// transient thing the Browser was showing about the previous page goes with
  /// it — result banners, the panel, the offline lookup, the log drawer.
  int _pageSession = -1;
  String _pageKey = '';

  /// What this page already holds locally, looked up once per page session.
  /// Null while unknown — which is also the honest answer for a page nobody
  /// has ever saved.
  V2PageStatus? _pageEntryState;

  /// Whether the restricted-site capture policy covers the page on screen.
  ///
  /// Recomputed with the page session, which is what makes it follow every
  /// navigation, redirect, reload and history move: the session moves whenever
  /// the address does, and this is derived from the address alone.
  bool _captureRestricted = false;

  @override
  void initState() {
    super.initState();
    _initialUrl = widget.initialUrl ?? kBrowserStartUrl;
    // A cold start has no page, so the toolbar's address field and the
    // blank WebView would both be empty. Browser Home is the designed
    // first-run surface, and it is where the last visited page lives (D57).
    if (!_hasRealPage(_initialUrl)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final presentation = ref.read(browserPresentationProvider);
        // ...unless something is already on its way here. Opening Home over
        // a page the user explicitly asked for is the bug this whole flow
        // exists to fix.
        if (ref.read(browserNavigatorProvider).hasPending) return;
        if (presentation.surface == BrowserSurface.website &&
            !_hasRealPage(ref.read(browserProvider).currentUrl)) {
          presentation.openHome();
        }
      });
    }
  }

  static bool _hasRealPage(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final browser = ref.read(browserProvider);
    if (!identical(browser, _browser)) {
      _browser?.removeListener(_onBrowserChanged);
      _browser = browser..addListener(_onBrowserChanged);
    }
    final presentation = ref.read(browserPresentationProvider);
    if (!identical(presentation, _presentation)) {
      _presentation?.removeListener(_onPresentationChanged);
      _presentation = presentation..addListener(_onPresentationChanged);
    }
    final navigator = ref.read(browserNavigatorProvider);
    if (!identical(navigator, _navigator)) {
      _navigator?.removeListener(_scheduleDrain);
      _navigator = navigator..addListener(_scheduleDrain);
    }
    // A request may already be waiting — this screen can be built *because*
    // of one.
    _scheduleDrain();
  }

  /// Keep the preserved-page snapshot current so Browser Home can offer a way
  /// back to whatever is actually loaded — including the entry hops an
  /// autonomous run makes.
  void _onBrowserChanged() {
    final browser = _browser;
    if (browser == null) return;
    // An attach is one of the two things a pending request waits for.
    _scheduleDrain();
    _syncPageSession(browser);
    final url = browser.currentUrl;
    if (url.isEmpty) return;
    _presentation?.rememberPage(PreservedPage(url: url, title: browser.title));
  }

  /// The Browser moved to another page: re-scope everything transient to it.
  ///
  /// This is the whole of "reset on navigation" (D59). It does not reach into
  /// the save run — a running run is not this screen's to reset, and an
  /// automation hop between entries lands here exactly like a manual one:
  /// the *presentation* follows the page, the *run* is untouched.
  void _syncPageSession(BrowserController browser) {
    if (browser.pageSession == _pageSession) return;
    _pageSession = browser.pageSession;
    _pageKey = browser.pageSessionKey;
    _pageEntryState = null;
    // Both the session's canonical key and the live address: a page whose key
    // could not be formed still has a host, and the policy is about the host.
    _captureRestricted =
        isCaptureRestricted(_pageKey) ||
        isCaptureRestricted(browser.currentUrl);
    unawaited(_loadPageEntryState(_pageSession, _pageKey));
    if (mounted) setState(() {});
  }

  /// Read this page's own saved/offline metadata — separately from any run,
  /// and discarded if the page moves on while the read is in flight.
  Future<void> _loadPageEntryState(int session, String pageKey) async {
    if (pageKey.isEmpty) return;
    final result = await v2PageStatusFor(
      ref,
      ref.read(browserProvider).currentUrl,
    );
    if (!mounted || session != _pageSession) return;
    setState(() => _pageEntryState = result);
  }

  void _onPresentationChanged() {
    if (mounted) setState(() {});
  }

  /// Drain after the current frame.
  ///
  /// Deferred, not delayed: draining calls `showWebsite()`, which notifies
  /// listeners and calls `setState` — illegal during a build, and
  /// `didChangeDependencies` is part of one. The wait is for the frame to
  /// end, never for a duration.
  void _scheduleDrain() {
    if (_drainScheduled || !mounted) return;
    final navigator = _navigator;
    if (navigator == null || !navigator.hasPending) return;
    _drainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      _drainPendingOpen();
    });
  }

  /// Hand a waiting request to the WebView, exactly once.
  ///
  /// Held back until the WebView is attached: a load into an unattached
  /// controller is silently dropped, which is precisely how the old flow lost
  /// the URL. Nothing polls — [_onBrowserChanged] fires on attach and brings
  /// us straight back here.
  void _drainPendingOpen() {
    if (!mounted) return;
    final navigator = _navigator;
    final browser = _browser;
    if (navigator == null || browser == null) return;

    PendingOpenDrainer(
      navigator: navigator,
      presentation: ref.read(browserPresentationProvider),
      isAttached: () => browser.isAttached,
      reveal: ref.read(browserPresentationProvider).showWebsite,
      load: (url) => unawaited(browser.load(url)),
    ).drain();
  }

  @override
  void dispose() {
    _browser?.removeListener(_onBrowserChanged);
    _presentation?.removeListener(_onPresentationChanged);
    _navigator?.removeListener(_scheduleDrain);
    super.dispose();
  }

  // --- navigation ----------------------------------------------------------

  BrowserPresentation get _p => ref.read(browserPresentationProvider);

  /// Opening a local surface hides the rendered page, so it goes through the
  /// same guard as leaving the Browser entirely (§15). Nothing is paused
  /// unless the user chooses to.
  Future<void> _openHome() async {
    if (!await LeaveBrowserGuard.confirmLeave(context)) return;
    if (!mounted) return;
    final browser = ref.read(browserProvider);
    _p.openHome(
      preserving: PreservedPage(url: browser.currentUrl, title: browser.title),
    );
  }

  void _openAddressEditor({bool fromHome = false}) {
    final browser = ref.read(browserProvider);
    final url = browser.currentUrl;
    _p.openAddressEditor(
      // From Home the field starts blank, as drawn; from a page it starts
      // with the whole URL, selected, so typing replaces it (§6).
      draft: fromHome ? '' : url,
      selectAll: !fromHome && url.isNotEmpty,
    );
  }

  /// Open [url] in the existing WebView. Never creates one.
  Future<void> _openUrl(String url, [String title = '']) async {
    final browser = ref.read(browserProvider);
    _p.showWebsite();
    await browser.load(url);
  }

  Future<void> _submitAddress(String text) async {
    final browser = ref.read(browserProvider);
    _p.showWebsite();
    final intent = await browser.open(text);
    if (!mounted) return;
    if (isExternalAppScheme(intent.url)) {
      // Classified, not loaded — the banner offers the handoff.
      return;
    }
  }

  Future<void> _goBack() async {
    final browser = ref.read(browserProvider);
    // Back closes a local surface first: the page it is covering is what the
    // user means by "back" while Home is up.
    if (_p.isEditingAddress) {
      _p.closeAddressEditor();
      return;
    }
    if (_p.isHome) {
      _p.showWebsite();
      return;
    }
    if (browser.canGoBack) {
      await browser.goBack();
      return;
    }
    // Nothing left in the page's history and no overlay: this is a request
    // to leave the Browser, and the save guard owns that decision.
    if (!await LeaveBrowserGuard.confirmLeave(context)) return;
    if (!mounted) return;
    ref.read(shellTabRequestProvider).value = 0;
  }

  Future<void> _openHistory() async {
    if (!await LeaveBrowserGuard.confirmLeave(context)) return;
    if (!mounted) return;
    context.push('/history');
  }

  Future<void> _addSavedSite() async {
    await showAddSavedSiteSheet(context);
  }

  Future<void> _saveCurrentPage({String? url, String? title}) async {
    final browser = ref.read(browserProvider);
    final target = url ?? browser.currentUrl;
    if (target.trim().isEmpty) return;
    await showSaveSiteSheet(
      context,
      url: target,
      title: (title ?? browser.title).trim().isEmpty
          ? displayHost(target)
          : (title ?? browser.title),
    );
  }

  Future<void> _openPageActions() async {
    final browser = ref.read(browserProvider);
    final url = browser.currentUrl;
    if (url.trim().isEmpty) return;
    final action = await showPageActionsSheet(
      context: context,
      ref: ref,
      url: url,
      title: browser.title,
      canSave: !_captureRestricted,
    );
    if (!mounted) return;
    switch (action) {
      case PageAction.save:
        await _showSaveSheet(context);
      case PageAction.addToSavedSites:
        await _saveCurrentPage();
      case PageAction.findInPage:
        // Find sits where the toolbar was, so it ends immersive reading
        // rather than appearing over a page with no chrome around it.
        _p.setChromeHidden(false);
        setState(() => _findOpen = true);
      case PageAction.none:
        break;
    }
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final browser = ref.watch(browserProvider);
    final presentation = ref.watch(browserPresentationProvider);
    final runner = ref.watch(queueRunnerProvider);
    final sourceCheck = ref.watch(checkControllerProvider);
    final assist = ref.watch(v2AssistProvider);

    // Settings asked for Browser Home from another route; honour it once the
    // Browser is actually on screen.
    if (presentation.consumeHomeRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPresentationChanged();
      });
    }
    // A page can arrive before any listener fires (first build, a restored
    // session): keep the scope in step without waiting for a notification.
    if (browser.pageSession != _pageSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPageSession(browser);
      });
    }

    // Read once, here, in the build that owns this ref — the pieces below
    // rebuild from Listenables, and a `watch` from inside one of those
    // callbacks is a dependency registered outside its widget's build.
    final tasks = ref.watch(v2SaveTasksProvider).value ?? const [];
    final pageIsQueued = tasks.any(
      (t) => !t.state.isTerminal && normalizeUrl(t.locationUrl) == _pageKey,
    );
    final waitingSaves = tasks
        .where((t) => t.state == SaveTaskState.queued)
        .length;

    // Reading a website with nothing around it. The state is the
    // presentation's, because the shell's tab bar goes with the toolbar and
    // the shell cannot see inside this screen — one flag, so the two halves
    // of the chrome can never disagree. What is *offered* is this screen's:
    // Find sits where the toolbar was, and a page that is not a page has
    // nothing to read.
    final chromeHidden = presentation.chromeHidden;
    final canHideChrome =
        presentation.surface == BrowserSurface.website &&
        !_findOpen &&
        _hasRealPage(browser.currentUrl);

    return Scaffold(
      backgroundColor: palette.surfaceMuted,
      body: SafeArea(
        bottom: false,
        // The docked layers below the WebView are budgeted against the height
        // this Column actually has. Without that budget the selection sheet's
        // fixed 420, the running panel and the toolbar together exceed every
        // phone, the WebView's `Expanded` resolves to **zero**, and the app
        // asks the user to tap an Entry on a page it is no longer drawing.
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (!chromeHidden)
                BrowserToolbar(
                  browser: browser,
                  homeActive: presentation.isHome,
                  onBack: _goBack,
                  onForward: browser.canGoForward ? browser.goForward : null,
                  onAddress: () => _openAddressEditor(),
                  onReloadOrStop: () => browser.isLoading
                      ? browser.stopLoading()
                      : browser.reload(),
                  onHome: _openHome,
                ),
              if (_findOpen)
                FindInPageBar(
                  browser: browser,
                  onClose: () => setState(() => _findOpen = false),
                ),
              _HostChangeBanner(browser: browser),
              _PageStateBanner(
                browser: browser,
                onRetry: browser.reload,
                onEditAddress: () => _openAddressEditor(),
                onGoHome: _openHome,
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Always in the tree, always laid out at full size. The
                    // layers below cover it; none of them unmount it.
                    _WebViewHost(browser: browser, initialUrl: _initialUrl),
                    _BlockingPageState(
                      browser: browser,
                      onRetry: browser.reload,
                      onEditAddress: () => _openAddressEditor(),
                      onGoHome: _openHome,
                      onOpenLibrary: () =>
                          ref.read(shellTabRequestProvider).value = 0,
                    ),
                    // While a run runs, block stray taps from reaching the page.
                    //
                    // Except while it is *holding for a tap*: the whole of the
                    // assist flow is the user pointing at something in the page,
                    // and a veil over it would swallow the one gesture the run is
                    // waiting for. The page is in the bridge's element-picking
                    // mode by then, which swallows the tap itself rather than
                    // letting it navigate — so nothing here is loosened, the job
                    // has simply moved to the layer that can tell a teaching tap
                    // from a stray one.
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        runner,
                        sourceCheck,
                        assist,
                      ]),
                      builder: (context, _) =>
                          (runner.isRunning || sourceCheck.isRunning) &&
                              assist.pendingSelection == null
                          ? Positioned.fill(
                              child: AbsorbPointer(
                                child: ColoredBox(color: palette.veil),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    BrowserSaveActions(
                      runner: runner,
                      sourceCheck: sourceCheck,
                      pageStatus: _pageEntryState,
                      pageIsQueued: pageIsQueued,
                      captureRestricted: _captureRestricted,
                      waitingSaves: waitingSaves,
                      chromeHidden: chromeHidden,
                      canHideChrome: canHideChrome,
                      onToggleChrome: () =>
                          _p.setChromeHidden(!presentation.chromeHidden),
                      onSave: () => _showSaveSheet(context),
                      onPageActions: _openPageActions,
                      onViewLibrary: () =>
                          ref.read(shellTabRequestProvider).value = 0,
                    ),
                    if (presentation.isHome)
                      Positioned.fill(
                        child: BrowserHome(
                          preserved: presentation.preserved,
                          onClose: _p.showWebsite,
                          onOpenAddressEditor: () =>
                              _openAddressEditor(fromHome: true),
                          onOpenUrl: _openUrl,
                          onOpenHistory: _openHistory,
                          onAddSite: _addSavedSite,
                          onEditSite: (site) => showSaveSiteSheet(
                            context,
                            url: site.url,
                            title: site.title,
                            editingId: site.id,
                            offerSiteRoot: false,
                          ),
                        ),
                      ),
                    if (presentation.isEditingAddress)
                      Positioned.fill(
                        child: BrowserUrlEditor(
                          initialText: presentation.addressDraft,
                          selectAll: presentation.selectAllOnOpen,
                          currentPageUrl: browser.currentUrl,
                          onSubmit: _submitAddress,
                          onCancel: () => _p.closeAddressEditor(
                            // Cancelling out of an editor opened from Home
                            // returns to Home, not to the page behind it.
                            toHome:
                                presentation.addressDraft.isEmpty &&
                                presentation.preserved != null,
                          ),
                          onSaveSite: (url, title) =>
                              _saveCurrentPage(url: url, title: title),
                        ),
                      ),
                  ],
                ),
              ),
              // A run holding for the user, asked **here**.
              //
              // The save sheet renders the same overlay while it is open, but a
              // journey outlives it by design: the sheet answers, closes, and the
              // Browser performs the Start. So the surface the *Needs you* pill
              // sends people to has to be able to ask as well, or a walk that
              // stops to ask holds against a controller nothing is drawing.
              //
              // Docked below the page rather than over it, for the same reason
              // the run panel is: the element being pointed at is in the page,
              // and a sheet across the middle of it hides the control the user
              // is being asked to find.
              AnimatedBuilder(
                animation: assist,
                builder: (context, _) {
                  final request = assist.pendingSelection;
                  if (request == null) return const SizedBox.shrink();
                  return RuleSelectionOverlay(
                    run: assist,
                    request: request,
                    // The page keeps the majority; this sheet lives in what is
                    // left, and the running panel folds to its holding line
                    // underneath rather than competing for the same strip.
                    maxHeight: math.min(
                      kAssistOverlayMaxHeight,
                      constraints.maxHeight * kAssistSheetShare,
                    ),
                  );
                },
              ),
              // Docked under the WebView, never over it: while this app drives
              // the Browser the user can see what it is doing and end it.
              const RunningOperationPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSaveSheet(BuildContext context) async {
    // The control that leads here is absent on a restricted page, so this is
    // the belt to those braces: the sheet cannot be opened by a stale
    // callback, a race with a navigation, or any future caller.
    if (_captureRestricted) return;
    final browser = ref.read(browserProvider);
    final url = browser.currentUrl;
    if (url.isEmpty) return;
    final start = await showModalBottomSheet<SaveSheetStart>(
      context: context,
      // The panel is as tall as what it has to say — a Collection's context,
      // the ranges, and the sentence explaining what each one writes. Left at
      // the default it would be capped near half the screen and the choice
      // between adding to a Collection and saving loose would be below the
      // fold, which is where this flow went wrong the first time.
      isScrollControlled: true,
      builder: (_) => V2SavePanel(url: url, pageTitle: browser.title),
    );
    if (!mounted) return;
    // The Start the sheet asked for, run **after** it has closed, from the
    // surface the run itself needs. `startQueuedDownloads` does not return
    // until the batch is done, so a sheet that awaited it stayed on top of the
    // Browser for the whole run — visibly so for *Start and keep using
    // Scrollary*, whose promise is that the user carries straight on
    // ([SaveSheetStart]).
    if (start != null) {
      await startQueuedDownloads(this.context, ref, decided: start.where);
      if (!mounted) return;
    }
    unawaited(_loadPageEntryState(_pageSession, _pageKey));
  }
}

/// The Browser's floating controls over the page: hide-the-chrome, page
/// actions, and the save action.
///
/// Public only so it can be exercised in a widget test — `BrowserScreen`
/// itself embeds a real platform WebView and cannot be pumped.
class BrowserSaveActions extends StatelessWidget {
  const BrowserSaveActions({
    super.key,
    required this.runner,
    required this.sourceCheck,
    required this.pageStatus,
    required this.pageIsQueued,
    required this.captureRestricted,
    required this.waitingSaves,
    required this.chromeHidden,
    required this.canHideChrome,
    required this.onToggleChrome,
    required this.onSave,
    required this.onPageActions,
    required this.onViewLibrary,
  });

  final QueueRunner runner;
  final CheckController sourceCheck;
  final V2PageStatus? pageStatus;
  final bool pageIsQueued;
  final bool captureRestricted;
  final int waitingSaves;

  /// True while the toolbar is out of the tree and the page has the screen.
  final bool chromeHidden;

  /// Whether hiding is on offer at all — a page is on screen and no local
  /// surface is covering it.
  final bool canHideChrome;
  final VoidCallback onToggleChrome;
  final VoidCallback onSave;
  final VoidCallback onPageActions;
  final VoidCallback onViewLibrary;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([runner, sourceCheck]),
      builder: (context, _) {
        final running = runner.isRunning || sourceCheck.isRunning;
        // On a restricted page the save control is not drawn at all — and
        // neither is the gap it would have left. Page actions keep their
        // position on the right, so nothing else on screen moves or reserves
        // space for something that is not there.
        final offersCapture = !captureRestricted;
        final hasCopy = pageStatus?.hasCopy ?? false;

        // With the chrome hidden the page is the whole screen and this is the
        // only control left. It is never conditional on anything else — a way
        // back to the toolbar that could itself disappear would be a trap, so
        // it stays drawn while a run runs, on a restricted host, and on a page
        // that failed to load.
        if (chromeHidden) {
          return Positioned(
            right: 14,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: _RoundAction(
              actionKey: const ValueKey('browserShowChrome'),
              icon: Icons.visibility_outlined,
              tooltip: 'Show browser controls',
              dimmed: true,
              onPressed: onToggleChrome,
            ),
          );
        }

        return Positioned(
          left: 14,
          right: 14,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (waitingSaves > 0 && !running) ...[
                _QueuedSavesChip(
                  count: waitingSaves,
                  onViewLibrary: onViewLibrary,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!running) ...[
                    // Page actions, then hide, then save: the order runs from
                    // the least committal control to the one the user came
                    // for, and the save keeps the corner under the thumb.
                    _RoundAction(
                      actionKey: const ValueKey('browserPageActions'),
                      icon: Icons.more_horiz,
                      tooltip: 'Page actions',
                      onPressed: onPageActions,
                    ),
                    if (canHideChrome) ...[
                      const SizedBox(width: 8),
                      _RoundAction(
                        actionKey: const ValueKey('browserHideChrome'),
                        icon: Icons.visibility_off_outlined,
                        tooltip: 'Hide browser controls',
                        onPressed: onToggleChrome,
                      ),
                    ],
                    if (offersCapture) const SizedBox(width: 8),
                  ],
                  // Not drawn at all while a run runs — it is the save, and
                  // the save is not available while this app is driving the
                  // Browser. It used to stay, wearing the downloading glyph,
                  // and lead to the library instead: a download-looking
                  // control in the save's own place that took the user off
                  // the page they were watching. A run is already visible and
                  // stoppable in the panel docked below the page, so nothing
                  // is lost by its absence — and the other two controls in
                  // this group are gone for the same duration.
                  if (offersCapture && !running)
                    // Icon only: the page is what the user came for, and the
                    // word beside the glyph bought nothing a tooltip and an
                    // accessible name do not. The state still reads — the
                    // glyph and the tint carry it, and the name says it in
                    // words for anyone who cannot see either.
                    //
                    // Same square, radius, lift and glyph size as the two
                    // controls beside it: these are one group, and a control
                    // of a different shape and size reads as belonging to a
                    // different surface. What marks this one as the action
                    // the user came for is the accent tint — the app's own
                    // emphasis, a container and an edge rather than a
                    // saturated fill, so it survives a warm filter and does
                    // not shout over the page.
                    _RoundAction(
                      actionKey: const ValueKey('browserSaveAction'),
                      icon: pageIsQueued
                          ? Icons.schedule
                          : hasCopy
                          ? Icons.download_for_offline
                          : Icons.download,
                      tooltip: _saveLabel(hasCopy),
                      emphasis: true,
                      onPressed: onSave,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// What the control is, in words — the tooltip, and the name assistive
  /// technology reads now that the button carries no text.
  ///
  /// Each line is the state this page is in, then **what this tap does about
  /// it** — and the two halves have to agree. Every line names a save, because
  /// the save is the only thing this control does: while a run runs it is not
  /// drawn at all, so no state is left in which it leads anywhere else. A
  /// queued page used to promise the library here and open the save sheet
  /// instead.
  String _saveLabel(bool hasCopy) => pageIsQueued
      ? 'Waiting to download — save this page'
      : hasCopy
      ? 'On this device — save again'
      : 'Save this page';
}

/// Queued V2 saves, waiting for an explicit Start. Tapping leads to the
/// library, where the queue rows live.
class _QueuedSavesChip extends StatelessWidget {
  const _QueuedSavesChip({required this.count, required this.onViewLibrary});

  final int count;
  final VoidCallback onViewLibrary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('queuedSavesChip'),
        borderRadius: BorderRadius.circular(14),
        onTap: onViewLibrary,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            count == 1 ? '1 download waiting' : '$count downloads waiting',
            style: TextStyle(fontSize: 12, color: palette.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// One control in the floating group over the page. Every control in that
/// group is this widget: same square, same radius, same lift, same glyph
/// size, so the row reads as one thing rather than as parts borrowed from
/// different surfaces. [emphasis] is the only difference on offer.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.actionKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.dimmed = false,
    this.emphasis = false,
  });

  final Key actionKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Drawn back, for the one control that stays over a page being read.
  final bool dimmed;

  /// The accent tone, for the one action in the group the user came for. It
  /// is the app's ordinary emphasis — a container fill and a matching edge,
  /// not a saturated block — so it stays legible under a warm filter and
  /// never outweighs the page it sits on.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: dimmed ? 0.72 : 1,
      child: Tooltip(
        message: tooltip,
        child: SizedBox.square(
          // 48: the smallest square a finger can be asked to find.
          dimension: 48,
          child: Material(
            color: emphasis ? palette.primaryContainer : palette.surface,
            elevation: 2,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: emphasis ? palette.primaryBorder : palette.border,
              ),
            ),
            child: InkWell(
              key: actionKey,
              onTap: onPressed,
              borderRadius: BorderRadius.circular(16),
              child: Icon(
                icon,
                size: 21,
                color: emphasis
                    ? palette.onPrimaryContainer
                    : palette.inkStrong,
                semanticLabel: tooltip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A banner-style page state, shown above the page it is describing.
class _PageStateBanner extends StatelessWidget {
  const _PageStateBanner({
    required this.browser,
    required this.onRetry,
    required this.onEditAddress,
    required this.onGoHome,
  });

  final BrowserController browser;
  final VoidCallback onRetry;
  final VoidCallback onEditAddress;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: browser,
    builder: (context, _) {
      final fault = browser.fault;
      if (fault == null || PageStateView.isBlocking(fault.state)) {
        return const SizedBox.shrink();
      }
      return PageStateView(
        fault: fault,
        actions: switch (fault.state) {
          BrowserPageState.certificate => [
            PageStateAction('Go Home', onGoHome, primary: true),
            PageStateAction('Dismiss', browser.clearFault),
          ],
          BrowserPageState.externalApp => [
            PageStateAction('Stay here', browser.clearFault),
          ],
          _ => [
            PageStateAction('Retry', onRetry, primary: true),
            PageStateAction('Edit address', onEditAddress),
          ],
        },
      );
    },
  );
}

/// A page state that replaces the page, because there is nothing behind it.
class _BlockingPageState extends ConsumerWidget {
  const _BlockingPageState({
    required this.browser,
    required this.onRetry,
    required this.onEditAddress,
    required this.onGoHome,
    required this.onOpenLibrary,
  });

  final BrowserController browser;
  final VoidCallback onRetry;
  final VoidCallback onEditAddress;
  final VoidCallback onGoHome;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnimatedBuilder(
    animation: browser,
    builder: (context, _) {
      final fault = browser.fault;
      if (fault == null || !PageStateView.isBlocking(fault.state)) {
        return const SizedBox.shrink();
      }
      return Positioned.fill(
        child: PageStateView(
          fault: fault,
          blocking: true,
          actions: switch (fault.state) {
            BrowserPageState.offline => [
              PageStateAction('Retry', onRetry, primary: true),
              PageStateAction('Open library', onOpenLibrary),
            ],
            BrowserPageState.invalidAddress => [
              PageStateAction('Edit address', onEditAddress, primary: true),
              PageStateAction('Go Home', onGoHome),
            ],
            _ => [
              PageStateAction('Retry', onRetry, primary: true),
              PageStateAction('Edit address', onEditAddress),
              PageStateAction('Go Home', onGoHome),
            ],
          },
        ),
      );
    },
  );
}

/// The only place an `InAppWebView` widget is constructed.
class _WebViewHost extends StatefulWidget {
  const _WebViewHost({required this.browser, required this.initialUrl});

  final BrowserController browser;
  final String initialUrl;

  @override
  State<_WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<_WebViewHost>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialSettings: BrowserController.settings,
      findInteractionController: widget.browser.findController,
      initialUserScripts: UnmodifiableListView([
        BrowserController.bridgeUserScript,
      ]),
      onWebViewCreated: (controller) {
        widget.browser.attach(controller);
        controller.addJavaScriptHandler(
          handlerName: 'webread.selection',
          callback: (args) {
            if (args.isNotEmpty && args.first is Map) {
              widget.browser.onSelection(
                Map<String, dynamic>.from(args.first as Map),
              );
            }
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final target = action.request.url?.toString();
        if (widget.browser.shouldBlockNavigation(
          target,
          isMainFrame: action.isForMainFrame,
        )) {
          return NavigationActionPolicy.CANCEL;
        }

        // A scheme this Browser cannot render is a handoff, not a page. Named
        // rather than allowed to fail as an opaque platform error (§14).
        if (target != null &&
            (action.isForMainFrame) &&
            isExternalAppScheme(target)) {
          widget.browser.onExternalAppLink(target);
          return NavigationActionPolicy.CANCEL;
        }

        // A page hopping to another host on its own gets asked about. Silence
        // for 5s is a refusal, and the current site keeps running.
        final userInitiated =
            (action.hasGesture ?? false) && !(action.isRedirect ?? false);
        if (widget.browser.needsHostChangeConsent(
          fromUrl: widget.browser.currentUrl,
          toUrl: target,
          isMainFrame: action.isForMainFrame,
          userInitiated: userInitiated,
        )) {
          final allowed = await widget.browser.requestHostChange(
            fromUrl: widget.browser.currentUrl,
            toUrl: target!,
          );
          return allowed
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      // No popups during save — an unrelated top-level window is exactly
      // the kind of navigation a locked run must not follow.
      onCreateWindow: (controller, request) async => false,
      onLoadStart: (_, url) => widget.browser.onLoadStart(url?.toString()),
      onLoadStop: (_, url) => widget.browser.onLoadStop(url?.toString()),
      onProgressChanged: (_, p) => widget.browser.onProgress(p),
      // The page moved. Whether that was a person or a save run enumerating it
      // is not this widget's to know — it is reported and judged one level up.
      onScrollChanged: (_, _, _) => widget.browser.onScrolled?.call(),
      onUpdateVisitedHistory: (_, url, _) =>
          widget.browser.onUrlChanged(url?.toString()),
      onReceivedError: (_, request, error) async {
        if (request.isForMainFrame ?? true) {
          // Whether the device has a connection at all changes "this site is
          // down" into "you are offline", which is a different instruction.
          final online = await hasNetwork();
          widget.browser.onPageFault(
            description: error.description,
            type: error.type.toString(),
            online: online,
          );
        }
      },
      onReceivedHttpError: (_, request, response) {
        if ((request.isForMainFrame ?? true) &&
            (response.statusCode ?? 0) >= 400) {
          widget.browser.onPageFault(statusCode: response.statusCode);
        }
      },
      onConsoleMessage: (_, msg) {
        if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
          debugPrint('[page] ${msg.message}');
        }
      },
      // The page's own process died. Named on both platforms so a run that
      // was reading it fails honestly rather than timing out into a shrug.
      onWebContentProcessDidTerminate: (_) =>
          widget.browser.onRendererTerminated(),
      onRenderProcessGone: (_, _) => widget.browser.onRendererTerminated(),
    );
  }
}

/// Asks before a page takes the browser to a different host.
///
/// Counts down and then refuses. A redirect the user did not ask for should
/// not win by default just because nobody was looking — the current site keeps
/// running instead.
class _HostChangeBanner extends StatefulWidget {
  const _HostChangeBanner({required this.browser});

  final BrowserController browser;

  @override
  State<_HostChangeBanner> createState() => _HostChangeBannerState();
}

class _HostChangeBannerState extends State<_HostChangeBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.browser.addListener(_onBrowserChanged);
  }

  void _onBrowserChanged() {
    final pending = widget.browser.pendingHostChange != null;
    if (pending && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
    } else if (!pending) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.browser.removeListener(_onBrowserChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.browser.pendingHostChange;
    if (request == null) return const SizedBox.shrink();

    final seconds = (request.remaining.inMilliseconds / 1000).ceil();
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              Icons.open_in_new,
              size: 18,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This page wants to open ${request.toHost}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    'Staying on ${request.fromHost} in ${seconds}s',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => widget.browser.resolveHostChange(false),
              child: const Text('Stay'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => widget.browser.resolveHostChange(true),
              child: Text('Allow ($seconds)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the Browser measured about the page before offering to save it.
