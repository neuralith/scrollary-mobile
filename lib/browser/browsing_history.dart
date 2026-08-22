/// The Browser's history vocabulary: who moved the WebView, how long a visit
/// is kept, and how the History screen groups what it reads.
///
/// V1's `HistoryRepository` lived here and is gone. Its rows moved to the V2
/// `history` table, which the recognition pipeline reads too — two tables
/// holding the same fact is how they come to disagree — and the recording
/// rule with them: `HistoryStore` (`lib/recognition/history.dart`) refuses
/// anything that is not a completed, user-performed load of a web page, and
/// `BrowsingHistoryStore` (`lib/features/v2_composition.dart`) carries the
/// collapse window and the retention sweep. What stays here is what neither
/// of those owns: the vocabulary the browser surface and the History screen
/// are written in.
library;

import 'browser_url.dart';
import '../data/schema.dart' show HistoryRow;

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

/// Hostnames with counts, newest-active first (§9).
///
/// Computed from a bounded read rather than a GROUP BY so the same list can be
/// built from an already-loaded page list without a second query — the History
/// screen's two tabs share one stream.
List<VisitedHost> groupVisitsByHost(List<HistoryRow> visits) {
  final byHost = <String, List<HistoryRow>>{};
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

/// Grouped, in display order, with empty groups dropped.
List<(HistoryDayGroup, List<HistoryRow>)> groupVisitsByDay(
  List<HistoryRow> visits, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final buckets = <HistoryDayGroup, List<HistoryRow>>{};
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
