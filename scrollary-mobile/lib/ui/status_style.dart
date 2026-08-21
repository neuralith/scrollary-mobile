import 'dart:math' as math;

import '../core/device_storage.dart';

import 'package:flutter/material.dart';

import '../reading/reading_position.dart';
import '../storage/database.dart';
import 'palette.dart';
import 'theme.dart';

/// The two status vocabularies the design keeps strictly apart.
///
/// Save state answers "is this on the device" and never uses a checkmark.
/// Read state owns the checkmark and nothing else does. Mixing them is the
/// single worst thing this UI could do, so they live in one file where the
/// separation is visible.
///
/// Everything here reads from an [AppPalette]. These are the pieces every
/// screen draws — a chip, a glyph, a section label, a monogram — so a literal
/// colour in this file becomes a literal colour on every page at once, which
/// is a large part of how the dark appearance broke (D62).

// ─── save state ──────────────────────────────────────────────────────────

class SaveLook {
  const SaveLook(this.icon, this.color, this.label, {this.dimTitle = false});

  final IconData icon;
  final Color color;
  final String label;

  /// Rows whose content is not readable are greyed rather than shouted at.
  final bool dimTitle;
}

/// Presentation for an entry's save state. [filesMissing] is decided by
/// the caller (the manifest is on disk but its images are not), because the
/// database has no such status — the files simply stopped existing.
SaveLook saveLook(
  Entry entry,
  AppPalette palette, {
  bool filesMissing = false,
}) {
  if (filesMissing) {
    return SaveLook(
      Icons.folder_off,
      palette.danger,
      'Files missing',
      dimTitle: true,
    );
  }
  // An entry whose files the USER removed is not an error and not a
  // discovery — it is a known entry that simply is not downloaded.
  if (entry.contentPath == null && entry.offlineRemovedAt != null) {
    return SaveLook(Icons.cloud, palette.inkFaint, 'Not downloaded');
  }
  return switch (entry.saveStatus) {
    'knownRemote' => SaveLook(Icons.cloud, palette.inkFaint, 'On source only'),
    'complete' => SaveLook(
      Icons.download_for_offline,
      palette.primary,
      'Saved offline',
    ),
    'partial' => SaveLook(Icons.arrow_circle_down, palette.warn, 'Partial'),
    'saving' => SaveLook(Icons.downloading, palette.primary, 'Saving'),
    _ => SaveLook(Icons.error, palette.danger, 'Failed', dimTitle: true),
  };
}

/// The save glyph on its own — 22px, matching the entry rows.
class SaveGlyph extends StatelessWidget {
  const SaveGlyph(this.look, {super.key, this.size = 22});

  final SaveLook look;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(look.icon, size: size, color: look.color);
}

// ─── read state ─────────────────────────────────────────────────────────────

/// Read-state indicator. Unread is a small filled dot, in-progress a partial
/// ring with its percentage beside it, finished a hollow check.
// ─── storage ────────────────────────────────────────────────────────────────

/// The colours one storage reading wears, everywhere it appears.
///
/// Driven by the **percentage of the device in use**, not by the app's own
/// share and not by free bytes alone (D51). One palette, one source, so the
/// Library pill and the Storage screen can never disagree about how worried
/// to look.
class StorageLook {
  const StorageLook({
    required this.ink,
    required this.track,
    required this.fill,
    required this.bg,
    required this.border,
    required this.label,
  });

  /// Text and glyph colour.
  final Color ink;

  /// Meter background and its filled portion.
  final Color track, fill;

  /// Card background and border, for the surfaces that have one.
  final Color bg, border;

  /// One word for what this level means.
  final String label;
}

