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
/// ## The production implementation is blocked, deliberately
///
/// **No implementation over `SaveEngine` is written here, and writing one
/// requires an internal change to a frozen component** — which is its own
/// reviewed task, never a side effect of a call-site edit
/// (docs/V2_PORT_CHECKLIST.md).
///
/// `SaveEngine.saveCurrentPage` and `SaveEngine._saveDocument` do not stop at
/// a staged package. Both take `AppDatabase db`, and both end their last phase
/// by writing V1 library rows — `findEntryByUrlKeyAnywhere`, `upsertEntry`,
/// `clearOfflineRemovedMark`, `markCollectionSaved` — and by performing the
/// FileStore commit themselves. A V2 host has no V1 database and must not
/// acquire one, and the commit belongs to the pipeline, where the policy's
/// last gate sits.
///
/// The reviewed task is therefore: give the engine a way to end at "the
/// package is staged and here is what it holds" — the four database calls
/// behind an injected result sink, and the commit either moved out or its
/// output returned — leaving every measurement, judgement and stopping
/// condition inside it untouched. Until then this seam has exactly one
/// implementation, in `test/save_v2/`, and Lane E's device-bound validation
/// waits on that task.
library;

import '../storage/document.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import 'capture_mode.dart';
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
       stopReason = null;

  /// Nothing was stored, and the reason is not the app's own policy: the page
  /// held nothing this app saves, the site stopped the run, the download
  /// failed, the surface never rendered.
  const PageCaptureOutcome.failed({
    required this.pageUrl,
    required this.error,
    this.stopReason,
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
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
  });
}

/// Convenience for an implementation that stages a structured document: the
/// reference the manifest needs, measured from the document itself.
DocumentRef documentRefFor(StructuredDocument document) => DocumentRef(
  relativePath: FileStore.documentFileName,
  blockCount: document.blockCount,
  textLength: document.textLength,
);
