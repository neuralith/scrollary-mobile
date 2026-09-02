/// The reader-area hold has to leave the page it is asking about on screen.
///
/// **The regression this pins.** The selection sheet was a fixed 420 high and
/// the running panel below it drew its full progress block, so on the Browser
/// the two of them plus the toolbar came to more than a phone has. The
/// WebView's `Expanded` resolved to **zero**: the app asked the user to tap
/// the Entry's images in a page it had stopped drawing, and there was no
/// gesture that could answer it. Measured at zero on a small phone, a current
/// phone and the largest one.
///
/// So the numbers here are the point of the file. A sheet that fits is not
/// the property — a page that is still there is.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/running_operation_panel.dart';
import 'package:web_reader/features/selection_overlay.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/save/selection_request.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';
import 'helpers/v2_harness.dart';

/// A phone, as the Browser sees one: the screen, and the insets the shell has
/// already taken out of the Column this measures.
typedef Phone = ({String name, Size size, double top, double bottom});

const _phones = <Phone>[
  (name: 'small', size: Size(375, 667), top: 20, bottom: 0),
  (name: 'current', size: Size(390, 844), top: 47, bottom: 34),
  (name: 'largest', size: Size(430, 932), top: 59, bottom: 34),
];

/// `BrowserToolbar`: 6 + `kBrowserActionHeight` + 6 + the 2px progress line.
const _toolbar = 54.0;

void main() {
  late V2Harness v2;
  late FakeBrowser browser;

  setUp(() {
    browser = FakeBrowser();
    v2 = V2Harness(browser: browser, fileStore: tempFileStore());
  });
  tearDown(() async {
    await v2.close();
    browser.dispose();
  });

  SelectionRequest readerAreaRequest() => SelectionRequest(
    kind: HintKind.readerArea,
    sourceUrl: 'https://reading.example.com/works/quiet-harbour/part-1',
    prompt: 'Select the reader area',
    // The sentence the engine's collapse guard now produces.
    reason:
        'The images this page ended with are far shorter than the content '
        'seen while scrolling — the tallest is 580px where 16000px was found',
  );

  /// `BrowserScreen`'s docked stack, in the order and with the constraints it
  /// builds them in: a toolbar, the WebView taking what is left, the hold
  /// docked under it, and the running panel under that.
  ///
  /// Built here rather than by pumping `BrowserScreen`, which embeds a real
  /// platform WebView a widget test cannot host — the same reason
  /// `browser_ui_test.dart` builds the Browser's surfaces directly. What is
  /// under test is the height budget, and every widget that consumes one is
  /// the real one.
  Widget dockedStack(Phone phone) => ProviderScope(
    overrides: [
      libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
      browserProvider.overrideWithValue(browser),
      v2ServicesProvider.overrideWithValue(v2.services),
      assistHoldProvider.overrideWithValue(v2.assist),
    ],
    child: MaterialApp(
      theme: appTheme(palette: AppPalette.light),
      home: Scaffold(
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                const SizedBox(height: _toolbar),
                Expanded(
                  child: Container(
                    key: const ValueKey('webViewSlot'),
                    color: const Color(0xFF000000),
                  ),
                ),
                AnimatedBuilder(
                  animation: v2.assist,
                  builder: (context, _) {
                    final request = v2.assist.pendingSelection;
                    if (request == null) return const SizedBox.shrink();
                    return RuleSelectionOverlay(
                      run: v2.assist,
                      request: request,
                      maxHeight: constraints.maxHeight * kAssistSheetShare,
                    );
                  },
                ),
                const RunningOperationPanel(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SizedBox(height: 44 + 12 + phone.bottom),
      ),
    ),
  );

  Future<double> pumpHolding(WidgetTester tester, Phone phone) async {
    tester.view.physicalSize = phone.size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(top: phone.top, bottom: phone.bottom);
    addTearDown(tester.view.reset);

    v2.runner.debugSetRunning(true);
    unawaited(v2.assist.ask(readerAreaRequest()));
    await tester.pumpWidget(dockedStack(phone));
    await tester.pump();
    return tester.getSize(find.byKey(const ValueKey('webViewSlot'))).height;
  }

  /// The Column's own height on this phone, which is what the budget is a
  /// fraction of: the screen less the top inset and the shell's tab bar.
  double columnHeight(Phone phone) =>
      phone.size.height - phone.top - (44 + 12 + phone.bottom);

  group('a reader-area hold on the Browser', () {
    for (final phone in _phones) {
      testWidgets('leaves the page on screen — ${phone.name} phone', (
        tester,
      ) async {
        final webView = await pumpHolding(tester, phone);
        final column = columnHeight(phone);

        expect(
          webView,
          greaterThan(0),
          reason:
              'the hold asks for a tap in the page; a page with no height '
              'cannot be tapped',
        );
        // An absolute floor rather than a share of the screen: what the user
        // has to do is find a content image and put a finger on it, and that
        // takes a window of a certain size, not a certain fraction. 200 is
        // roughly a third of the smallest phone's Column here, and the two
        // larger phones clear it by a wide margin.
        expect(
          webView,
          greaterThanOrEqualTo(200),
          reason: 'too little page left to find an Entry image in and tap it',
        );
        expect(webView, greaterThanOrEqualTo(column / 3));

        await tester.tap(find.text('Cancel run'));
        await tester.pump();
      });
    }

    testWidgets('folds the running panel to its holding line', (tester) async {
      await pumpHolding(tester, _phones.first);

      expect(
        find.textContaining('offline copy'),
        findsNothing,
        reason:
            'the full panel describes motion that has stopped, and it was '
            'taking the room the page needed',
      );
      expect(
        find.byKey(const ValueKey('panelStopDownload')),
        findsOneWidget,
        reason:
            'the only stop on this screen stays — Cancel run ends the hold, '
            'not the download',
      );

      await tester.tap(find.text('Cancel run'));
      await tester.pump();
    });

    testWidgets('keeps every action reachable without scrolling the sheet', (
      tester,
    ) async {
      // The smallest phone gives the sheet its smallest budget, which is
      // where an unpinned action row disappeared below the fold.
      await pumpHolding(tester, _phones.first);

      final sheet = tester.getRect(find.byType(RuleSelectionOverlay));
      for (final action in const [
        'Use this area',
        'Retry auto',
        'Cancel run',
      ]) {
        final rect = tester.getRect(find.text(action));
        expect(
          sheet.contains(rect.center),
          isTrue,
          reason: '"$action" is drawn outside the sheet that holds it',
        );
      }

      await tester.tap(find.text('Cancel run'));
      await tester.pump();
      expect(v2.assist.pendingSelection, isNull);
    });
  });

  group('the sheet honours the budget it is given', () {
    testWidgets('never draws taller than the caller allows', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      unawaited(v2.assist.ask(readerAreaRequest()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libui.libraryUiServicesProvider.overrideWithValue(v2.ui),
            browserProvider.overrideWithValue(browser),
            v2ServicesProvider.overrideWithValue(v2.services),
          ],
          child: MaterialApp(
            theme: appTheme(palette: AppPalette.light),
            home: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  RuleSelectionOverlay(
                    run: v2.assist,
                    request: v2.assist.pendingSelection!,
                    maxHeight: 180,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(RuleSelectionOverlay)).height,
        lessThanOrEqualTo(180),
      );
      // Still answerable at that height: the body scrolls, the actions do not.
      expect(find.text('Use this area'), findsOneWidget);
      expect(find.text('Cancel run'), findsOneWidget);

      await tester.tap(find.text('Cancel run'));
      await tester.pump();
    });
  });
}
