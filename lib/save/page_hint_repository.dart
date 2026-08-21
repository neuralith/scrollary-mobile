import 'package:uuid/uuid.dart';

import '../browser/browser_controller.dart';
import '../storage/database.dart';
import 'page_hint.dart';

const _uuid = Uuid();

/// Reads and writes user-created site rules, and turns a tapped element into
/// one.
class PageHintRepository {
  PageHintRepository(this.db);

  final AppDatabase db;

  Future<UserPageHint?> findFor(String url, HintKind kind) async {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    final rows = await db.hintsForHost(host);
    return bestMatchingHint(rows.map(toModel).toList(), url, kind: kind);
  }

  Future<List<UserPageHint>> all() async =>
      (await db.watchAllHints().first).map(toModel).toList();

  Future<void> delete(String id) => db.deleteHint(id);

  Future<void> recordUse(String id, {required bool success}) =>
      db.recordHintUse(id, success: success);

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
    await db.upsertHint(_toRow(rule));
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
    await db.upsertHint(_toRow(rule));
    return rule;
  }

  /// Teaching a rule for a scope that already has one *replaces* it. Letting
  /// them accumulate would leave the winner decided by a timestamp tie-break,
  /// and would quietly keep a rule the user just corrected.
  Future<void> _replaceSameScope(UserPageHint incoming) async {
    final existing = await db.hintsForHost(incoming.host);
    for (final row in existing) {
      if (row.kind == incoming.kind.name &&
          row.scope == incoming.scope.name &&
          row.hintPath == incoming.hintPath) {
        await db.deleteHint(row.id);
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

  static UserPageHintRow _toRow(UserPageHint rule) => UserPageHintRow(
    id: rule.id,
    host: rule.host,
    hintPath: rule.hintPath,
    scope: rule.scope.name,
    kind: rule.kind.name,
    locatorJson: rule.locator.encode(),
    exampleSourceUrl: rule.exampleSourceUrl,
    exampleTargetUrl: rule.exampleTargetUrl,
    sameHostOnly: rule.sameHostOnly,
    createdAt: rule.createdAt,
    lastUsedAt: rule.lastUsedAt,
    successCount: rule.successCount,
    failureCount: rule.failureCount,
  );
}
