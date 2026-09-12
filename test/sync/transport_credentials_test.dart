/// Which credential the sync transport sends, and what it does with a 401.
///
/// Over a real socket, against an in-process server, because the thing under
/// test is the headers on the wire.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/sync/transport.dart';

/// Records every request's credentials and answers whatever it is told to.
class _Recorder {
  _Recorder(this._server) {
    _server.listen(_handle);
  }

  static Future<_Recorder> start() async =>
      _Recorder(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  final List<String?> authorization = [];
  final List<String?> libraryHeader = [];

  /// Access tokens the server accepts. Anything else is 401.
  final Set<String> accepted = {};

  /// When true, the development namespace header is accepted on its own.
  bool acceptDevNamespace = false;

  Future<void> _handle(HttpRequest request) async {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    final lib = request.headers.value('X-Scrollary-Library');
    authorization.add(auth);
    libraryHeader.add(lib);
    await utf8.decoder.bind(request).join();

    final token = (auth ?? '').replaceFirst('Bearer ', '');
    final ok =
        (auth != null && accepted.contains(token)) ||
        (auth == null && lib != null && acceptDevNamespace);

    request.response.statusCode = ok ? HttpStatus.ok : HttpStatus.unauthorized;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(
        ok
            ? {'changes': <Object>[], 'next_cursor': 0, 'has_more': false}
            : {
                'error': {'code': 'unauthenticated', 'message': 'no'},
              },
      ),
    );
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _Recorder server;

  setUp(() async => server = await _Recorder.start());
  tearDown(() async => server.stop());

  HttpSyncTransport transport({
    Future<String?> Function()? accessToken,
    Future<bool> Function()? refreshSession,
  }) => HttpSyncTransport(
    baseUrl: server.baseUrl,
    libraryName: 'development',
    accessToken: accessToken,
    refreshSession: refreshSession,
  );

  // The service refuses a request carrying both, so the client must never send
  // both. Which one it sends is decided by whether there is a token, and by
  // nothing else.
  group('which credential goes on the wire', () {
    test(
      'a signed-out device sends the development namespace, no token',
      () async {
        server.acceptDevNamespace = true;
        final t = transport(accessToken: () async => null);

        await t.getChanges(cursor: 0);

        expect(server.authorization.single, isNull);
        expect(server.libraryHeader.single, 'development');
        t.close();
      },
    );

    test(
      'a signed-in device sends the token, and never the namespace',
      () async {
        server.accepted.add('good');
        final t = transport(accessToken: () async => 'good');

        await t.getChanges(cursor: 0);

        expect(server.authorization.single, 'Bearer good');
        expect(
          server.libraryHeader.single,
          isNull,
          reason: 'the service refuses a request carrying both credentials',
        );
        t.close();
      },
    );

    test(
      'a build with no account closure behaves exactly as it always did',
      () async {
        server.acceptDevNamespace = true;
        final t = transport();

        await t.getChanges(cursor: 0);

        expect(server.libraryHeader.single, 'development');
        t.close();
      },
    );
  });

  group('a 401 in flight', () {
    test('the session is renewed once and the request is sent again', () async {
      var renewals = 0;
      String? token = 'stale';
      server.accepted.add('fresh');

      final t = transport(
        accessToken: () async => token,
        refreshSession: () async {
          renewals++;
          token = 'fresh';
          return true;
        },
      );

      final reply = await t.getChanges(cursor: 0);

      expect(reply.ok, isTrue);
      expect(renewals, 1);
      expect(server.authorization, ['Bearer stale', 'Bearer fresh']);
      t.close();
    });

    // A second 401 after a successful renewal is the service saying something
    // other than "your token expired". Retrying again would turn one refusal
    // into a loop.
    test('it is retried exactly once, never twice', () async {
      var renewals = 0;
      final t = transport(
        accessToken: () async => 'never-accepted',
        refreshSession: () async {
          renewals++;
          return true;
        },
      );

      final reply = await t.getChanges(cursor: 0);

      expect(reply.status, 401);
      expect(renewals, 1);
      expect(server.authorization.length, 2);
      t.close();
    });

    test('a renewal that fails is not retried at all', () async {
      final t = transport(
        accessToken: () async => 'stale',
        refreshSession: () async => false,
      );

      final reply = await t.getChanges(cursor: 0);

      expect(reply.status, 401);
      expect(server.authorization.length, 1, reason: 'nothing to retry with');
      t.close();
    });

    test('with no renewal closure the 401 is simply the answer', () async {
      final t = transport(accessToken: () async => 'stale');

      final reply = await t.getChanges(cursor: 0);

      expect(reply.status, 401);
      expect(server.authorization.length, 1);
      t.close();
    });
  });
}
