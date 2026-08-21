/// The whole V2 read path, end to end, with nothing V1 behind it.
///
/// One page, driven by the **ported save engine** over a faked browser, and
/// then: staged, gated, committed by the pipeline, recorded as an OfflineCopy,
/// resolved back out of that copy, and opened in the **real reader** — which
/// is handed its package instead of loading V1 rows.
///
/// What makes this worth running is what is absent. No `AppDatabase` is
/// constructed anywhere in it: not by the capture (the engine writes through
/// `StagedPackageSink`), not by the reader (it is given
/// [OfflineReaderData] and never reads `databaseProvider`). The widget is
/// pumped in a [ProviderScope] with **no overrides at all**, so any V1
/// provider it touched would throw `UnimplementedError` and fail the test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/features/document_reader.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/storage/manifest.dart';

import '../helpers/fake_browser.dart';
import 'support/capture_harness.dart';

const _url = 'https://reading.example.com/serial-alpha/part-101';

String _filler([int n = 10]) =>
    List.filled(n, 'The quick brown fox jumps over the lazy dog. ').join();

PageProbe _prosePage({String url = _url}) => PageProbe(
  url: url,
  title: 'Part 101',
  readyState: 'complete',
  documentHeight: 6000,
  viewportHeight: 800,
  viewportWidth: 400,
  atBottom: true,
  content: const PageContentSignals(
    textLength: 9000,
    paragraphCount: 20,
    headingCount: 1,
    hasArticleElement: true,
  ),
);

/// Long enough that a restore has somewhere to go: a document that fits on one
/// screen cannot demonstrate a reading position at all.
RawDocument _rawDocument() => RawDocument(
  title: 'Part 101',
  regionBasis: 'article element',
  blocks: [
    const RawDocumentBlock(kind: 'heading', text: 'Part 101', level: 1),
    for (var i = 0; i < 12; i++)
      RawDocumentBlock(kind: 'paragraph', text: _filler()),
  ],
);

