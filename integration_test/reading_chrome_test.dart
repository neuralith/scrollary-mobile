// Reading a website with the Browser's chrome hidden, on a real WebView.
//
//   flutter test integration_test/reading_chrome_test.dart -d <device-id>
//
// The widget tests pin what the controls draw. This pins the thing only a real
// WebView can answer: taking the toolbar and the shell's tab bar out of the
// tree resizes a live platform view, and the page has to survive it — same
// document, same address, more of it visible — and the one control left has to
// bring both halves of the chrome back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/features/browser_toolbar.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  tearDown(() => app.shutdown());

  final hide = find.byKey(const ValueKey('browserHideChrome'));
  final show = find.byKey(const ValueKey('browserShowChrome'));

  testWidgets(
    'hiding the chrome gives the page the screen, and gives it back',
    (tester) async {
      app = V2App(tag: 'chrome_${caseIndex++}_$kRunStamp');
      await app.boot(tester);
      await showBrowser(tester);
      await openPage(tester, app, fixture.entry(1));

      // Read partway down, which is what someone hiding the chrome is doing.
      await app.browser.scrollTo(1200);
      await pumpFor(tester, const Duration(seconds: 1));

      final before = await app.browser.probe(withSignals: false);
      expect(before.viewportHeight, greaterThan(0));
      expect(before.scrollY, greaterThan(0));
      expect(find.byType(BrowserToolbar), findsOneWidget);
      expect(browserTab, findsOneWidget);

      // Hide.
      expect(hide, findsOneWidget);
      await tester.tap(hide, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 2));

      expect(find.byType(BrowserToolbar), findsNothing);
      expect(browserTab, findsNothing, reason: 'the tab bar goes too');
      expect(show, findsOneWidget, reason: 'the way back is always drawn');

      final hidden = await app.browser.probe(withSignals: false);
      expect(
        hidden.viewportHeight,
        greaterThan(before.viewportHeight),
        reason: 'the page is what gained the space',
      );
      expect(hidden.url, before.url, reason: 'nothing navigated');
      expect(
        hidden.scrollY,
        closeTo(before.scrollY, before.viewportHeight),
        reason: 'the reader keeps their place across the resize',
      );
      expect(hidden.documentHeight, greaterThan(0));
      expect(app.browser.currentUrl, contains('/entry/1'));

      // And back.
      await tester.tap(show, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 2));

      expect(find.byType(BrowserToolbar), findsOneWidget);
      expect(browserTab, findsOneWidget);
      expect(hide, findsOneWidget);

      final restored = await app.browser.probe(withSignals: false);
      expect(restored.url, before.url);
      expect(restored.viewportHeight, before.viewportHeight);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'work the user can watch brings the chrome back on its own',
    (tester) async {
      app = V2App(tag: 'chrome_${caseIndex++}_$kRunStamp');
      await app.boot(tester);
      await showBrowser(tester);
      await openPage(tester, app, fixture.entry(1));

      await tester.tap(hide, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.byType(BrowserToolbar), findsNothing);
      expect(browserTab, findsNothing);

      // The runner's own test hook, which is what the shell listens to: this
      // pins the shell's reaction, not the engine that would raise the flag.
      app.runner.debugSetRunning(true);
      await pumpFor(tester, const Duration(seconds: 2));

      expect(
        find.byType(BrowserToolbar),
        findsOneWidget,
        reason: 'a run brings the toolbar back',
      );
      expect(browserTab, findsOneWidget, reason: 'and the tab bar with it');
      expect(show, findsNothing);
      expect(
        hide,
        findsNothing,
        reason: 'and it cannot be taken away again while the run runs',
      );

      // Idle again: reading with the chrome away is on offer, but only
      // because the user asks for it a second time.
      app.runner.debugSetRunning(false);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.byType(BrowserToolbar), findsOneWidget);
      expect(hide, findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
