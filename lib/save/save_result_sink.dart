/// Where a finished capture goes — the one thing the save engine does not
/// decide for itself.
///
/// **Why this exists.** Everything the engine does to *someone else's site* —
/// the render guards, the paced scroll passes, lazy-image settling,
/// enumeration, detection, extraction, the decode decisions, the stopping
/// conditions — is device knowledge that was paid for on hardware and is
/// frozen (docs/V2_PORT_CHECKLIST.md). Everything it did *afterwards* was V1's
/// library: open staging under the store, commit the package, look the row up
/// by `url_key`, write it back. That tail is ordinary logic, and it is the
/// only part of a save a V2 host needs to replace.
///
/// So the tail is a seam and nothing else moves. The one implementation left
/// is [StagedPackageSink]: the engine stops at *the package is staged and
/// here is what it holds*, which is what lets `entry_capture.dart` run its own
/// policy gate before the commit and record an OfflineCopy. The default that
/// used to sit here wrote four V1 library rows; it retired with that library,
/// and with it the last thing in this lane that could build one.
///
/// [CapturedEntry] is what the seam carries. It was V1's `Entry` row, and the
/// fields are the same fields with the same names for the same reason the
/// commit order is the same one: this is a description of *what a capture
/// produced*, and the engine's phases are frozen. What changed is only that
/// the description is now this lane's own value rather than another schema's
/// row — a sink that keeps a library maps it, and the one that keeps a
/// package ignores it.
///
/// The sink is told about the result; it never judges it. Nothing here may
/// measure a page, decide a capture mode, or turn a `partial` into a
/// `complete`.
library;

import '../storage/file_store.dart';
import '../storage/manifest.dart';

/// What one capture produced, as the engine describes it to its sink.
///
/// Every field is one the engine sets or one [carryReading] reads back off a
/// previous capture of the same address; nothing here is derived, and nothing
/// here is a database concept. A sink that has no library to re-save over
/// answers null to [SaveResultSink.findExistingEntry], and then the carried
/// halves are simply their defaults.
class CapturedEntry {
  const CapturedEntry({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.urlKey,
    required this.host,
    required this.contentKind,
    required this.contentKindConfidence,
    required this.contentKindIsUserSet,
    required this.artifactFormat,
    required this.saveStatus,
    required this.savedAt,
    this.collectionId,
    this.canonicalUrl,
    this.sourceTitle,
    this.publishedAt,
    this.captureMode,
    this.contentPath,
    this.detectedAssetCount = 0,
    this.storedAssetCount = 0,
    this.nextSourceUrl,
    this.entryOrder = 0,
    this.saveError,
    this.byteSize = 0,
    this.entryNumber,
    this.sourceMarker,
    this.readStatus = 'unread',
    this.progressFraction = 0,
    this.progressPageIndex = 0,
    this.progressOffsetInPage = 0,
    this.firstOpenedAt,
    this.lastReadAt,
    this.completedAt,
    this.progressUpdatedAt,
    this.discoveredAt,
    this.discoveryBasis,
    this.discoveryConfidence,
  });

  final String id;
  final String? collectionId;
  final String title;
  final String sourceUrl;
  final String urlKey;
  final String? canonicalUrl;
  final String host;
  final String? sourceTitle;
  final DateTime? publishedAt;

  final String contentKind;
  final String contentKindConfidence;
  final bool contentKindIsUserSet;

  final String artifactFormat;
  final String? captureMode;
  final String saveStatus;
  final String? contentPath;
  final DateTime savedAt;
  final int detectedAssetCount;
  final int storedAssetCount;
  final String? nextSourceUrl;
  final int entryOrder;
  final String? saveError;
  final int byteSize;
  final double? entryNumber;
  final String? sourceMarker;

  /// Reading state, carried across a re-save and never rebuilt.
  final String readStatus;
  final double progressFraction;
  final int progressPageIndex;
  final double progressOffsetInPage;
  final DateTime? firstOpenedAt;
  final DateTime? lastReadAt;
  final DateTime? completedAt;
  final DateTime? progressUpdatedAt;

  /// Discovery history, when an update check introduced this address first.
  final DateTime? discoveredAt;
  final String? discoveryBasis;
  final String? discoveryConfidence;
}

/// The save engine's final phase, injected.
abstract interface class SaveResultSink {
  /// Open the staging directory this capture fills.
  ///
  /// Nothing outside `tmp/` exists until [commitEntry], and a refused page
  /// never gets this far — both restricted-site checks run above it, which is
  /// what keeps the asset fetcher out of the policy entirely.
  Future<StagingHandle> beginEntry({
    required String? collectionId,
    required String entryId,
  });

  /// The entry this capture would replace, looked up by normalised URL across
  /// every collection and the standalone entries — or null when the caller
  /// keeps no such library.
  ///
  /// A null answer means "nothing to re-save over": the capture keeps the id
  /// it minted, carries no reading state, and commits as a new package.
  Future<CapturedEntry?> findExistingEntry(String urlKey);

  /// Commit the staged package, and return the path recorded in the library —
  /// or **null** to leave it staged.
  ///
  /// Null is not a failure. It is a caller saying *the commit is mine*: the
  /// staged tree is left exactly as it is, and the engine hands back what it
  /// holds without writing a byte outside `tmp/`. Whoever answers null owns
  /// the staging directory from that moment, including discarding it.
  ///
  /// [replacing] carries the engine's own answer to "is there a copy here
  /// already", so a replacement still keeps the old package until the new one
  /// is safely in place.
  Future<String?> commitEntry(
    StagingHandle staging,
    EntryManifest manifest, {
    required bool replacing,
  });

  /// Record the finished entry.
  ///
  /// [collectionId] is null for a standalone entry, which has no collection to
  /// stamp — the entry's own `savedAt` is the whole record.
  Future<void> recordEntry(
    CapturedEntry entry, {
    required String? collectionId,
    required DateTime savedAt,
  });
}

/// The other end of the seam: a capture that stops at *the package is staged*.
///
/// It fills the staging directory the caller opened, answers "nothing here
/// already" to the re-save lookup, and keeps the package staged. **No database
/// is touched, because there is none to touch.**
///
/// Leaving the package staged is the point: the pre-commit restricted-site
/// gate and the atomic commit belong to `entry_capture.dart`, which asks the
/// policy about the address the manifest claims to be a copy of and only then
/// commits. Whoever passes this sink owns [staging] from the moment the engine
/// returns, discard included.
class StagedPackageSink implements SaveResultSink {
  const StagedPackageSink(this.staging);

  /// The directory the capture fills — opened by the caller, before the engine
  /// existed, so the bytes land where the commit will look for them.
  final StagingHandle staging;

  @override
  Future<StagingHandle> beginEntry({
    required String? collectionId,
    required String entryId,
  }) async => staging;

  /// Always null: an Entry's identity is the caller's, and a V2 capture is
  /// aimed at one that already exists. Nothing is looked up, so nothing is
  /// replaced by accident.
  @override
  Future<CapturedEntry?> findExistingEntry(String urlKey) async => null;

  /// Always null: the package stays in staging.
  @override
  Future<String?> commitEntry(
    StagingHandle staging,
    EntryManifest manifest, {
    required bool replacing,
  }) async => null;

  /// Nothing. The copy is recorded by the pipeline, after the commit.
  @override
  Future<void> recordEntry(
    CapturedEntry entry, {
    required String? collectionId,
    required DateTime savedAt,
  }) async {}
}
