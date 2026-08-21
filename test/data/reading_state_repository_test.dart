/// ReadingState repository (C6): access recording (I16), revertible
/// completion (V2-D6), and serialised writes — the concurrency posture ported
/// from V1's reading queue.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/reading_state.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('an Entry with no row reads as unread (I10)', () async {
    final seeded = await h.seedLibrary();
    final state = await h.reading.stateOf(seeded.entry.id);
    expect(state.status, ReadStatus.unread);
    expect(state.firstOpenedAt, isNull);
  });

  test('recordSourceAccess sets first-open once, last-read always, and never '
      'completes (I16)', () async {
    final seeded = await h.seedLibrary();
    final t1 = DateTime.utc(2026, 8, 21, 12);
    final t2 = DateTime.utc(2026, 8, 21, 13);

    final (s1, v1) = await h.reading.recordSourceAccess(
      seeded.entry.id,
      at: t1,
    );
    expect(v1, isNull);
    expect(s1!.status, ReadStatus.reading);
    expect(s1.firstOpenedAt, t1);
    expect(s1.lastReadAt, t1);
    expect(s1.completedAt, isNull);

    final (s2, _) = await h.reading.recordSourceAccess(seeded.entry.id, at: t2);
    expect(s2!.firstOpenedAt, t1, reason: 'first-open is written once');
    expect(s2.lastReadAt, t2);
    expect(s2.status, ReadStatus.reading, reason: 'access never completes');
  });

  test('completion is a value, not a floor: markUnread lowers it', () async {
    final seeded = await h.seedLibrary();
    final (read, _) = await h.reading.markRead(seeded.entry.id);
    expect(read!.status, ReadStatus.completed);
    expect(read.completedAt, isNotNull);

    final (unread, _) = await h.reading.markUnread(seeded.entry.id);
    expect(unread!.status, ReadStatus.unread);
    expect(unread.completedAt, isNull);
    expect(
      unread.firstOpenedAt,
      read.firstOpenedAt,
      reason: 'history stays — it happened',
    );

    // Access after unread starts the cycle again without resurrecting
    // completion.
    final (again, _) = await h.reading.recordSourceAccess(seeded.entry.id);
    expect(again!.status, ReadStatus.reading);
    expect(again.completedAt, isNull);
  });

  test('interleaved writes are serialised: the last operation wins and no '
      'stale write clobbers a newer one', () async {
    final seeded = await h.seedLibrary();
    // Fire without awaiting between them — the internal queue must order
    // them; the final state is the last call's.
    final futures = [
      h.reading.markRead(seeded.entry.id),
      h.reading.markUnread(seeded.entry.id),
      h.reading.recordSourceAccess(seeded.entry.id),
      h.reading.markRead(seeded.entry.id),
    ];
    await Future.wait(futures);
    final state = await h.reading.stateOf(seeded.entry.id);
    expect(state.status, ReadStatus.completed);
    expect(state.completedAt, isNotNull);
  });

  test('every mutation carries the full state field set on the wire', () async {
    final seeded = await h.seedLibrary();
    await h.reading.markRead(seeded.entry.id);
    final rows = await h.outbox.pending(limit: 100);
    final fields = jsonDecode(rows.last.payload) as Map<String, dynamic>;
    expect(fields.keys.toSet(), {
      'status',
      'first_opened_at',
      'last_read_at',
      'completed_at',
    });
    expect(fields['status'], 'completed');
  });

  test('a write against an unknown Entry is refused', () async {
    final (state, violation) = await h.reading.markRead('missing');
    expect(state, isNull);
    expect(violation, isNotNull);
  });
}
