/// The account, as the rest of the app sees it.
///
/// One object holds the whole of it: whether there is a session, what it is,
/// and how it is renewed. Everything else — the sync stack especially — is
/// handed closures rather than this object, so nothing outside `lib/account/`
/// can reach a token or condition a local write on one.
///
/// **The app is fully usable with no account, permanently** (V2-D3). Nothing
/// here is consulted to read, capture, organise, save or open anything. It is
/// asked one question, in one place: may the network drain run
/// (`SyncComposition.resolve`)? That is the same shape the capability seam
/// already has, and it is deliberate — one gate, on the drain, and never on
/// recording (V2-D7).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account_api.dart';
import 'firebase_sign_in.dart';
import 'token_store.dart';

/// Where the account stands.
enum AccountStatus {
  /// No session on this device. The ordinary state, and a complete product.
  signedOut,

  /// A stored session is being checked against the service on launch.
  resolving,

  /// A session this device holds and believes in.
  signedIn,

  /// This build has no service address compiled in, so signing in is not
  /// something it can do. Distinct from [signedOut], which is a choice.
  unavailable,
}

/// The account state and the operations that change it.
class AccountController extends ChangeNotifier {
  AccountController({
    required this._tokens,
    required this._api,
    ProviderSignIn? providers,
  }) : _providers = providers ?? FirebaseProviderSignIn();

  final TokenStore _tokens;

  /// Null when this build has no service address, which is when signing in is
  /// not something the app can offer at all.
  final AccountApi? _api;

  final ProviderSignIn _providers;

  AccountStatus _status = AccountStatus.signedOut;
  StoredSession? _session;
  Future<bool>? _refreshing;

  AccountStatus get status =>
      _api == null ? AccountStatus.unavailable : _status;

  /// Whether this device holds a session. The one question the sync gate asks.
  bool get isSignedIn => _api != null && _status == AccountStatus.signedIn;

  /// The signed-in account's id, or null.
  String? get userId => _session?.userId;

  /// Restores a stored session on launch, if there is one.
  ///
  /// A failure to reach the service does NOT sign the user out: an app that
  /// forgets who you are because a train went into a tunnel is worse than one
  /// that finds out on its next drain. Only an explicit refusal clears.
  Future<void> restore() async {
    final api = _api;
    if (api == null) return;

    final stored = await _tokens.read();
    if (stored == null) {
      _set(AccountStatus.signedOut, null);
      return;
    }

    _set(AccountStatus.resolving, stored);
    try {
      await api.me(stored.accessToken);
      _set(AccountStatus.signedIn, stored);
    } on AccountApiException catch (e) {
      if (!e.unauthenticated) {
        // Unreachable, not refused. Believe the stored session; the drain will
        // find out soon enough, and it knows how to refresh.
        _set(AccountStatus.signedIn, stored);
        return;
      }
      // The access token is dead. One rotation is exactly what the refresh
      // token is for, and this is the ordinary path after an hour away.
      if (await _rotate()) return;
      await signOutLocally();
    }
  }

  /// Signs in with a provider and exchanges the result for a session.
  ///
  /// Returns the account id. Throws [SignInFailure] when the provider refused
  /// or the person cancelled, and [AccountApiException] when the service did.
  Future<String> signIn(SignInProvider provider) async {
    final idToken = await _providers.idToken(provider);
    return _exchange(idToken);
  }

  /// Signs in with a development identity (`dev:<name>`).
  ///
  /// The deterministic path: no provider, no network beyond this service, the
  /// same account every time. It is what the automated suites drive and what a
  /// developer uses against a local service — and a production service refuses
  /// it, because it holds a Firebase client that cannot parse the shape.
  Future<String> signInAsDeveloper(String name) =>
      _exchange('dev:${name.trim()}');

  Future<String> _exchange(String idToken) async {
    final api = _api;
    if (api == null) {
      throw const AccountApiException('This build has no service configured.');
    }
    final session = await api.signIn(idToken);
    await _tokens.write(session);
    _set(AccountStatus.signedIn, session);
    return session.userId;
  }

  /// The access token for an outgoing request, or null when signed out.
  Future<String?> accessToken() async => _session?.accessToken;

  /// Renews the session after a 401. Single-flight: concurrent callers wait on
  /// one rotation rather than each spending the refresh token, which — because
  /// the service rotates on use — would leave all but one of them holding a
  /// token that has already been invalidated.
  Future<bool> refreshSession() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final started = _rotate().whenComplete(() => _refreshing = null);
    _refreshing = started;
    return started;
  }

  Future<bool> _rotate() async {
    final api = _api;
    final current = _session;
    if (api == null || current == null) return false;
    try {
      final renewed = await api.refresh(current.refreshToken);
      await _tokens.write(renewed);
      _set(AccountStatus.signedIn, renewed);
      return true;
    } on AccountApiException catch (e) {
      if (e.unauthenticated) {
        // The refresh token is gone: revoked from another device, expired, or
        // the account was deleted. There is nothing left to renew.
        await signOutLocally();
      }
      return false;
    }
  }

  /// Signs out: revoke this session server-side, then clear it locally.
  ///
  /// **Everything on the device stays** (V2-D11). Tokens clear and the drain
  /// stops; rows, downloads and the outbox are untouched, and the library is
  /// exactly as usable as it was before anybody signed in.
  ///
  /// The server call is best-effort by design. Somebody who taps Sign out with
  /// no connection must still end up signed out on the device rather than
  /// trapped; the refresh token then stays valid until it expires, which is the
  /// honest trade — refusing to sign out is worse for the person holding the
  /// phone.
  Future<void> signOut() async {
    final api = _api;
    final current = _session;
    if (api != null && current != null) {
      try {
        await api.signOut(current.refreshToken);
      } on AccountApiException catch (e) {
        debugPrint('[account] server revoke failed, continuing locally: $e');
      }
    }
    await _providers.signOut();
    await signOutLocally();
  }

  /// Clears the device's session without calling the service.
  ///
  /// Split out because the paths that need exactly this — a refresh token the
  /// service has already rejected — must not fire a second doomed request.
  Future<void> signOutLocally() async {
    await _tokens.clear();
    _set(AccountStatus.signedOut, null);
  }

  void _set(AccountStatus status, StoredSession? session) {
    if (_status == status && _session?.accessToken == session?.accessToken) {
      return;
    }
    _status = status;
    _session = session;
    notifyListeners();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}
