import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../browser/browser_controller.dart';
import '../browser/browser_url.dart';
import '../core/url_utils.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// What the page-actions sheet decided to do. The Browser owns the
/// consequences — the sheet only reports the choice, so save and saving
/// keep their existing flows rather than growing a second copy here.
enum PageAction { save, addToSavedSites, findInPage, none }

/// The design's page-actions sheet.
///
/// Actions that cannot apply are absent, not disabled-and-mysterious: on a
/// blank Browser there is nothing to copy, share or save, so the sheet is
/// only offered once a page is loaded.
/// [canSave] is false when the restricted-site capture policy covers this page.
/// The Save block is then **absent** — the sheet closes up around it, exactly
/// as it does for any other action that cannot apply. Everything else on the
/// sheet (saved sites, copy, share, open externally, find, site information) is
/// ordinary browsing and stays.
Future<PageAction> showPageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String url,
  required String title,
  bool canSave = true,
}) async {
  final action = await showModalBottomSheet<PageAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _PageActionsSheet(
      url: url,
      title: title,
      parentRef: ref,
      canSave: canSave,
    ),
  );
  return action ?? PageAction.none;
}

class _PageActionsSheet extends ConsumerWidget {
  const _PageActionsSheet({
    required this.url,
    required this.title,
    required this.parentRef,
    required this.canSave,
  });

  final String url;
  final String title;
  final WidgetRef parentRef;
  final bool canSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final saved = ref.watch(savedSitesProvider).value ?? const [];
    final isSaved = saved.any((s) => s.urlKey == normalizeUrl(url));
    final host = displayHost(url);

    return SafeArea(
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
                  title.isEmpty ? host : title,
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
                  shortUrl(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11, color: palette.inkMuted),
                ),
              ],
            ),
          ),
          if (canSave)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Material(
                color: palette.primary,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const ValueKey('pageActionSave'),
                  onTap: () => Navigator.of(context).pop(PageAction.save),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    child: Row(
                      children: [
                        Icon(
                          Icons.download,
                          size: 21,
                          color: palette.onPrimary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontVariations: wght(600),
                                  fontWeight: FontWeight.w600,
                                  color: palette.onPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'This entry, or a number of entries from here',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.onPrimary.withValues(
                                    alpha: 0.78,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.divider)),
            ),
            child: Column(
              children: [
                _ActionTile(
                  icon: isSaved ? Icons.bookmark_added : Icons.bookmark_add,
                  label: isSaved
                      ? 'Already in saved sites'
                      : 'Add to saved sites',
                  badge: isSaved ? 'Saved' : null,
                  onTap: () =>
                      Navigator.of(context).pop(PageAction.addToSavedSites),
                ),
                _ActionTile(
                  icon: Icons.link,
                  label: 'Copy link',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final navigator = Navigator.of(context);
                    await Clipboard.setData(ClipboardData(text: url));
                    navigator.pop(PageAction.none);
                    messenger?.showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
                _ActionTile(
                  icon: Icons.ios_share,
                  label: 'Share',
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    navigator.pop(PageAction.none);
                    await SharePlus.instance.share(
                      ShareParams(
                        uri: Uri.tryParse(url),
                        title: title.isEmpty ? host : title,
                      ),
                    );
                  },
                ),
                _ActionTile(
                  icon: Icons.open_in_new,
                  label: 'Open in Safari',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final navigator = Navigator.of(context);
                    final uri = Uri.tryParse(url);
                    navigator.pop(PageAction.none);
                    if (uri == null) return;
                    // Explicitly leaves the app. Save is unaffected: it
                    // runs against the in-app WebView, which stays where it
                    // is.
                    final launched = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!launched) {
                      messenger?.showSnackBar(
                        const SnackBar(
                          content: Text('No app could open this address'),
                        ),
                      );
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.find_in_page,
                  label: 'Find in page',
                  onTap: () => Navigator.of(context).pop(PageAction.findInPage),
                ),
                _ActionTile(
                  icon: Icons.info_outline,
                  label: 'Site information',
                  onTap: () {
                    Navigator.of(context).pop(PageAction.none);
                    showSiteInformationSheet(
                      context: context,
                      ref: parentRef,
                      url: url,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

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
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: palette.inkStrong),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: palette.ink),
                ),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 11,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the user can usefully know about this site — not a diagnostics dump.
Future<void> showSiteInformationSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String url,
}) async {
  final browser = ref.read(browserProvider);
  final cookies = await browser.cookieCountFor(url);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      final host = displayHost(url);
      final secure = url.startsWith('https://');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Site information',
                style: serifStyle(size: 20, color: palette.ink),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    secure ? Icons.lock : Icons.lock_open,
                    size: 19,
                    color: secure ? palette.primary : palette.warn,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      secure
                          ? 'Secure connection'
                          : 'Not secure — this page is served over http',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: secure ? palette.ink : palette.warn,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(label: 'Site', value: host),
              _InfoRow(label: 'Address', value: url, wrap: true),
              _InfoRow(
                label: 'Cookies',
                value: cookies == 0
                    ? 'none stored'
                    : '$cookies stored for this site',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('siteInfoClearData'),
                onPressed: cookies == 0
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.maybeOf(
                          sheetContext,
                        );
                        final navigator = Navigator.of(sheetContext);
                        await browser.clearDataForUrl(url);
                        navigator.pop();
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Cleared stored data for $host — you may need '
                              'to sign in again',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.no_encryption, size: 18),
                label: const Text('Clear data for this site'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(color: palette.borderStrong),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.wrap = false});

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: monoStyle(size: 11.5, color: palette.inkFaint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: wrap ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(size: 11.5, color: palette.inkStrong),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact find-in-page bar.
///
/// Sits above the page rather than over it: a find bar that covers the first
/// match is a find bar that does not work.
class FindInPageBar extends StatefulWidget {
  const FindInPageBar({
    super.key,
    required this.browser,
    required this.onClose,
  });

  final BrowserController browser;
  final VoidCallback onClose;

  @override
  State<FindInPageBar> createState() => _FindInPageBarState();
}

class _FindInPageBarState extends State<FindInPageBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: widget.browser,
      builder: (context, _) {
        final matches = widget.browser.findMatchCount;
        final active = widget.browser.findActiveMatch;
        final hasQuery = _controller.text.trim().isNotEmpty;

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: palette.surfaceInset,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.borderInset),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('findInPageField'),
                          controller: _controller,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            setState(() {});
                            widget.browser.findAll(value);
                          },
                          onSubmitted: (_) => widget.browser.findNext(),
                          style: TextStyle(fontSize: 13, color: palette.ink),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Find in page',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: palette.inkFaint,
                            ),
                          ),
                        ),
                      ),
                      if (hasQuery)
                        Text(
                          matches == 0 ? 'no matches' : '$active/$matches',
                          key: const ValueKey('findInPageCount'),
                          style: monoStyle(size: 11, color: palette.inkMuted),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: matches == 0
                    ? null
                    : () => widget.browser.findNext(forward: false),
                tooltip: 'Previous match',
                iconSize: 20,
                color: palette.inkStrong,
                disabledColor: palette.inkDisabled,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                onPressed: matches == 0
                    ? null
                    : () => widget.browser.findNext(),
                tooltip: 'Next match',
                iconSize: 20,
                color: palette.inkStrong,
                disabledColor: palette.inkDisabled,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                key: const ValueKey('findInPageClose'),
                onPressed: () {
                  widget.browser.clearFind();
                  widget.onClose();
                },
                tooltip: 'Close find',
                iconSize: 20,
                color: palette.inkStrong,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }
}
