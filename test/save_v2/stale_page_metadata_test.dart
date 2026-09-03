/// What a save writes about a page is the page's own, never the last one's.
///
/// **The leak this pins.** `BrowserController` read the document title once,
/// at `onLoadStop`, and nothing ever took it back. Every other thing the
/// Browser says *about a page* is scoped to `pageSession` (D59) — the title
/// was not, so between committing to a new document and that document's load
/// finishing, `browser.title` was still the previous page's name while
/// `currentUrl` was already the new page's.
///
/// That pair is exactly what the save sheet is opened with
/// (`BrowserScreen._showSaveSheet` → `V2SavePanel(url:, pageTitle:)`), and
/// `pageTitle` is not decoration: it becomes the new Collection's suggested
/// name and its `detected_title`, the new Entry's stored title, and — through
/// `parseEntryNumber`, which reads a title before it reads an address — the
/// **ordinal the Entry is placed at**. So a save started a moment too early
/// filed the new page under the previous page's name, at the previous page's
/// number, and the download then named that Entry on screen.
///
/// Two halves, in the order they fail: the Browser's own rule, then what the
/// library ends up holding when a save follows a save.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/storage/file_store.dart';

import '../recognition/support/recognition_harness.dart';

/// The real [BrowserController], with the one thing a host test cannot
/// have — a WebView to ask what the document calls itself — scripted.
///
/// Deliberately not a hand-written stand-in: the rule under test *is* the
/// controller's load lifecycle, so the test drives the production one and
/// only supplies what the platform would have answered.
class ScriptedTitleBrowser extends BrowserController {
  ScriptedTitleBrowser(this.titles);

  /// What each address's document prints as its title. An address that is
  /// absent is a document that did not say — which is what a WebView answers
  /// mid-teardown, and what a page that has not finished arriving answers.
  final Map<String, String> titles;

  @override
  Future<String?> readPageTitle() async => titles[currentUrl];
}

/// A whole navigation: the main frame commits, then the load finishes.
Future<void> visit(BrowserController browser, String url) async {
  browser.onLoadStart(url);
  await browser.onLoadStop(url);
}

