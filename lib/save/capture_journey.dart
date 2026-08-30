/// *Capture the next N* as one journey: capture this entry, find the next
/// one, capture that.
///
/// **Why this file exists.** A count from the entry in front of the user used
/// to be answered in two phases — read the Source forward until N Entries had
/// been resolved, write them all into the library and the queue, and only then
/// begin downloading. That is N page loads to find out what to download
/// followed by N page loads to download it, and for a user who asked for a
/// hundred it is a hundred pages of nothing visibly happening before the first
/// byte is kept. It is also not what they asked for: *capture the next twenty*
/// starts at the entry they are on and goes forward, and if the source runs
/// out at sixteen then sixteen is the answer (V2-D56).
///
/// So the two halves are interleaved, and the alternation is the whole of what
/// this file owns:
///
/// ```text
/// capture this entry → find the next → capture it → find the next → …
/// ```
///
/// Everything each step *decides* is decided elsewhere. Which Entry a page is
/// belongs to `EntryReconciler` through [SourceWalk]; what a queued download
/// is belongs to `SaveQueueRepository`; how a page becomes bytes belongs to
/// the capture the runner drives. What is here is the order, the bound the
/// user typed, and the fact that the walk goes no further until the entry it
/// just resolved has been captured.
///
/// Three properties it keeps:
///
/// * **One page load per Entry.** The walk opens the page to find out which
///   Entry it is; the capture then reads that same loaded page rather than
///   asking the site for it again ([JourneyCapture]'s `pageAlreadyLoaded`).
/// * **The bound is the number the user typed**, counting the Entry they were
///   on as the first — the same meaning the sheet states, so *20* is a
///   ceiling the run can be measured against while it happens.
/// * **Ending early is an answer, not a failure.** A source with nothing after
///   its sixteenth entry ends the journey with sixteen captures and a sentence
///   about the source.
library;

import '../recognition/walk.dart';
import 'capture_mode.dart';
import 'capture_policy.dart' show kCaptureRestrictedMessage;
import 'queue_repository.dart';

/// Capture one queued row, now.
///
/// The row is already written and eligible; what this does is claim it, run
/// it and settle it — which is [QueueRunner]'s, because the claim, the
/// cooperative stop and the terminal verdict all belong to the loop that owns
/// the queue.
///
/// [pageAlreadyLoaded] states that the row's address is the page the browser
/// is showing because this journey just opened it. A false answer ends the
/// journey: the row was cancelled, the device is out of room, or the run is
/// over.
typedef JourneyCapture =
    Future<bool> Function(String taskId, {required bool pageAlreadyLoaded});

/// A bounded sequential capture, handed to the runner by the flow that
/// authorised it.
abstract class CaptureJourney {
  /// How many Entries the user asked for, counting the one they were on. The
  /// run shows its progress against this rather than against the queue's
  /// length, because the queue only ever holds the step being taken.
  int get requested;

  /// What ended it, in the user's words, once it has ended. Null while it is
  /// running and null for a journey that simply reached the count.
  String? get endNote;

  /// Take the journey. Returns when the count is reached, the Source ends, or
  /// [capture] answers false.
  Future<void> run({
    required JourneyCapture capture,
    required bool Function() shouldContinue,
  });
}

/// The journey along one Source: the Entry in front of the user, then each
/// Entry that Source names after it.
class SourceCaptureJourney implements CaptureJourney {
  SourceCaptureJourney({
    required this._walk,
    required this._queue,
    required this.startEntryId,
    required this.startLocationId,
    required this.startLocationUrl,
    required this.requested,
    this.captureMode,
    this.captureModeIsUserSet = false,
  });

  final SourceWalk _walk;
  final SaveQueueRepository _queue;

  /// The Entry the user is on. Its identity is already known — it is why the
  /// sheet could be opened at all — so nothing is opened to establish it.
  final String startEntryId;
  final String startLocationId;
  final String startLocationUrl;

  @override
  final int requested;

  /// What the sheet asked for, carried onto every row this journey writes so
  /// the tenth entry is captured the way the first was.
  final CaptureMode? captureMode;
  final bool captureModeIsUserSet;

