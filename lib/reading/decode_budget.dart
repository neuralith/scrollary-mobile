import 'dart:math' show sqrt;

/// How wide a stored image should be *decoded*, given the width it will be
/// painted at.
///
/// **Never wider than the image really is.** Both readers used to hand
/// `Image.file` a `cacheWidth` of the display width in physical pixels, with no
/// reference to the file. When the stored image is narrower than the screen —
/// which is the normal case for long-strip content, commonly 720–900 px wide on
/// a 1179 px-wide phone — that instructs the decoder to *upscale*, and an
/// upscaled bitmap costs `(display / natural)²` times the memory while adding
/// no detail whatsoever. At 800 px natural on a 1179 px screen that is 2.17×,
/// paid on every resident panel.
///
/// Clamping is lossless in the strict sense: the same pixels reach the screen
/// either way. Flutter simply scales at paint time instead of at decode time,
/// which is where scaling belongs.
///
/// [naturalWidth] is the stored file's own width, from the manifest, and is
/// null when the save could not verify it. Unknown means "do not guess" — the
/// display width is used, exactly as before.
int? decodeWidthFor({
  required double displayWidth,
  required double devicePixelRatio,
  int? naturalWidth,
}) {
  final target = (displayWidth * devicePixelRatio).round();
  if (target <= 0) return null;
  if (naturalWidth == null || naturalWidth <= 0) return target;
  return target < naturalWidth ? target : naturalWidth;
}

/// A ceiling on the decoded size of one image, in pixels of width.
///
/// The second half of the problem, and a smaller one: a single very tall strip
/// can be tens of megapixels on its own. A structured document builds every
/// block eagerly — that is what makes its restore offsets exact — so an
/// image-heavy document holds all of them at once and one pathological panel
/// is multiplied by the whole document.
///
/// [budgetPixels] is a whole-image budget rather than a height cap, because
/// what costs memory is area. Returns the width to decode at so the decoded
/// area stays inside the budget, or [width] when it already does.
///
/// Applied *after* [decodeWidthFor], so it can only ever shrink further. It
/// takes effect on images that are already being downscaled by a large factor,
/// where a little more downscaling is not visible; ordinary panels never reach
/// it. Nothing here touches the stored bytes, which stay byte-for-byte as
/// captured.
int decodeWidthWithinBudget({
  required int width,
  required int? naturalWidth,
  required int? naturalHeight,
  int budgetPixels = kPanelDecodeBudgetPixels,
}) {
  if (naturalWidth == null ||
      naturalHeight == null ||
      naturalWidth <= 0 ||
      naturalHeight <= 0) {
    return width;
  }
  final aspect = naturalHeight / naturalWidth;
  final area = width * width * aspect;
  if (area <= budgetPixels) return width;
  final capped = sqrt(budgetPixels / aspect).round();
  return capped < 1 ? 1 : capped;
}

/// 24 megapixels — about 96 MB decoded at 4 bytes a pixel.
///
/// Chosen to sit well above an ordinary full-screen panel (a 1179 × 4000 strip
/// is 4.7 MP) so normal reading never reaches it, and far below the ~21 MP a
/// single upscaled long strip was costing. It bounds the pathological case
/// without touching the common one.
const int kPanelDecodeBudgetPixels = 24 * 1000 * 1000;
