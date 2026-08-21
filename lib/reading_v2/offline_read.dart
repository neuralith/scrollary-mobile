/// Opening an Entry through its OfflineCopy (roadmap E5).
///
/// V1 asked the Entry row whether it could be read: `content_path`,
/// `save_status`, `artifact_format` and the reading anchor were all columns on
/// it. V2 asks the **copy**. An Entry is in the library because somebody wants
/// to read it; the bytes are a per-device capability of it, so the row that
/// knows where they are is the row that decides whether a reader can open.
///
/// What this file provides is the *resolution* — the inputs the readers need,
/// assembled exactly as V1's own loader assembles them from its rows — and the
/// write-back. Building widgets is the UX lane's; no route is wired here.
///
/// **Position restore is unchanged, and the difference between the two
/// artifacts is load-bearing.** The image reader opens *at* its position,
/// because panel geometry comes from the manifest and every offset is known
/// before an image decodes. The document reader restores *to* its position,
/// because a paragraph has no offset until it has been laid out at this width,
/// font and text scale. The anchor that makes both work lives on the
/// OfflineCopy — an index into *these* bytes, meaningless without them, and it
/// never leaves the device.
///
/// **Three writes, three owners.** The anchor goes to the copy (device).
/// Reading state goes through `ReadingStateRepository` (user, synced, its own
/// clock). Nothing here writes a Measurement: a measurement is scoped to the
/// rendering it was taken against, and reading an offline copy is not reading
/// a Source.
///
/// ## What the UX lane can wire today, and what it cannot
///
/// [OfflineDocumentRead] carries exactly what `DocumentBody` takes — document,
/// manifest, entry directory — so the document body is constructible from here
/// as it stands. [OfflineImageRead] carries the same page list and geometry
/// V1's own loader builds, through [OfflineImageRead.geometryFor].
///
/// `ReaderScreen` itself is **not** constructible from this: it takes an
/// `entryId` and loads everything else from V1 rows inside its own state
/// (`db.entryById`, `reading.markOpened`, `db.touchCollection`, siblings from
/// `db.entriesForCollection`). Opening it through an OfflineCopy means it must
/// accept its data instead of fetching it — an internal change to a frozen
/// component, and so a reviewed task of its own rather than a side effect of
/// this one (docs/V2_PORT_CHECKLIST.md §13).
library;

import 'dart:io';

import '../data/offline_copy_repository.dart';
import '../data/reading_state_repository.dart';
import '../domain/offline_copy.dart';
import '../domain/reading_state.dart';
import '../reading/reading_position.dart'
    show
        CompletionPolicy,
        EntryLayout,
        ReadingPosition,
        kDefaultCompletionPolicy;
import '../storage/document.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';

/// Why an Entry cannot be opened offline. Each is a state the reader reports
/// honestly; none of them is a failure of the library, and none demotes the
/// Entry.
enum OfflineReadRefusal {
  /// This device holds no copy. The Entry is still listed, with its reading
  /// history intact — it just has to be saved again to be read here.
  noCopy,

  /// The copy row says where the bytes are and they are not there.
  filesMissing,

  /// The package is on disk but does not describe itself.
  manifestUnreadable,

  /// A package a newer build wrote. Said plainly rather than misread as one of
  /// the formats this version does know — an unrecognised artifact resolves to
  /// [ArtifactFormat.unknown] and the reader says so.
  unknownArtifact,

  /// A structured document whose text will not parse.
  documentUnreadable,
}

/// One page of an image sequence, resolved to a local file.
///
/// **Local files only.** There is no remote fallback anywhere in this path: a
/// missing file is reported, never fetched, because falling back to the source
/// would make "offline" a claim that only fails once the network is gone.
class OfflinePage {
  const OfflinePage({
    required this.file,
    required this.exists,
    this.width,
    this.height,
  });

  final File file;
  final bool exists;

  /// Intrinsic size, **only when it was decoded from the stored bytes**. A
  /// page's own claim about its size is a layout assertion, not a pixel fact,
  /// and panels sized from one lay out at the wrong aspect ratio. Null means
  /// "not measured", which the geometry handles; it never means "guess".
  final int? width;
  final int? height;
}

/// What the reader can open, or why it cannot.
sealed class OfflineRead {
  const OfflineRead();
}

