/// The one place user-facing words for an [Entry] are produced.
///
/// `Entry` and `Collection` are the canonical technical model everywhere in the
/// code. What a *screen* prints is a contextual label derived here — and only
/// here. Individual screens must never assemble their own noun, because that is
/// how one app ends up calling the same thing an episode, a chapter and a page
/// on three consecutive screens.
///
/// Two rules do the real work:
///
/// 1. **A guess is never printed as a fact.** Low-confidence or unknown content
///    is an *Item* / *Saved item*. A number in a URL is not evidence of a
///    chapter, and a page arriving from the web is not evidence of a page.
/// 2. **The user can correct it.** The label follows the stored shape, and the
///    stored shape is editable (`Entry details → Content type`), so a wrong
///    detection is a two-tap fix rather than a permanent mislabel.
library;

import 'content_shape.dart';

/// The vocabulary a surface may use for one entry.
///
/// Deliberately small and deliberately generic at the bottom: every value here
/// must be true of *any* website, which is why there is no `Volume`, no
/// `Issue`, and nothing genre-specific.
enum EntryLabelStyle {
  article,
  post,
  chapter,
  episode,
  part,
  page,
  item,
  savedItem;

  /// Singular / plural nouns, sentence-case for prose, as used in body copy.
  ({String one, String many}) get nouns => switch (this) {
    EntryLabelStyle.article => (one: 'article', many: 'articles'),
    EntryLabelStyle.post => (one: 'post', many: 'posts'),
    EntryLabelStyle.chapter => (one: 'chapter', many: 'chapters'),
    EntryLabelStyle.episode => (one: 'episode', many: 'episodes'),
    EntryLabelStyle.part => (one: 'part', many: 'parts'),
    EntryLabelStyle.page => (one: 'page', many: 'pages'),
    EntryLabelStyle.item => (one: 'item', many: 'items'),
    EntryLabelStyle.savedItem => (one: 'saved item', many: 'saved items'),
  };

  /// Title-case nouns, for headings, buttons and section labels.
  ({String one, String many}) get titles => switch (this) {
    EntryLabelStyle.article => (one: 'Article', many: 'Articles'),
    EntryLabelStyle.post => (one: 'Post', many: 'Posts'),
    EntryLabelStyle.chapter => (one: 'Chapter', many: 'Chapters'),
    EntryLabelStyle.episode => (one: 'Episode', many: 'Episodes'),
    EntryLabelStyle.part => (one: 'Part', many: 'Parts'),
    EntryLabelStyle.page => (one: 'Page', many: 'Pages'),
    EntryLabelStyle.item => (one: 'Item', many: 'Items'),
    EntryLabelStyle.savedItem => (one: 'Saved item', many: 'Saved items'),
  };

  /// True when this style may carry a number (`Chapter 12`, `Page 3`).
  ///
  /// `Article`, `Post`, `Item` and `Saved item` never do: numbering an article
  /// invents an ordering the source never claimed.
  bool get takesNumber =>
      this == EntryLabelStyle.chapter ||
      this == EntryLabelStyle.episode ||
      this == EntryLabelStyle.part ||
      this == EntryLabelStyle.page;

  static EntryLabelStyle fromName(String? name) =>
      EntryLabelStyle.values.firstWhere(
        (s) => s.name == name,
        orElse: () => EntryLabelStyle.savedItem,
      );
}

/// The label vocabulary for one entry or collection, plus the number rule.
class EntryLabels {
  const EntryLabels(this.style);

  final EntryLabelStyle style;

  String get one => style.nouns.one;
  String get many => style.nouns.many;
  String get One => style.titles.one; // ignore: non_constant_identifier_names
  String get Many => style.titles.many; // ignore: non_constant_identifier_names

  /// `1 chapter` / `4 saved items`. The number always leads, because that is
  /// what a reader scans for.
  String count(int n) => '$n ${n == 1 ? one : many}';

  /// `Chapter 12` when the style takes a number and one is known; otherwise
  /// null, so the caller falls back to a real title rather than a fabrication.
  String? numbered(double? number) {
    if (!style.takesNumber || number == null) return null;
    final asInt = number == number.roundToDouble();
    return '$One ${asInt ? number.round() : number}';
  }
}

/// The vocabulary for content whose shape is unknown, or for a surface that
/// spans several collections and so has no single vocabulary to speak.
///
/// Exists so that no screen ever has to write `'entry${n == 1 ? '' : 's'}'`.
/// That idiom is where "2 entrys" came from: a mechanical rename turned a noun
/// with a regular plural into one without, and every hand-rolled plural in the
/// UI broke at once. Counting is centralised for the same reason naming is.
const EntryLabels kGenericEntryLabels = EntryLabels(EntryLabelStyle.savedItem);

