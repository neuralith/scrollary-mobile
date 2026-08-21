/// The offline reader's **structured-document** path.
///
/// A sibling to the image reader in `reader_screen.dart`, not a replacement:
/// that screen still owns the chrome, the progress writes, the completion
/// rule, entry navigation and cleanup, and it hands the body to whichever of
/// the two matches the entry's `ArtifactFormat`. Only the scrolling content
/// differs, because only the scrolling content is artifact-specific.
///
/// Nothing here renders HTML. Blocks are typed, their text is plain, and their
/// emphasis is a list of offset ranges — so a saved page cannot carry a script,
/// reach the network, or lay out differently than the reader intends.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../reading/reading_position.dart';
import '../storage/document.dart';
import '../storage/manifest.dart';
import '../reading/decode_budget.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart' show serifStyle;
import '../ui/theme.dart' show wght;

/// Reading measure. Prose set much wider than this is measurably harder to
/// read, so the column is capped and centred rather than filling a tablet.
const double kDocumentMaxWidth = 660;

/// Horizontal breathing room on a phone, where the cap never binds.
const double kDocumentSideInset = 22;

/// The document body: a measured column of blocks.
///
/// **Why a `Column` and not a `ListView.builder`.** Restoring a reading
/// position in reflowing text needs the *real* offset of the anchor block, and
/// a lazily-built list does not know the offset of a block it has not built.
/// Building the whole document makes every offset exact, which is what lets
/// restore land on the paragraph the reader left rather than near it. The cost
/// is bounded on purpose: extraction caps a document's blocks, and a text
/// block is among the cheapest widgets Flutter has.
class DocumentBody extends StatefulWidget {
  const DocumentBody({
    super.key,
    required this.document,
    required this.manifest,
    required this.entryDir,
    required this.controller,
    required this.leadingExtent,
    required this.onLayout,
    this.banner,
    this.trailing,
  });

  final StructuredDocument document;
  final EntryManifest manifest;

  /// Absolute directory holding this entry's files, for resolving the
  /// document's inline images. Local paths only — this reader never has a
  /// remote URL to fall back to, which is what makes "offline" true.
  final Directory entryDir;

  final ScrollController controller;

  /// Everything above the first block, so offsets computed here and offsets
  /// used by the scroll controller agree.
  final double leadingExtent;

  /// Called once the blocks have been measured, and again after a reflow
  /// (rotation, text-scale change) moves them.
  final ValueChanged<DocumentLayout> onLayout;

  /// The partial-save banner, when there is one.
  final Widget? banner;

  /// The end-of-entry block.
  final Widget? trailing;

  @override
  State<DocumentBody> createState() => _DocumentBodyState();
}

class _DocumentBodyState extends State<DocumentBody> {
  /// One key per block, used to read back its laid-out position. Kept in a
  /// field so a rebuild measures the same elements rather than new ones.
  late List<GlobalKey> _keys;
  final GlobalKey _columnKey = GlobalKey();

