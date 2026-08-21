import 'package:flutter/material.dart';

import '../browser/browser_presentation.dart';
import '../browser/browser_url.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// One action offered by a page-state banner or overlay.
class PageStateAction {
  const PageStateAction(this.label, this.onPressed, {this.primary = false});

  final String label;
  final VoidCallback onPressed;
  final bool primary;
}

/// The copy and shape for every classified page state (§14).
///
/// Two presentations, chosen by whether the page underneath is still worth
/// looking at: a **banner** when it is (a blocked redirect, a login wall, a
/// certificate warning the user may want to read about), and a **blocking
/// overlay** when there is nothing behind it (offline, DNS failure, a
/// mistyped address).
class PageStateView extends StatelessWidget {
  const PageStateView({
    super.key,
    required this.fault,
    required this.actions,
    this.blocking = false,
  });

  final BrowserPageFault fault;
  final List<PageStateAction> actions;

  /// Draw as a full-area overlay rather than a banner.
  final bool blocking;

  /// Whether [state] leaves anything useful on screen behind it.
  static bool isBlocking(BrowserPageState state) => switch (state) {
    BrowserPageState.offline ||
    BrowserPageState.unreachable ||
    BrowserPageState.unavailable ||
    BrowserPageState.invalidAddress => true,
    _ => false,
  };

  static (IconData, String, String) copyFor(BrowserPageFault fault) =>
      switch (fault.state) {
        BrowserPageState.offline => (
          Icons.wifi_off,
          "You're offline",
          "The device has no connection, so this page can't load. Entries "
              'already saved still open from your library.',
        ),
        BrowserPageState.unreachable => (
          Icons.public_off,
          "This site couldn't be reached",
          'The address may be wrong, or the site may be down. Nothing was '
              'loaded.',
        ),
        BrowserPageState.unavailable => (
          Icons.public_off,
          "This page didn't load",
          'The site answered with an error. It may be down, or the entry '
              'may have moved.',
        ),
        BrowserPageState.invalidAddress => (
          Icons.link_off,
          "That address doesn't look right",
          'Check the spelling, or search for the entry instead.',
        ),
        BrowserPageState.certificate => (
          Icons.gpp_bad,
          "This connection isn't private",
          "The site's security certificate can't be verified. Save is "
              'blocked on pages like this.',
        ),
        BrowserPageState.redirectBlocked => (
          Icons.shield,
          'A redirect was blocked',
          'This page tried to send you somewhere else. Nothing was loaded '
              'from the other host.',
        ),
        BrowserPageState.externalApp => (
          Icons.open_in_new,
          'This link opens another app',
          "That isn't a web address, so nothing was opened here.",
        ),
        BrowserPageState.ok ||
        BrowserPageState.loading ||
        BrowserPageState.refreshing => (Icons.info_outline, '', ''),
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, title, body) = copyFor(fault);
    final (bg, bd, fg) = switch (fault.state) {
      BrowserPageState.certificate => (
        palette.dangerContainer,
        palette.dangerBorder,
        palette.danger,
      ),
      BrowserPageState.externalApp => (
        palette.warnContainer,
        palette.warnBorder,
        palette.warn,
      ),
      _ => (palette.surfaceHigh, palette.borderInset, palette.inkMuted),
    };

    if (blocking) {
      return Container(
        color: palette.surfaceMuted,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.inkGhost),
            const SizedBox(height: 9),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.5,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
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
            if (fault.url.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  shortUrl(fault.url, maxLength: 60),
                  textAlign: TextAlign.center,
                  style: monoStyle(size: 11, color: palette.inkGhost),
                ),
              ),
            ],
            // The platform's own words, kept but demoted — diagnostics, not
            // the explanation.
            if (fault.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  fault.detail,
                  textAlign: TextAlign.center,
                  style: monoStyle(size: 10, color: palette.inkDisabled),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ActionWrap(actions: actions, large: true),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: palette.inkMuted,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _ActionWrap(actions: actions, large: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionWrap extends StatelessWidget {
  const _ActionWrap({required this.actions, required this.large});

  final List<PageStateAction> actions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: large ? 7 : 6,
      runSpacing: 6,
      alignment: large ? WrapAlignment.center : WrapAlignment.start,
      children: [
        for (final action in actions)
          Material(
            color: action.primary ? palette.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: action.onPressed,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: large ? 15 : 12,
                  vertical: large ? 10 : 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: action.primary
                        ? palette.primary
                        : palette.borderStrong,
                  ),
                ),
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: large ? 13 : 11.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: action.primary
                        ? palette.onPrimary
                        : palette.inkStrong,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The dashed "saves are waiting" chip the design shows over the page.
///
/// Deliberately inert: it counts and it points at Activity. Nothing on
/// Browser Home or this chip may start queued work (D46, §16).
class QueuedSavesChip extends StatelessWidget {
  const QueuedSavesChip({
    super.key,
    required this.count,
    required this.onViewActivity,
  });

  final int count;
  final VoidCallback onViewActivity;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: palette.inkMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 1 ? 'Save queued' : '$count saves waiting',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'waiting for you to start them',
                  style: monoStyle(size: 11, color: palette.inkMuted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const ValueKey('queuedChipViewActivity'),
            onPressed: onViewActivity,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
            child: const Text('View Activity'),
          ),
        ],
      ),
    );
  }
}
