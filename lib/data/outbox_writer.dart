/// The one place a sync intent is recorded (roadmap C10).
///
/// Every mutation of a synced entity writes exactly one outbox row, in the
/// same database transaction as the entity write. The rule lives here and
/// nowhere else; every repository calls through this writer, so a write path
/// that forgets the outbox does not exist.
///
/// Payloads are the sparse `fields` object of the contract's
/// `MutationEnvelope` (contracts/openapi.yaml): wire-spelled snake_case keys,
/// ISO-8601 UTC timestamps, enum `name`s. The outbox row's `created_at` is the
/// envelope's `client_time` — it is written with the same clock value as the
/// entity row it accompanies, because that value is the row's merge clock.
///
/// Kinds are [SyncedEntityKind] only. An intent about an OfflineCopy or
/// history cannot be expressed (I11) — the enum omits them and the table's
/// CHECK refuses the spelling.
library;

import 'dart:convert';

import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'schema.dart';

/// A mutation operation, mirroring the contract envelope's `op`.
enum OutboxOp { upsert, delete }

class OutboxWriter {
  OutboxWriter(this._db, {IdGenerator? newId}) : _newId = newId ?? newLocalId;

  final LibraryDatabase _db;
  final IdGenerator _newId;

  /// Appends one intent. Must be called inside the transaction that performs
  /// the entity write it describes, with the same [at] the entity row was
  /// stamped with.
  Future<void> record({
    required SyncedEntityKind kind,
    required String entityId,
    required OutboxOp op,
    required DateTime at,
    Map<String, Object?>? fields,
  }) async {
    assert(
      op == OutboxOp.delete || fields != null,
      'an upsert intent carries fields',
    );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            mutationId: _newId(),
            entityKind: kind.name,
            entityId: entityId,
            op: op.name,
            payload: jsonEncode(fields ?? const <String, Object?>{}),
            createdAt: at,
          ),
        );
  }
}

/// Wire form of a timestamp: ISO-8601, UTC. Null stays null so a clearing
/// write is expressible (the envelope's fields are sparse; an explicit null
/// clears).
String? wireTime(DateTime? value) => value?.toUtc().toIso8601String();