/// The Entry cannot be read from this device right now.
class OfflineReadUnavailable extends OfflineRead {
  const OfflineReadUnavailable(this.refusal, {this.copy});

  final OfflineReadRefusal refusal;

  /// The copy row, when there was one to name. Present for every refusal but
  /// [OfflineReadRefusal.noCopy] — it is what lets a cleanup surface say what
  /// it is offering to remove.
  final OfflineCopy? copy;
}

/// An ordered sequence of full-size images.
class OfflineImageRead extends OfflineRead {
  const OfflineImageRead({
    required this.copy,
    required this.manifest,
    required this.entryDir,
    required this.pages,
    required this.restored,
  });

  final OfflineCopy copy;
  final EntryManifest manifest;
  final Directory entryDir;

  /// In manifest order, which is DOM order, which is reading order.
  final List<OfflinePage> pages;

  /// Where the reader left off, rebuilt from the copy's own anchor.
  final ReadingPosition restored;

  /// Panel geometry at a given width — known before a single image decodes,
  /// which is what lets this reader open *at* [restored] rather than jump
  /// there afterwards.
  EntryLayout geometryFor(double viewportWidth) => EntryLayout(
    viewportWidth: viewportWidth,
    panels: [for (final p in pages) (width: p.width, height: p.height)],
  );
}

/// A structured document, optionally with inline images.
class OfflineDocumentRead extends OfflineRead {
  const OfflineDocumentRead({
    required this.copy,
    required this.manifest,
    required this.entryDir,
    required this.document,
    required this.restored,
  });

  final OfflineCopy copy;
  final EntryManifest manifest;

  /// Absolute directory holding this entry's files, for resolving the
  /// document's inline images. This is what `DocumentBody` takes.
  final Directory entryDir;

  final StructuredDocument document;

  /// Where the reader left off. Applied on the first measurement, not at
  /// construction: reflowing text has no offsets until it has been laid out.
  final ReadingPosition restored;
}

/// The reading position stored on a copy.
///
/// Only the anchor is stored, and deliberately: an index plus an offset inside
/// *these* bytes is the whole record. There is no per-copy fraction — a
/// fraction that meant something would have to name the rendering it was
/// measured against, and that is a Measurement, keyed by `(entry, source)`.
ReadingPosition positionOfCopy(OfflineCopy copy) => ReadingPosition(
  anchorIndex: copy.anchorIndex ?? 0,
  offsetInAnchor: copy.anchorOffset ?? 0,
);

/// Resolve what the reader should open for [entryId].
///
/// Picks the **active** copy — one per Entry per device (I13) — and reads the
/// artifact out of its manifest, never out of a file extension or an asset
/// count.
Future<OfflineRead> resolveOfflineRead({
  required String entryId,
  required OfflineCopyRepository offlineCopies,
  required FileStore fileStore,
}) async {
  final copy = await offlineCopies.activeCopyOf(entryId);
  if (copy == null) {
    return const OfflineReadUnavailable(OfflineReadRefusal.noCopy);
  }

  final relative = copy.contentPath;
  if (relative.isEmpty || !fileStore.entryExists(relative)) {
    return OfflineReadUnavailable(OfflineReadRefusal.filesMissing, copy: copy);
  }

  final manifest = await fileStore.readManifest(relative);
  if (manifest == null) {
    return OfflineReadUnavailable(
      OfflineReadRefusal.manifestUnreadable,
      copy: copy,
    );
  }

  // The manifest is the authority on what the package holds; the copy row's
  // `artifact_format` is a cached label for describing an Entry without
  // opening a file per row. When they disagree, the files win.
  if (!manifest.artifact.isReadable) {
    return OfflineReadUnavailable(
      OfflineReadRefusal.unknownArtifact,
      copy: copy,
    );
  }

  final entryDir = Directory(fileStore.resolve(relative));
  final restored = positionOfCopy(copy);

  if (manifest.isDocument) {
    final document = await fileStore.readDocument(
      relative,
      fileName: manifest.document?.relativePath ?? FileStore.documentFileName,
    );
    if (document == null || document.isEmpty) {
      return OfflineReadUnavailable(
        OfflineReadRefusal.documentUnreadable,
        copy: copy,
      );
    }
    return OfflineDocumentRead(
      copy: copy,
      manifest: manifest,
      entryDir: entryDir,
      document: document,
      restored: restored,
    );
  }

  return OfflineImageRead(
    copy: copy,
    manifest: manifest,
    entryDir: entryDir,
    pages: [
      for (final asset in manifest.storedAssets)
        _pageFor(fileStore, relative, asset),
    ],
    restored: restored,
  );
}

