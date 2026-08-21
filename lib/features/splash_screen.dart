/// The launch screen, and the only thing on screen while startup work runs.
///
/// Drawn deliberately without Material or a [MediaQuery]: it is mounted above
/// the app (and, for the first frames, instead of it), so it cannot depend on
/// anything a [MaterialApp] provides. Everything it needs — colours, fonts,
/// text direction — it states itself, which is also what lets it continue the
/// native launch window without a visible hand-off.
library;

import 'package:flutter/widgets.dart';

import '../core/startup.dart';
import '../ui/palette.dart';
import '../ui/theme.dart';

/// The app mark, at the size the native launch screens use.
const double kBrandMarkSize = 96;

class StartupSplash extends StatelessWidget {
  const StartupSplash({
    super.key,
    required this.palette,
    required this.run,
    this.onRetry,
  });

  final AppPalette palette;
  final StartupRun run;

  /// Offered when a critical step failed. Null means "no way back" — the
  /// screen then reports the failure and nothing else.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'IBM Plex Sans',
          fontSize: 13,
          color: palette.ink,
          decoration: TextDecoration.none,
        ),
        child: ColoredBox(
          color: palette.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BrandMark(palette: palette),
                const SizedBox(height: 22),
                Text(
                  'Scrollary',
                  style: TextStyle(
                    fontFamily: 'Newsreader',
                    fontSize: 30,
                    height: 1.1,
                    letterSpacing: -0.2,
                    fontVariations: wght(600),
                    color: palette.inkStrong,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Offline reading library',
                  style: TextStyle(
                    fontFamily: 'IBM Plex Sans',
                    fontSize: 12.5,
                    letterSpacing: 0.35,
                    color: palette.inkFaint,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 36),
                if (run.hasFailed)
                  _Failure(palette: palette, run: run, onRetry: onRetry)
                else
                  _Progress(palette: palette, run: run),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kBrandMarkSize,
      height: kBrandMarkSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kBrandMarkSize * 0.2237),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // The generated tile already carries its own rounded shape (see
      // tool/brand/generate_brand_assets.swift), so nothing here re-clips it.
      child: const Image(
        image: AssetImage('assets/brand/app_mark.png'),
        width: kBrandMarkSize,
        height: kBrandMarkSize,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The progress line: a bar that only ever moves forward, the step being
/// worked on, and where it sits in the sequence.
class _Progress extends StatelessWidget {
  const _Progress({required this.palette, required this.run});

  final AppPalette palette;
  final StartupRun run;

  @override
  Widget build(BuildContext context) {
    final label = run.currentLabel ?? 'Ready';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 176,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 3,
              color: palette.surfaceInset,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: run.fraction),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value.clamp(0, 1),
                  child: Container(color: palette.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Keyed by the text: the switcher must cross-fade when the step
        // changes, not when the frame does.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            label,
            key: ValueKey(label),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'IBM Plex Sans',
              fontSize: 12.5,
              color: palette.inkMuted,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          run.finished
              ? '${run.labels.length} of ${run.labels.length}'
              : '${run.completed + 1} of ${run.labels.length}',
          style: TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 10.5,
            letterSpacing: 0.4,
            color: palette.inkGhost,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

/// A critical step failed: the app has no database or no file store, so there
/// is nothing to fall through to. Say which step, and offer the retry.
class _Failure extends StatelessWidget {
  const _Failure({
    required this.palette,
    required this.run,
    required this.onRetry,
  });

  final AppPalette palette;
  final StartupRun run;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            run.completed < run.labels.length
                ? '${run.labels[run.completed]} failed'
                : 'Startup failed',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'IBM Plex Sans',
              fontSize: 14,
              fontVariations: wght(600),
              color: palette.danger,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${run.error}',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontSize: 11,
              height: 1.45,
              color: palette.inkMuted,
              decoration: TextDecoration.none,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Try again',
                  style: TextStyle(
                    fontFamily: 'IBM Plex Sans',
                    fontSize: 13,
                    fontVariations: wght(600),
                    color: palette.onPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
