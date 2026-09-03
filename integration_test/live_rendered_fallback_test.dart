// The rendered fallback, against a real website.
//
//   flutter test integration_test/live_rendered_fallback_test.dart -d <udid> \
//     --dart-define=LIVE_REFUSING_A='<an entry whose asset host refuses>' \
//     --dart-define=LIVE_REFUSING_B='<another entry on that same host>' \
//     --dart-define=LIVE_REFUSING_C='<a third, to consume the learned verdict>' \
//     --dart-define=LIVE_SERVING='<an entry whose assets download normally>'
//
// **Deliberately outside the deterministic suite, and deliberately not a
// fixture.** The thing under test is a host that serves its pictures to a
// browser and to nothing else, which is a property of a real website's
// delivery and cannot be modelled locally: a fixture that refuses on purpose
// proves the plumbing and nothing about whether the plumbing matches reality.
// With no `--dart-define` every case skips itself and says so, so nothing here
// can make `flutter test` depend on a network.
//
// No address is compiled in (test/repository_cleanliness_test.dart fails the
// build on one).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/data/asset_origin_repository.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/v2_harness.dart';

const String kRefusingA = String.fromEnvironment('LIVE_REFUSING_A');
const String kRefusingB = String.fromEnvironment('LIVE_REFUSING_B');
const String kRefusingC = String.fromEnvironment('LIVE_REFUSING_C');
const String kServing = String.fromEnvironment('LIVE_SERVING');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late V2App app;
  var caseIndex = 0;

  Future<void> boot(WidgetTester tester, {String tag = ''}) async {
    app = V2App(tag: 'live_${tag}_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    await showBrowser(tester);
  }

  /// Queue [url], start, and wait for the queue to fall idle.
  Future<String> capture(WidgetTester tester, String url, String label) async {
    app.resetObservations();
    await openPage(tester, app, url);
    final entryId = await app.queueSaveOf(url, title: label);
    await startQueue(tester, app);
    await pumpUntil(
      tester,
      () => !app.runner.isRunning,
      timeout: const Duration(minutes: 10),
      reason: '$label never finished',
    );
    for (final line in app.engineLog) {
      debugPrint('[live:$label] $line');
    }
    return entryId;
  }

  testWidgets(
    'a refused reading is kept as a rendering, and reads back offline',
    (tester) async {
      if (kRefusingA.isEmpty) {
        debugPrint('[live] skipped — no LIVE_REFUSING_A');
        return;
      }
      await boot(tester, tag: 'render');
      final origins = AssetOriginRepository(app.library);

      final entryId = await capture(tester, kRefusingA, 'A');

      // 1. The refusal was detected, and written down about the *origin*.
      final learned = await origins.all();
      debugPrint(
        '[live] learned: '
        '${learned.map((r) => '${r.origin}=${r.verdict}').join(', ')}',
      );
      expect(
        learned,
        isNotEmpty,
        reason: 'the refusal must be recorded against the asset origin',
      );

      // 2. …and the fallback ran instead of the entry failing.
      final task = await app.latestTaskFor(entryId);
      expect(
        task!.state,
        SaveTaskState.completed,
        reason: 'the capture ended ${task.state.name}: ${task.lastError}',
      );

      // 3. It is persisted, and it says what it is.
      final manifest = await app.manifestOf(entryId);
      expect(manifest, isNotNull);
      expect(
        manifest!.renderedFromPage,
        isTrue,
        reason: 'a rendering must never be recorded as the site’s own files',
      );
      expect(manifest.artifact, ArtifactFormat.imageSequence);
      expect(manifest.status, SaveStatus.complete);
      expect(manifest.storedAssetCount, greaterThan(1));
      debugPrint(
        '[live] manifest tiles=${manifest.storedAssetCount} '
        'rendered=${manifest.renderedFromPage}',
      );

      // 4. In order. The tiles are consecutive slices down the page, and each
      //    address carries the document position it was taken at, so "in
      //    order" is checkable rather than assumed. Asserted before the disk
      //    walk so the evidence is printed while the process is least loaded.
      final positions = [
        for (final asset in manifest.storedAssets)
          int.tryParse(asset.sourceUrl.split('#rendered-at-').last) ?? -1,
      ];
      debugPrint(
        '[live] tile positions: first=${positions.take(3).toList()} '
        'last=${positions.skip(positions.length - 3).toList()} '
        'strictlyIncreasing='
        '${List.generate(positions.length - 1, (i) => positions[i + 1] > positions[i]).every((e) => e)}',
      );
      expect(
        positions.every((p) => p >= 0),
        isTrue,
        reason: 'every stored tile records where it was taken',
      );
      for (var i = 1; i < positions.length; i++) {
        expect(
          positions[i],
          greaterThan(positions[i - 1]),
          reason: 'tile $i is not below tile ${i - 1}',
        );
      }

      // 5. Nothing about reading it needs the website. Every page is a file in
      //    the app's own container, and no tile address is even fetchable.
      final copy = await app.ui.offline.activeCopyOf(entryId);
      expect(copy, isNotNull, reason: 'an OfflineCopy must exist');
      final read = await resolveOfflineRead(
        entryId: entryId,
        offlineCopies: app.ui.offline,
        fileStore: app.fileStore,
      );
      expect(read, isA<OfflineImageRead>());
      final imageRead = read as OfflineImageRead;

      var bytesOnDisk = 0;
      for (final page in imageRead.pages) {
        expect(
          page.exists && page.file.existsSync(),
          isTrue,
          reason: 'page ${page.file.path} is not on this device',
        );
        bytesOnDisk += page.file.lengthSync();
      }
      debugPrint(
        '[live] offline read: ${imageRead.pages.length} page(s), '
        '${(bytesOnDisk / 1024).round()}KB on disk',
      );

      // And every page has real pixels, read from the file's own header.
      expect(
        imageRead.pages.every((p) => (p.width ?? 0) > 0 && (p.height ?? 0) > 0),
        isTrue,
        reason: 'a tile with no dimensions would not lay out',
      );

      await app.shutdown(dumpLog: false);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  testWidgets(
    'a second reading from the same refusing origin does not re-ask',
    (tester) async {
      if (kRefusingA.isEmpty || kRefusingB.isEmpty) {
        debugPrint('[live] skipped — needs LIVE_REFUSING_A and _B');
        return;
      }
      await boot(tester, tag: 'learn');
      final origins = AssetOriginRepository(app.library);

      // Two separate readings are what establishes a verdict — one is only a
      // suspicion, by design. The first is captured for real so the origin is
      // learned the way it would be in use.
      await capture(tester, kRefusingA, 'first');
      final afterFirst = await origins.all();
      debugPrint(
        '[live] after first: '
        '${afterFirst.map((r) => '${r.origin}=${r.verdict} '
            'n=${r.refusedCaptures}').join(', ')}',
      );

      await capture(tester, kRefusingB, 'second');
      final afterSecond = await origins.all();
      debugPrint(
        '[live] after second: '
        '${afterSecond.map((r) => '${r.origin}=${r.verdict} '
            'n=${r.refusedCaptures}').join(', ')}',
      );
      expect(
        afterSecond.any((r) => r.verdict == AssetOriginVerdict.refusing.name),
        isTrue,
        reason: 'two separate refused readings establish the verdict',
      );

      // The second capture is what *created* the verdict, so it could not
      // have used it. A third reading is the first one that can, and this is
      // the whole point of the memory: it must not ask for every panel again.
      if (kRefusingC.isNotEmpty) {
        await capture(tester, kRefusingC, 'third');
        final askedOnce = app.engineLog.any(
          (l) => l.contains('known refusing origin'),
        );
        final askedForEverything = app.engineLog.any(
          (l) => l.contains('were refused by the host'),
        );
        debugPrint(
          '[live] third capture: oneProbePath=$askedOnce '
          'fullDownloadAttempt=$askedForEverything',
        );
        expect(
          askedOnce,
          isTrue,
          reason:
              'a third reading from an established refusing origin must ask '
              'once, not once per panel',
        );
        expect(
          askedForEverything,
          isFalse,
          reason: 'and it must not run the full download loop at all',
        );
      } else {
        debugPrint('[live] no LIVE_REFUSING_C — third-reading case skipped');
      }

      // Several readings from one site, and the consent question put **once**.
      // The answer is stored against the Source, so every reading after the
      // first reads it rather than asking again.
      debugPrint(
        '[live] consent prompts across all readings: '
        '${app.renderedFallbackPrompts}',
      );
      expect(
        app.renderedFallbackPrompts,
        1,
        reason: 'a Source is asked once, not once per Entry',
      );

      await app.shutdown(dumpLog: false);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );

  testWidgets('a site that serves its files still gets the originals', (
    tester,
  ) async {
    if (kServing.isEmpty) {
      debugPrint('[live] skipped — no LIVE_SERVING');
      return;
    }
    await boot(tester, tag: 'serving');
    final entryId = await capture(tester, kServing, 'serving');

    final manifest = await app.manifestOf(entryId);
    expect(manifest, isNotNull);
    expect(
      manifest!.renderedFromPage,
      isNull,
      reason: 'the primary path must stay primary where it works',
    );
    expect(manifest.status, SaveStatus.complete);
    expect(manifest.storedAssetCount, greaterThan(1));
    // The addresses are the site's own files, not positions down a page.
    expect(
      manifest.storedAssets.every(
        (a) => !a.sourceUrl.contains('#rendered-at-'),
      ),
      isTrue,
    );
    debugPrint(
      '[live] originals: ${manifest.storedAssetCount} asset(s), '
      'rendered=${manifest.renderedFromPage}',
    );

    await app.shutdown(dumpLog: false);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
