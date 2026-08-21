/// Harness for the V2 library UX widget tests (roadmap D1–D3).
///
/// An in-memory [LibraryDatabase] with the real repositories over it, the
/// screens' own provider graph pointed at them, and a recording source opener
/// in place of the Browser this lane does not own.
///
/// `pumpAndSettle` is deliberately absent: while a stream provider is still
/// loading, the screens show a `CircularProgressIndicator`, which animates
/// forever and would make settling time out.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/offline_copy_repository.dart';
import 'package:web_reader/data/reading_state_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

class UiHarness {
  UiHarness() : db = LibraryDatabase.forTesting(NativeDatabase.memory());

  final LibraryDatabase db;

  /// Built lazily, and that is load-bearing: `setUp` runs outside the fake
  /// async zone `testWidgets` installs, and [ReadingStateRepository] holds a
  /// `Future` chain created with it. Built there, its first `then` is
  /// scheduled on the real microtask queue and the awaiting test hangs
  /// forever. Built on first use — inside the test body — it is not.
  late final LibraryUiServices services = LibraryUiServices(db);

  /// Every URL the injected opener was handed, in order.
  final opened = <String>[];

  FolderRepository get folders => services.folders;
  CollectionRepository get collections => services.collections;
  EntryRepository get entries => services.entries;
  ReadingStateRepository get reading => services.reading;
  OfflineCopyRepository get offline => services.offline;

  Widget app(Widget home) => ProviderScope(
    overrides: [
      libraryUiServicesProvider.overrideWithValue(services),
      sourceOpenerProvider.overrideWithValue((url) async => opened.add(url)),
    ],
    child: MaterialApp(
      theme: appTheme(palette: AppPalette.light),
      home: home,
    ),
  );

  Future<void> close() => db.close();

  // ─── seeding ──────────────────────────────────────────────────────────────

  Future<FolderRow> root() => folders.ensureRoot();

  Future<FolderRow> folder(String name, {String? parentId}) async {
    final (row, violation) = await folders.create(name, parentId: parentId);
    expect(violation, isNull, reason: 'seeding a folder must not be refused');
    return row!;
  }

  Future<CollectionRow> collection(
    String name, {
    required String folderId,
    OrderingBasis basis = OrderingBasis.explicitNumericIndex,
  }) async {
    final (row, violation) = await collections.create(
      name: name,
      folderId: folderId,
      orderingBasis: basis,
    );
    expect(violation, isNull);
    return row!;
  }

  Future<EntryRow> entryIn(
    String collectionId, {
    required String title,
    double? ordinal,
    Placement placement = Placement.placed,
  }) async {
    final (row, violation) = await entries.createInCollection(
      collectionId: collectionId,
      ordinal: ordinal,
      placement: placement,
      title: title,
    );
    expect(violation, isNull);
    return row!;
  }

  Future<EntryRow> standaloneEntry({
    required String folderId,
    required String title,
  }) async {
    final (row, violation) = await entries.createStandalone(
      folderId: folderId,
      title: title,
    );
    expect(violation, isNull);
    return row!;
  }

  Future<SourceRow> source(
    String collectionId, {
    String host = 'reading.example.com',
    String pathKey = 'serial-alpha',
  }) async {
    final (row, violation) = await collections.addSource(
      collectionId: collectionId,
      host: host,
      pathKey: pathKey,
      language: 'en',
    );
    expect(violation, isNull);
    return row!;
  }

  /// A Location belongs to a Source exactly when its Entry belongs to a
  /// Collection (I7), so [sourceId] is required for an Entry inside one.
  Future<LocationRow> location(
    String entryId,
    String url, {
    String? sourceId,
  }) async {
    final (row, violation) = await entries.addLocation(
      entryId: entryId,
      sourceId: sourceId,
      url: url,
      urlKey: url,
    );
    expect(violation, isNull);
    return row!;
  }

  /// An active OfflineCopy: bytes this device holds. Never a reason for a row
  /// to be listed, and this harness never treats it as one.
  Future<void> copyFor(String entryId) => offline.recordCopy(
    entryId: entryId,
    locationUrl: 'https://reading.example.com/one',
    artifactFormat: 'imageSequence',
    contentPath: 'library/$entryId',
    byteSize: 2048,
  );

  Future<int> offlineCopyRows(String entryId) async {
    final rows = await (db.select(
      db.offlineCopies,
    )..where((c) => c.entryId.equals(entryId))).get();
    return rows.length;
  }
}

/// Pump frames until [finder] matches, then stop. 80 × 25ms is far longer than
/// an in-memory query takes and short enough to fail a hang quickly.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isEmpty) return;
  }
  fail('timed out waiting for $finder to go');
}

/// Tap, then give the frame loop a few turns — enough for a sheet or dialog
/// transition to finish without settling.
Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// `testWidgets`, but at a phone's shape and with the widget tree torn down
/// inside the test body.
///
/// Both halves are V1's lessons, unchanged (`test/library_ui_test.dart`).
/// Drift schedules a zero-duration timer when its query streams are disposed:
/// left to the framework's teardown, which lands after the test has ended,
/// every test fails with "pending timers" despite passing its assertions. And
/// the default 800×600 window is wider and much shorter than any phone, so
/// list rows fall off the bottom and finders miss widgets a real device
/// shows.
void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
