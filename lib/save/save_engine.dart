import 'dart:async';

import 'package:uuid/uuid.dart';

import '../browser/browser_controller.dart';
import '../browser/browser_surface_policy.dart';
import '../browser/page_data.dart';
import '../core/config.dart';
import '../core/url_utils.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import 'asset_fetcher.dart';
import 'capture_mode.dart';
import 'capture_policy.dart';
import 'document_extraction.dart';
import 'save_state.dart';
import 'image_candidates.dart';
import 'next_page.dart';
import 'page_hint.dart';
import 'page_stability.dart';
import 'stop_conditions.dart';
import '../library/collection_identity.dart';
import '../library/collection_repository.dart';
import '../library/content_shape.dart';
import 'content_detection.dart';

const _uuid = Uuid();

/// Result of saving one entry.
class EntrySaveResult {
  const EntrySaveResult({
    required this.status,
    required this.entryId,
    this.manifest,
    this.nextUrl,
    this.nextEvidence,
    this.nextResult,
    this.readerHintFailed = false,
    this.extractionFailed = false,
    this.documentFailure,
    this.captureMode,
    this.nothingToSave = false,
    this.videoDominant = false,
    this.pageUrl = '',
    this.error,
    this.detectedImages = 0,
    this.storedImages = 0,
  });

  final SaveStatus status;
  final String entryId;
  final EntryManifest? manifest;
  final String? nextUrl;
  final String? nextEvidence;

  /// The full decision, including whether the user should be asked.
  final NextPageResult? nextResult;

  /// A saved reader-area rule matched nothing on this page.
  final bool readerHintFailed;

  /// **Image** extraction found too little to be an entry. This is the flag
  /// that routes a run into "point at the reader area", which is why it is
  /// image-specific: that assistance hands back a container of *images*, so
  /// offering it for a page with no readable prose would be a dead end
  /// dressed up as help.
  final bool extractionFailed;

  /// Why text extraction produced nothing, when it did. Deliberately a
  /// separate field from [extractionFailed]: the two failures have different
  /// causes, different messages and different remedies.
  final DocumentExtractionFailure? documentFailure;

  /// The mode this entry was actually saved in — the fallback, when the
  /// requested one could not be honoured on this page.
  final CaptureMode? captureMode;

  /// The settled page could hold nothing this app saves. Distinct from every
  /// other failure: there is nothing to retry and nothing to assist with, so
  /// the run reports it and walks on.
  final bool nothingToSave;

  /// …and it was a video page, which gets its own wording.
  final bool videoDominant;

  final String pageUrl;
  final String? error;

  /// Images detected and stored. For a document these are its inline images.
  final int detectedImages;
  final int storedImages;

  bool get isUsable =>
      status == SaveStatus.complete || status == SaveStatus.partial;

  /// Whether the run should offer user-assisted reader-area selection.
  ///
  /// Only ever for an image sequence. A prose page that failed to extract is
  /// reported and moved past — see `documentFailure`.
  bool get needsReaderAreaAssist => extractionFailed || readerHintFailed;
}

class SaveCancelled implements Exception {}

extension _EmptyToNull on String {
  /// Null for an empty reason, so "nothing to report" stays one value rather
  /// than becoming an empty string some readers would print.
  String? ifEmptyNull() => isEmpty ? null : this;
}

/// The page's image population as the save managed to read it.
class _ImageEnumeration {
  const _ImageEnumeration({
    required this.images,
    required this.total,
    required this.isComplete,
  });

  /// In document order, which is reading order.
  final List<PageImage> images;

  /// How many the page said it had.
  final int total;

  /// False when the save could not see every image the page holds. An entry
  /// built from an incomplete enumeration can never honestly be `complete`.
  final bool isComplete;
}

/// Reading state carried across a re-save.
///
/// Saving an entry must never move the user's place or un-finish something
/// they read. The one case where part of that cannot hold is a **format
/// change**: an anchor recorded against 40 image panels means nothing against
/// 300 text blocks, and applying it would drop the reader somewhere arbitrary
/// and call it "where you were".
///
/// So the split is: everything that is a fact about the *content* survives
/// (finished, first opened, last read, and the content-independent fraction);
/// only the anchor, which is a fact about the *artifact*, is reset. The
/// fraction then does exactly the job it was designed for — approximate but
/// always meaningful — and the reader lands in the right part of the entry.
class CarriedReading {
  const CarriedReading({
    this.readStatus = 'unread',
    this.fraction = 0,
    this.pageIndex = 0,
    this.offsetInPage = 0,
    this.anchorReset = false,
  });

  final String readStatus;
  final double fraction;
  final int pageIndex;
  final double offsetInPage;

  /// True when a format change forced the anchor back to the start.
  final bool anchorReset;
}

CarriedReading carryReading(Entry? existing, ArtifactFormat artifact) {
  if (existing == null) return const CarriedReading();
  final changed = ArtifactFormat.fromName(existing.artifactFormat) != artifact;
  return CarriedReading(
    readStatus: existing.readStatus,
    fraction: existing.progressFraction,
    pageIndex: changed ? 0 : existing.progressPageIndex,
    offsetInPage: changed ? 0 : existing.progressOffsetInPage,
    anchorReset: changed,
  );
}

/// Saves the page the WebView is currently showing.
///
/// The load-complete callback is treated as meaningless for content readiness:
/// the engine scrolls, watches document height / image counts / pending
/// decodes, and only extracts once the page has been quiet for a configured
/// period. That is the whole reason this class exists.
class SaveEngine {
  SaveEngine({
    required this.browser,
    required this.db,
    required this.fileStore,
    required this.downloader,
    this.config = kDefaultSaveConfig,
    this.onProgress,
    this.onLog,
  });

  final BrowserController browser;
  final AppDatabase db;
  final FileStore fileStore;
  final AssetFetcher downloader;
  final SaveConfig config;
  final void Function(SaveProgress Function(SaveProgress))? onProgress;
  final void Function(String)? onLog;

  bool _cancelled = false;
  bool _paused = false;

  /// Entry deadline. A field (not a parameter) because time spent waiting
  /// for the user to bring the Browser back is *their* time, not the page's —
  /// [_waitForRenderedSurface] extends it by exactly the waited duration.
  DateTime _deadline = DateTime.now();

  /// Phase durations for the diagnostic timing line, in milliseconds.
  final Map<String, int> _timings = {};

  /// The best candidate set seen during scrolling. If final extraction
  /// collapses far below this, something broke the page under us (an
  /// unrendered surface, a teardown) — refuse to store the wreckage.
  int _peakAccepted = 0;
  int _peakPanelHeight = 0;

  void cancel() => _cancelled = true;
  void pause() => _paused = true;
  void resume() => _paused = false;
  void reset() {
    _cancelled = false;
    _paused = false;
  }

  void _time(String phase, DateTime since) {
    _timings.update(
      phase,
      (v) => v + DateTime.now().difference(since).inMilliseconds,
      ifAbsent: () => DateTime.now().difference(since).inMilliseconds,
    );
  }

  void _log(String message) => onLog?.call(message);

  void _emit(SaveProgress Function(SaveProgress) update) =>
      onProgress?.call(update);

