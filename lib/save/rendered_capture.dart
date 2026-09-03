/// Keeping a reading the browser drew, when its files cannot be had.
///
/// **Secondary, always.** Original bytes are what a saved reading is; this is
/// what is left when a host serves its pictures to the browser and to nothing
/// else (see `asset_fetcher.dart` for why that has no other answer, and
/// `data/asset_origin_repository.dart` for how the app comes to believe it).
/// Nothing here obtains a protected file: the compositor is asked for the
/// pixels it has already put on the screen the person is looking at, which is
/// the same thing the device's own screenshot key does.
///
/// It is also honest about what it produced. The package is marked
/// `renderedFromPage`, the reader says so, and nobody can mistake it for the
/// files themselves.
///
/// ## Bounded memory is the whole design
///
/// The naive shape — settle the page, then capture it — is the one that cannot
/// work. Measured on a real reading of 134 panels: a settled page holds every
/// panel decoded, a full-scale viewport snapshot is another 9.5MB of bitmap on
/// top of that, and the process is killed part-way down. Three things keep
/// this inside the envelope, and each was measured rather than guessed:
///
/// 1. **One tile exists at a time.** Every capture is written to staging and
///    the reference dropped before the next scroll. The list this returns
///    holds file names, never bytes.
/// 2. **Reduced scale.** A tile is asked for at about the width of the
///    pictures it is a rendering of, not at the screen's own scale. A 3x
///    screen would otherwise produce a 1206px-wide tile of a 720px panel:
///    three times the pixels and no more detail. Full scale measured 402KB per
///    tile against 33KB at reduced scale on the same page.
/// 3. **JPEG, from the platform.** `dart:ui` can only encode PNG, and PNG of
///    these renderings measured 1.68MB a tile — 200MB for one reading. The
///    platform's own JPEG encoder never puts the bitmap in the Dart heap at
///    all.
library;

import 'dart:io' show File;
import 'dart:typed_data';

import '../browser/browser_controller.dart';
import '../core/image_dimensions.dart';
import '../reading_v2/source_reading.dart' show ImageContentBand;
import '../storage/file_store.dart';
import '../storage/manifest.dart';

/// A tile is asked for at about this width in pixels, unless the reading's own
/// pictures are narrower.
///
/// Wide enough that a phone-sized rendering loses nothing a reader would
/// notice, and far below what a 3x screen would hand over unasked.
const int kRenderedTileMaxWidth = 1080;

/// Give up rather than produce a package of this many tiles.
///
/// A reading is a reading; a document that needs more viewports than this is
/// something else, and quietly writing a thousand files for it is not a save.
const int kRenderedTileCeiling = 400;

/// What a rendered capture came to.
class RenderedCapture {
  const RenderedCapture({
    required this.assets,
    required this.bytes,
    required this.tileWidth,
    this.failure,
  });

  const RenderedCapture.failed(String this.failure)
    : assets = const [],
      bytes = 0,
      tileWidth = 0;

  /// One per tile, in reading order, already on disk.
  final List<EntryAsset> assets;
  final int bytes;
  final int tileWidth;

  /// Why nothing usable came of it, or null.
  final String? failure;

  bool get isUsable => failure == null && assets.length >= 2;
}