StorageLook storageLook(StorageLevel level, AppPalette palette) =>
    switch (level) {
      StorageLevel.critical => StorageLook(
        ink: palette.onDangerContainer,
        track: palette.dangerBorder,
        fill: palette.danger,
        bg: palette.dangerContainer,
        border: palette.dangerBorder,
        label: 'Almost full',
      ),
      StorageLevel.warning => StorageLook(
        ink: palette.onWarnContainer,
        track: palette.warnBorder,
        fill: palette.warn,
        bg: palette.warnContainer,
        border: palette.warnBorder,
        label: 'Filling up',
      ),
      // Quiet by belonging: the same ink as every other header glyph.
      StorageLevel.normal => StorageLook(
        ink: palette.inkMuted,
        track: palette.border,
        fill: palette.primary,
        bg: palette.surfaceHigh,
        border: palette.border,
        label: 'Healthy',
      ),
      StorageLevel.unknown => StorageLook(
        ink: palette.inkMuted,
        track: palette.border,
        fill: palette.inkDisabled,
        bg: palette.surfaceHigh,
        border: palette.border,
        label: 'Unavailable',
      ),
    };

// ─── screen header ──────────────────────────────────────────────────────────

/// Every action in a screen header is exactly this box, with exactly this
/// glyph inside it, in exactly this colour.
///
/// One definition, because the alternative was what the Library header had:
/// three 48pt `IconButton`s with 22pt glyphs beside a 40pt pill with a 15pt
/// glyph, bottom-aligned — so the pill's centre sat 4pt below every icon's
/// centre and its glyph read as a different family. Anything that joins this
/// row must be [kHeaderActionSize] tall and use [kHeaderIconSize].
const double kHeaderActionSize = 40;
const double kHeaderIconSize = 22;

/// The one ink every header glyph wears. A function rather than a constant:
/// it has to answer differently in the two appearances.
Color headerIconColor(AppPalette palette) => palette.inkMuted;

/// A header action. Deliberately tighter than a stock [IconButton] (48pt):
/// four actions plus a 28pt serif title do not fit across a 320pt screen at
/// the default size, and the title is what loses — it wrapped to three lines.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: kHeaderActionSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(
            icon,
            size: kHeaderIconSize,
            color: headerIconColor(AppPalette.of(context)),
          ),
        ),
      ),
    ),
  );
}

/// The entry list's progress pie, driven by the real reading fraction.
///
/// A painter rather than a set of range icons: the design's pie is a
/// continuous quantity, and bucketing it into "quarter / half / three
/// quarters" would show 51% and 74% as the same picture. One filled wedge from
/// twelve o'clock clockwise, on a quiet ring.
///
/// Cheap by construction — two `drawArc` calls, no animation, no layout — so
/// it costs nothing to have one per row in a long list.
class EntryProgressRing extends StatelessWidget {
  const EntryProgressRing({
    super.key,
    required this.fraction,
    required this.completed,
    this.size = 18,
  });

  /// 0..1. Callers pass [readProgressFor]'s output, so a completed entry is
  /// already pinned at 1 (D39).
  final double fraction;

  /// Drawn as a full disc with a check, whatever [fraction] says. The two
  /// always agree in practice; if they ever disagree, "finished" is the fact
  /// the user asserted and the fraction is the one that drifted.
  final bool completed;

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final value = completed ? 1.0 : fraction.clamp(0.0, 1.0);
    final percent = (value * 100).round();
    return Semantics(
      label: completed
          ? 'Read · 100%'
          : percent == 0
          ? 'Unread · 0%'
          : 'Reading progress $percent%',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ProgressRingPainter(
            fraction: value,
            completed: completed,
            // The unfilled part. Present at 0% so an unread entry reads as
            // "nothing yet", not as "no indicator".
            track: palette.borderStrong,
            // The filled wedge: body ink, so a finished entry is the
            // strongest mark on its row without borrowing a colour that
            // already means something else.
            fill: palette.ink,
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.fraction,
    required this.completed,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final bool completed;
  final Color track;
  final Color fill;

  static const double _twelveOClock = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final stroke = math.max(1.2, side * 0.1);
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (side - stroke) / 2;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (completed || fraction >= 1) {
      // Finished: a solid disc. Unmistakably different from 99%.
      canvas.drawCircle(centre, radius, Paint()..color = fill);
      return;
    }
    if (fraction <= 0) return;

    // The wedge is inset by half a stroke so it sits inside the ring rather
    // than straddling it.
    final inner = radius - stroke / 2;
    if (inner <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: inner),
      _twelveOClock,
      fraction * 2 * math.pi,
      true,
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.fraction != fraction ||
      old.completed != completed ||
      old.track != track ||
      old.fill != fill;
}

class ReadGlyph extends StatelessWidget {
  const ReadGlyph({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = readStatusFromName(entry.readStatus);
    final pct =
        (readProgressFor(
                  readStatus: entry.readStatus,
                  stored: entry.progressFraction,
                ) *
                100)
            .round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == ReadStatus.inProgress)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('$pct%', style: monoStyle(color: palette.inkMuted)),
          ),
        // One component for all three states: the ring IS the state, so an
        // unread entry cannot render as finished by picking a wrong icon.
        EntryProgressRing(
          key: ValueKey('progressRing-${entry.id}'),
          fraction: readProgressFor(
            readStatus: entry.readStatus,
            stored: entry.progressFraction,
          ),
          completed: status == ReadStatus.completed,
        ),
      ],
    );
  }
}

