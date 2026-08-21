/// The local structured-document model — what a text entry actually holds.
///
/// Deliberately **not** HTML. A saved page is stored as a list of typed blocks
/// with plain text and offset-based marks, so nothing in the library can carry
/// a script, a remote stylesheet, an iframe, an event handler or a tracking
/// pixel. The reader renders these blocks with Flutter widgets; there is no
/// HTML engine anywhere in the offline path, which is what makes "offline"
/// mean offline rather than "offline unless the page asks for something".
///
/// Pure Dart, no I/O and no Flutter, so the whole shape is testable against
/// literal fixtures.
library;

import 'dart:convert';

/// What one block of a saved document is.
///
/// Small on purpose. Every value here has a rendering in the reader and a
/// reason to survive extraction; anything the app cannot render honestly is
/// dropped at extraction time rather than stored as a shape nothing reads.
enum DocumentBlockType {
  heading,
  paragraph,
  quote,
  listItem,
  separator,

  /// A meaningful inline image. Carries the position it held between the text
  /// blocks — that ordering *is* the content, and is why images are blocks
  /// rather than a separate list bolted onto the side.
  image;

  static DocumentBlockType fromName(String? name) =>
      DocumentBlockType.values.firstWhere(
        (t) => t.name == name,
        // An unknown block type from a newer writer reads as prose rather than
        // vanishing: showing the text is always better than dropping it.
        orElse: () => DocumentBlockType.paragraph,
      );
}

/// Inline emphasis, as a range over the block's own text.
///
/// Offsets rather than nested spans: a flat range list cannot produce an
/// unbalanced tree, survives a round-trip through JSON unchanged, and is
/// trivially clamped when it disagrees with the text it describes.
enum InlineStyle {
  strong,
  emphasis,
  code;

  static InlineStyle fromName(String? name) => InlineStyle.values.firstWhere(
    (s) => s.name == name,
    orElse: () => InlineStyle.emphasis,
  );
}

/// One emphasis range. `[start, end)` in UTF-16 code units of the block text.
class InlineMark {
  const InlineMark({
    required this.start,
    required this.end,
    required this.style,
  });

  factory InlineMark.fromJson(Map<String, dynamic> json) => InlineMark(
    start: (json['start'] as num?)?.toInt() ?? 0,
    end: (json['end'] as num?)?.toInt() ?? 0,
    style: InlineStyle.fromName(json['style'] as String?),
  );

  final int start;
  final int end;
  final InlineStyle style;

  bool get isEmpty => end <= start;

  /// Pull the range inside `[0, length]`. A mark that describes text which is
  /// no longer there becomes empty rather than throwing at render time.
  InlineMark clampTo(int length) => InlineMark(
    start: start.clamp(0, length),
    end: end.clamp(0, length),
    style: style,
  );

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'style': style.name,
  };
}

/// One block of a saved document.
class DocumentBlock {
  const DocumentBlock({
    required this.index,
    required this.type,
    this.text = '',
    this.level = 0,
    this.ordered = false,
    this.assetIndex,
    this.imageSourceUrl,
    this.alt = '',
    this.marks = const [],
  });

