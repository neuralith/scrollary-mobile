/// Named surfaces and inks, so a screen can be drawn once and rendered in
/// either appearance.
///
/// This is a deliberate, narrow amendment to D28 ("flat theme, no token
/// layer"). That decision was right while there was one appearance: a literal
/// `Color(0xFFF5F3EF)` said exactly what the design said. A second appearance
/// makes a literal a lie — the same value cannot be "the quiet surface" in
/// both. The names here are the *roles* the design already uses, nothing
/// more: no scale, no elevation system, no component tokens.
///
/// ## How the values were chosen (D62)
///
/// Both ramps are tuned against measured contrast rather than picked by eye —
/// WCAG 2.x ratios for the compliance floor and APCA Lc for the perceptual
/// judgement, because WCAG 2 systematically overstates contrast near black and
/// cannot be used to design a dark theme. The app is for hour-long reading
/// sessions, so the target is the *comfort band*, not the maximum:
///
/// * **No pure black page, no pure white ink.** The dark page is a warm
///   near-black (L\* ≈ 8) rather than `#000000`: pure black maximises halation
///   (the glow astigmatic eyes see around light glyphs) and smears while
///   scrolling on OLED. Body ink is a warm off-white at L\* ≈ 88, not
///   `#FFFFFF` — the previous `#F2EFE9` on `#161513` measured Lc −97, well past
///   APCA's Lc 90 "preferred for fluent body text", which is what made text
///   look like it was glowing.
/// * **Four accessible text levels, then decoration.** `ink`, `inkStrong`,
///   `inkMuted` and `inkFaint` all clear 4.5:1 in both appearances. `inkGhost`
///   sits below that on purpose and is only for text that repeats something
///   already on screen; `inkDisabled` is the disabled-control tone. Hierarchy
///   is carried by type weight and size as well as tone — brightness alone was
///   how five near-identical greys ended up on one row.
/// * **Borders are visible but quiet.** The old dark border measured 1.37:1
///   (Lc 0 — literally imperceptible). Cards now separate twice: a surface
///   step *and* an edge.
/// * **Accents are desaturated on dark and never rely on hue alone.** A
///   device-level warm/night-light filter crushes the blue channel, which
///   collapses a teal accent towards the neutral ink. Every accent surface
///   therefore carries a lightness and a border difference too, so it survives
///   the filter.
/// * **The light page is off-white, not paper-white.** `#FBFAF8` (L\* 98) is
///   effectively a lamp; the body ink against it measured Lc +101. Both ends
///   moved inwards, which cuts glare while staying unmistakably light and
///   readable outdoors.
///
/// The light values are the prototype's hues, re-levelled; the dark values are
/// derived from them — same hue relationships, inverted lightness — and are
/// marked as such because the design artifact ships no dark variant (D56).
library;

