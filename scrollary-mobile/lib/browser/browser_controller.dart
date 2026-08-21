import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/url_utils.dart';
import 'bridge_script.dart';
import 'browser_presentation.dart';
import 'browser_url.dart';
import 'history_repository.dart';
import 'page_data.dart';

/// The single boundary between the app and `flutter_inappwebview`.
///
/// Nothing else in `lib/` imports the plugin. Swapping the WebView means
/// reimplementing this class and the injected JS — not touching save,
/// storage, or UI.
class BrowserController extends ChangeNotifier {
  InAppWebViewController? _webView;

  String _currentUrl = '';
  String _title = '';
  bool _isLoading = false;
  double _progress = 0;
  String? _lastError;
  bool _canGoBack = false;
  bool _canGoForward = false;

  final _navigationCompleters = <Completer<void>>[];
  final _selectionController = StreamController<SelectedElement>.broadcast();

  /// While a save run runs, the page may not initiate its own top-level
  /// navigation. A user-selected control is a strong signal about *one* link;
  /// it is not permission to follow whatever the page does next.
  bool navigationLocked = false;
  String? _allowedNavigationUrl;

  /// Who is driving the WebView right now ("a save run", "an update
  /// check"), or null. There is exactly one WebView; two autonomous processes
  /// navigating it at once would corrupt both, so each refuses to start while
  /// the other holds this.
  String? automationOwner;

  /// What kind of navigation the WebView is doing right now.
  ///
  /// Set beside [automationOwner] by whoever takes the WebView. History
  /// recording reads it, and *also* refuses outright while
  /// [automationOwner] is non-null — two independent guards, because a
  /// save flooding the user's history is the failure this exists to
  /// prevent (D53).
  NavigationSource navigationSource = NavigationSource.manual;

  /// True when something other than the user is moving the page.
  bool get isAutomating => automationOwner != null;

  // --- is the app painting this WebView? -----------------------------------

  bool _surfaceIsPainted = true;

  /// Whether the app is currently compositing the WebView.
  ///
  /// **The app is the authority on this, not the page.** Measured on both
  /// platforms (docs/FOREGROUND_MULTITASKING.md §3.1): a WebView the app has
  /// stopped painting keeps reporting a full viewport, keeps accepting
  /// programmatic scrolling, and — on Android — keeps reporting
  /// `document.visibilityState === 'visible'`. What actually degrades is
  /// `requestAnimationFrame`, which stops on iOS and is throttled to about a
  /// fifth of the display rate on Android. That is the mechanism behind the
  /// 2026-07-27 audit's complete-looking, wrong entry, and no signal readable
  /// from inside the page detects it portably.
  ///
  /// So the one widget that hosts the WebView publishes it here, and the
  /// Browser-dependent phases hold while it is false. Defaults to **true**:
  /// a controller nobody has told (a unit test's fake, a harness) is not
  /// making a claim about compositing, and the page-side checks still apply.
  bool get surfaceIsPainted => _surfaceIsPainted;

  /// When [surfaceIsPainted] last became true. Null if it has never changed —
  /// which is the case for every controller nobody wires to a shell.
  DateTime? _paintedSince;

  set surfaceIsPainted(bool value) {
    if (_surfaceIsPainted == value) return;
    _surfaceIsPainted = value;
    if (value) _paintedSince = DateTime.now();
    notifyListeners();
  }

  /// True when the decision to draw is newer than the frames that carry it out.
  ///
  /// Measured on a physical iPhone: a check started from the Reader saw
  /// `surfaceIsPainted == true` immediately — the app had *decided* — and
  /// navigated at once, so the document was still created before the route
  /// opacity, the shell rebuild and the platform-view composition had actually
  /// happened. It was then born hidden and cost the full page-hidden grace,
  /// about six seconds, on every check.
  bool get _paintDecisionIsFresh {
    final since = _paintedSince;
    return since != null &&
        DateTime.now().difference(since) < const Duration(milliseconds: 600);
  }

