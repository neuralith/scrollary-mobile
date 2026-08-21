import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../save/save_run.dart';
import 'database.dart';
import 'file_store.dart';

/// Removing offline files is NOT deletion. The entry row survives with its
/// source URL, ordering, reading progress, read marks, timestamps and
/// discovery metadata — only the bytes under `library/…` go, and
/// `offlineRemovedAt` records that the *user* chose this (unlike files the
/// system lost, which stay an error state).
///
/// Two paths:
///  - [removeOffline] — soft: the entry directory is renamed into
///    `tmp/undo-<id>` and can be restored until [UndoHandle.finalize] runs
///    (a few seconds later, or at next startup via the existing staging
///    sweep). This is what the reader flow and manual selection use, and
///    what makes the toast's Undo honest.
///  - [removeOfflineNow] — hard: for queued bulk work, where an undo window
///    per entry would be theatre.
class CleanupService {
  CleanupService({
    required this.db,
    required this.fileStore,
    this.saveRun,
    this.undoWindow = const Duration(seconds: 6),
  });

  final AppDatabase db;
  final FileStore fileStore;

  /// Optional: without it, the "in use by the running save" lock simply
  /// cannot fire. The entry's own `saving` status still protects it.
  final SaveRunController? saveRun;
  final Duration undoWindow;

  /// The entry currently open in the reader, if any. Set by the reader
  /// screen; cleanup refuses to touch it.
  final ValueNotifier<String?> openReaderEntryId = ValueNotifier(null);

  /// Bumped once per removal batch that actually freed something.
  ///
  /// Removal happens from five places (collection selection, whole collection, the
  /// Storage screen, the finished-entry flow, the queue). Anything showing
  /// a storage figure listens here instead of every one of those call sites
  /// remembering to refresh it.
  final ValueNotifier<int> removals = ValueNotifier(0);

  void _noteRemoval(int removed) {
    if (removed > 0) removals.value++;
  }

  /// Why an entry cannot be removed right now, or null when it can.
  ///
  /// Locked entries are *kept*, never errors: bulk operations skip them and
  /// say so, selection UI shows them as locked.
  Future<String?> lockReasonFor(Entry entry) async {
    if (entry.id == openReaderEntryId.value) {
      return 'open in the reader';
    }
    if (entry.saveStatus == 'saving') {
      return 'being saved';
    }
    final run = saveRun;
    if (run != null &&
        run.isRunning &&
        entry.sourceUrl.isNotEmpty &&
        Uri.tryParse(run.progress.currentUrl)?.path ==
            Uri.tryParse(entry.sourceUrl)?.path) {
      return 'in use by the running save';
    }
    return null;
  }

  bool isRemovable(Entry c) =>
      c.contentPath != null &&
      (c.saveStatus == 'complete' || c.saveStatus == 'partial');

  /// Soft-remove [entryIds]; locked/non-offline entries are skipped and
  /// reported. Returns a handle carrying freed bytes and the undo.
  Future<CleanupResult> removeOffline(List<String> entryIds) async {
    final undoable = <_UndoEntry>[];
    var freed = 0;
    var removed = 0;
    final kept = <String>[];

    for (final id in entryIds) {
      final entry = await db.entryById(id);
      if (entry == null || !isRemovable(entry)) continue;
      final lock = await lockReasonFor(entry);
      if (lock != null) {
        kept.add('${entry.sourceMarker ?? entry.title} ($lock)');
        continue;
      }

      final srcDir = Directory(fileStore.resolve(entry.contentPath!));
      if (!srcDir.existsSync()) {
        // Files already gone: just record the state honestly.
        await _writeRemoved(entry);
        removed++;
        continue;
      }
      final undoDir = Directory(
        p.join(fileStore.rootDir.path, FileStore.tmpFolderName, 'undo-$id'),
      );
      if (undoDir.existsSync()) undoDir.deleteSync(recursive: true);
      undoDir.parent.createSync(recursive: true);
      final bytes = entry.byteSize;
      srcDir.renameSync(undoDir.path);
      await _writeRemoved(entry);
      undoable.add(_UndoEntry(entry: entry, undoDir: undoDir, bytes: bytes));
      freed += bytes;
      removed++;
    }

    final handle = UndoHandle._(this, undoable);
    if (undoable.isNotEmpty) {
      handle._timer = Timer(undoWindow, handle.finalize);
    }
    _noteRemoval(removed);
    return CleanupResult(
      removed: removed,
      freedBytes: freed,
      keptLocked: kept,
      undo: handle,
    );
  }

