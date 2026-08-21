/// The wire boundary of the sync engine (roadmap G1/G2).
///
/// One interface, two implementations: [HttpSyncTransport] over `dart:io` for
/// the real service, and test fakes over an in-process `HttpServer`. Nothing
/// above this file constructs a socket, so nothing above it can accidentally
/// grow a second transport.
///
/// Metadata sync is the one automatic network activity (V2-D20). It calls the
/// five operations below and nothing else — it fetches no page and drives no
/// browser. The two download-request operations are no exception: a claim and
/// a resolve exchange a state, never content.
library;

import 'dart:convert';
import 'dart:io';

/// A completed HTTP exchange: status plus decoded JSON body (empty map when
/// the body was empty or not an object).
class TransportReply {
  const TransportReply(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  bool get ok => status >= 200 && status < 300;

  /// The named error code of a non-2xx reply, or null.
  String? get errorCode {
    final error = body['error'];
    if (error is Map) return error['code'] as String?;
    return null;
  }
}

/// A transport-level failure: connection refused, timeout, malformed body.
/// Distinct from a non-2xx reply, which is a server answer.
class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  @override
  String toString() => 'SyncTransportException: $message';
}

abstract class SyncTransport {
  Future<TransportReply> postMutations(Map<String, Object?> body);

  Future<TransportReply> getChanges({required int cursor, int limit});

  Future<TransportReply> arbitrate(Map<String, Object?> body);

  /// The single-winner claim. **Synchronous by necessity**: exactly one device
  /// may win, so it cannot be replayed from an outbox and never rides
  /// `/mutations`. A loser is told with 409.
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  );

  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  );
}

/// `dart:io` implementation. [libraryName] rides the development-only
/// `X-Scrollary-Library` header (V2-D28); production authentication replaces
/// the header without changing any payload.
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.baseUrl,
    required this.libraryName,
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final Uri baseUrl;
  final String libraryName;
  final HttpClient _client;
  final Duration timeout;

  @override
  Future<TransportReply> postMutations(Map<String, Object?> body) =>
      _send('POST', '/mutations', body: body);

  @override
  Future<TransportReply> getChanges({required int cursor, int limit = 200}) =>
      _send('GET', '/changes?cursor=$cursor&limit=$limit');

  @override
  Future<TransportReply> arbitrate(Map<String, Object?> body) =>
      _send('POST', '/identity/arbitrate', body: body);

  @override
  Future<TransportReply> claimDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _send('POST', '/download-requests/$requestId/claim', body: body);

  @override
  Future<TransportReply> resolveDownloadRequest(
    String requestId,
    Map<String, Object?> body,
  ) => _send('POST', '/download-requests/$requestId/resolve', body: body);

  Future<TransportReply> _send(
    String method,
    String pathAndQuery, {
    Map<String, Object?>? body,
  }) async {
    try {
      final request = await _client
          .openUrl(method, baseUrl.resolve(pathAndQuery))
          .timeout(timeout);
      request.headers.set('X-Scrollary-Library', libraryName);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      Object? decoded;
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          throw SyncTransportException(
            'unparseable body (HTTP ${response.statusCode})',
          );
        }
      }
      return TransportReply(
        response.statusCode,
        decoded is Map<String, Object?>
            ? decoded
            : decoded is Map
            ? Map<String, Object?>.from(decoded)
            : const {},
      );
    } on SyncTransportException {
      rethrow;
    } on Exception catch (e) {
      throw SyncTransportException('$method $pathAndQuery: $e');
    }
  }

  void close() => _client.close(force: true);
}
