// Architecture gate: does a *painted but fully covered* platform view keep
// rendering, scrolling and running JavaScript?
//
//   flutter test integration_test/occlusion_gate_test.dart -d <device-id>
//
// This is an experiment, not a product test. It exists to answer one binary
// question before any foreground-multitasking code is written, and it is
// referenced by docs/FOREGROUND_MULTITASKING.md §"Architecture decision".
//
// Three arms over the same real WebView, the same fixture entry, and the same
// production save engine:
//
//   painted    — the WebView is the only thing on screen (today's Browser tab)
//   covered    — the WebView is painted, an opaque layer is drawn over all of
//                it (what a Reader route would do above a root-hosted WebView)
//   unpainted  — the WebView is laid out but not painted, via IndexedStack
//                (today's shell when the Library tab is selected)
//
// Each arm records viewport height, scroll advance, requestAnimationFrame tick
// rate, document.visibilityState, and the outcome of a real one-entry save.
// The fixture entry loads four of its six panels through an IntersectionObserver
// with a 400ms delay, so a save that stores six proves viewport, scrolling,
// timers, JavaScript, IntersectionObserver and lazy loading all at once.
//
// Expected, if the always-painted architecture is viable: `painted` and
// `covered` agree on every number that matters and both store six images;
// `unpainted` reports a zero viewport and refuses to extract.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import '../tool/fixture/fixture_site.dart';

late String kFixtureBase;

final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

/// How the WebView is composited for one arm of the experiment.
enum SurfaceArm {
  /// Nothing above it.
  painted,

  /// Painted, with an opaque full-screen layer drawn over it.
  covered,

  /// Laid out but not painted — the current shell's hidden tab.
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
  String saveState = '?';
  int storedEntries = -1;
  int storedImages = -1;

  @override
  String toString() =>
      '[gate] ${arm.name.padRight(9)} '
      'viewport=$viewportHeight doc=$documentHeight '
      'scroll=$scrollBefore->$scrollAfter '
      'raf/s=$rafTicks visibility=$visibility '
      'save=$saveState entries=$storedEntries images=$storedImages';
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
  /// The raw controller, so the experiment can evaluate its own probes
  /// without going through the app's bridge.
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
          // selected one — exactly what the app shell does today.
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

  late HttpServer server;
  final readings = <ArmReading>[];

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    kFixtureBase = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      try {
        await for (final req in server) {
          try {
            await handleFixtureRequest(req);
          } catch (_) {
            /* client went away */
          }
        }
      } catch (_) {
        /* server closed */
      }
    }());
  });

  tearDownAll(() {
    server.close(force: true);
    debugPrint('[gate] ---- results ----');
    for (final r in readings) {
      debugPrint(r.toString());
    }
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Pump for [duration] of wall clock, so the page keeps getting frames.
  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<ArmReading> runArm(WidgetTester tester, SurfaceArm arm) async {
    final reading = ArmReading(arm);
    final armNotifier = ValueNotifier<SurfaceArm>(SurfaceArm.painted);
    final key = GlobalKey<GateHarnessState>();
    final db = AppDatabase(name: 'it_gate_${arm.name}_$kRunStamp');
    final fileStore = await FileStore.open(
      folderName: 'webread_it_gate_${arm.name}_$kRunStamp',
    );
    final browser = BrowserController();
    final run = SaveRunController(
      browser: browser,
      db: db,
      fileStore: fileStore,
    );

    // Always start painted: a WebView that has never been composited has
    // nothing to say about what covering it does.
    final entryUrl = '$kFixtureBase/entry/1';
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
    // settle into it.
    armNotifier.value = arm;
    await pumpFor(tester, const Duration(seconds: 2));

    final raw = key.currentState!.raw!;

    Future<Object?> eval(String js) async {
      final r = await raw.callAsyncJavaScript(functionBody: js);
      return r?.value;
    }

    Future<int> evalInt(String js) async {
      final v = await eval(js);
      if (v is num) return v.round();
      return num.tryParse('$v')?.round() ?? -1;
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
    //    the round trip.
    await eval('''
      window.__gateTicks = 0;
      const step = () => { window.__gateTicks++; requestAnimationFrame(step); };
      requestAnimationFrame(step);
      return 1;
    ''');
    await pumpFor(tester, const Duration(seconds: 1));
    reading.rafTicks = await evalInt('return window.__gateTicks;');

    // 4. The real thing: one entry, saved by the production engine, from the
    //    top of the page.
    await browser.loadAndWait(entryUrl);
    await pumpFor(tester, const Duration(seconds: 2));
    unawaited(
      run.start(
        range: SaveScope.currentPageOnly,
        entryLimit: 1,
        startUrl: entryUrl,
      ),
    );
    await pumpUntil(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
      // The unpainted arm never terminates — it holds at waitingForBrowser by
      // design, so this arm is expected to spend its whole budget here.
      timeout: arm == SurfaceArm.unpainted
          ? const Duration(seconds: 45)
          : const Duration(minutes: 3),
    );
    reading.saveState = run.progress.state.name;
    reading.storedEntries = run.progress.storedEntries;

    final entries = await db.allEntries();
    var images = 0;
    for (final e in entries) {
      final path = e.contentPath;
      if (path == null) continue;
      final manifest = await fileStore.readManifest(path);
      if (manifest != null) images += manifest.storedAssetCount;
    }
    reading.storedImages = images;

    debugPrint(reading.toString());
    for (final line in run.log.reversed.take(40)) {
      debugPrint('[gate:${arm.name}] $line');
    }

    run.stop();
    await pumpFor(tester, const Duration(seconds: 2));
    browser.detach();
    await db.close();
    armNotifier.dispose();
    return reading;
  }

  testWidgets('painted: baseline', (tester) async {
    readings.add(await runArm(tester, SurfaceArm.painted));
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets(
    'covered: painted under an opaque layer',
    (tester) async {
      readings.add(await runArm(tester, SurfaceArm.covered));
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets('unpainted: control', (tester) async {
    readings.add(await runArm(tester, SurfaceArm.unpainted));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
