/// An in-process fake of the sync service, faithful to the contract's
/// semantics: the mutation ledger's idempotency, per-library revisions, the
/// revision-ordered change feed with tombstones, scalar LWW on the client
/// clock, arbitration, the single-winner download-request claim and the
/// terminal-only resolve.
///
/// **It refuses an unknown field, exactly as the service does.** The real
/// merge is an allowlist (`internal/sync/fields.go`), and a field it does not
/// know is `validation_failed` rather than a silent drop — so a client that
/// sends one has its intent parked forever. A fake that accepted anything
/// would let that ship. The vocabulary is read from `contracts/openapi.yaml`,
/// never restated here, which makes every push test in this directory a parity
/// test between the app's payloads and the contract.
///
/// Deterministic and network-local; the real service is exercised by the
/// integration lane, never by these unit tests.
library;

import 'dart:convert';
import 'dart:io';

import 'contract_vocabulary.dart';

class FakeBackend {
  int revision = 0;

  /// kind → wire id → row (snake_case, carrying `revision`/`updated_at`).
  final Map<String, Map<String, Map<String, Object?>>> rows = {};

  /// Ordered feed of `{type, revision, entity_type?, entity?, tombstone?}`.
  final List<Map<String, Object?>> feed = [];

  /// mutation_id → the result originally returned.
  final Map<String, Map<String, Object?>> ledger = {};

  final List<List<Map<String, Object?>>> mutationBatches = [];

  /// Every `/claim` this server was asked for, in order — including the losing
  /// ones, which is how a race is told apart from a single caller.
  final List<String> claimRequests = [];

  /// Every `/resolve`, with the body the device reported.
  final List<(String, Map<String, Object?>)> resolveRequests = [];

  /// When set, `/mutations` answers HTTP 500 this many times first.
  int failMutationsTimes = 0;

  /// When set, the Nth `/changes` request (1-based) destroys the socket.
  int dieOnChangesRequest = 0;
  int changesRequests = 0;

  /// Rejects any upsert whose fields contain this marker key.
  static const rejectMarker = 'reject_me';

  /// What each entity kind may carry, from the contract. Read once.
  static final Map<String, Set<String>> vocabulary = contractMutableFields();

  /// Every field this server refused, so a test can say which one it was.
  final List<String> refusedFields = [];

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
    _publish(kind, id, stamped);
    return stamped;
  }

  /// Re-stamps a stored row at a fresh revision, exactly as a rename or a
  /// lifecycle change does. The row keeps its single place on the feed — the
  /// new one, at the end — which is how a parent comes to sort *after* its own
  /// children.
  Map<String, Object?> touch(
    String kind,
    String id, {
    DateTime? updatedAt,
    Map<String, Object?> fields = const {},
  }) {
    final row = kindRows(kind)[id]!;
    final stamped = {
      ...row,
      ...fields,
      'revision': ++revision,
      if (kind != 'measurement' &&
          kind != 'downloadRequest' &&
          updatedAt != null)
        'updated_at': updatedAt.toIso8601String(),
      if (kind == 'measurement' && updatedAt != null)
        'observed_at': updatedAt.toIso8601String(),
    };
    kindRows(kind)[id] = stamped;
    _publish(kind, id, stamped);
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
    _forget(kind, sourceId == null ? entityId : '$entityId|$sourceId');
    final t = {
      'kind': kind,
      'entity_id': entityId,
      'source_id': ?sourceId,
      'revision': ++revision,
      'deleted_at': (deletedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    feed.add({'type': 'tombstone', 'revision': t['revision'], 'tombstone': t});
  }

  /// Puts a row on the feed at its current revision, replacing the entry it
  /// had. **The feed carries each row once**, like the service's own
  /// revision-ordered query — a row that changes moves, it does not
  /// accumulate history (contracts/openapi.yaml `GET /changes`).
  void _publish(String kind, String key, Map<String, Object?> row) {
    _forget(kind, key);
    feed.add({
      'type': 'entity',
      'entity_type': kind,
      'revision': row['revision'],
      'entity': row,
    });
  }

  void _forget(String kind, String key) => feed.removeWhere(
    (item) =>
        item['type'] == 'entity' &&
        item['entity_type'] == kind &&
        _feedKey(kind, item['entity']! as Map<String, Object?>) == key,
  );

  String _feedKey(String kind, Map<String, Object?> entity) {
    final id = (entity['id'] ?? entity['entry_id'])! as String;
    return kind == 'measurement' ? '$id|${entity['source_id']}' : id;
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
      final claim = RegExp(
        r'^/download-requests/([^/]+)/claim$',
      ).firstMatch(path);
      if (request.method == 'POST' && claim != null) {
        claimRequests.add(claim.group(1)!);
        final (status, reply) = _claim(claim.group(1)!, json);
        return _reply(request, status, reply);
      }
      final resolve = RegExp(
        r'^/download-requests/([^/]+)/resolve$',
      ).firstMatch(path);
      if (request.method == 'POST' && resolve != null) {
        resolveRequests.add((resolve.group(1)!, json));
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
      _forget(kind, key);
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
    // The allowlist, as the service applies it. `reject_me` above is checked
    // first because it is this fake's own marker and is not contract
    // vocabulary; everything after it is.
    final allowed = vocabulary[kind]!;
    for (final key in fields.keys) {
      if (!allowed.contains(key)) {
        refusedFields.add('$kind.$key');
        return rejected('validation_failed');
      }
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
    _publish(kind, key, row);
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
          _publish(kind, row['id']! as String, Map<String, Object?>.from(row));
        }
      }
    }

    moveAll('folder', 'parent_id');
    moveAll('collection', 'folder_id');
    moveAll('entry', 'folder_id');
  }

  /// The single-winner claim: `pending → claimed` for exactly one caller.
  /// Everyone else gets 409 naming the device that holds it, which is what
  /// lets a device recognise a claim it won and then died before recording.
  (int, Map<String, Object?>) _claim(String id, Map<String, Object?> body) {
    final row = kindRows('downloadRequest')[id];
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
            'message': 'this request already reached a terminal state',
          },
        },
      );
    }
    if (row['state'] != 'pending') {
      return (
        409,
        {
          'error': {
            'code': 'download_request_already_claimed',
            'message': 'another device already claimed this request',
            'details': {'claimed_by_device': row['claimed_by_device'] ?? ''},
          },
        },
      );
    }
    row['state'] = 'claimed';
    row['claimed_by_device'] = body['device'];
    row['claimed_at'] = DateTime.now().toUtc().toIso8601String();
    row['revision'] = ++revision;
    _publish('downloadRequest', id, Map<String, Object?>.from(row));
    return (200, Map<String, Object?>.from(row));
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
    _publish('downloadRequest', id, Map<String, Object?>.from(row));
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
