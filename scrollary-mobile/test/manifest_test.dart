import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/storage/manifest.dart';

void main() {
  EntryManifest sample() => EntryManifest(
    schemaVersion: EntryManifest.currentSchemaVersion,
    entryId: 'entry-1',
    collectionId: 'item-1',
    sourceUrl: 'https://x.example/entry/1',
    canonicalUrl: 'https://x.example/entry/1',
    title: 'Entry 1',
    savedAt: DateTime.utc(2026, 7, 25, 12, 30),
    status: SaveStatus.partial,
    statusReason: 'assetsFailed:1',
    detectedAssetCount: 3,
    storedAssetCount: 2,
    nextUrl: 'https://x.example/entry/2',
    entryOrder: 1,
    assets: const [
      EntryAsset(
        index: 1,
        sourceUrl: 'https://x.example/img/1.png',
        status: AssetStatus.stored,
        relativePath: 'assets/001.png',
        mimeType: 'image/png',
        byteSize: 5661,
        width: 800,
        height: 1200,
      ),
      EntryAsset(
        index: 2,
        sourceUrl: 'https://x.example/img/2.png',
        status: AssetStatus.failed,
        error: 'HTTP 503',
      ),
      EntryAsset(
        index: 3,
        sourceUrl: 'https://x.example/img/3.png',
        status: AssetStatus.stored,
        relativePath: 'assets/003.png',
        mimeType: 'image/png',
        byteSize: 4200,
      ),
    ],
  );

  test('round-trips through JSON without losing anything', () {
    final original = sample();
    final restored = EntryManifest.decode(original.encode());

    expect(restored.schemaVersion, original.schemaVersion);
    expect(restored.entryId, original.entryId);
    expect(restored.collectionId, original.collectionId);
    expect(restored.sourceUrl, original.sourceUrl);
    expect(restored.canonicalUrl, original.canonicalUrl);
    expect(restored.title, original.title);
    expect(restored.savedAt.toUtc(), original.savedAt.toUtc());
    expect(restored.status, SaveStatus.partial);
    expect(restored.statusReason, 'assetsFailed:1');
    expect(restored.detectedAssetCount, 3);
    expect(restored.storedAssetCount, 2);
    expect(restored.nextUrl, original.nextUrl);
    expect(restored.entryOrder, 1);
    expect(restored.assets, hasLength(3));
  });

  test('preserves asset order and per-asset failure detail', () {
    final restored = EntryManifest.decode(sample().encode());

    expect(restored.assets.map((a) => a.index), [1, 2, 3]);
    expect(restored.assets[1].status, AssetStatus.failed);
    expect(restored.assets[1].error, 'HTTP 503');
    expect(restored.assets[1].relativePath, isNull);
  });

  test('storedAssets exposes only what is actually on disk, in order', () {
    final restored = EntryManifest.decode(sample().encode());

    expect(restored.storedAssets.map((a) => a.relativePath), [
      'assets/001.png',
      'assets/003.png',
    ]);
  });

  test('asset paths are relative — never absolute container paths', () {
    final restored = EntryManifest.decode(sample().encode());

    for (final asset in restored.storedAssets) {
      expect(asset.relativePath, isNot(startsWith('/')));
      expect(asset.relativePath, startsWith('assets/'));
    }
  });

  test('an unknown status decodes to failed rather than throwing', () {
    expect(saveStatusFromName('nonsense'), SaveStatus.failed);
    expect(assetStatusFromName(null), AssetStatus.failed);
  });

  test('copyWith promotes status without disturbing identity', () {
    final updated = sample().copyWith(
      status: SaveStatus.complete,
      storedAssetCount: 3,
    );

    expect(updated.status, SaveStatus.complete);
    expect(updated.storedAssetCount, 3);
    expect(updated.entryId, 'entry-1');
    expect(updated.entryOrder, 1);
  });
}
