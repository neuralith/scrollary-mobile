/// How this app opens a bottom-sheet menu, defined once.
///
/// **The bug this exists to prevent.** A stock `showModalBottomSheet` caps its
/// sheet at **nine sixteenths of the screen** unless it is told otherwise, and
/// a `Column` handed less height than it needs does not scroll or shrink — it
/// overflows, and the remainder is clipped, unhittable and unreachable. Eight
/// sheets were built as `SafeArea > Column(min)` with no scroll view and no
/// `isScrollControlled`, so on a 844pt phone every one of them was cut off at
/// 474.8pt: the Entry menu lost *Download for offline*, *Remove offline copy*
/// and *Remove from library* — four of its nine items — with nothing to scroll.
///
/// It survived because the widget-test window is 430×1400. Nine sixteenths of
/// that is 787pt, and the extra width lets subtitles wrap to fewer lines, so
/// the menus fitted in tests and in no phone anybody owns.
///
/// The shape here is the one `library_ui/entry_details.dart` already used and
/// the menus never adopted: **scroll-controlled, so the sheet may be as tall
/// as it needs, inside a scroll view, so being taller than the screen is a
/// scroll rather than a clip.** A `Column` with `MainAxisSize.min` inside a
/// `SingleChildScrollView` is exactly as tall as its contents, which means a
/// short menu is still short — no fixed height, no fraction, nothing to tune
/// per menu.
library;

import 'package:flutter/material.dart';

/// Open [builder]'s widget as a menu sheet.
///
/// [builder] returns the menu's own content — typically a
/// `Column(mainAxisSize: MainAxisSize.min)`. The safe area and the scrolling
/// are this function's, not the caller's: a caller that supplies its own is
/// how the two came apart in the first place.
///
/// `useSafeArea` keeps a full-height sheet from sliding under the status bar;
/// the inner [SafeArea] is what keeps its last item clear of the home
/// indicator.
Future<T?> showLibraryMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: showDragHandle,
  builder: (sheetContext) =>
      SafeArea(child: SingleChildScrollView(child: builder(sheetContext))),
);