OfflinePage _pageFor(FileStore store, String relative, EntryAsset asset) {
  final file = store.assetFile(relative, asset.relativePath!);
  return OfflinePage(
    file: file,
    exists: file.existsSync(),
    width: asset.dimensionsVerified ? asset.width : null,
    height: asset.dimensionsVerified ? asset.height : null,
  );
}

/// The write-back half: one open reader, one Entry.
///
/// Two destinations, and they are not interchangeable. The **anchor** goes to
/// the OfflineCopy, because it indexes those bytes and nothing else. The
/// **reading state** goes through `ReadingStateRepository`, which serialises
/// every write so a stale in-flight one cannot clobber a newer one, and which
/// is the only thing that may reach a reading column.
class OfflineReadSession {
  OfflineReadSession({
    required this.entryId,
    required this.offlineCopies,
    required this.reading,
    this.policy = kDefaultCompletionPolicy,
  });

  final String entryId;
  final OfflineCopyRepository offlineCopies;
  final ReadingStateRepository reading;

  /// Unchanged from V1: the only automatic route to completion is the measured
  /// threshold **plus its dwell**, in Scrollary's own reader. Whether the
  /// dwell has elapsed is the reader's to time; this class is told the answer.
  final CompletionPolicy policy;

  /// The reader opened the Entry. Records access and never completion: opening
  /// is not finishing, and a completed Entry that is reopened stays completed.
  Future<ReadingState> recordOpen({DateTime? at}) async {
    // `recordSourceAccess` is the repository's one non-completing access
    // write — first-opened once, last-read always, unread → reading — and it
    // is exactly what an open means here too. Its name reads oddly for a local
    // read; the behaviour is right, and the file is not this lane's to rename.
    final (state, _) = await reading.recordSourceAccess(entryId, at: at);
    return state ?? await reading.stateOf(entryId);
  }

  /// Persist where the reader is.
  ///
  /// [reachedEnd] is the reader's verdict that [CompletionPolicy.threshold]
  /// was crossed *and* held for [CompletionPolicy.dwell] — a fling to the
  /// bottom passes the threshold without ever satisfying the dwell, and must
  /// not finish anything.
  ///
  /// The anchor keeps following the scroll even for a finished Entry, so
  /// resuming one still lands where the reader actually is. There is no stored
  /// fraction to contradict it: a completed Entry is 100% read because its
  /// status says so, which is the rule enforced on write here and again by
  /// [offlineReadProgress] on display.
  Future<ReadingState> saveProgress(
    ReadingPosition position, {
    bool reachedEnd = false,
    DateTime? at,
  }) async {
    await offlineCopies.saveAnchor(
      entryId,
      anchorIndex: position.anchorIndex,
      anchorOffset: position.offsetInAnchor.clamp(0.0, 1.0),
    );
    if (reachedEnd) return markRead(at: at);
    final (state, _) = await reading.recordSourceAccess(entryId, at: at);
    return state ?? await reading.stateOf(entryId);
  }

  /// Explicit "I have read this", wherever the scroll happens to be.
  Future<ReadingState> markRead({DateTime? at}) async {
    final (state, _) = await reading.markRead(entryId, at: at);
    return state ?? await reading.stateOf(entryId);
  }

  /// Explicit "I have not read this" — deliberately lowering progress, which
  /// is why completion is a value and not a floor. The anchor is kept: the
  /// user is saying it is unfinished, not that they were never there.
  Future<ReadingState> markUnread({DateTime? at}) async {
    final (state, _) = await reading.markUnread(entryId, at: at);
    return state ?? await reading.stateOf(entryId);
  }

  Future<ReadingState> state() => reading.stateOf(entryId);
}

/// How far through an Entry is, for display.
///
/// The completed-is-100% rule, enforced a second time on the way out: a
/// finished Entry reopened and scrolled back to the top is still finished, and
/// its live scroll position is a fact about the scroll, not about the Entry.
double offlineReadProgress({
  required ReadingState state,
  required ReadingPosition live,
}) => state.status == ReadStatus.completed ? 1 : live.fraction.clamp(0.0, 1.0);