// ─── update-check state ─────────────────────────────────────────────────────

/// How a collection's update-check state reads on its library row. "Never checked"
/// is its own state and must never render as "no new entries".
class CheckLook {
  const CheckLook(this.icon, this.label, this.bg, this.fg, this.border);

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
}

CheckLook checkLook({
  required AppPalette palette,
  required bool checking,
  required bool failed,
  required DateTime? checkedAt,
  required int newCount,
  required String checkedLabel,
}) {
  CheckLook accent(IconData icon, String label) => CheckLook(
    icon,
    label,
    palette.primaryContainer,
    palette.onPrimaryContainer,
    palette.primaryBorder,
  );
  CheckLook neutral(IconData icon, String label) => CheckLook(
    icon,
    label,
    palette.surfaceHigh,
    palette.inkMuted,
    palette.border,
  );

  // Not a sync glyph: a check asks a source what it has published, which is
  // neither refreshing this screen nor reconciling two copies of anything.
  if (checking) return accent(Icons.manage_search, 'Checking');
  if (failed) {
    return CheckLook(
      Icons.error_outline,
      'Check failed',
      palette.dangerContainer,
      palette.onDangerContainer,
      palette.dangerBorder,
    );
  }
  if (checkedAt == null) {
    return neutral(Icons.history_toggle_off, 'Not checked yet');
  }
  if (newCount > 0) return accent(Icons.cloud, '$newCount new');
  return neutral(Icons.update, 'Checked $checkedLabel');
}

/// A small pill: icon + label, used for check state and for run phase.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    this.iconSize = 13,
  });

  final IconData icon;
  final String label;
  final Color bg, fg, border;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontVariations: wght(500),
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ],
    ),
  );
}

// ─── shared small pieces ────────────────────────────────────────────────────

/// The rounded monogram tile that stands in for cover art.
class MonogramTile extends StatelessWidget {
  const MonogramTile({
    super.key,
    required this.id,
    required this.title,
    this.size = 44,
    this.radius = 12,
    this.fontSize = 15,
  });

  final String id;
  final String title;
  final double size;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = monogramFor(id, AppPalette.of(context));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        monogramText(title),
        style: TextStyle(
          fontFamily: 'Newsreader',
          fontSize: fontSize,
          fontVariations: wght(600),
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Uppercase section label, optionally with something on the right.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 6),
  });

  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.84,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).inkMuted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

// ─── shared text styles ─────────────────────────────────────────────────────
//
// Both take a **nullable** colour, and null means "inherit". That resolves to
// the ambient `DefaultTextStyle` — the theme's `onSurface` — so a caller that
// does not care about tone can no longer pin one appearance's ink by
// accident, which is what the old light-only defaults did on every screen.

/// Monospace metadata line. Pass [color] for anything quieter than body ink;
/// `monoStyle()` on its own inherits.
TextStyle monoStyle({
  double size = 11,
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// Serif display/title style.
TextStyle serifStyle({double size = 28, Color? color}) => TextStyle(
  fontFamily: 'Newsreader',
  fontSize: size,
  height: 1.18,
  letterSpacing: -0.28,
  fontVariations: wght(500),
  fontWeight: FontWeight.w500,
  color: color,
);
