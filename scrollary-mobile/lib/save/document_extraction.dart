/// Turning what the page reported into what gets stored.
///
/// The browser half (`bridge_script.dart`) measures and flags; **this half
/// decides**. That split is the same one `content_detection.dart` makes and for
/// the same reason: a rule that determines what a user's offline copy contains
/// has to be testable against a literal fixture, not only through a live
/// WebView on a real website.
///
/// Pure Dart, no I/O, no Flutter.
library;

import '../browser/page_data.dart';
import '../storage/document.dart';
import 'capture_mode.dart';

/// A document must carry at least this much prose to be worth storing.
///
/// Below it, "saved" would mean a headline and a cookie notice. The save
/// reports an honest extraction failure instead, which is a different outcome
/// from a page that genuinely has no text.
const int kMinExtractedTextLength = 200;

/// Text shorter than this in a single block is furniture — a byline fragment,
/// a "3 min read", a stray label — unless it is a heading, which is allowed to
/// be short because headings are.
const int kMinParagraphLength = 2;

/// Why nothing could be stored.
enum DocumentExtractionFailure {
  /// The bridge could not run, or returned nothing at all.
  unreadable,

  /// Blocks came back, but everything was chrome, hidden or empty.
  noReadableContent,

  /// Real prose, but not enough of it to be an entry.
  tooLittleText;

  String get message => switch (this) {
    DocumentExtractionFailure.unreadable =>
      'The page could not be read for text.',
    DocumentExtractionFailure.noReadableContent =>
      'No readable text was found on this page.',
    DocumentExtractionFailure.tooLittleText =>
      'This page has too little readable text to save.',
  };
}

/// What extraction produced: a document, or a named reason there is none.
class DocumentExtraction {
  const DocumentExtraction.success(
    this.document, {
    this.imageRequests = const [],
    this.droppedBlocks = 0,
    this.truncated = false,
    this.regionBasis = '',
  }) : failure = null;

  const DocumentExtraction.failed(this.failure, {this.regionBasis = ''})
    : document = null,
      imageRequests = const [],
      droppedBlocks = 0,
      truncated = false;

  final StructuredDocument? document;

  /// Images the caller should download, in document order. Each carries the
  /// block index it belongs to, so a failure can be attributed to the right
  /// place in the text instead of to a position in a flat list.
  final List<InlineImageRequest> imageRequests;

  /// How many candidate blocks were discarded. Logged, so "the save kept
  /// half the page" is answerable.
  final int droppedBlocks;

  final bool truncated;
  final String regionBasis;
  final DocumentExtractionFailure? failure;

  bool get isSuccess => document != null;
}

/// One inline image to fetch, tied to the block that will show it.
class InlineImageRequest {
  const InlineImageRequest({
    required this.blockIndex,
    required this.assetIndex,
    required this.url,
    required this.width,
    required this.height,
    this.needsFetch = true,
  });

  final int blockIndex;

  /// 1-based, matching `EntryAsset.index`, so the manifest and the document
  /// agree without either having to know the other's ordering rules.
  final int assetIndex;

  final String url;
  final int width;
  final int height;

  /// False for the second and later appearances of the same image, which share
  /// the first one's asset instead of downloading it again.
  final bool needsFetch;
}

