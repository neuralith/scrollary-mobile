/// The V2 half of a widget-test app: a real in-memory LibraryDatabase, the
/// services over it, and provider overrides for everything `main()` wires.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/check_controller.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/library_ui/providers.dart' as libui;
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/entry_capture.dart';
import 'package:web_reader/save/queue_runner.dart';
import 'package:web_reader/storage/file_store.dart';

/// One page of nothing: a stand-in observation source for tests that never
/// run a check.
class _NoObservations implements SourceObservationSource {
  const _NoObservations();
  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) async => SourceObservation.unreadable(
    url: pageUrl ?? '',
    stop: SourceCheckStop.listingUnreadable,
  );
}

class V2Harness {
  V2Harness({required BrowserController browser, required FileStore fileStore})
    : library = LibraryDatabase.forTesting(NativeDatabase.memory()) {
    ui = libui.LibraryUiServices(library, fileStore: fileStore);
    runner = QueueRunner(
      queue: ui.queue,
      captureServiceFor: () => EntryCaptureService(
        entries: ui.entries,
        collections: ui.collections,
        offlineCopies: ui.offline,
        fileStore: fileStore,
        source: throw UnimplementedError('no capture in this test'),
      ),
    );
    check = CheckController(
      browser: browser,
      collections: CollectionRepository(library),
      entries: EntryRepository(library),
      index: RecognitionIndex(library),
      observations: const _NoObservations(),
    );
    services = V2Services(
      library: library,
      ui: ui,
      runner: runner,
      check: check,
    );
  }

  final LibraryDatabase library;
  late final libui.LibraryUiServices ui;
  late final QueueRunner runner;
  late final CheckController check;
  late final V2Services services;

  Future<void> close() async {
    runner.dispose();
    check.dispose();
    await library.close();
  }
}

/// A throwaway file store rooted in a temp dir, for harnesses that never
/// commit bytes.
FileStore tempFileStore() {
  final root = Directory.systemTemp.createTempSync('webread_v2_harness');
  Directory('${root.path}/${FileStore.libraryFolderName}').createSync();
  Directory('${root.path}/${FileStore.tmpFolderName}').createSync();
  return FileStore(root);
}
