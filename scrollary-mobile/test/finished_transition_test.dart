import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

/// The finished-entry transition, driven through the real reader: when the
/// collection is asked, what each answer stores, and that the answer belongs to
/// that collection and to no other (D37).
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  /// The service the reader under test is using. Assigned by [harness], so a
  /// test can read the reader lock it moves.
  late CleanupService cleanup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_finish');
    store = FileStore(root);
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

  Future<void> seedCollection({String id = 's1', String title = 'Foo'}) =>
      db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: id,
          title: title,
          sourceUrl: 'https://x.example/guide/$id',
          host: 'x.example',
          collectionKey: '/guide/$id',
          createdAt: DateTime(2026, 7, 1),
        ),
      );

  /// Entry ids stay `c1`, `c2`… for the first collection so the common case
  /// reads plainly; a second collection prefixes its own.
  String entryId(String collectionId, int n) =>
      collectionId == 's1' ? 'c$n' : '${collectionId}c$n';

  /// Three 800×1200 panels at the 800pt test viewport are 1200pt tall each:
  /// 3600pt of content against a 600pt viewport, so 3000pt of travel is the
  /// whole entry. Progress is seeded as a fraction and the anchor is derived
  /// from it, so the position the reader restores to and the fraction it
  /// computes once laid out are the same number.
  const panelHeight = 1200.0;
  const travel = 3000.0;
  const panelCount = 3;

  int anchorIndexFor(double progress) {
    final index = (progress.clamp(0.0, 1.0) * travel) ~/ panelHeight;
    return index >= panelCount ? panelCount - 1 : index;
  }

  double anchorOffsetFor(double progress) {
    final offset = progress.clamp(0.0, 1.0) * travel;
    return ((offset - anchorIndexFor(progress) * panelHeight) / panelHeight)
        .clamp(0.0, 1.0);
  }

  /// Real files so the reader actually opens.
  ///
  /// [progress] is how far through the entry the reader left off — the input
  /// that decides which side of `CompletionPolicy.nearThreshold` a transition
  /// out of this entry falls on. The default sits well below it: an ordinary
  /// part-read entry.
  Future<void> seedEntry(
    int n, {
    required String readStatus,
    bool withFiles = true,
    String collectionId = 's1',
    double progress = 0.4,
  }) async {
    final id = entryId(collectionId, n);
    String? relative;
    if (withFiles) {
      final staging = await store.beginEntry(
        collectionId: collectionId,
        entryId: id,
      );
      final entries = <EntryAsset>[];
      for (var i = 1; i <= 3; i++) {
        await staging
            .assetFile('00$i.png')
            .writeAsBytes(panelPng(entry: n, index: i));
        entries.add(
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
      relative = await store.commit(
        staging,
        EntryManifest(
          schemaVersion: EntryManifest.currentSchemaVersion,
          entryId: id,
          collectionId: collectionId,
          sourceUrl: 'https://x.example/guide/$collectionId/$n',
          title: 'Entry $n',
          savedAt: DateTime(2026, 7, 20),
          status: SaveStatus.complete,
          detectedAssetCount: 3,
          storedAssetCount: 3,
          assets: entries,
        ),
      );
    }
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: id,
        collectionId: collectionId,
        title: 'Entry $n',
        sourceUrl: 'https://x.example/guide/$collectionId/$n',
        urlKey: 'https://x.example/guide/$collectionId/$n',
        artifactFormat: 'imageSequence',
        saveStatus: withFiles ? 'complete' : 'knownRemote',
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 3,
        storedAssetCount: withFiles ? 3 : 0,
        entryOrder: n,
        byteSize: withFiles ? 1500 : 0,
        entryNumber: n.toDouble(),
        sourceMarker: 'Entry $n',
        readStatus: readStatus,
        progressFraction: readStatus == 'completed' ? 1 : progress,
        progressPageIndex: anchorIndexFor(progress),
        progressOffsetInPage: anchorOffsetFor(progress),
        completedAt: readStatus == 'completed' ? DateTime(2026, 7, 22) : null,
      ),
    );
  }

  Future<CollectionCleanupPreference?> prefOf(String collectionId) async =>
      collectionCleanupFromName(
        (await db.collectionById(collectionId))!.cleanupPreference,
      );

  /// [undoWindow] defaults to a short one so the finalize timer cannot outlive
  /// the test; the Undo test needs a real window and passes its own.
  Widget harness(
    String entryId, {
    Duration undoWindow = const Duration(milliseconds: 50),
  }) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fileStoreProvider.overrideWithValue(store),
      cleanupProvider.overrideWithValue(
        cleanup = CleanupService(
          db: db,
          fileStore: store,
          undoWindow: undoWindow,
        ),
      ),
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
  Future<void> openReader(
    WidgetTester tester,
    String entryId, {
    Duration undoWindow = const Duration(milliseconds: 50),
  }) async {
    await tester.pumpWidget(harness(entryId, undoWindow: undoWindow));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(ListView).evaluate().isNotEmpty) return;
      if (find.textContaining('Not available offline').evaluate().isNotEmpty) {
        return;
      }
    }
    fail('reader never finished loading');
  }

  /// Tap "next entry" in the bottom chrome.
  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Next saved entry'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(AlertDialog).evaluate().isNotEmpty) return;
    }
  }

  /// Real file IO again: pump `runAsync` windows until [ready], without
  /// advancing the fake clock (which would spend the notice's own timeout).
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

  final noticeText = find.text('Removed downloads');
  final restoredText = find.text('Restored downloads');
  final cleanupDialog = find.text('Downloaded entries in this collection');
  final removeOption = find.byKey(const ValueKey('collectionCleanup-remove'));
  final keepOption = find.byKey(const ValueKey('collectionCleanup-keep'));
  final completionDialog = find.text('You have not finished this one');
  final markComplete = find.byKey(const ValueKey('entryCompletion-complete'));
  final continueWithout = find.byKey(
    const ValueKey('entryCompletion-continueWithout'),
  );
  final cancelCompletion = find.byKey(const ValueKey('entryCompletion-cancel'));

  /// Whether the reader actually opened [id]. `_load` marks an entry opened,
  /// and nothing else in these tests does — which makes this a fact about the
  /// destination rather than about a label that also appears on a control
  /// pointing at it.
  Future<bool> opened(String id) async =>
      (await db.entryById(id))?.firstOpenedAt != null;

  /// Let real IO and the widget tree settle without asserting anything.
  Future<void> pumpAWhile(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// Which option the dialog has selected right now.
  bool isSelected(Finder option) => find
      .descendant(of: option, matching: find.byIcon(Icons.radio_button_checked))
      .evaluate()
      .isNotEmpty;

  Future<void> saveChoice(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('saveCollectionCleanup')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  /// A collection already set to remove, one finished entry and one to move on
  /// to; returns with the removal notice on screen.
  Future<void> removeByMovingOn(WidgetTester tester) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => noticeText.evaluate().isNotEmpty,
      reason: 'the removal notice never appeared',
    );
  }

  Future<void> settleDown(WidgetTester tester) async {
    // The undo window is a timer inside the fake-async zone: advance the
    // fake clock past it, or the tree is disposed with it still pending.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  }

  // --- when the question is asked -------------------------------------------

  testWidgets(
    'an undecided collection is asked on the first forward transition',
    (tester) async {
      await tester.runAsync(() async {
        await seedCollection();
        await seedEntry(1, readStatus: 'completed');
        await seedEntry(2, readStatus: 'unread');
      });
      await openReader(tester, 'c1');
      await tapNext(tester);

      expect(cleanupDialog, findsOneWidget);
      expect(
        find.textContaining('after you continue to the next'),
        findsOneWidget,
      );
      expect(find.text('Remove after continuing'), findsOneWidget);
      expect(find.text('Keep downloaded files'), findsOneWidget);
      expect(find.text('Save choice'), findsOneWidget);
      expect(
        find.textContaining('applies only to this collection'),
        findsOneWidget,
        reason: 'the scope is stated where the decision is made',
      );
      await settleDown(tester);
    },
  );

  testWidgets('Remove after continuing is the preselected answer', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    expect(isSelected(removeOption), isTrue);
    expect(isSelected(keepOption), isFalse);
    await settleDown(tester);
  });

  testWidgets('moving backward never asks, and finishes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      // Right at the end, and the collection already removes: the two things
      // that would make a forward move act. Backward is still backward.
      await seedEntry(2, readStatus: 'inProgress', progress: 0.95);
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c2');
    await tester.tap(find.byTooltip('Previous saved entry'));
    await pumpAWhile(tester);

    expect(find.byType(AlertDialog), findsNothing);
    final left = (await db.entryById('c2'))!;
    expect(left.contentPath, isNotNull);
    expect(
      left.readStatus,
      'inProgress',
      reason:
          'going back is not continuing, so the entry left behind is not '
          'finished by it either',
    );
    expect(left.progressFraction, closeTo(0.95, 0.06));
    await settleDown(tester);
  });

  // --- an unfinished entry, near the end -----------------------------------
  //
  // Moving forward is not evidence of finishing. Close to the end it is worth
  // asking about; the answers are what these pin down.

  testWidgets('near the end, an unfinished entry is asked about', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    expect(completionDialog, findsOneWidget);
    expect(find.text('Mark complete and continue'), findsOneWidget);
    expect(find.text('Continue without completing'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.textContaining('does not finish it'),
      findsOneWidget,
      reason: 'the dialog must not imply that moving on requires finishing',
    );
    expect(
      cleanupDialog,
      findsNothing,
      reason: 'one question at a time — cleanup is only asked after completion',
    );
    await settleDown(tester);
  });

  for (final width in <double>[320, 414]) {
    testWidgets('the completion question fits a ${width}pt screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await seedCollection();
        await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
        await seedEntry(2, readStatus: 'unread');
        await db.setCollectionCleanupPreference(
          's1',
          CollectionCleanupPreference.remove.name,
        );
      });
      await openReader(tester, 'c1');
      await tapNext(tester);

      expect(tester.takeException(), isNull, reason: 'nothing overflowed');
      // All three answers reachable, and each one a real button rather than a
      // label — assistive navigation reaches them by exactly this.
      for (final answer in [markComplete, continueWithout, cancelCompletion]) {
        expect(answer, findsOneWidget);
        expect(
          tester.getSize(answer).height,
          greaterThanOrEqualTo(36),
          reason: 'a stacked answer keeps a real tap target',
        );
      }
      await settleDown(tester);
    });
  }

  testWidgets('Cancel stays put and changes nothing at all', (tester) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    await tester.tap(cancelCompletion);
    await pumpAWhile(tester);

    expect(await opened('c2'), isFalse, reason: 'the reader never moved');
    final left = (await db.entryById('c1'))!;
    expect(left.readStatus, 'inProgress');
    expect(left.contentPath, isNotNull);
    expect(left.progressFraction, closeTo(0.95, 0.06));
    expect(
      cleanup.openReaderEntryId.value,
      'c1',
      reason: 'the reader lock never left the entry it is still showing',
    );
    await settleDown(tester);
  });

  testWidgets('Continue without completing moves on and leaves it alone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
      // The collection's rule is *remove*, and it must not reach an entry the
      // reader has just said is unfinished.
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    final anchorBefore = (await db.entryById('c1'))!.progressPageIndex;
    await tapNext(tester);
    await tester.tap(continueWithout);
    await pumpUntil(
      tester,
      () => opened('c2'),
      reason: 'the next entry never opened',
    );

    final left = (await db.entryById('c1'))!;
    expect(left.readStatus, 'inProgress');
    expect(left.contentPath, isNotNull, reason: 'the files are still there');
    expect(left.progressFraction, closeTo(0.95, 0.06));
    expect(
      left.progressPageIndex,
      anchorBefore,
      reason: 'the anchor it would resume at is untouched',
    );
    // And that anchor is exactly what a reopen restores from: `positionOf` is
    // the reader's own entry point into these columns.
    final resume = ReadingRepository(db).positionOf(left);
    expect(resume.fraction, closeTo(0.95, 0.06));
    expect(resume.anchorIndex, anchorBefore);
    expect(cleanupDialog, findsNothing);
    await settleDown(tester);
  });

  testWidgets('Mark complete and continue, with remove already chosen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    expect(
      find.textContaining('also removes its files'),
      findsOneWidget,
      reason: 'the deletion is named before the tap, not in a notice after it',
    );

    await tester.tap(markComplete);
    await pumpUntil(
      tester,
      () async => (await db.entryById('c1'))?.contentPath == null,
      reason: 'the entry was never removed',
    );

    expect(await opened('c2'), isTrue);
    final left = (await db.entryById('c1'))!;
    expect(left.readStatus, 'completed');
    expect(left.progressFraction, 1);
    expect(left.offlineRemovedAt, isNotNull);
    expect(left.sourceUrl, isNotEmpty, reason: 'the row survives intact');
    expect(cleanupDialog, findsNothing, reason: 'already decided');
    expect(
      cleanup.openReaderEntryId.value,
      'c2',
      reason: 'the lock followed the reader to the entry it is now on',
    );
    await settleDown(tester);
  });

  testWidgets('Mark complete and continue, with keep already chosen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.keep.name,
      );
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    expect(
      find.textContaining('also removes its files'),
      findsNothing,
      reason: 'nothing is going to be removed, so nothing warns about it',
    );

    await tester.tap(markComplete);
    await pumpUntil(
      tester,
      () async => (await db.entryById('c1'))?.readStatus == 'completed',
      reason: 'the entry was never completed',
    );

    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    expect(cleanupDialog, findsNothing);
    await settleDown(tester);
  });

  testWidgets('Mark complete and continue, with no decision yet, asks next', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    await tester.tap(markComplete);
    await pumpUntil(
      tester,
      () async => cleanupDialog.evaluate().isNotEmpty,
      reason: 'the cleanup question never followed the completion answer',
    );

    // Two dialogs, in one order, each asking one thing: is this finished, and
    // then what does this collection do with finished entries.
    expect(completionDialog, findsNothing, reason: 'the first one is done');
    await tester.tap(removeOption);
    await saveChoice(tester);
    await pumpUntil(
      tester,
      () async => (await db.entryById('c1'))?.contentPath == null,
      reason: 'the answer was never applied',
    );

    expect(await prefOf('s1'), CollectionCleanupPreference.remove);
    expect((await db.entryById('c1'))!.readStatus, 'completed');
    await settleDown(tester);
  });

  // --- an unfinished entry, not near the end -------------------------------

  testWidgets(
    'well short of the end, moving on asks nothing and does nothing',
    (tester) async {
      await tester.runAsync(() async {
        await seedCollection();
        await seedEntry(1, readStatus: 'inProgress', progress: 0.3);
        await seedEntry(2, readStatus: 'unread');
        // Remembered *remove*, which must not reach an unfinished entry.
        await db.setCollectionCleanupPreference(
          's1',
          CollectionCleanupPreference.remove.name,
        );
      });
      await openReader(tester, 'c1');
      final anchorBefore = (await db.entryById('c1'))!.progressPageIndex;
      await tester.tap(find.byTooltip('Next saved entry'));
      await pumpUntil(
        tester,
        () => opened('c2'),
        reason: 'the next entry never opened',
      );

      expect(find.byType(AlertDialog), findsNothing, reason: 'no modal at all');
      final left = (await db.entryById('c1'))!;
      expect(left.readStatus, 'inProgress');
      expect(left.contentPath, isNotNull);
      expect(left.progressFraction, closeTo(0.3, 0.06));
      expect(left.progressPageIndex, anchorBefore);
      await settleDown(tester);
    },
  );

  testWidgets('the reported case: no decision, unfinished, bottom-bar Next', (
    tester,
  ) async {
    // The regression this whole flow was reopened for, in both of its halves.
    // Below the near-completion threshold nothing is asked and nothing is
    // touched; above it the question appears — and it is the *bottom bar's*
    // control being tapped in each case, which is what used to be unable to
    // reach any of this.
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.5);
      await seedEntry(2, readStatus: 'inProgress', progress: 0.93);
      await seedEntry(3, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () => opened('c2'),
      reason: 'the next entry never opened',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect((await db.entryById('c1'))!.readStatus, 'inProgress');
    expect(await prefOf('s1'), isNull);

    await tapNext(tester);
    expect(completionDialog, findsOneWidget);
    await settleDown(tester);
  });

  // --- a destination that does not open ------------------------------------

  testWidgets('a destination whose row lost its files changes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'inProgress', progress: 0.95);
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    // Cleared without bumping the removal counter, so the control stays lit —
    // which is exactly the stale-control race `_goTo` re-reads the row for.
    await tester.runAsync(
      () => db.writeEntryReading(
        'c2',
        const EntriesCompanion(contentPath: Value(null)),
      ),
    );

    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpAWhile(tester);

    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'nothing is asked about a move that cannot happen',
    );
    final left = (await db.entryById('c1'))!;
    expect(left.readStatus, 'inProgress');
    expect(left.contentPath, isNotNull);
    expect(left.progressFraction, closeTo(0.95, 0.06));
    expect(await prefOf('s1'), isNull);
    expect(await opened('c2'), isFalse);
    expect(
      cleanup.openReaderEntryId.value,
      'c1',
      reason: 'the lock stays on the entry that is still open',
    );
    await settleDown(tester);
  });

  testWidgets('a destination that fails while loading changes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    // The row still says the package is there — it is the disk that has moved
    // on. This is the case `readerCanOpen` cannot see, and the reason the
    // removal waits for the load rather than for the row check.
    await tester.runAsync(() async {
      final target = (await db.entryById('c2'))!;
      Directory(store.resolve(target.contentPath!)).deleteSync(recursive: true);
    });

    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpAWhile(tester);

    expect(
      find.text('The files for this entry are gone'),
      findsOneWidget,
      reason: 'the destination landed on the unavailable screen',
    );
    final left = (await db.entryById('c1'))!;
    expect(
      left.contentPath,
      isNotNull,
      reason:
          'the entry just left is the only readable thing left — removing it '
          'would strand the reader',
    );
    expect(left.offlineRemovedAt, isNull);
    expect(noticeText, findsNothing);
    await settleDown(tester);
  });

  testWidgets('a burst of taps completes and removes exactly once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await seedEntry(3, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');

    // Three taps inside one frame, so the control is still mounted for each:
    // the second and third arrive while the first transition is mid-flight.
    final next = find.byTooltip('Next saved entry');
    await tester.tap(next);
    await tester.tap(next, warnIfMissed: false);
    await tester.tap(next, warnIfMissed: false);
    await pumpUntil(
      tester,
      () async => (await db.entryById('c1'))?.contentPath == null,
      reason: 'the entry left behind was never removed',
    );
    await pumpAWhile(tester);

    expect(
      cleanup.removals.value,
      1,
      reason: 'one transition, one removal, however many taps produced it',
    );
    expect(
      (await db.entryById('c2'))!.contentPath,
      isNotNull,
      reason: 'the entry the reader landed on is never the one removed',
    );
    await settleDown(tester);
  });

  // --- what an answer does --------------------------------------------------

  testWidgets('saving Remove stores it on this collection and applies it now', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedCollection(id: 's2', title: 'Bar');
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    await saveChoice(tester);
    // The answer is stored at once; the removal waits for the destination to
    // actually open.
    await pumpUntil(
      tester,
      () async => (await db.entryById('c1'))?.contentPath == null,
      reason: 'the entry left behind was never removed',
    );

    expect(await prefOf('s1'), CollectionCleanupPreference.remove);
    expect(
      await prefOf('s2'),
      isNull,
      reason: 'a decision reaches exactly one collection',
    );

    final removed = (await db.entryById('c1'))!;
    expect(removed.contentPath, isNull);
    expect(removed.readStatus, 'completed', reason: 'history kept');
    expect(removed.completedAt, isNotNull);
    expect(removed.sourceUrl, isNotEmpty, reason: 'metadata kept');
    expect(await db.collectionById('s1'), isNotNull);
    expect(
      (await db.entryById('c2'))!.contentPath,
      isNotNull,
      reason: 'the newly opened entry is never the one removed',
    );
    await settleDown(tester);
  });

  testWidgets('saving Keep stores it on this collection and removes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedCollection(id: 's2', title: 'Bar');
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    await tester.tap(keepOption);
    await tester.pump();
    expect(isSelected(keepOption), isTrue);
    expect(isSelected(removeOption), isFalse);
    await saveChoice(tester);

    expect(await prefOf('s1'), CollectionCleanupPreference.keep);
    expect(await prefOf('s2'), isNull);
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    expect(
      Directory(
        store.resolve((await db.entryById('c1'))!.contentPath!),
      ).existsSync(),
      isTrue,
    );
    await settleDown(tester);
  });

  testWidgets('dismissing without saving stores nothing and keeps the files', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    // The scrim: dismissal, not an answer.
    await tester.tapAt(const Offset(20, 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();

    expect(cleanupDialog, findsNothing);
    expect(await prefOf('s1'), isNull);
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    await settleDown(tester);
  });

  testWidgets('one dialog per transition, never a stacked second one', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'completed');
      await seedEntry(3, readStatus: 'unread');
    });
    await openReader(tester, 'c1');

    // Two forward taps in quick succession: the second lands while the first
    // transition is still resolving its question. Both entries are finished,
    // so without the guard each would raise its own dialog.
    final next = find.byTooltip('Next saved entry');
    await tester.tap(next);
    await tester.pump();
    if (next.evaluate().isNotEmpty) {
      await tester.tap(next, warnIfMissed: false);
    }
    await pumpUntil(
      tester,
      () async => find.byType(AlertDialog).evaluate().isNotEmpty,
      reason: 'the cleanup question never appeared',
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    await saveChoice(tester);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'answering once answers it — no queued duplicate behind it',
    );
    expect(await prefOf('s1'), CollectionCleanupPreference.remove);
    await settleDown(tester);
  });

  // --- a decided collection -----------------------------------------------------

  testWidgets('a collection set to remove is never asked again', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');
    await tapNext(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    final removed = (await db.entryById('c1'))!;
    expect(removed.contentPath, isNull);
    expect(removed.completedAt, isNotNull, reason: 'history kept');
    await settleDown(tester);
  });

  testWidgets('a collection set to keep is never asked and keeps its files', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.keep.name,
      );
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    await settleDown(tester);
  });

  testWidgets('another collection is still asked, and keeps its own answer', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedCollection(id: 's2', title: 'Bar');
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await seedEntry(1, readStatus: 'completed', collectionId: 's2');
      await seedEntry(2, readStatus: 'unread', collectionId: 's2');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });

    await openReader(tester, 's2c1');
    await tapNext(tester);
    expect(
      cleanupDialog,
      findsOneWidget,
      reason: "another collection's decision is not this one's",
    );
    expect(isSelected(removeOption), isTrue);

    await tester.tap(keepOption);
    await tester.pump();
    await saveChoice(tester);

    expect(await prefOf('s2'), CollectionCleanupPreference.keep);
    expect(
      await prefOf('s1'),
      CollectionCleanupPreference.remove,
      reason: 'deciding one collection leaves the other exactly as it was',
    );
    expect((await db.entryById('s2c1'))!.contentPath, isNotNull);
    await settleDown(tester);
  });

  testWidgets('a reset collection asks again, preselecting Remove', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      // Decided as keep, then reset from the collection settings.
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.keep.name,
      );
      await db.setCollectionCleanupPreference('s1', null);
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    expect(cleanupDialog, findsOneWidget);
    expect(
      isSelected(removeOption),
      isTrue,
      reason: 'the preselection is fixed, never the previous answer',
    );
    await settleDown(tester);
  });

  testWidgets('a stale global storage.afterFinished value changes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      // The obsolete key, written by an old build that auto-removed.
      await db.setSetting('storage.afterFinished', 'remove');
    });
    await openReader(tester, 'c1');
    await tapNext(tester);

    expect(
      cleanupDialog,
      findsOneWidget,
      reason: 'the collection has not been asked; a stale row is not an answer',
    );
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    await settleDown(tester);
  });

  // --- the removal notice ---------------------------------------------------
  //
  // It is a moment on the reader, not a message in a queue: it says one thing,
  // it offers the undo it can honour, and it ends — on its own, on a tap, on a
  // entry change, or on leaving the app. Nothing about it is persisted, so
  // there is nothing for a later screen or a later launch to restore.

  testWidgets('says what happened, offers Undo, and never quotes bytes', (
    tester,
  ) async {
    await removeByMovingOn(tester);

    expect(noticeText, findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      find.textContaining('freed'),
      findsNothing,
      reason: 'how much space came back is not a mid-read decision',
    );
    expect(find.textContaining('KB'), findsNothing);
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'not on the app-wide messenger, which outlives this screen',
    );
    await settleDown(tester);
  });

  testWidgets('times out on its own and does not come back', (tester) async {
    await removeByMovingOn(tester);

    await tester.pump(kReaderNoticeDuration + const Duration(seconds: 1));
    await tester.pump();
    expect(noticeText, findsNothing);

    // Rebuild the screen and let far more than a timeout pass: a dismissed
    // notice has no state left to redisplay.
    await tester.pump(const Duration(seconds: 30));
    expect(noticeText, findsNothing);
    await settleDown(tester);
  });

  testWidgets('closing it ends it for good', (tester) async {
    await removeByMovingOn(tester);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(noticeText, findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(noticeText, findsNothing);
    await settleDown(tester);
  });

  testWidgets('leaving the app ends it, and returning does not restore it', (
    tester,
  ) async {
    await removeByMovingOn(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(noticeText, findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      noticeText,
      findsNothing,
      reason: 'a resume must not replay what the user already saw',
    );
    await settleDown(tester);
  });

  testWidgets('moving on again clears it instead of stacking a second one', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'completed');
      await seedEntry(3, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1');

    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => noticeText.evaluate().isNotEmpty,
      reason: 'the first removal notice never appeared',
    );

    await pumpUntil(
      tester,
      () async => find.byTooltip('Next saved entry').evaluate().isNotEmpty,
      reason: 'the next entry never finished loading',
    );
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => (await db.entryById('c2'))?.contentPath == null,
      reason: 'the second entry was never removed',
    );

    expect(
      noticeText,
      findsOneWidget,
      reason: 'one notice at a time, replaced rather than queued',
    );
    await settleDown(tester);
  });

  testWidgets('an entry change with nothing removed clears the notice', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'completed');
      await seedEntry(3, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c2');
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => noticeText.evaluate().isNotEmpty,
      reason: 'the removal notice never appeared',
    );

    // Now go back. Backward movement removes nothing — and the notice about
    // c2 has no business surviving onto c1.
    await pumpUntil(
      tester,
      () async => find.byTooltip('Previous saved entry').evaluate().isNotEmpty,
      reason: 'the next entry never finished loading',
    );
    await tester.tap(find.byTooltip('Previous saved entry'));
    await tester.pump();
    expect(noticeText, findsNothing);
    await settleDown(tester);
  });

  testWidgets('Undo puts the files back and says so', (tester) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    // Undo() cancels the finalize timer, so a real window leaves nothing
    // pending at teardown.
    await openReader(tester, 'c1', undoWindow: const Duration(seconds: 10));
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => noticeText.evaluate().isNotEmpty,
      reason: 'the removal notice never appeared',
    );

    await tester.tap(find.text('Undo'));
    await pumpUntil(
      tester,
      () async => restoredText.evaluate().isNotEmpty,
      reason: 'the restore confirmation never appeared',
    );

    final restored = (await db.entryById('c1'))!;
    expect(restored.contentPath, isNotNull);
    expect(restored.byteSize, 1500);
    expect(store.entryExists(restored.contentPath!), isTrue);
    expect(noticeText, findsNothing, reason: 'replaced, not stacked');
    expect(find.text('Undo'), findsNothing);
    await settleDown(tester);
  });

  testWidgets('Undo is still live in the notice\'s last moments', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      await seedEntry(2, readStatus: 'unread');
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
    });
    await openReader(tester, 'c1', undoWindow: const Duration(seconds: 10));
    await tester.tap(find.byTooltip('Next saved entry'));
    await pumpUntil(
      tester,
      () async => noticeText.evaluate().isNotEmpty,
      reason: 'the removal notice never appeared',
    );

    // A frame short of the timeout — the notice is fading out but has not
    // dismissed, so what it still offers must still work. A shorter notice than
    // the undo window is fine; a notice that outlives what it can honour is not.
    await tester.pump(kReaderNoticeDuration - const Duration(milliseconds: 16));
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await pumpUntil(
      tester,
      () async => restoredText.evaluate().isNotEmpty,
      reason: 'a notice fading out still took the Undo, but never confirmed it',
    );
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    await settleDown(tester);
  });

  test('the notice never outlasts the undo it offers', () {
    expect(
      kReaderNoticeDuration,
      lessThanOrEqualTo(CleanupService(db: db, fileStore: store).undoWindow),
      reason: 'past that window Undo is a dead button',
    );
  });

  testWidgets('a removed entry reads as not-downloaded, not an error', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedCollection();
      await seedEntry(1, readStatus: 'completed');
      final cleanup = CleanupService(db: db, fileStore: store);
      await cleanup.removeOffline(['c1']);
    });
    await openReader(tester, 'c1');

    expect(find.text('Not available offline'), findsOneWidget);
    expect(
      find.textContaining('files for this entry are gone'),
      findsNothing,
      reason: 'the user did this on purpose; do not alarm them',
    );
    expect(find.textContaining('save it again'), findsOneWidget);
    await settleDown(tester);
  });
}
