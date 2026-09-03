/// The save sheet describes the page it was opened for, and no other.
///
/// **What this pins.** `V2SavePanel` is handed `(url, pageTitle)` as a
/// snapshot — `BrowserScreen._showSaveSheet` reads both off the Browser at the
/// moment the control is tapped — and then, in `initState`, asks the *live*
/// Browser for a probe. Those two are not the same page whenever the WebView
/// moves in between: a meta refresh, a `location.replace`, an SPA route that
/// lands late, or a save control tapped while the previous page was still
/// being replaced.
///
/// The probe's `pageHints` are not decoration. They feed `readPageShape`,
/// which produces `detectedTitle`, which is `_suggestedTitle`, which is what
/// the collection picker pre-fills the name field with — and a name the user
/// accepts is written to a real Collection by `LibraryAdoption.createCollection`.
/// So a probe taken from another page could name a new Collection after a work
/// the user was not looking at.
///
/// The rule: a probe is evidence about the address it was taken at. One taken
/// somewhere else is discarded, and the sheet falls back to what it already
/// knew about its own page — which is exactly the "not analysed" state it is
/// designed to open in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/collection_identity.dart' show PageHints;
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/entry_offline.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import '../helpers/fake_browser.dart';
import 'support/ui_harness.dart';

/// The page the user tapped Save on.
const _sheetUrl = 'https://reading.example.com/works/alpha/12';
const _sheetTitle = 'Alpha 12';

/// Where the Browser went while the sheet was opening. A different work, on a
/// different site, with a name nothing about the page above could produce.
const _movedUrl = 'https://elsewhere.example.com/works/distant-shore/3';
const _movedWork = 'Distant Shore';

void main() {
  late UiHarness h;
  late FakeBrowser browser;
  late List<String?> newCollectionNames;
  late ForegroundMultitasking capability;

  setUp(() {
    h = UiHarness();
    browser = FakeBrowser();
    newCollectionNames = [];
    capability = ForegroundMultitasking();
  });
  tearDown(() {
    capability.dispose();
    h.close();
  });

  Future<AddToLibraryReport> recordAdd(
    WidgetRef ref, {
    required String url,
    required String pageTitle,
    String? collectionId,
    String? newCollectionName,
    String? folderId,
    SaveLimits? limits,
    bool isListing = false,
    bool discoverMissing = false,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    newCollectionNames.add(newCollectionName);
    return AddToLibraryReport(
      sentence: 'The domain said what it did.',
      collectionId: collectionId ?? 'made-up-collection',
      entryId: 'made-up-entry',
      queued: limits?.maxEntries ?? 0,
    );
  }

  /// An ordinary readable page, optionally announcing a work by name the way
  /// a site's `og:title` does.
  PageProbe probeOf(String url, String title, {String? work}) => PageProbe(
    url: url,
    title: title,
    readyState: 'complete',
    documentHeight: 2000,
    viewportHeight: 800,
    viewportWidth: 400,
    atBottom: false,
    pageHints: work == null
        ? const PageHints()
        : PageHints(ogTitle: work, h1: work),
  );

  /// Open the sheet for [_sheetUrl] with the Browser standing on [browserUrl].
  ///
  /// The two being different is the whole scenario: the sheet's identity is
  /// the snapshot it was constructed with, and the probe it takes comes from
  /// wherever the WebView actually is.
  Future<void> openPanelWhileBrowserOn(
    WidgetTester tester,
    String browserUrl,
  ) async {
    browser
      ..addPage(_sheetUrl, probeOf(_sheetUrl, _sheetTitle))
      ..addPage(_movedUrl, probeOf(_movedUrl, 'Part 3', work: _movedWork))
      ..setUrl(browserUrl);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryUiServicesProvider.overrideWithValue(h.services),
          browserProvider.overrideWithValue(browser),
          saveQueueStarterProvider.overrideWithValue(h.starter),
          v2AddAndDownloadProvider.overrideWithValue(recordAdd),
          foregroundMultitaskingProvider.overrideWithValue(capability),
        ],
        child: MaterialApp(
          theme: appTheme(palette: AppPalette.light),
          home: _SaveSheetHost(url: _sheetUrl, pageTitle: _sheetTitle),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  /// The name the picker offers for a Collection about to be created.
  Future<String> suggestedName(WidgetTester tester) async {
    await pumpUntil(tester, key('v2AddToCollection'));
    await tapAndPump(tester, key('v2AddToCollection'));
    await pumpUntil(tester, key('collectionPickerNew'));
    await tapAndPump(tester, key('collectionPickerNew'));
    await pumpUntil(tester, key('collectionNameField'));
    return tester
        .widget<TextField>(key('collectionNameField'))
        .controller!
        .text;
  }

  screenTest('the name offered for a new Collection comes from this page', (
    tester,
  ) async {
    await h.root();
    await openPanelWhileBrowserOn(tester, _sheetUrl);
    final control = await suggestedName(tester);
    expect(
      control,
      isNot(contains(_movedWork)),
      reason: 'sanity: this page has nothing to do with the other work',
    );
    expect(control, isNotEmpty);
  });

  screenTest('a probe taken after the Browser moved names nothing on this '
      'sheet', (tester) async {
    await h.root();
    // The WebView is already showing another work by the time the sheet
    // probes — the sheet's own identity is still the page Save was tapped on.
    await openPanelWhileBrowserOn(tester, _movedUrl);

    final offered = await suggestedName(tester);
    expect(
      offered,
      isNot(contains(_movedWork)),
      reason:
          'a probe is evidence about the address it was taken at; this sheet '
          'is not that address',
    );
  });

  screenTest('and a Collection created from that sheet is not named after the '
      'page it never showed', (tester) async {
    await h.root();
    await openPanelWhileBrowserOn(tester, _movedUrl);

    await suggestedName(tester);
    await pumpUntil(tester, key('saveScopeAddToQueue'));
    final launch = key('saveScopeAddToQueue');
    await tester.ensureVisible(launch);
    await tester.pump();
    await tapAndPump(tester, launch);

    expect(newCollectionNames, hasLength(1));
    expect(
      newCollectionNames.single,
      isNot(contains(_movedWork)),
      reason: 'what is persisted is the page the user was actually saving',
    );
  });
}

/// The panel as the Browser hosts it: a modal route over a surface that
/// outlives it.
class _SaveSheetHost extends ConsumerStatefulWidget {
  const _SaveSheetHost({required this.url, required this.pageTitle});

  final String url;
  final String pageTitle;

  @override
  ConsumerState<_SaveSheetHost> createState() => _SaveSheetHostState();
}

class _SaveSheetHostState extends ConsumerState<_SaveSheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final start = await showModalBottomSheet<SaveSheetStart>(
      context: context,
      isScrollControlled: true,
      builder: (_) => V2SavePanel(url: widget.url, pageTitle: widget.pageTitle),
    );
    if (!mounted || start == null) return;
    await startQueuedDownloads(context, ref, decided: start.where);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
