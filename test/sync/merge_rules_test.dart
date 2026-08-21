/// The three merge characters, row by row (V2_SYNC.md §4.2). The pure rules
/// are tested here; their end-to-end application through pull is
/// pull_test.dart's job.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/sync/merge.dart';

void main() {
  final older = DateTime.utc(2026, 8, 21, 10);
  final newer = DateTime.utc(2026, 8, 21, 11);

  group('scalar — last write wins on the row clock', () {
    // §4.2 names: Folder name and placement, Collection rename and lifecycle,
    // preferred Source, Source lifecycle, reading state. One rule serves all:
    // the row clock decides, remote wins ties.
    test('a newer remote row replaces an older local row', () {
      expect(remoteRowWins(localClock: older, remoteClock: newer), isTrue);
    });

    test('an older remote row never clobbers a newer local row', () {
      expect(remoteRowWins(localClock: newer, remoteClock: older), isFalse);
    });

    test('a tie goes to the remote side, deterministically', () {
      expect(remoteRowWins(localClock: newer, remoteClock: newer), isTrue);
    });

    test('no local row means the remote row simply lands', () {
      expect(remoteRowWins(localClock: null, remoteClock: older), isTrue);
    });

    test('clocks compare in UTC regardless of representation', () {
      final local = DateTime.utc(2026, 8, 21, 12).toLocal();
      expect(remoteRowWins(localClock: local, remoteClock: newer), isFalse);
    });
  });

  group('set — add wins; removal only via tombstone', () {
    // §4.2 names: Sources of a Collection, Locations of an Entry, Entries of
    // a Collection, Folder children. Adds are row upserts; the only removal
    // is a tombstone, and a tombstone loses to an add written after it.
    test('a tombstone removes a row written before the deletion', () {
      expect(tombstoneWins(localClock: older, deletedAt: newer), isTrue);
    });

    test('an add written after the deletion survives it — add wins', () {
      expect(tombstoneWins(localClock: newer, deletedAt: older), isFalse);
    });

    test('a tombstone for a row this device never had is a no-op decision', () {
      expect(tombstoneWins(localClock: null, deletedAt: older), isTrue);
    });
  });

  group('keyed scalar — last write wins per key', () {
    // §4.2 names: Measurements, keyed (entry, source). Same clock rule,
    // applied per key; the key itself is never dropped (I12).
    test('per-key clock comparison is the scalar rule', () {
      expect(remoteRowWins(localClock: older, remoteClock: newer), isTrue);
      expect(remoteRowWins(localClock: newer, remoteClock: older), isFalse);
    });
  });
}