/// The same fallback, for a sentence that has already said "save" or "offline".
///
/// `Save 8 items` reads; `Save 8 saved items` does not. Two constants rather
/// than one because the redundancy is a property of the surrounding sentence,
/// which only the call site knows.
const EntryLabels kPlainEntryLabels = EntryLabels(EntryLabelStyle.item);

/// [labelsFor] over the stored strings, for callers holding a row rather than
/// parsed enums.
///
/// Takes names instead of the row itself so this file stays free of the database
/// layer — the label rules are pure, and a widget that has an entry in hand
/// should not have to parse three enums to ask what to call it.
EntryLabels labelsFromNames({
  String? contentKind,
  String? confidence,
  String? sequenceKind,
}) => labelsFor(
  kind: ContentKind.fromName(contentKind),
  sequence: SequenceKind.fromName(sequenceKind),
  confidence: ShapeConfidence.fromName(confidence),
);

/// Choose the vocabulary for a piece of content.
///
/// The order below is the whole policy. Note what is *absent*: there is no path
/// from "the URL contains a number" to `chapter`, and no path from "it came
/// from a web page" to `page`. Both require a positive signal about the
/// content's structure, at medium confidence or better.
EntryLabels labelsFor({
  ContentKind kind = ContentKind.unknownWebContent,
  SequenceKind sequence = SequenceKind.none,
  ShapeConfidence confidence = ShapeConfidence.low,
}) {
  // Rule 1: an uncertain detection gets a generic noun. This is the single
  // most important line in the file.
  if (!confidence.isActionable) {
    return const EntryLabels(EntryLabelStyle.savedItem);
  }

  return EntryLabels(switch (kind) {
    // Real pagination is the only thing allowed to be called a page.
    ContentKind.paginatedDocument => EntryLabelStyle.page,

    // A dated feed reads as posts whichever direction it runs in.
    ContentKind.datedPost => EntryLabelStyle.post,

    ContentKind.article => EntryLabelStyle.article,

    // Long prose split across a declared sequence: parts, unless the source
    // numbered them explicitly, in which case chapters is the honest word.
    ContentKind.sequentialText => switch (sequence) {
      SequenceKind.numberedPagination ||
      SequenceKind.explicitNextPrev => EntryLabelStyle.chapter,
      _ => EntryLabelStyle.part,
    },

    // Image-dominant content is deliberately NOT given a genre noun. An
    // ordered image sequence is made of episodes only when the source itself
    // declares an order; otherwise they are items.
    ContentKind.imageDominant => switch (sequence) {
      SequenceKind.explicitNextPrev ||
      SequenceKind.numberedPagination => EntryLabelStyle.episode,
      _ => EntryLabelStyle.item,
    },

    // A video page is never given a genre noun either. Whatever was saved from
    // it is readable text, not the video — calling it an "episode" would name
    // the thing the app deliberately did not keep.
    ContentKind.videoDominant ||
    ContentKind.longFormDocument ||
    ContentKind.standalonePage => EntryLabelStyle.item,

    ContentKind.unknownWebContent => EntryLabelStyle.savedItem,
  });
}

/// What a list row actually prints for one entry.
///
/// Number-first when the style takes a number *and* the source gave us one;
/// the source's own marker next (`Prologue`, `Appendix B` are real names and
/// must survive verbatim); the page title after that; and the generic noun as
/// the last resort. Nothing here invents a number.
String entryDisplayLabel({
  required EntryLabels labels,
  double? number,
  String? sourceMarker,
  String? title,
}) {
  final numbered = labels.numbered(number);
  if (numbered != null) return numbered;

  final marker = sourceMarker?.trim();
  if (marker != null && marker.isNotEmpty) return marker;

  final fallback = title?.trim();
  if (fallback != null && fallback.isNotEmpty) return fallback;

  return labels.One;
}

/// How a collection describes itself in one line: `12 chapters`, `3 saved items`.
String collectionExtentLabel({
  required EntryLabels labels,
  required int savedCount,
  int? knownTotal,
}) {
  if (knownTotal == null || knownTotal <= savedCount) {
    return labels.count(savedCount);
  }
  return '${labels.count(savedCount)} of $knownTotal';
}

/// Sentence for a sequence whose end is not knowable.
///
/// Used wherever a count would otherwise be printed for an open-ended
/// sequence — saying "12 chapters" about something with no known end is the
/// kind of small lie that makes the whole library untrustworthy.
String openEndedExtentLabel(EntryLabels labels) =>
    'No known end — ${labels.many} are added as you save them';
