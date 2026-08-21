import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';
import '../tool/fixture/fixture_site.dart';

/// Disk-space policy: preflight floor, rolling per-entry check, the
/// both-copies replacement check, distinct error class, and the platform
/// channel itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceStorage channel', () {
    const channel = MethodChannel('webread/device_storage');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('freeBytes returns the platform value', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'freeBytes');
            return 1234567890;
          });
      expect(await DeviceStorage().freeBytes(), 1234567890);
    });

    test('freeBytes degrades to null on channel errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'nope');
          });
      expect(await DeviceStorage().freeBytes(), isNull);
    });

    test('excludeFromBackup passes the path and returns the result', () async {
      String? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'excludeFromBackup');
            received = (call.arguments as Map)['path'] as String;
            return true;
          });
      expect(await DeviceStorage().excludeFromBackup('/x/webread'), isTrue);
      expect(received, '/x/webread');
    });

    test('excludeFromBackup degrades to false when unsupported', () async {
      // No handler installed: MissingPluginException path (Android today).
      expect(await DeviceStorage().excludeFromBackup('/x'), isFalse);
    });
  });

  group('save run policy', () {
    late AppDatabase db;
    late Directory root;
    late FileStore store;
    late FakeBrowser browser;
    late HttpServer server;
    late String assetBase;

    const host = 'https://x.example';
    String entryUrl(int n) => '$host/guide/foo/$n';

    const config = SaveConfig(
      scrollDelay: Duration.zero,
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollIterations: 2,
      maxScrollPasses: 1,
      domReadyTimeout: Duration(seconds: 2),
      maxAssetWait: Duration(seconds: 2),
      downloadRetries: 0,
      cooldownBetweenEntries: Duration.zero,
      maxEntriesPerRun: 10,
    );

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      assetBase = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final match = RegExp(
          r'^/img/(\d+)/(\d+)\.png$',
        ).firstMatch(req.uri.path);
        if (match == null) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(
          panelPng(
            entry: int.parse(match.group(1)!),
            index: int.parse(match.group(2)!),
          ),
        );
        await req.response.close();
      });
    });
    tearDownAll(() => server.close(force: true));

    setUp(() {
      // The widgets binding (needed by the channel group above) installs an
      // HttpOverrides that 400s everything; these tests download from a real
      // local server.
      HttpOverrides.global = null;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_disk');
      store = FileStore(root);
      Directory(
        p.join(root.path, FileStore.libraryFolderName),
      ).createSync(recursive: true);
      Directory(
        p.join(root.path, FileStore.tmpFolderName),
      ).createSync(recursive: true);
      browser = FakeBrowser();
    });
    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    void servePages(int count) {
      for (var n = 1; n <= count; n++) {
        browser.addPage(
          entryUrl(n),
          entryProbe(
            url: entryUrl(n),
            title: 'Foo Entry $n',
            imageUrls: [
              for (var i = 1; i <= 3; i++) '$assetBase/img/$n/$i.png',
            ],
            nextHref: n < count ? entryUrl(n + 1) : null,
          ),
        );
      }
    }

    test('the rolling check stops mid-run and keeps what is stored', () async {
      servePages(4);
      browser.setUrl(entryUrl(1));
      // Plenty of space for entry 1, below the reserve afterwards.
      final storage = _ScriptedStorage([
        4 * 1024 * 1024 * 1024, // preflight
        4 * 1024 * 1024 * 1024, // before entry 1
        100 * 1024 * 1024, // before entry 2 -> stop
      ]);
      final run = SaveRunController(
        browser: browser,
        db: db,
        fileStore: store,
        config: config,
        deviceStorage: storage,
      );

      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 4,
        startUrl: entryUrl(1),
      );

      expect(
        (await db.allEntries()).length,
        1,
        reason: 'entry 1 landed before space ran out, and is kept',
      );
      expect(run.progress.lastError, 'insufficientStorage');
      expect(run.progress.message, contains('not enough disk space'));
      // Staging left nothing behind.
      final tmp = Directory(p.join(root.path, FileStore.tmpFolderName));
      expect(tmp.listSync(), isEmpty);
    });

    test('replacement is refused when both copies cannot fit', () async {
      servePages(1);
      browser.setUrl(entryUrl(1));

      // First: save normally with generous space.
      final first = SaveRunController(
        browser: browser,
        db: db,
        fileStore: store,
        config: config,
        deviceStorage: _ScriptedStorage([for (var i = 0; i < 9; i++) 1 << 40]),
      );
      await first.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: entryUrl(1),
      );
      final entry = (await db.allEntries()).single;
      final contentDir = Directory(store.resolve(entry.contentPath!));
      final filesBefore = contentDir
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      expect(filesBefore, greaterThan(0));

      // Give the existing entry a huge recorded size, then re-save with
      // free space that cannot hold two of it plus the reserve.
      await db.upsertEntry(entry.copyWith(byteSize: 2 * 1024 * 1024 * 1024));
      final second = SaveRunController(
        browser: browser,
        db: db,
        fileStore: store,
        config: config,
        deviceStorage: _ScriptedStorage([
          1 * 1024 * 1024 * 1024, // preflight: above the floor
          1 * 1024 * 1024 * 1024, // rolling: above reserve + estimate
          // replacement check reads the same value
          1 * 1024 * 1024 * 1024,
        ]),
      );
      await second.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: entryUrl(1),
        policy: DuplicatePolicy.replaceAll,
      );

      expect(second.progress.lastError, 'insufficientStorage');
      final filesAfter = contentDir
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      expect(
        filesAfter,
        filesBefore,
        reason: 'the readable copy was never touched',
      );
    });

    test('a disk stop with zero stored reports failed, not complete', () async {
      servePages(2);
      browser.setUrl(entryUrl(1));
      final run = SaveRunController(
        browser: browser,
        db: db,
        fileStore: store,
        config: config,
        deviceStorage: _ScriptedStorage([
          4 * 1024 * 1024 * 1024, // preflight passes
          100 * 1024 * 1024, // first rolling check already too low
        ]),
      );
      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 2,
        startUrl: entryUrl(1),
      );

      expect(run.progress.state.name, 'failed');
      expect(run.progress.lastError, 'insufficientStorage');
      expect(await db.allEntries(), isEmpty);
    });
  });
}

/// Returns scripted values in order; repeats the last one when exhausted.
class _ScriptedStorage extends DeviceStorage {
  _ScriptedStorage(this.values);
  final List<int> values;
  var _i = 0;

  @override
  Future<int?> freeBytes() async =>
      values[_i < values.length ? _i++ : values.length - 1];

  @override
  Future<bool> excludeFromBackup(String absolutePath) async => true;
}
