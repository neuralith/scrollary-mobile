import 'package:flutter/material.dart';

import '../browser/browser_controller.dart';
import '../browser/browser_url.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// The five-action Browser toolbar: Back · Forward · Address · Refresh/Stop ·
/// Home.
///
/// There is deliberately **no permanent Go button**. Go belongs to the moment
/// the user is entering an address, and lives in the expanded editor and on
/// the keyboard; a Go that is always present is a button that does nothing on
/// every page the user is merely reading. Home took its place (§2).
///
/// Every action is [kBrowserActionWidth] × [kBrowserActionHeight], one row,
/// one baseline — the toolbar equivalent of the shared header geometry.
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({
    super.key,
    required this.browser,
    required this.homeActive,
    required this.onBack,
    required this.onForward,
    required this.onAddress,
    required this.onReloadOrStop,
    required this.onHome,
  });

  final BrowserController browser;

  /// True while Browser Home is the visible surface; the glyph fills.
  final bool homeActive;

  final VoidCallback onBack;

  /// Null disables Forward — the honest state when there is nothing ahead.
  final VoidCallback? onForward;
  final VoidCallback onAddress;
  final VoidCallback onReloadOrStop;
  final VoidCallback onHome;

  /// Narrower than a stock [IconButton] (48pt): five actions plus a readable
  /// address do not fit across 320pt otherwise, and the address is what
  /// loses. Still ≥ 34 × 38 with the row's padding, which clears the minimum
  /// touch target once the 8pt vertical padding is counted.
  static const double kBrowserActionWidth = 36;
  static const double kBrowserActionHeight = 40;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: browser,
      builder: (context, _) {
        final loading = browser.isLoading;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Row(
                  children: [
                    _ToolbarButton(
                      icon: Icons.arrow_back_ios_new,
                      tooltip: 'Back',
                      // Back is never disabled: with no page history it means
                      // "leave the Browser", which is a real action (§2).
                      onPressed: onBack,
                    ),
                    _ToolbarButton(
                      icon: Icons.arrow_forward_ios,
                      tooltip: 'Forward',
                      onPressed: browser.canGoForward ? onForward : null,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _AddressField(
                          browser: browser,
                          onTap: onAddress,
                        ),
                      ),
                    ),
                    _ToolbarButton(
                      key: const ValueKey('browserReloadStop'),
                      icon: loading ? Icons.close : Icons.refresh,
                      tooltip: loading ? 'Stop' : 'Refresh',
                      onPressed: onReloadOrStop,
                    ),
                    _ToolbarButton(
                      key: const ValueKey('browserHomeButton'),
                      icon: Icons.home,
                      tooltip: 'Browser Home',
                      active: homeActive,
                      onPressed: onHome,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 2,
                child: loading
                    ? LinearProgressIndicator(
                        value: browser.progress == 0 ? null : browser.progress,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = onPressed == null
        ? palette.inkDisabled
        : (active ? palette.primary : palette.inkStrong);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: BrowserToolbar.kBrowserActionWidth,
        height: BrowserToolbar.kBrowserActionHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

/// The compact address display.
///
/// Not an editor. It shows the host in full and as much path as fits, because
/// a squeezed full URL is unreadable — tapping opens the expanded editor,
/// which is where a long entry address can actually be inspected (§2).
class _AddressField extends StatelessWidget {
  const _AddressField({required this.browser, required this.onTap});

  final BrowserController browser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final url = browser.currentUrl;
    final host = url.isEmpty ? '' : displayHost(url);
    final loading = browser.isLoading;
    final insecureFault = !browser.isSecure && url.startsWith('https://');

    final (icon, iconColor) = loading
        ? (Icons.sync, palette.primary)
        : insecureFault
        ? (Icons.gpp_bad, palette.danger)
        : url.startsWith('https://')
        ? (Icons.lock, palette.inkMuted)
        : url.isEmpty
        ? (Icons.public, palette.inkMuted)
        : (Icons.lock_open, palette.warn);

    return Material(
      color: palette.surfaceInset,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('browserAddressField'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: BrowserToolbar.kBrowserActionHeight - 2,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.borderInset),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: host.isEmpty
                    ? Text(
                        'Search or enter address',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: 12, color: palette.inkFaint),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: host,
                              style: monoStyle(size: 12, color: palette.ink),
                            ),
                            TextSpan(
                              text: compactPath(url),
                              style: monoStyle(
                                size: 12,
                                color: palette.inkFaint,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
