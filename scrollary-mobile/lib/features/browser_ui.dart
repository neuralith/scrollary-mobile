import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_url.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// The site icon, at a fixed size, always.
///
/// The box is drawn before anything is fetched and never changes size, so an
/// icon arriving late repaints one square rather than reflowing the list
/// (§12). A miss is not a failure state — the hostname initial on a stable
/// tinted tile is the designed fallback, not a placeholder for something
/// better.
class FaviconTile extends ConsumerStatefulWidget {
  const FaviconTile({
    super.key,
    required this.host,
    this.size = 28,
    this.radius = 8,
    this.pageIconUrl,
  });

  final String host;
  final double size;
  final double radius;

  /// The icon the page declared, when the caller happens to know it. A much
  /// better source than the guessed `/favicon.ico`.
  final String? pageIconUrl;

  @override
  ConsumerState<FaviconTile> createState() => _FaviconTileState();
}

class _FaviconTileState extends ConsumerState<FaviconTile> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(FaviconTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host ||
        oldWidget.pageIconUrl != widget.pageIconUrl) {
      _request();
    }
  }

  /// Deferred past the current frame: `request` can complete synchronously
  /// from the in-memory cache and notify listeners, and notifying during
  /// build is an error.
  void _request() {
    if (widget.host.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(faviconServiceProvider)
          .request(widget.host, pageIcon: widget.pageIconUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final service = ref.watch(faviconServiceProvider);
    final (bg, fg) = faviconColorsFor(widget.host, palette: palette);

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final bytes = service.cached(widget.host);
        return SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: bytes == null
                ? Center(
                    child: Text(
                      faviconInitial(widget.host),
                      style: monoStyle(
                        size: widget.size * 0.44,
                        color: fg,
                      ).copyWith(fontWeight: FontWeight.w600, height: 1),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: Padding(
                      padding: EdgeInsets.all(widget.size * 0.15),
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        // A corrupt cached icon must not take the row with
                        // it; fall through to the letter.
                        errorBuilder: (context, _, _) => Center(
                          child: Text(
                            faviconInitial(widget.host),
                            style: monoStyle(
                              size: widget.size * 0.44,
                              color: fg,
                            ).copyWith(fontWeight: FontWeight.w600, height: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// The row shape shared by Recently Visited, History, suggestions and the
/// Add-site pickers: icon · title over subtitle · optional trailing.
class BrowserListRow extends StatelessWidget {
  const BrowserListRow({
    super.key,
    required this.host,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.onMenu,
    this.menuTooltip = 'More',
    this.iconSize = 28,
    this.dense = false,
  });

  final String host;
  final String title;
  final String subtitle;

  /// Right-aligned metadata (a visit time, a "Saved" flag).
  final Widget? trailing;
  final VoidCallback? onTap;

  /// When set, an overflow button is drawn after [trailing].
  final VoidCallback? onMenu;
  final String menuTooltip;
  final double iconSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            dense ? 9 : 11,
            onMenu == null ? 16 : 4,
            dense ? 9 : 11,
          ),
          child: Row(
            children: [
              FaviconTile(host: host, size: iconSize),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: palette.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 11, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (onMenu != null)
                IconButton(
                  onPressed: onMenu,
                  tooltip: menuTooltip,
                  iconSize: 19,
                  visualDensity: VisualDensity.compact,
                  color: palette.inkGhost,
                  icon: const Icon(Icons.more_vert),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's uppercase section label with an optional trailing action.
class BrowserSectionHeader extends StatelessWidget {
  const BrowserSectionHeader({
    super.key,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.72,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.inkMuted,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontVariations: wght(600),
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dashed-border empty block the design uses inside Browser Home.
class BrowserEmptyBlock extends StatelessWidget {
  const BrowserEmptyBlock({
    super.key,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: palette.inkMuted,
              ),
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onCta,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 9,
                ),
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              child: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-screen empty / no-results state.
class BrowserEmptyState extends StatelessWidget {
  const BrowserEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: palette.inkGhost),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.5,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded search / address field used on Browser Home and in History.
class BrowserSearchField extends StatelessWidget {
  const BrowserSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onTap,
    this.onChanged,
    this.readOnly = false,
    this.autofocus = false,
    this.onClear,
    this.height = 44,
  });

  final String hint;
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool autofocus;
  final VoidCallback? onClear;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final decoration = BoxDecoration(
      color: palette.surfaceInset,
      borderRadius: BorderRadius.circular(height >= 44 ? 14 : 999),
      border: Border.all(color: palette.borderInset),
    );

    if (readOnly) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height >= 44 ? 14 : 999),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: decoration,
            child: Row(
              children: [
                Icon(Icons.search, size: 19, color: palette.inkMuted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    hint,
                    style: TextStyle(fontSize: 13.5, color: palette.inkFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 11, right: 4),
      decoration: decoration,
      child: Row(
        children: [
          Icon(Icons.search, size: 17, color: palette.inkMuted),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 13, color: palette.ink),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: palette.inkFaint),
              ),
            ),
          ),
          if (onClear != null && (controller?.text.isNotEmpty ?? false))
            IconButton(
              onPressed: onClear,
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              color: palette.inkMuted,
              tooltip: 'Clear',
              icon: const Icon(Icons.cancel),
            ),
        ],
      ),
    );
  }
}

/// The design's two-up segmented control (History's Pages/Sites, the Add
/// sheet's Recent/Visited).
class BrowserSegmented extends StatelessWidget {
  const BrowserSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.borderInset),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == selected ? palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == selected && !palette.isDark
                        ? [
                            BoxShadow(
                              color: palette.shadow,
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontVariations: wght(i == selected ? 600 : 400),
                      fontWeight: i == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: i == selected ? palette.ink : palette.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "4 min ago" / "yesterday 21:40" / "12 Jul", as the design writes them.
String formatVisitTime(DateTime at, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final delta = reference.difference(at);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';

  final startOfToday = DateTime(reference.year, reference.month, reference.day);
  final time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  if (!at.isBefore(startOfToday)) {
    return delta.inHours < 6 ? '${delta.inHours} h ago' : time;
  }
  if (!at.isBefore(startOfToday.subtract(const Duration(days: 1)))) {
    return 'yesterday $time';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${at.day} ${months[at.month - 1]}';
  return at.year == reference.year ? date : '$date ${at.year}';
}
