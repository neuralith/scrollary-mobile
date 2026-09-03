import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/reading_v2/source_reading.dart';
import 'package:web_reader/save/rendered_capture.dart';
import 'package:web_reader/storage/file_store.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// **A rendering of the page, produced without holding the page in memory.**
///
/// The shape that cannot work is the obvious one: settle the reading, then
/// capture it. Measured on a real page of 134 panels, a settled document holds
/// every panel decoded, a full-scale viewport snapshot is another 9.5MB of
/// bitmap on top, and the process is killed part-way down. What is asserted
/// here is the shape that does work — one tile in flight, written and released
/// before the next scroll — plus the tiling arithmetic that decides what a
/// reader ends up looking at.
void main() {
  late Directory root;
  late FileStore store;
  late StagingHandle staging;

  /// Stands in for the platform's JPEG encoder. A real image either way, so
  /// the dimensions the module records are parsed from a real header.
  final tileBytes = panelPng(entry: 1, index: 1, width: 400, height: 600);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('webread_rendered');
    store = FileStore(root);
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);
    staging = await store.beginEntry(collectionId: null, entryId: 'e1');
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<RenderedCapture> render({
    required int bandTop,
    required int bandBottom,
    required int viewportHeight,
    int targetPixelWidth = 720,
    int documentHeight = 100000,
    _ScrollingBrowser? browser,
  }) {
    final fake =
        browser ??
        _ScrollingBrowser(
          tile: tileBytes,
          viewportHeight: viewportHeight,
          documentHeight: documentHeight,
        );
    return captureRenderedBand(
      browser: fake,
      staging: staging,
      band: ImageContentBand(top: bandTop, bottom: bandBottom, imageCount: 20),
      viewportHeight: viewportHeight,
      targetPixelWidth: targetPixelWidth,
      pageUrl: 'https://reading.example.com/entry/1',
    );
  }

  group('what a reader ends up with', () {
    test('one tile per viewport down the band, in reading order', () async {
      final result = await render(
        bandTop: 300,
        bandBottom: 300 + 400 * 5,
        viewportHeight: 400,
      );

      expect(result.isUsable, isTrue, reason: '${result.failure}');
      expect(result.assets, hasLength(5));
      expect(result.assets.map((a) => a.index).toList(), [
        1,
        2,
        3,
        4,
        5,
      ], reason: 'index is position in reading order, and it is dense');
      // Each tile records the document position it was taken at, so ordering
      // is checkable rather than assumed.
      final positions = [
        for (final a in result.assets)
          int.parse(a.sourceUrl.split('#rendered-at-').last),
      ];
      expect(positions, [300, 700, 1100, 1500, 1900]);
    });

    test('the last tile ends at the band, not past it', () async {
      // A band that is not a whole number of viewports. Running the last tile
      // past the end would put a screenful of whatever follows the reading
      // into the saved copy; pulling it back repeats a sliver instead.
      final result = await render(
        bandTop: 0,
        bandBottom: 1000,
        viewportHeight: 400,
      );

      expect(result.assets, hasLength(3));
      final positions = [
        for (final a in result.assets)
          int.parse(a.sourceUrl.split('#rendered-at-').last),
      ];
      expect(positions, [
        0,
        400,
        600,
      ], reason: 'the third tile covers 600..1000, which is exactly the band');
    });

    test('every tile is on disk, sized from its own bytes', () async {
      final result = await render(
        bandTop: 0,
        bandBottom: 1200,
        viewportHeight: 400,
      );

      for (final asset in result.assets) {
        expect(asset.isStored, isTrue);
        expect(asset.mimeType, 'image/jpeg');
        expect(asset.dimensionsVerified, isTrue);
        expect(asset.width, 400);
        expect(asset.height, 600);
        final file = File('${staging.dir.path}/${asset.relativePath}');
        expect(file.existsSync(), isTrue, reason: '${asset.relativePath}');
      }
    });

    test('nothing the returned assets carry is image data', () async {
      // The bounded-memory contract, stated as a property: what comes back
      // describes files. A tile's bytes exist only between the capture and
      // the write.
      final result = await render(
        bandTop: 0,
        bandBottom: 4000,
        viewportHeight: 400,
      );
      expect(result.assets, hasLength(10));
      expect(
        result.bytes,
        tileBytes.length * 10,
        reason: 'the total is counted, never accumulated in a buffer',
      );
    });
  });

  group('what it refuses to produce', () {
    test('a band taller than a reading', () async {
      final result = await render(
        bandTop: 0,
        bandBottom: 400 * (kRenderedTileCeiling + 1),
        viewportHeight: 400,
      );
      expect(result.isUsable, isFalse);
      expect(result.failure, contains('more than a reading'));
      expect(
        Directory('${staging.dir.path}/assets').existsSync() &&
            Directory('${staging.dir.path}/assets').listSync().isNotEmpty,
        isFalse,
        reason: 'and it wrote nothing before deciding',
      );
    });

    test('a page that reports no viewport', () async {
      final result = await render(
        bandTop: 0,
        bandBottom: 4000,
        viewportHeight: 0,
      );
      expect(result.isUsable, isFalse);
      expect(result.failure, contains('no viewport'));
    });

    test('too little to be worth keeping', () async {
      final result = await render(
        bandTop: 0,
        bandBottom: 300,
        viewportHeight: 400,
      );
      expect(result.isUsable, isFalse);
      expect(result.failure, contains('too little'));
    });

    test('a page that will not scroll', () async {
      // A document that clamps: every scroll lands in the same place, so
      // every tile would be the same pixels. Stopping is the only honest
      // answer, and two identical tiles are not a reading.
      final result = await render(
        bandTop: 0,
        bandBottom: 4000,
        viewportHeight: 400,
        browser: _ScrollingBrowser(
          tile: tileBytes,
          viewportHeight: 400,
          documentHeight: 100000,
          frozen: true,
        ),
      );
      expect(result.isUsable, isFalse);
    });

    test('a platform that hands back nothing', () async {
      final result = await render(
        bandTop: 0,
        bandBottom: 4000,
        viewportHeight: 400,
        browser: _ScrollingBrowser(
          tile: tileBytes,
          viewportHeight: 400,
          documentHeight: 100000,
          captureNull: true,
        ),
      );
      expect(result.isUsable, isFalse);
    });
  });

  test(
    'a rendering replaces a part-finished attempt, it does not join it',
    () async {
      // The primary path stores whatever arrived before it was refused. Those
      // files are not part of a rendering, and leaving them would put original
      // bytes under the same names as the tiles.
      final leftover = staging.assetFile('001.jpg');
      leftover.parent.createSync(recursive: true);
      leftover.writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      final stale = staging.assetFile('099.jpg')
        ..writeAsBytesSync(Uint8List.fromList([4, 5, 6]));

      final result = await render(
        bandTop: 0,
        bandBottom: 1200,
        viewportHeight: 400,
      );

      expect(result.assets, hasLength(3));
      expect(stale.existsSync(), isFalse, reason: 'the stray file is gone');
      expect(
        leftover.readAsBytesSync(),
        tileBytes,
        reason: '001.jpg is the first tile now, not the original that arrived',
      );
    },
  );
}

