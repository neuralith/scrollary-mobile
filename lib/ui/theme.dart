/// App theme, built from [AppPalette].
///
/// Every colour a widget can reach comes from the palette: the [ColorScheme],
/// the component themes below, and the shared text styles at the bottom of
/// this file. A literal `Color(0x…)` in a screen is a bug — it renders the
/// light design on a dark page, which is exactly how this app ended up with a
/// dark mode that looked like a light mode with the lamp switched off (D62).
///
/// Everything here is plain Material — no Cupertino widgets and no iOS-only
/// chrome — so the same UI renders on iOS and Android.
library;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Variable-font weight axis. Newsreader and IBM Plex Sans ship as variable
/// TTFs, so a bare [FontWeight] would not instantiate the axis.
List<FontVariation> wght(double w) => [FontVariation('wght', w)];

/// The persisted appearance preference.
const kAppearanceSettingKey = 'app.appearance';

/// System / Light / Dark, as the design's three-up control offers them.
enum AppearanceMode { system, light, dark }

AppearanceMode appearanceFromName(String? name) => AppearanceMode.values
    .firstWhere((m) => m.name == name, orElse: () => AppearanceMode.system);

ThemeMode themeModeFor(AppearanceMode mode) => switch (mode) {
  AppearanceMode.system => ThemeMode.system,
  AppearanceMode.light => ThemeMode.light,
  AppearanceMode.dark => ThemeMode.dark,
};

/// Collection monogram tile colours (background, foreground), keyed so a collection
/// keeps the same tile colour wherever it appears.
///
/// One table with the site favicons, because they are the same object — a
/// generated stand-in for artwork that does not exist — and two tables meant
/// the monograms had no dark variant at all.
(Color, Color) monogramFor(String id, AppPalette palette) =>
    palette.tilePairs[id.hashCode.abs() % palette.tilePairs.length];

/// Site favicon fallback tile, keyed by host.
(Color, Color) faviconColorsFor(String host, {required AppPalette palette}) =>
    tileColorsFor(host, palette: palette);

/// Two-letter monogram for a title, matching the prototype's tiles.
String monogramText(String title) {
  final words = title
      .split(RegExp(r'[\s:\-–—_]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '??';
  if (words.length == 1) {
    final w = words.first;
    return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// The dark appearance. Derived from [AppPalette.dark]; see the note there
/// about the design artifact shipping no dark variant (D56).
ThemeData appDarkTheme() => appTheme(palette: AppPalette.dark);

/// Built from [palette] so the [ColorScheme] and the extension can never
/// disagree — the two would drift within a week if they were written out
/// twice.
ThemeData appTheme({AppPalette palette = AppPalette.light}) {
  final dark = palette.isDark;
  final scheme = ColorScheme(
    brightness: palette.brightness,
    primary: palette.primary,
    onPrimary: palette.onPrimary,
    primaryContainer: palette.primaryContainer,
    onPrimaryContainer: palette.onPrimaryContainer,
    secondary: palette.inkMuted,
    onSecondary: dark ? palette.surface : palette.onPrimary,
    secondaryContainer: palette.surfaceHigh,
    onSecondaryContainer: palette.inkStrong,
    tertiary: palette.warn,
    onTertiary: palette.onWarn,
    tertiaryContainer: palette.warnContainer,
    onTertiaryContainer: palette.onWarnContainer,
    error: palette.danger,
    onError: palette.onDanger,
    errorContainer: palette.dangerContainer,
    onErrorContainer: palette.onDangerContainer,
    surface: palette.surface,
    onSurface: palette.ink,
    surfaceContainerLowest: palette.surfaceSunken,
    surfaceContainerLow: palette.surfaceMuted,
    surfaceContainer: palette.surfaceMuted,
    surfaceContainerHigh: palette.surfaceHigh,
    surfaceContainerHighest: palette.surfaceInset,
    onSurfaceVariant: palette.inkMuted,
    outline: palette.borderStrong,
    outlineVariant: palette.border,
    shadow: palette.shadow,
    scrim: palette.scrim,
    inverseSurface: palette.toastSurface,
    onInverseSurface: palette.toastInk,
    inversePrimary: palette.toastAccent,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    fontFamily: 'IBM Plex Sans',
    scaffoldBackgroundColor: palette.surface,
    canvasColor: palette.surface,
    extensions: [palette],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
      fontFamily: 'IBM Plex Sans',
    ),
    iconTheme: IconThemeData(color: palette.inkMuted),
    primaryIconTheme: IconThemeData(color: palette.inkMuted),
    dividerColor: palette.divider,
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.inkStrong,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: palette.inkMuted),
      actionsIconTheme: IconThemeData(color: palette.inkMuted),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 15,
        fontVariations: wght(600),
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        disabledBackgroundColor: palette.surfaceInset,
        disabledForegroundColor: palette.inkDisabled,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: TextStyle(
          fontFamily: 'IBM Plex Sans',
          fontSize: 14,
          fontVariations: wght(600),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.inkStrong,
        disabledForegroundColor: palette.inkDisabled,
        side: BorderSide(color: palette.borderStrong),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        textStyle: TextStyle(
          fontFamily: 'IBM Plex Sans',
          fontSize: 14,
          fontVariations: wght(500),
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        disabledForegroundColor: palette.inkDisabled,
        textStyle: TextStyle(
          fontFamily: 'IBM Plex Sans',
          fontSize: 13,
          fontVariations: wght(500),
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.inkMuted,
        disabledForegroundColor: palette.inkDisabled,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: palette.borderStrong,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      iconColor: palette.inkMuted,
      titleTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 17,
        fontVariations: wght(600),
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 13,
        height: 1.55,
        color: palette.inkMuted,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surfaceMuted,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      textStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 13.5,
        color: palette.ink,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surfaceMuted),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.toastSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 11.5,
        color: palette.toastInk,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.toastSurface,
      actionTextColor: palette.toastAccent,
      contentTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 13,
        color: palette.toastInk,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.inkMuted,
      textColor: palette.ink,
      subtitleTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 12.5,
        height: 1.4,
        color: palette.inkFaint,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceHigh,
      selectedColor: palette.primaryContainer,
      disabledColor: palette.surfaceInset,
      side: BorderSide(color: palette.border),
      labelStyle: TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontSize: 12,
        color: palette.inkStrong,
      ),
      iconTheme: IconThemeData(color: palette.inkMuted, size: 15),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceInset,
      hintStyle: TextStyle(color: palette.inkGhost),
      labelStyle: TextStyle(color: palette.inkMuted),
      floatingLabelStyle: TextStyle(color: palette.primary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.primary, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.primary,
      selectionColor: palette.primary.withValues(alpha: dark ? 0.34 : 0.22),
      selectionHandleColor: palette.primary,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(palette.onPrimary),
      side: BorderSide(color: palette.borderStrong, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.borderStrong,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.onPrimary
            : palette.inkFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.surfaceInset,
      ),
      trackOutlineColor: WidgetStatePropertyAll(palette.border),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.primary,
      linearTrackColor: palette.border,
      circularTrackColor: Colors.transparent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(palette.borderStrong),
    ),
  );
}