import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceInset,
    required this.surfaceHigh,
    required this.surfaceSunken,
    required this.surfaceSelected,
    required this.divider,
    required this.hairline,
    required this.border,
    required this.borderInset,
    required this.borderStrong,
    required this.ink,
    required this.inkStrong,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkGhost,
    required this.inkDisabled,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.primaryBorder,
    required this.onPrimaryContainer,
    required this.warn,
    required this.onWarn,
    required this.warnContainer,
    required this.warnBorder,
    required this.onWarnContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.dangerBorder,
    required this.onDangerContainer,
    required this.scrim,
    required this.veil,
    required this.shadow,
    required this.toastSurface,
    required this.toastInk,
    required this.toastAccent,
    required this.tilePairs,
  });

  final Brightness brightness;

  /// The page itself.
  final Color surface;

  /// A quiet block on the page (tiles, inset cards).
  final Color surfaceMuted;

  /// A field or pill sunk into the page (the address bar, search fields).
  final Color surfaceInset;

  /// A slightly raised neutral block (banners, chips).
  final Color surfaceHigh;

  /// One step *below* the page — the Material scheme's lowest container. Only
  /// the framework's own components reach for this.
  final Color surfaceSunken;

  /// A picked row in a selection list. Deliberately quieter than
  /// [primaryContainer]: a whole row of it must not read as a banner.
  final Color surfaceSelected;

  /// Section separator.
  final Color divider;

  /// Row separator inside a list — lighter than [divider].
  final Color hairline;

  final Color border;
  final Color borderInset;
  final Color borderStrong;

  /// Body text. The strongest ink there is.
  final Color ink;

  /// Titles and header glyphs — one step quieter than [ink], because a serif
  /// display line at 28pt does not need body-text weight to dominate.
  final Color inkStrong;

  /// Secondary text.
  final Color inkMuted;

  /// Tertiary text (metadata). Still clears 4.5:1.
  final Color inkFaint;

  /// Quaternary tone. Below 4.5:1 by design — only for text that repeats
  /// something already legible on the same row, or for decoration. Anything
  /// carrying unique information belongs in [inkFaint] or above.
  final Color inkGhost;

  /// A disabled control.
  final Color inkDisabled;

  final Color primary;

  /// Foreground on a [primary] fill. Not pure white in either appearance —
  /// white on a mid-tone fill is the other place glare comes from.
  final Color onPrimary;
  final Color primaryContainer;
  final Color primaryBorder;
  final Color onPrimaryContainer;

  final Color warn;

  /// Foreground on a filled [warn] button.
  final Color onWarn;
  final Color warnContainer;
  final Color warnBorder;
  final Color onWarnContainer;

  final Color danger;

  /// Foreground on a filled [danger] button.
  final Color onDanger;
  final Color dangerContainer;
  final Color dangerBorder;
  final Color onDangerContainer;

  /// Behind a modal.
  final Color scrim;

  /// A light wash over live content that is temporarily not interactive (the
  /// WebView during automation). Much weaker than [scrim] — the page under it
  /// is the thing being watched.
  final Color veil;

  /// Drop shadow, alpha included. Dark appearances need a heavier one: a
  /// shadow is only visible as a *difference* from the surface under it, and
  /// on a near-black page the light-theme value disappears entirely.
  final Color shadow;

  final Color toastSurface;
  final Color toastInk;
  final Color toastAccent;

  /// (background, foreground) pairs for the generated tiles that stand in for
  /// cover art and favicons. One table, so a collection monogram and a site tile
  /// cannot drift apart.
  final List<(Color, Color)> tilePairs;

  bool get isDark => brightness == Brightness.dark;

  /// The palette for the current theme. Falls back to [light] so a widget
  /// tested with a bare `MaterialApp` still renders.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? light;

  /// The prototype's hues, re-levelled away from paper-white (see the library
  /// note above).
  static const light = AppPalette(
    brightness: Brightness.light,
    surface: Color(0xFFF8F6F2),
    surfaceMuted: Color(0xFFF1EEE8),
    surfaceInset: Color(0xFFEBE7E0),
    surfaceHigh: Color(0xFFEFEBE4),
    surfaceSunken: Color(0xFFFCFAF7),
    surfaceSelected: Color(0xFFE7EFF3),
    divider: Color(0xFFE6E2DA),
    hairline: Color(0xFFE7E3DA),
    border: Color(0xFFDDD8CF),
    borderInset: Color(0xFFD6D0C6),
    borderStrong: Color(0xFFBBB4A8),
    ink: Color(0xFF24221E),
    inkStrong: Color(0xFF423E37),
    inkMuted: Color(0xFF5D584F),
    inkFaint: Color(0xFF6C665B),
    inkGhost: Color(0xFF918B80),
    inkDisabled: Color(0xFFB5AFA4),
    primary: Color(0xFF2A5464),
    onPrimary: Color(0xFFF8F6F2),
    primaryContainer: Color(0xFFE7EFF3),
    primaryBorder: Color(0xFFCCDFE6),
    onPrimaryContainer: Color(0xFF123642),
    warn: Color(0xFF875818),
    onWarn: Color(0xFFF8F6F2),
    warnContainer: Color(0xFFF5EBD7),
    warnBorder: Color(0xFFE3D0AC),
    onWarnContainer: Color(0xFF472D07),
    danger: Color(0xFF8C382E),
    onDanger: Color(0xFFF8F6F2),
    dangerContainer: Color(0xFFF4DBD6),
    dangerBorder: Color(0xFFE7C0B8),
    onDangerContainer: Color(0xFF471309),
    scrim: Color(0x8014120F),
    veil: Color(0x1A14120F),
    shadow: Color(0x241E1A14),
    toastSurface: Color(0xFF201F1C),
    toastInk: Color(0xFFECE8E1),
    toastAccent: Color(0xFF9CC0CB),
    tilePairs: _tilePairsLight,
  );

  /// Derived, not designed. The warm neutral of the light theme is kept —
  /// these are brown-greys, not blue-greys, which is also what keeps them
  /// coherent under a device warm filter — and the accents are lifted and
  /// desaturated rather than simply brightened.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    surface: Color(0xFF171614),
    surfaceMuted: Color(0xFF1F1E1B),
    surfaceInset: Color(0xFF252320),
    surfaceHigh: Color(0xFF2B2926),
    surfaceSunken: Color(0xFF121110),
    surfaceSelected: Color(0xFF1E3038),
    divider: Color(0xFF35322E),
    hairline: Color(0xFF2C2A26),
    border: Color(0xFF413D37),
    borderInset: Color(0xFF4B4640),
    borderStrong: Color(0xFF625C54),
    ink: Color(0xFFE2DDD4),
    inkStrong: Color(0xFFCEC8BE),
    inkMuted: Color(0xFFADA69B),
    inkFaint: Color(0xFF9C958B),
    inkGhost: Color(0xFF7B746A),
    inkDisabled: Color(0xFF635D54),
    primary: Color(0xFF95C0CF),
    onPrimary: Color(0xFF0F2129),
    primaryContainer: Color(0xFF1C333C),
    primaryBorder: Color(0xFF315361),
    onPrimaryContainer: Color(0xFFC6DEE7),
    warn: Color(0xFFCFA267),
    onWarn: Color(0xFF241A08),
    warnContainer: Color(0xFF34270F),
    warnBorder: Color(0xFF56411D),
    onWarnContainer: Color(0xFFEEDCB9),
    danger: Color(0xFFCE8B80),
    onDanger: Color(0xFF2A100C),
    dangerContainer: Color(0xFF3B1D18),
    dangerBorder: Color(0xFF5C2D26),
    onDangerContainer: Color(0xFFF0CFC8),
    scrim: Color(0xB3000000),
    veil: Color(0x33000000),
    shadow: Color(0x66000000),
    toastSurface: Color(0xFF302D29),
    toastInk: Color(0xFFE8E3DA),
    toastAccent: Color(0xFF9CC0CB),
    tilePairs: _tilePairsDark,
  );

  @override
  AppPalette copyWith({Brightness? brightness}) =>
      brightness == null || brightness == this.brightness
      ? this
      : (brightness == Brightness.dark ? dark : light);

  /// Snaps at the midpoint rather than interpolating.
  ///
  /// A cross-fade through the middle of these two palettes produces a muddy
  /// grey that belongs to neither, and the theme switch is a preference
  /// change — not an animation anyone is watching frame by frame.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// The generated-tile table, straight from the prototype's `FV` swatches.