/// A browser whose page really moves, so the module's scroll arithmetic is
/// exercised rather than assumed.
class _ScrollingBrowser extends FakeBrowser {
  _ScrollingBrowser({
    required this.tile,
    required this.viewportHeight,
    required this.documentHeight,
    this.frozen = false,
    this.captureNull = false,
  });

  final Uint8List tile;
  final int viewportHeight;
  final int documentHeight;

  /// A document that refuses to move — every scroll lands at zero.
  final bool frozen;
  final bool captureNull;

  int _y = 0;

  /// How many captures were asked for, and the widths they were asked at.
  final List<int?> requestedWidths = [];

  @override
  Future<void> scrollTo(int y) async {
    if (frozen) return;
    final maxY = documentHeight - viewportHeight;
    _y = y < 0 ? 0 : (y > maxY ? maxY : y);
  }

  @override
  Future<PageProbe> probe({
    bool withLinks = false,
    bool withSignals = true,
  }) async => PageProbe(
    url: 'https://reading.example.com/entry/1',
    title: 'An entry',
    readyState: 'complete',
    documentHeight: documentHeight,
    viewportHeight: viewportHeight,
    viewportWidth: 400,
    scrollY: _y,
    atBottom: _y >= documentHeight - viewportHeight,
  );

  @override
  Future<Uint8List?> captureViewport({
    int? targetPixelWidth,
    int quality = 82,
  }) async {
    requestedWidths.add(targetPixelWidth);
    return captureNull ? null : tile;
  }
}
