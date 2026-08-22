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
import 'package:web_reader/save/queue_task.dart';
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

    screenTest('offers Save for a page with nothing queued', (tester) async {
      await openPanel(tester);

      await pumpUntil(tester, find.byKey(const ValueKey('v2SaveButton')));
      expect(find.byKey(const ValueKey('v2StartButton')), findsNothing);
      expect(find.text('Not in your library yet.'), findsOneWidget);
    });

    screenTest('offers Start, and no longer Save, once a task is waiting', (
      tester,
    ) async {
      await openPanel(tester);
      await pumpUntil(tester, find.byKey(const ValueKey('v2SaveButton')));

      await tapAndPump(tester, find.byKey(const ValueKey('v2SaveButton')));

      await pumpUntil(tester, find.byKey(const ValueKey('v2StartButton')));
      expect(find.byKey(const ValueKey('v2SaveButton')), findsNothing);
      expect(find.text('Queued — waiting for Start.'), findsOneWidget);
      expect((await theOnlyTask()).state, SaveTaskState.queued);
    });
  });
}
