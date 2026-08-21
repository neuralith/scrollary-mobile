import 'package:flutter/foundation.dart';

/// Which local surface the Browser is showing.
///
/// Explicit state, not "whichever overlay happens to be in the tree" (§1).
/// All three share **one** WebView: [home] and [editingAddress] are drawn
/// over the still-mounted page, never in place of it, so returning reveals
/// the same document with its scroll position, cookies and in-page state
/// intact (D52).
enum BrowserSurface {
  /// The rendered website. The WebView is the whole content area.
  website,

  /// The local Browser Home: search field, saved sites, recently visited.
  home,

  /// The expanded URL editor, over whatever was underneath.
  editingAddress,
}

/// A page held behind a local surface, so Home can offer a way back to it.
class PreservedPage {
  const PreservedPage({required this.url, required this.title});

  final String url;
  final String title;

  bool get isEmpty => url.trim().isEmpty;
}

/// The Browser's presentation state.
///
/// Lives outside the widget so things that are not inside the Browser can
/// drive it — Settings → Saved sites opens Browser Home, and the shell's tab
/// switch has to know whether a local surface is already up.
class BrowserPresentation extends ChangeNotifier {
  BrowserSurface _surface = BrowserSurface.website;
  BrowserSurface get surface => _surface;

  bool get isHome => _surface == BrowserSurface.home;
  bool get isEditingAddress => _surface == BrowserSurface.editingAddress;

  /// True when a local surface is covering the page — the state that decides
  /// whether Back means "close this" or "go back in the page's history".
  bool get hasLocalSurface => _surface != BrowserSurface.website;

  /// The seed text for the URL editor when it opens. Empty means "start
  /// blank", which is what opening it from Browser Home does.
  String _addressDraft = '';
  String get addressDraft => _addressDraft;

  /// Whether the editor should select its whole contents on open — true when
  /// it was opened on an existing page, so typing replaces the URL (§6).
  bool _selectAllOnOpen = false;
  bool get selectAllOnOpen => _selectAllOnOpen;

  /// What Home shows in its "still open" row. Null when there is no page
  /// behind it (first run, or after website data was cleared).
  PreservedPage? _preserved;
  PreservedPage? get preserved => _preserved;

  /// A URL Browser Home was asked to open before the Browser was on screen.
  /// Consumed by the Browser once it builds.
  bool _pendingHomeRequest = false;

  void openHome({PreservedPage? preserving}) {
    if (preserving != null && !preserving.isEmpty) _preserved = preserving;
    _set(BrowserSurface.home);
  }

  /// Ask for Browser Home from outside the Browser tab (Settings). The tab
  /// switch is the caller's run; this only makes sure Home is what greets
  /// them when they arrive.
  void requestHome() {
    _pendingHomeRequest = true;
    _set(BrowserSurface.home);
  }

  bool consumeHomeRequest() {
    final pending = _pendingHomeRequest;
    _pendingHomeRequest = false;
    return pending;
  }

  void openAddressEditor({String draft = '', bool selectAll = false}) {
    _addressDraft = draft;
    _selectAllOnOpen = selectAll;
    _set(BrowserSurface.editingAddress);
  }

  /// Close the address editor back to whatever it was covering.
  void closeAddressEditor({bool toHome = false}) =>
      _set(toHome ? BrowserSurface.home : BrowserSurface.website);

  /// Reveal the preserved page. Deliberately does not reload anything.
  void showWebsite() => _set(BrowserSurface.website);

  void rememberPage(PreservedPage page) {
    if (page.isEmpty) return;
    if (_preserved?.url == page.url && _preserved?.title == page.title) return;
    _preserved = page;
    // Not a surface change: nothing rebuilds for a title arriving late unless
    // Home is actually on screen to show it.
    if (_surface == BrowserSurface.home) notifyListeners();
  }

  /// Website data was cleared — the page behind Home may no longer be signed
  /// in, so the "still open" affordance stops claiming otherwise.
  void forgetPreserved() {
    _preserved = null;
    notifyListeners();
  }

  void _set(BrowserSurface next) {
    if (_surface == next) return;
    _surface = next;
    notifyListeners();
  }
}

/// How a page load ended, classified for the user rather than reported raw.
///
/// The WebView hands back platform error codes and vendor strings; §14 asks
/// for named states with actions, and the raw text is kept alongside for
/// diagnostics rather than shown as the headline.
enum BrowserPageState {
  ok,
  loading,
  refreshing,

  /// The device has no connection.
  offline,

  /// DNS, connection refused, host unreachable.
  unreachable,

  /// The server answered, badly (4xx/5xx).
  unavailable,

  /// The address itself does not parse.
  invalidAddress,

  /// TLS could not be verified.
  certificate,

  /// A cross-host redirect the Browser held back.
  redirectBlocked,

  /// A `mailto:` / custom-scheme link.
  externalApp,
}

/// A classified failure: what to tell the user, plus the raw text for
/// diagnostics.
class BrowserPageFault {
  const BrowserPageFault({
    required this.state,
    required this.detail,
    this.url = '',
  });

  final BrowserPageState state;

  /// The platform's own words. Shown small, under the explanation — never as
  /// the explanation.
  final String detail;
  final String url;
}

/// Map a platform error onto a state the UI has copy for.
///
/// [description] and [type] are whatever `onReceivedError` produced;
/// [statusCode] is set instead for an HTTP error. Unknown errors land on
/// [BrowserPageState.unavailable] — the honest "it did not load", rather than
/// a guess.
BrowserPageState classifyPageError({
  String description = '',
  String type = '',
  int? statusCode,
  bool online = true,
}) {
  if (statusCode != null && statusCode >= 400) {
    return BrowserPageState.unavailable;
  }
  final text = '$type $description'.toLowerCase();
  if (!online) return BrowserPageState.offline;
  if (text.contains('notconnectedtointernet') ||
      text.contains('network_is_offline') ||
      text.contains('internet_disconnected') ||
      text.contains('no internet')) {
    return BrowserPageState.offline;
  }
  if (text.contains('cannotfindhost') ||
      text.contains('name_not_resolved') ||
      text.contains('hostlookup') ||
      text.contains('cannotconnecttohost') ||
      text.contains('connection_refused') ||
      text.contains('timedout') ||
      text.contains('connection_timed_out')) {
    return BrowserPageState.unreachable;
  }
  if (text.contains('servercertificate') ||
      text.contains('cert_') ||
      text.contains('sslhandshake') ||
      text.contains('secureconnectionfailed')) {
    return BrowserPageState.certificate;
  }
  if (text.contains('unsupportedurl') || text.contains('badurl')) {
    return BrowserPageState.invalidAddress;
  }
  return BrowserPageState.unavailable;
}
