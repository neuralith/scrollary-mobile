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
  setUp(() {
    toggles = 0;
    saves = 0;
  });

  Widget host({
    required bool chromeHidden,
    bool canHideChrome = true,
    bool captureRestricted = false,
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
            pageIsQueued: false,
            captureRestricted: captureRestricted,
            waitingSaves: 0,
            chromeHidden: chromeHidden,
            canHideChrome: canHideChrome,
            onToggleChrome: () => toggles++,
            onSave: () => saves++,
            onPageActions: () {},
            onViewLibrary: () {},
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
