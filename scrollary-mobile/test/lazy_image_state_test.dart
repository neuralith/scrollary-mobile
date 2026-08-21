import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/image_candidates.dart';

/// Telling an image that has not been switched on yet from one that is dead.
///
/// `HTMLImageElement.complete` is true in three unrelated situations (HTML
/// §the-img-element): the load finished, the load failed, **and** the element
/// has neither `src` nor `srcset` at all. `naturalWidth` is 0 in the last two.
/// So `complete && naturalWidth == 0` — what this code used to call "broken" —
/// lumped a dead image together with a lazy one whose real address is still
/// parked in `data-src`.
///
/// That mattered because the adaptive lookahead deliberately ignores broken
/// images: nothing is coming, so there is nothing to slow down for. Applying
/// that to an untriggered lazy image told the engine a region was settled when
/// its panels had never been asked for, and the loader that would have produced
/// them only fires if something scrolls there.
///
/// The shapes below were measured against a real WKWebView; see
/// `integration_test/lazy_image_flow_test.dart`.
void main() {
  PageImage image({
    String? src,
    String? currentSrc,
    String? dataSrc,
    required bool hasSource,
    required bool complete,
    int naturalWidth = 0,
    int naturalHeight = 0,
    int attrWidth = 800,
    int attrHeight = 1200,
    bool hidden = false,
  }) => PageImage(
    domIndex: 0,
    src: src,
    currentSrc: currentSrc,
    dataSrc: dataSrc,
    hasSource: hasSource,
    complete: complete,
    naturalWidth: naturalWidth,
    naturalHeight: naturalHeight,
    attrWidth: attrWidth,
    attrHeight: attrHeight,
    renderedWidth: 390,
    renderedHeight: 585,
    hidden: hidden,
  );

  /// A loaded panel.
  final loaded = image(
    src: 'https://cdn.example/p/1.png',
    currentSrc: 'https://cdn.example/p/1.png',
    hasSource: true,
    complete: true,
    naturalWidth: 800,
    naturalHeight: 1200,
  );

  /// In flight: asked for, not arrived.
  final inFlight = image(
    src: 'https://cdn.example/p/2.png',
    currentSrc: 'https://cdn.example/p/2.png',
    hasSource: true,
    complete: false,
  );

  /// Asked for, finished, no pixels — a real 404.
  final failed = image(
    src: 'https://cdn.example/gone.png',
    currentSrc: 'https://cdn.example/gone.png',
    hasSource: true,
    complete: true,
  );

  /// `<img data-src="…">` — never asked for anything.
  final untriggered = image(
    dataSrc: 'https://cdn.example/p/3.png',
    hasSource: false,
    complete: true,
  );

  /// `<img src="" data-src="…">` — the empty-src variant of the same thing.
  final emptySrc = image(
    src: '',
    dataSrc: 'https://cdn.example/p/4.png',
    hasSource: false,
    complete: true,
  );

  group('the four states are distinct', () {
    test('a loaded image is resolved and nothing else', () {
      expect(loaded.isResolved, isTrue);
      expect(loaded.isPending, isFalse);
      expect(loaded.isBroken, isFalse);
      expect(loaded.isUnrequested, isFalse);
      expect(loaded.isUnsettled, isFalse);
    });

    test('an in-flight image is pending', () {
      expect(inFlight.isPending, isTrue);
      expect(inFlight.isBroken, isFalse);
      expect(inFlight.isUnrequested, isFalse);
      expect(inFlight.isUnsettled, isTrue);
    });

    test('a failed image is broken, and terminally so', () {
      expect(failed.isBroken, isTrue);
      expect(failed.isPending, isFalse);
      expect(failed.isUnrequested, isFalse);
      expect(
        failed.isUnsettled,
        isFalse,
        reason: 'nothing more is coming, so traversal must not wait for it',
      );
    });

    test('an untriggered lazy image is NOT broken', () {
      expect(untriggered.isUnrequested, isTrue);
      expect(untriggered.isBroken, isFalse);
      expect(untriggered.isResolved, isFalse);
      expect(
        untriggered.isUnsettled,
        isTrue,
        reason: 'the page still has this one to give',
      );
    });

    test('an empty src is the same as no src', () {
      expect(emptySrc.isUnrequested, isTrue);
      expect(emptySrc.isBroken, isFalse);
      expect(emptySrc.isUnsettled, isTrue);
    });
  });

  group('traversal treats them correctly', () {
    /// The engine's own gate, as `_scrollPass` applies it.
    bool blocksFastMode(PageImage i) =>
        couldBeContent(i) && !i.isResolved && !i.isBroken;

    test('an untriggered lazy panel holds the careful pace', () {
      expect(
        blocksFastMode(untriggered),
        isTrue,
        reason: 'jumping past it means its loader never fires',
      );
    });

    test('an in-flight panel holds the careful pace', () {
      expect(blocksFastMode(inFlight), isTrue);
    });

    test('a genuinely dead panel does not', () {
      expect(
        blocksFastMode(failed),
        isFalse,
        reason: 'waiting for a 404 only spends the deadline',
      );
    });

    test('a loaded panel does not', () {
      expect(blocksFastMode(loaded), isFalse);
    });

    test('an untriggered DECORATIVE image does not', () {
      // The size filter runs first, so the correction cannot make a page full
      // of lazy avatars slow again.
      final avatar = image(
        dataSrc: 'https://cdn.example/avatar.png',
        hasSource: false,
        complete: true,
        attrWidth: 48,
        attrHeight: 48,
      );
      expect(avatar.isUnrequested, isTrue);
      expect(blocksFastMode(avatar), isFalse);
    });
  });

  group('waiting is separate from blocking', () {
    /// `_relevantPendingCount` waits only for what is actually on the wire.
    bool worthWaitingFor(PageImage i) => couldBeContent(i) && i.isPending;

    test('an in-flight panel is worth waiting for', () {
      expect(worthWaitingFor(inFlight), isTrue);
    });

    test('an untriggered panel is NOT worth waiting for', () {
      expect(
        worthWaitingFor(untriggered),
        isFalse,
        reason:
            'nothing is on the wire — only scrolling to it helps, which is '
            'why the lookahead sees it and the asset wait does not',
      );
    });

    test('a dead panel is not worth waiting for', () {
      expect(worthWaitingFor(failed), isFalse);
    });
  });

  group('the state transitions as a loader runs', () {
    test('untriggered becomes pending becomes resolved', () {
      var i = untriggered;
      expect(i.isUnrequested, isTrue);

      // The loader assigns the real address.
      i = image(
        src: 'https://cdn.example/p/3.png',
        currentSrc: 'https://cdn.example/p/3.png',
        hasSource: true,
        complete: false,
      );
      expect(i.isPending, isTrue);
      expect(i.isUnrequested, isFalse);

      // …and it arrives.
      i = image(
        src: 'https://cdn.example/p/3.png',
        currentSrc: 'https://cdn.example/p/3.png',
        hasSource: true,
        complete: true,
        naturalWidth: 800,
        naturalHeight: 1200,
      );
      expect(i.isResolved, isTrue);
      expect(i.isUnsettled, isFalse);
    });

    test('untriggered can become broken if the real address 404s', () {
      final after = image(
        src: 'https://cdn.example/p/3.png',
        currentSrc: 'https://cdn.example/p/3.png',
        hasSource: true,
        complete: true,
      );
      expect(after.isBroken, isTrue);
    });
  });

  group('candidate selection is unchanged', () {
    test('a broken panel is still a candidate, so it fails out loud', () {
      final selection = selectImageCandidates([
        loaded,
        failed,
        image(
          src: 'https://cdn.example/p/9.png',
          currentSrc: 'https://cdn.example/p/9.png',
          hasSource: true,
          complete: true,
          naturalWidth: 800,
          naturalHeight: 1200,
        ),
      ]);
      expect(
        selection.accepted.map((c) => c.url),
        contains('https://cdn.example/gone.png'),
      );
    });

    test('an untriggered panel is a candidate via its lazy address', () {
      final selection = selectImageCandidates([untriggered, loaded, inFlight]);
      expect(
        selection.accepted.map((c) => c.url),
        contains('https://cdn.example/p/3.png'),
      );
    });
  });

  group('an older bridge degrades safely', () {
    test('a probe without hasSource keeps the previous meaning', () {
      // No `hasSource` key: the flag defaults to true, so a complete image
      // with no pixels still reads as broken rather than as something the
      // engine would wait forever for.
      final parsed = PageImage.fromJson({
        'index': 0,
        'src': 'https://cdn.example/gone.png',
        'complete': true,
        'naturalWidth': 0,
        'naturalHeight': 0,
      });
      expect(parsed.hasSource, isTrue);
      expect(parsed.isBroken, isTrue);
      expect(parsed.isUnrequested, isFalse);
    });

    test('a probe that reports hasSource:false is honoured', () {
      final parsed = PageImage.fromJson({
        'index': 0,
        'dataSrc': 'https://cdn.example/p/1.png',
        'complete': true,
        'hasSource': false,
        'naturalWidth': 0,
      });
      expect(parsed.isUnrequested, isTrue);
      expect(parsed.isBroken, isFalse);
    });
  });
}
