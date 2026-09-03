// The text capture modes, end to end against the controlled fixture on a real
// WebView.
//
//   flutter test integration_test/text_capture_test.dart -d <device-id>
//
// Nothing here is mocked: a live WebView loads the fixture, the injected bridge
// walks the real DOM, `save/document_extraction.dart` decides what survives,
// inline images are downloaded into the app container, and a document package
// is committed and read back.
//
// **What the V2 port changed: where the mode comes from.** V1 passed
// `captureMode:` into `SaveRunController.start`. V2 carries it on the queue row
// — decided on the page the user was looking at, in the save sheet, and never
// re-derived later — so the mode travels with the task and
// `captureModeIsUserSet` records whether a *person* chose it or detection did.
// Everything the mode then means is unchanged: the three concepts stay separate
// (`ContentKind` what the page is, `CaptureMode` what was asked for,
// `ArtifactFormat` what the package holds), only `ArtifactFormat` decides how an
// entry is read, and a document is stored as typed blocks in `document.json`
// with no HTML anywhere in it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/document_extraction.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Delays off: the two-second slow panel is `/img/`'s, and nothing here reads
  // an image sequence.
  final fixture = FixtureSite(applyDelays: false);
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester, {String? startUrl}) async {
    app = V2App(tag: 'text_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    // A WKWebView that has never been painted reports zero layout metrics, and
    // every geometry rule here depends on real ones.
    await showBrowser(tester);
    if (startUrl != null) await openPage(tester, app, startUrl);
  }

  tearDown(() => app.shutdown());

  /// Queue the page the Browser is on in [mode], start, and return the Entry.
  Future<String> captureCurrent(WidgetTester tester, CaptureMode mode) async {
    final entryId = await app.queueSaveOf(
      app.browser.currentUrl,
      captureMode: mode,
      captureModeIsUserSet: true,
    );
    await startQueue(tester, app);
    await awaitQueueIdle(tester, app);
    final task = await app.latestTaskFor(entryId);
    expect(
      task!.state,
      SaveTaskState.completed,
      reason: 'the capture ended ${task.state.name}: ${task.lastError}',
    );
    return entryId;
  }

  testWidgets(
    'the bridge extracts real structure from a live DOM',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/textimages/1');

      final raw = await app.browser.extractDocument();
      expect(raw, isNotNull, reason: 'the bridge could not read the page');
      expect(raw!.regionBasis, isNotEmpty);

      final result = extractDocument(
        raw,
        mode: CaptureMode.textAndImages,
        sourceUrl: '${fixture.base}/textimages/1',
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
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a live prose page classifies as an article',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/text/1');
      final probe = await app.browser.probe(withLinks: true);

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.content.kind, ContentKind.article);
      expect(capabilities.allows(CaptureMode.textOnly), isTrue);
      expect(capabilities.defaultMode, CaptureMode.textOnly);
      expect(capabilities.videoDominant, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a live illustrated page offers text and images by default',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/textimages/1');
      final probe = await app.browser.probe(withLinks: true);

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.allows(CaptureMode.textAndImages), isTrue);
      expect(capabilities.defaultMode, CaptureMode.textAndImages);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a live image sequence still defaults to images',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));
      final probe = await app.browser.probe(withLinks: true);

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.allows(CaptureMode.imageSequence), isTrue);
      expect(capabilities.defaultMode, CaptureMode.imageSequence);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // --- a page whose only words are its own furniture -----------------------
  //
  // A real page of stacked panels declared no <article>, no <main> and no
  // dense paragraph container, wrote its menus and its sign-in box as <div>s
  // rather than <nav>/<footer>, and carried `sidebar-hidden` on its readable
  // column. The signals therefore measured ~6,400 characters of "prose" over
  // 23 "paragraphs" — every one of them furniture — and reported no
  // content-region images at all. The page classified as an article, resolved
  // to a text capture, and failed saying it had no readable text. That was
  // true, and it said nothing about the 132 panels never looked at.
  //
  // Both halves are asserted, because either one alone reproduces it.

  testWidgets(
    'a page whose only words are furniture is not an article',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/noprose');
      final probe = await app.browser.probe(withLinks: true);

      // Furniture text is not prose. The fixture carries several thousand
      // characters of it, all inside named containers.
      expect(
        probe.content.textLength,
        lessThan(900),
        reason:
            'the menus, the listing and the sign-in box were counted as the '
            "page's prose",
      );
      expect(
        probe.content.paragraphCount,
        lessThan(3),
        reason:
            'paragraphCount counted every <p> in the document rather than '
            'the ones behind the prose measurement',
      );
      expect(probe.content.looksProse, isFalse);
      expect(probe.content.looksImageDominant, isTrue);

      // A negated state class is not a declaration of furniture: the readable
      // column is `main-col sidebar-hidden`, and its panels are in the region.
      expect(
        probe.content.contentRegionImageCount,
        greaterThanOrEqualTo(6),
        reason:
            '"sidebar-hidden" names the column left when the sidebar is gone '
            '— read as a declaration it empties the content region',
      );

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.content.kind, ContentKind.imageDominant);
      expect(capabilities.allows(CaptureMode.imageSequence), isTrue);
      expect(
        capabilities.allows(CaptureMode.textOnly),
        isFalse,
        reason: 'there is nothing on this page to read',
      );
      expect(capabilities.defaultMode, CaptureMode.imageSequence);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'that page saves its panels, in order, with no furniture among them',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/noprose');

      // No mode is passed: null means "decide from the settled page", which
      // is the decision that used to come out as text.
      final entryId = await app.queueSaveOf(app.browser.currentUrl);
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final task = await app.latestTaskFor(entryId);
      expect(
        task!.state,
        SaveTaskState.completed,
        reason: 'the capture ended ${task.state.name}: ${task.lastError}',
      );

      final manifest = await app.manifestOf(entryId);
      expect(manifest, isNotNull);
      expect(manifest!.artifact, ArtifactFormat.imageSequence);

      final sources = manifest.assets.map((a) => a.sourceUrl).toList();
      expect(
        sources,
        [for (var i = 1; i <= 6; i++) '${fixture.base}/img/1/$i.png'],
        reason: 'the panels, in reading order, and nothing else',
      );
      // The logo, the tracking pixel and everything else the page decorates
      // itself with stayed out.
      expect(sources.any((s) => s.contains('/chrome/')), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'a live video page is classified and refused',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/videopage');
      final probe = await app.browser.probe(withLinks: true);

      expect(probe.media.videoCount, greaterThan(0));
      expect(probe.media.primaryVideoPixels, greaterThan(0));
      expect(probe.media.videoInContentRegion, isTrue);

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.content.kind, ContentKind.videoDominant);
      expect(capabilities.videoDominant, isTrue);
      // No readable article and no image sequence: nothing to offer, and
      // deliberately NOT a sweep of the sidebar thumbnails.
      expect(capabilities.canSaveAnything, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'the save sheet offers nothing on a video page',
    (tester) async {
      // The V2 half of the case above: what the user actually sees. The sheet is
      // built from `CaptureCapabilities`, so a page that can hold nothing offers
      // no save rather than a button that would refuse.
      await boot(tester, startUrl: '${fixture.base}/videopage');

      await tester.tap(
        find.byKey(const ValueKey('browserSaveAction')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 4));

      // **No route into the queue at all.** A button the engine could not
      // honour would be a button that lies, and the sheet is built from
      // `CaptureCapabilities` precisely so that it has none to offer here.
      //
      // The `videoNotSavedNotice` this used to look for is part of the
      // *capture block*, and V2-D69 moved that block off this sheet: what a
      // page can be saved as is asked on the sheet the Collection picker
      // hands back, once there is a Collection to save into. On a page the
      // library knows nothing about there is no such block, so the notice is
      // not drawn — which leaves a video page saying nothing about why it
      // offers nothing. That is a wording gap, reported rather than asserted;
      // what the product rule actually promises is that no route exists, and
      // that is what is checked.
      for (final absent in [
        'v2SaveStandalone',
        'v2AddToCollection',
        'saveScopeThisEntry',
        'saveScopeFromHere',
        'saveScopeAddToQueue',
        'startInBrowser',
        'startKeepUsingApp',
        'v2StartButton',
      ]) {
        expect(
          find.byKey(ValueKey(absent)),
          findsNothing,
          reason:
              '$absent must not be offered for a page nothing can be taken '
              'from',
        );
      }
      // And nothing reached the queue by any other means.
      expect(await app.ui.queue.all(), isEmpty);
      expect(await app.ui.offline.allCopies(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'a live ambiguous page keeps its answer low-confidence',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/ambiguous');
      final probe = await app.browser.probe(withLinks: true);

      final capabilities = detectCaptureCapabilities(probe);
      expect(capabilities.content.confidence.isActionable, isFalse);
      expect(capabilities.videoDominant, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'text only writes a document package with no assets',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/text/1');
      final entryId = await captureCurrent(tester, CaptureMode.textOnly);

      final copy = await app.ui.offline.activeCopyOf(entryId);
      expect(copy, isNotNull);
      expect(copy!.artifactFormat, ArtifactFormat.structuredDocument.name);

      final manifest = (await app.fileStore.readManifest(copy.contentPath))!;
      expect(manifest.schemaVersion, EntryManifest.currentSchemaVersion);
      expect(manifest.artifact, ArtifactFormat.structuredDocument);
      expect(manifest.captureMode, CaptureMode.textOnly.name);
      expect(
        manifest.captureModeIsUserSet,
        isTrue,
        reason:
            '"the person chose this" is a different fact from "the page did"',
      );
      expect(manifest.document, isNotNull);
      expect(manifest.storedAssetCount, 0);

      final document = await app.fileStore.readDocument(copy.contentPath);
      expect(document!.blockCount, greaterThan(5));
      expect(document.textLength, greaterThan(500));
      expect(document.blocks.any((b) => b.isImage), isFalse);
      expect(
        Directory(
          '${app.fileStore.resolve(copy.contentPath)}/assets',
        ).listSync(),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'text and images downloads the figures and keeps their places',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/textimages/2');
      final entryId = await captureCurrent(tester, CaptureMode.textAndImages);

      final copy = (await app.ui.offline.activeCopyOf(entryId))!;
      expect(copy.artifactFormat, ArtifactFormat.structuredDocument.name);

      final manifest = (await app.fileStore.readManifest(copy.contentPath))!;
      expect(manifest.storedAssetCount, 2);
      final document = (await app.fileStore.readDocument(copy.contentPath))!;
      final images = document.blocks.where((b) => b.isImage).toList();
      expect(images, hasLength(2));

      for (final block in images) {
        final asset = manifest.assetByIndex(block.assetIndex!)!;
        final file = File(
          '${app.fileStore.resolve(copy.contentPath)}/${asset.relativePath}',
        );
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      }

      // A figure sits between two text blocks, not bunched at either end.
      final firstImage = document.blocks.indexWhere((b) => b.isImage);
      expect(firstImage, greaterThan(0));
      expect(firstImage, lessThan(document.blockCount - 1));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'the saved text opens offline with the source unreachable',
    (tester) async {
      await boot(tester, startUrl: '${fixture.base}/text/3');
      final entryId = await captureCurrent(tester, CaptureMode.textOnly);

      // Take the source away entirely, then read what is on the device — through
      // the V2 resolution path, which asks the *copy* rather than an Entry row.
      await fixture.stop();
      expect(await fixture.reachable(), isFalse);

      final read = await resolveOfflineRead(
        entryId: entryId,
        offlineCopies: app.ui.offline,
        fileStore: app.fileStore,
      );
      expect(read, isA<OfflineDocumentRead>());
      final document = (read as OfflineDocumentRead).document;
      expect(document.textLength, greaterThan(500));
      expect(document.blocks.first.text, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