  Future<void> _checkpoint() async {
    if (_cancelled) throw SaveCancelled();
    while (_paused) {
      _emit((p) => p.copyWith(state: SaveState.paused));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_cancelled) throw SaveCancelled();
    }
  }

  Future<EntrySaveResult> saveCurrentPage({
    /// The collection this entry joins, or null for a standalone entry.
    required String? collectionId,
    required int entryOrder,
    required Set<String> visitedNormalized,

    /// What to produce. **Required**, for the same reason `range` is required
    /// on `SaveRunController.start`: no caller may inherit a default about
    /// what it takes off someone else's page.
    ///
    /// **Null means "decide from this page"** — which is a decision, not an
    /// absence of one, and it is deliberately made *here* rather than by the
    /// caller. The caller only has the probe taken when the page loaded; on
    /// the second and later entries of a run that page has not been scrolled
    /// yet, so a lazy-loading image sequence still looks like a page with no
    /// images. This method has the settled probe, and that is the only
    /// measurement worth deciding on.
    ///
    /// A non-null mode is still validated against the settled page, so a
    /// remembered preference cannot force an impossible save.
    required CaptureMode? captureMode,

    /// True when a person chose [captureMode] rather than detection.
    bool captureModeIsUserSet = false,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool replaceExisting = false,
  }) async {
    var entryId = _uuid.v4();
    _deadline = DateTime.now().add(config.maxSaveDuration);
    _timings.clear();
    _peakAccepted = 0;
    _peakPanelHeight = 0;
    StagingHandle? staging;

    // The restricted-site policy, asked before anything is read from the page.
    // Nothing has been probed, scrolled, measured or staged at this point, and
    // nothing will be: this returns above the DOM-ready wait.
    //
    // This — with the landed-page check below and the pre-commit check further
    // down — is where capture is decided, and it is decided about the **page**.
    // Both run before `fileStore.beginEntry`, so a restricted page never reaches
    // a staging directory and therefore never reaches a download at all. That
    // ordering is what lets `AssetFetcher` stay out of the policy entirely: the
    // question has already been answered by the time any asset URL exists, and
    // an asset's own host is not a capture source (see `capture_policy.dart`).
    final restrictedOnEntry = _restrictedRefusal(entryId, browser.currentUrl);
    if (restrictedOnEntry != null) return restrictedOnEntry;

    try {
      // 1. Inspect ------------------------------------------------------
      _emit(
        (p) => p.copyWith(
          state: SaveState.inspecting,
          message: 'Reading the page',
          clearError: true,
        ),
      );
      var tPhase = DateTime.now();
      final initial = await _awaitDomReady(_deadline);
      _time('domReady', tPhase);
      await _checkpoint();

      // An unrendered WebView (hidden tab) answers probes but measures
      // nothing real. Hold here — before any scrolling or judgement — until
      // the surface is back.
      await _waitForRenderedSurface('inspect');

      final pageTitle = initial.title.trim().isEmpty
          ? 'Untitled entry'
          : initial.title;
      final pageUrl = initial.url.isEmpty ? browser.currentUrl : initial.url;

      // Where we actually are, which is not always where we aimed: a redirect
      // between the navigation and DOM-ready lands here. Re-asked before a
      // single scroll, image inspection or download.
      final restrictedOnLanding = _restrictedRefusal(entryId, pageUrl);
      if (restrictedOnLanding != null) return restrictedOnLanding;

      // Re-saving an entry (a retry after a partial, say) must replace the
      // existing row, not insert a second one.
      //
      // The lookup is by URL **alone**, across every collection and the
      // standalone entries. Scoping it to [collectionId] was wrong once
      // `collection_id` became nullable: a single-page re-save resolves no
      // collection, so the scoped lookup missed the row that already existed
      // inside one and minted a fresh id — two rows for one page, with the
      // reading position stranded on the one nothing pointed at any more.
      // Neither the composite UNIQUE nor the standalone partial index can catch
      // that, because the two rows differ in `collection_id`.
      final existing = await db.findEntryByUrlKeyAnywhere(
        normalizeUrl(pageUrl),
      );
      if (existing != null) {
        entryId = existing.id;
        _log(
          're-saving existing entry '
          '${existing.id.length > 8 ? existing.id.substring(0, 8) : existing.id} '
          '(was ${existing.saveStatus})',
        );
      }
      // An entry keeps the collection it is already in. The caller may resolve
      // none (a single-page re-save does), and that must not move a page out of
      // the collection it belongs to — nor out of the directory its bytes are
      // already in.
      final owningCollectionId = collectionId ?? existing?.collectionId;

      _emit((p) => p.copyWith(entryTitle: pageTitle, currentUrl: pageUrl));
      _log('save start: "$pageTitle" <$pageUrl>');

      // 2-4. Scroll until the page stops changing ------------------------
      tPhase = DateTime.now();
      await _scrollUntilStable(initial);
      _time('scroll', tPhase);
      await _checkpoint();

      // 5. Verify --------------------------------------------------------
      _emit(
        (p) => p.copyWith(
          state: SaveState.verifying,
          message: 'Checking what loaded',
        ),
      );
      // Never measure the final candidate set on an unrendered surface.
      await _waitForRenderedSurface('verify');
      tPhase = DateTime.now();
      var probeWithLinks = await browser.probe(withLinks: true);
      if (probeWithLinks.viewportHeight <= 0) {
        // Went hidden between the guard and the probe: wait and re-measure.
        await _waitForRenderedSurface('verify');
        probeWithLinks = await browser.probe(withLinks: true);
      }

      // --- decide what this page becomes ---------------------------------
      // Measured on the SETTLED probe, after scrolling: before it, a lazy
      // page reports whatever happened to have loaded, and deciding from that
      // is how entry 2 of a run ends up saved in a different format from
      // entry 1.
      final capabilities = detectCaptureCapabilities(
        probeWithLinks,
        config: config,
      );
      final resolution = capabilities.resolve(captureMode);
      if (resolution.explanation != null) _log(resolution.explanation!);

      // A page that is *about* its video, with nothing readable on it, is the
      // one case that gets refused outright. Sweeping up its thumbnails and
      // calling that an offline copy is exactly what this exists to prevent.
      if (resolution.mode == null && capabilities.videoDominant) {
        _log(
          'nothing to save: this page is a video, and it has no readable '
          'text to save instead',
        );
        return EntrySaveResult(
          status: SaveStatus.failed,
          entryId: entryId,
          nothingToSave: true,
          videoDominant: true,
          error: 'video is not saved, and this page has no text to save',
          pageUrl: pageUrl,
        );
      }

      // A taught reader-area rule beats detection outright: the user pointed
      // at the container of images, so there is nothing left to infer.
      //
      // The `?? imageSequence` is unreachable in practice — capabilities only
      // yield no mode for a video page with no text, which returned above —
      // and is written rather than forced so a future value cannot turn this
      // into a crash.
      final resolvedMode = readerHint != null
          ? CaptureMode.imageSequence
          : (resolution.mode ?? CaptureMode.imageSequence);

      if (captureMode == null || captureMode != resolvedMode) {
        _log('capture mode: ${resolvedMode.name} (${capabilities.content})');
      }

      // --- the fork -----------------------------------------------------
      // Everything above is shared: a page has to be loaded, scrolled and
      // measured whatever it is going to be stored as. Everything below
      // depends on what was asked for, and the two paths converge again at
      // the download loop.
      if (resolvedMode.isDocument) {
        return await _saveDocument(
          captureMode: resolvedMode,
          captureModeIsUserSet: captureModeIsUserSet && resolution.honoured,
          entryId: entryId,
          existing: existing,
          owningCollectionId: owningCollectionId,
          entryOrder: entryOrder,
          pageUrl: pageUrl,
          pageTitle: pageTitle,
          probe: probeWithLinks,
          visitedNormalized: visitedNormalized,
          nextHint: nextHint,
          replaceExisting: replaceExisting,
        );
      }

      // A user-taught reader area wins over the generic heuristic — the user
      // pointed at the container, so there is nothing to infer.
      CandidateSelection? selection;
      if (readerHint != null) {
        final images = await browser.applyReaderRule(
          readerHint.locator.toJson(),
        );
        if (images != null && images.isNotEmpty) {
          selection = selectImageCandidates(images, config: config);
          _log(
            'reader-area rule matched ${images.length} image(s) -> '
            '${selection.acceptedCount} candidate(s)',
          );
        } else {
          _log('reader-area rule matched nothing on this page');
          return EntrySaveResult(
            status: SaveStatus.failed,
            entryId: entryId,
            error: 'saved reader-area rule no longer matches',
            readerHintFailed: true,
            pageUrl: pageUrl,
          );
        }
      }

      // Every image on the page, not just the first sliceful. Only for the
      // generic path: a taught reader-area rule already returned its own
      // complete list from inside the container the user pointed at.
      final enumeration = readerHint != null
          ? _ImageEnumeration(images: const [], total: 0, isComplete: true)
          : await _enumerateImages(probeWithLinks);
      await _checkpoint();

      final chosen =
          selection ??
          selectImageCandidates(enumeration.images, config: config);
      final rejectionCounts = <RejectReason, int>{};
      for (final r in chosen.rejected) {
        rejectionCounts.update(r.reason, (v) => v + 1, ifAbsent: () => 1);
      }
      // The denominator is whatever list the candidates were drawn from: the
      // enumerated page, or the container a taught rule handed back.
      final consideredCount = chosen.acceptedCount + chosen.rejected.length;
      _log(
        'candidates: ${chosen.acceptedCount} accepted, '
        '${chosen.rejected.length} rejected '
        '(of $consideredCount images) '
        '${rejectionCounts.entries.map((e) => '${e.key.name}=${e.value}').join(' ')}',
      );

      if (chosen.acceptedCount < config.minCandidates) {
        // Not a hard failure: the run can ask the user to point at the reader.
        return EntrySaveResult(
          status: SaveStatus.failed,
          entryId: entryId,
          error:
              'Only ${chosen.acceptedCount} content images found '
              '(need ${config.minCandidates})',
          extractionFailed: true,
          pageUrl: pageUrl,
        );
      }

      // Defensive extraction: if scrolling saw a healthy panel set and the
      // final selection collapsed to a fraction of it — or to short
      // avatar-sized images where tall panels were seen — the page is not
      // what it was (unrendered surface, teardown, layout loss). Storing
      // that would be a confident lie; fail towards user assistance instead.
      final chosenMaxHeight = chosen.accepted.fold<int>(
        0,
        (m, c) => c.height > m ? c.height : m,
      );
      final collapsedCount =
          _peakAccepted >= config.minCandidates &&
          chosen.acceptedCount * 2 < _peakAccepted;
      final collapsedHeight =
          _peakPanelHeight > 0 && chosenMaxHeight * 10 < _peakPanelHeight;
      if (readerHint == null && (collapsedCount || collapsedHeight)) {
        _log(
          'extraction collapsed: saw $_peakAccepted candidates '
          '(tallest $_peakPanelHeight px) while scrolling, now '
          '${chosen.acceptedCount} (tallest $chosenMaxHeight px) — refusing '
          'to store',
        );
        return EntrySaveResult(
          status: SaveStatus.failed,
          entryId: entryId,
          error:
              'The page changed under the save — found '
              '${chosen.acceptedCount} images where $_peakAccepted were seen',
          extractionFailed: true,
          pageUrl: pageUrl,
        );
      }
      _time('extract', tPhase);

      // 6. Extract -------------------------------------------------------
      _emit(
        (p) => p.copyWith(
          state: SaveState.extracting,
          detectedImages: chosen.acceptedCount,
          message: '${chosen.acceptedCount} images to fetch',
        ),
      );
      await _checkpoint();

      // 7. Download into staging ----------------------------------------
      staging = await fileStore.beginEntry(
        collectionId: owningCollectionId,
        entryId: entryId,
      );

      final userAgent = await browser.userAgent();
      final cookieHeader = await browser.cookieHeaderFor(pageUrl);

      var entries = <EntryAsset>[
        for (var i = 0; i < chosen.accepted.length; i++)
          EntryAsset(
            index: i + 1,
            sourceUrl: chosen.accepted[i].url,
            status: AssetStatus.pending,
            width: chosen.accepted[i].width,
            height: chosen.accepted[i].height,
          ),
      ];

      _emit(
        (p) => p.copyWith(
          state: SaveState.fetchingAssets,
          storedImages: 0,
          failedImages: 0,
        ),
      );

      tPhase = DateTime.now();
      entries = await _downloadAll(
        entries: entries,
        staging: staging,
        refererUrl: pageUrl,
        userAgent: userAgent,
        cookieHeader: cookieHeader,
      );
      _time('download', tPhase);
      await _checkpoint();

      final stored = entries.where((e) => e.isStored).length;
      final failed = entries.length - stored;

      if (stored == 0) {
        await fileStore.discard(staging);
        return _fail(entryId, 'No images could be downloaded');
      }

      // 8. Detect the next entry before we leave the page --------------
      _emit((p) => p.copyWith(state: SaveState.detectingNext));

      final next = await _resolveNext(
        probe: probeWithLinks,
        pageUrl: pageUrl,
        visitedNormalized: visitedNormalized,
        nextHint: nextHint,
      );

      // 9. Save: manifest -> atomic move -> database --------------------
      _emit((p) => p.copyWith(state: SaveState.saving, message: 'Saving'));

      // An entry built from an image list the save could not finish reading is
      // **never** complete, however well the downloads went. Those images were
      // not skipped by a filter and not failed by a server; they were never
      // looked at, and reporting that as a finished offline copy is the exact
      // failure this guards.
      final truncatedReason = enumeration.isComplete
          ? null
          : 'imagesTruncated:${enumeration.images.length}/${enumeration.total}';
      final status = (failed == 0 && truncatedReason == null)
          ? SaveStatus.complete
          : SaveStatus.partial;

      // …and it must not overwrite a copy that holds more. Replacement exists
      // to repair an entry, not to trade a good one for a shorter one; the
      // staged tree is discarded and the readable copy stays exactly as it is.
      if (truncatedReason != null &&
          existing != null &&
          existing.storedAssetCount > stored) {
        await fileStore.discard(staging);
        staging = null;
        _log(
          'refusing to replace "${existing.title}": it holds '
          '${existing.storedAssetCount} image(s) and this capture could only '
          'read $stored of ${enumeration.total} — keeping the saved copy',
        );
        return EntrySaveResult(
          status: SaveStatus.failed,
          entryId: entryId,
          error:
              'This page has ${enumeration.total} images, more than one pass '
              'can read. The existing save (${existing.storedAssetCount} '
              'images) was kept.',
          pageUrl: pageUrl,
          detectedImages: entries.length,
          storedImages: stored,
        );
      }

      if (truncatedReason != null) {
        _log(
          'saving as partial: read ${enumeration.images.length} of '
          '${enumeration.total} images on the page ($truncatedReason)',
        );
      }
      final imageShape = detectContentKind(probeWithLinks);
      final manifest = EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.imageSequence,
        captureMode: CaptureMode.imageSequence.name,
        captureModeIsUserSet: captureModeIsUserSet && resolution.honoured,
        entryId: entryId,
        collectionId: owningCollectionId,
        sourceUrl: pageUrl,
        canonicalUrl: probeWithLinks.canonicalUrl,
        title: pageTitle,
        savedAt: DateTime.now(),
        status: status,
        statusReason: [
          if (failed > 0) 'assetsFailed:$failed',
          ?truncatedReason,
        ].join(' ').ifEmptyNull(),
        detectedAssetCount: entries.length,
        storedAssetCount: stored,
        nextUrl: next.chosen?.href,
        entryOrder: entryOrder,
        host: Uri.tryParse(pageUrl)?.host.toLowerCase(),
        contentKind: imageShape.kind.name,
        contentKindConfidence: imageShape.confidence.name,
        publishedAt: probeWithLinks.content.publishedAt,
        assets: entries,
      );

      // Last gate before anything is committed. The manifest names the URL this
      // package claims to be a copy of, so that URL — not the one the run
      // started from — is what the policy is asked about. A refusal here
      // discards the staging tree and writes no row, no file and no manifest.
      if (isCaptureRestricted(manifest.sourceUrl)) {
        await fileStore.discard(staging);
        staging = null;
        return _restrictedRefusal(entryId, manifest.sourceUrl)!;
      }

      // Replacing keeps the old copy until the new one is safely in place, so
      // a failed re-download leaves the readable entry untouched.
      tPhase = DateTime.now();
      final relativePath = replaceExisting || existing?.contentPath != null
          ? await fileStore.commitReplacing(staging, manifest)
          : await fileStore.commit(staging, manifest);
      staging = null;

      final byteSize = await fileStore.entryByteSize(relativePath);
      // The page's own headings and breadcrumb tail are read too: some sites
      // put a clean "Entry 487" in an <h1> while the <title> carries the
      // site name and a tagline.
      final hints = probeWithLinks.pageHints;
      final entryNumber = parseEntryNumber(
        title: pageTitle,
        url: pageUrl,
        extra: [
          hints.h1,
          hints.ogTitle,
          if (hints.breadcrumbs.isNotEmpty) hints.breadcrumbs.last.text,
        ],
      );
      // What this page is, measured from the page itself. A user answer already
      // on the row always wins: detection must never overwrite a correction.
      final shape = detectContentKind(probeWithLinks);
      final keepUserKind = existing?.contentKindIsUserSet == true;
      final carried = carryReading(existing, ArtifactFormat.imageSequence);
      if (carried.anchorReset) {
        _log(
          're-saved as an image sequence over a different format — reading '
          'position kept as a fraction, exact anchor reset',
        );
      }

      await db.upsertEntry(
        Entry(
          id: entryId,
          collectionId: owningCollectionId,
          title: pageTitle,
          sourceUrl: pageUrl,
          urlKey: normalizeUrl(pageUrl),
          canonicalUrl: probeWithLinks.canonicalUrl,
          host: Uri.tryParse(pageUrl)?.host.toLowerCase() ?? '',
          sourceTitle: probeWithLinks.title.trim().isEmpty
              ? null
              : probeWithLinks.title.trim(),
          publishedAt: probeWithLinks.content.publishedAt,
          contentKind: keepUserKind ? existing!.contentKind : shape.kind.name,
          contentKindConfidence: keepUserKind
              ? existing!.contentKindConfidence
              : shape.confidence.name,
          contentKindIsUserSet: keepUserKind,
          artifactFormat: ArtifactFormat.imageSequence.name,
          captureMode: CaptureMode.imageSequence.name,
          saveStatus: status.name,
          contentPath: relativePath,
          savedAt: manifest.savedAt,
          detectedAssetCount: entries.length,
          storedAssetCount: stored,
          nextSourceUrl: next.chosen?.href,
          // A row that already had a place in the collection (a discovered
          // entry, a retried partial) keeps it; this run's traversal
          // ordinal is only for entries it introduces.
          entryOrder: existing != null && existing.entryOrder > 0
              ? existing.entryOrder
              : entryOrder,
          saveError: [
            if (failed > 0) '$failed image(s) failed',
            if (truncatedReason != null)
              'only ${enumeration.images.length} of ${enumeration.total} '
                  'images on the page could be read',
          ].join('; ').ifEmptyNull(),
          byteSize: byteSize,
          entryNumber: entryNumber,
          sourceMarker: sourceMarkerFrom(
            title: pageTitle,
            url: pageUrl,
            number: entryNumber,
          ),
          // Reading state is carried over, never rebuilt. Saving an entry —
          // including re-downloading one — must not move the user's place or
          // un-finish something they had read. See [carryReading] for the one
          // part that cannot survive a change of stored format.
          readStatus: carried.readStatus,
          progressFraction: carried.fraction,
          progressPageIndex: carried.pageIndex,
          progressOffsetInPage: carried.offsetInPage,
          firstOpenedAt: existing?.firstOpenedAt,
          lastReadAt: existing?.lastReadAt,
          completedAt: existing?.completedAt,
          progressUpdatedAt: existing?.progressUpdatedAt,
          // Saving an entry an update check discovered fills in the same
          // row; keep the discovery record as history.
          discoveredAt: existing?.discoveredAt,
          discoveryBasis: existing?.discoveryBasis,
          discoveryConfidence: existing?.discoveryConfidence,
        ),
      );
      // Files are back, so the user-removed marker must go (a null on the
      // data class would be treated as "leave it alone").
      await db.clearOfflineRemovedMark(entryId);
      // Standalone entries have no collection to stamp; the entry's own
      // `savedAt` is the whole record.
      if (owningCollectionId != null) {
        await db.markCollectionSaved(owningCollectionId, manifest.savedAt);
      }

      _time('commit', tPhase);
      _log(
        'saved $stored/${entries.length} images -> $relativePath '
        '(${status.name})',
      );
      _log(
        '[timing] ${_timings.entries.map((e) => '${e.key}=${e.value}ms').join(' · ')}',
      );

      _emit(
        (p) => p.copyWith(
          state: status == SaveStatus.complete
              ? SaveState.complete
              : SaveState.partial,
          storedImages: stored,
          failedImages: failed,
          message: 'Saved $stored of ${entries.length} images',
        ),
      );

      return EntrySaveResult(
        status: status,
        entryId: entryId,
        manifest: manifest,
        nextUrl: next.hasNext ? next.chosen?.href : null,
        nextEvidence: next.chosen?.evidence,
        nextResult: next,
        captureMode: CaptureMode.imageSequence,
        pageUrl: pageUrl,
        detectedImages: entries.length,
        storedImages: stored,
      );
    } on SaveCancelled {
      if (staging != null) await fileStore.discard(staging);
      _emit(
        (p) => p.copyWith(state: SaveState.cancelled, message: 'Cancelled'),
      );
      return EntrySaveResult(
        status: SaveStatus.failed,
        entryId: entryId,
        error: 'cancelled',
      );
    } catch (e, stack) {
      if (staging != null) await fileStore.discard(staging);
      _log('save error: $e\n$stack');
      return _fail(entryId, e.toString());
    }
  }

  // --- structured documents -----------------------------------------------

  /// Save the page as text, optionally with the images that sit inside it.
  ///
  /// Shares staging, the download loop, next-page detection and the atomic
  /// commit with the image path — the difference is what gets written, not how
  /// safely it gets written.
  Future<EntrySaveResult> _saveDocument({
    required CaptureMode captureMode,
    required bool captureModeIsUserSet,
    required String entryId,
    required Entry? existing,
    required String? owningCollectionId,
    required int entryOrder,
    required String pageUrl,
    required String pageTitle,
    required PageProbe probe,
    required Set<String> visitedNormalized,
    UserPageHint? nextHint,
    bool replaceExisting = false,
  }) async {
    StagingHandle? staging;
    try {
      _emit(
        (p) => p.copyWith(
          state: SaveState.extracting,
          message: 'Reading the text',
        ),
      );
      final tExtract = DateTime.now();

      final raw = await browser.extractDocument();
      final extraction = extractDocument(
        raw,
        mode: captureMode,
        sourceUrl: pageUrl,
        fallbackTitle: pageTitle,
      );
      _time('extractText', tExtract);
      await _checkpoint();

      if (!extraction.isSuccess) {
        final failure =
            extraction.failure ?? DocumentExtractionFailure.noReadableContent;
        _log(
          'text extraction failed: ${failure.name} (${extraction.regionBasis})',
        );
        return EntrySaveResult(
          status: SaveStatus.failed,
          entryId: entryId,
          // Deliberately NOT `extractionFailed`: that flag routes the run into
          // "point at the reader area", which hands back images and cannot
          // help a page with no prose.
          documentFailure: failure,
          captureMode: captureMode,
          error: failure.message,
          pageUrl: pageUrl,
        );
      }

      var document = extraction.document!;
      _log(
        'document: ${document.blockCount} blocks, ${document.textLength} chars '
        'from ${extraction.regionBasis} '
        '(${extraction.droppedBlocks} blocks dropped'
        '${extraction.truncated ? ', TRUNCATED' : ''})',
      );

      // 2. Inline images ------------------------------------------------
      staging = await fileStore.beginEntry(
        collectionId: owningCollectionId,
        entryId: entryId,
      );

      final requests = extraction.imageRequests;
      final toFetch = requests.where((r) => r.needsFetch).toList();
      var assets = <EntryAsset>[
        for (final r in toFetch)
          EntryAsset(
            index: r.assetIndex,
            sourceUrl: r.url,
            status: AssetStatus.pending,
            width: r.width,
            height: r.height,
          ),
      ];

      if (assets.isNotEmpty) {
        _emit(
          (p) => p.copyWith(
            state: SaveState.fetchingAssets,
            detectedImages: assets.length,
            storedImages: 0,
            failedImages: 0,
            message: '${assets.length} images to fetch',
          ),
        );
        final tDownload = DateTime.now();
        assets = await _downloadAll(
          entries: assets,
          staging: staging,
          refererUrl: pageUrl,
          userAgent: await browser.userAgent(),
          cookieHeader: await browser.cookieHeaderFor(pageUrl),
        );
        _time('download', tDownload);
        await _checkpoint();
      } else if (captureMode == CaptureMode.textAndImages) {
        // Asked for, and there were none. Not a failure: the text is the
        // entry, and saying so is more useful than refusing to save it.
        _log('no meaningful inline images on this page — saving the text');
      }

      final storedIndexes = {
        for (final a in assets)
          if (a.isStored) a.index,
      };
      final failedImages = assets.length - storedIndexes.length;
      document = applyImageResults(
        document,
        requests: requests,
        storedAssetIndexes: storedIndexes,
      );

      // 3. Next entry, before we leave the page -------------------------
      _emit((p) => p.copyWith(state: SaveState.detectingNext));
      final next = await _resolveNext(
        probe: probe,
        pageUrl: pageUrl,
        visitedNormalized: visitedNormalized,
        nextHint: nextHint,
      );

      // 4. Write ---------------------------------------------------------
      _emit((p) => p.copyWith(state: SaveState.saving, message: 'Saving'));

      // Text present but an image missing is `partial`, exactly like a
      // half-downloaded image sequence: the entry opens and reads, and the
      // reader is told what is not there. Only a total absence of text is a
      // failure, and that was handled above.
      final status = failedImages == 0
          ? SaveStatus.complete
          : SaveStatus.partial;

      await staging.documentFile.writeAsString(document.encode(), flush: true);

      final shape = detectContentKind(probe);
      final manifest = EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.structuredDocument,
        captureMode: captureMode.name,
        captureModeIsUserSet: captureModeIsUserSet,
        document: DocumentRef(
          relativePath: FileStore.documentFileName,
          blockCount: document.blockCount,
          textLength: document.textLength,
        ),
        entryId: entryId,
        collectionId: owningCollectionId,
        sourceUrl: pageUrl,
        canonicalUrl: probe.canonicalUrl,
        title: pageTitle,
        savedAt: DateTime.now(),
        status: status,
        statusReason: failedImages == 0 ? null : 'assetsFailed:$failedImages',
        detectedAssetCount: assets.length,
        storedAssetCount: storedIndexes.length,
        nextUrl: next.chosen?.href,
        entryOrder: entryOrder,
        host: Uri.tryParse(pageUrl)?.host.toLowerCase(),
        contentKind: shape.kind.name,
        contentKindConfidence: shape.confidence.name,
        publishedAt: probe.content.publishedAt,
        assets: assets,
      );

      // Last gate before anything is committed — the document path's copy of
      // the same rule. See the image path for why the manifest's URL is what is
      // asked about.
      if (isCaptureRestricted(manifest.sourceUrl)) {
        await fileStore.discard(staging);
        staging = null;
        return _restrictedRefusal(entryId, manifest.sourceUrl)!;
      }

      final tCommit = DateTime.now();
      final relativePath = replaceExisting || existing?.contentPath != null
          ? await fileStore.commitReplacing(staging, manifest)
          : await fileStore.commit(staging, manifest);
      staging = null;

      final byteSize = await fileStore.entryByteSize(relativePath);
      final hints = probe.pageHints;
      final entryNumber = parseEntryNumber(
        title: pageTitle,
        url: pageUrl,
        extra: [
          hints.h1,
          hints.ogTitle,
          if (hints.breadcrumbs.isNotEmpty) hints.breadcrumbs.last.text,
        ],
      );
      final keepUserKind = existing?.contentKindIsUserSet == true;
      final carried = carryReading(existing, ArtifactFormat.structuredDocument);
      if (carried.anchorReset) {
        _log(
          're-saved as a document over a different format — reading position '
          'kept as a fraction, exact anchor reset',
        );
      }

      await db.upsertEntry(
        Entry(
          id: entryId,
          collectionId: owningCollectionId,
          title: pageTitle,
          sourceUrl: pageUrl,
          urlKey: normalizeUrl(pageUrl),
          canonicalUrl: probe.canonicalUrl,
          host: Uri.tryParse(pageUrl)?.host.toLowerCase() ?? '',
          sourceTitle: probe.title.trim().isEmpty ? null : probe.title.trim(),
          publishedAt: probe.content.publishedAt,
          contentKind: keepUserKind ? existing!.contentKind : shape.kind.name,
          contentKindConfidence: keepUserKind
              ? existing!.contentKindConfidence
              : shape.confidence.name,
          contentKindIsUserSet: keepUserKind,
          artifactFormat: ArtifactFormat.structuredDocument.name,
          captureMode: captureMode.name,
          saveStatus: status.name,
          contentPath: relativePath,
          savedAt: manifest.savedAt,
          detectedAssetCount: assets.length,
          storedAssetCount: storedIndexes.length,
          nextSourceUrl: next.chosen?.href,
          entryOrder: existing != null && existing.entryOrder > 0
              ? existing.entryOrder
              : entryOrder,
          saveError: failedImages == 0 ? null : '$failedImages image(s) failed',
          byteSize: byteSize,
          entryNumber: entryNumber,
          sourceMarker: sourceMarkerFrom(
            title: pageTitle,
            url: pageUrl,
            number: entryNumber,
          ),
          readStatus: carried.readStatus,
          progressFraction: carried.fraction,
          progressPageIndex: carried.pageIndex,
          progressOffsetInPage: carried.offsetInPage,
          firstOpenedAt: existing?.firstOpenedAt,
          lastReadAt: existing?.lastReadAt,
          completedAt: existing?.completedAt,
          progressUpdatedAt: existing?.progressUpdatedAt,
          discoveredAt: existing?.discoveredAt,
          discoveryBasis: existing?.discoveryBasis,
          discoveryConfidence: existing?.discoveryConfidence,
        ),
      );
      await db.clearOfflineRemovedMark(entryId);
      if (owningCollectionId != null) {
        await db.markCollectionSaved(owningCollectionId, manifest.savedAt);
      }

      _time('commit', tCommit);
      _log(
        'saved a ${captureMode.name} document: ${document.blockCount} blocks, '
        '${storedIndexes.length}/${assets.length} inline images -> '
        '$relativePath (${status.name})',
      );
      _log(
        '[timing] ${_timings.entries.map((e) => '${e.key}=${e.value}ms').join(' · ')}',
      );

      _emit(
        (p) => p.copyWith(
          state: status == SaveStatus.complete
              ? SaveState.complete
              : SaveState.partial,
          storedImages: storedIndexes.length,
          failedImages: failedImages,
          message: 'Saved ${document.blockCount} blocks of text',
        ),
      );

      return EntrySaveResult(
        status: status,
        entryId: entryId,
        manifest: manifest,
        nextUrl: next.hasNext ? next.chosen?.href : null,
        nextEvidence: next.chosen?.evidence,
        nextResult: next,
        captureMode: captureMode,
        pageUrl: pageUrl,
        detectedImages: assets.length,
        storedImages: storedIndexes.length,
      );
    } on SaveCancelled {
      if (staging != null) await fileStore.discard(staging);
      _emit(
        (p) => p.copyWith(state: SaveState.cancelled, message: 'Cancelled'),
      );
      return EntrySaveResult(
        status: SaveStatus.failed,
        entryId: entryId,
        error: 'cancelled',
      );
    } catch (e, stack) {
      if (staging != null) await fileStore.discard(staging);
      _log('document save error: $e\n$stack');
      return _fail(entryId, e.toString());
    }
  }

  /// Next-page resolution, shared by both save paths.
  Future<NextPageResult> _resolveNext({
    required PageProbe probe,
    required String pageUrl,
    required Set<String> visitedNormalized,
    UserPageHint? nextHint,
  }) async {
    String? hintHref;
    if (nextHint != null) {
      final match = await browser.applyLocator(nextHint.locator.toJson());
      if (match != null && match.isMatch) {
        hintHref = match.href;
        _log(
          'saved next-link rule matched (${match.matchedSignals}, '
          'score ${match.score}${match.ambiguous ? ", ambiguous" : ""})',
        );
      } else {
        _log(
          'saved next-link rule did not match: '
          '${match?.failureReason ?? "no result"}',
        );
      }
    }
    final next = resolveNextPage(
      probe,
      currentUrl: pageUrl,
      visitedNormalized: visitedNormalized,
      hintHref: hintHref,
    );
    if (next.needsUserSelection) {
      _log('next: not confident — ${next.reason}');
    } else if (next.hasNext) {
      _log(
        'next: ${next.chosen!.href} '
        'via ${next.chosen!.strategy.label} (${next.chosen!.evidence})',
      );
    } else {
      _log(
        'next: none (${next.considered.length} candidates considered, '
        '${next.rejection?.name ?? "no candidates"})',
      );
    }
    return next;
  }

  /// A refusal for a restricted address, or null when [url] is not restricted.
  ///
  /// Deliberately shaped as `nothingToSave` rather than a retryable failure:
  /// there is nothing to retry, nothing to assist with, and no amount of
  /// re-running changes the answer.
  EntrySaveResult? _restrictedRefusal(String entryId, String? url) {
    if (!isCaptureRestricted(url)) return null;
    _log(kCaptureRestrictedMessage);
    _emit(
      (p) => p.copyWith(
        state: SaveState.failed,
        lastError: StopReason.captureRestrictedForSite.name,
        message: kCaptureRestrictedMessage,
      ),
    );
    return EntrySaveResult(
      status: SaveStatus.failed,
      entryId: entryId,
      nothingToSave: true,
      error: kCaptureRestrictedMessage,
      pageUrl: url ?? '',
    );
  }

  EntrySaveResult _fail(String entryId, String reason) {
    _log('save failed: $reason');
    _emit(
      (p) => p.copyWith(
        state: SaveState.failed,
        lastError: reason,
        message: reason,
      ),
    );
    return EntrySaveResult(
      status: SaveStatus.failed,
      entryId: entryId,
      error: reason,
    );
  }

  // --- page readiness -----------------------------------------------------

  Future<PageProbe> _awaitDomReady(DateTime deadline) async {
    final domDeadline = DateTime.now().add(config.domReadyTimeout);
    PageProbe? last;
    while (DateTime.now().isBefore(domDeadline) &&
        DateTime.now().isBefore(deadline)) {
      await _checkpoint();
      try {
        final probe = await browser.probe(withSignals: false);
        last = probe;
        if (probe.domReady) return probe;
      } catch (_) {
        // The page may be mid-navigation; retry until the deadline.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (last != null) return last;
    throw StateError('Page never became inspectable');
  }

  /// Hold while the WebView surface is not being composited.
  ///
  /// Three independent checks, because no one of them is sufficient
  /// (docs/FOREGROUND_MULTITASKING.md §3.1):
  ///
  /// * **The app is not painting the WebView** ([BrowserController.surfaceIsPainted]).
  ///   The only portable answer. An unpainted WebView keeps a full viewport and
  ///   keeps scrolling on both platforms, but its `requestAnimationFrame` stops
  ///   (iOS) or is throttled to a fifth of the display rate (Android), which is
  ///   how a page's lazy content silently fails to arrive.
  /// * **Zero viewport.** The original check. Still true for a WebView that has
  ///   never been laid out, and cheap to keep.
  /// * **The page says it is hidden.** True on iOS for an unpainted surface, and
  ///   true on both when the app is not in the foreground. Never read the other
  ///   way round: `visible` proves nothing.
  ///
  /// The engine waits (checkpointing for cancel), and the waited time is *added
  /// back* to the entry deadline: the page did not get slower, the user just
  /// looked away.
  Future<void> _waitForRenderedSurface(String phase) async {
    var warned = false;
    final waitStart = DateTime.now();
    while (true) {
      await _checkpoint();
      PageProbe probe;
      try {
        probe = await browser.probe(withSignals: false);
      } catch (_) {
        // Mid-navigation; the caller's own probe loop handles that case.
        return;
      }
      final hold = surfaceHoldReason(
        surfaceIsPainted: browser.surfaceIsPainted,
        pageHidden: probe.pageHidden,
        viewportHeight: probe.viewportHeight,
        heldFor: DateTime.now().difference(waitStart),
      );
      if (hold == null) {
        if (warned && probe.pageHidden) {
          _log(
            'the page still calls itself hidden, but the app is drawing it — '
            'continuing (a document created behind another screen keeps the '
            'visibility it was born with)',
          );
        }
        if (warned) {
          final waited = DateTime.now().difference(waitStart);
          _deadline = _deadline.add(waited);
          _time('browserWait', waitStart);
          _log(
            'browser surface is back after ${waited.inSeconds}s — resuming '
            '($phase)',
          );
        }
        return;
      }
      if (!warned) {
        warned = true;
        _log(
          'browser surface: ${surfaceHoldMessage(hold)} — holding the $phase '
          'phase',
        );
        _emit(
          (p) => p.copyWith(
            state: SaveState.waitingForBrowser,
            message: 'Open the Browser to continue save.',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Pending images that could plausibly be entry content. A comment-box
  /// avatar that never loads must not hold the save for the full asset
  /// wait — but a pending image with a content-sized box (or no measurable
  /// size at all, which is unknowable and therefore treated as relevant)
  /// still does.
  ///
  /// The test is [couldBeContent], the same one final selection is built on.
  /// This used to carry its own threshold — 0.7 of the size floor, on *either*
  /// edge — which admitted images the save would then reject: a 300x250
  /// advertisement slot cleared the loosened width test and held the entry for
  /// the whole of [SaveConfig.maxAssetWait] before being discarded as too
  /// small.
  ///
  /// A **broken** image is not pending. It has finished, badly, and it stays a
  /// candidate so its download fails explicitly and the entry is marked
  /// partial — waiting for it would only spend the timeout.
  /// An image whose lazy source has not been switched on is deliberately NOT
  /// counted: nothing is on the wire, so waiting cannot produce it. Only
  /// scrolling to it can, which is why it is the fast-mode lookahead that has
  /// to see it and this count that must not.
  int _relevantPendingCount(PageProbe probe) => probe.images
      .where((i) => couldBeContent(i, config: config) && i.isPending)
      .length;

  /// Track the best candidate set seen while traversing, for the collapse
  /// guard at extraction time.
  void _trackPeak(PageProbe probe) {
    final selection = selectImageCandidates(probe.images, config: config);
    if (selection.acceptedCount > _peakAccepted) {
      _peakAccepted = selection.acceptedCount;
    }
    for (final c in selection.accepted) {
      if (c.height > _peakPanelHeight) _peakPanelHeight = c.height;
    }
  }

  /// Scroll, watching for growth and lazy loads, and stop only when the page
  /// has been quiet for [SaveConfig.quietPeriod] at the bottom.
  ///
  /// A second downward pass runs when the first one revealed new images: many
  /// lazy loaders only fire when an element is scrolled *into* view from
  /// above, so a first pass that outran the loader leaves holes.
  Future<PageProbe> _scrollUntilStable(PageProbe initial) async {
    var probe = initial;
    var pass = 0;
    var previousImageCount = probe.images.length;

    while (pass < config.maxScrollPasses) {
      pass++;
      _log('scroll pass $pass');
      probe = await _scrollPass(probe, pass);
      await _checkpoint();

      probe = await _waitForPendingAssets();
      await _checkpoint();

      final grew = probe.images.length > previousImageCount;
      previousImageCount = probe.images.length;
      if (!grew) break;

      if (pass < config.maxScrollPasses) {
        await browser.scrollTo(0);
        await Future<void>.delayed(config.scrollDelay);
      }
    }
    return probe;
  }

  /// One downward pass, paced by evidence.
  ///
  /// **Careful** (the original 0.8-viewport / 300 ms pace) whenever anything
  /// within [SaveConfig.lookaheadViewports] below the position is still
  /// loading, the document height moved, or the bottom is near. **Fast**
  /// ([SaveConfig.fastScrollStepViewports] per step,
  /// [SaveConfig.fastScrollDelay]) after
  /// [SaveConfig.fastModeAfterStableProbes] consecutive probes with a
  /// fully-resolved lookahead — the audit measured scrolling at 90–98% of
  /// save time on pages whose content was already loaded.
  ///
  /// The stopping condition is untouched: at bottom, quiet for
  /// [SaveConfig.quietPeriod], [SaveConfig.requiredStableChecks] times.
  Future<PageProbe> _scrollPass(PageProbe start, int pass) async {
    _emit(
      (p) => p.copyWith(
        state: SaveState.scrolling,
        message: 'Scrolling (pass $pass)',
      ),
    );

    var probe = start;
    var stableChecks = 0;
    var iterations = 0;
    var lastStability = measureStability(probe, config: config);
    var lastChangeAt = DateTime.now();
    var lastDocHeight = probe.documentHeight;
    var resolvedStreak = 0;
    var frozenSteps = 0;
    var fastSteps = 0;

    while (iterations < config.maxScrollIterations) {
      await _checkpoint();
      if (DateTime.now().isAfter(_deadline)) {
        _log('scroll pass $pass hit the save deadline');
        break;
      }
      iterations++;

      // Unrendered surface: hold instead of issuing scrolls into the void.
      if (probe.viewportHeight <= 0) {
        await _waitForRenderedSurface('scroll');
        _emit(
          (p) => p.copyWith(
            state: SaveState.scrolling,
            message: 'Scrolling (pass $pass)',
          ),
        );
        probe = await browser.probe(withSignals: false);
        lastChangeAt = DateTime.now();
        continue;
      }

      // Fast when everything within the lookahead is resolved and the layout
      // is standing still; careful otherwise, and always near the bottom.
      // The lookahead must cover the whole prospective jump PLUS a margin —
      // a 3.5-viewport leap cleared by a 2-viewport check would sail past a
      // lazy trigger sitting between the two.
      final viewport = probe.viewportHeight;
      final lookahead =
          probe.scrollY +
          viewport *
              (1 + config.fastScrollStepViewports + config.lookaheadViewports);
      // Only an image that could be *entry content* is worth slowing down for.
      // The test was any unresolved image with a URL, which handed the pace of
      // a save to whatever advertisement, avatar or decorative asset happened
      // to sit in the next few viewports — none of which final selection would
      // keep. An image with no measurable size still qualifies: unknown is not
      // the same as small, and the careful pace is the right answer when the
      // page has not told us yet.
      //
      // "Unsettled" covers both an image still arriving and one whose lazy
      // source has not been switched on at all. The second used to read as
      // broken — nothing coming, nothing to wait for — which let a fast jump
      // clear a region whose panels had never been asked for, so the loader
      // that would have produced them never fired.
      final unresolvedNear = probe.images.any(
        (i) =>
            couldBeContent(i, config: config) &&
            i.isUnsettled &&
            i.documentTop < lookahead,
      );
      final heightMoved = probe.documentHeight != lastDocHeight;
      lastDocHeight = probe.documentHeight;
      final distanceToBottom =
          probe.documentHeight - (probe.scrollY + viewport);
      final nearBottom =
          distanceToBottom < viewport * config.lookaheadViewports;

      if (!unresolvedNear && !heightMoved && !nearBottom) {
        resolvedStreak++;
      } else {
        resolvedStreak = 0;
      }
      final fast = resolvedStreak >= config.fastModeAfterStableProbes;
      if (fast) fastSteps++;

      final step = fast
          ? (viewport * config.fastScrollStepViewports).round()
          : (viewport * config.scrollStepFraction).round();
      final yBefore = probe.scrollY;
      await browser.scrollStep(step < 100 ? 400 : step);
      await Future<void>.delayed(
        fast ? config.fastScrollDelay : config.scrollDelay,
      );

      probe = await browser.probe(withSignals: false);
      _trackPeak(probe);

      // Scroll commands that move nothing: with a rendered viewport this is
      // a page quirk — stop the pass and let extraction (and its collapse
      // guard) judge what actually loaded, instead of spinning the bound.
      if (probe.scrollY == yBefore && !probe.atBottom) {
        frozenSteps++;
        if (probe.viewportHeight <= 0) continue; // handled at loop top
        if (frozenSteps >= 6) {
          _log(
            'scroll pass $pass: position frozen at ${probe.scrollY} for '
            '$frozenSteps steps — stopping the pass',
          );
          break;
        }
      } else {
        frozenSteps = 0;
      }

      // Change is judged over the images that could be entry content, plus the
      // page's height and total image count — see save/page_stability.dart. A
      // decorative image cycling at the bottom of the page used to reset this
      // on every probe, which is how a settled entry could run to the save
      // deadline without anything readable having changed.
      final stability = measureStability(probe, config: config);
      if (stability != lastStability) {
        lastStability = stability;
        lastChangeAt = DateTime.now();
        stableChecks = 0;
      }

      final percent = probe.documentHeight == 0
          ? 0.0
          : ((probe.scrollY + probe.viewportHeight) / probe.documentHeight)
                .clamp(0.0, 1.0);
      _emit(
        (p) => p.copyWith(
          scrollPercent: percent,
          detectedImages: probe.images.length,
          message:
              'Scrolling (pass $pass) · '
              '${probe.resolvedImageCount}/${probe.images.length} images',
        ),
      );

      // Quiescence is judged on *change*, not on everything having succeeded.
      // A broken image never resolves, so requiring zero pending images here
      // would spin until the iteration bound.
      final quietFor = DateTime.now().difference(lastChangeAt);
      if (probe.atBottom && quietFor >= config.quietPeriod) {
        stableChecks++;
        if (stableChecks >= config.requiredStableChecks) {
          _log(
            'stable after $iterations steps '
            '($fastSteps fast, ${probe.images.length} images, '
            'height ${probe.documentHeight}, '
            '${probe.pendingImageCount} pending, '
            '${probe.brokenImageCount} broken)',
          );
          break;
        }
      } else if (probe.atBottom) {
        // At the bottom but not yet quiet — hold position and keep watching.
        await Future<void>.delayed(config.scrollDelay);
      }
    }

    if (iterations >= config.maxScrollIterations) {
      _log(
        'scroll pass $pass stopped at the iteration bound '
        '(possible infinite scroll)',
      );
    }
    return probe;
  }

  /// Every `<img>` on the settled page, not just the first sliceful.
  ///
  /// The bridge caps how many image records one call returns, because a
  /// probe's cost scales with the records it serialises and the scroll loop
  /// takes one per step. That cap is right for traversal and wrong for the
  /// one probe that decides what gets saved: stopping there produced an entry
  /// holding the page's first N images and calling it complete.
  ///
  /// So this walks the remaining slices. Termination is guaranteed three ways
  /// over — the offset strictly increases, a slice that returns nothing ends
  /// the loop, and the total is bounded by
  /// [SaveConfig.maxEnumeratedImages] — and every turn checkpoints for
  /// cancellation and honours the entry deadline.
  ///
  /// Images are keyed by their index in the page's own collection, so a repeat
  /// or an overlap cannot double-count and the reassembled list is in document
  /// order, which is reading order.
  Future<_ImageEnumeration> _enumerateImages(PageProbe settled) async {
    if (!settled.imagesTruncated) {
      return _ImageEnumeration(
        images: settled.images,
        total: settled.imageCount == 0
            ? settled.images.length
            : settled.imageCount,
        isComplete: true,
      );
    }

    final byIndex = <int, PageImage>{
      for (final image in settled.images) image.domIndex: image,
    };
    var total = settled.imageCount;
    var offset = settled.imageOffset + settled.images.length;
    var truncated = true;
    var mutated = false;

    _log(
      'the page holds $total image(s), more than one probe returns — '
      'reading the rest',
    );

    while (truncated && byIndex.length < config.maxEnumeratedImages) {
      await _checkpoint();
      if (DateTime.now().isAfter(_deadline)) {
        _log('image enumeration hit the save deadline at ${byIndex.length}');
        break;
      }

      final PageProbe slice;
      try {
        slice = await browser.probeImageSlice(offset);
      } catch (e) {
        _log('image enumeration failed at offset $offset: $e');
        break;
      }
      if (slice.images.isEmpty) break; // no progress: stop rather than spin

      // The page grew or shrank between slices. Recorded, not fought: the
      // count below decides honestly whether everything was seen.
      if (slice.imageCount != total) {
        mutated = true;
        total = slice.imageCount;
      }
      for (final image in slice.images) {
        byIndex[image.domIndex] = image;
      }
      offset = slice.imageOffset + slice.images.length;
      truncated = slice.imagesTruncated;
    }

    final ordered = byIndex.keys.toList()..sort();
    final images = [for (final i in ordered) byIndex[i]!];
    final complete = !truncated && images.length >= total;
    _log(
      'enumerated ${images.length}/$total image(s)'
      '${complete ? '' : ' — INCOMPLETE'}'
      '${mutated ? ' (the page changed while reading)' : ''}',
    );
    return _ImageEnumeration(
      images: images,
      total: total,
      isComplete: complete,
    );
  }

  Future<PageProbe> _waitForPendingAssets() async {
    _emit((p) => p.copyWith(state: SaveState.waitingForAssets));
    final assetDeadline = DateTime.now().add(config.maxAssetWait);
    var probe = await browser.probe(withSignals: false);

    // Wait only for images that could be content. A comments-section avatar
    // stuck in "loading" forever is not a reason to hold the entry for
    // [SaveConfig.maxAssetWait].
    var relevant = _relevantPendingCount(probe);
    while (relevant > 0 &&
        DateTime.now().isBefore(assetDeadline) &&
        DateTime.now().isBefore(_deadline)) {
      await _checkpoint();
      _emit((p) => p.copyWith(message: '$relevant image(s) still loading'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      probe = await browser.probe(withSignals: false);
      relevant = _relevantPendingCount(probe);
    }

    final irrelevant = probe.pendingImageCount - relevant;
    if (relevant > 0) {
      _log('$relevant content image(s) never finished loading');
    }
    if (irrelevant > 0) {
      _log('$irrelevant unrelated image(s) still pending — not waiting');
    }
    if (probe.brokenImageCount > 0) {
      // Not fatal here: a broken image stays a candidate so its download fails
      // explicitly and the entry is marked partial, rather than the page
      // quietly shrinking by one.
      _log('${probe.brokenImageCount} image(s) failed to load in the page');
    }
    return probe;
  }

  // --- downloads ----------------------------------------------------------

  Future<List<EntryAsset>> _downloadAll({
    required List<EntryAsset> entries,
    required StagingHandle staging,
    required String refererUrl,
    String? userAgent,
    String? cookieHeader,
  }) async {
    final results = List<EntryAsset>.from(entries);
    var completed = 0;
    var failed = 0;
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        await _checkpoint();
        final index = cursor;
        if (index >= results.length) return;
        cursor++;

        final result = await downloader.download(
          entry: results[index],
          staging: staging,
          refererUrl: refererUrl,
          userAgent: userAgent,
          cookieHeader: cookieHeader,
        );
        results[index] = result;

        if (result.isStored) {
          completed++;
        } else {
          failed++;
          _log('asset ${result.index} failed: ${result.error}');
        }
        _emit(
          (p) => p.copyWith(
            storedImages: completed,
            failedImages: failed,
            message: 'Downloaded $completed/${results.length}',
          ),
        );
      }
    }

    await Future.wait([
      for (var i = 0; i < config.downloadConcurrency; i++) worker(),
    ]);
    return results;
  }
}

/// The collection that owns entries saved from [url] — or **null**, when this
/// page is a standalone entry.
///
/// Null is the normal answer for a single saved article. A collection is created
/// only when [sequence] says the page is part of one, so a one-off save never
/// produces a group of one in the library.
Future<Collection?> ensureCollection({
  required AppDatabase db,
  required String url,
  required String title,
  required SequenceShape sequence,
  PageHints hints = const PageHints(),
  void Function(String)? log,
  Future<String?> Function(NewCollectionProposal)? confirmNewName,
}) => CollectionRepository(db).resolveCollection(
  entryUrl: url,
  pageTitle: title,
  sequence: sequence,
  hints: hints,
  log: log,
  confirmNewName: confirmNewName,
);
