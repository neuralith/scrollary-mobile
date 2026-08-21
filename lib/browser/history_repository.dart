import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../core/url_utils.dart';
import '../storage/database.dart';
import 'browser_url.dart';

const _uuid = Uuid();

/// Who moved the WebView.
///
/// The Browser has exactly one WebView, and save, update checks and rule
/// validation all drive it. The user can watch every one of those navigations
/// happen — which is precisely why "it appeared in the address bar" cannot be
/// the rule for what lands in History. Only [manual] does (D53).
enum NavigationSource {
  /// The user typed, tapped, or opened something themselves.
  manual,

  /// A save run walking the entry chain.
  saveAutomation,

  /// An update check reading a collection index.
  updateCheck,

  /// App-driven navigation that is not a user destination (about:blank, a
  /// re-load to recover a torn-down page).
  internal,

  /// Loading a page to test a saved element rule against it.
  ruleValidation,

  /// A bounded live smoke test driving the Browser.
  liveTest,
}

NavigationSource navigationSourceFromName(String name) => NavigationSource
    .values
    .firstWhere((s) => s.name == name, orElse: () => NavigationSource.internal);

/// Retention (§18). Bounded by both age and row count: either alone leaves a
/// way to grow without limit. Internal for now — no setting was designed, and
/// clearing history stays the user-facing control.
const Duration kHistoryMaxAge = Duration(days: 90);
const int kHistoryMaxRows = 5000;

/// Visits closer together than this to the same page are one visit.
///
/// Individual rows are kept (that is what makes "clear the last hour"
/// accurate), but a reload loop must not stack twelve identical entries.
const Duration kVisitCollapseWindow = Duration(minutes: 30);

/// A hostname with its visit counts — the "Visited sites" aggregate (§9).
///
/// Deliberately *not* a saved site: it is a derived view of history that
/// disappears when those visits are cleared.
class VisitedHost {
  const VisitedHost({
    required this.host,
    required this.visitCount,
    required this.lastVisitedAt,
    required this.latestUrl,
    required this.latestTitle,
  });

  final String host;
  final int visitCount;
  final DateTime lastVisitedAt;

  /// The most recent page seen on this host — the fallback the Add flow saves
  /// when no reliable site root can be derived.
  final String latestUrl;
  final String latestTitle;

  /// A site-level URL, when one can be derived safely. Null means "we only
  /// know pages here", and the Add flow says so instead of inventing one.
  String? get siteRoot => siteRootFor(latestUrl);
}

/// Reading and writing the Browser's own history.
///
/// The recording rule lives here, in one method, so there is exactly one
/// place that can decide a page is worth remembering.
class HistoryRepository {
  HistoryRepository(this.db);

  final AppDatabase db;

  /// URLs that are never a destination, whatever else is true about them.
  static bool isRecordableUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  /// Record a completed manual visit, or decide not to.
  ///
  /// Returns the row that now represents this visit, or null when nothing was
  /// recorded. Every exclusion in §7 funnels through here:
  ///
  ///  * automation of any kind — save, checks, rule validation, internal;
  ///  * anything that is not an `http(s)` page (`about:blank`, app schemes);
  ///  * loads that never completed, or that ended on an error page;
  ///  * a repeat of the same page inside [kVisitCollapseWindow], which
  ///    refreshes the existing row rather than adding one.
  Future<BrowsingHistoryData?> recordVisit({
    required String url,
    required String title,
    required NavigationSource source,
    bool completed = true,
    String? finalUrl,
    DateTime? now,
  }) async {
    if (source != NavigationSource.manual) return null;
    if (!completed) return null;
    final landed = (finalUrl ?? url).trim();
    if (!isRecordableUrl(landed)) return null;

    final at = now ?? DateTime.now();
    final key = normalizeUrl(landed);
    final host = Uri.tryParse(landed)?.host.toLowerCase() ?? '';
    // A page that never reported a title reads better as its host than as an
    // empty row the user cannot identify.
    final label = title.trim().isEmpty ? displayHost(landed) : title.trim();

    final recent = await db.recentVisitTo(
      key,
      source: source.name,
      window: kVisitCollapseWindow,
      now: at,
    );
    final row = BrowsingHistoryData(
      id: recent?.id ?? _uuid.v4(),
      url: landed,
      urlKey: key,
      host: host,
      title: label,
      source: source.name,
      finalUrl: finalUrl != null && finalUrl != url ? finalUrl : null,
      completed: true,
      visitedAt: at,
    );
    await db.insertVisit(row);
    return row;
  }

  Stream<List<BrowsingHistoryData>> watchRecent({int limit = 200}) =>
      db.watchVisits(limit: limit);

  Future<List<BrowsingHistoryData>> recent({int limit = 200}) =>
      db.visits(limit: limit);

  Future<List<BrowsingHistoryData>> search(String query, {int limit = 200}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return db.visits(limit: limit);
    return db.searchVisits(trimmed, limit: limit);
  }

