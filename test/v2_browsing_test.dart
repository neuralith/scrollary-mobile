/// Reading the web is how the library stays current (roadmap F6, V2-D13).
///
/// The rule the composition applies to every completed navigation, and the two
/// halves of it that are easy to collapse into one:
///
/// * A page the library already holds, on a Collection the user **follows**,
///   records that it was opened. Never that it was finished — a website has no
///   position to measure, so no progress figure is invented (I16, V2-D9).
/// * Everything else is device-local history (I11). *Everything else* includes
///   a page on a Source the library knows but has stopped following: following
///   is the authorising act, and reading an unfollowed Collection must not
///   quietly expand the synced library.
///
/// And the invariant underneath both: **browsing alone creates no library
/// row.** Promotion out of history is a tap the user makes.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/browser/favicon_service.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/features/settings_screen.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/v2_harness.dart';

void main() {
  late BrowserController browser;
  late FileStore store;
  late V2Harness v2;

  const entryUrl = 'https://reading.example.com/quiet-harbour/3';
  const strangerUrl = 'https://elsewhere.example.com/notes/1';

  setUp(() {
    browser = BrowserController();
    store = tempFileStore();
    v2 = V2Harness(browser: browser, fileStore: store);
  });

  tearDown(() async {
    await v2.close();
    browser.dispose();
    if (store.rootDir.existsSync()) store.rootDir.deleteSync(recursive: true);
  });

  /// One Collection with one Source, one Entry, and the address it is read at.
  Future<({CollectionRow collection, EntryRow entry})> seedLibrary() async {
    final root = await v2.ui.folders.ensureRoot();
    final (collection, _) = await v2.ui.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (source, _) = await v2.ui.collections.addSource(
      collectionId: collection!.id,
      host: 'reading.example.com',
      pathKey: 'quiet-harbour',
      language: 'en',
    );
    final (entry, _) = await v2.ui.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 3,
      placement: Placement.placed,
      title: 'Quiet Harbour 3',
    );
    await v2.ui.entries.addLocation(
      entryId: entry!.id,
      sourceId: source!.id,
      url: entryUrl,
      urlKey: normalizeUrl(entryUrl),
    );
    return (collection: collection, entry: entry);
  }

  Future<void> browseTo(
    String url, {
    String title = 'A page',
    bool userInitiated = true,
  }) => recordCompletedVisit(
    v2.services,
    url: url,
    title: title,
    userInitiated: userInitiated,
  );

  Future<List<HistoryRow>> historyRows() => v2.history.recent();

  Future<ReadingStateRow?> readingOf(String entryId) => (v2.library.select(
    v2.library.readingStates,
  )..where((r) => r.entryId.equals(entryId))).getSingleOrNull();

  Future<({int collections, int entries, int locations})> counts() async {
    return (
      collections:
          (await v2.library.select(v2.library.collections).get()).length,
      entries: (await v2.library.select(v2.library.entries).get()).length,
      locations: (await v2.library.select(v2.library.locations).get()).length,
    );
  }

  test('a page of a followed collection records that it was opened', () async {
    final s = await seedLibrary();
    final before = await counts();

    await browseTo(entryUrl, title: 'Quiet Harbour 3');

    final reading = await readingOf(s.entry.id);
    expect(reading, isNotNull, reason: 'access was recorded');
    expect(reading!.status, 'reading');
    expect(reading.lastReadAt, isNotNull);
    expect(
      reading.completedAt,
      isNull,
      reason:
          'a website has no position to measure, so nothing is guessed about '
          'how far the reader got — and access is never completion (I16)',
    );
    expect(
      await historyRows(),
      isEmpty,
      reason: 'the library already holds this; history is everything else',
    );
    expect(await counts(), before, reason: 'browsing creates no library row');
  });

  test(
    'a page of a collection the user stopped following is history',
    () async {
      final s = await seedLibrary();
      await v2.ui.collections.archive(s.collection.id);
      final before = await counts();

      await browseTo(entryUrl, title: 'Quiet Harbour 3');

      expect(
        await readingOf(s.entry.id),
        isNull,
        reason:
            'following is the authorising act — unfollowed reading never keeps '
            'the synced library current',
      );
      final rows = await historyRows();
      expect(rows, hasLength(1));
      expect(rows.single.url, entryUrl);
      expect(await counts(), before);
    },
  );

  test(
    'a page the library has never seen is history and nothing else',
    () async {
      await seedLibrary();
      final before = await counts();

      await browseTo(strangerUrl, title: 'Somebody else');

      final rows = await historyRows();
      expect(rows, hasLength(1));
      expect(rows.single.url, strangerUrl);
      expect(rows.single.title, 'Somebody else');
      expect(
        await counts(),
        before,
        reason: 'nothing is created from a page the user merely looked at',
      );
    },
  );

  test('a standalone entry is in the library by construction', () async {
    final root = await v2.ui.folders.ensureRoot();
    final (entry, _) = await v2.ui.entries.createStandalone(
      folderId: root.id,
      title: 'A stray page',
    );
    await v2.ui.entries.addLocation(
      entryId: entry!.id,
      url: strangerUrl,
      urlKey: normalizeUrl(strangerUrl),
    );

    await browseTo(strangerUrl, title: 'A stray page');

    expect(await readingOf(entry.id), isNotNull);
    expect(await historyRows(), isEmpty);
  });

  test('automation is never recorded anywhere', () async {
    final s = await seedLibrary();

    await browseTo(entryUrl, userInitiated: false);
    await browseTo(strangerUrl, userInitiated: false);

    expect(
      await readingOf(s.entry.id),
      isNull,
      reason: 'a save run reading a page is not the user reading it',
    );
    expect(await historyRows(), isEmpty);
  });

  test('the same page again inside the window is one visit', () async {
    await browseTo(strangerUrl, title: 'Somebody else');
    await browseTo(strangerUrl, title: 'Somebody else');
    await browseTo(strangerUrl, title: 'Somebody else');

    expect(
      await historyRows(),
      hasLength(1),
      reason: 'a reload loop must not stack twelve identical entries',
    );
  });

  group('Settings', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('scrollary_v2_browsing');
    });

    tearDown(() async {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    testWidgets('the browsing-history row counts the V2 rows', (tester) async {
      tester.view.physicalSize = const Size(430, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await browseTo(strangerUrl, title: 'Somebody else');
      await browseTo('https://another.example.com/page', title: 'Another page');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileStoreProvider.overrideWithValue(FileStore(root)),
            browserProvider.overrideWithValue(browser),
            v2ServicesProvider.overrideWithValue(v2.services),
            libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
            faviconServiceProvider.overrideWithValue(
              FaviconService(db: v2.library, allowNetwork: false),
            ),
          ],
          child: MaterialApp(theme: appTheme(), home: const SettingsScreen()),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(find.byKey(const ValueKey('settingsBrowsingHistory')), findsOne);
      expect(
        find.text('2 pages · 2 sites'),
        findsOneWidget,
        reason: 'Settings reads the V2 history table, not V1\'s',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('the source-reading meter', () {
    // `recordCompletedVisit` is where the app finds out what page is on
    // screen, so it is where the meter is told what it is looking at.
    // Nothing is measured here — a navigation is not a reading — but a page
    // the library does not hold must not leave the previous target armed, or
    // the next measurement lands on the wrong Entry.
    test('a recognised entry becomes what the meter is watching', () async {
      final s = await seedLibrary();
      await browseTo(entryUrl, title: 'Quiet Harbour 3');

      expect(v2.services.sourceReading.isWatching, isTrue);

      // And it measures against that Entry when the page has a position.
      final fraction = await v2.services.sourceReading.record(
        PageProbe(
          url: entryUrl,
          title: '',
          documentHeight: 4000,
          viewportHeight: 1000,
          scrollY: 1000,
        ),
      );
      expect(fraction, 0.5);
      final measured = await v2.library.select(v2.library.measurements).get();
      expect(measured, hasLength(1));
      expect(measured.single.entryId, s.entry.id);
    });

    test('moving on to a page the library does not hold disarms it', () async {
      await seedLibrary();
      await browseTo(entryUrl, title: 'Quiet Harbour 3');
      expect(v2.services.sourceReading.isWatching, isTrue);

      await browseTo(strangerUrl, title: 'Somewhere else');

      expect(
        v2.services.sourceReading.isWatching,
        isFalse,
        reason: 'history has no Entry to be a fraction of',
      );
      expect(
        await v2.library.select(v2.library.measurements).get(),
        isEmpty,
      );
    });
  });
}
