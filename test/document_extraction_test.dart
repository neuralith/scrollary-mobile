import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/document_extraction.dart';
import 'package:web_reader/storage/document.dart';

/// What survives extraction, and what does not.
///
/// The browser half measures and flags; these are the *decisions* made on the
/// Dart side, against literal blocks. No WebView, no website — the same
/// property that makes `content_detection.dart` testable.
void main() {
  const url = 'https://example.com/text/1';

  RawDocumentBlock text(
    String body, {
    String kind = 'paragraph',
    int level = 0,
    bool ordered = false,
    bool chrome = false,
    bool hidden = false,
    List<RawInlineMark> marks = const [],
  }) => RawDocumentBlock(
    kind: kind,
    text: body,
    level: level,
    ordered: ordered,
    inChrome: chrome,
    hidden: hidden,
    marks: marks,
  );

  RawDocumentBlock image(
    String src, {
    int width = 640,
    int height = 420,
    String alt = '',
    bool chrome = false,
    bool hidden = false,
  }) => RawDocumentBlock(
    kind: 'image',
    src: src,
    alt: alt,
    width: width,
    height: height,
    inChrome: chrome,
    hidden: hidden,
  );

  /// Enough prose to clear the "worth storing" floor.
  String filler([int repeats = 6]) => List.filled(
    repeats,
    'The quick brown fox jumps over the lazy dog. ',
  ).join();

  RawDocument doc(List<RawDocumentBlock> blocks, {String title = 'A title'}) =>
      RawDocument(title: title, blocks: blocks, regionBasis: 'article element');

  DocumentExtraction run(
    RawDocument? raw, {
    CaptureMode mode = CaptureMode.textAndImages,
  }) => extractDocument(raw, mode: mode, sourceUrl: url);

  group('structure', () {
    test('headings and paragraphs keep their type, level and order', () {
      final result = run(
        doc([
          text('The Beginning', kind: 'heading', level: 1),
          text(filler()),
          text('A Subheading', kind: 'heading', level: 3),
          text(filler()),
        ]),
      );
      expect(result.isSuccess, isTrue);
      final blocks = result.document!.blocks;
      expect(blocks.map((b) => b.type), [
        DocumentBlockType.heading,
        DocumentBlockType.paragraph,
        DocumentBlockType.heading,
        DocumentBlockType.paragraph,
      ]);
      expect(blocks[0].level, 1);
      expect(blocks[2].level, 3);
      expect(blocks.map((b) => b.index), [0, 1, 2, 3]);
    });

    test('lists and block quotes survive with their own types', () {
      final result = run(
        doc([
          text(filler()),
          text('First point', kind: 'listItem', level: 1),
          text('Second point', kind: 'listItem', level: 1),
          text('A nested point', kind: 'listItem', level: 2, ordered: true),
          text('Something someone said', kind: 'quote'),
        ]),
      );
      final blocks = result.document!.blocks;
      expect(blocks[1].type, DocumentBlockType.listItem);
      expect(blocks[3].level, 2);
      expect(blocks[3].ordered, isTrue);
      expect(blocks[4].type, DocumentBlockType.quote);
    });

    test(
      'a separator between blocks is kept; leading and trailing are not',
      () {
        final result = run(
          doc([
            const RawDocumentBlock(kind: 'separator'),
            text(filler()),
            const RawDocumentBlock(kind: 'separator'),
            const RawDocumentBlock(kind: 'separator'),
            text(filler()),
            const RawDocumentBlock(kind: 'separator'),
          ]),
        );
        final types = result.document!.blocks.map((b) => b.type).toList();
        expect(types, [
          DocumentBlockType.paragraph,
          DocumentBlockType.separator,
          DocumentBlockType.paragraph,
        ]);
      },
    );

    test('an unrecognised block kind is dropped, not guessed at', () {
      final result = run(
        doc([
          text(filler()),
          text('???', kind: 'somethingNew'),
          text(filler()),
        ]),
      );
      expect(result.document!.blockCount, 2);
      expect(result.droppedBlocks, 1);
    });
  });

  group('exclusion', () {
    test('page furniture never reaches storage', () {
      final result = run(
        doc([
          text('Skip to content', chrome: true),
          text(filler()),
          text('Sign up for our newsletter', chrome: true),
          image('https://example.com/ad.png', chrome: true),
          text(filler()),
        ]),
      );
      final blocks = result.document!.blocks;
      expect(blocks.length, 2);
      expect(
        blocks.every((b) => b.type == DocumentBlockType.paragraph),
        isTrue,
      );
      expect(result.droppedBlocks, 3);
    });

    test('hidden content never reaches storage', () {
      final result = run(
        doc([
          text('Screen-reader only preamble', hidden: true),
          text(filler()),
          image('https://example.com/hidden.png', hidden: true),
          text(filler()),
        ]),
      );
      expect(result.document!.blockCount, 2);
      expect(result.document!.blocks.any((b) => b.isImage), isFalse);
    });

    test('an image too small to matter is dropped', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/icon.png', width: 32, height: 32),
          text(filler()),
        ]),
      );
      expect(result.document!.blocks.any((b) => b.isImage), isFalse);
    });

    test('an image with no usable URL is dropped', () {
      final result = run(
        doc([
          text(filler()),
          const RawDocumentBlock(kind: 'image', width: 800, height: 600),
          text(filler()),
        ]),
      );
      expect(result.document!.blocks.any((b) => b.isImage), isFalse);
    });
  });

  group('inline images', () {
    test('keep their position between the text blocks', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/a.png', alt: 'The first figure'),
          text(filler()),
          image('https://example.com/b.png'),
          text(filler()),
        ]),
      );
      final blocks = result.document!.blocks;
      expect(blocks.map((b) => b.type), [
        DocumentBlockType.paragraph,
        DocumentBlockType.image,
        DocumentBlockType.paragraph,
        DocumentBlockType.image,
        DocumentBlockType.paragraph,
      ]);
      expect(blocks[1].alt, 'The first figure');
      expect(result.imageRequests.map((r) => r.blockIndex), [1, 3]);
      expect(result.imageRequests.map((r) => r.assetIndex), [1, 2]);
    });

    test('the same image twice shares one asset and one download', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/same.png'),
          text(filler()),
          image('https://example.com/same.png'),
        ]),
      );
      final requests = result.imageRequests;
      expect(requests.map((r) => r.assetIndex), [1, 1]);
      expect(requests.map((r) => r.needsFetch), [true, false]);
    });

    test('text-only drops images entirely rather than leaving holes', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/a.png'),
          text(filler()),
        ]),
        mode: CaptureMode.textOnly,
      );
      expect(result.document!.blocks.any((b) => b.isImage), isFalse);
      expect(result.imageRequests, isEmpty);
      expect(result.document!.blockCount, 2);
    });

    test('a stored image gets its asset; a failed one keeps its place', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/ok.png'),
          text(filler()),
          image('https://example.com/broken.png'),
        ]),
      );
      final applied = applyImageResults(
        result.document!,
        requests: result.imageRequests,
        // Only the first landed.
        storedAssetIndexes: {1},
      );
      final images = applied.blocks.where((b) => b.isImage).toList();
      expect(images, hasLength(2));
      expect(images[0].assetIndex, 1);
      expect(images[0].hasStoredImage, isTrue);
      expect(images[1].assetIndex, isNull);
      // The position and the source survive even though the bytes did not.
      expect(images[1].imageSourceUrl, 'https://example.com/broken.png');
      expect(applied.missingImageBlocks, hasLength(1));
    });

    test('when every image fails the text is still a document', () {
      final result = run(
        doc([
          text(filler()),
          image('https://example.com/a.png'),
          image('https://example.com/b.png'),
        ]),
      );
      final applied = applyImageResults(
        result.document!,
        requests: result.imageRequests,
        storedAssetIndexes: const {},
      );
      expect(
        applied.blocks.any((b) => b.type == DocumentBlockType.paragraph),
        isTrue,
      );
      expect(applied.storedImageBlocks, isEmpty);
      expect(applied.missingImageBlocks, hasLength(2));
    });
  });

  group('emphasis', () {
    test('marks are kept as ranges over the stored text', () {
      final result = run(
        doc([
          text(
            'Some words matter more than others in this sentence about foxes.',
            marks: const [RawInlineMark(start: 5, end: 10, style: 'strong')],
          ),
          text(filler()),
        ]),
      );
      final mark = result.document!.blocks.first.safeMarks.single;
      expect(mark.style, InlineStyle.strong);
      expect(mark.start, 5);
      expect(mark.end, 10);
    });

    test('a mark that runs past the text is clamped, never thrown', () {
      final result = run(
        doc([
          text(
            'Short.',
            marks: const [RawInlineMark(start: 2, end: 900, style: 'emphasis')],
          ),
          text(filler()),
        ]),
      );
      final marks = result.document!.blocks.first.safeMarks;
      expect(marks.single.end, lessThanOrEqualTo(6));
    });

    test('a mark that collapses to nothing is dropped', () {
      final result = run(
        doc([
          text(
            'Body text.',
            marks: const [RawInlineMark(start: 900, end: 950, style: 'code')],
          ),
          text(filler()),
        ]),
      );
      expect(result.document!.blocks.first.marks, isEmpty);
    });

    test('an unknown mark style degrades to emphasis rather than failing', () {
      final result = run(
        doc([
          text(
            'Body text that is long enough to be kept by the extractor rules.',
            marks: const [RawInlineMark(start: 0, end: 4, style: 'blink')],
          ),
          text(filler()),
        ]),
      );
      expect(
        result.document!.blocks.first.safeMarks.single.style,
        InlineStyle.emphasis,
      );
    });
  });

  group('text handling', () {
    test('whitespace and invisible characters are collapsed', () {
      final result = run(
        doc([text('  Spaced out​ text \n\n  with   gaps.  '), text(filler())]),
      );
      expect(result.document!.blocks.first.text, 'Spaced out text with gaps.');
    });

    test('non-Latin prose survives verbatim', () {
      const turkish = 'Bir varmış, bir yokmuş. Uzun zaman önce, çok uzaklarda…';
      const japanese = 'むかしむかし、あるところに おじいさんと おばあさんが すんでいました。';
      const arabic = 'كان يا ما كان في قديم الزمان، في بلد بعيد جدا.';
      final result = run(
        doc([
          text(turkish),
          text(japanese),
          text(arabic),
          text(filler()),
        ], title: 'Üç Dilde Bir Hikâye'),
      );
      final blocks = result.document!.blocks;
      expect(blocks[0].text, turkish);
      expect(blocks[1].text, japanese);
      expect(blocks[2].text, arabic);
      expect(result.document!.title, 'Üç Dilde Bir Hikâye');
    });

    test('the title falls back to the page title when the region has none', () {
      final result = extractDocument(
        doc([text(filler())], title: ''),
        mode: CaptureMode.textOnly,
        sourceUrl: url,
        fallbackTitle: 'From the page title',
      );
      expect(result.document!.title, 'From the page title');
    });
  });

  group('failure is named, not guessed', () {
    test('a bridge that could not run is "unreadable"', () {
      final result = run(null);
      expect(result.isSuccess, isFalse);
      expect(result.failure, DocumentExtractionFailure.unreadable);
    });

    test('a page of nothing but furniture has no readable content', () {
      final result = run(
        doc([
          text('Home', chrome: true),
          text('About', chrome: true),
          text('Hidden note', hidden: true),
        ]),
      );
      expect(result.failure, DocumentExtractionFailure.noReadableContent);
    });

    test('an empty block list has no readable content', () {
      expect(
        run(doc(const [])).failure,
        DocumentExtractionFailure.noReadableContent,
      );
    });

    test('a headline and a byline is too little text', () {
      final result = run(
        doc([
          text('A Headline', kind: 'heading', level: 1),
          text('By someone'),
          text('2 min read'),
        ]),
      );
      expect(result.failure, DocumentExtractionFailure.tooLittleText);
    });

    test('malformed blocks do not take the extraction down', () {
      final result = run(
        doc([
          const RawDocumentBlock(kind: ''),
          const RawDocumentBlock(kind: 'paragraph', text: ''),
          const RawDocumentBlock(kind: 'heading', level: 99),
          const RawDocumentBlock(kind: 'listItem', level: -4, text: 'x'),
          const RawDocumentBlock(
            kind: 'image',
            src: '   ',
            width: 900,
            height: 900,
          ),
          text(filler()),
        ]),
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.blocks.last.text, isNotEmpty);
    });

    test('a heading level out of range is clamped into 1..6', () {
      final result = run(
        doc([text('Deep', kind: 'heading', level: 99), text(filler())]),
      );
      expect(result.document!.blocks.first.level, 6);
    });

    test('truncation is reported rather than hidden', () {
      final raw = RawDocument(
        title: 'Long',
        blocks: [text(filler()), text(filler())],
        truncated: true,
      );
      expect(run(raw).truncated, isTrue);
    });
  });

  group('round trip', () {
    test('a document survives encode and decode unchanged', () {
      final result = run(
        doc([
          text('Title Here', kind: 'heading', level: 2),
          text(
            'Emphasised prose that is long enough to be kept in the document.',
            marks: const [RawInlineMark(start: 0, end: 11, style: 'strong')],
          ),
          image('https://example.com/a.png', alt: 'A figure'),
          text('An item', kind: 'listItem', level: 1, ordered: true),
          text(filler()),
        ]),
      );
      final original = applyImageResults(
        result.document!,
        requests: result.imageRequests,
        storedAssetIndexes: {1},
      );
      final decoded = StructuredDocument.decode(original.encode());

      expect(decoded.schemaVersion, StructuredDocument.currentSchemaVersion);
      expect(decoded.title, original.title);
      expect(decoded.sourceUrl, url);
      expect(decoded.blockCount, original.blockCount);
      for (var i = 0; i < decoded.blockCount; i++) {
        final a = original.blocks[i];
        final b = decoded.blocks[i];
        expect(b.type, a.type);
        expect(b.text, a.text);
        expect(b.level, a.level);
        expect(b.ordered, a.ordered);
        expect(b.assetIndex, a.assetIndex);
        expect(b.alt, a.alt);
        expect(b.marks.length, a.marks.length);
      }
    });
  });
}
