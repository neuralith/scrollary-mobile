/// What the user asked a save to produce, and what a given page can honestly
/// offer.
///
/// Three concepts are kept apart on purpose, and conflating any two of them is
/// what produced a library where every entry was an image list:
///
/// * **`ContentKind`** (`library/content_shape.dart`) — what the *page* is.
///   Detected, confidence-graded, and correctable by the user.
/// * **[CaptureMode]** — what the *save* was asked to do. Chosen by the user
///   from what detection says is possible, or defaulted from it.
/// * **`ArtifactFormat`** (`storage/manifest.dart`) — what the stored package
///   actually *holds*. The only one the reader is allowed to switch on.
///
/// A page classified `article` can be captured as `imageSequence` if the user
/// insists and the images are there; a page classified `imageDominant` can be
/// captured as `textOnly` if it also carries prose. Neither is a contradiction,
/// which is precisely why one field could not carry all three.
library;

import '../browser/page_data.dart';
import '../core/config.dart';
import '../library/content_shape.dart';
import '../storage/manifest.dart';
import 'content_detection.dart';
import 'image_candidates.dart';

/// How much readable prose a page must carry before a text mode is offered.
///
/// Lower than `PageContentSignals.looksProse` (900) on purpose: that threshold
/// answers "is this page *about* its prose", which is a classification
/// question. This one answers "would saving the text produce something worth
/// reading offline", and a 600-character note is.
const int kMinReadableTextLength = 600;

/// And at least this many paragraphs, so a single long run of navigation text
/// cannot pass as an article.
const int kMinReadableParagraphs = 2;

/// A content-region image must be at least this big on both edges to count as
/// *meaningful* rather than as an avatar, an icon or a share button.
///
/// Deliberately well below `SaveConfig.minImageEdge` (300), which guards the
/// image-*sequence* pipeline: a 240px diagram in an article is meaningful
/// content even though it would never survive the image-sequence clustering.
const int kMinInlineImageEdge = 200;

/// What a save should produce.
///
/// There is deliberately **no video value**. Video capture is not implemented,
/// and a mode the engine cannot honour must never appear in this enum — the
/// save sheet is built from these values, so an unhonourable one would become
/// a button that lies. The future-video seam is `ArtifactFormat`, which is a
/// statement about stored bytes rather than about an offer made to a user.
enum CaptureMode {
  /// Ordered full-size images, no text. The original behaviour.
  imageSequence,

  /// A structured document and nothing else. Content images are not
  /// downloaded and decorative ones are not kept.
  textOnly,

  /// A structured document plus the meaningful inline images, each keeping its
  /// position between the text blocks.
  textAndImages;

  /// The artifact this mode produces. The mapping is fixed and total: every
  /// mode has exactly one stored shape, which is what lets the reader trust
  /// the manifest's discriminator.
  ArtifactFormat get artifact => switch (this) {
    CaptureMode.imageSequence => ArtifactFormat.imageSequence,
    CaptureMode.textOnly ||
    CaptureMode.textAndImages => ArtifactFormat.structuredDocument,
  };

  bool get isDocument => artifact == ArtifactFormat.structuredDocument;

  /// Whether this mode downloads images at all.
  bool get fetchesImages => this != CaptureMode.textOnly;

  /// Short label for the save sheet and the details sheet.
  String get label => switch (this) {
    CaptureMode.imageSequence => 'Images only',
    CaptureMode.textOnly => 'Text only',
    CaptureMode.textAndImages => 'Text and images',
  };

  /// One line explaining what this mode will store.
  String get description => switch (this) {
    CaptureMode.imageSequence => 'Save the page images in order, with no text.',
    CaptureMode.textOnly => 'Save the readable text. No images are downloaded.',
    CaptureMode.textAndImages =>
      'Save the readable text with the images that sit inside it.',
  };
}

