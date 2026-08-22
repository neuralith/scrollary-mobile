/// A device that ran an older build, launching this one.
///
/// There is **no migration** (V2-D26): nothing shipped, so V2 was designed
/// from the domain and development databases are reset by hand. What that
/// leaves on a developer's or a tester's device is a V1 database file sitting
/// beside the V2 one, and possibly a V1 asset tree under the same store root.
///
/// The rule this file pins down is *ignore it, and do not crash*:
///
/// 1. **The two databases are different files.** V1's was `webread`; V2's is
///    `scrollary_library`. Opening one has never had anything to do with the
///    other, so a stale file is simply never read.
/// 2. **Nothing in `lib/` can open it.** The class that did is deleted, and
///    the guard here is the same kind the palette and cleanliness suites use:
///    a scan of the source, so a reintroduction fails the build rather than
///    surfacing on a device.
/// 3. **Deliberately not deleted.** Destroying a file this build cannot
///    interpret, on the strength of its name, is not a decision a launch gets
///    to make — and the file holds someone's development library. It costs
///    nothing to leave, and an uninstall takes it.
/// 4. **The file side tolerates what it does not recognise.** The store root
///    is shared, so the boot's two file-level passes and the storage survey
///    all have to walk past anything they do not understand rather than
///    throwing on it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/file_store.dart';

import 'data/support/repo_harness.dart';

void main() {
  group('the retired database is a file nothing here can open', () {
    test('the V2 database is not the V1 one', () {
      final schema = File('lib/data/schema.dart').readAsStringSync();
      expect(
        schema,
        contains("name = 'scrollary_library'"),
        reason: 'the V2 store names its own file',
      );
      expect(
        schema.contains("driftDatabase(name: 'webread')"),
        isFalse,
        reason: "V1's file is never opened from here",
      );
    });

    test('no source file can construct the retired database', () {
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final needle in const [
          'AppDatabase',
          'databaseProvider',
          'storage/database.dart',
        ]) {
          if (text.contains(needle)) offenders.add('${file.path}: $needle');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the V1 database is retired; nothing in lib/ may name it, not '
            'even in a comment that would read as an instruction',
      );
    });
  });

  group('the shared store root tolerates what it does not recognise', () {
    late RepoHarness repos;
    late Directory root;
    late FileStore fileStore;
    late CleanupService cleanup;

    setUp(() {
      repos = RepoHarness();
      root = Directory.systemTemp.createTempSync('scrollary_v1_leftovers');
      fileStore = FileStore(root);
      Directory(p.join(root.path, FileStore.libraryFolderName)).createSync();
      Directory(p.join(root.path, FileStore.tmpFolderName)).createSync();
      cleanup = CleanupService(
        offlineCopies: repos.offline,
        entries: repos.entries,
        collections: repos.collections,
        reading: repos.reading,
        fileStore: fileStore,
      );
    });

    tearDown(() async {
      await repos.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a stray file in the root is walked past, not tripped over', () async {
      File(p.join(root.path, 'webread.sqlite')).writeAsStringSync('not ours');
      File(
        p.join(root.path, FileStore.libraryFolderName, 'stray.txt'),
      ).writeAsStringSync('not a package either');

      // The boot's two file-level passes, and the one walk that reads the
      // library tree.
      expect(await fileStore.restoreInterruptedReplacements(), 0);
      expect(await fileStore.sweepStaging(), 0);
      expect(fileStore.listCommittedEntryPaths(), isEmpty);

      final survey = await cleanup.survey();
      expect(survey.held, isEmpty);
      expect(survey.missing, isEmpty);
      expect(
        survey.orphans,
        isEmpty,
        reason: 'a loose file is not a package, and is never offered as one',
      );

      expect(
        File(p.join(root.path, 'webread.sqlite')).existsSync(),
        isTrue,
        reason: 'nothing deletes a file it cannot interpret',
      );
    });
  });
}
