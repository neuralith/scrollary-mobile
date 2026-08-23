/// Capture, retargeted to `(Entry, Location)` and writing an OfflineCopy
/// (roadmap E2).
///
/// V1 captured a URL and wrote a library row: the address *was* the Entry, and
/// `save_status`, `content_path`, `byte_size` and `artifact_format` were
/// columns on it. V2 separates the two. The Entry is in the library because
/// somebody wants to read it; whether **this device** holds its bytes is an
/// OfflineCopy, and this file is the only thing that creates one.
///
/// The order of operations is the whole design, and it is V1's:
///
/// 1. **Ask the restricted-site policy**, before anything is read, staged or
///    fetched. A refusal returns here, above every other step.
/// 2. Open staging and hand it to a [PageCaptureSource], which owns everything
///    that touches the page — including the landed-URL boundary, because only
///    the thing that navigates knows where it ended up.
/// 3. Turn what came back into a manifest.
/// 4. **Ask the policy again, about the manifest's own `sourceUrl`** — the
///    address this package claims to be a copy of, which is not necessarily
///    the one the task named. A refusal here discards the staged tree, so no
///    file, no manifest and no row survives it.
/// 5. Commit atomically through the ported FileStore, and only then record the
///    copy, with provenance stored as values (V2-D22).
///
/// The policy judges **pages, never assets**. Both checks above run against a
/// page address; neither the asset fetcher nor any image `src` is ever asked
/// about, which is why `asset_fetcher.dart` does not import the policy at all.
library;

import '../data/collection_repository.dart';
import '../data/data_ids.dart';
import '../data/entry_repository.dart';
import '../data/offline_copy_repository.dart';
import '../domain/offline_copy.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';
import 'capture_mode.dart';
import 'capture_policy.dart';
import 'page_capture_source.dart';
import 'page_hint.dart';
import 'stop_conditions.dart';

/// How a capture ended.
enum EntryCaptureStatus {
  /// Bytes are on disk and an OfflineCopy names them.
  captured,

  /// The app withheld capture. Not something the site did — see
  /// `capture_policy.dart`.
  refused,

  /// Something else stopped it. Nothing was committed.
  failed,
}

/// The result of capturing one Entry at one Location.
class EntryCaptureResult {
  const EntryCaptureResult._({
    required this.status,
    this.copy,
    this.manifest,
    this.contentPath,
    this.byteSize = 0,
    this.stopReason,
    this.message,
    this.error,
    this.needsReaderAreaAssist = false,
  });

  const EntryCaptureResult.captured({
    required OfflineCopy copy,
    required EntryManifest manifest,
    required String contentPath,
    required int byteSize,
  }) : this._(
         status: EntryCaptureStatus.captured,
         copy: copy,
         manifest: manifest,
         contentPath: contentPath,
         byteSize: byteSize,
       );

  /// The one user-facing sentence, and the app's own named reason. Terminal:
  /// nothing retries it, and nothing was deleted to produce it.
  const EntryCaptureResult.refused()
    : this._(
        status: EntryCaptureStatus.refused,
        stopReason: StopReason.captureRestrictedForSite,
        message: kCaptureRestrictedMessage,
      );

  const EntryCaptureResult.failed(
    String error, {
    StopReason? stopReason,
    bool needsReaderAreaAssist = false,
  }) : this._(
         status: EntryCaptureStatus.failed,
         error: error,
         stopReason: stopReason,
         needsReaderAreaAssist: needsReaderAreaAssist,
       );

  final EntryCaptureStatus status;

  /// The copy that now names the bytes. Null unless [status] is
  /// [EntryCaptureStatus.captured].
  final OfflineCopy? copy;
  final EntryManifest? manifest;

  /// Relative to the store root. Absolute paths are never stored: the iOS
  /// app-container path contains a UUID that changes between installs.
  final String? contentPath;
  final int byteSize;

  final StopReason? stopReason;
  final String? message;
  final String? error;

  /// The page held too little for automatic image extraction, or a saved
  /// reader-area rule stopped matching. Carried up untouched from the
  /// [PageCaptureSource]: whoever has a user to ask decides what to do with
  /// it, and this file never asks anything of anyone.
  final bool needsReaderAreaAssist;

  bool get isCaptured => status == EntryCaptureStatus.captured;
  bool get isRefused => status == EntryCaptureStatus.refused;
}

/// Provenance as values, copied at capture (V2-D22).
///
/// Not references: a Source can die and a Location can be retracted without
/// orphaning a copy already on a device, and the copy can still say where it
/// came from.
class CaptureProvenance {
  const CaptureProvenance({
    required this.locationUrl,
    this.sourceName = '',
    this.sourceHost = '',
    this.sourceLanguage = '',
    this.sourceLabel = '',
    this.sourceNumber,
  });