const _tilePairsLight = <(Color, Color)>[
  (Color(0xFFD9E4E8), Color(0xFF224A57)),
  (Color(0xFFE2DFD5), Color(0xFF4A463B)),
  (Color(0xFFE9DDD5), Color(0xFF583D31)),
  (Color(0xFFDAE2DC), Color(0xFF334C3B)),
  (Color(0xFFE5DDE4), Color(0xFF4A3748)),
  (Color(0xFFE0E3E8), Color(0xFF373F4D)),
];

/// The same six hues, inverted. Backgrounds sit just above the dark card so a
/// grid of tiles does not read as a grid of lit windows; foregrounds clear
/// 4.5:1 on their own background.
const _tilePairsDark = <(Color, Color)>[
  (Color(0xFF20333A), Color(0xFFA9C8D2)),
  (Color(0xFF302D28), Color(0xFFC7C1B3)),
  (Color(0xFF362720), Color(0xFFD1B5A6)),
  (Color(0xFF223028), Color(0xFFACC6B4)),
  (Color(0xFF30252C), Color(0xFFC8AFC2)),
  (Color(0xFF23272E), Color(0xFFAFB7C5)),
];

/// Stable per-key tile colours: the same site or collection keeps the same tile
/// wherever it appears. Mirrors the prototype's `fav()` hash exactly so a
/// screenshot of the design and a screenshot of the app agree.
(Color, Color) tileColorsFor(String key, {required AppPalette palette}) {
  var h = 0;
  for (final unit in key.codeUnits) {
    h = (h * 31 + unit) & 0xFFFFFFFF;
  }
  return palette.tilePairs[h % palette.tilePairs.length];
}

