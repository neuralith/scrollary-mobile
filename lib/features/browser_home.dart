import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_presentation.dart';
import '../browser/browser_url.dart';
import '../browser/saved_sites_repository.dart';
import '../providers.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'browser_ui.dart';

/// The local Browser Home, drawn **over** the live WebView.
///
/// It is a layer, not a route and not a replacement: the page underneath
/// stays mounted, so closing this reveals the same document — same scroll
/// position, same cookies, same in-page state — without a reload (D52). The
/// only thing that changes is what the user is looking at.
class BrowserHome extends ConsumerWidget {
  const BrowserHome({
    super.key,
    required this.preserved,
    required this.onClose,
    required this.onOpenAddressEditor,
    required this.onOpenUrl,
    required this.onOpenHistory,
    required this.onAddSite,
    required this.onEditSite,
  });

  /// The page behind this surface, if there is one.
  final PreservedPage? preserved;

  final VoidCallback onClose;
  final VoidCallback onOpenAddressEditor;

  /// Open a page in the existing WebView.
  final void Function(String url, String title) onOpenUrl;
  final VoidCallback onOpenHistory;
  final VoidCallback onAddSite;
  final void Function(SavedSite site) onEditSite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final hasPage = preserved != null && !preserved!.isEmpty;

    return Material(
      color: palette.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(hasPage: hasPage, onClose: onClose),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 14, bottom: 90),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: BrowserSearchField(
                      key: const ValueKey('browserHomeSearch'),
                      hint: 'Search or enter address',
                      readOnly: true,
                      onTap: onOpenAddressEditor,
                    ),
                  ),
                  if (hasPage)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: _PreservedPageCard(
                        page: preserved!,
                        onTap: onClose,
                      ),
                    ),
                  _SavedSitesSection(
                    onOpenUrl: onOpenUrl,
                    onAddSite: onAddSite,
                    onEditSite: onEditSite,
                  ),
                  _RecentlyVisitedSection(
                    onOpenUrl: onOpenUrl,
                    onOpenHistory: onOpenHistory,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasPage, required this.onClose});

  final bool hasPage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Browser',
              style: TextStyle(
                fontSize: 15.5,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          // Only offered when there is something behind this surface; on a
          // cold start there is no page to go back to and the affordance
          // would be a lie.
          if (hasPage)
            TextButton.icon(
              key: const ValueKey('browserHomeBackToPage'),
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Page'),
              style: TextButton.styleFrom(
                foregroundColor: palette.inkStrong,
                backgroundColor: palette.surfaceInset,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: palette.borderInset),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreservedPageCard extends StatelessWidget {
  const _PreservedPageCard({required this.page, required this.onTap});

  final PreservedPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final host = displayHost(page.url);
    return Material(
      color: palette.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.primaryBorder),
          ),
          child: Row(
            children: [
              FaviconTile(host: host, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      page.title.isEmpty ? host : page.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontVariations: wght(600),
                        fontWeight: FontWeight.w600,
                        color: palette.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Literal, and true: the WebView was never torn down.
                      'still open · scroll position kept',
                      style: monoStyle(
                        size: 11,
                        color: palette.onPrimaryContainer.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 19, color: palette.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedSitesSection extends ConsumerStatefulWidget {
  const _SavedSitesSection({
    required this.onOpenUrl,
    required this.onAddSite,
    required this.onEditSite,
  });

  final void Function(String url, String title) onOpenUrl;
  final VoidCallback onAddSite;
  final void Function(SavedSite site) onEditSite;

  @override
  ConsumerState<_SavedSitesSection> createState() => _SavedSitesSectionState();
}

class _SavedSitesSectionState extends ConsumerState<_SavedSitesSection> {
  bool _reordering = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sites = ref.watch(savedSitesProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrowserSectionHeader(
          label: 'Saved sites',
          actionLabel: (sites?.isEmpty ?? true)
              ? null
              : (_reordering ? 'Done' : 'Reorder'),
          onAction: (sites?.isEmpty ?? true)
              ? null
              : () => setState(() => _reordering = !_reordering),
        ),
        if (sites == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(height: 92),
          )
        else if (sites.isEmpty)
          BrowserEmptyBlock(
            title: 'No saved sites yet',
            body: "Save the sites you read on so they're one tap away.",
            ctaLabel: 'Add a site',
            onCta: widget.onAddSite,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The design's `repeat(auto-fill, minmax(96px, 1fr))`. At
                // 320pt this is three columns, not a squeezed four.
                final columns = ((constraints.maxWidth + 8) / 104)
                    .floor()
                    .clamp(2, 5);
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.05,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < sites.length; i++)
                      _SavedSiteTile(
                        site: sites[i],
                        reordering: _reordering,
                        canMoveUp: i > 0,
                        canMoveDown: i < sites.length - 1,
                        onOpen: () => _open(sites[i]),
                        onEdit: () => widget.onEditSite(sites[i]),
                        onMove: (up) => ref
                            .read(savedSitesRepositoryProvider)
                            .move(sites[i].id, up: up),
                        onRemove: () => _remove(sites[i]),
                      ),
                    _AddSiteTile(onTap: widget.onAddSite),
                  ],
                );
              },
            ),
          ),
        if (sites != null && sites.isNotEmpty && _reordering)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              'Long press a tile to rename it or change its address.',
              style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
            ),
          ),
      ],
    );
  }

  void _open(SavedSite site) {
    unawaitedMarkOpened(ref, site.id);
    widget.onOpenUrl(site.url, savedSiteDisplayTitle(site));
  }

  Future<void> _remove(SavedSite site) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref.read(savedSitesRepositoryProvider).remove(site.id);
    if (!mounted) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${savedSiteDisplayTitle(site)} from saved sites',
          ),
          action: SnackBarAction(
            label: 'Undo',
            // Re-saving restores the row's content, not its identity — the
            // id is new. Nothing references a saved site by id, so this is
            // an undo in every sense the user can observe.
            onPressed: () => ref
                .read(savedSitesRepositoryProvider)
                .save(
                  url: site.url,
                  title: savedSiteDisplayTitle(site),
                  updateExisting: true,
                ),
          ),
        ),
      );
  }
}