/// Build a storable document out of the page's reported blocks.
///
/// [mode] decides what happens to images:
///
/// * [CaptureMode.textAndImages] keeps each meaningful image as a block and
///   asks for its bytes.
/// * [CaptureMode.textOnly] drops image blocks entirely. Not "keeps the
///   position without the picture" — the user asked for text, and a column of
///   grey placeholders down a long text entry is not what they asked for.
DocumentExtraction extractDocument(
  RawDocument? raw, {
  required CaptureMode mode,
  required String sourceUrl,
  String fallbackTitle = '',
}) {
  if (raw == null) {
    return const DocumentExtraction.failed(
      DocumentExtractionFailure.unreadable,
    );
  }

  final kept = <DocumentBlock>[];
  final requests = <InlineImageRequest>[];

  // The same illustration can legitimately appear twice in one document, and
  // both places should show it. Downloading it twice should not follow from
  // that, so a repeated URL reuses the asset it already has.
  final assetForUrl = <String, int>{};
  var dropped = 0;
  var nextAssetIndex = 1;

  for (final block in raw.blocks) {
    // Furniture and invisible content never reach storage, whatever they say.
    if (block.inChrome || block.hidden) {
      dropped++;
      continue;
    }

    final type = _typeOf(block.kind);
    if (type == null) {
      dropped++;
      continue;
    }

    switch (type) {
      case DocumentBlockType.image:
        final url = block.src?.trim();
        final meaningful =
            url != null &&
            url.isNotEmpty &&
            block.width >= kMinInlineImageEdge &&
            block.height >= kMinInlineImageEdge;
        if (!meaningful) {
          dropped++;
          continue;
        }
        if (!mode.fetchesImages) {
          // Text only: the picture is not wanted and neither is a hole where
          // it was.
          dropped++;
          continue;
        }
        final index = kept.length;
        final asset = assetForUrl[url] ?? nextAssetIndex;
        final isNew = !assetForUrl.containsKey(url);
        if (isNew) {
          assetForUrl[url] = asset;
          nextAssetIndex++;
        }
        kept.add(
          DocumentBlock(
            index: index,
            type: DocumentBlockType.image,
            imageSourceUrl: url,
            alt: block.alt.trim(),
          ),
        );
        requests.add(
          InlineImageRequest(
            blockIndex: index,
            assetIndex: asset,
            url: url,
            width: block.width,
            height: block.height,
            // Only the first appearance is downloaded; the rest point at the
            // asset it produces.
            needsFetch: isNew,
          ),
        );

      case DocumentBlockType.separator:
        // A rule between two blocks is structure; one at the very top or
        // repeated is decoration.
        if (kept.isEmpty || kept.last.type == DocumentBlockType.separator) {
          dropped++;
          continue;
        }
        kept.add(
          DocumentBlock(index: kept.length, type: DocumentBlockType.separator),
        );

      case DocumentBlockType.heading:
      case DocumentBlockType.paragraph:
      case DocumentBlockType.quote:
      case DocumentBlockType.listItem:
        final text = _collapse(block.text);
        if (text.isEmpty) {
          dropped++;
          continue;
        }
        if (type != DocumentBlockType.heading &&
            text.length < kMinParagraphLength) {
          dropped++;
          continue;
        }
        kept.add(
          DocumentBlock(
            index: kept.length,
            type: type,
            text: text,
            level: type == DocumentBlockType.heading
                ? block.level.clamp(1, 6)
                : (type == DocumentBlockType.listItem
                      ? block.level.clamp(1, 6)
                      : 0),
            ordered: type == DocumentBlockType.listItem && block.ordered,
            marks: _marks(block, text.length),
          ),
        );
    }
  }

  // A trailing separator has nothing to separate.
  while (kept.isNotEmpty && kept.last.type == DocumentBlockType.separator) {
    kept.removeLast();
    dropped++;
  }

  if (kept.isEmpty) {
    return DocumentExtraction.failed(
      DocumentExtractionFailure.noReadableContent,
      regionBasis: raw.regionBasis,
    );
  }

  final document = StructuredDocument(
    schemaVersion: StructuredDocument.currentSchemaVersion,
    title: _collapse(raw.title.isEmpty ? fallbackTitle : raw.title),
    sourceUrl: sourceUrl,
    blocks: kept,
  );

  if (document.textLength < kMinExtractedTextLength) {
    return DocumentExtraction.failed(
      DocumentExtractionFailure.tooLittleText,
      regionBasis: raw.regionBasis,
    );
  }

  return DocumentExtraction.success(
    document,
    imageRequests: requests,
    droppedBlocks: dropped,
    truncated: raw.truncated,
    regionBasis: raw.regionBasis,
  );
}

/// Attach the results of downloading the inline images.
///
/// [storedAssetIndexes] holds the asset indexes whose bytes actually landed.
/// A block whose image failed keeps its place and its source URL with a null
/// `assetIndex` — the reader renders that as an honest "this image was not
/// saved" gap rather than as a broken file, and the entry is `partial` rather
/// than pretending to be whole.
StructuredDocument applyImageResults(
  StructuredDocument document, {
  required List<InlineImageRequest> requests,
  required Set<int> storedAssetIndexes,
}) {
  final byBlock = {for (final r in requests) r.blockIndex: r};

  DocumentBlock resolve(DocumentBlock block) {
    if (!block.isImage) return block;
    final asset = byBlock[block.index]?.assetIndex;
    final stored = asset != null && storedAssetIndexes.contains(asset);
    return DocumentBlock(
      index: block.index,
      type: DocumentBlockType.image,
      assetIndex: stored ? asset : null,
      imageSourceUrl: block.imageSourceUrl,
      alt: block.alt,
    );
  }

  return StructuredDocument(
    schemaVersion: document.schemaVersion,
    title: document.title,
    sourceUrl: document.sourceUrl,
    blocks: [for (final block in document.blocks) resolve(block)],
  );
}

DocumentBlockType? _typeOf(String kind) {
  for (final type in DocumentBlockType.values) {
    if (type.name == kind) return type;
  }
  return null;
}

/// Collapse runs of whitespace, including the non-breaking spaces and
/// zero-width characters that page markup is full of.
///
/// Deliberately does not touch anything else: prose is stored exactly as the
/// source wrote it, in whatever script it wrote it in.
String _collapse(String text) => text
    // Escapes rather than the characters themselves: an invisible literal in
    // source is unreviewable, and this list is exactly the set of invisible
    // characters page markup is full of.
    .replaceAll('\u00A0', ' ')
    .replaceAll('\u202F', ' ')
    .replaceAll(RegExp('[\u200B-\u200F\u2060\uFEFF]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Marks pulled inside the block's final text, dropped when they collapsed.
///
/// Whitespace collapsing can shorten the text under a mark the page reported,
/// so every range is clamped rather than trusted — an out-of-range span would
/// be a crash at render time on somebody's saved novel.
List<InlineMark> _marks(RawDocumentBlock block, int length) {
  final out = <InlineMark>[];
  for (final raw in block.marks) {
    final mark = InlineMark(
      start: raw.start,
      end: raw.end,
      style: InlineStyle.fromName(raw.style),
    ).clampTo(length);
    if (!mark.isEmpty) out.add(mark);
  }
  return out;
}
