// End-to-end proof of the text capture modes against the controlled fixture,
// on a real WebView in the iOS Simulator.
//
//   flutter test integration_test/text_capture_test.dart -d <simulator-id>
//
// Nothing here is mocked: a live WebView loads the fixture, the injected
// bridge walks the real DOM, the extractor decides what survives, inline
// images are downloaded into the app container, and a document package is
// committed and read back. The fixture is served in-process, like every other
// integration suite.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/document_extraction.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';

late String kFixtureBase;

final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FileStore fileStore;
  late BrowserController browser;
  late SaveRunController run;
  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    kFixtureBase = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      try {
        await for (final req in server) {
          try {
            await handleFixtureRequest(req, applyDelays: false);
          } catch (_) {
            /* client went away */
          }
        }
      } catch (_) {
        /* server closed */
      }
    }());
  });

  tearDownAll(() => server.close(force: true));

  Future<void> bootApp(WidgetTester tester, {String? startUrl}) async {
    db = AppDatabase(name: 'it_text_capture_$kRunStamp');
    fileStore = await FileStore.open(
      folderName: 'webread_it_text_capture_$kRunStamp',
    );
    browser = BrowserController();
    run = SaveRunController(browser: browser, db: db, fileStore: fileStore);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            AppServices(
              db: db,
              fileStore: fileStore,
              browser: browser,
              saveRun: run,
            ),
          ),
        ],
        child: const WebReaderApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A WKWebView that has never been painted reports zero layout metrics,
    // and every geometry rule here depends on real ones.
    await tester.tap(
      find.byKey(const ValueKey('navTab-Browser')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 600));

    if (startUrl != null) {
      await browser.loadAndWait(startUrl);
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: 'timed out waiting for the condition');
  }

  tearDown(() async {
    for (final line in run.log.reversed) {
      debugPrint('[run] $line');
    }
    // Loading a page kicks off a favicon fetch that writes to the database
    // without anyone awaiting it. Closing the connection out from under it
    // throws *after* the test has already passed, which reads as a failure
    // and is not one — so give the in-flight write somewhere to land first.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await db.close();
  });

  /// Save the page the browser is on, in [mode], and return the stored entry.
  Future<Entry> saveCurrent(
    WidgetTester tester,
    CaptureMode mode, {
    String? url,
  }) async {
    unawaited(
      run.start(
        entryLimit: 1,
        range: SaveScope.currentPageOnly,
        startUrl: url ?? browser.currentUrl,
        captureMode: mode,
        captureModeIsUserSet: true,
      ),
    );
    await pumpUntil(tester, () => !run.isRunning);
    final entries = await db.allEntries();
    expect(entries, isNotEmpty, reason: 'the save produced no entry');
    return entries.last;
  }

  testWidgets('the bridge extracts real structure from a live DOM', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/textimages/1');

    final raw = await browser.extractDocument();
    expect(raw, isNotNull, reason: 'the bridge could not read the page');
    expect(raw!.regionBasis, isNotEmpty);

    final result = extractDocument(
      raw,
      mode: CaptureMode.textAndImages,
      sourceUrl: '$kFixtureBase/textimages/1',
    );
    expect(result.isSuccess, isTrue, reason: '${result.failure}');

    final document = result.document!;
    final types = document.blocks.map((b) => b.type).toSet();
    expect(types, contains(DocumentBlockType.heading));
    expect(types, contains(DocumentBlockType.paragraph));
    expect(types, contains(DocumentBlockType.quote));
    expect(types, contains(DocumentBlockType.listItem));
    expect(types, contains(DocumentBlockType.image));

    final text = document.blocks.map((b) => b.text).join(' ');
    // Everything the fixture marks as furniture must be absent.
    expect(text, isNot(contains('must not be saved')));
    expect(text, isNot(contains('Recommended')));
    expect(text, isNot(contains('hidden note')));
    // …and the real content must be present.
    expect(text, contains('Paragraph 1 of entry 1'));
    expect(text, contains('A subheading'));

    // The tracking pixel and the sidebar recommendation are not figures.
    expect(document.blocks.where((b) => b.isImage), hasLength(2));
  });

  testWidgets('a live prose page classifies as an article', (tester) async {
    await bootApp(tester, startUrl: '$kFixtureBase/text/1');
    final probe = await browser.probe(withLinks: true);

    final caps = detectCaptureCapabilities(probe);
    expect(caps.content.kind, ContentKind.article);
    expect(caps.allows(CaptureMode.textOnly), isTrue);
    expect(caps.defaultMode, CaptureMode.textOnly);
    expect(caps.videoDominant, isFalse);
  });

  testWidgets('a live illustrated page offers text and images by default', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/textimages/1');
    final probe = await browser.probe(withLinks: true);

    final caps = detectCaptureCapabilities(probe);
    expect(caps.allows(CaptureMode.textAndImages), isTrue);
    expect(caps.defaultMode, CaptureMode.textAndImages);
  });

  testWidgets('a live image sequence still defaults to images', (tester) async {
    await bootApp(tester, startUrl: '$kFixtureBase/entry/1');
    final probe = await browser.probe(withLinks: true);

    final caps = detectCaptureCapabilities(probe);
    expect(caps.allows(CaptureMode.imageSequence), isTrue);
    expect(caps.defaultMode, CaptureMode.imageSequence);
  });

  testWidgets('a live video page is classified and refused', (tester) async {
    await bootApp(tester, startUrl: '$kFixtureBase/videopage');
    final probe = await browser.probe(withLinks: true);

    expect(probe.media.videoCount, greaterThan(0));
    expect(probe.media.primaryVideoPixels, greaterThan(0));
    expect(probe.media.videoInContentRegion, isTrue);

    final caps = detectCaptureCapabilities(probe);
    expect(caps.content.kind, ContentKind.videoDominant);
    expect(caps.videoDominant, isTrue);
    // No readable article and no image sequence: nothing to offer, and
    // deliberately NOT a sweep of the sidebar thumbnails.
    expect(caps.canSaveAnything, isFalse);
  });

  testWidgets('a live ambiguous page keeps its answer low-confidence', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/ambiguous');
    final probe = await browser.probe(withLinks: true);

    final caps = detectCaptureCapabilities(probe);
    expect(caps.content.confidence.isActionable, isFalse);
    expect(caps.videoDominant, isFalse);
  });

  testWidgets('text only writes a document package with no assets', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/text/1');
    final entry = await saveCurrent(tester, CaptureMode.textOnly);

    expect(entry.saveStatus, 'complete');
    expect(entry.artifactFormat, ArtifactFormat.structuredDocument.name);
    expect(entry.captureMode, CaptureMode.textOnly.name);
    expect(entry.storedAssetCount, 0);

    final manifest = await fileStore.readManifest(entry.contentPath!);
    expect(manifest!.schemaVersion, EntryManifest.currentSchemaVersion);
    expect(manifest.artifact, ArtifactFormat.structuredDocument);
    expect(manifest.document, isNotNull);

    final document = await fileStore.readDocument(entry.contentPath!);
    expect(document!.blockCount, greaterThan(5));
    expect(document.textLength, greaterThan(500));
    expect(document.blocks.any((b) => b.isImage), isFalse);
    expect(
      Directory('${fileStore.resolve(entry.contentPath!)}/assets').listSync(),
      isEmpty,
    );
  });

  testWidgets('text and images downloads the figures and keeps their places', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/textimages/2');
    final entry = await saveCurrent(tester, CaptureMode.textAndImages);

    expect(entry.saveStatus, 'complete');
    expect(entry.artifactFormat, ArtifactFormat.structuredDocument.name);
    expect(entry.storedAssetCount, 2);

    final manifest = (await fileStore.readManifest(entry.contentPath!))!;
    final document = (await fileStore.readDocument(entry.contentPath!))!;
    final images = document.blocks.where((b) => b.isImage).toList();
    expect(images, hasLength(2));

    for (final block in images) {
      final asset = manifest.assetByIndex(block.assetIndex!)!;
      final file = File(
        '${fileStore.resolve(entry.contentPath!)}/${asset.relativePath}',
      );
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    }

    // A figure sits between two text blocks, not bunched at either end.
    final firstImage = document.blocks.indexWhere((b) => b.isImage);
    expect(firstImage, greaterThan(0));
    expect(firstImage, lessThan(document.blockCount - 1));
  });

  testWidgets('the saved text opens offline with the source unreachable', (
    tester,
  ) async {
    await bootApp(tester, startUrl: '$kFixtureBase/text/3');
    final entry = await saveCurrent(tester, CaptureMode.textOnly);

    // Take the source away entirely, then read what is on the device.
    await server.close(force: true);

    final document = await fileStore.readDocument(entry.contentPath!);
    expect(document, isNotNull);
    expect(document!.textLength, greaterThan(500));
    expect(document.blocks.first.text, isNotEmpty);
  });
}