  final String locationUrl;

  /// The name of the work as published on this Source. A Source carries no
  /// name of its own — identity is `(host, path_key)` — so this is the
  /// Collection's name, which is what a person would call it.
  final String sourceName;
  final String sourceHost;
  final String sourceLanguage;

  /// What the Source printed for this Entry, and the number it carried, kept
  /// verbatim as evidence. Written into the manifest so a recovered package
  /// can still say what the site called it.
  final String sourceLabel;
  final double? sourceNumber;
}

/// Reads the provenance of `(entry, location)` out of the library, falling
/// back to what the address itself says.
///
/// A standalone Entry has no Source, and that is an ordinary case rather than
/// missing data: the host comes from the URL and the rest is genuinely empty.
Future<CaptureProvenance> resolveCaptureProvenance({
  required EntryRepository entries,
  required CollectionRepository collections,
  required String locationUrl,
  String? locationId,
}) async {
  final urlHost = Uri.tryParse(locationUrl)?.host.toLowerCase() ?? '';
  final location = locationId == null
      ? null
      : await entries.locationById(locationId);
  if (location == null) {
    return CaptureProvenance(locationUrl: locationUrl, sourceHost: urlHost);
  }
  final sourceId = location.sourceId;
  final source = sourceId == null
      ? null
      : await collections.sourceById(sourceId);
  final collection = source == null
      ? null
      : await collections.byId(source.collectionId);
  return CaptureProvenance(
    locationUrl: location.url,
    sourceName: collection?.name ?? '',
    sourceHost: source?.host ?? urlHost,
    sourceLanguage: source?.language ?? '',
    sourceLabel: location.sourceLabel,
    sourceNumber: location.sourceNumber,
  );
}

/// Captures one Entry, at one Location, into an OfflineCopy.
class EntryCaptureService {
  EntryCaptureService({
    required this.entries,
    required this.collections,
    required this.offlineCopies,
    required this.fileStore,
    required this.source,
    Clock? now,
  }) : _now = now ?? utcNow;

  final EntryRepository entries;
  final CollectionRepository collections;
  final OfflineCopyRepository offlineCopies;
  final FileStore fileStore;
  final PageCaptureSource source;
  final Clock _now;

