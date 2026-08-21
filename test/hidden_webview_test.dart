import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/manifest.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/scripted_browser.dart';

/// The unrendered-WebView class of bug (audit, 2026-07-27): an offstage
/// WKWebView answers probes with real DOM data but a zero viewport and a
/// frozen scroll position. On a long eagerly-rendered page that combination made
/// extraction accept comment avatars as entry panels. None of that may
/// ever reach disk.
void main() {
  late AppDatabase db;
  late Directory root;

  const config = SaveConfig(
    scrollDelay: Duration(milliseconds: 5),
    fastScrollDelay: Duration(milliseconds: 1),
    quietPeriod: Duration.zero,
    requiredStableChecks: 1,
    maxScrollPasses: 1,
    maxAssetWait: Duration(milliseconds: 300),
    domReadyTimeout: Duration(seconds: 2),
    downloadRetries: 0,
    cooldownBetweenEntries: Duration.zero,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_hidden');
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  SaveEngine engine(ScriptedBrowser browser) => SaveEngine(
    browser: browser,
    db: db,
    fileStore: FileStore(root),
    downloader: AssetFetcher(browser: browser, config: config),
    config: config,
  );

  /// The audit's regression fixture: valid DOM (panels + avatars), zero
  /// viewport, frozen scroll.
  PageProbe hiddenSurface(int y) => lazyStripProbe(
    y: 0,
    viewportHeight: 0,
    panelCount: 5,
    extraImages: [
      avatarImage(1, complete: true),
      avatarImage(2, complete: true),
      avatarImage(3, complete: true),
    ],
  );

  test('zero viewport pauses the save instead of extracting', () async {
    final states = <SaveState>[];
    final browser = ScriptedBrowser(probeBuilder: (y, _) => hiddenSurface(y))
      ..scrollMoves = false
      ..setUrl('https://x.example/guide/foo/1');

    final eng = SaveEngine(
      browser: browser,
      db: db,
      fileStore: FileStore(root),
      downloader: AssetFetcher(browser: browser, config: config),
      config: config,
      onProgress: (update) => states.add(update(const SaveProgress()).state),
    );

    final run = eng.saveCurrentPage(
      collectionId: 'collection-1',
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: CaptureMode.imageSequence,
    );

    // Give it ample time to (wrongly) extract if it were going to.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      states,
      contains(SaveState.waitingForBrowser),
      reason: 'the hold must be visible to the UI',
    );
    expect(
      states,
      isNot(contains(SaveState.extracting)),
      reason: 'nothing may be extracted from an unrendered surface',
    );

    eng.cancel();
    final result = await run;
    expect(result.status, SaveStatus.failed);
    expect(await db.allEntries(), isEmpty, reason: 'nothing stored');
    expect(
      Directory(root.path).listSync(recursive: true).whereType<File>(),
      isEmpty,
      reason: 'no files written',
    );
  });

  test('surface coming back resumes and saves normally', () async {
    // Hidden for the first 5 probes, rendered afterwards. Downloads still
    // fail (no server), but the run must get PAST the guard and reach
    // extraction/download rather than waiting forever.
    final browser = ScriptedBrowser(
      probeBuilder: (y, n) => n <= 5
          ? hiddenSurface(y)
          : lazyStripProbe(y: y, viewportHeight: 800, panelCount: 5),
    )..setUrl('https://x.example/guide/foo/1');

    final result = await engine(browser).saveCurrentPage(
      collectionId: 'collection-1',
      entryOrder: 1,
      visitedNormalized: {},
      captureMode: CaptureMode.imageSequence,
    );

    // It proceeded to the download phase (and failed there for lack of a
    // server) — the guard released; it did not hold forever and did not
    // refuse extraction.
    expect(result.error, 'No images could be downloaded');
  });

  test(
    'avatar-only collapse after healthy scrolling refuses to store',
    () async {
      // Scrolling sees tall real panels; the final verify probe sees only
      // avatars (rendered surface, but the reader content was torn down).
      // Extraction must refuse — never a complete entry of avatars.
      final browser = ScriptedBrowser(
        probeBuilder: (y, n) {
          final avatarsOnly = PageProbe(
            url: 'https://x.example/guide/foo/1',
            title: 'Foo Entry 1',
            readyState: 'complete',
            documentHeight: 4000,
            viewportHeight: 800,
            scrollY: y,
            atBottom: true,
            images: [
              for (var i = 0; i < 4; i++)
                PageImage(
                  domIndex: i,
                  src: 'https://cdn.example/avatar/big$i.webp',
                  currentSrc: 'https://cdn.example/avatar/big$i.webp',
                  complete: true,
                  naturalWidth: 538,
                  naturalHeight: 539,
                  renderedWidth: 538,
                  renderedHeight: 539,
                  documentTop: i * 600,
                ),
            ],
          );
          // Healthy tall strips while scrolling (probes before the last two),
          // avatars at verify time.
          return n < 12
              ? lazyStripProbe(
                  y: y,
                  viewportHeight: 800,
                  panelCount: 4,
                  panelHeight: 13000,
                )
              : avatarsOnly;
        },
      )..setUrl('https://x.example/guide/foo/1');

      final result = await engine(browser).saveCurrentPage(
        collectionId: 'collection-1',
        entryOrder: 1,
        visitedNormalized: {},
        captureMode: CaptureMode.imageSequence,
      );

      expect(result.status, SaveStatus.failed);
      expect(result.extractionFailed, isTrue, reason: 'asks the user instead');
      expect(result.error, contains('changed under the save'));
      expect(await db.allEntries(), isEmpty);
    },
  );

  test('the update checker holds on a hidden surface too', () async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 's1',
        title: 'Foo',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 's1',
        title: 'Foo Entry 1',
        sourceUrl: 'https://x.example/guide/foo/1',
        urlKey: 'https://x.example/guide/foo/1',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/s1/entries/c1',
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 3,
        storedAssetCount: 3,
        entryOrder: 1,
        byteSize: 1024,
        entryNumber: 1,
        sourceMarker: 'Entry 1',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );

    final browser = ScriptedBrowser(probeBuilder: (y, _) => hiddenSurface(y))
      ..setUrl('https://x.example/guide/foo/1');
    final checker = UpdateChecker(browser: browser, db: db);

    final outcome = checker.check('s1');
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      checker.log.join('\n'),
      contains('open the Browser'),
      reason: 'the hold is reported, not silent',
    );
    checker.cancel();
    final result = await outcome;
    expect(
      result.state,
      anyOf(UpdateCheckState.cancelled, UpdateCheckState.failed),
      reason: 'a cancelled hold never fabricates a result',
    );
  });
}
