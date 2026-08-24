// Architecture gate: does a *painted but fully covered* platform view keep
// rendering, scrolling and running JavaScript?
//
//   flutter test integration_test/occlusion_gate_test.dart -d <device-id>
//
// This is an experiment, not a product test. It exists to answer one binary
// question, it is referenced by docs/FOREGROUND_MULTITASKING.md §3 as the
// measured baseline, and its numbers are the reason the always-painted
// architecture was chosen at all. It is re-run against V2 because the premise
// belongs to the *compositing*, not to the engine that was on top of it — but
// the engine did change, so the numbers have to be taken again with the engine
// that ships.
//
// Three arms over the same real WebView, the same fixture entry, and the same
// production capture pipeline:
//
//   painted    — the WebView is the only thing on screen (the Browser tab)
//   covered    — the WebView is painted, an opaque layer is drawn over all of
//                it (what a Reader route does above a root-hosted WebView)
//   unpainted  — the WebView is laid out but not painted, via IndexedStack
//                (what the shell did before the always-painted change)
//
// Each arm records viewport height, scroll advance, requestAnimationFrame tick
// rate, document.visibilityState, and the outcome of a real one-Entry capture.
// The fixture entry loads four of its six panels through an IntersectionObserver
// with a 400ms delay, so a capture that stores six proves viewport, scrolling,
// timers, JavaScript, IntersectionObserver and lazy loading all at once.
//
// **What changed for V2, and what deliberately did not.**
//
// * The capture is `EntryCaptureService` over `SaveEnginePageCaptureSource` —
//   the production V2 pipeline — instead of V1's `SaveRunController`. Same
//   engine underneath; the ported internals are frozen.
// * `BrowserController.surfaceIsPainted` is set per arm. That is not a
//   convenience: **it is the invariant under test.** §3.1 measured that no
//   page-side signal discriminates portably — an unpainted WebView reports a
//   full viewport on both platforms and calls itself `visible` on Android — so
//   the app is the authority, and the app is what this harness stands in for.
//   Setting it is what makes the `unpainted` arm a control rather than a
//   second `painted` arm that happens to be invisible.
//
// Expected, if the always-painted architecture is viable: `painted` and
// `covered` agree on every number that matters and both store six images;
// `unpainted` holds at `waitingForBrowser` and stores nothing.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/save_engine.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/storage/file_store.dart';

import 'support/v2_harness.dart';

/// How the WebView is composited for one arm of the experiment.
enum SurfaceArm {
  /// Nothing above it.
  painted,

  /// Painted, with an opaque full-screen layer drawn over it.
  covered,

  /// Laid out but not painted.
  unpainted,
}

/// One arm's measurements.
class ArmReading {
  ArmReading(this.arm);

  final SurfaceArm arm;
  int viewportHeight = -1;
  int documentHeight = -1;
  int scrollBefore = -1;
  int scrollAfter = -1;
  int rafTicks = -1;
  String visibility = '?';
  String captureStatus = '?';
  bool heldForBrowser = false;
  int storedImages = -1;

  @override
  String toString() =>
      '[gate] ${arm.name.padRight(9)} '
      'viewport=$viewportHeight doc=$documentHeight '
      'scroll=$scrollBefore->$scrollAfter '
      'raf/s=$rafTicks visibility=$visibility '
      'capture=$captureStatus held=$heldForBrowser images=$storedImages';
}

/// Hosts exactly one [InAppWebView] and re-composites it per arm without
/// rebuilding it — the same native view is measured in every arm, so a
/// difference between arms is a difference in compositing and nothing else.
class GateHarness extends StatefulWidget {
  const GateHarness({
    super.key,
    required this.browser,
    required this.arm,
    required this.initialUrl,
  });

  final BrowserController browser;
  final ValueListenable<SurfaceArm> arm;
  final String initialUrl;

  @override
  State<GateHarness> createState() => GateHarnessState();
}

class GateHarnessState extends State<GateHarness> {
  /// The raw controller, so the experiment can evaluate its own probes without
  /// going through the app's bridge.
  InAppWebViewController? raw;