  String? _endNote;

  @override
  String? get endNote => _endNote;

  /// How many Entries this journey has taken on, captured or attempted. The
  /// bound counts entries, not successes: a page that would not download is
  /// still one of the twenty the user asked about.
  int get taken => _taken;
  int _taken = 0;

  @override
  Future<void> run({
    required JourneyCapture capture,
    required bool Function() shouldContinue,
  }) async {
    // 1. The entry in front of the user, first — before any address after it
    //    is so much as resolved. This is the half a pre-walk put last.
    if (!await _capture(
      capture,
      entryId: startEntryId,
      locationId: startLocationId,
      url: startLocationUrl,
      pageAlreadyLoaded: false,
    )) {
      return;
    }
    if (_taken >= requested) return;

    // 2. Then forward, one page at a time, each one captured where it was
    //    opened before the next is looked for.
    final outcome = await _walk.forward(
      fromLocationId: startLocationId,
      wanted: requested - _taken,
      shouldContinue: shouldContinue,
      // One page read per Entry, so a count the user was allowed to type is
      // not cut short by a ceiling meant for pages that resolve to nothing.
      maxPages: requested + 1 > kMaxWalkPages ? requested + 1 : kMaxWalkPages,
      onEntry: (entry) => _capture(
        capture,
        entryId: entry.entryId,
        locationId: entry.locationId,
        url: entry.url,
        pageAlreadyLoaded: true,
      ),
    );
    _endNote ??= journeyEndNote(outcome.stop, pagesRead: outcome.pagesRead);
  }

  /// Write the row, then have it captured. The queue is where a download is
  /// recorded, whichever way the work arrived at it.
  Future<bool> _capture(
    JourneyCapture capture, {
    required String entryId,
    required String locationId,
    required String url,
    required bool pageAlreadyLoaded,
  }) async {
    final result = await _queue.enqueue(
      entryId: entryId,
      locationId: locationId,
      locationUrl: url,
      captureMode: captureMode,
      captureModeIsUserSet: captureModeIsUserSet,
    );
    final refusal = result.refusedReason;
    if (refusal != null) {
      // The restricted-site policy, in its own sentence and no other. No row
      // was written, so there is nothing here to start or retry.
      _endNote = refusal;
      return false;
    }
    final task = result.task;
    if (task == null) return false;
    _taken++;
    final carriedOn = await capture(
      task.id,
      pageAlreadyLoaded: pageAlreadyLoaded,
    );
    if (!carriedOn) {
      _endNote ??= journeyEndNote(WalkStop.cancelledByUser);
      return false;
    }
    // The count itself is the walk's own bound — it was told how many were
    // wanted — so carrying on here is never the same thing as going past it.
    return true;
  }
}

/// Why a journey stopped, in the user's words — or null when reaching the
/// count is the whole story.
///
/// "There were only six" is an answer about the Source and reads as one. The
/// rest name what stopped the reading, because *we found fewer* and *we were
/// stopped* are different things and only the first is about what the site
/// publishes.
String? journeyEndNote(WalkStop stop, {int pagesRead = 0}) => switch (stop) {
  WalkStop.countReached => null,
  WalkStop.endOfSource =>
    'No next entry found — that is everything this site publishes after it.',
  WalkStop.unreadable => 'The next page did not load, so it stopped there.',
  WalkStop.noForwardProgress =>
    'Going to the next entry led back to the page Scrollary was already on, '
        'so it stopped rather than download the same entry again. Open the '
        'next entry yourself and ask from there.',
  WalkStop.needsUserAssist =>
    'Scrollary could not tell which control leads to the next entry on this '
        'site. Point at it once and it will remember.',
  WalkStop.leftTheSource =>
    'The next link leads away from this collection’s site, so it stopped '
        'rather than follow it.',
  WalkStop.captureRestrictedForSite => kCaptureRestrictedMessage,
  WalkStop.cancelledByUser =>
    'You stopped it — everything already downloaded is on this device.',
  WalkStop.pageCeiling =>
    'Scrollary stopped after $pagesRead pages. Ask again from the last one to '
        'carry on.',
};
