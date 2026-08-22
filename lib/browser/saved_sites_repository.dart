import 'package:drift/drift.dart';

import 'package:uuid/uuid.dart';

import '../core/url_utils.dart';
import '../data/schema.dart';
import 'browser_url.dart';

const _uuid = Uuid();

/// What a save attempt did.
enum SaveSiteOutcome { created, updated, duplicate }

class SaveSiteResult {
  const SaveSiteResult(this.outcome, this.site);

  final SaveSiteOutcome outcome;
  final SavedSiteRow site;

  bool get isDuplicate => outcome == SaveSiteOutcome.duplicate;
}

/// Reading and writing the user's saved sites.
///
/// Everything the user can do to a saved site is a method here.
///
/// The queries live here rather than on [LibraryDatabase] for the reason the
/// page-hint store gives: the library holds the row and knows nothing else
/// about it. The ordering, the URL key and the narrow rename write are V1's,
/// carried unchanged — only the database under them is the V2 one.
class SavedSitesRepository {
  SavedSitesRepository(this.db);

  final LibraryDatabase db;

  Stream<List<SavedSiteRow>> watchAll() => _ordered().watch();

  Future<List<SavedSiteRow>> all() => _ordered().get();

  SimpleSelectStatement<$SavedSitesTable, SavedSiteRow> _ordered() =>
      db.select(db.savedSites)..orderBy([
        (t) => OrderingTerm.asc(t.orderIndex),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);

  Future<SavedSiteRow?> _byUrlKey(String urlKey) => (db.select(
    db.savedSites,
  )..where((t) => t.urlKey.equals(urlKey))).getSingleOrNull();

  Future<SavedSiteRow?> _byId(String id) => (db.select(
    db.savedSites,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> _upsert(SavedSiteRow site) =>
      db.into(db.savedSites).insertOnConflictUpdate(site);

  /// Narrow writer for the fields the rename/edit sheet owns.
  ///
  /// Needed for the drift trap CLAUDE.md names: an upsert reads a null
  /// `userTitle` as "leave it alone", so clearing a rename would silently do
  /// nothing.
  Future<void> _write(String id, SavedSitesCompanion values) =>
      (db.update(db.savedSites)..where((t) => t.id.equals(id))).write(values);

  Future<int> _nextOrderIndex() async {
    final max = await (db.selectOnly(
      db.savedSites,
    )..addColumns([db.savedSites.orderIndex.max()])).getSingle();
    return (max.read(db.savedSites.orderIndex.max()) ?? 0) + 1;
  }

  // There is deliberately no seeding routine here.
  //
  // The list starts empty and stays empty until the user puts something in it.
  // A pre-seeded site is a recommendation the app is not entitled to make; it
  // also cannot be removed permanently without a flag to remember the removal,
  // and a "supported starting point" is exactly how a neutral reading tool
  // acquires a provider catalogue by accident. The empty state explains how to
  // add one instead.

  Future<SavedSiteRow?> findByUrl(String url) => _byUrlKey(normalizeUrl(url));

  Future<bool> isSaved(String url) async => await findByUrl(url) != null;

  /// Save [url] under [title].
  ///
  /// A URL that normalises to one already saved is never inserted twice.
  /// With [updateExisting] the caller has told the user it is a duplicate and
  /// they chose to edit it; without, the existing row comes back untouched so
  /// the caller can offer exactly that.
  ///
  /// Two pages on one host are two saved sites when their normalised URLs
  /// differ — that is the point of keying on the URL rather than the host.
  Future<SaveSiteResult> save({
    required String url,
    required String title,
    bool updateExisting = false,
    String? editingId,
  }) async {
    final cleanUrl = url.trim();
    final key = normalizeUrl(cleanUrl);
    final now = DateTime.now();
    final existing = await _byUrlKey(key);

    // Editing a row into its own URL is not a duplicate of itself.
    if (existing != null && existing.id != editingId) {
      if (!updateExisting) {
        return SaveSiteResult(SaveSiteOutcome.duplicate, existing);
      }
      final merged = existing.copyWith(
        url: cleanUrl,
        host: Uri.tryParse(cleanUrl)?.host ?? existing.host,
        title: title.trim().isEmpty ? existing.title : title.trim(),
        userTitle: Value(title.trim().isEmpty ? null : title.trim()),
        updatedAt: now,
      );
      await _upsert(merged);
      return SaveSiteResult(SaveSiteOutcome.updated, merged);
    }

    if (editingId != null) {
      final row = await _byId(editingId);
      if (row != null) {
        final merged = row.copyWith(
          url: cleanUrl,
          urlKey: key,
          host: Uri.tryParse(cleanUrl)?.host ?? row.host,
          title: title.trim().isEmpty ? row.title : title.trim(),
          userTitle: Value(title.trim().isEmpty ? null : title.trim()),
          updatedAt: now,
        );
        await _upsert(merged);
        return SaveSiteResult(SaveSiteOutcome.updated, merged);
      }
    }

    final site = SavedSiteRow(
      id: _uuid.v4(),
      url: cleanUrl,
      urlKey: key,
      host: Uri.tryParse(cleanUrl)?.host ?? displayHost(cleanUrl),
      title: title.trim().isEmpty ? displayHost(cleanUrl) : title.trim(),
      createdAt: now,
      updatedAt: now,
      orderIndex: await _nextOrderIndex(),
    );
    await _upsert(site);
    return SaveSiteResult(SaveSiteOutcome.created, site);
  }

  /// Rename. An empty name clears the override and the page title shows
  /// again — which is why the page's own `title` is kept alongside it.
  Future<void> rename(String id, String? userTitle) =>
      _write(id, savedSiteRenameCompanion(userTitle));

  Future<void> markOpened(String id) =>
      _write(id, SavedSitesCompanion(lastOpenedAt: Value(DateTime.now())));

  Future<int> remove(String id) =>
      (db.delete(db.savedSites)..where((t) => t.id.equals(id))).go();

  /// Move [id] one place towards the front (or back).
  ///
  /// Rewrites the whole list's indices rather than swapping two: rows seeded
  /// or imported with equal indices would otherwise swap into a no-op.
  Future<void> move(String id, {required bool up}) async {
    final sites = await all();
    final index = sites.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final target = up ? index - 1 : index + 1;
    if (target < 0 || target >= sites.length) return;
    final reordered = [...sites];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    await reindex(reordered);
  }

  /// Persist an explicit order.
  Future<void> reindex(List<SavedSiteRow> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].orderIndex == i) continue;
      await _write(ordered[i].id, SavedSitesCompanion(orderIndex: Value(i)));
    }
  }
}

SavedSitesCompanion savedSiteRenameCompanion(String? userTitle) =>
    SavedSitesCompanion(
      userTitle: Value(
        userTitle == null || userTitle.trim().isEmpty ? null : userTitle.trim(),
      ),
      updatedAt: Value(DateTime.now()),
    );

/// What the tile shows: the user's name when they set one, else the page's.
String savedSiteDisplayTitle(SavedSiteRow site) {
  final override = site.userTitle?.trim();
  if (override != null && override.isNotEmpty) return override;
  return site.title.trim().isEmpty ? displayHost(site.url) : site.title.trim();
}
