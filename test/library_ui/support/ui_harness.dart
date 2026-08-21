/// Harness for the V2 library UX widget tests (roadmap D1–D6).
///
/// An in-memory [LibraryDatabase] with the real repositories over it — the real
/// [SaveQueueRepository] included, because the queue's rules are the thing
/// under test — a [FileStore] on a temporary directory, the screens' own
/// provider graph pointed at them, and recording stand-ins for the three seams
/// this lane does not own: the Browser, the thing that works through the queue,
/// and the placement transport.
///
/// `pumpAndSettle` is deliberately absent: while a stream provider is still
/// loading, the screens show a `CircularProgressIndicator`, which animates
/// forever and would make settling time out.
library;

import 'dart:io';

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
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/library_ui/placement_models.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

class UiHarness {
  UiHarness()
    : db = LibraryDatabase.forTesting(NativeDatabase.memory()),
      storeRoot = Directory.systemTemp.createTempSync('scrollary_library_ui');

  final LibraryDatabase db;

  /// Where this device's bytes live for the duration of one test. Real files:
  /// freeing a copy is bytes first and rows second, and a fake store could not
  /// tell the difference.
  final Directory storeRoot;

  /// Built lazily, and that is load-bearing: `setUp` runs outside the fake
  /// async zone `testWidgets` installs, and [ReadingStateRepository] holds a
  /// `Future` chain created with it. Built there, its first `then` is
  /// scheduled on the real microtask queue and the awaiting test hangs
  /// forever. Built on first use — inside the test body — it is not.
  late final LibraryUiServices services = LibraryUiServices(
    db,
    fileStore: FileStore(storeRoot),
  );

  /// Every URL the injected opener was handed, in order.
  final opened = <String>[];

  /// How many times the queue runner was handed an authorised queue.
  int starts = 0;

  /// The runner the Start control hands the queue to. **Set it before calling
  /// [app]** — the override is read when the tree is built. Null stands for a
  /// composition with nothing attached, where a Start authorises nothing.
  late SaveQueueStarter? starter = () async => starts++;

  /// Every placement this UI submitted, in order.
  final placements = <PlacementRequest>[];

  /// The placement transport. Reassignable at any point in a test — the
  /// override forwards to whatever this field holds when the call is made.
  late PlacementSubmit placement = (request) async {
    placements.add(request);
    return PlacementOutcome.applied(request.ordinal);
  };

  FolderRepository get folders => services.folders;
  CollectionRepository get collections => services.collections;
  EntryRepository get entries => services.entries;
  ReadingStateRepository get reading => services.reading;
  OfflineCopyRepository get offline => services.offline;
  SaveQueueRepository get queue => services.queue;
  FileStore get fileStore => services.fileStore;

  Widget app(Widget home) => ProviderScope(
    overrides: [
      libraryUiServicesProvider.overrideWithValue(services),
      sourceOpenerProvider.overrideWithValue((url) async => opened.add(url)),
      saveQueueStarterProvider.overrideWithValue(starter),
      placementSubmitProvider.overrideWithValue(
        (request) => placement(request),
      ),
    ],
    child: MaterialApp(
      theme: appTheme(palette: AppPalette.light),
      home: home,
    ),
  );

  Future<void> close() async {
    await db.close();
    if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
  }

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
    String language = 'en',
    SourceLifecycle lifecycle = SourceLifecycle.active,
    String? resolvedIntoSourceId,
  }) async {
    final (row, violation) = await collections.addSource(
      collectionId: collectionId,
      host: host,
      pathKey: pathKey,
      language: language,
    );
    expect(violation, isNull);
    if (lifecycle == SourceLifecycle.active) return row!;
    // A site's whole life is one row (V2-D14), so a dead or moved Source is
    // seeded by moving the row it already has.
    final refused = await collections.setSourceLifecycle(
      row!.id,
      lifecycle,
      resolvedIntoSourceId: resolvedIntoSourceId,
    );
    expect(refused, isNull, reason: 'seeding a lifecycle must not be refused');
    return (await collections.sourceById(row.id))!;
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

  /// An active OfflineCopy **and the bytes it names**: a package on disk and a
  /// row pointing at it. Never a reason for a row to be listed, and this
  /// harness never treats it as one.
  Future<void> copyFor(String entryId) async {
    final directory = Directory(fileStore.resolve(_copyPath(entryId)))
      ..createSync(recursive: true);
    File(
      '${directory.path}/${FileStore.manifestFileName}',
    ).writeAsStringSync('{}');
    await offline.recordCopy(
      entryId: entryId,
      locationUrl: 'https://reading.example.com/one',
      artifactFormat: 'imageSequence',
      contentPath: _copyPath(entryId),
      byteSize: 2048,
    );
  }

  /// Whether this device is still holding the package for [entryId].
  bool bytesOnDisk(String entryId) =>
      Directory(fileStore.resolve(_copyPath(entryId))).existsSync();

  String _copyPath(String entryId) => 'library/$entryId';

  Future<int> offlineCopyRows(String entryId) async {
    final rows = await (db.select(
      db.offlineCopies,
    )..where((c) => c.entryId.equals(entryId))).get();
    return rows.length;
  }

  /// The queue row for one Entry, whatever state it is in.
  Future<SaveTask?> taskFor(String entryId) async {
    final tasks = await queue.all();
    return tasks.where((t) => t.entryId == entryId).firstOrNull;
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

/// Give the real event loop a turn, for the one thing in this lane that needs
/// it: files.
///
/// `Directory.delete` is genuinely asynchronous, and a `testWidgets` fake clock
/// never turns it — awaiting one inside the test zone waits forever.
/// [WidgetTester.runAsync] runs the real loop long enough for the I/O to
/// complete; its continuation lands back on the fake zone's microtask queue,
/// which the next pump flushes. In-memory drift needs none of this, which is
/// why every other wait in these tests is an ordinary pump.
Future<void> letFilesSettle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
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
