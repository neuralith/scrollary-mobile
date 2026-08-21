import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/content_detection.dart';

/// Direct tests for the two detectors and the capability table built on them.
///
/// These are the functions that decide what a user's offline copy will contain,
/// and until now they had none: `ARCHITECTURE.md` claimed they were
/// "unit-tested at the domain layer" when only the *labels* derived from them
/// were. Everything here is a literal [PageProbe], so each rule is exercised
/// without a WebView and without naming a website.
void main() {
  // --- probe builders -------------------------------------------------------
  // Named after what they describe, not after any site that looks like this.

  PageImage panel(int i, {int width = 800, int height = 1200}) => PageImage(
    domIndex: i,
    src: 'https://example.com/img/$i.png',
    complete: true,
    naturalWidth: width,
    naturalHeight: height,
    documentTop: i * height,
  );

  PageProbe probe({
    List<PageImage> images = const [],
    PageContentSignals content = const PageContentSignals(),
    PageMediaSignals media = const PageMediaSignals(),
    int documentHeight = 4000,
    int viewportHeight = 800,
    int viewportWidth = 400,
  }) => PageProbe(
    url: 'https://example.com/item',
    title: 'An item',
    documentHeight: documentHeight,
    viewportHeight: viewportHeight,
    viewportWidth: viewportWidth,
    images: images,
    content: content,
    media: media,
  );

  const prose = PageContentSignals(
    textLength: 4200,
    paragraphCount: 12,
    headingCount: 3,
    hasArticleElement: true,
  );

  group('detectContentKind', () {
    test('a column of large images is image-dominant', () {
      final shape = detectContentKind(
        probe(
          images: [for (var i = 0; i < 6; i++) panel(i)],
          content: const PageContentSignals(
            textLength: 80,
            contentImageCount: 6,
            contentImagePixels: 6 * 800 * 1200,
          ),
        ),
      );
      expect(shape.kind, ContentKind.imageDominant);
      expect(shape.confidence, ShapeConfidence.high);
    });

    test('prose inside an <article> is an article', () {
      final shape = detectContentKind(probe(content: prose));
      expect(shape.kind, ContentKind.article);
      expect(shape.confidence, ShapeConfidence.high);
    });

    test('a page with neither prose nor images is honestly unknown', () {
      final shape = detectContentKind(
        probe(content: const PageContentSignals(textLength: 120)),
      );
      expect(shape.kind, ContentKind.unknownWebContent);
      expect(shape.confidence, ShapeConfidence.low);
    });

    group('video', () {
      test(
        'a big player in the content region with no prose is a video page',
        () {
          final shape = detectContentKind(
            probe(
              content: const PageContentSignals(textLength: 180),
              media: const PageMediaSignals(
                videoCount: 1,
                // Half the 400x800 viewport.
                primaryVideoPixels: 400 * 400,
                videoInContentRegion: true,
              ),
            ),
          );
          expect(shape.kind, ContentKind.videoDominant);
          expect(shape.confidence, ShapeConfidence.high);
        },
      );

      test('an article that merely embeds a video stays an article', () {
        final shape = detectContentKind(
          probe(
            content: prose,
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 400,
              videoInContentRegion: true,
            ),
          ),
        );
        expect(shape.kind, ContentKind.article);
      });

      test('a player outside the readable region is page furniture', () {
        final shape = detectContentKind(
          probe(
            content: const PageContentSignals(textLength: 180),
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 400,
              videoInContentRegion: false,
            ),
          ),
        );
        expect(shape.kind, isNot(ContentKind.videoDominant));
      });

      test('a small preview is not a video page', () {
        final shape = detectContentKind(
          probe(
            content: const PageContentSignals(textLength: 180),
            media: const PageMediaSignals(
              videoCount: 8,
              // A grid of previews: many players, none of them big.
              primaryVideoPixels: 200 * 112,
              videoInContentRegion: true,
            ),
          ),
        );
        expect(shape.kind, isNot(ContentKind.videoDominant));
      });

      test('an unmeasurable viewport declines to classify', () {
        final shape = detectContentKind(
          probe(
            viewportWidth: 0,
            content: const PageContentSignals(textLength: 180),
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 400,
              videoInContentRegion: true,
            ),
          ),
        );
        expect(shape.kind, isNot(ContentKind.videoDominant));
      });

      test('a page of full-size images with a player is still images', () {
        final shape = detectContentKind(
          probe(
            images: [for (var i = 0; i < 6; i++) panel(i)],
            content: const PageContentSignals(
              textLength: 80,
              contentImageCount: 6,
              contentImagePixels: 6 * 800 * 1200,
            ),
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 400,
              videoInContentRegion: true,
            ),
          ),
        );
        expect(shape.kind, ContentKind.imageDominant);
      });
    });
  });

  group('detectCaptureCapabilities', () {
    test('an image sequence offers images and nothing else', () {
      final caps = detectCaptureCapabilities(
        probe(
          images: [for (var i = 0; i < 6; i++) panel(i)],
          content: const PageContentSignals(
            textLength: 80,
            contentImageCount: 6,
            contentImagePixels: 6 * 800 * 1200,
          ),
        ),
      );
      expect(caps.defaultMode, CaptureMode.imageSequence);
      expect(caps.allows(CaptureMode.textOnly), isFalse);
      expect(
        caps.blocked[CaptureMode.textOnly],
        ModeBlockReason.noReadableText,
      );
    });

    test('prose with no meaningful inline images defaults to text only', () {
      final caps = detectCaptureCapabilities(probe(content: prose));
      expect(caps.defaultMode, CaptureMode.textOnly);
      expect(caps.allows(CaptureMode.textAndImages), isFalse);
      expect(
        caps.blocked[CaptureMode.textAndImages],
        ModeBlockReason.noMeaningfulImages,
      );
    });

    test('prose with inline images defaults to text and images', () {
      final caps = detectCaptureCapabilities(
        probe(
          content: const PageContentSignals(
            textLength: 4200,
            paragraphCount: 12,
            headingCount: 3,
            hasArticleElement: true,
            contentRegionImageCount: 3,
            contentRegionImagePixels: 3 * 640 * 420,
          ),
        ),
      );
      expect(caps.defaultMode, CaptureMode.textAndImages);
      expect(caps.allows(CaptureMode.textOnly), isTrue);
    });

    test(
      'a sidebar full of thumbnails does not make text-and-images available',
      () {
        // `contentImageCount` is high because the page has thumbnails; the
        // count that matters is the one measured inside the readable region.
        final caps = detectCaptureCapabilities(
          probe(
            content: const PageContentSignals(
              textLength: 4200,
              paragraphCount: 12,
              hasArticleElement: true,
              contentImageCount: 12,
              contentImagePixels: 12 * 300 * 300,
              contentRegionImageCount: 0,
            ),
          ),
        );
        expect(caps.defaultMode, CaptureMode.textOnly);
        expect(caps.allows(CaptureMode.textAndImages), isFalse);
      },
    );

    test('an ambiguous page keeps the previous image-first behaviour', () {
      // Enough images for a sequence, not enough signal to classify. The
      // preselection must not silently change for pages that used to save.
      final caps = detectCaptureCapabilities(
        probe(
          images: [for (var i = 0; i < 4; i++) panel(i)],
          content: const PageContentSignals(textLength: 300),
        ),
      );
      expect(caps.content.kind, ContentKind.unknownWebContent);
      expect(caps.content.confidence.isActionable, isFalse);
      expect(caps.defaultMode, CaptureMode.imageSequence);
    });

    test(
      'a video page with readable text offers the text, never the images',
      () {
        final caps = detectCaptureCapabilities(
          probe(
            images: [for (var i = 0; i < 6; i++) panel(i)],
            content: const PageContentSignals(
              textLength: 2400,
              paragraphCount: 8,
              contentRegionImageCount: 1,
            ),
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 400,
              videoInContentRegion: true,
            ),
          ),
        );
        // Prose is present, so the page is not classified videoDominant — but
        // whatever the classification, a text mode is what gets preselected
        // rather than a sweep of the page's images.
        expect(caps.defaultMode, isNot(CaptureMode.imageSequence));
        expect(caps.canSaveAnything, isTrue);
      },
    );

    test('a video page with nothing readable can save nothing', () {
      final caps = detectCaptureCapabilities(
        probe(
          content: const PageContentSignals(textLength: 120),
          media: const PageMediaSignals(
            videoCount: 1,
            primaryVideoPixels: 400 * 500,
            videoInContentRegion: true,
          ),
        ),
      );
      expect(caps.videoDominant, isTrue);
      expect(caps.canSaveAnything, isFalse);
      expect(caps.defaultMode, isNull);
    });

    test('an unclassifiable page still offers the image attempt', () {
      // Two images and no prose: not a sequence by the clustering rule, not
      // readable text either. The app must still be willing to try — the
      // image path is the one with reader-area assistance behind it, and a
      // page like this is exactly what that assistance is for.
      final caps = detectCaptureCapabilities(
        probe(
          images: [panel(0), panel(1)],
          content: const PageContentSignals(textLength: 120),
        ),
      );
      expect(caps.canSaveAnything, isTrue);
      expect(caps.defaultMode, CaptureMode.imageSequence);
      expect(caps.allows(CaptureMode.imageSequence), isTrue);
      expect(caps.videoDominant, isFalse);
    });

    test('a video page with nothing readable is still refused outright', () {
      // The one case where "we cannot tell, try images" must NOT apply:
      // attempting an image sequence here would collect the page's thumbnails.
      final caps = detectCaptureCapabilities(
        probe(
          images: [panel(0), panel(1)],
          content: const PageContentSignals(textLength: 120),
          media: const PageMediaSignals(
            videoCount: 1,
            primaryVideoPixels: 400 * 500,
            videoInContentRegion: true,
          ),
        ),
      );
      expect(caps.videoDominant, isTrue);
      expect(caps.canSaveAnything, isFalse);
      expect(caps.allows(CaptureMode.imageSequence), isFalse);
    });

    test('an unanalysed page offers everything and says so', () {
      const caps = CaptureCapabilities.unanalysed();
      expect(caps.analysed, isFalse);
      expect(caps.defaultMode, CaptureMode.imageSequence);
      for (final mode in CaptureMode.values) {
        expect(caps.allows(mode), isTrue, reason: mode.name);
      }
    });
  });

  group('resolving a requested mode', () {
    final imagePage = probe(
      images: [for (var i = 0; i < 6; i++) panel(i)],
      content: const PageContentSignals(
        textLength: 80,
        contentImageCount: 6,
        contentImagePixels: 6 * 800 * 1200,
      ),
    );

    test('an honourable request is honoured', () {
      final caps = detectCaptureCapabilities(imagePage);
      final resolved = caps.resolve(CaptureMode.imageSequence);
      expect(resolved.mode, CaptureMode.imageSequence);
      expect(resolved.honoured, isTrue);
      expect(resolved.explanation, isNull);
    });

    test('a stale preference falls back and explains itself', () {
      final caps = detectCaptureCapabilities(imagePage);
      final resolved = caps.resolve(CaptureMode.textAndImages);
      expect(resolved.honoured, isFalse);
      expect(resolved.mode, CaptureMode.imageSequence);
      expect(resolved.didFallBack, isTrue);
      expect(resolved.explanation, contains('Text and images'));
      expect(resolved.explanation, contains('No readable text'));
    });

    test('no request means the detected default', () {
      final caps = detectCaptureCapabilities(imagePage);
      expect(caps.resolve(null).mode, caps.defaultMode);
    });

    test(
      'a preference on a page that can hold nothing resolves to nothing',
      () {
        final caps = detectCaptureCapabilities(
          probe(
            content: const PageContentSignals(textLength: 120),
            media: const PageMediaSignals(
              videoCount: 1,
              primaryVideoPixels: 400 * 500,
              videoInContentRegion: true,
            ),
          ),
        );
        final resolved = caps.resolve(CaptureMode.textOnly);
        expect(resolved.mode, isNull);
        expect(resolved.explanation, isNotNull);
      },
    );
  });

  group('capture mode', () {
    test('every mode maps to exactly one stored artifact', () {
      expect(CaptureMode.imageSequence.isDocument, isFalse);
      expect(CaptureMode.textOnly.isDocument, isTrue);
      expect(CaptureMode.textAndImages.isDocument, isTrue);
      expect(CaptureMode.textOnly.fetchesImages, isFalse);
      expect(CaptureMode.textAndImages.fetchesImages, isTrue);
    });

    test('there is no video capture mode', () {
      expect(
        CaptureMode.values.map((m) => m.name),
        isNot(contains(contains('video'))),
      );
    });

    test('an unrecognised stored mode is null, never a substitute', () {
      expect(captureModeFromName(null), isNull);
      expect(captureModeFromName('somethingElse'), isNull);
      expect(captureModeFromName('textOnly'), CaptureMode.textOnly);
    });
  });
}
