import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/resume_point.dart';
import 'package:web_reader/features/library_screen.dart' show LibraryCollection;
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/database.dart';

/// What a Continue card says about how much is left.
///
/// The number is always "readable entries after this one on this device" —
/// never a collection total, because a collection added from the middle has no local
/// evidence of what the source published.
void main() {
  Entry row(
    int n, {
    String saveStatus = 'complete',
    bool offline = true,
    String readStatus = 'unread',
    double progress = 0,
  }) => Entry(
    host: '',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    id: 'c$n',
    collectionId: 's1',
    title: 'Collection Entry $n',
    sourceUrl: 'https://x.example/guide/s1/$n',
    urlKey: 'https://x.example/guide/s1/$n',
    artifactFormat: 'imageSequence',
    saveStatus: saveStatus,
    contentPath: offline ? 'library/s1/entries/c$n' : null,
    savedAt: DateTime(2026, 7, 20),
    detectedAssetCount: 6,
    storedAssetCount: 6,
    entryOrder: n,
    byteSize: 1024,
    entryNumber: n.toDouble(),
    sourceMarker: 'Entry $n',
    readStatus: readStatus,
    progressFraction: progress,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

  final item = Collection(
    contentKind: 'unknownWebContent',
    sequenceKind: 'none',
    orderingBasis: 'discoveryOrder',
    shapeConfidence: 'low',
    lifecycle: 'active',
    id: 's1',
    title: 'Collection',
    sourceUrl: 'https://x.example/guide/s1',
    host: 'x.example',
    collectionKey: '/guide/s1',
    createdAt: DateTime(2026, 7, 1),
  );

  ResumePoint pointFor(List<Entry> entries) {
    final state = computeCollectionReadingState(entries);
    return ResumePoint(
      group: LibraryCollection(collection: item, entries: entries),
      entry: state.continueEntry!,
      state: state,
    );
  }

  test('counts only the entries after the one being continued', () {
    final point = pointFor([
      row(1, readStatus: 'inProgress', progress: 0.68),
      row(2),
      row(3),
    ]);

    expect(point.laterEntryCount, 2);
    expect(point.laterEntriesLabel, '2 saved items remaining');
  });

  test('one later entry is singular', () {
    final point = pointFor([
      row(1, readStatus: 'inProgress', progress: 0.1),
      row(2),
    ]);

    expect(point.laterEntriesLabel, '1 saved item remaining');
  });

  test('the newest readable entry is a state, not "0 remaining"', () {
    final point = pointFor([
      row(1, readStatus: 'completed', progress: 1),
      row(2, readStatus: 'inProgress', progress: 0.5),
    ]);

    expect(point.laterEntryCount, 0);
    expect(point.laterEntriesLabel, 'Latest saved item available');
  });

  test('entries before the current one are not counted', () {
    // Resuming an earlier entry: the two after it are what is left, and the
    // finished one before it is not.
    final point = pointFor([
      row(1, readStatus: 'inProgress', progress: 0.3),
      row(2, readStatus: 'completed', progress: 1),
      row(3),
    ]);

    expect(point.entry.id, 'c1');
    expect(point.laterEntriesLabel, '2 saved items remaining');
  });

  test('entries that cannot be opened are not "remaining"', () {
    final point = pointFor([
      row(1, readStatus: 'inProgress', progress: 0.2),
      // Discovered by an update check, never saved.
      row(2, saveStatus: 'knownRemote', offline: false),
      // The user freed up its space (D35).
      row(3, offline: false),
      row(4, saveStatus: 'failed', offline: false),
      row(5),
    ]);

    expect(point.laterEntryCount, 1);
    expect(point.laterEntriesLabel, '1 saved item remaining');
  });

  test('a partially saved entry still counts — it can be read', () {
    final point = pointFor([
      row(1, readStatus: 'inProgress', progress: 0.4),
      row(2, saveStatus: 'partial'),
    ]);

    expect(point.laterEntriesLabel, '1 saved item remaining');
  });
}
