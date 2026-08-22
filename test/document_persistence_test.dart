import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

/// Storage-side guarantees for the two artifacts.
///
/// The load-bearing one is **backward compatibility**: a schema-1 manifest was
/// written before documents existed, and every one of them describes an image
/// sequence. Reading those unchanged is what "existing entries keep working"
/// actually means, and it is asserted here against literal JSON rather than
/// against something this build wrote.
void main() {
  late Directory root;
  late FileStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('webread_doc_test');
    Directory('${root.path}/library').createSync(recursive: true);
    Directory('${root.path}/tmp').createSync(recursive: true);
    store = FileStore(root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  StructuredDocument sampleDocument() => const StructuredDocument(
    schemaVersion: StructuredDocument.currentSchemaVersion,
    title: 'A saved page',
    sourceUrl: 'https://example.com/text/1',
    blocks: [
      DocumentBlock(
        index: 0,
        type: DocumentBlockType.heading,
        text: 'A saved page',
        level: 1,
      ),
      DocumentBlock(
        index: 1,
        type: DocumentBlockType.paragraph,
        text: 'First paragraph.',
      ),
      DocumentBlock(
        index: 2,
        type: DocumentBlockType.image,
        assetIndex: 1,
        imageSourceUrl: 'https://example.com/a.png',
        alt: 'A figure',
      ),
      DocumentBlock(
        index: 3,
        type: DocumentBlockType.paragraph,
        text: 'Second paragraph.',
      ),
    ],
  );

  group('manifest versioning', () {
    /// Exactly what a pre-document build wrote: no `artifact`, no
    /// `captureMode`, no `document`.
    const schemaOneJson = '''
{
  "schemaVersion": 1,
  "entryId": "entry-1",
  "collectionId": "collection-1",
  "sourceUrl": "https://example.com/item/1",
  "title": "An older entry",
  "savedAt": "2026-01-01T00:00:00.000Z",
  "status": "complete",
  "detectedAssetCount": 2,
  "storedAssetCount": 2,
  "entryOrder": 1,
  "contentKind": "imageDominant",
  "contentKindConfidence": "high",
  "assets": [
    {"index": 1, "sourceUrl": "https://example.com/1.png", "status": "stored",
     "relativePath": "assets/001.png", "mimeType": "image/png",
     "width": 800, "height": 1200, "dimensionsVerified": true},
    {"index": 2, "sourceUrl": "https://example.com/2.png", "status": "stored",
     "relativePath": "assets/002.png", "mimeType": "image/png",
     "width": 800, "height": 1200, "dimensionsVerified": true}
  ]
}
''';

    test('a schema-1 manifest reads as an image sequence', () {
      final manifest = EntryManifest.decode(schemaOneJson);
      expect(manifest.schemaVersion, 1);
      expect(manifest.artifact, ArtifactFormat.imageSequence);
      expect(manifest.isImageSequence, isTrue);
      expect(manifest.isDocument, isFalse);
      expect(manifest.document, isNull);
      // And it still resolves to the mode that produced it, so the details
      // sheet has something honest to show for an entry saved long ago.
      expect(manifest.captureMode, CaptureMode.imageSequence.name);
    });

    test('a schema-1 manifest keeps every field it carried', () {
      final manifest = EntryManifest.decode(schemaOneJson);
      expect(manifest.entryId, 'entry-1');
      expect(manifest.collectionId, 'collection-1');
      expect(manifest.storedAssets, hasLength(2));
      expect(manifest.storedAssets.first.relativePath, 'assets/001.png');
      expect(manifest.contentKind, 'imageDominant');
      expect(manifest.pageCount, 2);
    });

    test('this build writes schema 2 with an explicit artifact', () {
      final manifest = EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.imageSequence,
        captureMode: CaptureMode.imageSequence.name,
        entryId: 'e',
        sourceUrl: 'https://example.com/a',
        title: 'T',
        savedAt: DateTime.utc(2026),
        status: SaveStatus.complete,
        detectedAssetCount: 0,
        storedAssetCount: 0,
        assets: const [],
      );
      expect(EntryManifest.currentSchemaVersion, 2);
      final json = jsonDecode(manifest.encode()) as Map<String, dynamic>;
      expect(json['schemaVersion'], 2);
      expect(json['artifact'], 'imageSequence');
    });

    test('a document manifest round-trips its reference and mode', () {
      final manifest = EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.structuredDocument,
        captureMode: CaptureMode.textAndImages.name,
        captureModeIsUserSet: true,
        document: const DocumentRef(
          relativePath: 'document.json',
          blockCount: 4,
          textLength: 512,
        ),
        entryId: 'e',
        sourceUrl: 'https://example.com/a',
        title: 'T',
        savedAt: DateTime.utc(2026),
        status: SaveStatus.complete,
        detectedAssetCount: 1,
        storedAssetCount: 1,
        assets: const [],
      );
      final decoded = EntryManifest.decode(manifest.encode());
      expect(decoded.artifact, ArtifactFormat.structuredDocument);
      expect(decoded.isDocument, isTrue);
      expect(decoded.captureMode, 'textAndImages');
      expect(decoded.captureModeIsUserSet, isTrue);
      expect(decoded.document!.blockCount, 4);
      expect(decoded.document!.textLength, 512);
      expect(decoded.document!.relativePath, 'document.json');
    });

    test(
      'an artifact from a newer build reads as unknown, not as an image',
      () {
        final json = jsonDecode(schemaOneJson) as Map<String, dynamic>
          ..['schemaVersion'] = 9
          ..['artifact'] = 'somethingFromTheFuture';
        final manifest = EntryManifest.fromJson(json);
        expect(manifest.artifact, ArtifactFormat.unknown);
        expect(manifest.artifact.isReadable, isFalse);
        // Crucially NOT imageSequence: misreading it would show the reader a
        // package it does not understand and call the result an entry.
        expect(manifest.isImageSequence, isFalse);
      },
    );
  });

  group('document packages on disk', () {
    Future<String> commitDocumentEntry({
      String entryId = 'entry-doc',
      String? collectionId = 'collection-1',
      SaveStatus status = SaveStatus.complete,
    }) async {
      final staging = await store.beginEntry(
        collectionId: collectionId,
        entryId: entryId,
      );
      await staging.documentFile.writeAsString(sampleDocument().encode());
      await staging.assetFile('001.png').writeAsBytes(List.filled(64, 7));
      return store.commit(
        staging,
        EntryManifest(
          schemaVersion: EntryManifest.currentSchemaVersion,
          artifact: ArtifactFormat.structuredDocument,
          captureMode: CaptureMode.textAndImages.name,
          document: const DocumentRef(
            relativePath: FileStore.documentFileName,
            blockCount: 4,
            textLength: 42,
          ),
          entryId: entryId,
          collectionId: collectionId,
          sourceUrl: 'https://example.com/text/1',
          title: 'A saved page',
          savedAt: DateTime.utc(2026),
          status: status,
          detectedAssetCount: 1,
          storedAssetCount: 1,
          assets: const [
            EntryAsset(
              index: 1,
              sourceUrl: 'https://example.com/a.png',
              status: AssetStatus.stored,
              relativePath: 'assets/001.png',
              mimeType: 'image/png',
            ),
          ],
        ),
      );
    }

    test('the document lands beside the manifest and the assets', () async {
      final relative = await commitDocumentEntry();
      expect(
        File('${store.resolve(relative)}/manifest.json').existsSync(),
        isTrue,
      );
      expect(
        File('${store.resolve(relative)}/document.json').existsSync(),
        isTrue,
      );
      expect(
        File('${store.resolve(relative)}/assets/001.png').existsSync(),
        isTrue,
      );
    });

    test('the document reads back with its blocks in order', () async {
      final relative = await commitDocumentEntry();
      final document = await store.readDocument(relative);
      expect(document, isNotNull);
      expect(document!.blockCount, 4);
      expect(document.blocks[0].type, DocumentBlockType.heading);
      expect(document.blocks[2].isImage, isTrue);
      expect(document.blocks[2].assetIndex, 1);
      expect(document.textLength, greaterThan(0));
    });

    test('a manifest image block resolves to its stored asset', () async {
      final relative = await commitDocumentEntry();
      final manifest = await store.readManifest(relative);
      final document = await store.readDocument(relative);
      final imageBlock = document!.blocks.firstWhere((b) => b.isImage);
      final asset = manifest!.assetByIndex(imageBlock.assetIndex!);
      expect(asset, isNotNull);
      expect(asset!.relativePath, 'assets/001.png');
    });

    test('a corrupt document reads as null, never as an exception', () async {
      final relative = await commitDocumentEntry();
      File(
        '${store.resolve(relative)}/document.json',
      ).writeAsStringSync('{ not json');
      expect(await store.readDocument(relative), isNull);
    });

    test('a missing document reads as null', () async {
      final relative = await commitDocumentEntry();
      File('${store.resolve(relative)}/document.json').deleteSync();
      expect(await store.readDocument(relative), isNull);
    });

    test('a standalone document entry is committed and found', () async {
      final relative = await commitDocumentEntry(
        entryId: 'standalone-doc',
        collectionId: null,
      );
      expect(relative, contains('standalone'));
      // The recovery walk must see it. Missing this was why a standalone
      // entry's files could never be reconciled from their own manifest.
      expect(store.listCommittedEntryPaths(), contains(relative));
    });

    test('replacement keeps the old copy until the new one lands', () async {
      final relative = await commitDocumentEntry();
      final before = await store.readDocument(relative);
      expect(before!.blockCount, 4);

      final staging = await store.beginEntry(
        collectionId: 'collection-1',
        entryId: 'entry-doc',
      );
      await staging.documentFile.writeAsString(
        const StructuredDocument(
          schemaVersion: 1,
          title: 'Replaced',
          sourceUrl: 'https://example.com/text/1',
          blocks: [
            DocumentBlock(
              index: 0,
              type: DocumentBlockType.paragraph,
              text: 'Only one block now.',
            ),
          ],
        ).encode(),
      );
      await store.commitReplacing(
        staging,
        EntryManifest(
          schemaVersion: EntryManifest.currentSchemaVersion,
          artifact: ArtifactFormat.structuredDocument,
          captureMode: CaptureMode.textOnly.name,
          document: const DocumentRef(
            relativePath: FileStore.documentFileName,
            blockCount: 1,
            textLength: 19,
          ),
          entryId: 'entry-doc',
          collectionId: 'collection-1',
          sourceUrl: 'https://example.com/text/1',
          title: 'Replaced',
          savedAt: DateTime.utc(2026, 2),
          status: SaveStatus.complete,
          detectedAssetCount: 0,
          storedAssetCount: 0,
          assets: const [],
        ),
      );

      final after = await store.readDocument(relative);
      expect(after!.blockCount, 1);
      // No `.previous` left behind once the replacement succeeded.
      expect(
        Directory('${store.resolve(relative)}.previous').existsSync(),
        isFalse,
      );
      // Text-only really means no assets survived the replacement.
      expect(
        Directory('${store.resolve(relative)}/assets').listSync(),
        isEmpty,
      );
    });

    test(
      'an interrupted replacement is restored, including a standalone',
      () async {
        final relative = await commitDocumentEntry(
          entryId: 'standalone-doc',
          collectionId: null,
        );
        final target = Directory(store.resolve(relative));
        // Simulate a kill between "step the old entry aside" and "move the new
        // one in": the backup exists and the original does not.
        target.renameSync('${target.path}.previous');
        expect(target.existsSync(), isFalse);

        final restored = await store.restoreInterruptedReplacements();
        expect(restored, 1);
        expect(target.existsSync(), isTrue);
        expect((await store.readDocument(relative))!.blockCount, 4);
      },
    );
  });

  /// Where the stored capture-mode name lives now: the save-queue row, which
  /// is what `queue_repository.dart` reads it back through.
  test('an unreadable stored preference means "detect", not a substitute', () {
    expect(captureModeFromName('somethingRemoved'), isNull);
  });
}