  /// Hard-remove, for bulk queue work. [onProgress] fires per entry with
  /// (processed, freedBytes so far).
  ///
  /// [shouldContinue] is asked **between entries** and is the only place this
  /// loop can be stopped. Each entry's removal — delete the directory, then
  /// clear the row's file fields — is atomic from the outside: an entry is
  /// either still offline or cleanly marked removed, never half of both. So a
  /// stop at an entry boundary is genuinely safe, which is what lets the
  /// Activity screen offer Cancel on a running cleanup and mean it (D64).
  /// Everything already removed stays removed; removal is not a transaction
  /// and was never presented as one.
  Future<CleanupResult> removeOfflineNow(
    List<String> entryIds, {
    void Function(int processed, int freedBytes)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    var freed = 0;
    var removed = 0;
    var processed = 0;
    var stoppedEarly = false;
    final kept = <String>[];
    for (final id in entryIds) {
      if (shouldContinue != null && !shouldContinue()) {
        stoppedEarly = true;
        break;
      }
      processed++;
      final entry = await db.entryById(id);
      if (entry == null || !isRemovable(entry)) continue;
      final lock = await lockReasonFor(entry);
      if (lock != null) {
        kept.add('${entry.sourceMarker ?? entry.title} ($lock)');
        continue;
      }
      try {
        await fileStore.deleteEntryContent(entry.contentPath!);
        await _writeRemoved(entry);
        freed += entry.byteSize;
        removed++;
      } catch (e) {
        kept.add('${entry.sourceMarker ?? entry.title} ($e)');
      }
      onProgress?.call(processed, freed);
    }
    _noteRemoval(removed);
    return CleanupResult(
      removed: removed,
      freedBytes: freed,
      keptLocked: kept,
      undo: UndoHandle._(this, const []),
      stoppedEarly: stoppedEarly,
    );
  }

  /// Everything the row must keep is untouched by construction: the write
  /// names ONLY the fields that change.
  Future<void> _writeRemoved(Entry entry) => db.writeEntryReading(
    entry.id,
    EntriesCompanion(
      contentPath: const Value(null),
      byteSize: const Value(0),
      offlineRemovedAt: Value(DateTime.now()),
    ),
  );

  Future<void> _restore(_UndoEntry entry) async {
    final target = Directory(fileStore.resolve(entry.entry.contentPath!));
    if (entry.undoDir.existsSync() && !target.existsSync()) {
      target.parent.createSync(recursive: true);
      entry.undoDir.renameSync(target.path);
    }
    await db.writeEntryReading(
      entry.entry.id,
      EntriesCompanion(
        contentPath: Value(entry.entry.contentPath),
        byteSize: Value(entry.bytes),
        offlineRemovedAt: const Value(null),
      ),
    );
  }
}

class CleanupResult {
  const CleanupResult({
    required this.removed,
    required this.freedBytes,
    required this.keptLocked,
    required this.undo,
    this.stoppedEarly = false,
  });

  final int removed;
  final int freedBytes;

  /// Human lines for entries skipped because they were in use.
  final List<String> keptLocked;
  final UndoHandle undo;

  /// The batch was asked to stop and did, at an entry boundary. The entries
  /// it never reached still have their files — the summary must say so rather
  /// than read like a completed sweep.
  final bool stoppedEarly;

  bool get canUndo => undo._entries.isNotEmpty && !undo._finalized;
}

/// Restores the renamed-away directories, or lets them die. Idempotent both
/// ways; a crash inside the window leaves `tmp/undo-*`, which the existing
/// startup staging sweep removes.
class UndoHandle {
  UndoHandle._(this._service, this._entries);

  final CleanupService _service;
  final List<_UndoEntry> _entries;
  Timer? _timer;
  bool _finalized = false;
  bool _undone = false;

  Future<void> undo() async {
    if (_finalized || _undone) return;
    _undone = true;
    _timer?.cancel();
    for (final entry in _entries) {
      await _service._restore(entry);
    }
  }

  Future<void> finalize() async {
    if (_finalized || _undone) return;
    _finalized = true;
    _timer?.cancel();
    for (final entry in _entries) {
      try {
        if (entry.undoDir.existsSync()) {
          entry.undoDir.deleteSync(recursive: true);
        }
      } catch (_) {
        // The startup sweep owns anything a crash leaves behind.
      }
    }
  }
}

class _UndoEntry {
  const _UndoEntry({
    required this.entry,
    required this.undoDir,
    required this.bytes,
  });

  final Entry entry;
  final Directory undoDir;
  final int bytes;
}

/// What a collection does with a finished entry's downloaded files when the
/// reader moves forward (D37).
///
/// Persisted on the library item itself — `collections.cleanup_preference` —
/// because the decision belongs to the collection being read. There is no global
/// default: a collection that has not been asked stores null, and null is a
/// question, not a value.
enum CollectionCleanupPreference { remove, keep }

/// Parses a stored value. Null, empty and anything unrecognised all read as
/// "not decided yet", so the user is asked instead of a wrong guess being
/// applied to their files.
CollectionCleanupPreference? collectionCleanupFromName(String? name) {
  for (final value in CollectionCleanupPreference.values) {
    if (value.name == name) return value;
  }
  return null;
}
