/// Establishing Collection context for a page the library does not hold yet.
///
/// **Why this file exists.** Recognition answers *what do we already know
/// about this address* and stops there, correctly: a new host can never be
/// matched to an existing Collection by title, and V2 refuses to guess
/// (V2-D16, PRODUCT.md §5.3). But between "we could not tell" and "save it as
/// a loose Entry in the root Folder" there is a person who knows the answer.
/// This file is the operation they drive: *this page belongs to that
/// Collection*, or *this page starts a new one*.
///
/// Three rules it carries:
///
/// * **The user decides identity; the app never infers it.** A detected title
///   pre-fills a field and filters a list. It never selects, and similarity is
///   never a match (V2-D44).
/// * **Nothing transitional is written.** A Collection, its Source, the Entry
///   and the Location are one transaction. There is no standalone Entry
///   created first and repaired afterwards — that is the state this file
///   exists to prevent.
/// * **A Source belongs to the Collection it was created under.** If the same
///   `(host, path_key)` already sits under another Collection, the answer is a
///   refusal the user can read, never a silent move (V2-D14: a site that moves
///   is a lifecycle change, not a reparenting).
library;

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/folder_repository.dart';
import '../data/recognition_index.dart';
import '../domain/invariants.dart';
import 'recognise.dart';

/// What an adoption did.
class AdoptionOutcome {
  const AdoptionOutcome({
    this.collectionId,
    this.sourceId,
    this.entryId,
    this.locationId,
    this.violation,
    this.mergedIntoExistingEntry = false,
    this.sourceReused = false,
  });

  /// A refusal, carrying the sentence the user is shown.
  const AdoptionOutcome.refused(InvariantViolation this.violation)
    : collectionId = null,
      sourceId = null,
      entryId = null,
      locationId = null,
      mergedIntoExistingEntry = false,
      sourceReused = false;

  final String? collectionId;
  final String? sourceId;
  final String? entryId;
  final String? locationId;
  final InvariantViolation? violation;

  /// True when the address joined an Entry the Collection already held, rather
  /// than creating one — cross-source equivalence, decided by
  /// `EntryReconciler` and nowhere else.
  final bool mergedIntoExistingEntry;

  /// True when the Source already existed under this Collection and was used
  /// as it stands. Adding the same site twice is not an error.
  final bool sourceReused;

  bool get succeeded => violation == null && entryId != null;
}

/// The user-assisted half of recognition.
class LibraryAdoption {
  LibraryAdoption({
    required this.folders,
    required this.collections,
    required this.entries,
    required this.index,
  });

  final FolderRepository folders;
  final CollectionRepository collections;
  final EntryRepository entries;
  final RecognitionIndex index;

  /// *This page is another Source of [collectionId].*
  ///
  /// Ensures the Source, then puts the address through the same reconciliation
  /// discovery uses: an equal ordinal under a numeric basis joins the Entry
  /// that already holds it; anything else is a new Entry, placed only when the
  /// evidence places it.
  ///
  /// Refuses with [sourceIdentityTaken] when this `(host, path_key)` already
  /// belongs to a different Collection, and with [sourceKeyUnavailable] when
  /// the address yields no stable Source key at all.
  Future<AdoptionOutcome> addToExistingCollection({
    required String collectionId,
    required RecognitionKeys keys,
    required String pageTitle,
    double? printedNumber,
    String language = '',
  }) {
    throw UnimplementedError('ms-domain');
  }

  /// *Start a new Collection for this page.*
  ///
  /// Collection, Source, Entry and Location in one transaction. [name] is the
  /// user's, never the detected title silently. The ordering basis is
  /// `explicitNumericIndex` only when this page actually printed a number —
  /// claiming a numeric basis for a work that numbers nothing would license
  /// cross-source merging the evidence does not support (V2-D16).
  Future<AdoptionOutcome> createCollection({
    required String name,
    required RecognitionKeys keys,
    required String pageTitle,
    double? printedNumber,
    String? folderId,
    String language = '',
  }) {
    throw UnimplementedError('ms-domain');
  }

  /// *This loose Entry belongs in that Collection after all.*
  ///
  /// Derives Source identity from the Entry's own address. When the Collection
  /// already holds an equivalent Entry, the two become one: the Location moves
  /// across, reading state merges by the rules already in `sync/identity.dart`
  /// (never discarding the more-progressed side), measurements and queue rows
  /// follow, and an existing OfflineCopy keeps its bytes and its provenance —
  /// domain reorganisation never destroys device-local content.
  Future<AdoptionOutcome> adoptStandalone({
    required String entryId,
    required String collectionId,
  }) {
    throw UnimplementedError('ms-domain');
  }
}

/// No stable Source key could be derived from this address, so no Source can
/// be made from it — a real answer, and the reason the user is told.
const sourceKeyUnavailable = InvariantViolation(
  'I5',
  'this address does not identify a site section this app can follow',
);

/// The Entry is already in a Collection, so there is nothing to adopt.
const entryNotStandalone = InvariantViolation(
  'I3',
  'this entry already belongs to a collection',
);
