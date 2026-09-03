/// The seam between the V2 capture pipeline and the thing that drives a page.
///
/// **Why this exists.** Everything a capture does to *someone else's site* —
/// waiting for a painted surface, the paced scroll passes, lazy-image
/// settling, enumeration, detection, extraction, the asset downloads — is
/// device knowledge that was paid for on hardware and is frozen
/// (docs/V2_PORT_CHECKLIST.md). Everything a capture does to *this device* —
/// asking the restricted-site policy, writing the manifest, the atomic commit,
/// recording the OfflineCopy — is ordinary logic that must be provable on a
/// host with no WebView anywhere near it.
///
/// This interface is the line between the two. An implementation drives the
/// page and fills a staging directory; `entry_capture.dart` decides whether
/// there was ever going to be a capture, turns what came back into a manifest,
/// commits it and records the copy.
///
/// **An implementation is not free to skip the policy.** Every boundary asks
/// `capture_policy.dart` for itself, and an implementation that navigates —
/// and can therefore *land* somewhere other than where it aimed — owns the
/// landed-URL boundary, which no caller can ask on its behalf. It reports a
/// refusal as [PageCaptureOutcome.refused]. The pipeline still asks the policy
/// twice on its own account, before anything is staged and again immediately
/// before the commit.
///
/// ## The production implementation
///
/// [SaveEnginePageCaptureSource] wraps the ported save engine, which was given
/// exactly one seam to make that possible (reviewed as an internal change to a
/// frozen component — docs/V2_PORT_CHECKLIST.md). The engine's final phase used
/// to open staging under the store, commit the package and write four V1 rows
/// — `findEntryByUrlKeyAnywhere`, `upsertEntry`, `clearOfflineRemovedMark`,
/// `markCollectionSaved`. Those calls now go through an injected
/// `SaveResultSink`, whose default is precisely the V1 library, so a V1 save is
/// the save it always was. A V2 capture passes `StagedPackageSink` instead: the
/// engine fills the staging directory the pipeline opened, writes no row, and
/// ends at a staged package with a manifest describing what it holds.
///
/// Everything above that phase — every measurement, settle window, decode
/// decision, stopping condition and retry posture — is untouched and stays
/// untouched.
library;

import 'dart:async';

import '../browser/browser_controller.dart';
import '../browser/browsing_history.dart' show NavigationSource;
import '../core/url_utils.dart';
import '../storage/document.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import 'capture_mode.dart';
import 'capture_policy.dart';
import 'page_hint.dart';
import 'save_engine.dart';
import 'save_result_sink.dart';
import 'stop_conditions.dart';

/// What driving one page produced.
///
/// The judgements stay on this side of the seam — what the page was, which
/// mode could be honoured, whether the result is `complete` or `partial` and
/// why. The pipeline records them; it does not re-derive them, because the
/// only honest measurement is the one taken on the settled page.
class PageCaptureOutcome {
  /// A page that was read and staged.
  const PageCaptureOutcome.captured({
    required this.pageUrl,
    required this.title,
    required this.artifact,
    required this.captureMode,
    required this.status,
    required this.detectedAssetCount,
    required this.storedAssetCount,
    required this.assets,
    this.captureModeIsUserSet = false,
    this.canonicalUrl,
    this.statusReason,
    this.document,
    this.contentKind,
    this.contentKindConfidence,
    this.publishedAt,
    this.nextUrl,
  }) : error = null,
       stopReason = null,
       needsReaderAreaAssist = false;

  /// Nothing was stored, and the reason is not the app's own policy: the page
  /// held nothing this app saves, the site stopped the run, the download
  /// failed, the surface never rendered.
  const PageCaptureOutcome.failed({
    required this.pageUrl,
    required this.error,
    this.stopReason,
    this.needsReaderAreaAssist = false,
  }) : title = '',
       artifact = ArtifactFormat.unknown,
       captureMode = null,
       captureModeIsUserSet = false,
       status = SaveStatus.failed,
       detectedAssetCount = 0,
       storedAssetCount = 0,
       assets = const [],
       canonicalUrl = null,
       statusReason = null,
       document = null,
       contentKind = null,
       contentKindConfidence = null,
       publishedAt = null,
       nextUrl = null;

  /// The page the run actually landed on is on a service this app does not
  /// save from. A distinct outcome from [PageCaptureOutcome.failed] because it
  /// carries the app's own named reason and its one user-facing sentence.
  const PageCaptureOutcome.refused({required String pageUrl})
    : this.failed(
        pageUrl: pageUrl,
        error: null,
        stopReason: StopReason.captureRestrictedForSite,
      );

  /// Where the capture actually happened — not necessarily where it aimed. A
  /// redirect between the navigation and DOM-ready lands somewhere else, and
  /// **this** is the address the stored package claims to be a copy of.
  final String pageUrl;
  final String? canonicalUrl;
  final String title;

  /// What the staged package holds. The one field a reader may switch on.
  final ArtifactFormat artifact;

