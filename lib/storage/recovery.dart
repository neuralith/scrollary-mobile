/// Rebuilding library rows from the packages on disk.
///
/// An entry directory describes itself — that is the whole reason the manifest
/// exists — so a database that was lost, reset or never had the row can be
/// reconciled from the files. This is the routine that does it, extracted from
/// the startup sequence so the mapping can be tested directly rather than only
/// by launching the app.
///
/// Two rules it must never break:
///
/// 1. **Nothing is promoted.** Recovery restores what was written; it does not
///    re-detect, re-classify or upgrade anything. A guess made now, against no
///    page, would be weaker than the one the save already made.
/// 2. **Reading state is not save state.** Whatever the row knew about where
///    the user was survives; only the save-side columns come from the file.
library;

import 'database.dart';
import 'manifest.dart';

/// Build the entry row a committed package describes.
///
/// [prior] is the row that already exists, when one does — its reading state
/// is carried across verbatim, because the files say nothing about where the
/// user got to and must not be allowed to imply it.
Entry entryFromManifest({
  required EntryManifest manifest,
  required String relativePath,
  required int byteSize,
  Entry? prior,
}) => Entry(
  id: manifest.entryId,
  collectionId: manifest.collectionId,
  title: manifest.title,
  sourceUrl: manifest.sourceUrl,
  urlKey: manifest.sourceUrl,
  host:
      manifest.host ??
      (Uri.tryParse(manifest.sourceUrl)?.host.toLowerCase() ?? ''),
  canonicalUrl: manifest.canonicalUrl,
  publishedAt: manifest.publishedAt,
  // The shape the save decided on, as recorded. Never re-derived.
  contentKind: manifest.contentKind ?? 'unknownWebContent',
  contentKindConfidence: manifest.contentKindConfidence ?? 'low',
  contentKindIsUserSet: manifest.contentKindIsUserSet ?? false,
  // The stored format comes from the package itself. A schema-1 manifest
  // resolves to `imageSequence`, so entries saved before documents existed
  // come back exactly as they were.
  artifactFormat: manifest.artifact.name,
  captureMode: manifest.captureMode,
  saveStatus: manifest.status.name,
  contentPath: relativePath,
  savedAt: manifest.savedAt,
  detectedAssetCount: manifest.detectedAssetCount,
  storedAssetCount: manifest.storedAssetCount,
  nextSourceUrl: manifest.nextUrl,
  entryOrder: manifest.entryOrder ?? 0,
  entryNumber: manifest.entryNumber,
  sourceMarker: manifest.sourceMarker,
  byteSize: byteSize,
  // Recovery restores the save, never the reading position.
  readStatus: prior?.readStatus ?? 'unread',
  progressFraction: prior?.progressFraction ?? 0,
  progressPageIndex: prior?.progressPageIndex ?? 0,
  progressOffsetInPage: prior?.progressOffsetInPage ?? 0,
  firstOpenedAt: prior?.firstOpenedAt,
  lastReadAt: prior?.lastReadAt,
  completedAt: prior?.completedAt,
  progressUpdatedAt: prior?.progressUpdatedAt,
  discoveredAt: prior?.discoveredAt,
  discoveryBasis: prior?.discoveryBasis,
  discoveryConfidence: prior?.discoveryConfidence,
);

/// Whether a package is worth reconciling into the library at all.
///
/// Only a finished save. A manifest left in `saving` or `failed` describes an
/// attempt, not an entry, and recovering it would promote a broken save into
/// something the library claims is readable.
bool isRecoverable(EntryManifest manifest) =>
    manifest.status == SaveStatus.complete ||
    manifest.status == SaveStatus.partial;
