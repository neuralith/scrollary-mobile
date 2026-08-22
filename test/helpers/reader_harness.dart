/// Opening the real reader over a real package, the way the app opens it.
///
/// The reader takes an [OfflineReaderData]: the package this device holds and
/// the session its reading goes back through. So a reader test needs three
/// real things and nothing else — a V2 library with an Entry in it, a
/// committed package under a [FileStore], and the OfflineCopy row that ties
/// them together. This harness builds those, and hands back exactly what the
/// route hands the screen.
///
/// Deliberately no widget scaffolding: how a suite pumps the reader is its
/// own business (a bare `MaterialApp`, or a router when the test is about
/// leaving it), and hiding that here would make the one thing several of
/// these suites are actually about invisible.
library;

import 'dart:io';

import 'package:web_reader/data/schema.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../../tool/fixture/fixture_site.dart' show panelPng;
import '../data/support/repo_harness.dart';

class ReaderHarness {
  ReaderHarness() {
    repos = RepoHarness();
    root = Directory.systemTemp.createTempSync('scrollary_reader');
    fileStore = FileStore(root);
    Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
    Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
  }

  late final RepoHarness repos;
  late final Directory root;
  late final FileStore fileStore;

  LibraryDatabase get db => repos.db;

  String? _collectionId;

  /// The Collection every seeded Entry joins. Created once, lazily, because a
  /// test that only ever opens one Entry should not have to know about it.
  Future<String> collectionId() async {
    final existing = _collectionId;
    if (existing != null) return existing;
    return _collectionId = (await repos.seedLibrary()).collection.id;
  }

  /// An Entry in the seeded Collection, with a Location to save from.
  Future<String> seedEntry({
    required String title,
    double ordinal = 101,
  }) async {
    final collection = await collectionId();
    final (entry, violation) = await repos.entries.createInCollection(
      collectionId: collection,
      ordinal: ordinal,
      title: title,
    );
    if (violation != null) throw StateError('seed entry: ${violation.message}');
    return entry!.id;
  }

  /// A tall image package for [entryId], committed and recorded as this
  /// device's active copy.
  Future<String> seedImages({
    required String entryId,
    int pages = 12,
    String title = 'Part 101',
    String sourceMarker = 'Entry 1',
    SaveStatus status = SaveStatus.complete,
    int detectedAssetCount = 0,
    bool dimensionsVerified = true,
    int? anchorIndex,
    double? anchorOffset,
  }) async {
    final collection = await collectionId();
    final staging = await fileStore.beginEntry(
      collectionId: collection,
      entryId: entryId,
    );
    final assets = <EntryAsset>[];
    for (var i = 1; i <= pages; i++) {
      final name = '${i.toString().padLeft(3, '0')}.png';
      await staging.assetFile(name).writeAsBytes(panelPng(entry: 1, index: i));
      assets.add(
        EntryAsset(
          index: i,
          sourceUrl: 'https://reading.example.com/img/$i.png',
          status: AssetStatus.stored,
          relativePath: StagingHandle.assetRelativePath(name),
          mimeType: 'image/png',
          width: 800,
          height: 1200,
          dimensionsVerified: dimensionsVerified,
        ),
      );
    }
    return _commit(
      entryId: entryId,
      staging: staging,
      manifest: EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: entryId,
        collectionId: collection,
        sourceUrl: 'https://reading.example.com/serial-alpha/part-101',
        title: title,
        sourceMarker: sourceMarker,
        savedAt: DateTime(2026, 7, 20),
        status: status,
        detectedAssetCount: detectedAssetCount == 0
            ? pages
            : detectedAssetCount,
        storedAssetCount: pages,
        assets: assets,
      ),
      artifact: ArtifactFormat.imageSequence,
      anchorIndex: anchorIndex,
      anchorOffset: anchorOffset,
    );
  }

  /// A structured-document package for [entryId].
  Future<String> seedDocument({
    required String entryId,
    required StructuredDocument document,
    String title = 'The Saved Page',
    String sourceMarker = 'Entry 1',
    SaveStatus status = SaveStatus.complete,
    int detectedAssetCount = 0,
    int storedAssetCount = 0,
    List<EntryAsset> assets = const [],
    String? body,
    int? anchorIndex,
    double? anchorOffset,
  }) async {
    final collection = await collectionId();
    final staging = await fileStore.beginEntry(
      collectionId: collection,
      entryId: entryId,
    );
    await staging.documentFile.writeAsString(body ?? document.encode());
    for (final asset in assets) {
      final path = asset.relativePath;
      if (path == null || asset.status != AssetStatus.stored) continue;
      await staging
          .assetFile(path.split('/').last)
          .writeAsBytes(panelPng(entry: 1, index: asset.index));
    }
    return _commit(
      entryId: entryId,
      staging: staging,
      manifest: EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        artifact: ArtifactFormat.structuredDocument,
        document: DocumentRef(
          relativePath: FileStore.documentFileName,
          blockCount: document.blockCount,
          textLength: document.textLength,
        ),
        entryId: entryId,
        collectionId: collection,
        sourceUrl: 'https://reading.example.com/serial-alpha/part-101',
        title: title,
        sourceMarker: sourceMarker,
        savedAt: DateTime(2026, 7, 20),
        status: status,
        detectedAssetCount: detectedAssetCount,
        storedAssetCount: storedAssetCount,
        assets: assets,
      ),
      artifact: ArtifactFormat.structuredDocument,
      anchorIndex: anchorIndex,
      anchorOffset: anchorOffset,
    );
  }

  Future<String> _commit({
    required String entryId,
    required StagingHandle staging,
    required EntryManifest manifest,
    required ArtifactFormat artifact,
    int? anchorIndex,
    double? anchorOffset,
  }) async {
    final relative = await fileStore.commit(staging, manifest);
    await repos.offline.recordCopy(
      entryId: entryId,
      locationUrl: manifest.sourceUrl,
      artifactFormat: artifact.name,
      contentPath: relative,
      byteSize: await fileStore.entryByteSize(relative),
    );
    if (anchorIndex != null || anchorOffset != null) {
      await repos.offline.saveAnchor(
        entryId,
        anchorIndex: anchorIndex ?? 0,
        anchorOffset: anchorOffset ?? 0,
      );
    }
    return relative;
  }

  /// Exactly what `V2ReaderRoute` hands `ReaderScreen`.
  Future<OfflineReaderData> open(String entryId) => openOfflineRead(
    entryId: entryId,
    offlineCopies: repos.offline,
    reading: repos.reading,
    fileStore: fileStore,
  );

  /// Delete the bytes and leave the copy row pointing at them — the
  /// "files are gone" state.
  Future<void> deletePackage(String relativePath) =>
      fileStore.deleteEntryContent(relativePath);

  Future<void> close() async {
    await repos.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
