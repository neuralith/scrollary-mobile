/// What the account layer must do, and what it must never do.
///
/// Network-free: an in-process `HttpServer` stands in for the service, so these
/// are deterministic tests of the real `AccountApi` over a real socket rather
/// than of a mock in the shape of one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/account/account_api.dart';
import 'package:web_reader/account/account_controller.dart';
import 'package:web_reader/account/firebase_sign_in.dart';
import 'package:web_reader/account/token_store.dart';

/// A service that answers the account endpoints, and records what it was asked.
class FakeService {
  FakeService(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeService> start() async =>
      FakeService(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  /// Every path this service was asked for, in order.
  final List<String> calls = [];

  /// Refresh tokens the service still considers valid, mapped to their account.
  final Map<String, String> validRefresh = {};

  /// Access tokens the service still accepts.
  final Map<String, String> validAccess = {};

  int signInCount = 0;
  int refreshCount = 0;
  int signOutCount = 0;

  /// When set, every request answers 401 regardless.
  bool refuseEverything = false;

  /// When set, the socket is closed without an answer — an unreachable service
  /// rather than a refusing one. The two must be handled differently.
  bool unreachable = false;

  int _issued = 0;

  Future<void> _handle(HttpRequest request) async {
    calls.add(request.uri.path);
    if (unreachable) {
      await request.response.close();
      await _server.close(force: true);
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    final json = body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(body) as Map<String, Object?>;

    switch (request.uri.path) {
      case '/auth/signin':
        signInCount++;
        final token = json['id_token'] as String? ?? '';
        if (refuseEverything || !token.startsWith('dev:')) {
          return _refuse(request);
        }
        return _issueSession(request, token.substring(4));
      case '/auth/refresh':
        refreshCount++;
        final presented = json['refresh_token'] as String? ?? '';
        final account = validRefresh.remove(presented);
        if (refuseEverything || account == null) return _refuse(request);
        return _issueSession(request, account);
      case '/auth/signout':
        signOutCount++;
        validRefresh.remove(json['refresh_token']);
        return _json(request, {'status': 'signed_out'});
      case '/me':
        final header = request.headers.value(HttpHeaders.authorizationHeader);
        final token = (header ?? '').replaceFirst('Bearer ', '');
        final account = validAccess[token];
        if (refuseEverything || account == null) return _refuse(request);
        return _json(request, {
          'user_id': account,
          'library_id': 'lib-$account',
        });
      default:
        request.response.statusCode = HttpStatus.notFound;
        return request.response.close();
    }
  }

  Future<void> _issueSession(HttpRequest request, String account) {
    _issued++;
    final access = 'access-$account-$_issued';
    final refresh = 'refresh-$account-$_issued';
    validAccess[access] = account;
    validRefresh[refresh] = account;
    return _json(request, {
      'access_token': access,
      'refresh_token': refresh,
      'expires_in': 3600,
      'token_type': 'Bearer',
      'user_id': account,
    });
  }

  Future<void> _refuse(HttpRequest request) {
    request.response.statusCode = HttpStatus.unauthorized;
    return _json(request, {
      'error': {'code': 'unauthenticated', 'message': 'refused'},
    }, status: false);
  }

  Future<void> _json(
    HttpRequest request,
    Map<String, Object?> body, {
    bool status = true,
  }) {
    if (status) request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    return request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

/// An in-memory TokenStore: the secure-storage plugin has no implementation in
/// a unit test, and what these tests are about is the controller's behaviour,
/// not the Keychain's.
class MemoryTokenStore implements TokenStore {
  StoredSession? session;
  int writes = 0;
  int clears = 0;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession s) async {
    writes++;
    session = s;
  }

  @override
  Future<void> clear() async {
    clears++;
    session = null;
  }
}

/// Stands in for Firebase. It never runs in these tests unless a case asks for
/// it, which is itself the point: no test here starts the SDK.
class FakeProviders implements ProviderSignIn {
  FakeProviders({this.token = 'dev:alice', this.failure});

  final String token;
  final SignInFailure? failure;
  int signOuts = 0;

  @override
  Future<String> idToken(SignInProvider provider) async {
    final f = failure;
    if (f != null) throw f;
    return token;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  late FakeService service;
  late MemoryTokenStore tokens;
  late FakeProviders providers;
  final controllers = <AccountController>[];

  AccountController build({bool configured = true}) {
    final c = AccountController(
      tokens: tokens,
      api: configured ? AccountApi(baseUrl: service.baseUrl) : null,
      providers: providers,
    );
    controllers.add(c);
    return c;
  }

  setUp(() async {
    service = await FakeService.start();
    tokens = MemoryTokenStore();
    providers = FakeProviders();
  });

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await service.stop();
  });

  group('the ordinary state', () {
    test(
      'a fresh install is signed out, and asks the service nothing',
      () async {
        final account = build();
        await account.restore();

        expect(account.isSignedIn, isFalse);
        expect(account.status, AccountStatus.signedOut);
        expect(
          service.calls,
          isEmpty,
          reason: 'a device with no session has nothing to ask about',
        );
      },
    );

    test('a build with no service address cannot offer an account', () async {
      final account = build(configured: false);
      await account.restore();

      expect(account.status, AccountStatus.unavailable);
      expect(account.isSignedIn, isFalse);
      expect(service.calls, isEmpty);
    });
  });

  group('signing in', () {
    test('a provider token becomes a stored session', () async {
      final account = build();
      final id = await account.signIn(SignInProvider.google);

      expect(id, 'alice');
      expect(account.isSignedIn, isTrue);
      expect(account.userId, 'alice');
      expect(tokens.session, isNotNull);
      expect(await account.accessToken(), tokens.session!.accessToken);
    });

    test('the development identity signs in without any provider', () async {
      final account = build();
      await account.signInAsDeveloper('bob');

      expect(account.userId, 'bob');
      expect(
        service.calls,
        contains('/auth/signin'),
        reason: 'the dev path is the same endpoint, not a second one',
      );
    });

    test('a cancelled provider sign-in leaves the device signed out', () async {
      providers = FakeProviders(failure: const SignInFailure.cancelled());
      final account = build();

      await expectLater(
        account.signIn(SignInProvider.apple),
        throwsA(
          isA<SignInFailure>().having((e) => e.cancelled, 'cancelled', isTrue),
        ),
      );
      expect(account.isSignedIn, isFalse);
      expect(service.signInCount, 0);
    });

    test('a refused token leaves the device signed out', () async {
      providers = FakeProviders(token: 'not-a-dev-token');
      final account = build();

      await expectLater(
        account.signIn(SignInProvider.google),
        throwsA(
          isA<AccountApiException>().having(
            (e) => e.unauthenticated,
            'unauthenticated',
            isTrue,
          ),
        ),
      );
      expect(account.isSignedIn, isFalse);
      expect(tokens.session, isNull);
    });
  });

  group('restoring on launch', () {
    test('a good stored session is restored', () async {
      final first = build();
      await first.signInAsDeveloper('alice');

      final second = build();
      await second.restore();

      expect(second.isSignedIn, isTrue);
      expect(second.userId, 'alice');
    });

    test(
      'an expired access token is renewed rather than signing out',
      () async {
        final account = build();
        await account.signInAsDeveloper('alice');

        // The access token dies; the refresh token is still good. This is the
        // ordinary state of any app reopened after an hour away.
        service.validAccess.clear();

        final next = build();
        await next.restore();

        expect(
          next.isSignedIn,
          isTrue,
          reason: 'one rotation is what the refresh token is for',
        );
        expect(service.refreshCount, 1);
      },
    );

    test('a dead refresh token signs the device out', () async {
      final account = build();
      await account.signInAsDeveloper('alice');

      service.validAccess.clear();
      service.validRefresh.clear();

      final next = build();
      await next.restore();

      expect(next.isSignedIn, isFalse);
      expect(tokens.session, isNull, reason: 'nothing left to renew');
    });

    // An app that forgets who you are because a train went into a tunnel is
    // worse than one that finds out on its next drain.
    test('an unreachable service does not sign the device out', () async {
      final account = build();
      await account.signInAsDeveloper('alice');
      service.unreachable = true;

      final next = build();
      await next.restore();

      expect(next.isSignedIn, isTrue);
      expect(tokens.session, isNotNull);
    });
  });

  group('refreshing', () {
    test('rotation replaces both tokens', () async {
      final account = build();
      await account.signInAsDeveloper('alice');
      final before = tokens.session!;

      expect(await account.refreshSession(), isTrue);

      expect(tokens.session!.accessToken, isNot(before.accessToken));
      expect(tokens.session!.refreshToken, isNot(before.refreshToken));
    });

    // The service rotates on use, so several requests meeting one expiry must
    // not each spend the refresh token: all but one would be holding a
    // credential the service has already invalidated.
    test('concurrent refreshes make exactly one exchange', () async {
      final account = build();
      await account.signInAsDeveloper('alice');

      final results = await Future.wait([
        account.refreshSession(),
        account.refreshSession(),
        account.refreshSession(),
        account.refreshSession(),
        account.refreshSession(),
      ]);

      expect(results, everyElement(isTrue));
      expect(service.refreshCount, 1, reason: 'single-flight, not five');
    });
  });

  group('signing out', () {
    test('it revokes server-side and clears the device', () async {
      final account = build();
      await account.signInAsDeveloper('alice');

      await account.signOut();

      expect(service.signOutCount, 1);
      expect(account.isSignedIn, isFalse);
      expect(tokens.session, isNull);
      expect(providers.signOuts, 1, reason: 'the provider session ends too');
    });

    // Somebody who taps Sign out with no connection must still end up signed
    // out on the device rather than trapped in an app they asked to leave.
    test('an unreachable service still signs the device out', () async {
      final account = build();
      await account.signInAsDeveloper('alice');
      service.unreachable = true;

      await account.signOut();

      expect(account.isSignedIn, isFalse);
      expect(tokens.session, isNull);
    });

    test('signing out locally makes no request at all', () async {
      final account = build();
      await account.signInAsDeveloper('alice');
      final before = service.calls.length;

      await account.signOutLocally();

      expect(account.isSignedIn, isFalse);
      expect(
        service.calls.length,
        before,
        reason: 'nothing left to tell the service',
      );
    });
  });

  group('what the rest of the app is told', () {
    test('every change notifies once', () async {
      final account = build();
      var notifications = 0;
      account.addListener(() => notifications++);

      await account.signInAsDeveloper('alice');
      expect(notifications, greaterThanOrEqualTo(1));

      final afterSignIn = notifications;
      await account.signOut();
      expect(notifications, greaterThan(afterSignIn));
    });

    test('the access token is null when signed out', () async {
      final account = build();
      expect(await account.accessToken(), isNull);

      await account.signInAsDeveloper('alice');
      expect(await account.accessToken(), isNotNull);

      await account.signOutLocally();
      expect(await account.accessToken(), isNull);
    });
  });
}