void main() {
  // Page A: the work the user was already reading, numbered in its title.
  const pageA = 'https://$kHostA$kWorkPath/part-5';
  const titleA = 'Quiet Harbour — Part 5';

  // Page B: another work on another site, numbered 12 by its own address and
  // named nothing like A. Nothing about it may come out looking like A.
  const pageB = 'https://$kHostB$kWorkPath/part-12';
  const titleB = 'Still Water — Part 12';

  group('the Browser\'s title belongs to the page it was read from', () {
    late ScriptedTitleBrowser browser;

    setUp(() => browser = ScriptedTitleBrowser({pageA: titleA, pageB: titleB}));
    tearDown(() => browser.dispose());

    test('a finished load takes the document\'s own title', () async {
      await visit(browser, pageA);
      expect(browser.title, titleA);
    });

    test('committing to another page drops the previous page\'s '
        'title', () async {
      await visit(browser, pageA);
      expect(browser.title, titleA);

      // The main frame is on B; B has not finished loading. This is the whole
      // window the bug lived in, and the save control is drawn throughout it.
      browser.onLoadStart(pageB);
      expect(browser.currentUrl, pageB);
      expect(
        browser.title,
        isEmpty,
        reason: 'the address is B\'s, so the name beside it may not be A\'s',
      );

      await browser.onLoadStop(pageB);
      expect(browser.title, titleB);
    });

    test('a page whose title cannot be read is left unnamed, never '
        'borrowing the last one\'s', () async {
      await visit(browser, pageA);
      // A document that answers nothing: a WebView mid-teardown, a page that
      // prints no <title>. Unnamed is honest; named after A is not.
      await visit(browser, 'https://$kHostShifted$kWorkPath/part-9');
      expect(browser.title, isEmpty);
    });

    test('a reload of the same page keeps its title', () async {
      await visit(browser, pageA);
      browser.onLoadStart(pageA);
      expect(
        browser.title,
        titleA,
        reason: 'the same document is arriving again, not a different one',
      );
    });

    test('a redirect is named by the document that landed', () async {
      browser.onLoadStart(pageA);
      await browser.onLoadStop(pageB);
      expect(browser.title, titleB);
    });

    test('a same-document jump keeps the title', () async {
      await visit(browser, pageA);
      browser.onUrlChanged('$pageA#notes');
      expect(browser.title, titleA);
    });

    test('the visit recorded for a page carries that page\'s name', () async {
      final visits = <BrowserVisit>[];
      browser.onVisitCompleted = visits.add;
      await visit(browser, pageA);
      // A page that prints no title of its own: history must not file it
      // under the previous page's name either.
      await visit(browser, 'https://$kHostShifted$kWorkPath/part-9');
      expect(visits.map((v) => v.title), [titleA, '']);
    });
  });

  group('what a save persists is the page it was started on', () {
    late LibraryDatabase db;
    late Directory storeRoot;

    setUp(() {
      db = LibraryDatabase.forTesting(NativeDatabase.memory());
      storeRoot = Directory.systemTemp.createTempSync('scrollary_stale_meta');
    });
    tearDown(() async {
      await db.close();
      if (storeRoot.existsSync()) storeRoot.deleteSync(recursive: true);
    });

    /// A `WidgetRef` over the library, built inside the test body — the
    /// repositories hold `Future` chains, and one created outside the fake
    /// async zone never completes.
    Future<WidgetRef> refOver(WidgetTester tester) async {
      final services = LibraryUiServices(db, fileStore: FileStore(storeRoot));
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryUiServicesProvider.overrideWithValue(services)],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return captured;
    }

    SaveLimits one() => SaveLimits.forScope(SaveScope.currentPageOnly);

    /// What the running download panel would put on screen for the row it is
    /// capturing: the queue's newest row, and the Entry it names.
    Future<({String title, String? collectionId})> nowDownloading() async {
      final tasks = await db.select(db.saveQueue).get();
      expect(tasks, isNotEmpty);
      tasks.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
      final entry = await (db.select(
        db.entries,
      )..where((e) => e.id.equals(tasks.last.entryId))).getSingle();
      return (title: entry.title, collectionId: entry.collectionId);
    }

    testWidgets('a new Collection started while the next page is still '
        'loading is not the last one', (tester) async {
      final ref = await refOver(tester);
      final browser = ScriptedTitleBrowser({pageA: titleA, pageB: titleB});
      addTearDown(browser.dispose);

      // 1. The work the user was reading: saved, and its download queued.
      await visit(browser, pageA);
      final first = await v2AddAndDownload(
        ref,
        url: browser.currentUrl,
        pageTitle: browser.title,
        newCollectionName: 'Quiet Harbour',
        limits: one(),
      );
      expect(first.succeeded, isTrue);
      expect(first.queued, 1);

      // 2. On to another work, and the save control is tapped before the page
      //    has finished arriving. This is the reported flow.
      browser.onLoadStart(pageB);
      final second = await v2AddAndDownload(
        ref,
        url: browser.currentUrl,
        pageTitle: browser.title,
        newCollectionName: 'Still Water',
        limits: one(),
      );
      expect(second.succeeded, isTrue);
      expect(second.queued, 1);
      expect(second.collectionId, isNot(first.collectionId));
      expect(second.entryId, isNot(first.entryId));

      final entries = await db.select(db.entries).get();
      expect(entries, hasLength(2));
      final newEntry = entries.singleWhere((e) => e.id == second.entryId);
      expect(
        newEntry.title,
        isNot(titleA),
        reason: 'the new Entry is not the previous page under a new id',
      );
      expect(
        newEntry.ordinal,
        isNot(5),
        reason: 'a number printed by the previous page never places this one',
      );

      final newCollection = await (db.select(
        db.collections,
      )..where((c) => c.id.equals(second.collectionId!))).getSingle();
      expect(newCollection.name, 'Still Water');
      expect(
        newCollection.detectedTitle,
        isNot(contains('Quiet Harbour')),
        reason: 'the detected title is evidence about this page, not the last',
      );

      // And what the download panel would name while it captures that row.
      final showing = await nowDownloading();
      expect(showing.collectionId, second.collectionId);
      expect(showing.title, isNot(titleA));
    });

    testWidgets('consecutive saves each file their own page', (tester) async {
      final ref = await refOver(tester);
      final browser = ScriptedTitleBrowser({pageA: titleA, pageB: titleB});
      addTearDown(browser.dispose);

      await visit(browser, pageA);
      final first = await v2AddAndDownload(
        ref,
        url: browser.currentUrl,
        pageTitle: browser.title,
        newCollectionName: 'Quiet Harbour',
        limits: one(),
      );
      final firstShowing = await nowDownloading();
      expect(firstShowing.title, titleA);
      expect(firstShowing.collectionId, first.collectionId);

      // The second page, this time fully loaded before the user saves.
      await visit(browser, pageB);
      final second = await v2AddAndDownload(
        ref,
        url: browser.currentUrl,
        pageTitle: browser.title,
        newCollectionName: 'Still Water',
        limits: one(),
      );

      final entryA = await (db.select(
        db.entries,
      )..where((e) => e.id.equals(first.entryId!))).getSingle();
      final entryB = await (db.select(
        db.entries,
      )..where((e) => e.id.equals(second.entryId!))).getSingle();

      expect(entryA.title, titleA);
      expect(entryA.ordinal, 5);
      expect(entryB.title, titleB);
      expect(entryB.ordinal, 12);
      expect(entryB.collectionId, second.collectionId);

      // Two rows, one per Entry, each naming its own — the download UI reads
      // the row's Entry, so this is what it can put on screen.
      final tasks = await db.select(db.saveQueue).get();
      expect(tasks, hasLength(2));
      expect(tasks.map((t) => t.entryId).toSet(), {
        first.entryId,
        second.entryId,
      });
      final secondShowing = await nowDownloading();
      expect(secondShowing.title, titleB);
      expect(secondShowing.collectionId, second.collectionId);
    });
  });
}
