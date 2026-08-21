import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/asset_fetcher.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/image_dimensions.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'helpers/fake_browser.dart';

/// Stored extensions come from the verified bytes, not the URL — a real CDN
/// serves image/jpeg under `.webp` names (observed during the capture audit).
void main() {
  group('fileNameFor', () {
    test('extension follows the sniffed MIME, not the URL', () {
      expect(
        AssetFetcher.fileNameFor(
          1,
          'image/jpeg',
          'https://cdn.example/p/a.webp',
        ),
        '001.jpg',
      );
      expect(
        AssetFetcher.fileNameFor(
          2,
          'image/webp',
          'https://cdn.example/p/a.webp',
        ),
        '002.webp',
      );
      expect(
        AssetFetcher.fileNameFor(
          3,
          'image/avif',
          'https://cdn.example/p/a.jpg',
        ),
        '003.avif',
      );
      expect(
        AssetFetcher.fileNameFor(10, 'image/png', 'https://cdn.example/p/a'),
        '010.png',
      );
    });

    test('unknown MIME falls back to the URL extension, then .img', () {
      expect(
        AssetFetcher.fileNameFor(
          1,
          'image/x-exotic',
          'https://cdn.example/a.tiff',
        ),
        '001.tiff',
      );
      expect(
        AssetFetcher.fileNameFor(1, 'image/x-exotic', 'https://cdn.example/a'),
        '001.img',
      );
    });
  });

  group('through the real downloader', () {
    late HttpServer server;
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('webread_mime');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        // JPEG bytes served under a .webp path with a lying content type —
        // all three layers disagree; the magic bytes must win.
        req.response.headers.contentType = ContentType('image', 'webp');
        req.response.add(panelJpeg());
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'JPEG under a .webp URL is stored as .jpg with the true MIME',
      () async {
        final store = FileStore(root);
        final staging = await store.beginEntry(
          collectionId: 's1',
          entryId: 'c1',
        );
        final downloader = AssetFetcher(
          browser: FakeBrowser(),
          // The fixture JPEG is tiny; the size floor is not what is under test.
          config: const SaveConfig(minAssetBytes: 16, downloadRetries: 0),
        );

        final entry = await downloader.download(
          entry: EntryAsset(
            index: 1,
            sourceUrl: 'http://127.0.0.1:${server.port}/img/panel.webp?v=123',
            status: AssetStatus.pending,
          ),
          staging: staging,
          refererUrl: 'http://127.0.0.1:${server.port}/entry/1',
        );

        expect(entry.status, AssetStatus.stored);
        expect(entry.mimeType, 'image/jpeg');
        expect(entry.relativePath, 'assets/001.jpg');
        final file = staging.assetFile('001.jpg');
        expect(file.existsSync(), isTrue);
        // Byte-for-byte original: nothing recompressed the panel.
        expect(await file.readAsBytes(), panelJpeg());
      },
    );

    test('a legacy mismatched-extension file stays readable', () async {
      // A save from before this change: JPEG bytes stored as 001.webp,
      // referenced by the manifest. Nothing renames it; everything that
      // reads through the manifest keeps working.
      final store = FileStore(root);
      final staging = await store.beginEntry(
        collectionId: 's1',
        entryId: 'legacy',
      );
      final legacy = staging.assetFile('001.webp');
      legacy.parent.createSync(recursive: true);
      await legacy.writeAsBytes(panelJpeg());
      final relative = await store.commit(
        staging,
        EntryManifest(
          schemaVersion: EntryManifest.currentSchemaVersion,
          entryId: 'legacy',
          collectionId: 's1',
          sourceUrl: 'https://x.example/1',
          title: 'Legacy',
          savedAt: DateTime(2026, 7, 1),
          status: SaveStatus.complete,
          detectedAssetCount: 1,
          storedAssetCount: 1,
          assets: [
            EntryAsset(
              index: 1,
              sourceUrl: 'https://cdn.example/1.webp',
              status: AssetStatus.stored,
              relativePath: 'assets/001.webp',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      final manifest = (await store.readManifest(relative))!;
      final asset = manifest.storedAssets.single;
      final file = store.assetFile(relative, asset.relativePath!);
      expect(file.existsSync(), isTrue);
      final dims = readImageDimensions(await file.readAsBytes());
      expect(dims, isNotNull, reason: 'decodable regardless of extension');
    });
  });
}

/// A tiny real JPEG (the fixture generator emits PNG; JPEG built here).
List<int> panelJpeg() {
  // Minimal valid JPEG: SOI, APP0/JFIF, minimal tables, 1x1, EOI.
  return _tinyJpeg;
}

// A pre-baked 1x1 white baseline JPEG.
const _tinyJpeg = <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xFF,
  0xDB,
  0x00,
  0x43,
  0x00,
  0x08,
  0x06,
  0x06,
  0x07,
  0x06,
  0x05,
  0x08,
  0x07,
  0x07,
  0x07,
  0x09,
  0x09,
  0x08,
  0x0A,
  0x0C,
  0x14,
  0x0D,
  0x0C,
  0x0B,
  0x0B,
  0x0C,
  0x19,
  0x12,
  0x13,
  0x0F,
  0x14,
  0x1D,
  0x1A,
  0x1F,
  0x1E,
  0x1D,
  0x1A,
  0x1C,
  0x1C,
  0x20,
  0x24,
  0x2E,
  0x27,
  0x20,
  0x22,
  0x2C,
  0x23,
  0x1C,
  0x1C,
  0x28,
  0x37,
  0x29,
  0x2C,
  0x30,
  0x31,
  0x34,
  0x34,
  0x34,
  0x1F,
  0x27,
  0x39,
  0x3D,
  0x38,
  0x32,
  0x3C,
  0x2E,
  0x33,
  0x34,
  0x32,
  0xFF,
  0xC0,
  0x00,
  0x0B,
  0x08,
  0x00,
  0x01,
  0x00,
  0x01,
  0x01,
  0x01,
  0x11,
  0x00,
  0xFF,
  0xC4,
  0x00,
  0x1F,
  0x00,
  0x00,
  0x01,
  0x05,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0xFF,
  0xC4,
  0x00,
  0xB5,
  0x10,
  0x00,
  0x02,
  0x01,
  0x03,
  0x03,
  0x02,
  0x04,
  0x03,
  0x05,
  0x05,
  0x04,
  0x04,
  0x00,
  0x00,
  0x01,
  0x7D,
  0x01,
  0x02,
  0x03,
  0x00,
  0x04,
  0x11,
  0x05,
  0x12,
  0x21,
  0x31,
  0x41,
  0x06,
  0x13,
  0x51,
  0x61,
  0x07,
  0x22,
  0x71,
  0x14,
  0x32,
  0x81,
  0x91,
  0xA1,
  0x08,
  0x23,
  0x42,
  0xB1,
  0xC1,
  0x15,
  0x52,
  0xD1,
  0xF0,
  0x24,
  0x33,
  0x62,
  0x72,
  0x82,
  0x09,
  0x0A,
  0x16,
  0x17,
  0x18,
  0x19,
  0x1A,
  0x25,
  0x26,
  0x27,
  0x28,
  0x29,
  0x2A,
  0x34,
  0x35,
  0x36,
  0x37,
  0x38,
  0x39,
  0x3A,
  0x43,
  0x44,
  0x45,
  0x46,
  0x47,
  0x48,
  0x49,
  0x4A,
  0x53,
  0x54,
  0x55,
  0x56,
  0x57,
  0x58,
  0x59,
  0x5A,
  0x63,
  0x64,
  0x65,
  0x66,
  0x67,
  0x68,
  0x69,
  0x6A,
  0x73,
  0x74,
  0x75,
  0x76,
  0x77,
  0x78,
  0x79,
  0x7A,
  0x83,
  0x84,
  0x85,
  0x86,
  0x87,
  0x88,
  0x89,
  0x8A,
  0x92,
  0x93,
  0x94,
  0x95,
  0x96,
  0x97,
  0x98,
  0x99,
  0x9A,
  0xA2,
  0xA3,
  0xA4,
  0xA5,
  0xA6,
  0xA7,
  0xA8,
  0xA9,
  0xAA,
  0xB2,
  0xB3,
  0xB4,
  0xB5,
  0xB6,
  0xB7,
  0xB8,
  0xB9,
  0xBA,
  0xC2,
  0xC3,
  0xC4,
  0xC5,
  0xC6,
  0xC7,
  0xC8,
  0xC9,
  0xCA,
  0xD2,
  0xD3,
  0xD4,
  0xD5,
  0xD6,
  0xD7,
  0xD8,
  0xD9,
  0xDA,
  0xE1,
  0xE2,
  0xE3,
  0xE4,
  0xE5,
  0xE6,
  0xE7,
  0xE8,
  0xE9,
  0xEA,
  0xF1,
  0xF2,
  0xF3,
  0xF4,
  0xF5,
  0xF6,
  0xF7,
  0xF8,
  0xF9,
  0xFA,
  0xFF,
  0xDA,
  0x00,
  0x08,
  0x01,
  0x01,
  0x00,
  0x00,
  0x3F,
  0x00,
  0xFB,
  0xD0,
  0xFF,
  0xD9,
];
