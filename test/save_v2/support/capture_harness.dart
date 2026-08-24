/// Shared fixtures for the V2 capture lane (E2 · E3 · E5).
///
/// Composes the repository harness the data lane already owns rather than
/// growing a second one, and adds the two things capture needs: a real
/// [FileStore] over a temp directory, and a [PageCaptureSource] that stages
/// bytes without a WebView anywhere near it.
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;

import 'package:web_reader/data/schema.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/page_capture_source.dart';
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/reading_v2/offline_read.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/storage/document.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../../../tool/fixture/fixture_site.dart' show panelPng;
import '../../data/support/repo_harness.dart';

/// A restricted address, built at run time from the policy's own list.
///
/// Deliberately assembled rather than written out: no hostname belongs in this
/// repository, and `test/repository_cleanliness_test.dart` fails the build on
/// one. The policy file is the single authority, so the test asks it.
String restrictedUrl([String path = '/entry/1']) {
  // Interpolated, so the literal source text is not a URL either.
  final host = restrictedCaptureDomains.first;
  return 'https://$host$path';
}

class CaptureHarness {
  /// [executor] is for the one test that has to prove a preference survives
  /// the database being closed and opened again: pointing two harnesses at the
  /// same file is the only honest way to write it. Everything else gets the
  /// in-memory default.
  CaptureHarness({QueryExecutor? executor}) {
    repos = RepoHarness(executor: executor);
    root = Directory.systemTemp.createTempSync('scrollary_v2_capture');
    fileStore = FileStore(root);
    Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
    Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
    queue = SaveQueueRepository(repos.db, now: repos.tick);
    preferences = CapturePreferenceStore(LocalSettingsStore(repos.db));
  }

  late final RepoHarness repos;
  late final Directory root;
  late final FileStore fileStore;
  late final SaveQueueRepository queue;

  /// What each Collection is normally captured as — the real store, over this
  /// harness's own database.
  late final CapturePreferenceStore preferences;

  LibraryDatabase get db => repos.db;

  EntryCaptureService captureWith(PageCaptureSource source) =>
      EntryCaptureService(
        entries: repos.entries,
        collections: repos.collections,
        offlineCopies: repos.offline,
        fileStore: fileStore,
        source: source,
        capturePreferences: preferences,
        now: repos.tick,
      );

  OfflineReadSession sessionFor(String entryId) => OfflineReadSession(
    entryId: entryId,
    offlineCopies: repos.offline,
    reading: repos.reading,
  );

  Future<OfflineRead> read(String entryId) => resolveOfflineRead(
    entryId: entryId,
    offlineCopies: repos.offline,
    fileStore: fileStore,
  );

  /// Committed entry directories on disk, relative to the store root.
  List<String> committedPaths() => fileStore.listCommittedEntryPaths();

  /// Anything left in staging. Every refusal and every failure must leave this
  /// empty: a discarded capture takes its temp tree with it.
  List<String> stagingLeftovers() {
    final tmp = Directory('${root.path}/${FileStore.tmpFolderName}');
    if (!tmp.existsSync()) return const [];
    return [for (final e in tmp.listSync()) e.path.split('/').last];
  }