/// Parse a stored mode name.
///
/// Returns **null** for anything unrecognised rather than falling back to a
/// value. There is no "safest" capture mode — every one of them is a different
/// artifact — so an unreadable preference has to mean "ask detection again",
/// not "quietly save something else".
CaptureMode? captureModeFromName(String? name) {
  if (name == null) return null;
  for (final mode in CaptureMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

/// Why a mode is not on offer for this page.
enum ModeBlockReason {
  /// Not enough large, similarly-sized images to form a sequence.
  noImageSequence,

  /// Too little readable prose to be worth saving as a document.
  noReadableText,

  /// Readable prose exists, but no image inside it is big enough to matter.
  /// Text-only is still on offer; only *text and images* is pointless.
  noMeaningfulImages;

  String get message => switch (this) {
    ModeBlockReason.noImageSequence =>
      'This page does not have enough full-size images to save as an image '
          'sequence.',
    ModeBlockReason.noReadableText =>
      'No readable text was found on this page.',
    ModeBlockReason.noMeaningfulImages =>
      'No images were found inside the readable text.',
  };
}

/// What a page can honestly be saved as, and what to preselect.
///
/// Built once per page, before the save sheet opens, so the sheet offers what
/// is actually possible instead of failing after the choice. Every mode the
/// sheet shows as available is one `SaveEngine` can carry out.
class CaptureCapabilities {
  const CaptureCapabilities({
    required this.content,
    required this.available,
    required this.blocked,
    this.defaultMode,
    this.videoDominant = false,
    this.analysed = true,
  });

  /// Nothing could be measured — the bridge was blocked, or the page was not
  /// ready. Every mode is offered, the image sequence is preselected because
  /// that is what this app did before it could tell the difference, and the
  /// sheet says plainly that the page was not analysed.
  const CaptureCapabilities.unanalysed()
    : content = const ContentShape(basis: 'the page could not be analysed'),
      available = const {
        CaptureMode.imageSequence,
        CaptureMode.textOnly,
        CaptureMode.textAndImages,
      },
      blocked = const {},
      defaultMode = CaptureMode.imageSequence,
      videoDominant = false,
      analysed = false;

  /// The detected page classification, with its confidence and evidence.
  final ContentShape content;

  /// Modes `SaveEngine` can genuinely carry out on this page.
  final Set<CaptureMode> available;

  /// Why each unavailable mode is unavailable. The sheet shows these rather
  /// than hiding the option, so "why can I not save the text" has an answer.
  final Map<CaptureMode, ModeBlockReason> blocked;

  /// What to preselect, or **null when nothing can be saved**.
  final CaptureMode? defaultMode;

  /// The page is primarily a video. Video is not saved; this drives the copy
  /// that says so.
  final bool videoDominant;

  /// False when the page could not be measured at all.
  final bool analysed;

  bool get canSaveAnything => available.isNotEmpty && defaultMode != null;

  bool allows(CaptureMode mode) => available.contains(mode);

  /// Apply a remembered or requested mode, falling back when the page cannot
  /// honour it. Never returns an unavailable mode.
  ///
  /// This is the one place a stale collection preference is stopped from
  /// forcing an impossible save: the preference proposes, the page disposes.
  CaptureResolution resolve(CaptureMode? requested) {
    if (requested == null) {
      return CaptureResolution(mode: defaultMode);
    }
    if (allows(requested)) {
      return CaptureResolution(mode: requested, honoured: true);
    }
    return CaptureResolution(
      mode: defaultMode,
      honoured: false,
      requested: requested,
      reason: blocked[requested],
    );
  }
}

/// The outcome of applying a requested mode to a page's real capabilities.
class CaptureResolution {
  const CaptureResolution({
    required this.mode,
    this.honoured = true,
    this.requested,
    this.reason,
  });

  /// What will actually be used, or null when the page can hold nothing.
  final CaptureMode? mode;

  /// False when [requested] could not be applied and [mode] is a fallback.
  final bool honoured;

  final CaptureMode? requested;
  final ModeBlockReason? reason;

  bool get didFallBack => !honoured && mode != null;

  /// A sentence naming what was asked for, what happened instead, and why.
  /// Logged on the run and shown to the user — a silent substitution is the
  /// failure this exists to prevent.
  String? get explanation {
    if (honoured || requested == null) return null;
    final why = reason?.message ?? 'this page cannot be saved that way.';
    final fallback = mode;
    if (fallback == null) {
      return '"${requested!.label}" is not possible here — $why';
    }
    return '"${requested!.label}" is not possible here — $why '
        'Saving as "${fallback.label}" instead.';
  }
}

/// Work out what this page can be saved as.
///
/// Every rule is a measurement over [probe]; there is no hostname, no selector
/// and no site list, exactly as in `content_detection.dart`. Pure, so the
/// whole decision table is unit-testable against literal probes.
CaptureCapabilities detectCaptureCapabilities(
  PageProbe probe, {
  SaveConfig config = kDefaultSaveConfig,
}) {
  final content = detectContentKind(probe);
  final c = probe.content;

  // An image *sequence* is what the existing pipeline can produce: enough
  // large, similarly-sized images to survive candidate selection. Asking the
  // real selector rather than re-deriving a threshold means the sheet cannot
  // offer a sequence the engine would then refuse.
  final sequence = selectImageCandidates(probe.images, config: config);
  final hasImageSequence = sequence.acceptedCount >= config.minCandidates;

  final hasReadableText =
      c.textLength >= kMinReadableTextLength &&
      c.paragraphCount >= kMinReadableParagraphs;

  // Meaningful *inline* images: inside the readable region, big enough to be
  // content. A page can have a hundred thumbnails in a sidebar and none here.
  final hasInlineImages = c.contentRegionImageCount > 0;

  final videoDominant = content.kind == ContentKind.videoDominant;

  final available = <CaptureMode>{};
  final blocked = <CaptureMode, ModeBlockReason>{};

  if (hasImageSequence) {
    available.add(CaptureMode.imageSequence);
  } else {
    blocked[CaptureMode.imageSequence] = ModeBlockReason.noImageSequence;
  }

  if (hasReadableText) {
    available.add(CaptureMode.textOnly);
    if (hasInlineImages) {
      available.add(CaptureMode.textAndImages);
    } else {
      blocked[CaptureMode.textAndImages] = ModeBlockReason.noMeaningfulImages;
    }
  } else {
    blocked[CaptureMode.textOnly] = ModeBlockReason.noReadableText;
    blocked[CaptureMode.textAndImages] = ModeBlockReason.noReadableText;
  }

  // Nothing confidently offerable, and not a video page: the page is simply
  // unclassifiable. Attempting the image sequence is what this app did before
  // it could tell the difference, and — crucially — it is the only path with
  // **user assistance** behind it: too few candidates ends in "point at the
  // reader area", which is exactly the help such a page needs.
  //
  // Done here rather than in the engine so the save sheet and the engine read
  // the same answer. A sheet that says "nothing can be saved" while the engine
  // would have tried, and asked, is the same class of lie as offering a mode
  // the engine cannot honour.
  if (available.isEmpty && !videoDominant) {
    available.add(CaptureMode.imageSequence);
    blocked.remove(CaptureMode.imageSequence);
  }

  return CaptureCapabilities(
    content: content,
    available: available,
    blocked: blocked,
    videoDominant: videoDominant,
    defaultMode: _defaultMode(
      kind: content.kind,
      available: available,
      hasInlineImages: hasInlineImages,
    ),
  );
}

/// Which of the available modes to preselect.
///
/// The order encodes one idea: **preselect what the page mostly is.** An
/// image-dominant page defaults to images even though its caption text might
/// pass the readable floor; a prose page defaults to text even when it has
/// enough pictures to form a sequence.
CaptureMode? _defaultMode({
  required ContentKind kind,
  required Set<CaptureMode> available,
  required bool hasInlineImages,
}) {
  if (available.isEmpty) return null;

  CaptureMode? textDefault() {
    if (hasInlineImages && available.contains(CaptureMode.textAndImages)) {
      return CaptureMode.textAndImages;
    }
    return available.contains(CaptureMode.textOnly)
        ? CaptureMode.textOnly
        : null;
  }

  switch (kind) {
    case ContentKind.imageDominant:
      if (available.contains(CaptureMode.imageSequence)) {
        return CaptureMode.imageSequence;
      }
    case ContentKind.article:
    case ContentKind.datedPost:
    case ContentKind.sequentialText:
    case ContentKind.longFormDocument:
    case ContentKind.paginatedDocument:
      final text = textDefault();
      if (text != null) return text;
    case ContentKind.videoDominant:
      // Video is not saved. Whatever readable content the page *also* has is
      // the honest fallback — never a silent sweep of its thumbnails, which is
      // why text is preferred here even though images may be available.
      final text = textDefault();
      if (text != null) return text;
    case ContentKind.standalonePage:
    case ContentKind.unknownWebContent:
      // Ambiguous, and deliberately biased towards the *existing* behaviour: a
      // page nothing could classify used to be saved as images, and quietly
      // changing that for every unrecognised reader page would be a regression
      // dressed up as a feature. The sheet shows the low confidence beside the
      // preselection and every alternative stays one tap away.
      if (available.contains(CaptureMode.imageSequence)) {
        return CaptureMode.imageSequence;
      }
      final text = textDefault();
      if (text != null) return text;
  }

  if (available.contains(CaptureMode.imageSequence)) {
    return CaptureMode.imageSequence;
  }
  return available.first;
}
