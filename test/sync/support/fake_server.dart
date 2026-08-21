/// An in-process fake of the sync service, faithful to the contract's
/// semantics: the mutation ledger's idempotency, per-library revisions, the
/// revision-ordered change feed with tombstones, scalar LWW on the client
/// clock, arbitration, and the terminal-only download-request resolve.
///
/// Deterministic and network-local; the real service is exercised by the
/// integration lane, never by these unit tests.
library;

import 'dart:convert';
import 'dart:io';

class FakeBackend {
  int revision = 0;

  /// kind → wire id → row (snake_case, carrying `revision`/`updated_at`).
  final Map<String, Map<String, Map<String, Object?>>> rows = {};

  /// Ordered feed of `{type, revision, entity_type?, entity?, tombstone?}`.
  final List<Map<String, Object?>> feed = [];

  /// mutation_id → the result originally returned.
  final Map<String, Map<String, Object?>> ledger = {};

  final List<List<Map<String, Object?>>> mutationBatches = [];

  /// When set, `/mutations` answers HTTP 500 this many times first.
  int failMutationsTimes = 0;

  /// When set, the Nth `/changes` request (1-based) destroys the socket.
  int dieOnChangesRequest = 0;
  int changesRequests = 0;

  /// Rejects any upsert whose fields contain this marker key.
  static const rejectMarker = 'reject_me';

  Map<String, Object?> Function(Map<String, Object?> request)? onArbitrate;

