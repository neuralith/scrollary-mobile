import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';
import 'package:web_reader/ui/palette.dart';

import '../tool/fixture/fixture_site.dart';

/// The reader's bottom controls: two entry-navigation controls with the reading
/// percentage between them.
///
/// What these tests are really about is the *availability* rule. A control that
/// offers an entry the reader cannot open sends the user to the unavailable
/// screen and loses their place in the one they were reading, so "is there a
/// previous entry" and "can it be opened" have to be the same question — asked
/// of the rows themselves, and asked again when something removes files while
/// the reader is still up.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late CleanupService cleanup;

  /// Short by default so the finalize timer cannot outlive a test; the one
  /// test that actually takes the undo asks for a window long enough that the
  /// real-time pumping in between cannot spend it.
  void useCleanup({Duration undoWindow = const Duration(milliseconds: 50)}) {
    cleanup = CleanupService(db: db, fileStore: store, undoWindow: undoWindow);
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_reader_controls');
    store = FileStore(root);
    useCleanup();
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 's1',
      title: 'Fixture Collection',
      sourceUrl: 'https://x.example/guide/s1',
      host: 'x.example',
      collectionKey: '/guide/s1',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  /// Real files, so the reader genuinely opens the entry rather than falling
  /// through to the unavailable state.
  Future<void> seedEntry(
    int n, {
    String? collectionId = 's1',
    String readStatus = 'unread',
  }) async {
    final id = 'c$n';
    final staging = await store.beginEntry(
      collectionId: collectionId ?? 'standalone',
      entryId: id,
    );
    final assets = <EntryAsset>[];
    for (var i = 1; i <= 3; i++) {
      await staging
          .assetFile('00$i.png')
          .writeAsBytes(panelPng(entry: n, index: i));
      assets.add(
        EntryAsset(
          index: i,
          sourceUrl: 'https://cdn.example/$n/$i.png',
          status: AssetStatus.stored,
          relativePath: 'assets/00$i.png',
          width: 800,
          height: 1200,
          dimensionsVerified: true,
        ),
      );
    }
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: id,
        collectionId: collectionId,
        sourceUrl: 'https://x.example/guide/s1/$n',
        title: 'Entry $n',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: 3,
        assets: assets,
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: id,
        collectionId: collectionId,
        title: 'Entry $n',
        sourceUrl: 'https://x.example/guide/s1/$n',
        urlKey: 'https://x.example/guide/s1/$n',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 3,
        storedAssetCount: 3,
        entryOrder: n,
        byteSize: 1500,
        entryNumber: n.toDouble(),
        sourceMarker: 'Entry $n',
        readStatus: readStatus,
        progressFraction: readStatus == 'completed' ? 1 : 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        completedAt: readStatus == 'completed' ? DateTime(2026, 7, 22) : null,
      ),
    );
  }

  /// Three entries in one collection, opened in the middle one so both
  /// directions exist.
  Future<void> seedThree() async {
    await seedCollection();
    for (var n = 1; n <= 3; n++) {
      await seedEntry(n);
    }
  }

  Widget harness(String entryId) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fileStoreProvider.overrideWithValue(store),
      cleanupProvider.overrideWithValue(cleanup),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ReaderScreen(entryId: entryId),
          ),
        ],
      ),
    ),
  );

  /// Real file IO cannot complete inside the fake-async zone, so the load is
  /// pumped with `runAsync` windows.
  Future<void> openReader(WidgetTester tester, String entryId) async {
    await tester.pumpWidget(harness(entryId));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ListView).evaluate().isNotEmpty) return;
    }
    fail('reader never finished loading');
  }

  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// Pump real-time windows until [ready], without advancing the fake clock —
  /// which would spend the reader notice's own timeout before it can be used.
  Future<void> pumpUntil(
    WidgetTester tester,
    Future<bool> Function() ready, {
    required String reason,
  }) async {
    for (var i = 0; i < 80; i++) {
      var done = false;
      await tester.runAsync(() async {
        done = await ready();
      });
      if (done) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail(reason);
  }

  /// Unmount inside the body so the undo/debounce timers do not outlive it.
  void readerTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    });
  }

  final previous = find.byTooltip('Previous saved entry');
  final next = find.byTooltip('Next saved entry');

  /// Whether an entry-step control can be tapped at all. Reads the control's
  /// own callback rather than a colour, so "looks disabled" and "is disabled"
  /// cannot drift apart.
  bool isEnabled(WidgetTester tester, Finder control) =>
      tester
          .widget<InkWell>(
            find.descendant(of: control, matching: find.byType(InkWell)),
          )
          .onTap !=
      null;

  Color chevronColour(WidgetTester tester, Finder control) => tester
      .widget<Icon>(find.descendant(of: control, matching: find.byType(Icon)))
      .color!;

  /// Which entry the reader currently has open, read off the top chrome.
  bool showsEntry(int n) =>
      find.text('Entry $n').evaluate().isNotEmpty &&
      find.byType(ListView).evaluate().isNotEmpty;

  // --- what the bar shows ---------------------------------------------------

  readerTest('the panel count is gone', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(find.textContaining('panel '), findsNothing);
    expect(
      find.textContaining(' / '),
      findsNothing,
      reason: 'no counter replaced it either',
    );
  });

  readerTest('the reading percentage is still rendered', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(find.text('0%'), findsOneWidget);
  });

  readerTest('the percentage sits in the centre, between the two controls', (
    tester,
  ) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    final width = tester.getSize(find.byType(ReaderScreen)).width;
    final centre = tester.getCenter(find.text('0%')).dx;

    expect(
      (centre - width / 2).abs(),
      lessThan(1),
      reason: 'the percentage is the stable central element',
    );
    expect(tester.getCenter(previous).dx, lessThan(centre));
    expect(tester.getCenter(next).dx, greaterThan(centre));
  });

  readerTest('both controls name the unit and their destination', (
    tester,
  ) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    // The words, so nothing reads as a step inside the page…
    expect(
      find.descendant(of: previous, matching: find.text('Previous entry')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: next, matching: find.text('Next entry')),
      findsOneWidget,
    );
    // …the direction…
    expect(
      find.descendant(of: previous, matching: find.byIcon(Icons.chevron_left)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: next, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    // …and which entry each one actually goes to.
    expect(
      find.descendant(of: previous, matching: find.text('Entry 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: next, matching: find.text('Entry 3')),
      findsOneWidget,
    );
  });

  readerTest('both controls are at least a 48px tap target', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(tester.getSize(previous).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
  });

  // --- when navigation is possible -----------------------------------------

  readerTest('previous is enabled and moves back one entry', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(isEnabled(tester, previous), isTrue);
    expect(chevronColour(tester, previous), ReaderColors.ink);

    await tester.tap(previous);
    await settle(tester);

    expect(showsEntry(1), isTrue);
    expect(
      isEnabled(tester, previous),
      isFalse,
      reason: 'the first entry has nothing before it',
    );
    expect(isEnabled(tester, next), isTrue);
  });

  readerTest('next is enabled and moves on one entry', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(isEnabled(tester, next), isTrue);
    await tester.tap(next);
    await settle(tester);

    expect(showsEntry(3), isTrue);
    expect(
      isEnabled(tester, next),
      isFalse,
      reason: 'the last entry has nothing after it',
    );
    expect(isEnabled(tester, previous), isTrue);
  });

  readerTest('a standalone entry offers neither direction', (tester) async {
    await tester.runAsync(() => seedEntry(1, collectionId: null));
    await openReader(tester, 'c1');

    expect(isEnabled(tester, previous), isFalse);
    expect(isEnabled(tester, next), isFalse);
  });

  // --- when it is not ------------------------------------------------------

  readerTest('previous disables itself when that entry stops being openable', (
    tester,
  ) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');
    expect(isEnabled(tester, previous), isTrue);

    // The reader's own finished-entry flow does exactly this to the entry
    // just left behind; here it is driven directly so the removal, and not a
    // reload, is what the control has to react to.
    await tester.runAsync(() => cleanup.removeOffline(['c1']));
    await settle(tester, rounds: 20);

    expect(
      isEnabled(tester, previous),
      isFalse,
      reason: 'its downloads are gone, so opening it could only fail',
    );
    expect(
      find.descendant(of: previous, matching: find.text('Entry 1')),
      findsNothing,
      reason: 'a destination that cannot be reached is not named',
    );
    expect(
      chevronColour(tester, previous),
      ReaderColors.inkDisabled,
      reason: 'and it reads as disabled rather than merely inert',
    );
    // Nothing else moved: the entry being read is untouched.
    expect(showsEntry(2), isTrue);
    expect(isEnabled(tester, next), isTrue);
  });

  readerTest('a disabled previous control navigates nowhere', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');
    await tester.runAsync(() => cleanup.removeOffline(['c1']));
    await settle(tester, rounds: 20);

    await tester.tap(previous, warnIfMissed: false);
    await settle(tester, rounds: 20);

    expect(showsEntry(2), isTrue, reason: 'the reader did not move');
    expect(
      (await db.entryById('c1'))!.offlineRemovedAt,
      isNotNull,
      reason: 'and nothing tried to bring the removed entry back',
    );
  });

  readerTest('the entry left behind keeps its reading state', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    // Read a little — nowhere near the end — then move on.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(next);
    await settle(tester);
    expect(showsEntry(3), isTrue);

    final left = (await db.entryById('c2'))!;
    expect(left.progressFraction, greaterThan(0));
    expect(left.progressUpdatedAt, isNotNull);
    expect(
      left.readStatus,
      'inProgress',
      reason: 'moving on is not finishing, and this entry is barely started',
    );
    expect(left.contentPath, isNotNull, reason: 'nothing was deleted');
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'and nothing was asked about it either',
    );
  });

  readerTest('the last entry offers no way forward', (tester) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c3');

    expect(isEnabled(tester, next), isFalse);
    expect(
      find.descendant(of: next, matching: find.text('Next entry')),
      findsOneWidget,
      reason: 'the control still names the unit; it just has nowhere to go',
    );
    expect(isEnabled(tester, previous), isTrue);
  });

  readerTest(
    'finishing an entry and moving on disables the way back — and Undo '
    'brings it back',
    (tester) async {
      // The route the user actually takes into this state: a finished entry, a
      // collection already set to clear its downloads, and one tap forward.
      useCleanup(undoWindow: const Duration(minutes: 5));
      await tester.runAsync(() async {
        await seedCollection();
        await seedEntry(1, readStatus: 'completed');
        await seedEntry(2);
        await db.setCollectionCleanupPreference(
          's1',
          CollectionCleanupPreference.remove.name,
        );
      });
      await openReader(tester, 'c1');

      await tester.tap(next);
      await pumpUntil(
        tester,
        () async => find.text('Removed downloads').evaluate().isNotEmpty,
        reason: 'the removal notice never appeared',
      );
      // The notice lives outside the loader, so it can be up while the entry
      // arriving is still being read off disk.
      await pumpUntil(
        tester,
        () async => find.byType(ListView).evaluate().isNotEmpty,
        reason: 'the next entry never opened',
      );

      expect(showsEntry(2), isTrue);
      expect(
        isEnabled(tester, previous),
        isFalse,
        reason:
            'the reader itself just removed that entry\'s downloads, so the '
            'control pointing at it cannot stay lit',
      );
      expect((await db.entryById('c1'))!.contentPath, isNull);

      await tester.tap(find.text('Undo'));
      await settle(tester, rounds: 20);

      expect(
        isEnabled(tester, previous),
        isTrue,
        reason: 'the files are back, so the destination is real again',
      );
      expect(
        find.descendant(of: previous, matching: find.text('Entry 1')),
        findsOneWidget,
      );
    },
  );

  // --- progress is untouched ------------------------------------------------

  readerTest('the centred percentage still tracks the scroll and persists', (
    tester,
  ) async {
    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');
    expect(find.text('0%'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('0%'),
      findsNothing,
      reason: 'the readout moves while scrolling',
    );

    // Still centred once the number has grown.
    final width = tester.getSize(find.byType(ReaderScreen)).width;
    final percent = find.descendant(
      of: find.byType(ReaderScreen),
      matching: find.textContaining('%'),
    );
    expect((tester.getCenter(percent).dx - width / 2).abs(), lessThan(1));

    await tester.pump(const Duration(seconds: 3));
    expect((await db.entryById('c2'))!.progressUpdatedAt, isNotNull);
  });

  // --- layout ---------------------------------------------------------------

  for (final width in <double>[320, 360, 414]) {
    readerTest('the bar lays out without overflow at ${width}pt', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(tester.view.reset);

      await tester.runAsync(seedThree);
      await openReader(tester, 'c2');

      expect(tester.takeException(), isNull);
      expect(find.text('0%'), findsOneWidget);
      expect(
        find.descendant(of: previous, matching: find.text('Previous entry')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: next, matching: find.text('Next entry')),
        findsOneWidget,
      );
    });
  }

  readerTest('and at a larger text scale on a narrow screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.runAsync(seedThree);
    await openReader(tester, 'c2');

    expect(tester.takeException(), isNull);
    expect(find.text('0%'), findsOneWidget);
  });
}
