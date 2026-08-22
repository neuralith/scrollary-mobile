import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../browser/browser_controller.dart';
import '../data/schema.dart';
import '../storage/database.dart';
import 'page_hint.dart';

const _uuid = Uuid();

/// Where the rules a person taught are kept.
///
/// Two implementations, because the V1 and V2 schemas coexist until the V1
/// cleanup points and must never share a database. The rule-building above
/// this — what signals a tapped element yields, how widely a rule applies,
/// which of several rules wins — is the same in both and lives once, in
/// [PageHintRepository].
abstract interface class PageHintStore {
  Future<List<UserPageHint>> forHost(String host);
  Stream<List<UserPageHint>> watchAll();
  Future<void> upsert(UserPageHint hint);
  Future<void> delete(String id);
  Future<void> recordUse(String id, {required bool success});
}

/// Reads and writes user-created site rules, and turns a tapped element into
/// one.
class PageHintRepository {
  /// Over the V1 database, which is where the retired save run kept them.
  PageHintRepository(AppDatabase db) : store = _V1PageHintStore(db);

  /// Over the V2 library's `page_hints` table — what the V2 capture path
  /// reads, and the only table a hint is written to from here on.
  PageHintRepository.forLibrary(LibraryDatabase db)
    : store = _LibraryPageHintStore(db);

  final PageHintStore store;

  Future<UserPageHint?> findFor(String url, HintKind kind) async {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    return bestMatchingHint(await store.forHost(host), url, kind: kind);
  }

  Future<List<UserPageHint>> all() async => store.watchAll().first;

  Stream<List<UserPageHint>> watchAll() => store.watchAll();

  Future<void> delete(String id) => store.delete(id);

  Future<void> recordUse(String id, {required bool success}) =>
      store.recordUse(id, success: success);

  /// Build a rule from what the user tapped.
  ///
  /// Signals are collected redundantly: `rel`, a conservative selector, the
  /// nav container, the label, and the destination's path shape. If only one
  /// survives, the rule is stored anyway but reported as weak rather than
  /// dressed up as stable.
  Future<UserPageHint> createNextLinkHint({
    required SelectedElement element,
    required String sourceUrl,
    HintScope scope = HintScope.collection,
  }) async {
    final host = Uri.tryParse(sourceUrl)?.host ?? '';
    final locator = DomLocator(
      tag: element.tag,
      rel: element.rel.isEmpty ? null : element.rel,
      cssSelector: element.selector,
      containerSelector: element.containerSelector,
      linkText: element.text.isEmpty ? null : element.text,
      ariaLabel: element.ariaLabel.isEmpty ? null : element.ariaLabel,
      titleAttr: element.title.isEmpty ? null : element.title,
      imgAlt: element.imgAlt.isEmpty ? null : element.imgAlt,
      hrefPattern: element.href.isEmpty ? null : hrefPatternFrom(element.href),
    );

    final rule = UserPageHint(
      id: _uuid.v4(),
      host: host,
      hintPath: _scopeKey(scope, sourceUrl),
      scope: scope,
      kind: HintKind.nextLink,
      locator: locator,
      exampleSourceUrl: sourceUrl,
      exampleTargetUrl: element.href.isEmpty ? null : element.href,
      createdAt: DateTime.now(),
    );
    await _replaceSameScope(rule);
    await store.upsert(rule);
    return rule;
  }

  Future<UserPageHint> createReaderAreaHint({
    required SelectedElement element,
    required String sourceUrl,
    List<String> excludeSelectors = const [],
    HintScope scope = HintScope.collection,
  }) async {
    final host = Uri.tryParse(sourceUrl)?.host ?? '';
    final locator = DomLocator(
      tag: element.tag,
      containerSelector: element.selector ?? element.containerSelector,
      imageSelector: element.imageSelector ?? 'img',
      excludeSelectors: excludeSelectors,
      // A floor derived from what is actually in the container, never below a
      // size that would sweep icons back in.
      minImageEdge: element.minImageEdge > 0
          ? (element.minImageEdge * 0.8).round().clamp(100, 2000)
          : 300,
    );

    final rule = UserPageHint(
      id: _uuid.v4(),
      host: host,
      hintPath: _scopeKey(scope, sourceUrl),
      scope: scope,
      kind: HintKind.readerArea,
      locator: locator,
      exampleSourceUrl: sourceUrl,
      createdAt: DateTime.now(),
    );
    await _replaceSameScope(rule);
    await store.upsert(rule);
    return rule;
  }

  /// Teaching a rule for a scope that already has one *replaces* it. Letting
  /// them accumulate would leave the winner decided by a timestamp tie-break,
  /// and would quietly keep a rule the user just corrected.
  Future<void> _replaceSameScope(UserPageHint incoming) async {
    for (final existing in await store.forHost(incoming.host)) {
      if (existing.kind == incoming.kind &&
          existing.scope == incoming.scope &&
          existing.hintPath == incoming.hintPath) {
        await store.delete(existing.id);
      }
    }
  }