  HttpServer? _server;
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server!.port}');

  Map<String, Map<String, Object?>> kindRows(String kind) =>
      rows.putIfAbsent(kind, () => {});

  /// Seeds a server-side row directly (the "second client" of the tests),
  /// assigning the next revision and a feed item.
  Map<String, Object?> seed(
    String kind,
    Map<String, Object?> row, {
    DateTime? updatedAt,
    String? key,
  }) {
    final id = key ?? (row['id'] ?? row['entry_id'])! as String;
    final stamped = {
      ...row,
      'revision': ++revision,
      if (kind != 'measurement' && kind != 'downloadRequest')
        'updated_at': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (kind == 'measurement' && updatedAt != null)
        'observed_at': updatedAt.toIso8601String(),
    };
    kindRows(kind)[id] = stamped;
    feed.add({
      'type': 'entity',
      'entity_type': kind,
      'revision': stamped['revision'],
      'entity': stamped,
    });
    return stamped;
  }

  /// Seeds a tombstone directly.
  void seedTombstone(
    String kind,
    String entityId, {
    String? sourceId,
    DateTime? deletedAt,
  }) {
    kindRows(kind).remove(entityId);
    final t = {
      'kind': kind,
      'entity_id': entityId,
      'source_id': ?sourceId,
      'revision': ++revision,
      'deleted_at': (deletedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    feed.add({'type': 'tombstone', 'revision': t['revision'], 'tombstone': t});
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/changes') {
        changesRequests += 1;
        if (dieOnChangesRequest == changesRequests) {
          await request.response.detachSocket().then((s) => s.destroy());
          return;
        }
        return _reply(request, 200, _changes(request.uri));
      }
      final body = await utf8.decoder.bind(request).join();
      final json = body.isEmpty
          ? <String, Object?>{}
          : Map<String, Object?>.from(jsonDecode(body) as Map);
      if (request.method == 'POST' && path == '/mutations') {
        if (failMutationsTimes > 0) {
          failMutationsTimes -= 1;
          return _reply(request, 500, {
            'error': {'code': 'internal', 'message': 'induced failure'},
          });
        }
        return _reply(request, 200, _mutations(json));
      }
      if (request.method == 'POST' && path == '/identity/arbitrate') {
        final handler = onArbitrate;
        if (handler == null) {
          return _reply(request, 200, {
            'outcome': 'unresolved',
            'reason': 'insufficient_evidence',
          });
        }
        return _reply(request, 200, handler(json));
      }
      final resolve = RegExp(
        r'^/download-requests/([^/]+)/resolve$',
      ).firstMatch(path);
      if (request.method == 'POST' && resolve != null) {
        final (status, reply) = _resolve(resolve.group(1)!, json);
        return _reply(request, status, reply);
      }
      return _reply(request, 404, {
        'error': {'code': 'unknown_entity', 'message': 'no such route $path'},
      });
    } on Object catch (e) {
      return _reply(request, 500, {
        'error': {'code': 'internal', 'message': '$e'},
      });
    }
  }

  Map<String, Object?> _changes(Uri uri) {
    final cursor = int.parse(uri.queryParameters['cursor'] ?? '0');
    final limit = int.parse(uri.queryParameters['limit'] ?? '200');
    final newer = feed
        .where((item) => (item['revision']! as int) > cursor)
        .toList();
    final page = newer.take(limit).toList();
    final nextCursor = page.isEmpty ? cursor : page.last['revision']! as int;
    return {
      'changes': page,
      'next_cursor': nextCursor,
      'latest_revision': revision,
      'has_more': newer.length > page.length,
    };
  }

  Map<String, Object?> _mutations(Map<String, Object?> body) {
    final envelopes = (body['mutations'] as List<Object?>)
        .map((e) => Map<String, Object?>.from(e! as Map))
        .toList();
    mutationBatches.add(envelopes);
    final results = <Map<String, Object?>>[];
    for (final envelope in envelopes) {
      final mutationId = envelope['mutation_id']! as String;
      final replay = ledger[mutationId];
      if (replay != null) {
        results.add({...replay, 'outcome': 'duplicate'});
        continue;
      }
      final result = _applyEnvelope(envelope);
      ledger[mutationId] = result;
      results.add(result);
    }
    return {'library_revision': revision, 'results': results};
  }

  Map<String, Object?> _applyEnvelope(Map<String, Object?> envelope) {
    final mutationId = envelope['mutation_id']! as String;
    final kind = envelope['entity_type']! as String;
    final entityId = envelope['entity_id']! as String;
    final op = envelope['op']! as String;
    final clientTime = DateTime.parse(envelope['client_time']! as String);
    const kinds = {
      'folder',
      'collection',
      'source',
      'entry',
      'location',
      'readingState',
      'measurement',
    };
    Map<String, Object?> rejected(String code) => {
      'mutation_id': mutationId,
      'outcome': 'rejected',
      'error': {'code': code, 'message': code},
    };
    if (!kinds.contains(kind)) return rejected('invalid_mutation');
    final key = kind == 'measurement'
        ? '$entityId|${(envelope['fields'] as Map?)?['source_id']}'
        : entityId;
    final store = kindRows(kind);
    if (op == 'delete') {
      final existing = store.remove(key);
      if (kind == 'folder' && existing?['parent_id'] != null) {
        _reparentChildrenOf(
          entityId,
          existing!['parent_id']! as String,
          clientTime,
        );
      }
      final t = {
        'kind': kind,
        'entity_id': entityId,
        if (kind == 'measurement' && existing != null)
          'source_id': existing['source_id'],
        'revision': ++revision,
        'deleted_at': clientTime.toIso8601String(),
      };
      feed.add({
        'type': 'tombstone',
        'revision': t['revision'],
        'tombstone': t,
      });
      return {
        'mutation_id': mutationId,
        'outcome': 'applied',
        'revision': revision,
      };
    }
    final fields = Map<String, Object?>.from(envelope['fields']! as Map);
    if (fields.containsKey(rejectMarker)) {
      return rejected('invariant_violation');
    }
    final existing = store[key];
    if (existing != null) {
      final currentClock = DateTime.parse(
        (existing['updated_at'] ?? existing['observed_at'])! as String,
      );
      if (currentClock.isAfter(clientTime)) {
        // LWW: the stored row is newer; the write is convergence, not failure.
        return {
          'mutation_id': mutationId,
          'outcome': 'applied',
          'revision': existing['revision'],
        };
      }
    }
    final row = {
      ...?existing,
      ...fields,
      if (kind == 'measurement' || kind == 'readingState')
        'entry_id': entityId
      else
        'id': entityId,
      'revision': ++revision,
      if (kind != 'measurement') 'updated_at': clientTime.toIso8601String(),
    };
    store[key] = row;
    feed.add({
      'type': 'entity',
      'entity_type': kind,
      'revision': row['revision'],
      'entity': row,
    });
    return {
      'mutation_id': mutationId,
      'outcome': 'applied',
      'revision': revision,
    };
  }

  /// Mirrors the server-side folder-delete reparent: children move to the
  /// deleted folder's parent and flow back as ordinary changes.
  void _reparentChildrenOf(String folderId, String target, DateTime at) {
    void moveAll(String kind, String field) {
      for (final row in kindRows(kind).values) {
        if (row[field] == folderId) {
          row[field] = target;
          row['revision'] = ++revision;
          row['updated_at'] = at.toIso8601String();
          feed.add({
            'type': 'entity',
            'entity_type': kind,
            'revision': row['revision'],
            'entity': Map<String, Object?>.from(row),
          });
        }
      }
    }

    moveAll('folder', 'parent_id');
    moveAll('collection', 'folder_id');
    moveAll('entry', 'folder_id');
  }

  (int, Map<String, Object?>) _resolve(String id, Map<String, Object?> body) {
    final store = kindRows('downloadRequest');
    final row = store[id];
    if (row == null) {
      return (
        404,
        {
          'error': {'code': 'unknown_entity', 'message': 'no such request'},
        },
      );
    }
    const terminal = {'completed', 'failed', 'cancelled'};
    if (terminal.contains(row['state'])) {
      return (
        409,
        {
          'error': {
            'code': 'download_request_terminal',
            'message': 'already terminal',
          },
        },
      );
    }
    final state = body['state'] as String?;
    if (!terminal.contains(state)) {
      return (
        400,
        {
          'error': {'code': 'validation_failed', 'message': 'not terminal'},
        },
      );
    }
    row['state'] = state;
    row['failure_reason'] = body['failure_reason'] ?? '';
    row['resolved_at'] = DateTime.now().toUtc().toIso8601String();
    row['revision'] = ++revision;
    feed.add({
      'type': 'entity',
      'entity_type': 'downloadRequest',
      'revision': row['revision'],
      'entity': Map<String, Object?>.from(row),
    });
    return (200, Map<String, Object?>.from(row));
  }

  void _reply(HttpRequest request, int status, Map<String, Object?> body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    request.response.close();
  }
}
