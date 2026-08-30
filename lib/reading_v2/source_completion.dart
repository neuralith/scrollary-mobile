/// Reading on to the next Entry **at its Source**, and what that says about
/// the one just left.
///
/// ## The question
///
/// A reader on a website finishes an Entry and follows the site's own way on to
/// the next one. Nothing about that navigation is a control this app drew, so
/// there is no dialog to ask them anything and no reader route to hold a plan
/// — by the time the app hears about it, the page it would have asked about is
/// gone. The only honest thing left is the evidence of the visit itself.
///
/// ## Why moving on is not, on its own, an answer
///
/// `ForwardTransitionService` says it plainly for the offline reader: *moving
/// forward is not evidence of finishing.* A reader looks ahead, compares two
/// Entries, mistaps, or opens the next one meaning to come back. So this
/// service treats the move as a **corroborating** signal and never as the
/// signal: it completes an Entry only when the visit it is completing already
/// looks like a reading on its own terms, and the move is what settles it.
///
/// Three facts have to hold together, and each one rules out a different way of
/// being wrong:
///
///  1. **The move is forward in the Collection's own order** — the same rule
///     `next_entry.dart` resolves, asked of the same resolver, so a jump to an
///     unrelated Entry, a step backwards, or a standalone Entry cannot look
///     like reading on. Nothing about the order is re-implemented here.
///  2. **The reading reached the end** — `CompletionPolicy.reachedEnd`, the
///     same threshold the offline reader completes at, measured against the
///     readable region rather than the document (see
///     [imageContentBand]). A page still at 40% is not finished because
///     something else was opened.
///  3. **It was read at a natural pace** — [NaturalPacePolicy]. A page opened
///     and flicked to the bottom in three seconds produces the same *fraction*
///     as one read properly, and the difference between them is time and the
///     scrolling that took it.
///
/// And one that cannot be present: a visit a machine scrolled
/// (`SourceReadingVisit.automationMoved`) is not a reading at all, so it can
/// never complete anything. Downloading an Entry must not mark it read.
///
/// ## What it writes
///
/// `ReadingStateRepository.markRead`, on the Entry left behind, and nothing
/// else. No measurement, no download, no Location, no placement. Completion is
/// reading state, and a completed Entry already displays as 100% by the rule
/// enforced on write and again on display.
library;

import '../data/entry_repository.dart';
import '../data/reading_state_repository.dart';
import '../domain/reading_state.dart';
import '../reading/reading_position.dart'
    show CompletionPolicy, kDefaultCompletionPolicy;
import 'next_entry.dart';
import 'source_reading.dart';

/// What separates a reading from a flick through.
///
/// Every figure here is a floor on *time*, because time is the one thing a
/// fast navigation cannot fake. They are deliberately generous — this is a
/// guard against the obviously-not-read case, not an attempt to measure
/// comprehension.
class NaturalPacePolicy {
  const NaturalPacePolicy({
    this.minimumDwell = const Duration(seconds: 15),
    this.perViewport = const Duration(seconds: 2),
    this.minimumScrollEvents = 3,
  });

  /// The shortest visit that can be a reading, however short the Entry.
  ///
  /// Opening a page and leaving it inside this is browsing, not reading.
  final Duration minimumDwell;

  /// The shortest time a screenful of content can be read in.
  ///
  /// Applied per viewport actually covered, so a twelve-screen Entry needs
  /// twelve times as long as a one-screen one. Two seconds is far below any
  /// real reading rate; a page passed over faster than this was not read at
  /// any pace a person has.
  final Duration perViewport;

  /// How many separate scroll movements the page must have had.
  ///
  /// A reading is made of many; a page dragged to the bottom in one throw is
  /// made of few, and a page nobody touched has none.
  final int minimumScrollEvents;

  /// Whether [visit] looks like somebody read it.
  bool readAtNaturalPace(SourceReadingVisit visit) {
    if (visit.dwell < minimumDwell) return false;
    if (visit.scrollEvents < minimumScrollEvents) return false;
    return visit.dwell >= perViewport * visit.viewportsCovered;
  }
}

const NaturalPacePolicy kDefaultNaturalPacePolicy = NaturalPacePolicy();

/// Why a visit did or did not complete the Entry it was of. Returned so the
/// decision can be asserted on and explained, rather than inferred from a
/// row afterwards.
enum SourceCompletionOutcome {
  /// Nothing was being read, or the arrival is the same Entry again.
  noVisit,

  /// A machine scrolled the page this visit is about.
  automationMoved,

  /// The Entry arrived at is not the next one in the Collection's order.
  notTheNextEntry,

  /// The reading did not reach the end of the readable region.
  notFinished,

  /// It reached the end, but not at a pace anybody reads at.
  tooFast,

  /// Nothing to do: the Entry was already read.
  alreadyRead,

  /// The Entry left behind was marked read.
  completed,
}

/// Completes the Entry a reader has genuinely read on from, at its Source.
class SourceForwardCompletion {
  SourceForwardCompletion({
    required this.entries,
    required this.reading,
    required this.nextEntry,
    this.completion = kDefaultCompletionPolicy,
    this.pace = kDefaultNaturalPacePolicy,
  });

  final EntryRepository entries;
  final ReadingStateRepository reading;

  /// What follows an Entry — the app's one answer to that, never a second one
  /// derived from ids, titles or the order rows happened to be written.
  final NextEntryResolver nextEntry;

  final CompletionPolicy completion;
  final NaturalPacePolicy pace;

  /// The reader has arrived at [entryId]. Decide what the visit they left says
  /// about the Entry it was of.
  ///
  /// [leaving] is read from the meter **before** the new page is watched: a
  /// visit is only knowable while it is still the current one.
  Future<SourceCompletionOutcome> arrivedAt({
    required String entryId,
    required SourceReadingVisit? leaving,
  }) async {
    if (leaving == null || leaving.entryId == entryId) {
      return SourceCompletionOutcome.noVisit;
    }
    if (leaving.automationMoved) {
      return SourceCompletionOutcome.automationMoved;
    }

    // Forward, inside one Collection, by the Collection's own order. Asked of
    // the resolver rather than worked out here, so a move judged forward by
    // this file and by the reader cannot mean two different things.
    final outcome = await nextEntry.after(leaving.entryId);
    final next = switch (outcome) {
      NextEntryDownloaded(:final entryId) => entryId,
      NextEntryAtSourceOnly(:final entryId) => entryId,
      NoNextEntryYet() || NoReadingOrder() => null,
    };
    if (next != entryId) return SourceCompletionOutcome.notTheNextEntry;

    // No position to be at is no evidence of having reached the end of one.
    // Opening something else is not a figure, and this app does not invent one
    // (I16, V2-D9).
    final fraction = leaving.fraction;
    if (fraction == null || !completion.reachedEnd(fraction)) {
      return SourceCompletionOutcome.notFinished;
    }
    if (!pace.readAtNaturalPace(leaving)) {
      return SourceCompletionOutcome.tooFast;
    }

    if (await entries.byId(leaving.entryId) == null) {
      return SourceCompletionOutcome.noVisit;
    }
    if ((await reading.stateOf(leaving.entryId)).status ==
        ReadStatus.completed) {
      return SourceCompletionOutcome.alreadyRead;
    }

    await reading.markRead(leaving.entryId);
    return SourceCompletionOutcome.completed;
  }
}