/// Fire-and-forget "last opened" stamp. Never blocks the navigation.
void unawaitedMarkOpened(WidgetRef ref, String id) {
  ref.read(savedSitesRepositoryProvider).markOpened(id).ignore();
}

class _SavedSiteTile extends StatelessWidget {
  const _SavedSiteTile({
    required this.site,
    required this.reordering,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onOpen,
    required this.onEdit,
    required this.onMove,
    required this.onRemove,
  });

  final SavedSite site;
  final bool reordering;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final void Function(bool up) onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final title = savedSiteDisplayTitle(site);
    final host = displayHost(site.url);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('savedSite-${site.id}'),
              onTap: reordering ? null : onOpen,
              // Long press explains and edits — the same grammar as the
              // entry list (D44).
              onLongPress: reordering ? null : onEdit,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FaviconTile(host: host, size: 30, radius: 9),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 10, color: palette.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (reordering)
            ColoredBox(
              color: palette.surface.withValues(alpha: 0.88),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TileAction(
                    icon: Icons.arrow_upward,
                    tooltip: 'Move up',
                    onPressed: canMoveUp ? () => onMove(true) : null,
                  ),
                  const SizedBox(width: 4),
                  _TileAction(
                    icon: Icons.arrow_downward,
                    tooltip: 'Move down',
                    onPressed: canMoveDown ? () => onMove(false) : null,
                  ),
                  const SizedBox(width: 4),
                  _TileAction(
                    icon: Icons.close,
                    tooltip: 'Remove',
                    danger: true,
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = onPressed == null
        ? palette.inkDisabled
        : (danger ? palette.danger : palette.inkStrong);
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 30,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(color: palette.border),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(9),
            child: Icon(icon, size: 17, color: fg),
          ),
        ),
      ),
    );
  }
}

class _AddSiteTile extends StatelessWidget {
  const _AddSiteTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('addSavedSiteTile'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.add, size: 22, color: palette.inkMuted),
              const SizedBox(height: 8),
              Text(
                'Add site',
                style: TextStyle(
                  fontSize: 12.5,
                  fontVariations: wght(500),
                  fontWeight: FontWeight.w500,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentlyVisitedSection extends ConsumerWidget {
  const _RecentlyVisitedSection({
    required this.onOpenUrl,
    required this.onOpenHistory,
  });

  final void Function(String url, String title) onOpenUrl;
  final VoidCallback onOpenHistory;

  /// Four rows, as drawn. Bounded here rather than in the query so the
  /// History screen can share the same stream (§20).
  static const int _maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final history = ref.watch(browsingHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrowserSectionHeader(
          label: 'Recently visited',
          actionLabel: 'Full history',
          onAction: onOpenHistory,
        ),
        history.when(
          loading: () => const SizedBox(height: 60),
          error: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'History is unavailable right now.',
              style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
            ),
          ),
          data: (visits) {
            if (visits.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Pages you open in the Browser show up here. Nothing is '
                  'sent anywhere.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: palette.inkMuted,
                  ),
                ),
              );
            }
            return Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: palette.divider)),
                  ),
                  child: Column(
                    children: [
                      for (final visit in visits.take(_maxRows))
                        BrowserListRow(
                          key: ValueKey('recentVisit-${visit.id}'),
                          host: visit.host,
                          title: visit.title,
                          subtitle: shortUrl(visit.url),
                          trailing: Text(
                            formatVisitTime(visit.visitedAt),
                            style: monoStyle(size: 11, color: palette.inkGhost),
                          ),
                          onTap: () => onOpenUrl(visit.url, visit.title),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
