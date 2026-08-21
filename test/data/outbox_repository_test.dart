/// Outbox storage and sync bookkeeping (C10): ordered drain reads, attempt
/// recording, acknowledgement, and the singleton sync_state row.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('pending intents come back oldest first — the order they must reach '
      'the server in', () async {
    final seeded = await h.seedLibrary();
    await h.collections.rename(seeded.collection.id, 'Renamed once');
    await h.collections.rename(seeded.collection.id, 'Renamed twice');

    final rows = await h.outbox.pending();
    expect(rows.length, greaterThanOrEqualTo(3));
    final ids = rows.map((r) => r.opId).toList();
    expect(ids, List.of(ids)..sort(), reason: 'rowid order is the order');
    // Distinct mutation ids throughout.
    expect(rows.map((r) => r.mutationId).toSet().length, rows.length);
  });

  test('markAttempt counts and records the failure; ack removes', () async {
    final seeded = await h.seedLibrary();
    await h.collections.rename(seeded.collection.id, 'x');
    final rows = await h.outbox.pending();
    final first = rows.first;

    await h.outbox.markAttempt(first.opId, error: 'connection refused');
    var reread = (await h.outbox.pending()).first;
    expect(reread.attempts, 1);
    expect(reread.lastError, 'connection refused');

    await h.outbox.markAttempt(first.opId);
    reread = (await h.outbox.pending()).first;
    expect(reread.attempts, 2);

    final before = await h.outbox.pendingCount();
    await h.outbox.ack([first.opId]);
    expect(await h.outbox.pendingCount(), before - 1);
  });

  test('the pending count is derived by COUNT(*), never cached', () async {
    expect(await h.outbox.pendingCount(), 0);
    final seeded = await h.seedLibrary();
    final afterSeed = await h.outbox.pendingCount();
    expect(afterSeed, greaterThan(0));
    await h.collections.archive(seeded.collection.id);
    expect(await h.outbox.pendingCount(), afterSeed + 1);
    final all = await h.outbox.pending(limit: 1000);
    await h.outbox.ack(all.map((r) => r.opId));
    expect(await h.outbox.pendingCount(), 0);
  });

  test('sync_state is one row: cursor, attempts, success and error', () async {
    expect(await h.syncState.cursor(), 0, reason: 'cursor 0 is bootstrap');

    await h.syncState.setCursor(118);
    expect(await h.syncState.cursor(), 118);

    final t1 = DateTime.utc(2026, 8, 21, 12);
    await h.syncState.recordError('offline', t1);
    var row = await h.syncState.current();
    expect(row.lastError, 'offline');
    expect(row.lastAttemptAt?.toUtc(), t1);
    expect(row.lastSuccessAt, isNull);

    final t2 = DateTime.utc(2026, 8, 21, 13);
    await h.syncState.recordSuccess(t2);
    row = await h.syncState.current();
    expect(row.lastError, isNull, reason: 'success clears the error');
    expect(row.lastSuccessAt?.toUtc(), t2);
    expect(row.lastAttemptAt?.toUtc(), t2);
  });
}