void main() {
  late CaptureHarness h;

  setUp(() => h = CaptureHarness());
  tearDown(() => h.close());

  FakeBrowser browserFor({String? landsOn}) {
    final browser = FakeBrowser()..setUrl('about:blank');
    final landed = landsOn ?? _url;
    if (landsOn != null) browser.redirects[_url] = landsOn;
    browser.addPage(landed, _prosePage(url: landed));
    browser.addDocument(landed, _rawDocument());
    return browser;
  }

  /// The production source, over the browser fake the save suites already use.
  /// Everything WebView-bound is closed over here; nothing else about the
  /// engine changes.
  PageCaptureSource sourceOver(FakeBrowser browser) =>
      SaveEnginePageCaptureSource(
        browser: browser,
        engineFor: (sink) => SaveEngine(
          browser: browser,
          fileStore: h.fileStore,
          downloader: AssetFetcher(
            browser: browser,
            config: kDefaultSaveConfig,
          ),
          sink: sink,
        ),
      );

  Future<EntryCaptureResult> captureOne({
    FakeBrowser? browser,
    String? locationUrl,
  }) async {
    final seeded = await h.repos.seedLibrary();
    return h
        .captureWith(sourceOver(browser ?? browserFor()))
        .capture(
          entryId: seeded.entry.id,
          locationId: seeded.location.id,
          locationUrl: locationUrl ?? seeded.location.url,
          captureMode: CaptureMode.textOnly,
        );
  }

  group('the ported engine, ended at a staged package', () {
    test('the pipeline commits it and records the copy', () async {
      final result = await captureOne();

      expect(result.status, EntryCaptureStatus.captured);
      expect(result.manifest!.artifact, ArtifactFormat.structuredDocument);
      expect(result.manifest!.sourceUrl, _url);
      // The judgement came from the settled page, through the engine's own
      // manifest — the pipeline recorded it and re-derived nothing.
      expect(result.manifest!.captureMode, CaptureMode.textOnly.name);
      expect(result.manifest!.status, SaveStatus.complete);

      // One committed package, nothing left in staging, one copy row.
      expect(h.committedPaths(), hasLength(1));
      expect(h.stagingLeftovers(), isEmpty);
      final copies = await h.repos.offline.allCopies();
      expect(copies, hasLength(1));
      expect(copies.single.contentPath, result.contentPath);
      expect(copies.single.byteSize, greaterThan(0));

      // …and the package on disk reads back as what it claims to be.
      final document = await h.fileStore.readDocument(result.contentPath!);
      expect(document!.blockCount, 13);
    });

    test('a landed refusal is the source\'s own boundary', () async {
      // The address the task named is fine; the navigation ended somewhere
      // this app does not save from. Only the thing that navigates can know
      // that, which is why the source owns this check and reports it.
      final browser = browserFor(landsOn: restrictedUrl('/serial/part-101'));
      final result = await captureOne(browser: browser);

      expect(result.status, EntryCaptureStatus.refused);
      expect(result.stopReason, StopReason.captureRestrictedForSite);
      expect(h.committedPaths(), isEmpty);
      expect(h.stagingLeftovers(), isEmpty);
      expect(await h.repos.offline.allCopies(), isEmpty);
    });

    test('a cancelled capture commits nothing', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h
          .captureWith(sourceOver(browserFor()))
          .capture(
            entryId: seeded.entry.id,
            locationUrl: seeded.location.url,
            captureMode: CaptureMode.textOnly,
            shouldContinue: () => false,
          );

      expect(result.status, EntryCaptureStatus.failed);
      expect(result.stopReason, StopReason.cancelledByUser);
      expect(h.committedPaths(), isEmpty);
      expect(h.stagingLeftovers(), isEmpty);
      expect(await h.repos.offline.allCopies(), isEmpty);
    });
  });

  group('the copy opens the real reader', () {
    testWidgets('with its data provided and no V1 library anywhere', (
      tester,
    ) async {
      late EntryCaptureResult captured;
      late OfflineReaderData data;
      late String entryId;

      await tester.runAsync(() async {
        final seeded = await h.repos.seedLibrary();
        entryId = seeded.entry.id;
        captured = await h
            .captureWith(sourceOver(browserFor()))
            .capture(
              entryId: entryId,
              locationId: seeded.location.id,
              locationUrl: seeded.location.url,
              captureMode: CaptureMode.textOnly,
            );
        expect(captured.status, EntryCaptureStatus.captured);

        // Somewhere in the middle of the text, so a restore has an offset
        // worth having.
        await h.repos.offline.saveAnchor(
          entryId,
          anchorIndex: 8,
          anchorOffset: 0,
        );

        data = OfflineReaderData(
          read: await h.read(entryId),
          session: h.sessionFor(entryId),
        );
      });

      expect(data.read, isA<OfflineDocumentRead>());

      // No overrides: a reader that reached for `databaseProvider` — to load a
      // row, to record the open, to save progress — would throw here.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ReaderScreen(entryId: entryId, offline: data),
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(DocumentBody).evaluate().isNotEmpty) break;
      }
      expect(
        find.byType(DocumentBody),
        findsOneWidget,
        reason: 'the reader never opened the provided package',
      );
      expect(find.textContaining('The quick brown fox'), findsWidgets);

      // The document restores **to** its position, not at it: it is laid out
      // from the top and jumps on the first measurement, because a paragraph
      // has no offset until it has been laid out at this width.
      await tester.pump();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(
        position.pixels,
        greaterThan(0),
        reason: 'the anchor on the copy is where the reader should have gone',
      );

      // The open was recorded through the session, which writes to the V2
      // reading state and never to a V1 row. Opening is not finishing.
      final state = await h.repos.reading.stateOf(entryId);
      expect(state.status, ReadStatus.reading);
      expect(state.firstOpenedAt, isNotNull);

      // Leave nothing running: the reader debounces its progress write.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('an Entry with no copy says so and demotes nothing', (
      tester,
    ) async {
      late OfflineReaderData data;
      late String entryId;
      await tester.runAsync(() async {
        final seeded = await h.repos.seedLibrary();
        entryId = seeded.entry.id;
        data = OfflineReaderData(
          read: await h.read(entryId),
          session: h.sessionFor(entryId),
        );
      });

      expect(data.read, isA<OfflineReadUnavailable>());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ReaderScreen(entryId: entryId, offline: data),
          ),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.textContaining('not downloaded').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('not downloaded'), findsOneWidget);

      // Nothing was opened, so nothing was recorded: an Entry that cannot be
      // read here keeps its reading history exactly as it was.
      final state = await h.repos.reading.stateOf(entryId);
      expect(state.status, ReadStatus.unread);
      expect(state.firstOpenedAt, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
