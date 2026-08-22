/// What kind of page the user is looking at, structurally.
///
/// **Why this file exists.** V2's recognition answers *which rows do we
/// already hold for this address* — Location, Source, or nothing. It
/// deliberately says nothing about what the page **is**, because identity is
/// not shape. But the save flow has to know the difference between an entry
/// of a serialized work, the index that lists them, and an ordinary page:
/// sending all three down the standalone path is what reduced a webtoon to a
/// loose item in the root Folder.
///
/// The question is answered from structure and the page's own words, with the
/// helpers that already exist — `parseEntryNumber` and `collectionFingerprint`
/// — and nothing else. No hostname, no selector, no site list: the rule reads
/// the same on every site (CLAUDE.md, "Nothing site-specific ships").
///
/// Every answer is a real answer. [PageKind.unknownPage] is not a failure and
/// never means "standalone": it means the page did not say, so the *user* is
/// asked rather than guessed at (§21 of the save-flow brief, V2-D44).
library;

import '../library/collection_identity.dart';
import '../save/page_hint.dart' show collectionFingerprint;

/// The three shapes the save flow distinguishes.
enum PageKind {
  /// One unit of reading inside a work: it printed a number, or it sits
  /// below a collection path that is not itself.
  entryPage,

  /// The listing a work is published at — the address the Source *is*.
  collectionIndex,

  /// Neither could be established. An ordinary article, a home page, a search
  /// result. The standalone Entry is honest here, and so is asking.
  unknownPage,
}

/// What the page said about itself, kept apart from what the library knows.
class PageShape {
  const PageShape({
    required this.kind,
    required this.printedNumber,
    required this.detectedTitle,
    required this.collectionIndexUrl,
    required this.identityIsStrong,
  });

  final PageKind kind;

  /// The entry number the page or its address printed, when it printed one.
  ///
  /// Evidence, never identity (V2_ARCHITECTURE §2.5). Null is the honest
  /// answer for "Prologue", "Extra", and for every page that numbers nothing.
  final double? printedNumber;

  /// The work's title as the page named it. A suggestion for the user to
  /// accept or correct — never a match key (V2-D44).
  final String? detectedTitle;

  /// Where this work's listing lives, when the page linked to one or its own
  /// address implies one.
  final String? collectionIndexUrl;

  /// Whether a stable Source key could be derived from the address at all.
  /// False means no Source can be made from this page, whatever the user
  /// chooses.
  final bool identityIsStrong;

  /// Whether this page belongs to serialized content, however weakly.
  bool get isSerialized =>
      kind == PageKind.entryPage || kind == PageKind.collectionIndex;
}

/// Read [url]'s shape, using whatever the page volunteered.
///
/// The order is deliberate and each step is structural:
///
///   1. **A printed number** — from the title, the page's own headings, or the
///      address — makes it an entry. This is `parseEntryNumber`, the same
///      reading discovery and the update check use, so a page numbered here is
///      numbered identically everywhere.
///   2. **A collection path that is not this address.** `collectionFingerprint`
///      strips trailing entry-looking segments; when it strips any, this
///      address sits *below* a listing, which is what an entry does. It is an
///      entry with no number — a real state, and one that stays unplaced.
///   3. **A collection path equal to this address**, with an identity strong
///      enough to key a Source, is the listing itself.
///   4. Anything else did not say.
PageShape readPageShape(
  String url, {
  String? pageTitle,
  PageHints hints = const PageHints(),
}) {
  final identity = resolveCollectionIdentity(
    entryUrl: url,
    pageTitle: pageTitle,
    hints: hints,
  );
  final strong = identity.confidence == IdentityConfidence.high;
  final number = parseEntryNumber(
    title: pageTitle,
    url: url,
    extra: [hints.h1, hints.ogTitle],
  );

  final fingerprint = collectionFingerprint(url);
  final ownPath = _ownPath(url);
  final belowListing = ownPath.isNotEmpty && fingerprint != ownPath;

  final PageKind kind;
  if (number != null) {
    kind = PageKind.entryPage;
  } else if (belowListing) {
    kind = PageKind.entryPage;
  } else if (strong && ownPath.isNotEmpty && ownPath != '/') {
    kind = PageKind.collectionIndex;
  } else {
    kind = PageKind.unknownPage;
  }

  return PageShape(
    kind: kind,
    printedNumber: number,
    detectedTitle: identity.detectedTitle,
    collectionIndexUrl: identity.collectionIndexUrl,
    identityIsStrong: strong,
  );
}

/// This address's own path, normalised the way a fingerprint is: no empty
/// segments, no trailing slash, `/` for a bare host.
String _ownPath(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  if (segments.isEmpty) return '/';
  return '/${segments.join('/')}';
}