  static String? _scopeKey(HintScope scope, String url) => switch (scope) {
    HintScope.collection => collectionFingerprint(url),
    HintScope.pathPattern => pathShape(Uri.tryParse(url)?.path ?? ''),
    HintScope.host => null,
  };

  static UserPageHint toModel(UserPageHintRow row) => UserPageHint(
    id: row.id,
    host: row.host,
    hintPath: row.hintPath,
    scope: hintScopeFromName(row.scope),
    kind: hintKindFromName(row.kind),
    locator: DomLocator.decode(row.locatorJson),
    exampleSourceUrl: row.exampleSourceUrl,
    exampleTargetUrl: row.exampleTargetUrl,
    sameHostOnly: row.sameHostOnly,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    successCount: row.successCount,
    failureCount: row.failureCount,
  );
}

class _V1PageHintStore implements PageHintStore {
  _V1PageHintStore(this.db);

  final AppDatabase db;

  @override
  Future<List<UserPageHint>> forHost(String host) async =>
      (await db.hintsForHost(host)).map(PageHintRepository.toModel).toList();

  @override
  Stream<List<UserPageHint>> watchAll() => db.watchAllHints().map(
    (rows) => rows.map(PageHintRepository.toModel).toList(),
  );

  @override
  Future<void> upsert(UserPageHint hint) => db.upsertHint(
    UserPageHintRow(
      id: hint.id,
      host: hint.host,
      hintPath: hint.hintPath,
      scope: hint.scope.name,
      kind: hint.kind.name,
      locatorJson: hint.locator.encode(),
      exampleSourceUrl: hint.exampleSourceUrl,
      exampleTargetUrl: hint.exampleTargetUrl,
      sameHostOnly: hint.sameHostOnly,
      createdAt: hint.createdAt,
      lastUsedAt: hint.lastUsedAt,
      successCount: hint.successCount,
      failureCount: hint.failureCount,
    ),
  );

  @override
  Future<void> delete(String id) => db.deleteHint(id);

  @override
  Future<void> recordUse(String id, {required bool success}) =>
      db.recordHintUse(id, success: success);
}

/// The V2 store. The queries live here rather than on [LibraryDatabase]
/// because a rule is a save-lane concept: the library knows nothing about it
/// beyond holding the row.
class _LibraryPageHintStore implements PageHintStore {
  _LibraryPageHintStore(this.db);

  final LibraryDatabase db;

  @override
  Future<List<UserPageHint>> forHost(String host) async => (await (db.select(
    db.pageHints,
  )..where((t) => t.host.equals(host))).get()).map(_toModel).toList();

  @override
  Stream<List<UserPageHint>> watchAll() =>
      (db.select(db.pageHints)..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
          .watch()
          .map((rows) => rows.map(_toModel).toList());

  @override
  Future<void> upsert(UserPageHint hint) => db
      .into(db.pageHints)
      .insertOnConflictUpdate(
        PageHintRow(
          id: hint.id,
          host: hint.host,
          hintPath: hint.hintPath,
          scope: hint.scope.name,
          kind: hint.kind.name,
          locatorJson: hint.locator.encode(),
          exampleSourceUrl: hint.exampleSourceUrl,
          exampleTargetUrl: hint.exampleTargetUrl,
          sameHostOnly: hint.sameHostOnly,
          createdAt: hint.createdAt,
          lastUsedAt: hint.lastUsedAt,
          successCount: hint.successCount,
          failureCount: hint.failureCount,
        ),
      );

  @override
  Future<void> delete(String id) =>
      (db.delete(db.pageHints)..where((t) => t.id.equals(id))).go();

  /// The same arithmetic V1 used: a success moves `lastUsedAt`, a failure
  /// only counts. A rule the user just fixed therefore wins the
  /// most-recently-used tie-break over one that keeps missing.
  @override
  Future<void> recordUse(String id, {required bool success}) async {
    final row = await (db.select(
      db.pageHints,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (db.update(db.pageHints)..where((t) => t.id.equals(id))).write(
      PageHintsCompanion(
        lastUsedAt: Value(success ? DateTime.now() : row.lastUsedAt),
        successCount: Value(success ? row.successCount + 1 : row.successCount),
        failureCount: Value(success ? row.failureCount : row.failureCount + 1),
      ),
    );
  }

  static UserPageHint _toModel(PageHintRow row) => UserPageHint(
    id: row.id,
    host: row.host,
    hintPath: row.hintPath,
    scope: hintScopeFromName(row.scope),
    kind: hintKindFromName(row.kind),
    locator: DomLocator.decode(row.locatorJson),
    exampleSourceUrl: row.exampleSourceUrl,
    exampleTargetUrl: row.exampleTargetUrl,
    sameHostOnly: row.sameHostOnly,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    successCount: row.successCount,
    failureCount: row.failureCount,
  );
}
