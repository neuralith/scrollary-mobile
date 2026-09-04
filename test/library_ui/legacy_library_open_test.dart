/// The Library, drawn over a database an older build left on disk.
///
/// The failure this guards is what the user saw: *Null check operator used on
/// a null value*, and a shelf with nothing on it. It happened only against an
/// existing library — `collections.capture_mode` and `collections.entry_sort`
/// were declared without a schema version bump, so drift's `SELECT *` returned
/// a row the generated mapper could not build (V2-D75).
///
/// Every other suite here builds its database fresh and therefore cannot see
/// it. This one opens a version-1 file and pumps the real screens over it.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/library_ui/shelf_screen.dart';

import '../helpers/version_one_library.dart';
import 'support/ui_harness.dart';

void main() {
  late Directory dir;
  late UiHarness h;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scrollary_legacy_library');
  });

  tearDown(() async {
    await h.close();
    await dir.delete(recursive: true);
  });

  Future<void> openVersionOneLibrary() async {
    final file = File('${dir.path}/library.sqlite');
    await writeVersionOneLibrary(
      file,
      collectionName: 'Quiet Harbour',
      entryTitle: 'The twelfth',
    );
    h = UiHarness(executor: NativeDatabase(file));
  }

  screenTest('the shelf draws the work a version-1 library already held', (
    tester,
  ) async {
    await openVersionOneLibrary();

    await tester.pumpWidget(h.app(const ShelfScreen()));
    await pumpUntil(tester, find.text('Quiet Harbour'));

    expect(find.text('Quiet Harbour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  screenTest('the Collection draws its Entries, in an order nobody has set', (
    tester,
  ) async {
    await openVersionOneLibrary();

    await tester.pumpWidget(
      h.app(const CollectionScreen(collectionId: 'coll')),
    );
    await pumpUntil(tester, find.text('The twelfth'));

    expect(find.text('The twelfth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
