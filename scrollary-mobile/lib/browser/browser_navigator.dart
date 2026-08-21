import 'package:flutter/foundation.dart';

import 'browser_presentation.dart';

/// A page that has been asked for but not yet handed to the WebView.
///
/// Carries an [id] so consumption is provably once: the Browser consumes by
/// value, and a rebuild that re-reads an already-consumed request finds
/// nothing rather than loading the same URL again.
@immutable
class PendingBrowserOpen {
  const PendingBrowserOpen({required this.url, required this.id});

  final String url;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is PendingBrowserOpen && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(url, id);
}

/// The hand-off between "something asked for a page" and "the Browser is on
/// screen with a live WebView".
///
/// This exists because the two are genuinely not simultaneous. Asking comes
/// from a pushed route (Collection Detail, a details sheet, History); the Browser
/// lives in the shell underneath, and between the ask and the load there is a
/// route pop, a tab switch and possibly a WebView attach. Loading into that
/// gap is how a URL gets silently dropped.
///
/// The contract is deliberately *not* a delay:
///
/// 1. the caller stores a request here;
/// 2. the caller pops back to the shell and selects the Browser tab;
/// 3. the Browser drains the request when it is mounted **and** its WebView
///    is attached — whenever that happens to be;
/// 4. draining removes it, so nothing can load it twice.
class BrowserNavigator extends ChangeNotifier {
  PendingBrowserOpen? _pending;
  int _nextId = 1;

  /// The waiting request, if any. Read-only — [consume] is the only way to
  /// take it.
  PendingBrowserOpen? get pending => _pending;

  bool get hasPending => _pending != null;

  /// Ask for [url] to be shown in the Browser.
  ///
  /// A second request before the first is drained replaces it: the user asked
  /// for the newer page, and loading both in sequence would flash the one
  /// they did not want.
  PendingBrowserOpen request(String url) {
    final next = PendingBrowserOpen(url: url.trim(), id: _nextId++);
    _pending = next;
    notifyListeners();
    return next;
  }

  /// Take the request, exactly once. Returns null when there is nothing
  /// waiting — which is the normal case on every rebuild after the first.
  PendingBrowserOpen? consume() {
    final request = _pending;
    if (request == null) return null;
    _pending = null;
    // Deliberately no notification: the only listener is the Browser, which
    // is already awake and acting on it. Notifying here would re-enter the
    // drain during the drain.
    return request;
  }

  /// Drop a request that can no longer be honoured (the user cancelled, or
  /// the Browser was reset out from under it).
  void cancel() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}

/// The receiving half of the contract: hand a waiting request to the WebView
/// when — and only when — it can actually take it.
///
/// A plain object rather than logic inside the Browser's `State`, because
/// what it decides is the part worth testing and a widget test cannot host a
/// platform WebView.
class PendingOpenDrainer {
  PendingOpenDrainer({
    required this.navigator,
    required this.presentation,
    required this.isAttached,
    required this.reveal,
    required this.load,
  });

  final BrowserNavigator navigator;
  final BrowserPresentation presentation;

  /// Whether the WebView is live. Loading into an unattached controller is
  /// silently dropped — which is exactly how the old flow lost the URL.
  final bool Function() isAttached;

  /// Bring the website surface forward, dismissing Browser Home or the URL
  /// editor. A page the user asked for must not load behind an overlay.
  final void Function() reveal;

  final void Function(String url) load;

  /// Returns true when a request was handed over.
  ///
  /// Safe to call as often as anything likes: with nothing pending, or with
  /// no WebView yet, it does nothing. That is what makes a provider rebuild
  /// harmless — the request is gone after the first drain, so a rebuild finds
  /// nothing to load and the page is not fetched twice.
  bool drain() {
    if (!navigator.hasPending) return false;
    if (!isAttached()) return false;
    final request = navigator.consume();
    if (request == null) return false;
    reveal();
    load(request.url);
    return true;
  }
}
