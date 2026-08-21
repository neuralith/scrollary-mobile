import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/image_dimensions.dart';

import '../tool/fixture/fixture_site.dart';

/// The dimension reader is the source of truth for stored assets, so every
/// format the downloader accepts is covered — plus the failure modes
/// (truncation, garbage) that must return null rather than a guess.
void main() {
  group('PNG', () {
    test('reads IHDR dimensions', () {
      expect(
        readImageDimensions(solidPng(800, 1200, 1, 2, 3)),
        const ImageDimensions(800, 1200),
      );
      expect(
        readImageDimensions(panelPng(entry: 1, index: 3)),
        const ImageDimensions(800, 1200),
      );
    });

    test('a truncated header is null, not zero-by-zero', () {
      final bytes = solidPng(800, 1200, 1, 2, 3).sublist(0, 20);
      expect(readImageDimensions(bytes), isNull);
    });
  });

  group('JPEG', () {
    Uint8List jpegSof({required int width, required int height}) =>
        Uint8List.fromList([
          0xff, 0xd8, // SOI
          0xff, 0xc0, 0x00, 0x11, 0x08, // SOF0, length, precision
          height >> 8, height & 0xff,
          width >> 8, width & 0xff,
          3, 0, 0, 0, 0, 0, // component stubs
        ]);

    test('reads the first SOF frame', () {
      expect(
        readImageDimensions(jpegSof(width: 720, height: 15000)),
        const ImageDimensions(720, 15000),
      );
    });

    test('EXIF orientation 6 swaps the reported dimensions', () {
      // APP1/EXIF (big-endian TIFF, orientation tag = 6) before the SOF.
      final exif = <int>[
        0xff, 0xd8,
        0xff, 0xe1, 0x00, 0x22, // APP1, length 34
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
        0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // TIFF header
        0x00, 0x01, // one IFD entry
        0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // orientation, SHORT
        0x00, 0x06, 0x00, 0x00, // value 6 (rotate 90)
        0x00, 0x00, 0x00, 0x00, // no next IFD
        0xff, 0xc0, 0x00, 0x11, 0x08,
        0x02, 0x00, // height 512
        0x04, 0x00, // width 1024
        3, 0, 0, 0, 0, 0,
      ];
      expect(
        readImageDimensions(Uint8List.fromList(exif)),
        const ImageDimensions(512, 1024),
        reason: 'the decoder rotates, so the layout must use rotated dims',
      );
    });
  });

  test('GIF logical screen descriptor', () {
    final gif = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
      0x20, 0x03, // 800 little-endian
      0xb0, 0x04, // 1200 little-endian
      0, 0, 0,
    ]);
    expect(readImageDimensions(gif), const ImageDimensions(800, 1200));
  });

  test('BMP BITMAPINFOHEADER, including top-down negative height', () {
    Uint8List bmp(int w, int h) {
      final b = Uint8List(30);
      b[0] = 0x42;
      b[1] = 0x4d;
      b[14] = 40; // header size
      ByteData.view(b.buffer).setInt32(18, w, Endian.little);
      ByteData.view(b.buffer).setInt32(22, h, Endian.little);
      return b;
    }

    expect(readImageDimensions(bmp(640, 480)), const ImageDimensions(640, 480));
    expect(
      readImageDimensions(bmp(640, -480)),
      const ImageDimensions(640, 480),
      reason: 'negative means top-down, not a negative size',
    );
  });

  group('WebP', () {
    Uint8List riff(String fourcc, List<int> payload) => Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF + size (unused)
      0x57, 0x45, 0x42, 0x50, // WEBP
      ...fourcc.codeUnits, 0, 0, 0, 0, // chunk + size (unused)
      ...payload,
    ]);

    test('VP8X extended header', () {
      final bytes = riff('VP8X', [
        0, 0, 0, 0, // flags + reserved
        0x1f, 0x03, 0x00, // width-1 = 799
        0xaf, 0x04, 0x00, // height-1 = 1199
      ]);
      expect(readImageDimensions(bytes), const ImageDimensions(800, 1200));
    });

    test('VP8 lossy frame header', () {
      final bytes = riff('VP8 ', [
        0, 0, 0, // frame tag
        0x9d, 0x01, 0x2a, // start code
        0x20, 0x03, // 800
        0xb0, 0x04, // 1200
      ]);
      expect(readImageDimensions(bytes), const ImageDimensions(800, 1200));
    });

    test('VP8L lossless bitstream', () {
      // 14-bit fields, minus one, packed after the 0x2F signature.
      const w = 800, h = 1200;
      final bits = (w - 1) | ((h - 1) << 14);
      final bytes = riff('VP8L', [
        0x2f,
        bits & 0xff,
        (bits >> 8) & 0xff,
        (bits >> 16) & 0xff,
        (bits >> 24) & 0xff,
      ]);
      expect(readImageDimensions(bytes), const ImageDimensions(800, 1200));
    });
  });

  group('AVIF / ISO-BMFF', () {
    Uint8List box(String type, List<int> payload) {
      final size = 8 + payload.length;
      return Uint8List.fromList([
        (size >> 24) & 0xff,
        (size >> 16) & 0xff,
        (size >> 8) & 0xff,
        size & 0xff,
        ...type.codeUnits,
        ...payload,
      ]);
    }

    List<int> ispe(int w, int h) => box('ispe', [
      0, 0, 0, 0, // version + flags
      (w >> 24) & 0xff, (w >> 16) & 0xff, (w >> 8) & 0xff, w & 0xff,
      (h >> 24) & 0xff, (h >> 16) & 0xff, (h >> 8) & 0xff, h & 0xff,
    ]);

    Uint8List avif(List<List<int>> ispeBoxes) {
      final ipco = box('ipco', [for (final b in ispeBoxes) ...b]);
      final iprp = box('iprp', ipco);
      final meta = box('meta', [0, 0, 0, 0, ...iprp]);
      return Uint8List.fromList([
        ...box('ftyp', 'avifavif'.codeUnits),
        ...meta,
      ]);
    }

    test('reads the ispe property', () {
      expect(
        readImageDimensions(avif([ispe(800, 16000)])),
        const ImageDimensions(800, 16000),
        reason: 'real example panels are strips this tall',
      );
    });

    test('several ispe boxes: the full image (largest) wins', () {
      expect(
        readImageDimensions(avif([ispe(160, 90), ispe(800, 13850)])),
        const ImageDimensions(800, 13850),
        reason: 'thumbnail/alpha properties must not shadow the image',
      );
    });
  });

  test('garbage and empty input are null', () {
    expect(readImageDimensions(Uint8List(0)), isNull);
    expect(
      readImageDimensions(Uint8List.fromList(List.filled(64, 0x41))),
      isNull,
    );
    expect(
      readImageDimensions(
        Uint8List.fromList('<html>error page</html>'.codeUnits),
      ),
      isNull,
    );
  });
}
