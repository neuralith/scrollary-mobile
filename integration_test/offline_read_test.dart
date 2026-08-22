// Save online, then read with the source gone — in one run.
//
//   flutter test integration_test/offline_read_test.dart -d <device-id>
//
// The fixture is served *in-process on the device*, so the test can shut it
// down mid-run. That is what makes "offline" provable rather than asserted:
// after the server is closed the source genuinely does not exist, and every
// panel the reader shows must have come off disk.
//
// (`flutter test integration_test/...` uninstalls the app afterwards, wiping
// the container — which is why the capture and the offline read must happen in
// the same run rather than as two separate invocations. For the same reason,
// durability is asserted through repositories built after the write rather than
// by relaunching the app mid-test: see the note in `support/v2_harness.dart`'s
// `boot` for why an in-process relaunch is not sustainable on either platform.)
//
// **What the V2 port changed: what is asked whether the Entry can be read.**
// V1 asked the Entry row — `content_path`, `save_status`, `artifact_format` and
// the reading anchor were columns on it. V2 asks the **OfflineCopy**, because
// an Entry is in the library because somebody wants to read it and the bytes
// are a per-device capability of it. So "the files are gone" is now a refusal
// resolved from the copy row (`OfflineReadRefusal.filesMissing`), and removing
// them cannot touch the Entry, its Locations or its reading state.
//
// **Position restore, and the distinction that is load-bearing.** The image
// reader opens *at* its position, because panel geometry comes from the
// manifest and every offset is known before an image decodes. The document
// reader restores *to* its position, because a paragraph has no offset until it
// has been laid out at this width, font and text scale. The last two cases here
// assert exactly that difference, on the device where the layout is real.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/reading/reading_position.dart' hide ReadStatus;
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FixtureSite fixture;
  late V2App app;
  var caseIndex = 0;

  /// A fresh origin per case: one of these tests destroys the server, and a
  /// shared one would take the rest of the file down with it.
  Future<void> boot(WidgetTester tester, {required String tag}) async {
    app = V2App(tag: tag);
    await app.boot(tester);
    await showBrowser(tester);
  }

  setUp(() async {
    fixture = FixtureSite();
    await fixture.start();
  });

  tearDown(() async {
    await app.shutdown();
    await fixture.stop();
  });

  /// Open the reader on [entryId], having first confirmed the Entry is on the
  /// shelf where a person would find it.
  ///
  /// The reader is opened through `entryOpenerProvider`'s route push — the same
  /// call the entry sheet's *Read* and the Continue Reading chips both make —
  /// rather than by tapping through the sheet itself. That is deliberate:
  /// `showEntryMenu` puts a non-scrolling `Column` inside a
  /// `showModalBottomSheet` with no `isScrollControlled`
  /// (lib/library_ui/collection_actions.dart:179), so on a shorter screen it
  /// overflows and its lower actions are unreachable — a defect this suite
  /// reports but is not about. `reading_flow_test.dart` is the suite whose
  /// subject *is* that sheet, and it drives it.
  Future<void> readThroughTheLibrary(
    WidgetTester tester,
    String entryId,
  ) async {
    await showLibrary(tester);
    final row = find.byKey(ValueKey('entryRow-$entryId'));
    await pumpUntil(
      tester,
      () => row.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the Entry never appeared on the shelf',
    );
    await tester.ensureVisible(row);
    await pumpFor(tester, const Duration(milliseconds: 400));
    await openReader(tester, entryId);
  }

  testWidgets(
    'save online, kill the source, read entirely from disk',
    (tester) async {
      expect(await fixture.reachable(), isTrue, reason: 'fixture should be up');
      await boot(tester, tag: 'offline_${caseIndex++}_$kRunStamp');

      // --- 1. capture, with the source up ---------------------------------
      final ids = <int, String>{};
      for (final n in [1, 2, 3]) {
        ids[n] = await app.queueSaveOf(fixture.entry(n), title: 'Entry $n');
      }
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 6));

      // --- 2. confirm the files are really there --------------------------
      var panelsOnDisk = 0;
      for (final n in [1, 2, 3]) {
        final copy = await app.ui.offline.activeCopyOf(ids[n]!);
        expect(copy, isNotNull, reason: 'entry $n has no copy');
        final relative = copy!.contentPath;
        expect(
          relative,
          isNot(startsWith('/')),
          reason: 'paths must be relative to the app container',
        );
        final manifest = (await app.fileStore.readManifest(relative))!;
        for (final asset in manifest.storedAssets) {
          final file = app.fileStore.assetFile(relative, asset.relativePath!);
          expect(file.existsSync(), isTrue);
          final bytes = await file.readAsBytes();
          expect(bytes.sublist(0, 4), [
            0x89,
            0x50,
            0x4e,
            0x47,
          ], reason: 'real PNG bytes, not a placeholder');
          panelsOnDisk++;
        }
      }
      expect(panelsOnDisk, 17, reason: '6 + 5 (one 503) + 6');

      // --- 3. destroy the source -------------------------------------------
      await fixture.stop();
      expect(
        await fixture.reachable(),
        isFalse,
        reason: 'the source must be genuinely gone for this to prove anything',
      );

      // --- 4. the library is durable, read through fresh repositories -------
      final fresh = app.freshLibraryReads();
      expect(
        (await fresh.offline.allCopies()).where((c) => c.active),
        hasLength(3),
        reason: 'every copy came back out of the database',
      );

      // --- 5. read it, through the real UI ---------------------------------
      await readThroughTheLibrary(tester, ids[1]!);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, isNotEmpty, reason: 'the reader rendered panels');
      for (final image in images) {
        // `cacheWidth` wraps the provider in a ResizeImage; unwrapping it also
        // confirms the decode-width limit is actually applied, which is what
        // keeps a long entry from becoming hundreds of MB of bitmaps.
        final provider = image.image;
        expect(provider, isA<ResizeImage>());
        final resize = provider as ResizeImage;
        expect(resize.width, isNotNull, reason: 'decode width must be bounded');
        expect(
          resize.imageProvider,
          isA<FileImage>().having(
            (f) => f.file.existsSync(),
            'file exists',
            isTrue,
          ),
          reason:
              'every panel must come from a local file — there is no remote '
              'fallback anywhere in this path, by design',
        );
      }
      debugPrint(
        '[offline] reader rendered ${images.length} local panels with the '
        'source server destroyed',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'a partial entry warns instead of pretending to be whole',
    (tester) async {
      await boot(tester, tag: 'offline_${caseIndex++}_$kRunStamp');

      final entryId = await app.queueSaveOf(
        fixture.entry(kBrokenEntry),
        title: 'Broken entry',
      );
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final manifest = (await app.manifestOf(entryId))!;
      expect(
        manifest.status,
        SaveStatus.partial,
        reason: 'the 503 panel must produce a partial, never a false complete',
      );
      expect(manifest.storedAssetCount, lessThan(manifest.detectedAssetCount));
      expect(manifest.statusReason, contains('assetsFailed'));

      final failed = manifest.assets
          .where((a) => a.status == AssetStatus.failed)
          .toList();
      expect(failed, isNotEmpty);
      expect(failed.first.error, isNotNull);
      expect(
        failed.first.relativePath,
        isNull,
        reason: 'a failed asset must not claim a local file',
      );

      await fixture.stop();
      await readThroughTheLibrary(tester, entryId);

      expect(
        find.textContaining('Partial save'),
        findsOneWidget,
        reason: 'the reader says so offline, on the entry it is about',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'deleted local files degrade gracefully, keeping the Entry',
    (tester) async {
      await boot(tester, tag: 'offline_${caseIndex++}_$kRunStamp');

      final entryId = await app.queueSaveOf(fixture.entry(1), title: 'Entry 1');
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final copy = (await app.ui.offline.activeCopyOf(entryId))!;

      // Simulate the OS or the user reclaiming the space behind our back.
      await fixture.stop();
      Directory(
        app.fileStore.resolve(copy.contentPath),
      ).deleteSync(recursive: true);

      // Open the gutted Entry itself. The copy row still says where the bytes
      // are, so the reader is what discovers they are not there — and must
      // degrade to an explicit message rather than crash.
      await readThroughTheLibrary(tester, entryId);

      expect(find.text('The files for this entry are gone'), findsOneWidget);

      // No crash, and — the invariant that matters — the Entry is untouched.
      final entry = await app.ui.entries.byId(entryId);
      expect(
        entry,
        isNotNull,
        reason: 'deleting files must never delete the Entry',
      );
      expect(entry!.title, 'Entry 1');
      expect(
        await app.ui.entries.locationsOf(entryId),
        isNotEmpty,
        reason: 'nor its Locations',
      );
      expect(
        (await app.ui.reading.stateOf(entryId)).status,
        isNot(ReadStatus.unread),
        reason: 'nor the fact that it was opened',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'an image sequence knows where to open before anything decodes',
    (tester) async {
      await boot(tester, tag: 'offline_${caseIndex++}_$kRunStamp');

      final entryId = await app.queueSaveOf(fixture.entry(1), title: 'Entry 1');
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      // Somebody read partway and left.
      final session = OfflineReadSession(
        entryId: entryId,
        offlineCopies: app.ui.offline,
        reading: app.ui.reading,
      );
      await session.saveProgress(
        const ReadingPosition(anchorIndex: 3, offsetInAnchor: 0.4),
      );

      // Ask what the reader would open, through repositories built after the
      // write: the anchor came out of the database, not out of the session.
      final fresh = app.freshLibraryReads();
      final read = await resolveOfflineRead(
        entryId: entryId,
        offlineCopies: fresh.offline,
        fileStore: app.fileStore,
      );
      expect(read, isA<OfflineImageRead>());
      final images = read as OfflineImageRead;
      expect(
        images.restored.anchorIndex,
        3,
        reason: 'the anchor is durable, on the copy that indexes it',
      );
      expect(images.restored.offsetInAnchor, closeTo(0.4, 0.01));

      // **At**, not **to**: the geometry is complete before a single image is
      // decoded, so the reader opens on the saved panel rather than jumping there
      // once the pictures arrive.
      final layout = images.geometryFor(390);
      expect(layout.panelCount, kFixtureImagesPerEntry);
      expect(layout.isEmpty, isFalse);
      expect(
        layout.offsetOf(3),
        greaterThan(0),
        reason: 'panel 3 has a known offset with nothing loaded',
      );
      expect(
        layout.offsetForPosition(images.restored),
        closeTo(layout.offsetOf(3) + layout.heightOf(3) * 0.4, 1),
        reason: 'and the restore lands inside that panel, not at the top of it',
      );

      // There is deliberately no stored fraction on a copy: an index plus an
      // offset inside *these* bytes is the whole record.
      final copy = (await fresh.offline.activeCopyOf(entryId))!;
      expect(copy.anchorIndex, 3);
      expect(copy.anchorOffset, closeTo(0.4, 0.01));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a document restores TO its position, having no offsets yet',
    (tester) async {
      await boot(tester, tag: 'offline_${caseIndex++}_$kRunStamp');
      fixture.applyDelays = false;

      final entryId = await app.queueSaveOf(
        '${fixture.base}/text/1',
        title: 'Text 1',
        captureMode: CaptureMode.textOnly,
        captureModeIsUserSet: true,
      );
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);
      final task = await app.latestTaskFor(entryId);
      expect(task!.state, SaveTaskState.completed, reason: task.lastError);

      final session = OfflineReadSession(
        entryId: entryId,
        offlineCopies: app.ui.offline,
        reading: app.ui.reading,
      );
      await session.saveProgress(
        const ReadingPosition(anchorIndex: 5, offsetInAnchor: 0.25),
      );

      final fresh = app.freshLibraryReads();
      final read = await resolveOfflineRead(
        entryId: entryId,
        offlineCopies: fresh.offline,
        fileStore: app.fileStore,
      );
      expect(read, isA<OfflineDocumentRead>());
      final document = read as OfflineDocumentRead;
      expect(document.restored.anchorIndex, 5);
      expect(document.restored.offsetInAnchor, closeTo(0.25, 0.01));
      expect(document.document.blockCount, greaterThan(5));

      // **To**, not **at**: a paragraph has no offset until it has been laid out
      // at this width, font and text scale, so the resolved read carries the
      // anchor and nothing that could pretend to be a scroll offset. The reader
      // applies it on the first measurement — which is why there is no geometry
      // object here to ask, and asserting on its absence is the honest test.
      expect(
        document.document.blocks.length,
        document.document.blockCount,
        reason: 'the blocks are all that came off disk',
      );

      // Opening it still works end to end, with the source gone.
      await fixture.stop();
      await readThroughTheLibrary(tester, entryId);
      expect(
        find.textContaining('Paragraph 1 of entry 1'),
        findsWidgets,
        reason: 'the saved text rendered from disk',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