  /// Hostnames with counts, newest-active first (§9).
  ///
  /// Computed from a bounded read rather than a GROUP BY so the same list can
  /// be built from an already-loaded page list without a second query — the
  /// History screen's two tabs share one stream.
  static List<VisitedHost> groupByHost(List<BrowsingHistoryData> visits) {
    final byHost = <String, List<BrowsingHistoryData>>{};
    for (final visit in visits) {
      byHost.putIfAbsent(visit.host, () => []).add(visit);
    }
    final hosts = <VisitedHost>[];
    byHost.forEach((host, rows) {
      rows.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      final latest = rows.first;
      hosts.add(
        VisitedHost(
          host: host,
          visitCount: rows.length,
          lastVisitedAt: latest.visitedAt,
          latestUrl: latest.url,
          latestTitle: latest.title,
        ),
      );
    });
    hosts.sort((a, b) => b.lastVisitedAt.compareTo(a.lastVisitedAt));
    return hosts;
  }

  Future<int> removeVisit(String id) => db.deleteVisit(id);

  Future<int> removeHost(String host) => db.deleteVisitsForHost(host);

  /// How many rows [range] would remove, counted before the user confirms.
  Future<int> countIn(HistoryClearRange range, {DateTime? now}) =>
      db.countVisitsSince(range.since(now ?? DateTime.now()));

  /// Clear a range. Touches `browsing_history` and nothing else: saved sites,
  /// the library, saved files, reading progress, cookies, rules and queue
  /// tasks all live in other tables and are never referenced here.
  Future<int> clear(HistoryClearRange range, {DateTime? now}) =>
      db.deleteVisitsSince(range.since(now ?? DateTime.now()));

  /// Apply the retention bounds. Cheap enough to run at boot; deliberately
  /// not run on every write, where it would turn one insert into a scan.
  Future<int> prune({DateTime? now}) => db.pruneHistory(
    before: (now ?? DateTime.now()).subtract(kHistoryMaxAge),
    keep: kHistoryMaxRows,
  );
}

/// The four ranges the clear sheet offers.
enum HistoryClearRange {
  lastHour,
  today,
  lastSevenDays,
  allTime;

  /// The earliest visit time this range covers. Null means "everything".
  DateTime? since(DateTime now) => switch (this) {
    HistoryClearRange.lastHour => now.subtract(const Duration(hours: 1)),
    // Calendar today, not "the last 24 hours" — the label says Today.
    HistoryClearRange.today => DateTime(now.year, now.month, now.day),
    HistoryClearRange.lastSevenDays => now.subtract(const Duration(days: 7)),
    HistoryClearRange.allTime => null,
  };

  String get label => switch (this) {
    HistoryClearRange.lastHour => 'Last hour',
    HistoryClearRange.today => 'Today',
    HistoryClearRange.lastSevenDays => 'Last 7 days',
    HistoryClearRange.allTime => 'All time',
  };

  String get cta => switch (this) {
    HistoryClearRange.lastHour => 'Clear last hour',
    HistoryClearRange.today => 'Clear today',
    HistoryClearRange.lastSevenDays => 'Clear 7 days',
    HistoryClearRange.allTime => 'Clear all history',
  };
}

/// Date buckets for the History list.
enum HistoryDayGroup {
  today,
  yesterday,
  earlier;

  String get label => switch (this) {
    HistoryDayGroup.today => 'Today',
    HistoryDayGroup.yesterday => 'Yesterday',
    HistoryDayGroup.earlier => 'Earlier',
  };
}

HistoryDayGroup historyGroupFor(DateTime visitedAt, DateTime now) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  if (!visitedAt.isBefore(startOfToday)) return HistoryDayGroup.today;
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  if (!visitedAt.isBefore(startOfYesterday)) return HistoryDayGroup.yesterday;
  return HistoryDayGroup.earlier;
}

/// Grouped, in display order, with empty groups dropped.
List<(HistoryDayGroup, List<BrowsingHistoryData>)> groupVisitsByDay(
  List<BrowsingHistoryData> visits, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final buckets = <HistoryDayGroup, List<BrowsingHistoryData>>{};
  for (final visit in visits) {
    buckets
        .putIfAbsent(historyGroupFor(visit.visitedAt, at), () => [])
        .add(visit);
  }
  return [
    for (final group in HistoryDayGroup.values)
      if ((buckets[group] ?? const []).isNotEmpty) (group, buckets[group]!),
  ];
}

/// Companion helper so callers do not import drift just to clear a title.
SavedSitesCompanion savedSiteTitleUpdate(String? userTitle) =>
    SavedSitesCompanion(
      userTitle: Value(
        userTitle == null || userTitle.trim().isEmpty ? null : userTitle.trim(),
      ),
      updatedAt: Value(DateTime.now()),
    );
