import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/status_style.dart';
import 'package:web_reader/ui/theme.dart';

/// The theme's own guarantees (D62).
///
/// Two kinds of check live here. The first is arithmetic on the palette:
/// contrast is a measurable property, and "the dark theme is comfortable" is
/// only an opinion until the numbers are pinned. The second is a source scan:
/// the reason the dark appearance broke was not a bad value anywhere, it was
/// four hundred light-theme literals in widget files that the palette could
/// never reach.
void main() {
  group('contrast', () {
    // Every text role that carries information, on each surface it is
    // actually drawn on.
    for (final (name, palette) in [
      ('light', AppPalette.light),
      ('dark', AppPalette.dark),
    ]) {
      test('$name: informational text clears WCAG AA on every surface', () {
        final surfaces = <String, Color>{
          'surface': palette.surface,
          'surfaceMuted': palette.surfaceMuted,
          'surfaceHigh': palette.surfaceHigh,
          'surfaceInset': palette.surfaceInset,
        };
        final inks = <String, Color>{
          'ink': palette.ink,
          'inkStrong': palette.inkStrong,
          'inkMuted': palette.inkMuted,
          'inkFaint': palette.inkFaint,
        };
        for (final s in surfaces.entries) {
          for (final i in inks.entries) {
            final ratio = _contrast(i.value, s.value);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$name ${i.key} on ${s.key} is ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      });

      test('$name: container inks clear AA on their own container', () {
        for (final (label, ink, bg) in [
          ('primary', palette.onPrimaryContainer, palette.primaryContainer),
          ('warn', palette.onWarnContainer, palette.warnContainer),
          ('danger', palette.onDangerContainer, palette.dangerContainer),
        ]) {
          final ratio = _contrast(ink, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name $label container: ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('$name: accents and button fills stay legible', () {
        for (final (label, fg, bg) in [
          ('primary on page', palette.primary, palette.surface),
          ('warn on page', palette.warn, palette.surface),
          ('danger on page', palette.danger, palette.surface),
          ('onPrimary on primary', palette.onPrimary, palette.primary),
          ('onWarn on warn', palette.onWarn, palette.warn),
          ('onDanger on danger', palette.onDanger, palette.danger),
          ('toastInk on toast', palette.toastInk, palette.toastSurface),
        ]) {
          final ratio = _contrast(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name $label: ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('$name: generated tile foregrounds are readable on their tile', () {
        for (final (bg, fg) in palette.tilePairs) {
          final ratio = _contrast(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name tile ${_hex(bg)}/${_hex(fg)}',
          );
        }
      });

      test('$name: body ink stays inside the reading comfort band', () {
        // Below 7:1 is thin for hour-long reading; above ~15:1 is the
        // over-contrast that makes glyphs bloom on a dark page and glare on a
        // light one. Both ends are the point of this palette.
        final ratio = _contrast(palette.ink, palette.surface);
        expect(ratio, greaterThan(7));
        expect(
          ratio,
          lessThan(15),
          reason: '$name body ink is ${ratio.toStringAsFixed(2)}:1 — glaring',
        );
      });

      test('$name: the ink ramp is monotonic', () {
        final ramp = [
          palette.ink,
          palette.inkStrong,
          palette.inkMuted,
          palette.inkFaint,
          palette.inkGhost,
          palette.inkDisabled,
        ].map((c) => _contrast(c, palette.surface)).toList();
        for (var i = 1; i < ramp.length; i++) {
          expect(
            ramp[i],
            lessThan(ramp[i - 1]),
            reason: '$name ink ramp step $i is not quieter than the one above',
          );
        }
      });

      test('$name: borders and dividers are perceptible', () {
        // The old dark border measured 1.37:1 — invisible. A hairline does
        // not need text contrast, but it does need to exist.
        for (final (label, line, bg) in [
          ('border', palette.border, palette.surface),
          ('borderStrong', palette.borderStrong, palette.surface),
          ('divider', palette.divider, palette.surface),
          ('hairline', palette.hairline, palette.surfaceMuted),
        ]) {
          final ratio = _contrast(line, bg);
          expect(
            ratio,
            greaterThan(1.1),
            reason: '$name $label: ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('$name: cards separate from the page without floating', () {
        for (final (label, card) in [
          ('surfaceMuted', palette.surfaceMuted),
          ('surfaceHigh', palette.surfaceHigh),
          ('primaryContainer', palette.primaryContainer),
          ('warnContainer', palette.warnContainer),
          ('dangerContainer', palette.dangerContainer),
        ]) {
          final ratio = _contrast(card, palette.surface);
          expect(
            ratio,
            greaterThan(1.03),
            reason: '$name $label is indistinguishable from the page',
          );
          expect(
            ratio,
            lessThan(1.9),
            reason: '$name $label reads as a lit rectangle, not a card',
          );
        }
      });

      test('$name: disabled looks disabled but stays visible', () {
        final ratio = _contrast(palette.inkDisabled, palette.surface);
        expect(ratio, greaterThan(1.9), reason: '$name disabled is invisible');
        expect(
          ratio,
          lessThan(_contrast(palette.inkFaint, palette.surface)),
          reason: '$name disabled is not quieter than tertiary text',
        );
      });
    }

    test('dark is not pure black and its ink is not pure white', () {
      expect(AppPalette.dark.surface, isNot(const Color(0xFF000000)));
      expect(AppPalette.dark.ink, isNot(const Color(0xFFFFFFFF)));
      expect(ReaderColors.canvas, isNot(const Color(0xFF000000)));
      // The light page is off-white, not paper-white.
      expect(_luminance(AppPalette.light.surface), lessThan(0.94));
    });

    test('accents survive a device warm/night-light filter', () {
      // A warm filter scales the blue channel down hard. An accent that
      // differs from the neutral inks only by hue collapses into them — a
      // teal link becomes indistinguishable grey text. Measured in L* after
      // the filter, because that is what is left when the hue has gone.
      for (final MapEntry(key: name, value: palette) in {
        'light': AppPalette.light,
        'dark': AppPalette.dark,
      }.entries) {
        final accent = _lstar(_warm(palette.primary));
        expect(
          (accent - _lstar(_warm(palette.ink))).abs(),
          greaterThan(4),
          reason: '$name primary collapses into body ink under a warm filter',
        );
        expect(
          (accent - _lstar(_warm(palette.inkMuted))).abs(),
          greaterThan(3),
          reason:
              '$name primary collapses into secondary ink under a warm filter',
        );
      }
    });
  });

  group('the theme is the only source of colour', () {
    test('no widget file names a colour literal', () {
      // `lib/ui/palette.dart` is where colours are allowed to be literals;
      // everywhere else a literal is a value the appearance switch cannot
      // reach. This is the check that would have caught the original bug.
      final offenders = <String>[];
      final pattern = RegExp(r'Color\(0x');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('ui/palette.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('///')) continue;
          if (pattern.hasMatch(line)) {
            offenders.add('${entity.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no widget file reaches for a raw Material swatch', () {
      // `Colors.transparent` and `Colors.black` (shadows, ink wells) are the
      // only two that mean the same thing in both appearances.
      const allowed = {'Colors.transparent', 'Colors.black'};
      final offenders = <String>[];
      // Word-boundaried: `ReaderColors.canvas` is a palette lookup, not a
      // Material swatch.
      final pattern = RegExp(r'(?<![A-Za-z])Colors\.[a-zA-Z]+');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('///')) continue;
          for (final match in pattern.allMatches(line)) {
            if (allowed.contains(match.group(0))) continue;
            offenders.add('${entity.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  group('the built theme agrees with the palette', () {
    for (final (name, palette) in [
      ('light', AppPalette.light),
      ('dark', AppPalette.dark),
    ]) {
      test('$name: scheme, extension and defaults line up', () {
        final theme = appTheme(palette: palette);
        expect(theme.extension<AppPalette>(), same(palette));
        expect(theme.colorScheme.surface, palette.surface);
        expect(theme.colorScheme.onSurface, palette.ink);
        expect(theme.colorScheme.primary, palette.primary);
        expect(theme.colorScheme.onPrimary, palette.onPrimary);
        expect(theme.colorScheme.error, palette.danger);
        expect(theme.scaffoldBackgroundColor, palette.surface);
        expect(theme.dividerTheme.color, palette.divider);
        expect(theme.iconTheme.color, palette.inkMuted);
        expect(theme.textTheme.bodyMedium?.color, palette.ink);
        expect(theme.brightness, palette.brightness);
      });
    }

    testWidgets('an unthemed widget still gets the light palette', (
      tester,
    ) async {
      late AppPalette resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = AppPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved, same(AppPalette.light));
    });

    testWidgets('shared components take their ink from the theme', (
      tester,
    ) async {
      // The pieces every screen draws. If these hardcode anything, every
      // page inherits it — which is precisely what happened before.
      for (final palette in [AppPalette.light, AppPalette.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(palette: palette),
            // The theme cross-fades by default, and `AppPalette.lerp` snaps at
            // the midpoint — so a single pump after a theme swap would still
            // be reading the previous appearance.
            themeAnimationDuration: Duration.zero,
            home: const Scaffold(
              body: Column(
                children: [
                  SectionLabel('SECTION'),
                  MonogramTile(id: 'collection-1', title: 'A Collection'),
                ],
              ),
            ),
          ),
        );
        final label = tester.widget<Text>(find.text('SECTION'));
        expect(label.style?.color, palette.inkMuted);

        // Located through the same helper the widget uses, so renaming the
        // fixture cannot break the assertion this test is actually about — which
        // is the tile's colour coming from the appearance's own table.
        final tile = tester.widget<Container>(
          find.ancestor(
            of: find.text(monogramText('A Collection')),
            matching: find.byType(Container),
          ),
        );
        final tileColour = (tile.decoration as BoxDecoration).color;
        expect(
          palette.tilePairs.map((p) => p.$1),
          contains(tileColour),
          reason: 'monogram tile is not from this appearance\'s table',
        );
      }
    });

    test('save and check looks are palette-driven, per appearance', () {
      final light = checkLook(
        palette: AppPalette.light,
        checking: true,
        failed: false,
        checkedAt: null,
        newCount: 0,
        checkedLabel: '',
      );
      final dark = checkLook(
        palette: AppPalette.dark,
        checking: true,
        failed: false,
        checkedAt: null,
        newCount: 0,
        checkedLabel: '',
      );
      expect(light.bg, AppPalette.light.primaryContainer);
      expect(dark.bg, AppPalette.dark.primaryContainer);
      expect(light.bg, isNot(dark.bg));
    });
  });
}

// ─── contrast maths ─────────────────────────────────────────────────────────

double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// CIE L\*, the perceptual lightness the eye is left with once a warm filter
/// has taken the hue away.
double _lstar(Color c) {
  final y = _luminance(c);
  return y > 0.008856 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 903.3 * y;
}

/// A strong device warm filter: blue cut hard, green trimmed, red kept.
Color _warm(Color c) =>
    Color.from(alpha: c.a, red: c.r, green: c.g * 0.86, blue: c.b * 0.62);

String _hex(Color c) =>
    '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0').substring(2)}';