  factory DocumentBlock.fromJson(Map<String, dynamic> json) => DocumentBlock(
    index: (json['index'] as num?)?.toInt() ?? 0,
    type: DocumentBlockType.fromName(json['type'] as String?),
    text: json['text']?.toString() ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    ordered: json['ordered'] == true,
    assetIndex: (json['assetIndex'] as num?)?.toInt(),
    imageSourceUrl: json['imageSourceUrl']?.toString(),
    alt: json['alt']?.toString() ?? '',
    marks: ((json['marks'] as List<dynamic>?) ?? const [])
        .map((e) => InlineMark.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
  );

  /// Zero-based reading order, and the **reading-position anchor**. Stable for
  /// the life of the stored document: the reader restores to a block index,
  /// which is layout-independent in a way a scroll offset can never be for
  /// reflowing text.
  final int index;

  final DocumentBlockType type;

  /// Plain text. Empty for [DocumentBlockType.separator] and
  /// [DocumentBlockType.image].
  final String text;

  /// Heading level 1–6, or list nesting depth for [DocumentBlockType.listItem].
  /// Zero for everything else.
  final int level;

  /// Numbered rather than bulleted. Only meaningful for a list item.
  final bool ordered;

  /// The [EntryAsset.index] holding this image's bytes, or **null when the
  /// image was not stored** — either the download failed or the entry was
  /// saved as text only. Null is a real state the reader renders as a
  /// placeholder; it is never treated as a missing file.
  final int? assetIndex;

  /// Where the image came from, kept even when the bytes were not. It is what
  /// an honest "this image was not saved" placeholder stands on.
  final String? imageSourceUrl;

  /// The page's own alt text, kept verbatim for accessibility and for the
  /// placeholder caption.
  final String alt;

  final List<InlineMark> marks;

  bool get isImage => type == DocumentBlockType.image;
  bool get hasStoredImage => isImage && assetIndex != null;

  /// Marks pulled inside this block's text, dropping any that collapsed.
  List<InlineMark> get safeMarks => [
    for (final m in marks)
      if (!m.clampTo(text.length).isEmpty) m.clampTo(text.length),
  ];

  DocumentBlock copyWith({
    int? index,
    int? assetIndex,
    bool clearAsset = false,
  }) => DocumentBlock(
    index: index ?? this.index,
    type: type,
    text: text,
    level: level,
    ordered: ordered,
    assetIndex: clearAsset ? null : (assetIndex ?? this.assetIndex),
    imageSourceUrl: imageSourceUrl,
    alt: alt,
    marks: marks,
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'type': type.name,
    if (text.isNotEmpty) 'text': text,
    if (level != 0) 'level': level,
    if (ordered) 'ordered': true,
    if (assetIndex != null) 'assetIndex': assetIndex,
    if (imageSourceUrl != null) 'imageSourceUrl': imageSourceUrl,
    if (alt.isNotEmpty) 'alt': alt,
    if (marks.isNotEmpty) 'marks': [for (final m in marks) m.toJson()],
  };
}

/// A saved readable document.
///
/// Written to `document.json` **beside** the bytes it describes, for the same
/// reason the page list lives in `manifest.json`: an entry directory that
/// describes itself can be recovered without the database, and a second copy
/// in SQLite would be a cache that can disagree with the files.
///
/// Kept out of the manifest itself so that manifest scanning — which recovery
/// does for every entry on disk at startup — stays cheap. A long text entry
/// is hundreds of kilobytes of prose; the manifest stays a few hundred bytes.
class StructuredDocument {
  const StructuredDocument({
    required this.schemaVersion,
    required this.title,
    required this.sourceUrl,
    required this.blocks,
  });

  factory StructuredDocument.fromJson(Map<String, dynamic> json) =>
      StructuredDocument(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        title: json['title']?.toString() ?? '',
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        blocks: ((json['blocks'] as List<dynamic>?) ?? const [])
            .map(
              (e) =>
                  DocumentBlock.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false),
      );

  factory StructuredDocument.decode(String jsonText) =>
      StructuredDocument.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);

  /// One. There is no earlier shape: structured documents did not exist before
  /// manifest schema 2, so nothing on disk can carry version 0.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String title;
  final String sourceUrl;
  final List<DocumentBlock> blocks;

  int get blockCount => blocks.length;

  /// Characters of prose. The measure the extractor's "is this actually
  /// readable" floor is applied to, and what the details sheet reports.
  int get textLength =>
      blocks.fold(0, (sum, b) => sum + (b.isImage ? 0 : b.text.length));

  /// Image blocks whose bytes are on disk.
  Iterable<DocumentBlock> get storedImageBlocks =>
      blocks.where((b) => b.hasStoredImage);

  /// Image blocks whose bytes are *not* on disk — a failed download, or a
  /// text-only save that kept the position but not the picture.
  Iterable<DocumentBlock> get missingImageBlocks =>
      blocks.where((b) => b.isImage && b.assetIndex == null);

  bool get isEmpty => blocks.isEmpty;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'title': title,
    'sourceUrl': sourceUrl,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
