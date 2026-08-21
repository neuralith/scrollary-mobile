import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/asset_fetcher.dart';

Uint8List bytesOf(List<int> v) => Uint8List.fromList(v);

void main() {
  group('detectImageMime', () {
    test(
      'recognises AVIF, which a real image sequence CDN actually serves',
      () async {
        // Regression: example.com serves `.avif` panels. The verifier only knew
        // PNG/JPEG/GIF/WebP, so all 15 detected images were rejected as "not a
        // usable image" and the entry failed with "No images could be
        // downloaded" — despite every download succeeding.
        final file = File('test/fixtures/sample.avif');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'sample.avif is the real byte stream from that CDN',
        );
        final bytes = await file.readAsBytes();

        expect(detectImageMime(bytes), 'image/avif');
        expect(bytes.length, greaterThan(1000));
      },
    );

    test('recognises the ISO-BMFF brands by name', () {
      Uint8List isoBmff(String brand) => bytesOf([
        0x00, 0x00, 0x00, 0x1c, // box length
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        ...brand.codeUnits,
        0x00, 0x00, 0x00, 0x00,
      ]);

      expect(detectImageMime(isoBmff('avif')), 'image/avif');
      expect(detectImageMime(isoBmff('avis')), 'image/avif');
      expect(detectImageMime(isoBmff('heic')), 'image/heic');
      expect(detectImageMime(isoBmff('mif1')), 'image/heif');
      // An ISO container that is not a still image is not accepted.
      expect(detectImageMime(isoBmff('mp42')), isNull);
      expect(detectImageMime(isoBmff('qt  ')), isNull);
    });

    test('recognises the classic formats', () {
      expect(
        detectImageMime(bytesOf([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])),
        'image/png',
      );
      expect(detectImageMime(bytesOf([0xff, 0xd8, 0xff, 0xe0])), 'image/jpeg');
      expect(
        detectImageMime(bytesOf([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        'image/gif',
      );
      expect(
        detectImageMime(
          bytesOf([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x00, 0x00, 0x00, 0x00,
            0x57, 0x45, 0x42, 0x50, // WEBP
          ]),
        ),
        'image/webp',
      );
      expect(detectImageMime(bytesOf([0x42, 0x4d, 0, 0])), 'image/bmp');
    });

    test('rejects an HTML error page served with a 200', () {
      // The exact failure the magic-number check exists to catch.
      final html = bytesOf('<!doctype html><html><body>403'.codeUnits);
      expect(detectImageMime(html), isNull);
    });

    test('rejects short or empty payloads without throwing', () {
      expect(detectImageMime(bytesOf([])), isNull);
      expect(detectImageMime(bytesOf([0x89])), isNull);
      expect(detectImageMime(bytesOf([0x00, 0x00, 0x00, 0x1c])), isNull);
    });
  });
}