  /// The mode that was actually honoured on this page, which is not always the
  /// one that was asked for: a collection preference proposes, the page
  /// disposes.
  final CaptureMode? captureMode;
  final bool captureModeIsUserSet;

  final SaveStatus status;
  final String? statusReason;
  final int detectedAssetCount;
  final int storedAssetCount;

  /// The ordered page list, or a document's stored inline images.
  final List<EntryAsset> assets;

  /// Set when [artifact] is a structured document. The implementation has
  /// already written `document.json` into staging; this describes it.
  final DocumentRef? document;

  final String? contentKind;
  final String? contentKindConfidence;
  final DateTime? publishedAt;
  final String? nextUrl;

  final String? error;
  final StopReason? stopReason;

  /// Image extraction found too little, or a saved reader-area rule stopped
  /// matching. The page could still be captured if a person points at the
  /// container the entry is in — see `features/v2_save_flow.dart`.
  ///
  /// Only ever true alongside a failure, and only for an image sequence: a
  /// prose page that extracted nothing is reported and walked past, because
  /// this assistance hands back a container of *images*.
  final bool needsReaderAreaAssist;

  bool get isCaptured =>
      status == SaveStatus.complete || status == SaveStatus.partial;

  bool get isRestricted => stopReason == StopReason.captureRestrictedForSite;
}

/// Drives one page and stages what it holds.
///
/// The production implementation wraps the ported save engine and is the only
/// thing in the capture path that may touch a WebView; a test implementation
/// writes bytes into [StagingHandle] directly. Neither writes a database row,
/// commits anything, or decides whether the capture was allowed to start.
abstract interface class PageCaptureSource {
  /// Read [url] and fill [staging].
  ///
  /// [requestedMode] is **required and may be null**, for the same reason the
  /// save range is required in V1: no implementation may inherit a default
  /// about what it takes off someone else's page. Null means "decide from the
  /// settled page", which is a decision made where the measurement is.
  ///
  /// [shouldContinue] is the cooperative stop. It is asked at safe boundaries
  /// and never mid-write; a `false` answer ends the capture with a
  /// [StopReason.cancelledByUser] failure and leaves staging for the caller to
  /// discard.
  ///
  /// [readerHint] and [nextHint] are the narrowest rules the user has taught
  /// for this address, or null. They are passed through untouched — nothing
  /// here infers one, and a rule exists only because a person tapped an
  /// element.
  ///
  /// [pageAlreadyLoaded] is the caller stating that [url] is the page the
  /// browser is showing *and that this run put it there* — the sequential
  /// capture of a Source, which reads each page to find out which Entry it is
  /// and then captures it where it stands (V2-D56). It saves the second load
  /// of the same page, which is a request to somebody else's site that this
  /// app has no reason to make twice. It is never inferred: a page the user
  /// has been reading has been scrolled, and the engine scrolls **downward
  /// from where it finds the page**, so capturing one in place would miss
  /// everything above the reader's position.
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  });
}

/// Convenience for an implementation that stages a structured document: the
/// reference the manifest needs, measured from the document itself.
DocumentRef documentRefFor(StructuredDocument document) => DocumentRef(
  relativePath: FileStore.documentFileName,
  blockCount: document.blockCount,
  textLength: document.textLength,
);

/// Builds the save engine for one capture, over the sink that keeps its
/// package staged.
///
/// A function rather than an engine, because the sink is per-capture: it
/// carries the staging directory the pipeline opened. Everything WebView-bound
/// — the controller, the asset fetcher, the config — is closed over by whoever
/// supplies this, which is what lets a host test build the same source over a
/// fake browser.
typedef SaveEngineFactory = SaveEngine Function(SaveResultSink sink);

/// The production [PageCaptureSource]: the ported save engine, ended at a
/// staged package.
///
/// It owns the two things only the thing that drives the page can own — the
/// navigation, and therefore the landed-URL boundary — and nothing else. It
/// writes no row, commits nothing, and decides nothing about whether the
/// capture was allowed to start; `entry_capture.dart` does all three.
class SaveEnginePageCaptureSource implements PageCaptureSource {
  SaveEnginePageCaptureSource({
    required this.browser,
    required this.engineFor,
    this.cancelPollInterval = const Duration(milliseconds: 250),
  });

  /// The one thing in the capture path that may touch a WebView.
  final BrowserController browser;
  final SaveEngineFactory engineFor;