  /// Capture [locationUrl] for [entryId].
  ///
  /// [captureMode] is **required and may be null**, deliberately: null means
  /// "decide from the settled page", which is a decision made where the
  /// measurement is, and there is no default about what to take off someone
  /// else's site.
  Future<EntryCaptureResult> capture({
    required String entryId,
    required String locationUrl,
    required CaptureMode? captureMode,
    String? locationId,
    bool captureModeIsUserSet = false,
    bool Function()? shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,

    /// True when this run has just opened [locationUrl] and the browser is
    /// still on it — the sequential capture of a Source (V2-D56). Passed
    /// straight through: whether a loaded page may be captured where it stands
    /// is the navigator's judgement, not this pipeline's.
    bool pageAlreadyLoaded = false,
  }) async {
    final carryOn = shouldContinue ?? () => true;

    // 1. The policy, before anything is read from the page. Nothing has been
    //    probed, measured or staged at this point, and nothing will be.
    if (isCaptureRestricted(locationUrl)) {
      return const EntryCaptureResult.refused();
    }

    final entry = await entries.byId(entryId);
    if (entry == null) {
      return const EntryCaptureResult.failed(
        'that entry is not in the library',
      );
    }
    if (!carryOn()) {
      return const EntryCaptureResult.failed(
        'cancelled',
        stopReason: StopReason.cancelledByUser,
      );
    }

    final provenance = await resolveCaptureProvenance(
      entries: entries,
      collections: collections,
      locationUrl: locationUrl,
      locationId: locationId,
    );

    // 2. Staging. Nothing outside `tmp/` exists until the commit below.
    final staging = await fileStore.beginEntry(
      collectionId: entry.collectionId,
      entryId: entryId,
    );

    PageCaptureOutcome outcome;
    try {
      outcome = await source.capturePage(
        url: locationUrl,
        staging: staging,
        requestedMode: captureMode,
        shouldContinue: carryOn,
        // Straight through, unchanged. A rule exists only because a person
        // tapped an element, and nothing on this path may invent one.
        readerHint: readerHint,
        nextHint: nextHint,
        pageAlreadyLoaded: pageAlreadyLoaded,
      );
    } catch (e) {
      await fileStore.discard(staging);
      return EntryCaptureResult.failed(e.toString());
    }

    if (!outcome.isCaptured) {
      await fileStore.discard(staging);
      if (outcome.isRestricted) return const EntryCaptureResult.refused();
      return EntryCaptureResult.failed(
        outcome.error ?? outcome.stopReason?.name ?? 'the capture failed',
        stopReason: outcome.stopReason,
        needsReaderAreaAssist: outcome.needsReaderAreaAssist,
      );
    }

    // 3. The manifest. Every judgement in it was made where the page was
    //    measured; nothing is re-derived here.
    final manifest = EntryManifest(
      schemaVersion: EntryManifest.currentSchemaVersion,
      artifact: outcome.artifact,
      captureMode: outcome.captureMode?.name,
      // Null rather than false: the manifest omits the field entirely unless
      // a person chose the mode, so "detection picked it" and "nobody has
      // said" stay one value rather than two.
      captureModeIsUserSet:
          (outcome.captureModeIsUserSet || captureModeIsUserSet) ? true : null,
      document: outcome.document,
      entryId: entryId,
      collectionId: entry.collectionId,
      sourceUrl: outcome.pageUrl,
      host: Uri.tryParse(outcome.pageUrl)?.host.toLowerCase(),
      canonicalUrl: outcome.canonicalUrl,
      title: outcome.title,
      savedAt: _now(),
      status: outcome.status,
      statusReason: outcome.statusReason,
      detectedAssetCount: outcome.detectedAssetCount,
      storedAssetCount: outcome.storedAssetCount,
      nextUrl: outcome.nextUrl,
      contentKind: outcome.contentKind,
      contentKindConfidence: outcome.contentKindConfidence,
      publishedAt: outcome.publishedAt,
      sourceMarker: provenance.sourceLabel.isEmpty
          ? null
          : provenance.sourceLabel,
      entryNumber: provenance.sourceNumber,
      assets: outcome.assets,
    );

    // 4. The last gate. The manifest names the address this package claims to
    //    be a copy of — a redirect can have landed somewhere else — so that is
    //    what the policy is asked about, not the one the task named. A refusal
    //    discards the staged tree and writes no row, no file and no manifest.
    if (isCaptureRestricted(manifest.sourceUrl)) {
      await fileStore.discard(staging);
      return const EntryCaptureResult.refused();
    }

    // 5. Commit, then record. Replacing keeps the old package until the new
    //    one is safely in place, so a failed re-capture leaves a readable copy
    //    exactly as it was.
    final relative = FileStore.entryRelativePath(entry.collectionId, entryId);
    final String contentPath;
    try {
      contentPath = fileStore.entryExists(relative)
          ? await fileStore.commitReplacing(staging, manifest)
          : await fileStore.commit(staging, manifest);
    } catch (e) {
      await fileStore.discard(staging);
      return EntryCaptureResult.failed(e.toString());
    }

    final byteSize = await fileStore.entryByteSize(contentPath);
    final copy = await offlineCopies.recordCopy(
      entryId: entryId,
      locationUrl: provenance.locationUrl,
      sourceName: provenance.sourceName,
      sourceHost: provenance.sourceHost,
      sourceLanguage: provenance.sourceLanguage,
      capturedAt: manifest.savedAt,
      artifactFormat: manifest.artifact.name,
      contentPath: contentPath,
      byteSize: byteSize,
    );

    return EntryCaptureResult.captured(
      copy: copy,
      manifest: manifest,
      contentPath: contentPath,
      byteSize: byteSize,
    );
  }
}

/// Free this device's copy of an Entry: the package, then the rows.
///
/// **Removing a copy is never removing an Entry.** The Entry, its Locations,
/// its reading state and every measurement are untouched — the Entry is in the
/// library because somebody wants to read it, not because bytes were
/// downloaded. Nothing about this synchronises, and nothing here can be
/// triggered by a remote mutation (I14): the space is freed *here only*
/// (V2_SYNC.md §5).
///
/// Files first, rows second. The reverse order would leave a package under
/// `library/` that a future recovery pass would rebuild an Entry from.
/// Returns how many copy rows were removed.
Future<int> removeOfflineCopies({
  required String entryId,
  required OfflineCopyRepository offlineCopies,
  required FileStore fileStore,
}) async {
  for (final copy in await offlineCopies.allCopies()) {
    if (copy.entryId != entryId) continue;
    await fileStore.deleteEntryContent(copy.contentPath);
  }
  return offlineCopies.removeCopies(entryId);
}