  Future<void> close() async {
    await repos.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// A [PageCaptureSource] that stages real bytes and returns a scripted result.
///
/// Everything a genuine implementation does to a *page* is out of scope here
/// by construction — this one never navigates, scrolls or measures. What it
/// exercises is exactly the half the pipeline owns: staging in, manifest,
/// commit, OfflineCopy out.
class FakePageCaptureSource implements PageCaptureSource {
  FakePageCaptureSource.images({
    this.pageCount = 2,
    this.status = SaveStatus.complete,
    this.landedUrl,
    this.title = 'Part 101',
    this.dimensionsVerified = true,
  }) : _kind = _Kind.images,
       _failure = null,
       hintAlsoFails = false;

  FakePageCaptureSource.document({
    this.status = SaveStatus.complete,
    this.landedUrl,
    this.title = 'Part 101',
  }) : _kind = _Kind.document,
       pageCount = 0,
       dimensionsVerified = true,
       hintAlsoFails = false,
       _failure = null;

  /// The page could not be read. Nothing is staged.
  FakePageCaptureSource.failing(String failure)
    : _kind = _Kind.failed,
      _failure = failure,
      pageCount = 0,
      status = SaveStatus.failed,
      landedUrl = null,
      title = '',
      hintAlsoFails = false,
      dimensionsVerified = true;

  /// Image extraction found too little, exactly as the engine reports a page
  /// whose panels it could not pick out. Given a reader-area rule it stages
  /// [pageCount] images instead — unless [hintAlsoFails], which is how a rule
  /// that matches nothing on this page looks from here.
  FakePageCaptureSource.needingReaderAreaAssist({
    this.pageCount = 2,
    this.hintAlsoFails = false,
    this.title = 'Part 101',
  }) : _kind = _Kind.needsAssist,
       _failure = 'Only 0 content images found (need 3)',
       status = SaveStatus.complete,
       landedUrl = null,
       dimensionsVerified = true;

  /// The implementation's own landed-URL boundary refused. This is the shape a
  /// real one reports a redirect onto a restricted service in.
  FakePageCaptureSource.refusing()
    : _kind = _Kind.refused,
      _failure = null,
      pageCount = 0,
      status = SaveStatus.failed,
      landedUrl = null,
      title = '',
      hintAlsoFails = false,
      dimensionsVerified = true;

  final _Kind _kind;
  final String? _failure;
  final int pageCount;
  final SaveStatus status;

  /// Where the capture ended up, when that is not where it aimed.
  final String? landedUrl;
  final String title;
  final bool dimensionsVerified;

  /// A reader-area rule that still matches nothing, which is the other half of
  /// what `needsReaderAreaAssist` covers.
  final bool hintAlsoFails;

  /// Every URL this source was asked for, in order.
  final List<String> requested = <String>[];

  /// What [PageCaptureSource.capturePage] was told to produce, in order.
  final List<CaptureMode?> modes = <CaptureMode?>[];

  /// The rules handed to each capture, in order. Null is a capture that ran
  /// with no rule at all.
  final List<UserPageHint?> readerHints = <UserPageHint?>[];
  final List<UserPageHint?> nextHints = <UserPageHint?>[];

  /// Whether each capture was told the page was already open — the sequential
  /// journey's promise that it is not asking the site for the same page twice.
  final List<bool> reusedLoadedPage = <bool>[];

  @override
  Future<PageCaptureOutcome> capturePage({
    required String url,
    required StagingHandle staging,
    required CaptureMode? requestedMode,
    required bool Function() shouldContinue,
    UserPageHint? readerHint,
    UserPageHint? nextHint,
    bool pageAlreadyLoaded = false,
  }) async {
    requested.add(url);
    modes.add(requestedMode);
    readerHints.add(readerHint);
    nextHints.add(nextHint);
    reusedLoadedPage.add(pageAlreadyLoaded);
    final landed = landedUrl ?? url;

    switch (_kind) {
      case _Kind.failed:
        return PageCaptureOutcome.failed(pageUrl: landed, error: _failure);
      case _Kind.refused:
        return PageCaptureOutcome.refused(pageUrl: landed);
      case _Kind.needsAssist:
        if (readerHint == null || hintAlsoFails) {
          return PageCaptureOutcome.failed(
            pageUrl: landed,
            error: readerHint == null
                ? _failure
                : 'saved reader-area rule no longer matches',
            needsReaderAreaAssist: true,
          );
        }
        return _stageImages(staging, landed);
      case _Kind.images:
        return _stageImages(staging, landed);
      case _Kind.document:
        return _stageDocument(staging, landed);
    }
  }

  Future<PageCaptureOutcome> _stageImages(
    StagingHandle staging,
    String landed,
  ) async {
    final assets = <EntryAsset>[];
    for (var i = 1; i <= pageCount; i++) {
      final name = '${i.toString().padLeft(3, '0')}.png';
      final bytes = panelPng(entry: 1, index: i, width: 40, height: 60);
      staging.assetFile(name).writeAsBytesSync(bytes);
      assets.add(
        EntryAsset(
          index: i,
          sourceUrl: '$landed/img/$i.png',
          status: AssetStatus.stored,
          relativePath: StagingHandle.assetRelativePath(name),
          mimeType: 'image/png',
          byteSize: bytes.length,
          width: 40,
          height: 60,
          dimensionsVerified: dimensionsVerified,
        ),
      );
    }
    return PageCaptureOutcome.captured(
      pageUrl: landed,
      title: title,
      artifact: ArtifactFormat.imageSequence,
      captureMode: CaptureMode.imageSequence,
      status: status,
      detectedAssetCount: pageCount,
      storedAssetCount: pageCount,
      assets: assets,
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
    );
  }

  Future<PageCaptureOutcome> _stageDocument(
    StagingHandle staging,
    String landed,
  ) async {
    const document = StructuredDocument(
      schemaVersion: StructuredDocument.currentSchemaVersion,
      title: 'Part 101',
      sourceUrl: 'https://reading.example.com/serial-alpha/part-101',
      blocks: [
        DocumentBlock(
          index: 0,
          type: DocumentBlockType.heading,
          text: 'Part 101',
          level: 1,
        ),
        DocumentBlock(
          index: 1,
          type: DocumentBlockType.paragraph,
          text: 'The first paragraph of the saved text.',
        ),
        DocumentBlock(
          index: 2,
          type: DocumentBlockType.paragraph,
          text: 'The second paragraph, which is where the reader stopped.',
        ),
      ],
    );
    staging.documentFile.writeAsStringSync(document.encode());
    return PageCaptureOutcome.captured(
      pageUrl: landed,
      title: title,
      artifact: ArtifactFormat.structuredDocument,
      captureMode: CaptureMode.textOnly,
      status: status,
      detectedAssetCount: 0,
      storedAssetCount: 0,
      assets: const [],
      document: documentRefFor(document),
      contentKind: 'article',
      contentKindConfidence: 'high',
    );
  }
}

enum _Kind { images, document, failed, refused, needsAssist }
