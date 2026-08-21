import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document.dart';
import 'manifest.dart';

/// Owns the on-disk layout and the atomic commit.
///
/// Hard rule enforced here: **the database stores relative paths only**. The
/// iOS app-container path contains a UUID that changes between installs, so a
/// persisted absolute path is a library that breaks later. Everything is
/// resolved against [rootDir] at runtime.
///
///     <app support>/webread/
///       library/<collection-id>/entries/<entry-id>/
///         manifest.json           always
///         document.json           structured-document entries only
///         assets/001.png ...      image pages, or a document's inline images
///       library/standalone/<entry-id>/    entries in no collection
///       tmp/<entry-id>/           staging, swept at startup
class FileStore {
  FileStore(this.rootDir);

  static const String rootFolderName = 'webread';
  static const String libraryFolderName = 'library';

  /// Where entries that belong to no collection are stored.
  static const String standaloneFolderName = 'standalone';
  static const String tmpFolderName = 'tmp';
  static const String manifestFileName = 'manifest.json';

  /// The structured document, beside the bytes it describes. Kept out of the
  /// manifest so startup recovery, which reads every manifest on disk, stays
  /// proportional to the number of entries rather than to the size of their
  /// prose.
  static const String documentFileName = 'document.json';
  static const String assetsFolderName = 'assets';

  final Directory rootDir;

