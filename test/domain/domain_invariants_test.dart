/// Invariant tests for the pure V2 domain (docs/V2_ARCHITECTURE.md §3).
///
/// These cite invariant numbers so a failure names the rule it broke. The
/// SQL-layer twins live in test/data/schema_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/domain.dart';

void main() {
  group('I1 — one root, and only the root is parentless', () {
    test('root with a parent is refused', () {
      const folder = Folder(
        id: 'f1',
        kind: FolderKind.root,
        name: 'Library',
        parentId: 'f0',
      );
      expect(folder.validate()?.invariant, 'I1');
    });

    test('user folder without a parent is refused', () {
      const folder = Folder(id: 'f1', kind: FolderKind.user, name: 'Weekly');
      expect(folder.validate()?.invariant, 'I1');
    });

    test('root without a parent and user folder with one are valid', () {
      const root = Folder(id: 'f0', kind: FolderKind.root, name: 'Library');
      const child = Folder(
        id: 'f1',
        kind: FolderKind.user,
        name: 'Weekly',
        parentId: 'f0',
      );
      expect(root.validate(), isNull);
      expect(child.validate(), isNull);
    });
  });

  group('I2 — the folder tree has no cycles', () {
    test('a folder may not be its own parent', () {
      const folder = Folder(
        id: 'f1',
        kind: FolderKind.user,
        name: 'Weekly',
        parentId: 'f1',
      );
      expect(folder.validate()?.invariant, 'I2');
    });

    test('moving a folder under its own descendant is a cycle', () {
      final parentOf = {'root': null, 'a': 'root', 'b': 'a', 'c': 'b'};
      expect(
        wouldCreateFolderCycle(
          parentOf: parentOf,
          folderId: 'a',
          newParentId: 'c',
        ),
        isTrue,
      );
    });

    test('moving a folder sideways is not a cycle', () {
      final parentOf = {'root': null, 'a': 'root', 'b': 'root'};
      expect(
        wouldCreateFolderCycle(
          parentOf: parentOf,
          folderId: 'a',
          newParentId: 'b',
        ),
        isFalse,
      );
    });
  });

  group('I3 — an Entry has a Folder iff it has no Collection', () {
    test('both set is refused', () {
      const entry = Entry(
        id: 'e1',
        placement: Placement.placed,
        collectionId: 'c1',
        folderId: 'f1',
      );
      expect(entry.validate()?.invariant, 'I3');
    });

    test('neither set is refused', () {
      const entry = Entry(id: 'e1', placement: Placement.placed);
      expect(entry.validate()?.invariant, 'I3');
    });

    test('a standalone Entry lives in a Folder and is valid', () {
      const entry = Entry(
        id: 'e1',
        placement: Placement.placed,
        folderId: 'f1',
      );
      expect(entry.validate(), isNull);
      expect(entry.standalone, isTrue);
    });
  });

  test('an unplaced Entry carries no ordinal', () {
    const entry = Entry(
      id: 'e1',
      placement: Placement.unplaced,
      collectionId: 'c1',
      ordinal: 12,
    );
    expect(entry.validate(), isNotNull);
  });

  group('I7 — a Location has a Source iff its Entry has a Collection', () {
    const collectionEntry = Entry(
      id: 'e1',
      placement: Placement.placed,
      collectionId: 'c1',
    );
    const standaloneEntry = Entry(
      id: 'e2',
      placement: Placement.placed,
      folderId: 'f1',
    );

    test('sourced Location on a standalone Entry is refused', () {
      const location = Location(
        id: 'l1',
        entryId: 'e2',
        url: 'https://example.com/a',
        urlKey: 'example.com/a',
        sourceId: 's1',
      );
      expect(location.validateAgainstEntry(standaloneEntry)?.invariant, 'I7');
    });

    test('sourceless Location on a Collection Entry is refused', () {
      const location = Location(
        id: 'l1',
        entryId: 'e1',
        url: 'https://example.com/a',
        urlKey: 'example.com/a',
      );
      expect(location.validateAgainstEntry(collectionEntry)?.invariant, 'I7');
    });

    test('an empty url_key is never valid', () {
      const location = Location(
        id: 'l1',
        entryId: 'e1',
        url: 'https://example.com/a',
        urlKey: '',
        sourceId: 's1',
      );
      expect(location.validateAgainstEntry(collectionEntry), isNotNull);
    });
  });

  group('I9 — a preferred Source belongs to its Collection', () {
    const collection = Collection(
      id: 'c1',
      folderId: 'f1',
      name: 'Work',
      orderingBasis: OrderingBasis.explicitNumericIndex,
      preferredSourceId: 's1',
    );

    test('a Source of another Collection is refused', () {
      const foreign = Source(
        id: 's1',
        collectionId: 'c2',
        host: 'example.com',
        pathKey: 'work',
      );
      expect(collection.validatePreferredSource(foreign)?.invariant, 'I9');
    });

    test('its own Source is accepted', () {
      const own = Source(
        id: 's1',
        collectionId: 'c1',
        host: 'example.com',
        pathKey: 'work',
      );
      expect(collection.validatePreferredSource(own), isNull);
    });
  });

  test('I12 — a Measurement names its Source and stays a fraction', () {
    final unscoped = Measurement(
      entryId: 'e1',
      sourceId: '',
      fraction: 0.5,
      observedAt: DateTime.utc(2026),
    );
    expect(unscoped.validate()?.invariant, 'I12');

    final overflowing = Measurement(
      entryId: 'e1',
      sourceId: 's1',
      fraction: 1.5,
      observedAt: DateTime.utc(2026),
    );
    expect(overflowing.validate(), isNotNull);
  });

  group('I15 — retraction is source-scoped', () {
    const onA = Location(
      id: 'l1',
      entryId: 'e1',
      url: 'https://example.com/a',
      urlKey: 'example.com/a',
      sourceId: 'sourceA',
    );

    test('a reading of Source A may retract its own Location', () {
      expect(
        mayRetractLocation(readingSourceId: 'sourceA', location: onA),
        isTrue,
      );
    });

    test('a reading of Source B may never retract Source A', () {
      expect(
        mayRetractLocation(readingSourceId: 'sourceB', location: onA),
        isFalse,
      );
    });

    test('a standalone Location is never retracted by source reading', () {
      const standalone = Location(
        id: 'l2',
        entryId: 'e2',
        url: 'https://example.com/b',
        urlKey: 'example.com/b',
      );
      expect(
        mayRetractLocation(readingSourceId: 'sourceA', location: standalone),
        isFalse,
      );
    });
  });

  group('I16 — a source read is access, never completion', () {
    test('unread becomes reading, never completed', () {
      const state = ReadingState(entryId: 'e1');
      final after = state.recordSourceAccess(DateTime.utc(2026, 1, 2));
      expect(after.status, ReadStatus.reading);
      expect(after.completedAt, isNull);
      expect(after.firstOpenedAt, DateTime.utc(2026, 1, 2));
      expect(after.lastReadAt, DateTime.utc(2026, 1, 2));
    });

    test('first-opened is written once', () {
      const state = ReadingState(entryId: 'e1');
      final after = state
          .recordSourceAccess(DateTime.utc(2026, 1, 2))
          .recordSourceAccess(DateTime.utc(2026, 1, 5));
      expect(after.firstOpenedAt, DateTime.utc(2026, 1, 2));
      expect(after.lastReadAt, DateTime.utc(2026, 1, 5));
    });

    test('completed stays completed — access does not regress it', () {
      final state = ReadingState(
        entryId: 'e1',
        status: ReadStatus.completed,
        completedAt: DateTime.utc(2026, 1, 1),
      );
      final after = state.recordSourceAccess(DateTime.utc(2026, 1, 2));
      expect(after.status, ReadStatus.completed);
      expect(after.completedAt, DateTime.utc(2026, 1, 1));
    });
  });

  group('I17 — a DownloadRequest is claimed once and resolves terminally', () {
    final pending = DownloadRequest(
      id: 'r1',
      entryId: 'e1',
      state: DownloadRequestState.pending,
    );

    test('exactly one claim wins', () {
      final (claimed, violation) = pending.claim(
        device: 'phone',
        at: DateTime.utc(2026),
      );
      expect(violation, isNull);
      expect(claimed!.state, DownloadRequestState.claimed);
      expect(claimed.claimedByDevice, 'phone');

      final (second, lost) = claimed.claim(
        device: 'tablet',
        at: DateTime.utc(2026),
      );
      expect(second, isNull);
      expect(lost, isNotNull);
    });

    test('resolving to a non-terminal state is refused', () {
      final (claimed, _) = pending.claim(
        device: 'phone',
        at: DateTime.utc(2026),
      );
      final (resolved, violation) = claimed!.resolve(
        to: DownloadRequestState.claimed,
        at: DateTime.utc(2026),
      );
      expect(resolved, isNull);
      expect(violation, isNotNull);
    });

    test('terminal states are exactly completed, failed, cancelled', () {
      const terminal = {
        DownloadRequestState.completed,
        DownloadRequestState.failed,
        DownloadRequestState.cancelled,
      };
      for (final state in DownloadRequestState.values) {
        expect(state.terminal, terminal.contains(state), reason: '$state');
      }
    });
  });

  group('V2-D16 — cross-source equivalence is gated and conservative', () {
    test('only an explicit numeric index supports merging', () {
      for (final basis in OrderingBasis.values) {
        expect(
          basis.supportsCrossSourceMerge,
          basis == OrderingBasis.explicitNumericIndex,
          reason: '$basis',
        );
      }
    });

    test('equal ordinals merge', () {
      expect(
        crossSourceEquivalence(
          basis: OrderingBasis.explicitNumericIndex,
          existingOrdinal: 100,
          observedOrdinal: 100,
        ),
        EquivalenceDecision.sameEntry,
      );
    });

    test('100 against 99.5 stays two Entries', () {
      expect(
        crossSourceEquivalence(
          basis: OrderingBasis.explicitNumericIndex,
          existingOrdinal: 100,
          observedOrdinal: 99.5,
        ),
        EquivalenceDecision.distinctEntries,
      );
    });

    test('no observed ordinal means unplaced, never guessed', () {
      expect(
        crossSourceEquivalence(
          basis: OrderingBasis.explicitNumericIndex,
          existingOrdinal: 100,
          observedOrdinal: null,
        ),
        EquivalenceDecision.unplaced,
      );
    });

    test('a date-ordered Collection never merges, even on equal numbers', () {
      expect(
        crossSourceEquivalence(
          basis: OrderingBasis.publicationDate,
          existingOrdinal: 100,
          observedOrdinal: 100,
        ),
        EquivalenceDecision.distinctEntries,
      );
    });
  });

  test('I11 — no synced kind exists for device-owned state', () {
    final names = SyncedEntityKind.values.map((k) => k.name).toSet();
    expect(names, {
      'folder',
      'collection',
      'source',
      'entry',
      'location',
      'readingState',
      'measurement',
      'downloadRequest',
    });
    // The absence that matters: nothing can express an intent about an
    // offline copy, history, hints or anchors.
    expect(names.any((n) => n.toLowerCase().contains('offline')), isFalse);
    expect(names.any((n) => n.toLowerCase().contains('history')), isFalse);
  });
}
