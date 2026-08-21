import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/page_stability.dart';

/// What counts as the page changing while a save traverses it.
///
/// The rule under test: change to an image counts only when that image could
/// be entry content, while the page's height and its total image count count
/// unconditionally. Before this existed, a decorative image cycling at the
/// bottom of a finished page reset the quiet timer on every probe and a
/// settled entry could run all the way to the save deadline.
void main() {
  /// A full-size panel — the thing a reader came for.
  PageImage panel(
    int index, {
    String? url,
    int width = 800,
    int height = 1200,
    bool complete = true,
    bool broken = false,
  }) => PageImage(
    domIndex: index,
    src: url ?? 'https://cdn.example/p/$index.png',
    currentSrc: url ?? 'https://cdn.example/p/$index.png',
    complete: complete,
    naturalWidth: broken || !complete ? 0 : width,
    naturalHeight: broken || !complete ? 0 : height,
    // Declared attributes, so a panel that never loads is still sized as one
    // rather than shrinking into an icon.
    attrWidth: width,
    attrHeight: height,
    renderedWidth: 390,
    renderedHeight: 585,
    documentTop: index * height,
  );

  /// A 300x250 advertisement slot: never qualifies, whatever it does.
  PageImage decoration(int index, {required bool loaded}) => PageImage(
    domIndex: 900 + index,
    src: 'https://ads.example/slot/$index.gif',
    currentSrc: 'https://ads.example/slot/$index.gif',
    complete: loaded,
    naturalWidth: loaded ? 300 : 0,
    naturalHeight: loaded ? 250 : 0,
    renderedWidth: 300,
    renderedHeight: 250,
    documentTop: 5000,
  );

  PageProbe page(List<PageImage> images, {int documentHeight = 12000}) =>
      PageProbe(
        url: 'https://x.example/guide/foo/1',
        title: 'Foo Entry 1',
        readyState: 'complete',
        documentHeight: documentHeight,
        viewportHeight: 800,
        images: images,
      );

  group('changes that are not progress', () {
    test('a decorative image finishing does not change the signature', () {
      final before = measureStability(
        page([panel(0), panel(1), panel(2), decoration(1, loaded: false)]),
      );
      final after = measureStability(
        page([panel(0), panel(1), panel(2), decoration(1, loaded: true)]),
      );

      expect(after, before);
    });

    test('a decorative image cycling forever does not change it', () {
      // The case that used to run a settled entry into the save deadline.
      final states = [
        for (var i = 0; i < 6; i++)
          measureStability(
            page([panel(0), panel(1), decoration(1, loaded: i.isEven)]),
          ),
      ];

      expect(states.toSet(), hasLength(1));
    });

    test('reordering the same qualified images does not change it', () {
      final before = measureStability(page([panel(0), panel(1), panel(2)]));
      final after = measureStability(page([panel(2), panel(0), panel(1)]));

      expect(after, before);
    });
  });

  group('changes that are progress', () {
    test('a newly discovered qualified image changes it', () {
      final before = measureStability(page([panel(0), panel(1)]));
      final after = measureStability(page([panel(0), panel(1), panel(2)]));

      expect(after, isNot(before));
    });

    test('a placeholder swapped for the final URL changes it', () {
      // Same count, same size, same load state — only the address moved.
      final before = measureStability(
        page([
          panel(0, url: 'https://cdn.example/p/placeholder.png'),
          panel(1),
        ]),
      );
      final after = measureStability(
        page([panel(0, url: 'https://cdn.example/p/real-0.png'), panel(1)]),
      );

      expect(after, isNot(before));
    });

    test('dimensions changing at an unchanged URL changes it', () {
      final before = measureStability(
        page([panel(0, width: 800, height: 1200), panel(1)]),
      );
      final after = measureStability(
        page([panel(0, width: 800, height: 4800), panel(1)]),
      );

      expect(after, isNot(before));
    });

    test('a qualified image finishing changes it', () {
      final before = measureStability(
        page([panel(0, complete: false), panel(1)]),
      );
      final after = measureStability(page([panel(0), panel(1)]));

      expect(after, isNot(before));
    });

    test('a qualified image breaking changes it', () {
      // Pending -> broken is a settled outcome, and it must register: the
      // entry becomes partial rather than staying "still loading".
      final before = measureStability(
        page([panel(0, complete: false), panel(1)]),
      );
      final after = measureStability(
        page([panel(0, complete: true, broken: true), panel(1)]),
      );

      expect(after, isNot(before));
    });
  });

  group('a lazy loader firing is progress', () {
    test('untriggered becoming in-flight changes the signature', () {
      // Neither the resolved count nor the URL moves at this moment, so this
      // transition is only visible through the unrequested count. Without it
      // the page would look settled exactly as it started fetching a panel.
      final before = measureStability(
        page([
          panel(0),
          PageImage(
            domIndex: 1,
            dataSrc: 'https://cdn.example/p/1.png',
            hasSource: false,
            complete: true,
            attrWidth: 800,
            attrHeight: 1200,
            renderedWidth: 390,
            renderedHeight: 585,
          ),
        ]),
      );
      final after = measureStability(
        page([
          panel(0),
          PageImage(
            domIndex: 1,
            src: 'https://cdn.example/p/1.png',
            currentSrc: 'https://cdn.example/p/1.png',
            hasSource: true,
            complete: false,
            attrWidth: 800,
            attrHeight: 1200,
            renderedWidth: 390,
            renderedHeight: 585,
          ),
        ]),
      );

      expect(after, isNot(before));
    });
  });

  group('structural change counts unconditionally', () {
    test('document height growing with no new images changes it', () {
      // Infinite loading routinely inserts empty containers first. A signal
      // that watched only qualified images would read this as nothing.
      final images = [panel(0), panel(1)];
      final before = measureStability(page(images, documentHeight: 12000));
      final after = measureStability(page(images, documentHeight: 24000));

      expect(after, isNot(before));
    });

    test('a new DOM image changes it even before it can qualify', () {
      final before = measureStability(page([panel(0), panel(1)]));
      final after = measureStability(
        page([panel(0), panel(1), decoration(7, loaded: false)]),
      );

      expect(
        after,
        isNot(before),
        reason: 'a newly inserted node is new page content, qualified or not',
      );
    });
  });
}
