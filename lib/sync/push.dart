/// The push half of sync (roadmap G1): the outbox drained in order.
///
/// Envelopes carry the client-minted mutation id, so a retry after an
/// ambiguous failure is safe — the server's ledger answers `duplicate` with
/// the originally assigned revision, and both `applied` and `duplicate`
/// acknowledge the row. A `rejected` outcome parks the row with its named
/// reason and the drain continues: a rejection is deterministic, so resending
/// it would fail identically forever, and one bad intent must never dam the
/// queue behind it (V2_SYNC.md §1).
///
/// `downloadRequest` intents do not ride `/mutations` — the contract excludes
/// the kind because claim/resolve are single-winner transitions that cannot
/// be replayed from an async outbox. They route to
/// `POST /download-requests/{id}/resolve` individually.
library;

import 'dart:convert';

import '../data/schema.dart';
import '../domain/sync_kinds.dart';
import 'ids.dart';
import 'repositories.dart';
import 'transport.dart';

class PushResult {
  const PushResult({
    required this.acked,
    required this.rejected,
    this.stoppedBy,
  });

  final int acked;
  final int rejected;

  /// Set when the drain stopped early on a transport failure or an unusable
  /// server reply; the remaining rows retry on the next opportunity.
  final String? stoppedBy;

  bool get pushedAnything => acked > 0;
}

class SyncPusher {
  SyncPusher(this._repos);

  final SyncRepositories _repos;

  Future<PushResult> drainAll(SyncTransport transport, {int batch = 50}) async {
    var acked = 0;
    var rejected = 0;
    var after = 0;
    while (true) {
      final rows = await _repos.outbox.pendingAfter(after, limit: batch);
      if (rows.isEmpty) break;
      after = rows.last.opId;
      final mutationRows = <OutboxRow>[];
      for (final row in rows) {
        if (row.entityKind == SyncedEntityKind.downloadRequest.name) {
          final outcome = await _resolveDownloadRequest(transport, row);
          switch (outcome) {
            case _RowOutcome.acked:
              acked += 1;
            case _RowOutcome.rejected:
              rejected += 1;
            case _RowOutcome.stop:
              return PushResult(
                acked: acked,
                rejected: rejected,
                stoppedBy: row.lastError ?? 'transport failure',
              );
          }
        } else {
          mutationRows.add(row);
        }
      }
      if (mutationRows.isEmpty) continue;
      final envelopes = <Map<String, Object?>>[];
      for (final row in mutationRows) {
        envelopes.add(await _envelope(row));
      }
      final TransportReply reply;
      try {
        reply = await transport.postMutations({'mutations': envelopes});
      } on SyncTransportException catch (e) {
        for (final row in mutationRows) {
          await _repos.outbox.markAttempt(row.opId, error: e.message);
        }
        return PushResult(
          acked: acked,
          rejected: rejected,
          stoppedBy: e.message,
        );
      }
      if (!reply.ok) {
        final reason =
            'mutations: HTTP ${reply.status} ${reply.errorCode ?? ''}';
        for (final row in mutationRows) {
          await _repos.outbox.markAttempt(row.opId, error: reason);
        }
        return PushResult(acked: acked, rejected: rejected, stoppedBy: reason);
      }
      final results = <String, Map<String, Object?>>{};
      for (final raw in reply.body['results'] as List<Object?>? ?? const []) {
        final result = Map<String, Object?>.from(raw! as Map);
        results[result['mutation_id']! as String] = result;
      }
      for (final row in mutationRows) {
        final result = results[row.mutationId];
        if (result == null) {
          await _repos.outbox.markAttempt(
            row.opId,
            error: 'no result for mutation',
          );
          continue;
        }
        switch (result['outcome']) {
          case 'applied':
          case 'duplicate':
            await _repos.outbox.ack([row.opId]);
            acked += 1;
          case 'rejected':
            final error = result['error'];
            final code = error is Map ? error['code'] as String? : null;
            await _repos.outbox.markRejected(row.opId, code ?? 'rejected');
            rejected += 1;
          default:
            await _repos.outbox.markAttempt(
              row.opId,
              error: 'unrecognised outcome ${result['outcome']}',
            );
        }
      }
    }
    return PushResult(acked: acked, rejected: rejected);
  }

  Future<Map<String, Object?>> _envelope(OutboxRow row) async {
    final kind = SyncedEntityKind.values.byName(row.entityKind);
    final fields = Map<String, Object?>.from(jsonDecode(row.payload) as Map);
    return {
      'mutation_id': row.mutationId,
      'entity_type': row.entityKind,
      'entity_id': await _repos.ids.wireIdOf(entityIdKind(kind), row.entityId),
      'op': row.op,
      if (row.op == 'upsert')
        'fields': await _repos.ids.outboundFields(kind, fields),
      'client_time': row.createdAt.toUtc().toIso8601String(),
    };
  }

  Future<_RowOutcome> _resolveDownloadRequest(
    SyncTransport transport,
    OutboxRow row,
  ) async {
    final fields = Map<String, Object?>.from(jsonDecode(row.payload) as Map);
    final wireId = await _repos.ids.wireIdOf(
      SyncedEntityKind.downloadRequest,
      row.entityId,
    );
    final TransportReply reply;
    try {
      reply = await transport.resolveDownloadRequest(wireId, {
        'state': fields['state'],
        'failure_reason': fields['failure_reason'] ?? '',
      });
    } on SyncTransportException catch (e) {
      await _repos.outbox.markAttempt(row.opId, error: e.message);
      return _RowOutcome.stop;
    }
    if (reply.ok) {
      await _repos.outbox.ack([row.opId]);
      return _RowOutcome.acked;
    }
    if (reply.status == 409 && reply.errorCode == 'download_request_terminal') {
      // Already terminal on the server — this report has been made (perhaps
      // by a retry that lost its ack). Converged; acknowledge.
      await _repos.outbox.ack([row.opId]);
      return _RowOutcome.acked;
    }
    if (reply.status >= 500) {
      await _repos.outbox.markAttempt(
        row.opId,
        error: 'resolve: HTTP ${reply.status}',
      );
      return _RowOutcome.stop;
    }
    await _repos.outbox.markRejected(
      row.opId,
      reply.errorCode ?? 'resolve: HTTP ${reply.status}',
    );
    return _RowOutcome.rejected;
  }
}

enum _RowOutcome { acked, rejected, stop }