  /// How often the cooperative stop is relayed to the engine.
  ///
  /// The engine's own checkpoints are what actually stop it; `cancel()` is how
  /// it is asked, and it is asked from here because [PageCaptureSource] states
  /// the stop as a question the caller answers rather than a signal it sends.
  final Duration cancelPollInterval;

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) async {
    if (!shouldContinue()) return _cancelled(url);

    final engine = engineFor(StagedPackageSink(staging));
    final poll = Timer.periodic(cancelPollInterval, (_) {
      if (!shouldContinue()) engine.cancel();
    });

    // **Claim the WebView, for as long as this capture drives it.** There is
    // one WebView and `automationOwner` is how the app says who is driving it
    // — a Collection check refuses to start against a Browser somebody else
    // holds. A capture that never claimed it left that guard reading a field
    // nobody set, and left every page the capture opened attributed to the
    // user: `effectiveNavigationSource` degrades an unclaimed Browser to
    // `manual`, which is the one value that enters browsing history.
    //
    // Saved and restored rather than cleared, so a nested claim can never
    // hand the Browser back on somebody else's behalf.
    final heldOwner = browser.automationOwner;
    final heldSource = browser.navigationSource;
    browser.automationOwner = 'a download';
    browser.navigationSource = NavigationSource.saveAutomation;

    final EntrySaveResult result;
    try {
      // Claim the surface *before* the first navigation. WebKit fixes a
      // document's visibility at creation, so a document created in a view
      // that is not being composited is born hidden and stays that way — see
      // `browser_surface_policy.dart` and the guard the engine then applies to
      // every phase.
      await browser.awaitPaintedSurface();
      // The page this run just opened to find out which Entry it is: the
      // engine's own contract is *save the page that is loaded*, so it is
      // captured where it stands rather than fetched a second time. Asserted
      // against the browser rather than trusted — if anything moved it in
      // between, this is an ordinary navigation again.
      if (!pageAlreadyLoaded ||
          normalizeUrl(browser.currentUrl) != normalizeUrl(url)) {
        browser.allowNextNavigation(url);
        await browser.loadAndWait(url);
      }
      result = await engine.saveCurrentPage(
        // V2 identity is the caller's: the Entry, the Location and the
        // collection are already decided, and the engine's own ids and
        // ordinals never leave the staged manifest.
        collectionId: null,
        entryOrder: 0,
        visitedNormalized: const <String>{},
        // Null means "decide from the settled page", which is a decision made
        // where the measurement is. Passed straight through, never defaulted.
        captureMode: requestedMode,
        // A reader-area rule is a rule about *images*; it has nothing to say
        // about a text save, and the engine only consults it on the image
        // path anyway. Exactly V1's condition.
        readerHint: requestedMode?.isDocument == true ? null : readerHint,
        nextHint: nextHint,
      );
    } finally {
      poll.cancel();
      browser.automationOwner = heldOwner;
      browser.navigationSource = heldSource;
    }
    return outcomeOf(result, requestedUrl: url);
  }

  static PageCaptureOutcome _cancelled(String url) => PageCaptureOutcome.failed(
    pageUrl: url,
    error: 'cancelled',
    stopReason: StopReason.cancelledByUser,
  );
}

/// Turn what the engine reports into what the pipeline records.
///
/// **Nothing is re-derived here.** Every judgement — the artifact, the mode
/// that was honoured, `complete` against `partial` and why, the counts, the
/// shape — is read off the manifest the engine built on the settled page,
/// because that is the only place the measurement exists. This function maps;
/// it does not decide.
///
/// Visible for the seam's own tests, which drive the engine over a fake
/// browser and check what comes back.
PageCaptureOutcome outcomeOf(
  EntrySaveResult result, {
  required String requestedUrl,
}) {
  final landed = result.pageUrl.isEmpty ? requestedUrl : result.pageUrl;
  final manifest = result.manifest;
  if (!result.isUsable || manifest == null) {
    // The engine refuses a restricted page with its own named reason and its
    // one user-facing sentence; both are the app's, not the site's, so the
    // refusal keeps its own outcome rather than becoming a failure.
    if (result.error == kCaptureRestrictedMessage ||
        isCaptureRestricted(landed)) {
      return PageCaptureOutcome.refused(pageUrl: landed);
    }
    return PageCaptureOutcome.failed(
      pageUrl: landed,
      error: result.error,
      // The engine's own named reason first — it is the one made where the
      // page was measured. The cancelled case stays because that answer comes
      // from the runner rather than from a measurement.
      stopReason:
          result.stopReason ??
          (result.error == 'cancelled' ? StopReason.cancelledByUser : null),
      // Read off the engine's own result, never re-derived: whether pointing
      // at the reader area could help is a judgement made where the page was
      // measured.
      needsReaderAreaAssist: result.needsReaderAreaAssist,
    );
  }
  return PageCaptureOutcome.captured(
    // The manifest's address, not the requested one: a redirect between the
    // navigation and DOM-ready lands somewhere else, and this is what the
    // package claims to be a copy of.
    pageUrl: manifest.sourceUrl,
    canonicalUrl: manifest.canonicalUrl,
    title: manifest.title,
    artifact: manifest.artifact,
    captureMode: result.captureMode,
    captureModeIsUserSet: manifest.captureModeIsUserSet ?? false,
    status: manifest.status,
    statusReason: manifest.statusReason,
    detectedAssetCount: manifest.detectedAssetCount,
    storedAssetCount: manifest.storedAssetCount,
    assets: manifest.assets,
    document: manifest.document,
    contentKind: manifest.contentKind,
    contentKindConfidence: manifest.contentKindConfidence,
    publishedAt: manifest.publishedAt,
    nextUrl: manifest.nextUrl,
  );
}
