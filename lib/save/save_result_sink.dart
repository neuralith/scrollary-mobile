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
/// So the tail is a seam and nothing else moves. [LibrarySaveResultSink] is
/// the default and performs exactly the calls the engine used to make, in
/// exactly the order it made them, so a V1 save is bit-for-bit the save it
/// always was. A V2 caller injects its own and gets the engine to stop at
/// *the package is staged and here is what it holds* — which is what lets
/// `entry_capture.dart` run its own policy gate before the commit, and record
/// an OfflineCopy instead of an `entries` row.
///
/// The sink is told about the result; it never judges it. Nothing here may
/// measure a page, decide a capture mode, or turn a `partial` into a
/// `complete`.
library;

import '../storage/database.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';

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
  Future<Entry?> findExistingEntry(String urlKey);

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
    Entry entry, {
    required String? collectionId,
    required DateTime savedAt,
  });
}

/// The V1 library: the four database calls and the atomic commit, exactly as
/// the engine performed them itself.
///
/// This is the default, and it is deliberately the whole of the change: a
/// [SaveEngine] built the way every current caller builds it — with a `db` —
/// runs this and nothing else, so no measurement, ordering, retry posture or
/// written row differs from before the seam was cut.
class LibrarySaveResultSink implements SaveResultSink {
  const LibrarySaveResultSink({required this.db, required this.fileStore});

  final AppDatabase db;
  final FileStore fileStore;

  @override
  Future<StagingHandle> beginEntry({
    required String? collectionId,
    required String entryId,
  }) => fileStore.beginEntry(collectionId: collectionId, entryId: entryId);

  @override
  Future<Entry?> findExistingEntry(String urlKey) =>
      db.findEntryByUrlKeyAnywhere(urlKey);

  @override
  Future<String?> commitEntry(
    StagingHandle staging,
    EntryManifest manifest, {
    required bool replacing,
  }) => replacing
      ? fileStore.commitReplacing(staging, manifest)
      : fileStore.commit(staging, manifest);

  @override
  Future<void> recordEntry(
    Entry entry, {
    required String? collectionId,
    required DateTime savedAt,
  }) async {
    await db.upsertEntry(entry);
    // Files are back, so the user-removed marker must go (a null on the
    // data class would be treated as "leave it alone").
    await db.clearOfflineRemovedMark(entry.id);
    // Standalone entries have no collection to stamp; the entry's own
    // `savedAt` is the whole record.
    if (collectionId != null) {
      await db.markCollectionSaved(collectionId, savedAt);
    }
  }
}

/// The other end of the seam: a capture that stops at *the package is staged*.
///
/// It fills the staging directory the caller opened, answers "nothing here
/// already" to the re-save lookup, and keeps the package staged. **No database
/// is touched, because there is none to touch** — a V2 host has no V1 library
/// and must not acquire one.
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
  Future<Entry?> findExistingEntry(String urlKey) async => null;

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
    Entry entry, {
    required String? collectionId,
    required DateTime savedAt,
  }) async {}
}
