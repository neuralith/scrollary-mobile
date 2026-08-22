/// What a page is, structurally (V2_SAVE_FLOW.md §2).
///
/// Shape is not identity: nothing here merges anything, and nothing here
/// decides what the library holds. Every answer is a real answer —
/// [PageKind.unknownPage] means the page did not say, which is why the user is
/// asked rather than guessed at.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/recognition/page_kind.dart';

import 'support/recognition_harness.dart';

void main() {
  test('a page that printed a number is an entry of something', () {
    final shape = readPageShape(partUrl(kHostA, 5), pageTitle: 'Part 5');

    expect(shape.kind, PageKind.entryPage);
    expect(shape.printedNumber, 5);
    expect(shape.identityIsStrong, isTrue);
  });

  test('a page below a listing is an entry even with no number', () {
    final shape = readPageShape(
      postUrl(kHostA, 'epilogue'),
      pageTitle: 'Epilogue',
    );

    expect(shape.kind, PageKind.entryPage);
    expect(
      shape.printedNumber,
      isNull,
      reason: 'nothing numbered it, and a position is never guessed',
    );
  });

  test('the address a work is published at is the listing itself', () {
    final shape = readPageShape(
      'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
    );

    expect(shape.kind, PageKind.collectionIndex);
    expect(shape.identityIsStrong, isTrue);
    expect(shape.printedNumber, isNull);
  });

  test('an ordinary page did not say, and says so', () {
    final shape = readPageShape('https://$kHostA/', pageTitle: 'Alpha');

    expect(shape.kind, PageKind.unknownPage);
    expect(shape.identityIsStrong, isFalse);
    expect(shape.isSerialized, isFalse);
  });
}