  /// The measurement last published, so a reflow that changes nothing does not
  /// churn the parent.
  double _lastTotal = -1;
  double _lastFirstOffset = -1;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(
      widget.document.blocks.length,
      (_) => GlobalKey(),
      growable: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(DocumentBody old) {
    super.didUpdateWidget(old);
    if (old.document.blockCount != widget.document.blockCount) {
      _keys = List.generate(
        widget.document.blocks.length,
        (_) => GlobalKey(),
        growable: false,
      );
      _lastTotal = -1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Read every block's offset and height out of the laid-out tree.
  ///
  /// Offsets are taken **relative to the column**, not to the screen, so the
  /// numbers mean the same thing whatever the scroll position happens to be
  /// when the measurement runs.
  void _measure() {
    if (!mounted) return;
    final columnBox = _columnKey.currentContext?.findRenderObject();
    if (columnBox is! RenderBox || !columnBox.hasSize) return;

    final offsets = <double>[];
    final heights = <double>[];
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        // A block that has not been laid out yet: publish nothing rather than
        // a layout with a hole in it, and try again next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return;
      }
      final local = box.localToGlobal(Offset.zero, ancestor: columnBox);
      offsets.add(local.dy);
      heights.add(box.size.height);
    }

    final total = columnBox.size.height;
    if (total == _lastTotal &&
        offsets.isNotEmpty &&
        offsets.first == _lastFirstOffset) {
      return;
    }
    _lastTotal = total;
    _lastFirstOffset = offsets.isEmpty ? -1 : offsets.first;

    widget.onLayout(
      DocumentLayout(offsets: offsets, heights: heights, totalHeight: total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final blocks = widget.document.blocks;

    return SingleChildScrollView(
      controller: widget.controller,
      padding: EdgeInsets.only(top: widget.leadingExtent),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kDocumentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDocumentSideInset),
            child: Column(
              key: _columnKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.banner != null) widget.banner!,
                for (var i = 0; i < blocks.length; i++)
                  DocumentBlockView(
                    key: _keys[i],
                    block: blocks[i],
                    manifest: widget.manifest,
                    entryDir: widget.entryDir,
                    palette: palette,
                  ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One rendered block.
class DocumentBlockView extends StatelessWidget {
  const DocumentBlockView({
    super.key,
    required this.block,
    required this.manifest,
    required this.entryDir,
    required this.palette,
  });

  final DocumentBlock block;
  final EntryManifest manifest;
  final Directory entryDir;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      DocumentBlockType.heading => _heading(),
      DocumentBlockType.paragraph => _paragraph(),
      DocumentBlockType.quote => _quote(),
      DocumentBlockType.listItem => _listItem(),
      DocumentBlockType.separator => _separator(),
      DocumentBlockType.image => _image(context),
    };
  }

  Widget _heading() {
    // Levels compress towards the body size: a saved page's h4 is not four
    // steps more important than its body text, it is just a subheading.
    final size = switch (block.level) {
      <= 1 => 26.0,
      2 => 21.0,
      3 => 18.0,
      _ => 16.0,
    };
    return Padding(
      padding: EdgeInsets.only(top: block.level <= 2 ? 28 : 22, bottom: 8),
      child: Text(
        block.text,
        style: serifStyle(size: size, color: palette.ink).copyWith(height: 1.3),
      ),
    );
  }

  Widget _paragraph() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text.rich(
      _spans(TextStyle(fontSize: 16.5, height: 1.62, color: palette.ink)),
    ),
  );

  Widget _quote() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.primaryBorder, width: 3),
        ),
      ),
      child: Text.rich(
        _spans(
          TextStyle(
            fontSize: 15.5,
            height: 1.6,
            color: palette.inkMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ),
  );

  Widget _listItem() {
    final depth = (block.level - 1).clamp(0, 4);
    return Padding(
      padding: EdgeInsets.only(left: 6 + depth * 16.0, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 10),
            child: Text(
              // The source's own numbering is not stored — only whether the
              // list was ordered — so an ordered item gets a neutral marker
              // rather than a number this app invented.
              block.ordered ? '—' : '•',
              style: TextStyle(fontSize: 15, color: palette.inkFaint),
            ),
          ),
          Expanded(
            child: Text.rich(
              _spans(TextStyle(fontSize: 16, height: 1.55, color: palette.ink)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _separator() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: SizedBox(
        width: 64,
        child: Divider(thickness: 1, color: palette.hairline),
      ),
    ),
  );

  Widget _image(BuildContext context) {
    final asset = block.assetIndex == null
        ? null
        : manifest.assetByIndex(block.assetIndex!);
    final relative = asset?.relativePath;

    if (relative == null) {
      return _missingImage();
    }

    final file = File('${entryDir.path}/$relative');
    if (!file.existsSync()) return _missingImage(fileGone: true);

    // A document builds every block eagerly — that is what makes its restore
    // offsets exact — so all of its inline images are resident at once and the
    // per-image decode size is multiplied by the whole document. Never decode
    // wider than the file is, and cap the pathological case (decode_budget.dart).
    final media = MediaQuery.of(context);
    // Only dimensions read back from the stored bytes may bound a decode.
    // `EntryAsset.width` is otherwise whatever the *page* claimed, which is
    // diagnostics — trusting it could ask for fewer pixels than the file has
    // and quietly soften the image. Unverified means "do not bound".
    final verified = asset != null && asset.dimensionsVerified;
    final naturalWidth = verified ? asset.width : null;
    final naturalHeight = verified ? asset.height : null;
    final decodeWidth = decodeWidthWithinBudget(
      width:
          decodeWidthFor(
            displayWidth: media.size.width,
            devicePixelRatio: media.devicePixelRatio,
            naturalWidth: naturalWidth,
          ) ??
          1,
      naturalWidth: naturalWidth,
      naturalHeight: naturalHeight,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              cacheWidth: decodeWidth,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _missingImage(fileGone: true),
            ),
          ),
          if (block.alt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.alt,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: palette.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// An image that is part of the document but not on the device.
  ///
  /// Says which of the two it is. "This image was not saved" (a text-only
  /// save, or a download that failed) and "the file is gone" are different
  /// facts, and the reader should not have to guess which happened.
  Widget _missingImage({bool fileGone = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: palette.inkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                fileGone
                    ? 'This image is no longer on the device.'
                    : 'This image was not saved.',
                if (block.alt.isNotEmpty) block.alt,
              ].join(' '),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.inkFaint,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// Text plus its emphasis ranges, as one span tree.
  ///
  /// Ranges are already clamped to the text at extraction time and clamped
  /// again by [DocumentBlock.safeMarks], so a mark that disagrees with the
  /// prose degrades to plain text instead of throwing inside somebody's saved
  /// novel.
  TextSpan _spans(TextStyle base) {
    final marks = block.safeMarks.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (marks.isEmpty) return TextSpan(text: block.text, style: base);

    final children = <TextSpan>[];
    var cursor = 0;
    for (final mark in marks) {
      if (mark.start < cursor) continue; // overlapping: first one wins
      if (mark.start > cursor) {
        children.add(TextSpan(text: block.text.substring(cursor, mark.start)));
      }
      children.add(
        TextSpan(
          text: block.text.substring(mark.start, mark.end),
          style: switch (mark.style) {
            InlineStyle.strong => TextStyle(
              fontWeight: FontWeight.w600,
              fontVariations: wght(600),
            ),
            InlineStyle.emphasis => const TextStyle(
              fontStyle: FontStyle.italic,
            ),
            InlineStyle.code => TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontSize: base.fontSize == null ? null : base.fontSize! - 1.5,
            ),
          },
        ),
      );
      cursor = mark.end;
    }
    if (cursor < block.text.length) {
      children.add(TextSpan(text: block.text.substring(cursor)));
    }
    return TextSpan(style: base, children: children);
  }
}