  /// [folderName] exists for integration tests, which give every test file
  /// its own storage root. The app always uses the default.
  static Future<FileStore> open({String folderName = rootFolderName}) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, folderName));
    if (!root.existsSync()) root.createSync(recursive: true);
    final store = FileStore(root);
    Directory(store._libraryPath).createSync(recursive: true);
    Directory(store._tmpPath).createSync(recursive: true);
    return store;
  }

  String get _libraryPath => p.join(rootDir.path, libraryFolderName);
  String get _tmpPath => p.join(rootDir.path, tmpFolderName);

  /// Relative path of an entry directory, as stored in the database.
  /// Where an entry's bytes live, relative to the store root.
  ///
  /// A standalone entry (`collectionId == null`) goes under a fixed
  /// `standalone/` folder rather than a synthesised collection directory: the
  /// path must never imply a grouping the library does not have, and a folder
  /// named after an entry id that is also its "collection" is exactly the kind
  /// of thing a later reader mistakes for one.
  static String entryRelativePath(String? collectionId, String entryId) =>
      collectionId == null
      ? p.join(libraryFolderName, standaloneFolderName, entryId)
      : p.join(libraryFolderName, collectionId, 'entries', entryId);

  /// Where one collection's entries live, relative to the store root.
  ///
  /// The parent of every `entries/<entry-id>` directory it owns, so permanent
  /// deletion can move the whole collection in one atomic step — including the
  /// `.previous` backups an interrupted replacement leaves inside it, which no
  /// per-entry path names.
  static String collectionRelativePath(String collectionId) =>
      p.join(libraryFolderName, collectionId);

  /// Turn a stored relative path into a usable absolute one.
  String resolve(String relativePath) => p.join(rootDir.path, relativePath);

  Directory entryDir(String? collectionId, String entryId) =>
      Directory(resolve(entryRelativePath(collectionId, entryId)));

  bool entryExists(String relativePath) =>
      Directory(resolve(relativePath)).existsSync();

  File assetFile(String entryRelativePath, String assetRelativePath) =>
      File(p.join(resolve(entryRelativePath), assetRelativePath));

  // --- staging + atomic commit -------------------------------------------

  /// Start an entry in staging. Nothing outside `tmp/` exists until commit.
  Future<StagingHandle> beginEntry({
    required String? collectionId,
    required String entryId,
  }) async {
    final dir = Directory(p.join(_tmpPath, entryId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    Directory(p.join(dir.path, assetsFolderName)).createSync(recursive: true);
    return StagingHandle._(
      collectionId: collectionId,
      entryId: entryId,
      dir: dir,
    );
  }

  /// Write the manifest, then move staging into place, then (caller) update
  /// the database. A crash before the move leaves an orphan in `tmp/`; a crash
  /// after it leaves a directory whose manifest describes itself, which
  /// [reconcileOrphans] can finish. Neither produces an entry that claims to
  /// be complete and is not.
  Future<String> commit(StagingHandle handle, EntryManifest manifest) async {
    final manifestFile = File(p.join(handle.dir.path, manifestFileName));
    await manifestFile.writeAsString(manifest.encode(), flush: true);

    final relative = entryRelativePath(handle.collectionId, handle.entryId);
    final target = Directory(resolve(relative));
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.parent.createSync(recursive: true);

    try {
      await handle.dir.rename(target.path);
    } on FileSystemException {
      // Cross-device rename is not possible; fall back to copy + delete.
      await _copyDirectory(handle.dir, target);
      await handle.dir.delete(recursive: true);
    }
    return relative;
  }

  /// Replace an existing entry's files, keeping the old copy until the new
  /// one is safely in place.
  ///
  /// The naive version — delete then move — leaves the user with nothing if the
  /// move fails, having destroyed an entry that was perfectly readable. Here
  /// the old directory is stepped aside first and only removed once the
  /// replacement has landed; any failure puts it back.
  Future<String> commitReplacing(
    StagingHandle handle,
    EntryManifest manifest,
  ) async {
    final relative = entryRelativePath(handle.collectionId, handle.entryId);
    final target = Directory(resolve(relative));
    if (!target.existsSync()) return commit(handle, manifest);

    final backup = Directory('${target.path}.previous');
    if (backup.existsSync()) backup.deleteSync(recursive: true);
    target.renameSync(backup.path);

    try {
      final manifestFile = File(p.join(handle.dir.path, manifestFileName));
      await manifestFile.writeAsString(manifest.encode(), flush: true);
      target.parent.createSync(recursive: true);
      try {
        await handle.dir.rename(target.path);
      } on FileSystemException {
        await _copyDirectory(handle.dir, target);
        await handle.dir.delete(recursive: true);
      }
      // Only now is the old copy expendable.
      if (backup.existsSync()) backup.deleteSync(recursive: true);
      return relative;
    } catch (_) {
      // Put the previous entry back exactly as it was.
      if (target.existsSync()) target.deleteSync(recursive: true);
      if (backup.existsSync()) backup.renameSync(target.path);
      rethrow;
    }
  }

  /// Restore a `.previous` copy left behind by an interrupted replacement.
  /// Runs at startup so a kill mid-replace cannot cost a readable entry.
  Future<int> restoreInterruptedReplacements() async {
    final library = Directory(_libraryPath);
    if (!library.existsSync()) return 0;
    var restored = 0;

    int sweep(Directory dir) {
      var count = 0;
      for (final entity in dir.listSync().whereType<Directory>()) {
        if (!entity.path.endsWith('.previous')) continue;
        final original = Directory(
          entity.path.substring(0, entity.path.length - '.previous'.length),
        );
        if (original.existsSync()) {
          // The replacement did land; the backup is just leftover.
          entity.deleteSync(recursive: true);
        } else {
          entity.renameSync(original.path);
          count++;
        }
      }
      return count;
    }

    for (final item in library.listSync().whereType<Directory>()) {
      // Standalone entries sit directly under `standalone/`, with no
      // `entries/` level. Skipping them here left an interrupted replacement of
      // a standalone entry unrecoverable.
      if (p.basename(item.path) == standaloneFolderName) {
        restored += sweep(item);
        continue;
      }
      final entriesDir = Directory(p.join(item.path, 'entries'));
      if (!entriesDir.existsSync()) continue;
      restored += sweep(entriesDir);
    }
    return restored;
  }

  Future<void> discard(StagingHandle handle) async {
    if (handle.dir.existsSync()) {
      await handle.dir.delete(recursive: true);
    }
  }

  /// Delete an entry's files while leaving its database row intact
  /// ("free up space" — the entry stays known, just not offline).
  Future<void> deleteEntryContent(String relativePath) async {
    final dir = Directory(resolve(relativePath));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Read an entry's structured document, or null when it has none, the file
  /// is gone, or it does not parse.
  ///
  /// Null is a state the reader renders honestly ("the saved text is
  /// unreadable"), never an exception: a corrupt file in one entry must not be
  /// able to take a library screen down with it.
  Future<StructuredDocument?> readDocument(
    String entryRelativePath, {
    String fileName = documentFileName,
  }) async {
    final file = File(p.join(resolve(entryRelativePath), fileName));
    if (!file.existsSync()) return null;
    try {
      return StructuredDocument.decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<EntryManifest?> readManifest(String entryRelativePath) async {
    final file = File(p.join(resolve(entryRelativePath), manifestFileName));
    if (!file.existsSync()) return null;
    try {
      return EntryManifest.decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Rewrite a committed entry's manifest in place, atomically (temp file +
  /// rename). Used by dimension repair; the assets themselves are never
  /// touched.
  Future<void> writeManifest(
    String entryRelativePath,
    EntryManifest manifest,
  ) async {
    final dir = resolve(entryRelativePath);
    final tmp = File(p.join(dir, '$manifestFileName.tmp'));
    await tmp.writeAsString(manifest.encode(), flush: true);
    await tmp.rename(p.join(dir, manifestFileName));
  }

  /// Bytes sitting in `tmp/` — interrupted saves and pending cleanup
  /// undos. Reported on the Storage screen as recoverable space.
  Future<int> stagingByteSize() async {
    final tmp = Directory(_tmpPath);
    if (!tmp.existsSync()) return 0;
    var total = 0;
    try {
      await for (final e in tmp.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {
      // A sweep racing this walk is not worth failing a size readout over.
    }
    return total;
  }

  /// Startup sweep: staging directories belong to no live session.
  Future<int> sweepStaging() async {
    final tmp = Directory(_tmpPath);
    if (!tmp.existsSync()) return 0;
    var removed = 0;
    for (final entity in tmp.listSync()) {
      try {
        entity.deleteSync(recursive: true);
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  /// Committed entry directories on disk, for reconciling against the DB.
  ///
  /// Walks **both** layouts: `<collection>/entries/<entry>` and the flat
  /// `standalone/<entry>`. Missing the second one meant a standalone entry's
  /// files could never be recovered from their own manifest — the row was
  /// gone, the bytes were there, and nothing ever put them back together.
  List<String> listCommittedEntryPaths() {
    final library = Directory(_libraryPath);
    if (!library.existsSync()) return const [];
    final out = <String>[];
    for (final item in library.listSync().whereType<Directory>()) {
      if (p.basename(item.path) == standaloneFolderName) {
        for (final entry in item.listSync().whereType<Directory>()) {
          if (entry.path.endsWith('.previous')) continue;
          out.add(p.relative(entry.path, from: rootDir.path));
        }
        continue;
      }
      final entries = Directory(p.join(item.path, 'entries'));
      if (!entries.existsSync()) continue;
      for (final ch in entries.listSync().whereType<Directory>()) {
        if (ch.path.endsWith('.previous')) continue;
        out.add(p.relative(ch.path, from: rootDir.path));
      }
    }
    return out;
  }

  Future<int> entryByteSize(String relativePath) async {
    final dir = Directory(resolve(relativePath));
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    to.createSync(recursive: true);
    await for (final entity in from.list(recursive: true)) {
      final rel = p.relative(entity.path, from: from.path);
      final destPath = p.join(to.path, rel);
      if (entity is Directory) {
        Directory(destPath).createSync(recursive: true);
      } else if (entity is File) {
        File(destPath).parent.createSync(recursive: true);
        await entity.copy(destPath);
      }
    }
  }
}

class StagingHandle {
  StagingHandle._({
    required this.collectionId,
    required this.entryId,
    required this.dir,
  });

  /// Null for a standalone entry.
  final String? collectionId;
  final String entryId;
  final Directory dir;

  File assetFile(String fileName) =>
      File(p.join(dir.path, FileStore.assetsFolderName, fileName));

  /// The staged document, written before the manifest and moved into place
  /// with everything else — so a document entry is as atomic as an image one.
  File get documentFile => File(p.join(dir.path, FileStore.documentFileName));

  /// Path recorded in the manifest — relative to the entry directory.
  static String assetRelativePath(String fileName) =>
      '${FileStore.assetsFolderName}/$fileName';
}