/// Render [band] into ordered JPEG tiles inside [staging].
///
/// Reading order is the page's own vertical order, because that is what the
/// tiles are: consecutive slices down the band, each starting where the last
/// one ended. There is no filename to trust and no ordering to infer.
///
/// [targetPixelWidth] is what the caller knows about the pictures being
/// rendered — the content images' own width — so a reading of 720px panels is
/// not stored at 1206px. Clamped to [kRenderedTileMaxWidth].
Future<RenderedCapture> captureRenderedBand({
  required BrowserController browser,
  required StagingHandle staging,
  required ImageContentBand band,
  required int viewportHeight,
  required int targetPixelWidth,
  required String pageUrl,
  Future<void> Function()? checkpoint,
  void Function(int stored, int total)? onProgress,
  void Function(String)? log,
}) async {
  if (viewportHeight <= 0) {
    return const RenderedCapture.failed('the page reported no viewport');
  }
  if (band.height <= 0) {
    return const RenderedCapture.failed('the readable band has no height');
  }

  final tileWidth = targetPixelWidth <= 0
      ? kRenderedTileMaxWidth
      : (targetPixelWidth < kRenderedTileMaxWidth
            ? targetPixelWidth
            : kRenderedTileMaxWidth);

  final total = (band.height / viewportHeight).ceil();
  if (total > kRenderedTileCeiling) {
    return RenderedCapture.failed(
      'the readable band is $total viewports tall, more than a reading',
    );
  }

  // Whatever the primary path managed before it was refused is not part of a
  // rendering, and leaving it behind would put a handful of original files
  // under the same names as the tiles about to be written. A rendering
  // replaces the attempt, it does not join it.
  final assetsDir = staging.assetFile('x').parent;
  if (assetsDir.existsSync()) {
    for (final leftover in assetsDir.listSync()) {
      if (leftover is File) leftover.deleteSync();
    }
  }

  final assets = <EntryAsset>[];
  var bytes = 0;
  var lastTop = -1;

  for (var index = 0; index < total; index++) {
    if (checkpoint != null) await checkpoint();

    // The last tile is pulled back so it *ends* at the band rather than
    // running past it: a repeated sliver at the very end of a reading is
    // better than a screenful of the comments underneath it.
    final wanted = index == total - 1 && total > 1
        ? band.bottom - viewportHeight
        : band.top + index * viewportHeight;
    final target = wanted < band.top ? band.top : wanted;

    await browser.scrollTo(target);
    // Where the page actually went, which is not always where it was sent —
    // a document clamps at its own end, and a tile has to describe the
    // pixels that were really captured.
    final settled = await browser.probe(withSignals: false);
    final actualTop = settled.scrollY;
    if (actualTop <= lastTop && index > 0) {
      log?.call(
        'rendered capture stopped at tile $index: the page would not scroll '
        'past $actualTop',
      );
      break;
    }
    lastTop = actualTop;

    final jpeg = await browser.captureViewport(targetPixelWidth: tileWidth);
    if (jpeg == null || jpeg.isEmpty) {
      log?.call('rendered capture: tile $index came back empty');
      break;
    }
    // Written and released before the next scroll. Nothing above holds a
    // reference to these bytes, which is what keeps a hundred-tile reading
    // inside one tile's worth of memory.
    final asset = await _writeTile(
      staging: staging,
      index: assets.length + 1,
      pageUrl: pageUrl,
      documentTop: actualTop,
      jpeg: jpeg,
    );
    bytes += jpeg.length;
    assets.add(asset);
    onProgress?.call(assets.length, total);
  }

  if (assets.length < 2) {
    return const RenderedCapture.failed(
      'too little of the page could be rendered to be worth keeping',
    );
  }
  log?.call(
    'rendered ${assets.length}/$total tile(s) at ${tileWidth}px wide, '
    '${(bytes / 1024).round()}KB total',
  );
  return RenderedCapture(assets: assets, bytes: bytes, tileWidth: tileWidth);
}

Future<EntryAsset> _writeTile({
  required StagingHandle staging,
  required int index,
  required String pageUrl,
  required int documentTop,
  required Uint8List jpeg,
}) async {
  final fileName = '${index.toString().padLeft(3, '0')}.jpg';
  final file = staging.assetFile(fileName);
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(jpeg, flush: true);
  final size = readImageDimensions(jpeg);
  return EntryAsset(
    index: index,
    // There is no file behind a tile, so the address says what it actually
    // is: this page, at this position down it. Unique per tile, and it never
    // pretends to be something that could be re-fetched.
    sourceUrl: '$pageUrl#rendered-at-$documentTop',
    status: AssetStatus.stored,
    relativePath: StagingHandle.assetRelativePath(fileName),
    mimeType: 'image/jpeg',
    byteSize: jpeg.length,
    width: size?.width,
    height: size?.height,
    dimensionsVerified: size != null,
  );
}
