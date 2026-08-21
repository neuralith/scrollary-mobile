import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_url.dart';
import '../browser/history_repository.dart';
import '../providers.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'browser_data_dialogs.dart';
import 'browser_ui.dart';
import 'open_in_browser.dart';
import 'saved_site_sheets.dart';

/// The full History screen: date-grouped pages, hostname-grouped sites,
/// search, and the clear flow.
///
/// Everything on it is local and manual — automation navigations were never
/// written, so there is nothing to filter out here (D53).
class BrowserHistoryScreen extends ConsumerStatefulWidget {
  const BrowserHistoryScreen({super.key});

  @override
  ConsumerState<BrowserHistoryScreen> createState() =>
      _BrowserHistoryScreenState();
}

class _BrowserHistoryScreenState extends ConsumerState<BrowserHistoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _tab = 0;
  String? _expandedHost;

  static const Duration _debounceDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Filtering happens against the already-loaded bounded stream, so typing
  /// costs a rebuild rather than a query. The debounce is still here because
  /// at the stream's limit that rebuild walks 500 rows per keystroke (§20).
  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _query = value);
    });
  }

  List<BrowsingHistoryData> _filter(List<BrowsingHistoryData> visits) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return visits;
    return visits
        .where(
          (v) =>
              v.title.toLowerCase().contains(needle) ||
              v.url.toLowerCase().contains(needle) ||
              v.host.toLowerCase().contains(needle),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final async = ref.watch(browsingHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton(
            key: const ValueKey('historyClearButton'),
            onPressed: () => showClearHistorySheet(context, ref),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: BrowserSearchField(
              key: const ValueKey('historySearchField'),
              hint: 'Search title, URL or site',
              controller: _search,
              height: 38,
              onChanged: _onQueryChanged,
              onClear: () {
                _search.clear();
                _onQueryChanged('');
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: BrowserSegmented(
              labels: const ['Pages', 'Sites'],
              selected: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
          ),
          Divider(height: 1, color: palette.divider),
          Expanded(
            child: async.when(
              loading: () => const _HistorySkeleton(),
              error: (error, _) => BrowserEmptyState(
                icon: Icons.error_outline,
                title: 'History is unavailable',
                body:
                    "The history store couldn't be read. Your saved sites and "
                    'library are unaffected.',
              ),
              data: (all) {
                final visits = _filter(all);
                if (visits.isEmpty) {
                  final searching = _query.trim().isNotEmpty;
                  return BrowserEmptyState(
                    icon: searching ? Icons.search_off : Icons.history,
                    title: searching ? 'No matches' : 'No history yet',
                    body: searching
                        ? 'Nothing in your history matches '
                              '“${_query.trim()}”. Try a site name instead.'
                        : 'Pages you open in the Browser show up here. '
                              'Nothing is sent anywhere.',
                  );
                }
                return _tab == 0
                    ? _PagesTab(visits: visits, onMenu: _showRowMenu)
                    : _SitesTab(
                        visits: visits,
                        expandedHost: _expandedHost,
                        onToggleHost: (host) => setState(
                          () => _expandedHost = _expandedHost == host
                              ? null
                              : host,
                        ),
                        onRemoveHost: _removeHost,
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRowMenu(BrowsingHistoryData visit) async {
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Six rows plus a two-line header do not fit on a short screen in
      // landscape; the sheet scrolls rather than clipping an action off the
      // bottom where nobody can reach it.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontVariations: wght(600),
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      shortUrl(visit.url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 11, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.north_east),
                title: const Text('Open'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _open(visit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add),
                title: const Text('Add to saved sites'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showSaveSiteSheet(
                    context,
                    url: visit.url,
                    title: visit.title,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copy URL'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: visit.url));
                  messenger?.showSnackBar(
                    const SnackBar(content: Text('URL copied')),
                  );
                },
              ),
              ListTile(
                key: const ValueKey('historyRemoveVisit'),
                leading: Icon(Icons.delete_outline, color: palette.danger),
                title: Text(
                  'Remove this visit',
                  style: TextStyle(color: palette.danger),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref.read(historyRepositoryProvider).removeVisit(visit.id);
                },
              ),
              ListTile(
                key: const ValueKey('historyRemoveHost'),
                leading: Icon(Icons.delete_sweep, color: palette.danger),
                title: Text(
                  'Remove all visits from ${visit.host}',
                  style: TextStyle(color: palette.danger),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _removeHost(visit.host);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Opening from History goes through the same coordinator as every other
  /// source-page action.
  ///
  /// It used to pop one route and switch the tab, which is right only when
  /// History was reached directly from the Browser — reached from
  /// Settings it landed the user back on Settings, with the page loaded
  /// somewhere they could not see.
  void _open(BrowsingHistoryData visit) {
    // No reachability probe: a history row is a page the user has already
    // been to, and the Browser's own offline state explains it better than a
    // snackbar that refuses to move.
    openInBrowser(context, ref, visit.url, checkConnectivity: false);
  }

  Future<void> _removeHost(String host) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.delete_sweep, color: palette.danger),
        title: Text('Remove history for $host?'),
        content: const Text(
          'Every visit to this site is removed from your history. Saved '
          'sites, your library and any sign-in you have there are kept.',
          style: TextStyle(fontSize: 13.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref.read(historyRepositoryProvider).removeHost(host);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Removed $removed visits from $host')),
    );
  }
}

class _PagesTab extends StatelessWidget {
  const _PagesTab({required this.visits, required this.onMenu});

  final List<BrowsingHistoryData> visits;
  final void Function(BrowsingHistoryData) onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final groups = groupVisitsByDay(visits);
    // Flattened into one lazy list rather than nested Columns: a seeded
    // 10,000-row history has to scroll without building every row (§20).
    final rows = <Widget>[];
    for (final (group, items) in groups) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            group.label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.72,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.inkMuted,
            ),
          ),
        ),
      );
      for (final visit in items) {
        rows.add(
          BrowserListRow(
            key: ValueKey('historyRow-${visit.id}'),
            host: visit.host,
            title: visit.title,
            subtitle: shortUrl(visit.url),
            trailing: Text(
              formatVisitTime(visit.visitedAt),
              style: monoStyle(size: 11, color: palette.inkGhost),
            ),
            onTap: () => onMenu(visit),
            onMenu: () => onMenu(visit),
          ),
        );
      }
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }
}

class _SitesTab extends StatelessWidget {
  const _SitesTab({
    required this.visits,
    required this.expandedHost,
    required this.onToggleHost,
    required this.onRemoveHost,
  });

  final List<BrowsingHistoryData> visits;
  final String? expandedHost;
  final void Function(String host) onToggleHost;
  final void Function(String host) onRemoveHost;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hosts = HistoryRepository.groupByHost(visits);
    return ListView.builder(
      itemCount: hosts.length,
      itemBuilder: (context, i) {
        final host = hosts[i];
        final expanded = expandedHost == host.host;
        final pages = visits.where((v) => v.host == host.host).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('historyHost-${host.host}'),
              onTap: () => onToggleHost(host.host),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  color: expanded ? palette.surfaceMuted : null,
                  border: Border(bottom: BorderSide(color: palette.hairline)),
                ),
                child: Row(
                  children: [
                    FaviconTile(host: host.host, size: 30, radius: 9),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            host.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontVariations: wght(500),
                              fontWeight: FontWeight.w500,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${host.visitCount} '
                            '${host.visitCount == 1 ? 'visit' : 'visits'} · '
                            'last ${formatVisitTime(host.lastVisitedAt)}',
                            style: monoStyle(size: 11, color: palette.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: palette.inkDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              ColoredBox(
                color: palette.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final page in pages.take(8))
                      Padding(
                        padding: const EdgeInsets.only(left: 39),
                        child: BrowserListRow(
                          key: ValueKey('historyHostPage-${page.id}'),
                          host: page.host,
                          title: page.title,
                          subtitle:
                              '${pathAndQuery(page.url)} · '
                              '${formatVisitTime(page.visitedAt)}',
                          iconSize: 20,
                          dense: true,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(55, 10, 16, 12),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: () => showSaveSiteSheet(
                              context,
                              url: host.siteRoot ?? host.latestUrl,
                              title: host.siteRoot != null
                                  ? host.host.split('.').first
                                  : host.latestTitle,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Add to Saved Sites'),
                          ),
                          TextButton(
                            onPressed: () => onRemoveHost(host.host),
                            style: TextButton.styleFrom(
                              foregroundColor: palette.danger,
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Remove site history'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      children: [
        for (final width in [0.7, 0.55, 0.78, 0.48, 0.66])
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: width,
                        child: Container(height: 10, color: palette.divider),
                      ),
                      const SizedBox(height: 7),
                      FractionallySizedBox(
                        widthFactor: 0.4,
                        child: Container(height: 8, color: palette.hairline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