  /// Wait until the app is drawing the WebView, up to [timeout].
  ///
  /// **Call this before an operation's first navigation.** WebKit fixes a
  /// document's `document.visibilityState` when the document is created, and a
  /// document created in a view that is not being composited starts life
  /// `hidden` — and stays that way even once the view is composited. An
  /// operation that asks for the surface to be drawn and navigates in the same
  /// breath creates exactly that document, and then every visibility-based
  /// check about it is wrong for as long as it exists.
  ///
  /// Measured on a physical iPhone against a real site: a check started while
  /// the Reader was open held for its whole budget and failed, on a page that
  /// was being drawn the entire time. Waiting one or two frames here is what
  /// stops the document being born hidden in the first place.
  ///
  /// Returns whether the surface was painted in the end. **False is not an
  /// error** — with the capability off, or the user genuinely elsewhere, the
  /// caller proceeds and the ordinary render guard does its job.
  Future<bool> awaitPaintedSurface({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // Drawing, and has been for long enough that the frames have landed? Then
    // there is nothing to wait for: a document created now cannot be born
    // hidden. Returning immediately keeps this method invisible to every caller
    // in the common case — which matters, because it sits in front of the first
    // navigation of every operation, and because a controller that no shell
    // ever wired up (a unit test's) is always in exactly this case.
    if (_surfaceIsPainted && !_paintDecisionIsFresh) return true;

    final deadline = DateTime.now().add(timeout);
    while (!_surfaceIsPainted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_surfaceIsPainted) return false;
    // The flag is not the frame. `surfaceIsPainted` flips the moment the app
    // *decides* to draw the WebView, which is one or more frames before the
    // route opacity, the shell rebuild and the platform-view composition have
    // actually happened. A document created in that window is still born
    // hidden — measured on a physical iPhone, where a check claimed the
    // WebView, navigated immediately, and then sat out the whole page-hidden
    // grace before it could read anything.
    //
    // Waiting for real frames costs a few milliseconds and removes the wait
    // that costs seconds.
    //
    // Each wait is bounded, because `endOfFrame` completes only when a frame is
    // actually produced — and there are legitimate states where none is: the
    // app is not in the foreground, or this is a test that does not pump. An
    // unbounded wait here would turn "be careful about the first navigation"
    // into a hang, which is the class of bug this whole method exists to fix.
    // …and the whole thing is optional. This class is a plain `ChangeNotifier`
    // that pure Dart tests construct directly, where there is no binding and
    // therefore no frames at all. Reaching for one must not be able to break a
    // caller: no binding means nothing to wait for.
    try {
      for (var i = 0; i < 3; i++) {
        await SchedulerBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 120),
          onTimeout: () {},
        );
      }
    } catch (_) {
      // No binding in this context.
    }
    return _surfaceIsPainted;
  }

  /// The source a visit landing now should be attributed to.
  ///
  /// While something holds the WebView, `manual` is not an available answer
  /// even if nobody set [navigationSource] — a forgotten assignment degrades
  /// to `internal`, which is excluded from History, rather than to the one
  /// value that would pollute it.
  NavigationSource get effectiveNavigationSource {
    if (!isAutomating) return navigationSource;
    return navigationSource == NavigationSource.manual
        ? NavigationSource.internal
        : navigationSource;
  }

  /// Called once per completed main-frame load. The history repository is
  /// wired to this at bootstrap; the controller itself knows nothing about
  /// storage.
  void Function(BrowserVisit visit)? onVisitCompleted;

  // --- page session identity (D59) ----------------------------------------

  int _pageSession = 0;

  /// Identity of the page currently on screen, as a monotonically increasing
  /// counter.
  ///
  /// Everything the Browser shows *about a page* — a save result, a
  /// preflight summary, an offline badge — is scoped to this number, so a
  /// completed run cannot go on being the state of the next page the user
  /// opens. It changes only for a main-frame page change: asset loads,
  /// sub-frames and hash-only jumps do not reach it (they never produce a
  /// different [pageIdentityKey]), and an address that is not a renderable
  /// page (`about:blank`, `mailto:`) starts no session at all.
  int get pageSession => _pageSession;

  String _pageSessionKey = '';

  /// Canonical identity of the page this session is showing; empty before the
  /// first real page.
  String get pageSessionKey => _pageSessionKey;

  NavigationSource _pageSessionSource = NavigationSource.manual;

  /// Who moved the Browser onto this page. Automation moving the page forward
  /// is a page change like any other for *presentation* — but it is not the
  /// user browsing, and the running run it belongs to is untouched by it.
  NavigationSource get pageSessionSource => _pageSessionSource;

  /// True when the user is what put this page on screen.
  bool get pageSessionIsManual =>
      _pageSessionSource == NavigationSource.manual && !isAutomating;

  /// Note that the main frame is showing [url]. Idempotent per page.
  void _notePageIdentity(String? url) {
    if (url == null) return;
    final key = pageIdentityKey(url);
    if (key.isEmpty || key == _pageSessionKey) return;
    _pageSessionKey = key;
    _pageSession++;
    _pageSessionSource = effectiveNavigationSource;
  }

  /// Test seam: drive a page change without a WebView.
  @visibleForTesting
  void debugEnterPage(String url) => _notePageIdentity(url);

  /// Hosts the user has explicitly allowed this session to leave for.
  final Set<String> _allowedHostChanges = {};

  /// A cross-host navigation waiting on the user. Null when nothing is pending.
  HostChangeRequest? _pendingHostChange;
  HostChangeRequest? get pendingHostChange => _pendingHostChange;

  /// How long the prompt waits before denying. Silence means "stay here" —
  /// a redirect the user did not ask for should not win by default.
  static const Duration hostChangeTimeout = Duration(seconds: 5);

  /// Elements the user taps while in selection mode.
  Stream<SelectedElement> get selections => _selectionController.stream;

  bool _selectionActive = false;
  bool get isSelecting => _selectionActive;

  String get currentUrl => _currentUrl;
  String get title => _title;
  bool get isLoading => _isLoading;
  double get progress => _progress;
  String? get lastError => _lastError;
  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;
  bool get isAttached => _webView != null;

  /// Registered at document start so `__wr` exists for Web Inspector poking.
  /// Bridge calls do not depend on it — they carry their own preamble.
  static final UserScript bridgeUserScript = UserScript(
    source: kBridgePreamble,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
  );

  static InAppWebViewSettings get settings => InAppWebViewSettings(
    javaScriptEnabled: true,
    // Needed so navigation can be vetoed while a run is running.
    useShouldOverrideUrlLoading: true,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    // Non-incognito and never cleared: the session the user browsed with
    // is the session save runs in.
    incognito: false,
    cacheEnabled: true,
    mediaPlaybackRequiresUserGesture: true,
    transparentBackground: false,
    // iOS 16.4+ requires this opt-in for Safari Web Inspector.
    isInspectable: kDebugMode,
    allowsInlineMediaPlayback: true,
  );

  /// Allow exactly one upcoming navigation (the entry the run chose).
  void allowNextNavigation(String url) => _allowedNavigationUrl = url;

  /// Veto policy for `shouldOverrideUrlLoading`. Returns true to block.
  bool shouldBlockNavigation(String? url, {required bool isMainFrame}) {
    if (!navigationLocked || !isMainFrame || url == null) return false;
    final allowed = _allowedNavigationUrl;
    if (allowed == null) return true;
    if (url == allowed) return false;
    // Redirects within the allowed target's origin+path prefix are fine; a
    // jump elsewhere is not.
    final a = Uri.tryParse(allowed);
    final b = Uri.tryParse(url);
    if (a == null || b == null) return true;
    return a.host.toLowerCase() != b.host.toLowerCase();
  }

  /// Does leaving [fromUrl] for [toUrl] need the user's say-so?
  ///
  /// Only for navigation the *page* started — a tap the user made is already
  /// their decision. A redirect that hops to another host is the case worth
  /// interrupting for.
  bool needsHostChangeConsent({
    required String? fromUrl,
    required String? toUrl,
    required bool isMainFrame,
    required bool userInitiated,
  }) {
    if (!isMainFrame || toUrl == null) return false;
    final to = Uri.tryParse(toUrl);
    if (to == null || to.host.isEmpty) return false;
    if (to.scheme != 'http' && to.scheme != 'https') return false;

    final from = Uri.tryParse(fromUrl ?? _currentUrl);
    final fromHost = from?.host.toLowerCase() ?? '';
    final toHost = to.host.toLowerCase();
    if (fromHost.isEmpty || fromHost == toHost) return false;
    if (_allowedHostChanges.contains(toHost)) return false;
    // A deliberate tap during ordinary browsing is not something to nag about.
    if (userInitiated && !navigationLocked) return false;
    return true;
  }

  /// Ask, and wait. Times out into a refusal.
  Future<bool> requestHostChange({
    required String fromUrl,
    required String toUrl,
  }) async {
    final toHost = Uri.tryParse(toUrl)?.host.toLowerCase() ?? toUrl;
    final request = HostChangeRequest(
      fromHost: Uri.tryParse(fromUrl)?.host ?? fromUrl,
      toHost: toHost,
      targetUrl: toUrl,
      deadline: DateTime.now().add(hostChangeTimeout),
    );
    _pendingHostChange = request;
    notifyListeners();

    bool decided;
    try {
      decided = await request.completer.future.timeout(
        hostChangeTimeout,
        onTimeout: () => false,
      );
    } catch (_) {
      decided = false;
    }

    if (decided) _allowedHostChanges.add(toHost);
    _pendingHostChange = null;
    notifyListeners();
    return decided;
  }

  void resolveHostChange(bool allow) {
    final request = _pendingHostChange;
    if (request == null) return;
    if (!request.completer.isCompleted) request.completer.complete(allow);
  }

  /// Forget the session's allow-list (used when a save run starts, so a
  /// decision made while browsing does not silently widen an autonomous run).
  void clearAllowedHostChanges() => _allowedHostChanges.clear();

  // --- wiring from the widget -------------------------------------------

  /// The WebView is live.
  ///
  /// Notifying matters: a page waiting to be shown is waiting on exactly this
  /// (see `PendingOpenDrainer`). There is deliberately no queued-URL field
  /// here any more — holding a pending page in *two* places was how one of
  /// them ended up being the one nobody drained. The Browser owns that
  /// contract now, in one place, with the tab switch and the local surfaces
  /// it also has to coordinate (D60).
  void attach(InAppWebViewController controller) {
    _webView = controller;
    notifyListeners();
  }

  void detach() {
    _webView = null;
    notifyListeners();
  }

  void onLoadStart(String? url) {
    _isLoading = true;
    _lastError = null;
    _fault = null;
    // A load that starts is the previous load's error going away, and the
    // start of the URL this navigation was *asked* for — kept so a redirect
    // to a different address is visible as one.
    _requestedUrl = url ?? _requestedUrl;
    if (url != null) _currentUrl = url;
    // The main frame is committing to a different document: whatever the
    // Browser was saying about the previous page stops being true here (D58).
    _notePageIdentity(url);
    notifyListeners();
  }

  Future<void> onLoadStop(String? url) async {
    final hadError = _fault != null;
    _isLoading = false;
    _progress = 1;
    if (url != null) _currentUrl = url;
    // A redirect chain resolves here; the landing page is the page.
    _notePageIdentity(url);
    String? iconUrl;
    try {
      _title = await _webView?.getTitle() ?? _title;
      await _refreshHistory();
      iconUrl = await _readPageIcon();
    } catch (_) {
      // The platform view can be mid-teardown (tab disposed, app shutting
      // down); a closed channel here must not surface as an error.
    }
    _pageIconUrl = iconUrl;

    // Only a load that finished without a fault is a destination. An error
    // page the user never wanted is not somewhere they went (§7).
    if (!hadError && _currentUrl.isNotEmpty) {
      onVisitCompleted?.call(
        BrowserVisit(
          url: _currentUrl,
          title: _title,
          source: effectiveNavigationSource,
          requestedUrl: _requestedUrl,
          iconUrl: iconUrl,
        ),
      );
    }

    notifyListeners();
    for (final c in _navigationCompleters) {
      if (!c.isCompleted) c.complete();
    }
    _navigationCompleters.clear();
  }

  void onProgress(int p) {
    _progress = p / 100;
    notifyListeners();
  }

  void onError(String message) {
    _isLoading = false;
    _lastError = message;
    notifyListeners();
    for (final c in _navigationCompleters) {
      if (!c.isCompleted) c.complete();
    }
    _navigationCompleters.clear();
  }

  /// A classified main-frame failure, ready for the design's error copy.
  ///
  /// Kept separate from [lastError], which stays the raw platform string —
  /// the user gets the classification, diagnostics keep the original (§14).
  BrowserPageFault? _fault;
  BrowserPageFault? get fault => _fault;

  /// The address this navigation was asked for, before any redirect.
  String _requestedUrl = '';
  String get requestedUrl => _requestedUrl;

  /// The icon the current page declared, if any.
  String? _pageIconUrl;
  String? get pageIconUrl => _pageIconUrl;

  /// True while the connection is one we would let a save run on.
  bool get isSecure =>
      _currentUrl.startsWith('https://') &&
      _fault?.state != BrowserPageState.certificate;

  /// The page's own process died — iOS `onWebContentProcessDidTerminate`,
  /// Android `onRenderProcessGone`.
  ///
  /// Named rather than left to be discovered as a timeout, because the two
  /// look identical from the Dart side and mean different things: the document
  /// is gone, whatever was measured about it a second ago is no longer true,
  /// and nothing read after this may be treated as the page. An operation in
  /// flight finds out through the failing probe that follows and ends the
  /// entry — a terminated renderer is never a completion.
  void onRendererTerminated() {
    _isLoading = false;
    _fault = BrowserPageFault(
      state: BrowserPageState.unavailable,
      detail: 'the page stopped responding and was reloaded by the system',
      url: _currentUrl,
    );
    notifyListeners();
    for (final c in _navigationCompleters) {
      if (!c.isCompleted) c.complete();
    }
    _navigationCompleters.clear();
  }

  /// Record a classified failure for the current page.
  void onPageFault({
    String description = '',
    String type = '',
    int? statusCode,
    bool online = true,
  }) {
    final state = classifyPageError(
      description: description,
      type: type,
      statusCode: statusCode,
      online: online,
    );
    _isLoading = false;
    final detail = statusCode != null
        ? 'HTTP $statusCode'
        : [type, description].where((s) => s.isNotEmpty).join(' · ');
    _lastError = detail;
    _fault = BrowserPageFault(
      state: state,
      detail: detail,
      url: _currentUrl.isEmpty ? _requestedUrl : _currentUrl,
    );
    notifyListeners();
    for (final c in _navigationCompleters) {
      if (!c.isCompleted) c.complete();
    }
    _navigationCompleters.clear();
  }

  /// The user dismissed an error banner, or is retrying.
  void clearFault() {
    if (_fault == null && _lastError == null) return;
    _fault = null;
    _lastError = null;
    notifyListeners();
  }

  /// A link the Browser will not follow itself (`mailto:`, `reader://`).
  /// Recorded so the page-state banner can offer the handoff explicitly
  /// rather than the tap doing nothing.
  void onExternalAppLink(String url) {
    _fault = BrowserPageFault(
      state: BrowserPageState.externalApp,
      detail: url,
      url: url,
    );
    notifyListeners();
  }

  /// Read the page's declared icon. Best effort and never awaited by
  /// anything that matters — a page with no `<link rel="icon">` is normal.
  Future<String?> _readPageIcon() async {
    try {
      final raw = await _call(
        kCallPageIcon,
        timeout: const Duration(seconds: 5),
      );
      final href = raw?.toString().trim();
      return href == null || href.isEmpty ? null : href;
    } catch (_) {
      return null;
    }
  }

  /// A main-frame address change with no document load — `history.pushState`,
  /// a hash jump. Only the first of those is a new page, and
  /// [pageIdentityKey] is what tells them apart.
  void onUrlChanged(String? url) {
    if (url != null) _currentUrl = url;
    _notePageIdentity(url);
    notifyListeners();
  }

  void onSelection(Map<String, dynamic> payload) {
    _selectionController.add(SelectedElement.fromJson(payload));
  }

  Future<void> _refreshHistory() async {
    _canGoBack = await _webView?.canGoBack() ?? false;
    _canGoForward = await _webView?.canGoForward() ?? false;
  }

  // --- navigation --------------------------------------------------------

  /// Load [url].
  ///
  /// Callers that already hold an absolute address (save, checks, a saved
  /// site, a history row) pass it straight through. Free text typed by the
  /// user goes through [interpretUrlInput] first — see [open].
  Future<void> load(String url) async {
    final target = url.trim();
    if (target.isEmpty) return;
    _lastError = null;
    _fault = null;
    _requestedUrl = target;
    await _webView?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  /// Open whatever the user typed: an address, or a search for it.
  ///
  /// Returns the intent so the caller can say what it did ("Search Google
  /// for…") without re-deriving it. An external-app scheme is classified and
  /// **not** loaded — handing a `reader://` link to the WebView produces an
  /// unhelpful platform error, so the banner offers the handoff instead.
  Future<UrlIntent> open(String text) async {
    final intent = interpretUrlInput(text);
    if (intent.isEmpty) return intent;
    if (isExternalAppScheme(intent.url)) {
      onExternalAppLink(intent.url);
      return intent;
    }
    await load(intent.url);
    return intent;
  }

  /// Navigate and wait for the load to settle (or time out). The save
  /// engine does its own readiness checks afterwards — `onLoadStop` is only a
  /// hint, never proof that content has arrived.
  Future<void> loadAndWait(String url, {Duration? timeout}) async {
    final completer = Completer<void>();
    _navigationCompleters.add(completer);
    await load(url);
    await completer.future.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {},
    );
  }

  Future<void> goBack() async => _webView?.goBack();
  Future<void> goForward() async => _webView?.goForward();
  Future<void> reload() async {
    _fault = null;
    _lastError = null;
    await _webView?.reload();
  }

  Future<void> stopLoading() async {
    await _webView?.stopLoading();
    _isLoading = false;
    notifyListeners();
  }

  // --- find in page --------------------------------------------------------

  /// The plugin's own find controller, handed to the `InAppWebView` widget.
  ///
  /// Created here rather than in the widget so find state survives the
  /// Browser Home overlay going up and coming down.
  late final FindInteractionController findController =
      FindInteractionController(
        onFindResultReceived:
            (_, activeMatchOrdinal, numberOfMatches, isDoneCounting) {
              if (!isDoneCounting && numberOfMatches == 0) return;
              _findMatches = numberOfMatches;
              _findActiveMatch = numberOfMatches == 0
                  ? 0
                  : activeMatchOrdinal + 1;
              notifyListeners();
            },
      );

  String _findQuery = '';
  int _findMatches = 0;
  int _findActiveMatch = 0;

  String get findQuery => _findQuery;

  /// How many matches the last search found.
  int get findMatchCount => _findMatches;

  /// 1-based index of the highlighted match, or 0 when there is none.
  int get findActiveMatch => _findActiveMatch;

  Future<void> findAll(String query) async {
    _findQuery = query;
    if (query.trim().isEmpty) {
      await clearFind();
      return;
    }
    _findMatches = 0;
    _findActiveMatch = 0;
    notifyListeners();
    await findController.findAll(find: query);
  }

  Future<void> findNext({bool forward = true}) async {
    if (_findQuery.trim().isEmpty || _findMatches == 0) return;
    await findController.findNext(forward: forward);
  }

  Future<void> clearFind() async {
    _findQuery = '';
    _findMatches = 0;
    _findActiveMatch = 0;
    notifyListeners();
    try {
      await findController.clearMatches();
    } catch (_) {
      // Nothing was highlighted; clearing is idempotent by intent.
    }
  }

  // --- website data --------------------------------------------------------

  /// Clear the app-owned WebView website storage: cookies, local and session
  /// storage, and the HTTP cache.
  ///
  /// Deliberately does **not** touch anything the app owns — saved sites,
  /// history, the library, saved files, reading progress and queue rows
  /// all live in SQLite and are not reachable from here.
  ///
  /// Returns what could not be cleared, so the caller can say so honestly
  /// rather than claiming a clean sweep (§11).
  Future<List<String>> clearWebsiteData() async {
    final failures = <String>[];

    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      failures.add('cookies ($e)');
    }

    try {
      if (Platform.isIOS || Platform.isMacOS) {
        // WKWebsiteDataStore has no "delete everything" call; deleting
        // everything modified since the epoch is the supported equivalent.
        await WebStorageManager.instance().removeDataModifiedSince(
          dataTypes: WebsiteDataType.ALL,
          date: DateTime.fromMillisecondsSinceEpoch(0),
        );
      } else {
        await WebStorageManager.instance().deleteAllData();
      }
    } catch (e) {
      failures.add('site storage ($e)');
    }

    try {
      await InAppWebViewController.clearAllCache();
    } catch (e) {
      failures.add('cache ($e)');
    }

    // A session that no longer exists must not keep an in-memory allow-list
    // of hosts the user consented to under it.
    clearAllowedHostChanges();
    notifyListeners();
    return failures;
  }

  /// Cookies for one host, for the site-information sheet.
  Future<int> cookieCountFor(String url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url),
      );
      return cookies.length;
    } catch (_) {
      return 0;
    }
  }

  /// Clear cookies for a single site. Best effort: the platform only exposes
  /// per-cookie deletion, so this is "every cookie we can see for this URL".
  Future<void> clearDataForUrl(String url) async {
    try {
      await CookieManager.instance().deleteCookies(url: WebUri(url));
    } catch (_) {
      // Nothing stored for this host, or the platform refused; the sheet
      // reports what it could do rather than pretending.
    }
  }

  // --- JavaScript bridge --------------------------------------------------

  /// Run [body] in the page and return its value. **Diagnostics only.**
  ///
  /// The one question no product code needs and no validation can do without:
  /// *is this page still doing anything?* Counting `requestAnimationFrame`
  /// ticks, watching a `setInterval`, or reading how many requests a page has
  /// in flight cannot be expressed through [probe], which deliberately returns
  /// a fixed shape. Rather than widen that shape for a test, this is a narrow,
  /// named seam with the word "debug" in it.
  ///
  /// Refuses outside a debug build, so no release path can reach it. Nothing in
  /// `lib/` calls it and nothing may: a product behaviour that depends on
  /// arbitrary injected script is a product behaviour that cannot be reviewed.
  @visibleForTesting
  Future<Object?> debugEvaluate(String body, {Duration? timeout}) async {
    if (!kDebugMode) return null;
    return _call(body, timeout: timeout);
  }

  /// Every bridge call is bounded. `callAsyncJavaScript` awaits a promise, and
  /// a promise that never settles — a `fetch` against a dead socket, a page
  /// navigating out from under us — would otherwise hang the save run with
  /// no way back.
  static const Duration defaultCallTimeout = Duration(seconds: 20);

  Future<Object?> _call(
    String body, {
    Map<String, dynamic> args = const {},
    Duration? timeout,
  }) async {
    final controller = _webView;
    if (controller == null) {
      throw StateError('WebView is not attached');
    }
    final result = await controller
        .callAsyncJavaScript(
          functionBody: '$kBridgePreamble\n$body',
          arguments: args,
        )
        .timeout(
          timeout ?? defaultCallTimeout,
          onTimeout: () => throw BridgeException(
            'JavaScript call timed out after '
            '${(timeout ?? defaultCallTimeout).inSeconds}s',
          ),
        );
    if (result == null) return null;
    if (result.error != null) {
      throw BridgeException(result.error!);
    }
    return result.value;
  }

  /// Read the page.
  ///
  /// [withSignals] carries the content, media and access measurements. Pass
  /// **false** for a probe whose caller only needs geometry and image state —
  /// the scroll loop takes one of those per step, and the signal half is the
  /// expensive half. A probe taken without them reports the defaults, which
  /// every consumer already reads as "nothing detected"; asking a light probe
  /// to classify a page would get a confidently wrong answer, so nothing does.
  ///
  /// [withLinks] implies signals: the only caller that wants links is the
  /// settled probe that decides what the page becomes, and it needs both.
  Future<PageProbe> probe({
    bool withLinks = false,
    bool withSignals = true,
  }) async {
    final body = withLinks
        ? kCallProbeWithLinks
        : (withSignals ? kCallProbe : kCallProbeLight);
    final raw = await _call(body);
    if (raw is! Map) {
      throw BridgeException('probe returned ${raw.runtimeType}');
    }
    return PageProbe.fromJson(Map<String, dynamic>.from(raw));
  }

  /// The image slice starting at [imageOffset], with no signals and no links.
  ///
  /// The bridge holds no state between calls: the slice carries `imageCount`
  /// and each image's absolute `index`, which is what lets a caller reassemble
  /// a population larger than one call returns.
  Future<PageProbe> probeImageSlice(int imageOffset) async {
    final raw = await _call(
      kCallProbeImageSlice,
      args: {'imageOffset': imageOffset},
    );
    if (raw is! Map) {
      throw BridgeException('image slice returned ${raw.runtimeType}');
    }
    return PageProbe.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<Map<String, dynamic>> scrollStep(int dy) async {
    final raw = await _call(kCallScrollStep, args: {'dy': dy});
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Future<void> scrollTo(int y) async {
    await _call(kCallScrollTo, args: {'y': y});
  }

  /// Fallback asset read: pull the bytes through the page itself.
  /// Returns null when blocked (CORS on a cross-origin CDN is the common case).
  Future<InPageBytes?> fetchAsBase64(String url) async {
    try {
      final raw = await _call(
        kCallFetchBase64,
        args: {'url': url},
        timeout: const Duration(seconds: 45),
      );
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) return null;
      return InPageBytes(
        base64Data: map['data']?.toString() ?? '',
        mimeType: map['mime']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Enter element-picking mode. Taps are swallowed so the page cannot
  /// navigate while the user is choosing.
  Future<void> startSelection({String mode = 'link'}) async {
    await _call(kCallStartSelection, args: {'mode': mode});
    _selectionActive = true;
    notifyListeners();
  }

  Future<void> stopSelection() async {
    try {
      await _call(kCallStopSelection);
    } catch (_) {
      // The page may have navigated; the overlay is gone either way.
    }
    _selectionActive = false;
    notifyListeners();
  }

  /// Resolve a saved next-link rule against the current page.
  Future<LocatorMatch?> applyLocator(Map<String, dynamic> locator) async {
    try {
      final raw = await _call(kCallApplyLocator, args: {'locator': locator});
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) {
        return LocatorMatch.failed(map['reason']?.toString() ?? 'no match');
      }
      return LocatorMatch(
        href: map['href']?.toString() ?? '',
        score: (map['score'] as num?)?.toInt() ?? 0,
        ambiguous: map['ambiguous'] == true,
        matchedSignals: map['matched']?.toString() ?? '',
      );
    } catch (e) {
      return LocatorMatch.failed(e.toString());
    }
  }

  /// Read the page's readable region as a list of candidate blocks.
  ///
  /// Returns what the page *reported*, flags and all — the decision about
  /// which blocks survive belongs to `save/document_extraction.dart`, where it
  /// is unit-tested. Null when the bridge could not run at all (a CSP that
  /// blocks injection, a page mid-navigation), which the caller reports as a
  /// text-extraction failure rather than as an empty document.
  Future<RawDocument?> extractDocument({int blockCap = 2000}) async {
    try {
      final raw = await _call(
        kCallExtractDocument,
        args: {'blockCap': blockCap},
        // Walking a long entry's DOM is slower than a probe, and a novel
        // page is exactly the case this exists for.
        timeout: const Duration(seconds: 45),
      );
      if (raw is! Map) return null;
      return RawDocument.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  /// Resolve a saved reader-area rule into an ordered image list.
  Future<List<PageImage>?> applyReaderRule(Map<String, dynamic> rule) async {
    try {
      final raw = await _call(kCallApplyReaderRule, args: {'rule': rule});
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) return null;
      return (map['images'] as List<dynamic>? ?? const [])
          .map((e) => PageImage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Cookie header for [url], read from the WebView's own store. Never
  /// persisted by us and never logged.
  Future<String?> cookieHeaderFor(String url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url),
      );
      if (cookies.isEmpty) return null;
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _selectionController.close();
    super.dispose();
  }

  Future<String?> userAgent() async {
    try {
      final raw = await _call('return navigator.userAgent;');
      return raw?.toString();
    } catch (_) {
      return null;
    }
  }
}

/// One completed main-frame load, as the controller saw it.
///
/// Emitted for *every* completed load, automation included — the recording
/// rule is the repository's run, and handing it the source rather than
/// pre-filtering keeps that rule in one readable place.
class BrowserVisit {
  const BrowserVisit({
    required this.url,
    required this.title,
    required this.source,
    this.requestedUrl = '',
    this.iconUrl,
  });

  final String url;
  final String title;
  final NavigationSource source;

  /// What was asked for before redirects. Differs from [url] exactly when
  /// something moved the navigation.
  final String requestedUrl;

  /// The page's declared icon, when it had one.
  final String? iconUrl;

  bool get wasRedirected => requestedUrl.isNotEmpty && requestedUrl != url;
}

/// What the user tapped in selection mode.
class SelectedElement {
  const SelectedElement({
    required this.mode,
    required this.tag,
    this.text = '',
    this.href = '',
    this.rel = '',
    this.ariaLabel = '',
    this.title = '',
    this.id = '',
    this.classes = '',
    this.rawClasses = '',
    this.imgAlt = '',
    this.selector,
    this.containerSelector,
    this.outerHtml = '',
    this.imageCount = 0,
    this.minImageEdge = 0,
    this.imageSelector,
  });

  factory SelectedElement.fromJson(Map<String, dynamic> json) =>
      SelectedElement(
        mode: json['mode']?.toString() ?? 'link',
        tag: json['tag']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        href: json['href']?.toString() ?? '',
        rel: json['rel']?.toString() ?? '',
        ariaLabel: json['ariaLabel']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        id: json['id']?.toString() ?? '',
        classes: json['classes']?.toString() ?? '',
        rawClasses: json['rawClasses']?.toString() ?? '',
        imgAlt: json['imgAlt']?.toString() ?? '',
        selector: json['selector']?.toString(),
        containerSelector: json['containerSelector']?.toString(),
        outerHtml: json['outerHtml']?.toString() ?? '',
        imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
        minImageEdge: (json['minImageEdge'] as num?)?.toInt() ?? 0,
        imageSelector: json['imageSelector']?.toString(),
      );

  final String mode;
  final String tag;
  final String text;
  final String href;
  final String rel;
  final String ariaLabel;
  final String title;
  final String id;
  final String classes;
  final String rawClasses;
  final String imgAlt;
  final String? selector;
  final String? containerSelector;
  final String outerHtml;
  final int imageCount;
  final int minImageEdge;
  final String? imageSelector;
}

class LocatorMatch {
  const LocatorMatch({
    required this.href,
    required this.score,
    this.ambiguous = false,
    this.matchedSignals = '',
  }) : failureReason = null;

  const LocatorMatch.failed(this.failureReason)
    : href = '',
      score = 0,
      ambiguous = false,
      matchedSignals = '';

  final String href;
  final int score;
  final bool ambiguous;
  final String matchedSignals;
  final String? failureReason;

  bool get isMatch => failureReason == null && href.isNotEmpty;
}

/// A cross-host navigation the page started, waiting on the user.
class HostChangeRequest {
  HostChangeRequest({
    required this.fromHost,
    required this.toHost,
    required this.targetUrl,
    required this.deadline,
  });

  final String fromHost;
  final String toHost;
  final String targetUrl;

  /// When silence becomes a refusal.
  final DateTime deadline;
  final Completer<bool> completer = Completer<bool>();

  Duration get remaining {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class BridgeException implements Exception {
  BridgeException(this.message);
  final String message;
  @override
  String toString() => 'BridgeException: $message';
}

class InPageBytes {
  const InPageBytes({required this.base64Data, required this.mimeType});
  final String base64Data;
  final String mimeType;
}