  /// Built once and held, so re-compositing for an arm never rebuilds the
  /// native view.
  late final Widget _webView = InAppWebView(
    key: const ValueKey('gate-webview'),
    initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
    initialSettings: BrowserController.settings,
    initialUserScripts: UnmodifiableListView([
      BrowserController.bridgeUserScript,
    ]),
    onWebViewCreated: (controller) {
      raw = controller;
      widget.browser.attach(controller);
    },
    shouldOverrideUrlLoading: (_, _) async => NavigationActionPolicy.ALLOW,
    onCreateWindow: (_, _) async => false,
    onLoadStart: (_, url) => widget.browser.onLoadStart(url?.toString()),
    onLoadStop: (_, url) => widget.browser.onLoadStop(url?.toString()),
    onProgressChanged: (_, p) => widget.browser.onProgress(p),
    onUpdateVisitedHistory: (_, url, _) =>
        widget.browser.onUrlChanged(url?.toString()),
    onConsoleMessage: (_, msg) => debugPrint('[gate:page] ${msg.message}'),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ValueListenableBuilder<SurfaceArm>(
        valueListenable: widget.arm,
        builder: (context, arm, _) {
          // IndexedStack lays every child out at full size and paints only the
          // selected one.
          final stack = IndexedStack(
            sizing: StackFit.expand,
            index: arm == SurfaceArm.unpainted ? 1 : 0,
            children: [_webView, const SizedBox.expand()],
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              stack,
              if (arm == SurfaceArm.covered)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF101014)),
                ),
            ],
          );
        },
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  final readings = <ArmReading>[];

  setUpAll(fixture.start);

  tearDownAll(() async {
    await fixture.stop();
    debugPrint('[gate] ---- results ----');
    for (final reading in readings) {
      debugPrint(reading.toString());
    }
  });

  Future<ArmReading> runArm(WidgetTester tester, SurfaceArm arm) async {
    final reading = ArmReading(arm);
    final armNotifier = ValueNotifier<SurfaceArm>(SurfaceArm.painted);
    final key = GlobalKey<GateHarnessState>();
    final library = LibraryDatabase(name: 'it_gate_${arm.name}_$kRunStamp');
    final fileStore = await FileStore.open(
      folderName: 'webread_it_gate_${arm.name}_$kRunStamp',
    );
    final services = libui.LibraryUiServices(library, fileStore: fileStore);
    final browser = BrowserController();

    final engineStates = <SaveState>{};
    var progress = const SaveProgress();
    final capture = EntryCaptureService(
      entries: services.entries,
      collections: services.collections,
      offlineCopies: services.offline,
      fileStore: fileStore,
      capturePreferences: CapturePreferenceStore(LocalSettingsStore(library)),
      source: SaveEnginePageCaptureSource(
        browser: browser,
        engineFor: (sink) => SaveEngine(
          browser: browser,
          fileStore: fileStore,
          downloader: AssetFetcher(
            browser: browser,
            config: kDefaultSaveConfig,
          ),
          sink: sink,
          onProgress: (update) {
            progress = update(progress);
            engineStates.add(progress.state);
          },
          onLog: (line) => debugPrint('[gate:${arm.name}] $line'),
        ),
      ),
    );

    // Always start painted: a WebView that has never been composited has
    // nothing to say about what covering it does.
    final entryUrl = fixture.entry(1);
    await tester.pumpWidget(
      GateHarness(
        key: key,
        browser: browser,
        arm: armNotifier,
        initialUrl: entryUrl,
      ),
    );
    for (var i = 0; i < 100 && !browser.isAttached; i++) {
      await pumpFor(tester, const Duration(milliseconds: 100));
    }
    expect(browser.isAttached, isTrue, reason: 'no WebView attached');
    await pumpFor(tester, const Duration(seconds: 4));
    debugPrint('[gate:${arm.name}] loaded url=${browser.currentUrl}');

    // Now composite for this arm and give the platform view several frames to
    // settle into it. The controller is told what the app is doing, because the
    // app is the authority on that and no page-side signal is portable.
    armNotifier.value = arm;
    browser.surfaceIsPainted = arm != SurfaceArm.unpainted;
    await pumpFor(tester, const Duration(seconds: 2));

    final raw = key.currentState!.raw!;

    Future<Object?> eval(String js) async {
      final result = await raw.callAsyncJavaScript(functionBody: js);
      return result?.value;
    }

    Future<int> evalInt(String js) async {
      final value = await eval(js);
      if (value is num) return value.round();
      return num.tryParse('$value')?.round() ?? -1;
    }

    // 1. Geometry, straight from the page rather than through the app bridge.
    debugPrint(
      '[gate:${arm.name}] href=${await eval('return location.href;')} '
      'readyState=${await eval('return document.readyState;')} '
      'imgs=${await eval('return document.images.length;')}',
    );
    reading.viewportHeight = await evalInt('return window.innerHeight;');
    reading.documentHeight = await evalInt(
      'return document.documentElement.scrollHeight;',
    );
    reading.visibility =
        '${await eval('return document.visibilityState;') ?? '?'}';

    // 2. Does scroll advance?
    reading.scrollBefore = await evalInt('return Math.round(window.scrollY);');
    await eval('window.scrollBy(0, 900); return 1;');
    await pumpFor(tester, const Duration(milliseconds: 600));
    reading.scrollAfter = await evalInt('return Math.round(window.scrollY);');

    // 3. requestAnimationFrame ticks over one second of wall clock. Counted in
    //    the page and read back afterwards, so the count is not distorted by
    //    the round trip. This is the signal §3.1 found actually degrades when a
    //    surface is not composited, and the reason none of the numbers above it
    //    can be trusted to discriminate.
    await eval('''
      window.__gateTicks = 0;
      const step = () => { window.__gateTicks++; requestAnimationFrame(step); };
      requestAnimationFrame(step);
      return 1;
    ''');
    await pumpFor(tester, const Duration(seconds: 1));
    reading.rafTicks = await evalInt('return window.__gateTicks;');

    // 4. The real thing: one Entry, captured by the production V2 pipeline,
    //    from the top of the page.
    final root = await services.folders.ensureRoot();
    final (entry, _) = await services.entries.createStandalone(
      folderId: root.id,
      title: 'gate ${arm.name}',
    );
    final (location, _) = await services.entries.addLocation(
      entryId: entry!.id,
      url: entryUrl,
      urlKey: normalizeUrl(entryUrl),
      discoveryBasis: 'userSave',
    );

    var cancelled = false;
    EntryCaptureResult? result;
    unawaited(
      capture
          .capture(
            entryId: entry.id,
            locationId: location!.id,
            locationUrl: entryUrl,
            captureMode: null,
            shouldContinue: () => !cancelled,
          )
          .then((value) => result = value),
    );

    // The unpainted arm never terminates on its own — it holds at
    // `waitingForBrowser` by design, so it is expected to spend its whole
    // budget here and is then cancelled cooperatively.
    final settled = await pumpWhile(
      tester,
      () => result != null,
      timeout: arm == SurfaceArm.unpainted
          ? const Duration(seconds: 45)
          : const Duration(minutes: 3),
    );
    if (!settled) {
      cancelled = true;
      await pumpWhile(
        tester,
        () => result != null,
        timeout: const Duration(seconds: 40),
      );
    }

    reading.captureStatus = result?.status.name ?? 'never-finished';
    reading.heldForBrowser = engineStates.contains(SaveState.waitingForBrowser);
    reading.storedImages = result?.manifest?.storedAssetCount ?? 0;

    debugPrint(reading.toString());

    browser.detach();
    await library.close();
    armNotifier.dispose();
    return reading;
  }

  testWidgets('painted: baseline', (tester) async {
    readings.add(await runArm(tester, SurfaceArm.painted));
    final reading = readings.last;
    expect(reading.viewportHeight, greaterThan(0));
    expect(reading.scrollAfter, greaterThan(reading.scrollBefore));
    expect(
      reading.rafTicks,
      greaterThan(30),
      reason: 'a visible page animates at the display rate',
    );
    expect(reading.captureStatus, EntryCaptureStatus.captured.name);
    expect(reading.storedImages, kFixtureImagesPerEntry);
    expect(reading.heldForBrowser, isFalse);
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets(
    'covered: painted under an opaque layer',
    (tester) async {
      readings.add(await runArm(tester, SurfaceArm.covered));
      final covered = readings.last;
      final painted = readings.firstWhere((r) => r.arm == SurfaceArm.painted);

      // The premise, stated as the plan's V-1 acceptance criteria state it.
      expect(
        covered.viewportHeight,
        painted.viewportHeight,
        reason: 'covering is not resizing',
      );
      expect(
        covered.documentHeight,
        painted.documentHeight,
        reason: 'covering is not reflowing',
      );
      expect(
        covered.scrollAfter,
        greaterThan(covered.scrollBefore),
        reason: 'a covered page still scrolls',
      );
      expect(
        covered.rafTicks,
        greaterThan((painted.rafTicks * 0.8).round()),
        reason:
            'requestAnimationFrame is the honest signal, and a covered page must '
            'keep it within 20% of the visible baseline',
      );
      expect(
        covered.captureStatus,
        EntryCaptureStatus.captured.name,
        reason: 'a covered capture must complete',
      );
      expect(
        covered.storedImages,
        painted.storedImages,
        reason: 'and store byte-for-byte what the visible one stored',
      );
      expect(
        covered.heldForBrowser,
        isFalse,
        reason: 'covered is drawn, so nothing should have held',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets('unpainted: control', (tester) async {
    readings.add(await runArm(tester, SurfaceArm.unpainted));
    final reading = readings.last;

    // The control is the half of this experiment that is easy to lose. §3.1
    // measured that the *page* cannot tell: viewport and scroll are useless on
    // both platforms, and `visibilityState` says `visible` on Android. So the
    // assertion is on the app's own guard firing, not on a page-side number.
    expect(
      reading.heldForBrowser,
      isTrue,
      reason:
          'an unpainted surface must hold the capture — this is invariant D1, '
          'and the guard it replaced (zero viewport alone) did not fire here',
    );
    expect(
      reading.captureStatus,
      isNot(EntryCaptureStatus.captured.name),
      reason: 'nothing may be committed off a surface nobody is compositing',
    );
    expect(
      reading.storedImages,
      0,
      reason: 'a held capture stores nothing at all',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
