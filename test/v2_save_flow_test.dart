/// The Browser's save flow over the V2 library.
///
/// Four properties, and each of them is a rule from CLAUDE.md rather than an
/// implementation detail:
///
/// * **On a restricted host the control is absent**, and the refusal is asked
///   for again underneath — `v2SavePage` returns the policy's one sentence and
///   writes no row, so no hidden button is ever the enforcement.
/// * **Saving a page the library does not know promotes it**, through the same
///   path history uses, and leaves exactly one task *waiting*. Nothing runs
///   without an explicit Start.
/// * **The chosen mode travels onto the row**, together with whether a person
///   or the page chose it. Null is a real answer — "decide from the settled
///   page" — and must not be defaulted here.
/// * **The panel offers Save or Start, never both**: what is already queued
///   cannot be queued again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/selection_request.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';
import 'library_ui/support/ui_harness.dart';
import 'save_v2/support/capture_harness.dart' show restrictedUrl;

/// An ordinary page on a reserved example host.
const _pageUrl = 'https://reading.example.com/notes/the-first-one';
const _pageTitle = 'The first one';

void main() {
  late UiHarness h;
  late FakeBrowser browser;

  setUp(() {
    h = UiHarness();
    browser = FakeBrowser();
  });
  tearDown(() => h.close());

  /// A page the bridge could read, carrying nothing in particular. Enough for
  /// detection to run for real, which is what the panel does before it offers
  /// anything.
  PageProbe probeOf(String url) => PageProbe(
    url: url,
    title: _pageTitle,
    readyState: 'complete',
    documentHeight: 2000,
    viewportHeight: 800,
    viewportWidth: 400,
    atBottom: false,
  );

  Widget app(Widget home) => ProviderScope(
    overrides: [
      libraryUiServicesProvider.overrideWithValue(h.services),
      browserProvider.overrideWithValue(browser),
      saveQueueStarterProvider.overrideWithValue(h.starter),
    ],
    child: MaterialApp(
      theme: appTheme(palette: AppPalette.light),
      home: home,
    ),
  );

  /// The flow takes a [WidgetRef], so the test stands up the smallest tree
  /// that can hold one.
  Future<WidgetRef> refFor(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return captured;
  }

  Future<SaveTask> theOnlyTask() async {
    final tasks = await h.queue.all();
    expect(tasks, hasLength(1));
    return tasks.single;
  }

  group('the save control', () {
    test('is offered for an ordinary page and absent on a restricted one', () {
      expect(v2SaveAvailable(_pageUrl), isTrue);
      // Absent, not disabled: the caller asks before it builds the control.
      expect(v2SaveAvailable(restrictedUrl('/notes/one')), isFalse);
    });

    test('is absent for an address that is not a web page', () {
      expect(v2SaveAvailable('about:blank'), isFalse);
      expect(v2SaveAvailable('file:///etc/hosts'), isFalse);
    });
  });

  group('saving a page', () {
    screenTest('refuses a restricted address with the policy sentence, and '
        'writes no row', (tester) async {
      final ref = await refFor(tester);
      final url = restrictedUrl('/notes/one');

      final message = await v2SavePage(ref, url: url, pageTitle: _pageTitle);

      expect(message, kCaptureRestrictedMessage);
      // Nothing to start, so nothing recorded — and nothing to delete later.
      expect(await h.queue.all(), isEmpty);
      expect((await v2PageStatusFor(ref, url)).entryId, isNull);
    });

    screenTest('promotes a page the library does not know, and leaves one '
        'task waiting', (tester) async {
      final ref = await refFor(tester);

      final message = await v2SavePage(
        ref,
        url: _pageUrl,
        pageTitle: _pageTitle,
      );

      expect(message, isNull);
      final status = await v2PageStatusFor(ref, _pageUrl);
      expect(status.result, isA<RecognisedLocation>());
      expect(status.entryId, isNotNull);

      final task = await theOnlyTask();
      expect(task.entryId, status.entryId);
      expect(task.locationUrl, _pageUrl);
      expect(task.state, SaveTaskState.queued);
      // Nothing captures until the user's explicit Start.
      expect(await h.queue.eligible(), isEmpty);
    });

    screenTest('asking a second time is the same request, not a second row', (
      tester,
    ) async {
      final ref = await refFor(tester);
      await v2SavePage(ref, url: _pageUrl, pageTitle: _pageTitle);
      final first = await theOnlyTask();

      final message = await v2SavePage(
        ref,
        url: _pageUrl,
        pageTitle: _pageTitle,
      );

      expect(message, isNull);
      expect((await theOnlyTask()).id, first.id);
    });

    screenTest('carries the chosen mode, and that a person chose it, onto the '
        'row', (tester) async {
      final ref = await refFor(tester);

      await v2SavePage(
        ref,
        url: _pageUrl,
        pageTitle: _pageTitle,
        captureMode: CaptureMode.textAndImages,
        captureModeIsUserSet: true,
      );

      final task = await theOnlyTask();
      expect(task.captureMode, CaptureMode.textAndImages);
      expect(task.captureModeIsUserSet, isTrue);
    });

    screenTest('stores no mode when nothing was chosen, rather than a default', (
      tester,
    ) async {
      final ref = await refFor(tester);

      await v2SavePage(ref, url: _pageUrl, pageTitle: _pageTitle);

      final task = await theOnlyTask();
      // Null means "decide from the settled page" — never a quiet answer about
      // what to take off it.
      expect(task.captureMode, isNull);
      expect(task.captureModeIsUserSet, isFalse);
    });
  });

  group('a page on a Source the library already holds', () {
    screenTest('joins the entry that Collection already has at that '
        'number', (tester) async {
      final ref = await refFor(tester);
      final root = await h.folders.ensureRoot();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      // The Source key is the one the address itself yields, so the page the
      // user is on lands on this Source rather than looking like a new site.
      final source = await h.source(
        collection.id,
        pathKey: RecognitionKeys.of(
          'https://reading.example.com/notes/12',
        ).pathKey!,
      );
      // The Collection already holds part 12, found by reading the Source's
      // own listing.
      final held = await h.entryIn(
        collection.id,
        title: 'Part 12',
        ordinal: 12,
      );
      await h.location(
        held.id,
        'https://reading.example.com/notes/12',
        sourceId: source.id,
      );

      // The user is on the same part, at a second address on that Source.
      const other = 'https://reading.example.com/notes/part-12-mirror';
      final message = await v2SavePage(ref, url: other, pageTitle: 'Part 12');

      expect(message, isNull);
      // One Entry, two addresses — not a second unplaced Entry that could
      // never be placed at 12 afterwards (I8).
      expect(await h.entries.entriesOf(collection.id), hasLength(1));
      final locations = await h.entries.locationsOf(held.id);
      expect(locations, hasLength(2));
      expect(locations.every((l) => l.sourceId == source.id), isTrue);
      expect((await v2PageStatusFor(ref, other)).entryId, held.id);
    });

    screenTest('a part the Collection does not hold is added, unplaced when '
        'nothing numbers it', (tester) async {
      final ref = await refFor(tester);
      final root = await h.folders.ensureRoot();
      final collection = await h.collection('Serial Alpha', folderId: root.id);
      await h.source(
        collection.id,
        pathKey: RecognitionKeys.of(
          'https://reading.example.com/notes/12',
        ).pathKey!,
      );

      const unnumbered = 'https://reading.example.com/notes/ep-extra';
      final message = await v2SavePage(
        ref,
        url: unnumbered,
        pageTitle: 'Afterword',
      );

      expect(message, isNull);
      final entries = await h.entries.entriesOf(collection.id);
      expect(entries, hasLength(1));
      expect(entries.single.ordinal, isNull);
      expect(entries.single.placement, 'unplaced');
    });
  });

  group('what the sheet knows about the page', () {
    screenTest('reports that this device already holds a copy', (tester) async {
      final ref = await refFor(tester);
      await v2SavePage(ref, url: _pageUrl, pageTitle: _pageTitle);
      final entryId = (await v2PageStatusFor(ref, _pageUrl)).entryId!;
      expect((await v2PageStatusFor(ref, _pageUrl)).hasCopy, isFalse);

      await h.copyFor(entryId);

      expect((await v2PageStatusFor(ref, _pageUrl)).hasCopy, isTrue);
    });

    screenTest('reports the open task for a page already queued', (
      tester,
    ) async {
      final ref = await refFor(tester);
      expect((await v2PageStatusFor(ref, _pageUrl)).task, isNull);

      await v2SavePage(ref, url: _pageUrl, pageTitle: _pageTitle);

      final status = await v2PageStatusFor(ref, _pageUrl);
      expect(status.task, isNotNull);
      expect(status.task!.id, (await theOnlyTask()).id);
      expect(status.task!.state, SaveTaskState.queued);
    });
  });

  group('the save panel', () {
    Future<void> openPanel(WidgetTester tester) async {
      browser
        ..setUrl(_pageUrl)
        ..addPage(_pageUrl, probeOf(_pageUrl));
      await tester.pumpWidget(
        app(const V2SavePanel(url: _pageUrl, pageTitle: _pageTitle)),
      );
    }

    // What each branch of the sheet offers is
    // `test/library_ui/save_panel_test.dart`; what is here is the pair of
    // facts this file has always covered — an unknown page is asked about
    // rather than filed, and a row already waiting offers the Start instead
    // of a second request.
    screenTest('asks about a page the library does not know', (tester) async {
      await openPanel(tester);

      await pumpUntil(tester, find.byKey(const ValueKey('v2AddCollection')));
      expect(find.byKey(const ValueKey('v2StartButton')), findsNothing);
      expect(find.text('Not in your library yet.'), findsOneWidget);
    });

    screenTest('offers Start, and no second request, once a task is waiting', (
      tester,
    ) async {
      final ref = await refFor(tester);
      await v2SavePage(ref, url: _pageUrl, pageTitle: _pageTitle);
      await openPanel(tester);

      await pumpUntil(tester, find.byKey(const ValueKey('v2StartButton')));
      expect(
        find.byKey(const ValueKey('saveScopeThisEntry')),
        findsNothing,
        reason: 'a row already waiting is not asked for again',
      );
      expect(find.text('Queued — waiting for Start.'), findsOneWidget);
      expect((await theOnlyTask()).state, SaveTaskState.queued);
    });
  });

  group('the reading-area hold', () {
    /// What a capture that could not pick the entry's images out of the page
    /// asks for. Built here rather than run through a capture, because what is
    /// under test is the presentation: the sheet either holds or it does not.
    SelectionRequest requestFor(String url) => SelectionRequest(
      kind: HintKind.readerArea,
      sourceUrl: url,
      prompt: 'Select the reader area',
      reason: 'automatic extraction found too little',
    );

    Future<V2AssistController> openPanel(WidgetTester tester) async {
      browser
        ..setUrl(_pageUrl)
        ..addPage(_pageUrl, probeOf(_pageUrl));
      await tester.pumpWidget(
        app(const V2SavePanel(url: _pageUrl, pageTitle: _pageTitle)),
      );
      await pumpUntil(tester, find.byKey(const ValueKey('v2AddCollection')));
      return ProviderScope.containerOf(
        tester.element(find.byType(V2SavePanel)),
      ).read(v2AssistProvider);
    }

    screenTest('is absent while nothing is holding', (tester) async {
      await openPanel(tester);

      expect(find.text('Show the app where the content is'), findsNothing);
      expect(find.byKey(const ValueKey('v2AddCollection')), findsOneWidget);
    });

    screenTest('takes over the sheet exactly while a capture holds', (
      tester,
    ) async {
      final assist = await openPanel(tester);

      unawaited(assist.ask(requestFor(_pageUrl)));
      await tester.pump();

      expect(find.text('Show the app where the content is'), findsOneWidget);
      expect(
        find.textContaining('automatic extraction found too little'),
        findsOneWidget,
        reason: 'the user is told what failed, not asked to tap blindly',
      );
      expect(
        find.byKey(const ValueKey('v2AddCollection')),
        findsNothing,
        reason: 'one slot: the hold replaces the sheet it interrupted',
      );

      await tapAndPump(tester, find.text('Cancel run'));

      expect(find.text('Show the app where the content is'), findsNothing);
      expect(find.byKey(const ValueKey('v2AddCollection')), findsOneWidget);
      expect(assist.pendingSelection, isNull);
    });

    screenTest('offers the narrowest scope first, and teaches nothing until '
        'something is tapped', (tester) async {
      final assist = await openPanel(tester);

      unawaited(assist.ask(requestFor(_pageUrl)));
      await tester.pump();

      expect(find.text('This collection on this host'), findsOneWidget);
      expect(
        find.textContaining('Nothing selected yet'),
        findsOneWidget,
        reason: 'a rule exists only because a person tapped an element',
      );
      expect(await h.db.select(h.db.pageHints).get(), isEmpty);

      await assist.cancelSelection();
      await tester.pump();
    });
  });
}
