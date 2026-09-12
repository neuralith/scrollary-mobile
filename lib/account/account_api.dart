/// The account half of the service API: sign in, rotate, sign out, identify.
///
/// Deliberately separate from `lib/sync/transport.dart`, which speaks the
/// synchronisation endpoints and nothing else. The two share a base URL and
/// share nothing else: the sync transport never learns how a token is obtained,
/// and this file never learns what a mutation is.
library;

import 'dart:convert';
import 'dart:io';

import 'token_store.dart';

/// A refusal by the service, or a failure to reach it.
class AccountApiException implements Exception {
  const AccountApiException(this.message, {this.code, this.status});

  final String message;

  /// The service's named error code, where there was one. `unauthenticated`
  /// and `auth_unavailable` are the two a caller acts on.
  final String? code;
  final int? status;

  /// Whether the credential was refused, as opposed to the request failing.
  bool get unauthenticated => code == 'unauthenticated' || status == 401;

  /// Whether this server cannot sign anybody in at all.
  bool get unavailable => code == 'auth_unavailable' || status == 501;

  @override
  String toString() => 'AccountApiException($status $code): $message';
}

/// The account endpoints.
class AccountApi {
  AccountApi({
    required this.baseUrl,
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final Uri baseUrl;
  final HttpClient _client;
  final Duration timeout;

  /// Exchanges a provider ID token for a Scrollary session.
  ///
  /// [idToken] is a Firebase ID token in an ordinary build, or `dev:<name>`
  /// against a development service. The app does not branch on which: the
  /// service decides what it will accept, and a production service holds a
  /// client that cannot parse a development token at all.
  Future<StoredSession> signIn(String idToken) async {
    final body = await _send('POST', '/auth/signin', {'id_token': idToken});
    return _sessionFrom(body);
  }

  /// Rotates the session. The presented refresh token is spent by the call.
  Future<StoredSession> refresh(String refreshToken) async {
    final body = await _send('POST', '/auth/refresh', {
      'refresh_token': refreshToken,
    });
    return _sessionFrom(body);
  }

  /// Ends this one session server-side.
  ///
  /// The service answers 200 for an unknown or already-revoked token, so the
  /// only failures that reach a caller are transport-level — and the caller
  /// signs out locally regardless (V2-D11).
  Future<void> signOut(String refreshToken) async {
    await _send('POST', '/auth/signout', {'refresh_token': refreshToken});
  }

  /// Confirms a stored access token still works, and reports the account.
  Future<String> me(String accessToken) async {
    final body = await _send('GET', '/me', null, accessToken: accessToken);
    final id = body['user_id'];
    if (id is! String || id.isEmpty) {
      throw const AccountApiException('The service did not name the account.');
    }
    return id;
  }

  StoredSession _sessionFrom(Map<String, Object?> body) {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    final user = body['user_id'];
    if (access is! String || refresh is! String || user is! String) {
      throw const AccountApiException(
        'The service returned no usable session.',
      );
    }
    return StoredSession(
      accessToken: access,
      refreshToken: refresh,
      userId: user,
    );
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    Map<String, Object?>? payload, {
    String? accessToken,
  }) async {
    HttpClientResponse response;
    String text;
    try {
      final request = await _client
          .openUrl(method, baseUrl.resolve(path))
          .timeout(timeout);
      // Named so a session row in the account's device list is recognisable.
      // Nothing here is hardware-derived (V2-D34).
      request.headers.set('X-Client-Type', Platform.isIOS ? 'ios' : 'android');
      if (accessToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(payload)));
      }
      response = await request.close().timeout(timeout);
      text = await response.transform(utf8.decoder).join().timeout(timeout);
    } on Object catch (e) {
      throw AccountApiException('$method $path could not be completed: $e');
    }

    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw AccountApiException(
          'The service answered ${response.statusCode} with an unreadable body.',
          status: response.statusCode,
        );
      }
    }
    final body = decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};

    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    final error = body['error'];
    throw AccountApiException(
      error is Map && error['message'] is String
          ? error['message'] as String
          : 'The service refused the request.',
      code: error is Map ? error['code'] as String? : null,
      status: response.statusCode,
    );
  }

  void close() => _client.close(force: true);
}
