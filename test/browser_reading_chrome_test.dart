import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/browser_screen.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/v2_harness.dart';

/// The Browser's floating controls over a page being read: the save action
/// with no word beside it, and the eye that takes the chrome away.
///
/// Built directly, like every other test of a Browser surface — the screen
/// around them embeds a real platform WebView a widget test cannot host.
void main() {
  late V2Harness v2;
  late BrowserController browser;

  setUp(() {
    browser = BrowserController();
    v2 = V2Harness(browser: browser, fileStore: tempFileStore());
  });
  tearDown(() async {
    await v2.close();
    browser.dispose();
  });

  var toggles = 0;
  var saves = 0;
  var libraryViews = 0;
  setUp(() {
    toggles = 0;
    saves = 0;
    libraryViews = 0;
  });

  Widget host({
    required bool chromeHidden,
    bool canHideChrome = true,
    bool captureRestricted = false,
    bool pageIsQueued = false,
  }) => MaterialApp(
    theme: appTheme(),
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
          BrowserSaveActions(
            runner: v2.runner,
            sourceCheck: v2.check,
            pageStatus: null,
            pageIsQueued: pageIsQueued,
            captureRestricted: captureRestricted,
            waitingSaves: 0,
            chromeHidden: chromeHidden,
            canHideChrome: canHideChrome,
            onToggleChrome: () => toggles++,
            onSave: () => saves++,
            onPageActions: () {},
            onViewLibrary: () => libraryViews++,
          ),
        ],
      ),
    ),
  );

  group('the save action', () {
    testWidgets('is the icon alone — no word beside it', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));

      expect(find.byKey(const ValueKey('browserSaveAction')), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('still says what it is, in words, for anyone who cannot see '
        'the glyph', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('browserSaveAction')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Save this page');
      expect(
        tester.widget<Icon>(find.byIcon(Icons.download)).semanticLabel,
        'Save this page',
      );
    });

    testWidgets('keeps a full touch target', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));

      final size = tester.getSize(
        find.byKey(const ValueKey('browserSaveAction')),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('opens the save flow when tapped', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));
      await tester.tap(find.byKey(const ValueKey('browserSaveAction')));
      expect(saves, 1);
    });

    testWidgets('on a page already waiting to download, says the save it '
        'performs — never a screen it does not open', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false, pageIsQueued: true));

      final save = find.byKey(const ValueKey('browserSaveAction'));
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: save, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, 'Waiting to download — save this page');
      expect(
        tester.widget<Icon>(find.byIcon(Icons.schedule)).semanticLabel,
        'Waiting to download — save this page',
      );

      // The words and the tap agree: this one saves, and nothing about it
      // leads to the library.
      await tester.tap(save);
      expect(saves, 1);
      expect(libraryViews, 0);
    });
  });

  group('while a run runs', () {
    testWidgets('the save action is not drawn at all', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));
      expect(find.byKey(const ValueKey('browserSaveAction')), findsOneWidget);

      v2.runner.debugSetRunning(true);
      await tester.pump();

      // Gone, not restyled: a download-looking control in the save's own
      // place is what sent people to the library from a page they were
      // watching.
      expect(find.byKey(const ValueKey('browserSaveAction')), findsNothing);
      expect(find.byIcon(Icons.downloading), findsNothing);
      expect(find.byIcon(Icons.download), findsNothing);

      // And nothing else took the corner: no control in this group navigates
      // anywhere while the run runs.
      expect(find.byKey(const ValueKey('browserPageActions')), findsNothing);
      expect(find.byKey(const ValueKey('browserHideChrome')), findsNothing);
      expect(libraryViews, 0);

      v2.runner.debugSetRunning(false);
    });

    testWidgets('a source check takes it away for the same reason', (
      tester,
    ) async {
      await tester.pumpWidget(host(chromeHidden: false));

      v2.check.debugSetRunning(true);
      await tester.pump();

      expect(find.byKey(const ValueKey('browserSaveAction')), findsNothing);
      expect(libraryViews, 0);

      v2.check.debugSetRunning(false);
    });

    testWidgets('a queued page loses it too, and gets it back as the save '
        'when the run ends', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false, pageIsQueued: true));
      v2.runner.debugSetRunning(true);
      await tester.pump();
      expect(find.byKey(const ValueKey('browserSaveAction')), findsNothing);

      v2.runner.debugSetRunning(false);
      await tester.pump();

      final save = find.byKey(const ValueKey('browserSaveAction'));
      expect(save, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: save, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, 'Waiting to download — save this page');
      await tester.tap(save);
      expect(saves, 1);
      expect(libraryViews, 0);
    });
  });

  group('hiding the chrome', () {
    testWidgets('is offered beside the page actions', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false));

      final hide = find.byKey(const ValueKey('browserHideChrome'));
      expect(hide, findsOneWidget);
      await tester.tap(hide);
      expect(toggles, 1);
    });

    testWidgets('is not offered where it cannot be honoured', (tester) async {
      await tester.pumpWidget(host(chromeHidden: false, canHideChrome: false));

      expect(find.byKey(const ValueKey('browserHideChrome')), findsNothing);
      expect(find.byKey(const ValueKey('browserPageActions')), findsOneWidget);
    });

    testWidgets('leaves exactly one control on the page, and it brings the '
        'chrome back', (tester) async {
      await tester.pumpWidget(host(chromeHidden: true));

      expect(find.byKey(const ValueKey('browserSaveAction')), findsNothing);
      expect(find.byKey(const ValueKey('browserPageActions')), findsNothing);
      expect(find.byKey(const ValueKey('browserHideChrome')), findsNothing);

      final show = find.byKey(const ValueKey('browserShowChrome'));
      expect(show, findsOneWidget);
      await tester.tap(show);
      expect(toggles, 1);
    });

    testWidgets('keeps the way back while an operation is running', (
      tester,
    ) async {
      v2.runner.debugSetRunning(true);
      await tester.pumpWidget(host(chromeHidden: true));

      expect(find.byKey(const ValueKey('browserShowChrome')), findsOneWidget);
      v2.runner.debugSetRunning(false);
    });

    testWidgets('keeps the way back on a page that cannot be saved from', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(chromeHidden: true, captureRestricted: true),
      );

      expect(find.byKey(const ValueKey('browserShowChrome')), findsOneWidget);
      expect(find.byKey(const ValueKey('browserSaveAction')), findsNothing);
    });
  });
}
