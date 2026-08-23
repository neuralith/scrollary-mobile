/// Walking one Source forward from the Entry in front of the user.
///
/// **Why this file exists.** `SaveScopePlanner` turns a count into rows the
/// library already holds, which is right for "download the ones I have" and
/// wrong for the thing people actually ask for: *I am on entry 101, give me
/// the next ten.* Ten is a claim about the Source, not about the library, and
/// the library usually knows four of them.
///
/// So there are two operations and this is the second one
/// (docs/V2_SAVE_FLOW.md §4). It walks forward along the Source the reader is
/// actually on, resolves each page's identity **before** anything is queued,
/// and hands back targets the ordinary V2 queue then captures. Nothing here
/// captures, and nothing here repairs identity afterwards.
///
/// Five rules it carries:
///
/// * **The Source is the one being read**, taken from the Location the walk
///   starts at — never the preferred Source, never the first active one. A
///   next address that leaves that Source ends the walk rather than quietly
///   continuing somewhere else.
/// * **No address is invented.** The next page is whatever `resolveNextPage`
///   decides from the page's own links, the same resolver capture uses. A
///   number in a URL never manufactures the address after it.
/// * **Identity is reconciled, not created.** Every page goes through
///   `EntryReconciler`, so an Entry the Collection already holds at that
///   position gains a Location rather than a twin (V2-D16), and an address the
///   library already holds is reused as it stands.
/// * **It is bounded twice**: by the count the user typed, and by a ceiling on
///   pages opened. There is no walk that runs until a site stops answering.
/// * **It stops rather than guesses.** End of chain, a page that cannot be
///   read, a next control only the user can identify, a landed address on a
///   restricted service, or a cancellation — each is a named stop, and the
///   Entries already resolved stay resolved.
library;

import '../data/schema.dart';

/// Why a walk ended. Every one of these is an ordinary answer.
enum WalkStop {
  /// The requested number of Entries was resolved.
  countReached,

  /// The Source offered no further page: the end of what it publishes.
  endOfSource,

  /// The next page could not be read at all — it never came back, or never
  /// rendered.
  unreadable,

  /// A next control exists but nothing could identify it confidently. The
  /// user is asked to point at it rather than the app guessing
  /// (`HintKind.nextLink`).
  needsUserAssist,

  /// The next address belongs to another site, or another section of this
  /// one. Following it would silently change what is being downloaded.
  leftTheSource,

  /// The walk landed on a service this app does not capture from. Not
  /// something the site did — see `save/capture_policy.dart`.
  captureRestrictedForSite,

  /// The user stopped it. Asked at page boundaries, never mid-read.
  cancelledByUser,

  /// The walk's own ceiling on pages opened was reached.
  pageCeiling,
}

/// One page, as the walk read it. Evidence only: nothing here is identity
/// until [SourceWalk] has reconciled it.
class WalkedPage {
  const WalkedPage({
    required this.url,
    required this.printedNumber,
    required this.title,
    this.nextUrl,
    this.stop,
  });

  /// A page that could not be read, and the named condition that ended it.
  const WalkedPage.unreadable({required this.url, required WalkStop this.stop})
    : printedNumber = null,
      title = '',
      nextUrl = null;

  /// Where the reading actually landed — never where it aimed.
  final String url;

  /// The number this page printed, when it printed one. Null is honest and
  /// leaves the Entry unplaced.
  final double? printedNumber;

  final String title;

  /// The next address, when the page's own links named one confidently.
  /// Null ends the walk with [WalkStop.endOfSource] unless [stop] says
  /// otherwise.
  final String? nextUrl;

  /// Set when this reading ended the walk instead of contributing to it.
  final WalkStop? stop;
}

/// Reading one page of a Source. The only part of the walk that touches a
/// WebView; implemented over the real Browser in
/// `features/browser_forward_pages.dart` and faked in tests.
abstract class ForwardPageSource {
  /// Open [url] and read it.
  ///
  /// [shouldContinue] is the cooperative stop, asked at safe boundaries and
  /// never mid-read. [source] is the Source the walk belongs to, so an
  /// implementation can report [WalkStop.leftTheSource] for an address that
  /// is not on it.
  Future<WalkedPage> read({
    required String url,
    required SourceRow source,
    required bool Function() shouldContinue,
  });
}

/// One Entry the walk resolved, and how.
class WalkedEntry {
  const WalkedEntry({
    required this.entryId,
    required this.locationId,
    required this.url,
    required this.printedNumber,
    required this.wasAlreadyHeld,
    required this.mergedIntoExistingEntry,
  });

  final String entryId;
  final String locationId;
  final String url;
  final double? printedNumber;

  /// True when the library already held this address and it was reused as it
  /// stands — no row was written for it.
  final bool wasAlreadyHeld;

  /// True when this address joined an Entry the Collection already had at
  /// that position, rather than creating one.
  final bool mergedIntoExistingEntry;
}

/// What a walk came to.
class WalkOutcome {
  const WalkOutcome({
    required this.entries,
    required this.stop,
    required this.pagesRead,
    required this.requested,
  });

  /// In the order they were walked, starting after the Entry the walk began
  /// at.
  final List<WalkedEntry> entries;

  /// Why it ended. Never null: finishing normally is [WalkStop.countReached].
  final WalkStop stop;

  final int pagesRead;

  /// What was asked for, so a short walk can say it was short.
  final int requested;

  int get resolved => entries.length;

  /// Whether the walk ended because the Source ran out rather than because
  /// anything went wrong. The user is told "there were only six", which is an
  /// answer about the Source and not a failure.
  bool get endedNaturally =>
      stop == WalkStop.countReached || stop == WalkStop.endOfSource;
}

/// How many pages one walk may open, whatever it was asked for.
///
/// A second bound beside the user's count, for the same reason every other
/// ceiling in this codebase exists: a count is a promise about Entries, and a
/// site can answer with pages that resolve to none of them. Stated here so
/// raising it is a visible edit.
const int kMaxWalkPages = 60;

/// The walk itself: identity first, queue rows second, capture never.
abstract class SourceWalk {
  /// Walk forward from [fromLocationId], resolving up to [wanted] further
  /// Entries on that Location's own Source.
  ///
  /// [wanted] counts Entries **after** the starting one — the caller has
  /// already accounted for the Entry in front of the user (see
  /// docs/V2_SAVE_FLOW.md §4 on what a typed count means).
  ///
  /// Writes Entries and Locations through the ordinary repositories as it
  /// goes, so a walk stopped half way leaves everything it resolved in the
  /// library rather than discarding it. Queues nothing.
  Future<WalkOutcome> forward({
    required String fromLocationId,
    required int wanted,
    required bool Function() shouldContinue,
    int maxPages = kMaxWalkPages,
  });
}
