/// What a Collection is normally captured as, honoured wherever capture starts
/// (V2-D58).
///
/// **The regression this pins.** V1 resolved the fallback inside its run —
/// `requestedCaptureMode ?? the collection's preferred mode` — so a Collection
/// kept as *Images only* stayed that way whatever asked for the save. V2 moved
/// the read into the Browser save sheet's own widget state, and every path
/// that never opens that sheet lost it: *Download for offline*, the bar after
/// a check, the reader's repair, a request from another device.
///
/// So the property under test is deliberately **about the row, not about a
/// screen**: a queue row that carries no explicit mode is what all of those
/// paths write, and this file proves that such a row captures at the
/// Collection's answer. Every one of them is covered by that, including the
/// next one somebody adds.
///
/// What it must not become is a second way of saying "the user chose this":
/// `captureModeIsUserSet` is untouched, an explicit mode still wins, a
/// standalone Entry gets nothing, and the page still has the last word through
/// `CaptureCapabilities.resolve`.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/queue_task.dart';

import 'support/capture_harness.dart';

void main() {
  late CaptureHarness h;

  setUp(() => h = CaptureHarness());
  tearDown(() => h.close());

  /// Capture the seeded Entry exactly as the queue runner does: the row's own
  /// values, and nothing the caller invented on the way.
  Future<CaptureMode?> captureRow(SaveTask task) async {
    final source = FakePageCaptureSource.images();
    final result = await h
        .captureWith(source)
        .capture(
          entryId: task.entryId,
          locationUrl: task.locationUrl,
          locationId: task.locationId,
          captureMode: task.captureMode,
          captureModeIsUserSet: task.captureModeIsUserSet,
        );
    expect(result.status, EntryCaptureStatus.captured);
    return source.modes.single;
  }

  /// A row of the shape every non-Browser path writes: an Entry, its address,
  /// and **no capture mode at all**.
  Future<SaveTask> rowWithNoMode({
    required String entryId,
    required String locationId,
    required String url,
  }) async {
    final result = await h.queue.enqueue(
      entryId: entryId,
      locationId: locationId,
      locationUrl: url,
    );
    final task = result.task!;
    expect(
      task.captureMode,
      isNull,
      reason: 'the preference is resolved at capture, never copied onto a row',
    );
    return task;
  }

  group('a row that names no mode', () {
    test('captures at the collection\'s remembered answer', () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );

      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      expect(await captureRow(task), CaptureMode.imageSequence);
    });

    test('and at nothing when the collection has never said', () async {
      final seeded = await h.repos.seedLibrary();
      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      expect(
        await captureRow(task),
        isNull,
        reason: 'null reaches the engine, which decides from the settled page',
      );
    });

    test('*Ask each time* is a real answer, not an absent one', () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );
      // The Collection menu's fourth row.
      await h.preferences.forget(seeded.collection.id);

      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      expect(await captureRow(task), isNull);
    });

    test('*Ask each time* proposes nothing at the seam either', () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.askEachTime(seeded.collection.id);

      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      expect(
        await captureRow(task),
        isNull,
        reason:
            'stored as an answer, and read as no mode — the engine seam '
            'never learns there is a difference',
      );
    });

    test('a standalone entry is given no collection to inherit from', () async {
      final seeded = await h.repos.seedLibrary();
      // The library's other Collection does have a preference, so what is
      // asserted below is that *this Entry* has none to inherit — not that
      // there was nothing to inherit anywhere.
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );

      final root = await h.repos.folders.ensureRoot();
      final (entry, violation) = await h.repos.entries.createStandalone(
        folderId: root.id,
        title: 'On its own',
      );
      expect(violation, isNull);
      final (location, lv) = await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: 'https://reading.example.com/loose/one',
        urlKey: 'https://reading.example.com/loose/one',
      );
      expect(lv, isNull);

      final task = await rowWithNoMode(
        entryId: entry.id,
        locationId: location!.id,
        url: location.url,
      );

      expect(
        await captureRow(task),
        isNull,
        reason: 'no collection, so no standing answer to inherit',
      );
    });
  });

  group('precedence', () {
    test('an explicit mode on the save wins over the preference', () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );

      // What the Browser's sheet writes when the user answered on the page.
      final result = await h.queue.enqueue(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        locationUrl: seeded.location.url,
        captureMode: CaptureMode.textOnly,
        captureModeIsUserSet: true,
      );

      expect(await captureRow(result.task!), CaptureMode.textOnly);
    });

    test('a remembered mode is not a person having chosen it', () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );
      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      final source = FakePageCaptureSource.images();
      await h
          .captureWith(source)
          .capture(
            entryId: task.entryId,
            locationUrl: task.locationUrl,
            locationId: task.locationId,
            captureMode: task.captureMode,
            captureModeIsUserSet: task.captureModeIsUserSet,
          );

      final manifest = await h.fileStore.readManifest(
        (await h.repos.offline.activeCopyOf(task.entryId))!.contentPath,
      );
      expect(
        manifest!.captureModeIsUserSet,
        isNull,
        reason:
            'the field is omitted unless a person chose the mode — a standing '
            'answer about the work is not that',
      );
    });
  });

  test(
    'the preference that counts is the one in force when it starts',
    () async {
      final seeded = await h.repos.seedLibrary();
      await h.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );

      // Queued now…
      final task = await rowWithNoMode(
        entryId: seeded.entry.id,
        locationId: seeded.location.id,
        url: seeded.location.url,
      );

      // …and the user changes their mind while it waits for Start. Resolving at
      // enqueue time would have frozen the old answer onto the row.
      await h.preferences.remember(seeded.collection.id, CaptureMode.textOnly);

      expect(await captureRow(task), CaptureMode.textOnly);
    },
  );

  test('the page still has the last word on an impossible preference', () {
    // The seam proposes; `CaptureCapabilities.resolve` disposes. Asserted on
    // the resolver itself with the mode the seam would hand it, because what
    // is being pinned is that the preference arrives as a *request* — the same
    // input an explicit choice arrives as — and not as an instruction that
    // bypasses the page.
    const probe = PageProbe(
      url: 'https://reading.example.com/serial-alpha/part-101',
      title: 'Part 101',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      viewportWidth: 400,
      atBottom: false,
    );
    final capabilities = detectCaptureCapabilities(probe);
    final resolution = capabilities.resolve(CaptureMode.textOnly);

    expect(resolution.honoured, isFalse);
    expect(resolution.requested, CaptureMode.textOnly);
    expect(resolution.mode, isNot(CaptureMode.textOnly));
    expect(resolution.explanation, contains('not possible here'));
  });

  test('it survives the database being closed and opened again', () async {
    // A real round trip, not a seeded read: the preference is written through
    // one database handle and read by a capture running over another one over
    // the same file. Nothing in between re-states it.
    final dir = Directory.systemTemp.createTempSync('scrollary_pref_reopen');
    final file = File('${dir.path}/library.sqlite');
    try {
      final first = CaptureHarness(executor: NativeDatabase(file));
      final seeded = await first.repos.seedLibrary();
      final entryId = seeded.entry.id;
      final locationId = seeded.location.id;
      final url = seeded.location.url;
      await first.preferences.remember(
        seeded.collection.id,
        CaptureMode.imageSequence,
      );
      await first.close();

      final second = CaptureHarness(executor: NativeDatabase(file));
      try {
        final enqueued = await second.queue.enqueue(
          entryId: entryId,
          locationId: locationId,
          locationUrl: url,
        );
        final source = FakePageCaptureSource.images();
        final result = await second
            .captureWith(source)
            .capture(
              entryId: entryId,
              locationUrl: url,
              locationId: locationId,
              captureMode: enqueued.task!.captureMode,
            );

        expect(result.status, EntryCaptureStatus.captured);
        expect(source.modes.single, CaptureMode.imageSequence);
      } finally {
        await second.close();
      }
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
