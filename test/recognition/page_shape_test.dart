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

  test('a Source\'s own address is the listing, when the library can say '
      'so', () {
    final shape = readPageShape(
      'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
      sourcePathKey: kWorkPath,
    );

    expect(shape.kind, PageKind.collectionIndex);
    expect(shape.identityIsStrong, isTrue);
    expect(shape.printedNumber, isNull);
  });

  test('the same address is not a listing when nothing knows it is', () {
    // An address alone cannot tell a work's listing from an about page, and
    // announcing "add this collection" over a privacy policy is the failure
    // that guess produces. Without the library's word, it did not say.
    final shape = readPageShape(
      'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
    );

    expect(shape.kind, PageKind.unknownPage);
    expect(shape.identityIsStrong, isTrue);
  });

  test('an ordinary page did not say, and says so', () {
    final shape = readPageShape('https://$kHostA/', pageTitle: 'Alpha');

    expect(shape.kind, PageKind.unknownPage);
    expect(shape.identityIsStrong, isFalse);
    expect(shape.isSerialized, isFalse);
  });
}