/// The reader's own surface, which is dark in every appearance.
///
/// Not a second theme — a single fixed set of values for one screen that is
/// deliberately outside the light/dark preference, because it exists to show
/// images at night. It is kept here rather than in the reader so the choices
/// sit beside the ones they were derived from.
///
/// The canvas is a near-black, not `#000000`: on OLED a pure-black background
/// smears visibly under the continuous vertical scrolling this screen is built
/// for, and it maximises the halo around the overlaid chrome. It is dark
/// enough that a panel's own black borders still read as part of the artwork.
abstract final class ReaderColors {
  /// Behind the panels.
  static const canvas = Color(0xFF0C0B0A);

  /// Entry label in the top chrome.
  static const ink = Color(0xFFE2DDD4);

  /// Sub-title beside it.
  static const inkMuted = Color(0xFF9A938A);

  /// Counters and the end-of-entry rule.
  static const inkFaint = Color(0xFF7C766D);

  /// Disabled entry-step arrows.
  static const inkDisabled = Color(0xFF4C4841);

  /// Position bar and the read pill when set.
  static const accent = Color(0xFF9CC0CB);

  /// Track under the position bar.
  static const track = Color(0xFF262A2C);

  /// The read pill, unset then set.
  static const pill = Color(0xFF19181A);
  static const pillActive = Color(0xFF1E2528);

  /// The "next entry" button at the end of an entry.
  static const buttonSurface = Color(0xFF17191B);
  static const buttonInk = Color(0xFFD3DFE3);
  static const buttonBorder = Color(0xFF2E3336);

  /// Chrome gradients — the top and bottom bars fade into the canvas rather
  /// than sitting on a hard edge.
  static const chromeStrong = Color(0xF2000000);
  static const chromeSoft = Color(0xC0000000);
  static const chromeClear = Color(0x00000000);

  /// A panel whose file is missing or undecodable.
  static const brokenPanel = Color(0xFF241614);
  static const brokenPanelInk = Color(0xFFD9A79C);

  /// The partial-save banner.
  static const warnSurface = Color(0xFF2A2010);
  static const warnBorder = Color(0xFF4E3C19);
  static const warn = Color(0xFFD3A669);
  static const onWarn = Color(0xFF2A1D06);
  static const warnInk = Color(0xFFEBD6AC);
  static const warnInkMuted = Color(0xFFB9A47D);

  /// The "jump back to where you were" chip, and the save-again button on
  /// the unavailable state — the only two lit affordances on the screen.
  static const chipSurface = Color(0xFFDCE9ED);
  static const chipInk = Color(0xFF123642);

  /// The unavailable state's outlined way out.
  static const outlineInk = Color(0xFFD8D3CA);
  static const outlineBorder = Color(0xFF3A3733);
}
