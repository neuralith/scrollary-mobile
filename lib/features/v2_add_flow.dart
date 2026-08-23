/// The restored journey: *which Collection is this?* and *how many entries?*
///
/// **Why this file exists.** Those were V1's two questions on the way in, and
/// the V2 rewrite lost both (docs/V2_SAVE_FLOW.md §1). This is the
/// orchestration that puts them back, and it owns no rules of its own: page
/// shape is `recognition/page_kind.dart`'s, Collection context is
/// `recognition/adopt.dart`'s, cross-source equivalence is
/// `recognition/reconcile.dart`'s, how much is [SaveLimits] and
/// `SaveScopePlanner`'s, and a queued save is `SaveQueueRepository.enqueue`'s.
/// What is here is the order they happen in and the sentence the user reads.
///
/// Two rules bind every function below:
///
/// * **Library membership and downloading are separate acts** (PRODUCT.md
///   §2.4). One tap may ask for both; they remain two operations, and the
///   sentence says how each of them went.
/// * **Nothing starts a run.** Every planned save becomes a waiting
///   `save_queue` row, and the wording says so in the same breath: nothing is
///   downloaded until the user presses Start.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../domain/invariants.dart';
import '../library_ui/providers.dart';
import '../recognition/page_kind.dart';
import '../recognition/recognise.dart';
import '../recognition/walk.dart';
import '../save/capture_mode.dart';
import '../save/capture_policy.dart' show kCaptureRestrictedMessage;
import '../save/save_scope.dart' show SaveScopePlan;
import 'v2_adoption_providers.dart';
import 'v2_save_flow.dart';

/// What one trip through the sheet did, to the library and to the queue.
class AddToLibraryReport {
  const AddToLibraryReport({
    this.sentence,
    this.collectionId,
    this.entryId,
    this.queued = 0,
    this.shortfall = 0,
    this.walkStop,
  });

  /// What the user is told, in one sentence. Never null on a refusal.
  final String? sentence;

  /// The Collection this page now belongs to, when it belongs to one.
  final String? collectionId;

  /// The Entry the page became, or joined. Null for a listing, which is
  /// never an Entry (V2_SAVE_FLOW.md §3).
  final String? entryId;

  /// Rows now waiting in the save queue because of this call.
  final int queued;

  /// How many of the requested downloads the library could not name an
  /// address for. Reported, never quietly dropped.
  final int shortfall;

  /// Why the forward walk ended, when one ran. Null when the count was
  /// answered from the library alone — which is every call that did not ask
  /// to discover what is missing.
  ///
  /// [sentence] already says all of this in words, and that is what the
  /// surfaces read; this is here for the one that wants to offer *point at
  /// the next control* rather than only report it.
  final WalkStop? walkStop;

  /// Whether the library changed, or already held what was asked for. A
  /// listing succeeds with no Entry: that is the answer, not a failure.
  bool get succeeded => collectionId != null || entryId != null;
}

/// Establish Collection context for the page, then queue [limits] worth of
/// downloads.
///
/// Exactly one of [collectionId] / [newCollectionName] may be set; both null
/// means "the page is already in the library" and only the queueing runs.
/// [limits] null queues nothing — which is what a listing gets, because a
/// listing is not an Entry and there is nothing on it to download.
///
/// [isListing] is the caller's answer to *is this address a Source's own
/// page*. It is a parameter rather than something re-derived here because
/// only the library can answer it (`readPageShape`'s `sourcePathKey`), and
/// the sheet has already asked.
///
/// [discoverMissing] chooses which of the two operations a typed count means
/// (docs/V2_SAVE_FLOW.md §4). False — the default — plans against the library
/// and opens nothing. True adds the second half: when the library knows fewer
/// Entries than were asked for, the Source the user is reading is walked
/// forward for **the shortfall only**, and the plan is rebuilt over what that
/// found. Nothing is downloaded either way.
Future<AddToLibraryReport> v2AddAndDownload(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  String? collectionId,
  String? newCollectionName,
  String? folderId,
  SaveLimits? limits,
  bool isListing = false,
  bool discoverMissing = false,
  CaptureMode? captureMode,
  bool captureModeIsUserSet = false,
}) async {
  if (collectionId != null && newCollectionName != null) {
    return const AddToLibraryReport(
      sentence:
          'Choose a collection to add this to, or a name for a new one — '
          'not both.',
    );
  }

  final services = ref.read(libraryUiServicesProvider);
  final adoption = ref.read(libraryAdoptionProvider);
  final shape = readPageShape(url, pageTitle: pageTitle);
  final keys = RecognitionKeys.of(url, pageTitle: pageTitle);

  // The index page is never an Entry (§3). A listing is where a Source lives,
  // and what it lists is found by a check — a separate, visible, bounded act.
  if (isListing || shape.kind == PageKind.collectionIndex) {
    return _addListing(
      ref,
      keys: keys,
      collectionId: collectionId,
      newCollectionName: newCollectionName,
      folderId: folderId,
      limits: limits,
    );
  }

  String? entryId;
  String? sourceId;
  var merged = false;
  var context = '';

  if (newCollectionName != null) {
    final outcome = await adoption.createCollection(
      name: newCollectionName,
      keys: keys,
      pageTitle: pageTitle,
      printedNumber: shape.printedNumber,
      folderId: folderId,
    );
    if (!outcome.succeeded) return _refused(outcome.violation);
    collectionId = outcome.collectionId;
    entryId = outcome.entryId;
    sourceId = outcome.sourceId;
    context = 'Started $newCollectionName with this page.';
  } else if (collectionId != null) {
    final outcome = await adoption.addToExistingCollection(
      collectionId: collectionId,
      keys: keys,
      pageTitle: pageTitle,
      printedNumber: shape.printedNumber,
    );
    if (!outcome.succeeded) return _refused(outcome.violation);
    final joined = outcome.collectionId!;
    collectionId = joined;
    entryId = outcome.entryId;
    sourceId = outcome.sourceId;
    merged = outcome.mergedIntoExistingEntry;
    final name = await _collectionName(ref, joined);
    context = merged
        ? 'Added to $name, where it joined the entry already there.'
        : 'Added to $name.';
  } else {
    // Nothing to establish: the page is already in the library, and this call
    // is only about how much to download.
    final recogniser = Recogniser(
      index: RecognitionIndexOf(services).index,
      collections: services.collections,
      reading: services.reading,
    );
    final result = await recogniser.recogniseKeys(keys);
    if (result is! RecognisedLocation) {
      return const AddToLibraryReport(
        sentence:
            'This page is not in your library yet — choose a collection for '
            'it first.',
      );
    }
    entryId = result.entry.id;
    collectionId = result.collection?.id;
    sourceId = result.location.sourceId;
    context = 'Already in your library.';
  }

  if (limits == null) {
    return AddToLibraryReport(
      sentence: '$context Nothing was queued.',
      collectionId: collectionId,
      entryId: entryId,
    );
  }

  final queueing = await _queue(
    ref,
    startEntryId: entryId!,
    preferSourceId: sourceId,
    limits: limits,
    discoverMissing: discoverMissing,
    captureMode: captureMode,
    captureModeIsUserSet: captureModeIsUserSet,
  );

  return AddToLibraryReport(
    sentence: '$context ${queueing.sentence}',
    collectionId: collectionId,
    entryId: entryId,
    queued: queueing.queued,
    shortfall: queueing.shortfall,
    walkStop: queueing.walkStop,
  );
}

/// Save the page as a standalone Entry — the deliberate fallback, unchanged
/// behaviour.
///
/// A serialized page never lands here by accident: standalone is offered,
/// chosen, and is never what "recognition could not tell" falls back to
/// (V2_SAVE_FLOW.md §3).
Future<AddToLibraryReport> v2SaveStandalone(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  CaptureMode? captureMode,
  bool captureModeIsUserSet = false,
}) async {
  final message = await v2SavePage(
    ref,
    url: url,
    pageTitle: pageTitle,
    captureMode: captureMode,
    captureModeIsUserSet: captureModeIsUserSet,
  );
  final status = await v2PageStatusFor(ref, url);
  final result = status.result;
  final collectionId = result is RecognisedLocation
      ? result.collection?.id
      : null;
  if (message != null) {
    return AddToLibraryReport(
      sentence: message,
      collectionId: collectionId,
      entryId: status.entryId,
    );
  }
  return AddToLibraryReport(
    sentence: 'Saved to your library. $_oneQueued',
    collectionId: collectionId,
    entryId: status.entryId,
    queued: 1,
  );
}

/// Adopt a standalone Entry into a Collection.
Future<AddToLibraryReport> v2AdoptStandalone(
  WidgetRef ref, {
  required String entryId,
  required String collectionId,
}) async {
  final outcome = await ref
      .read(libraryAdoptionProvider)
      .adoptStandalone(entryId: entryId, collectionId: collectionId);
  if (!outcome.succeeded) return _refused(outcome.violation);
  final name = await _collectionName(ref, collectionId);
  return AddToLibraryReport(
    sentence: outcome.mergedIntoExistingEntry
        ? 'Moved into $name, where it joined the entry already there. '
              'Nothing was downloaded, and nothing on this device was removed.'
        : 'Moved into $name. Nothing was downloaded.',
    collectionId: collectionId,
    entryId: outcome.entryId,
  );
}

// ─── the halves ─────────────────────────────────────────────────────────────

Future<AddToLibraryReport> _addListing(
  WidgetRef ref, {
  required RecognitionKeys keys,
  String? collectionId,
  String? newCollectionName,
  String? folderId,
  SaveLimits? limits,
}) async {
  if (collectionId == null && newCollectionName == null) {
    return const AddToLibraryReport(
      sentence:
          'This page is a collection’s list. Add it to a collection to '
          'follow it.',
    );
  }
  final adopted = await ref
      .read(libraryAdoptionProvider)
      .addListingSource(
        collectionId: collectionId,
        newCollectionName: newCollectionName,
        keys: keys,
        folderId: folderId,
      );
  if (!adopted.succeeded) return _refused(adopted.violation);

  final name = await _collectionName(ref, adopted.collectionId!);
  final buffer = StringBuffer(
    adopted.createdCollection
        ? 'Started $name from this site’s list.'
        : adopted.sourceReused
        ? 'This site is already a source of $name.'
        : 'Added this site as another source of $name.',
  );
  buffer.write(
    ' A list is not an entry, so nothing was added to read from it — '
    'check $name to find its entries.',
  );
  if (limits != null) buffer.write(' Nothing was queued.');
  return AddToLibraryReport(
    sentence: buffer.toString(),
    collectionId: adopted.collectionId,
  );
}

class _Queueing {
  const _Queueing({
    required this.sentence,
    required this.queued,
    required this.shortfall,
    this.walkStop,
  });

  final String sentence;
  final int queued;
  final int shortfall;
  final WalkStop? walkStop;
}

/// Plan against the library, then enqueue each planned save through the one
/// enqueue there is. **Nothing is started**: `authoriseStart` is not called
/// here, and a queued row waits for the user's explicit Start.
///
/// The order matters and is the whole of what this function owns. The library
/// is planned against **first**, opening nothing — so a request the library
/// can already answer in full never drives a browser. Only what is missing
/// after that is walked for, and only when the caller asked
/// ([discoverMissing]). The walk resolves identity and writes library rows,
/// and **what it resolved is what gets queued** — the Entries it names, not a
/// second plan derived from the library afterwards, which cannot see an Entry
/// the Source left unnumbered.
Future<_Queueing> _queue(
  WidgetRef ref, {
  required String startEntryId,
  required String? preferSourceId,
  required SaveLimits limits,
  required bool discoverMissing,
  required CaptureMode? captureMode,
  required bool captureModeIsUserSet,
}) async {
  final queue = ref.read(libraryUiServicesProvider).queue;
  final planner = ref.read(saveScopePlannerProvider);
  Future<SaveScopePlan> planNow() => planner.plan(
    startEntryId: startEntryId,
    limits: limits,
    preferSourceId: preferSourceId,
  );

  final plan = await planNow();

  // *Download the next N from here.* The count is a claim about the Source,
  // so the ones the library cannot name are read forward on the site the user
  // is actually on — from the furthest Entry the plan reached, for the
  // shortfall and no more. A fully known request never gets here.
  WalkOutcome? walk;
  if (discoverMissing &&
      !plan.startIsUnplaced &&
      plan.saves.isNotEmpty &&
      plan.planned < limits.maxEntries) {
    final cancellation = ref.read(sourceWalkCancellationProvider)..begin();
    try {
      walk = await ref
          .read(sourceWalkProvider)
          .forward(
            fromLocationId: plan.saves.last.locationId,
            wanted: limits.maxEntries - plan.planned,
            shouldContinue: cancellation.shouldContinue,
          );
    } finally {
      // However it ended — its own stop, the user's, or a throw — the panel
      // stops saying a site is being read.
      cancellation.finish();
    }
  }

  // What will actually be captured, in the order it was decided: the library's
  // own plan, then the Entries the walk resolved beyond it.
  //
  // **The walk's answer is used as it stands, not re-derived.** Re-planning
  // over the library after a walk looks equivalent and is not: the planner
  // takes a Collection's rows in ordinal order from the starting Entry, and a
  // page that printed no number reconciles to an Entry with no ordinal
  // (`EntryReconciler`). Those Entries are real, addressed and downloadable —
  // position is organisation, not permission — but a plan cannot see them, so
  // the count that had just been satisfied on the Source came back short or
  // empty. A `WalkedEntry` already names the Entry and the Location; that is
  // the target, and nothing about it has to be looked up again.
  final targets = <({String entryId, String locationId, String url})>[];
  final seen = <String>{};
  void want(String entryId, String locationId, String url) {
    if (seen.add(entryId)) {
      targets.add((entryId: entryId, locationId: locationId, url: url));
    }
  }

  for (final save in plan.saves) {
    want(save.entryId, save.locationId, save.url);
  }
  for (final entry in walk?.entries ?? const <WalkedEntry>[]) {
    if (targets.length >= limits.maxEntries) break;
    want(entry.entryId, entry.locationId, entry.url);
  }

  var queued = 0;
  var waiting = 0;
  String? refusal;
  for (final save in targets) {
    final result = await queue.enqueue(
      entryId: save.entryId,
      locationId: save.locationId,
      locationUrl: save.url,
      captureMode: captureMode,
      captureModeIsUserSet: captureModeIsUserSet,
    );
    if (result.refusedReason != null) {
      refusal ??= result.refusedReason;
      continue;
    }
    queued++;
    if (result.alreadyQueued) waiting++;
  }

  final buffer = StringBuffer();
  if (queued == 0) {
    buffer.write('Nothing was queued.');
  } else {
    buffer.write('$queued ${_entries(queued)} queued — $_startFirst');
    if (waiting > 0) {
      buffer.write(
        ' ${waiting == 1 ? '1 of them was' : '$waiting of them were'} already '
        'waiting.',
      );
    }
  }
  final shortfall = (limits.maxEntries - queued).clamp(0, limits.maxEntries);
  if (shortfall > 0) {
    if (plan.startIsUnplaced) {
      buffer.write(
        ' This entry has no position in its collection, so there is nothing '
        'after it to queue.',
      );
    } else if (walk != null) {
      buffer.write(' ${_walkShortfall(walk, queued: queued)}');
    } else {
      buffer.write(
        ' Your library knows $queued of the ${limits.maxEntries} asked for; '
        'checking this collection for updates can find more.',
      );
    }
  }
  if (refusal != null) buffer.write(' $refusal');
  return _Queueing(
    sentence: buffer.toString(),
    queued: queued,
    shortfall: shortfall,
    walkStop: walk?.stop,
  );
}

/// Why a walk that ran still left the request short, in the user's words.
///
/// Ending is not failure: *there were only six* is an answer about the Source
/// and reads as one. The rest name what stopped the reading, because "we found
/// fewer" and "we were stopped" are different things and only the first is
/// about the site's contents.
String _walkShortfall(WalkOutcome walk, {required int queued}) =>
    switch (walk.stop) {
      WalkStop.endOfSource =>
        'That is everything this site publishes after it — there '
            '${queued == 1 ? 'was only 1' : 'were only $queued'}.',
      WalkStop.countReached =>
        'The rest were added to your library with no position in this '
            'collection, so they are there to place rather than queued.',
      WalkStop.cancelledByUser =>
        'You stopped the search — what it had already found is in your '
            'library.',
      WalkStop.needsUserAssist =>
        'Scrollary could not tell which control leads to the next entry on '
            'this site. Point at it once and it will remember.',
      WalkStop.leftTheSource =>
        'The next link leads away from this collection’s site, so the '
            'search stopped rather than follow it.',
      WalkStop.unreadable =>
        'The next page did not load, so the search stopped there.',
      WalkStop.captureRestrictedForSite => kCaptureRestrictedMessage,
      WalkStop.pageCeiling =>
        'Scrollary stopped after ${walk.pagesRead} pages. Ask again from the '
            'last one to carry on.',
    };

const String _startFirst = 'nothing is downloaded until you press Start.';
const String _oneQueued = '1 entry queued — $_startFirst';

String _entries(int count) => count == 1 ? 'entry' : 'entries';

AddToLibraryReport _refused(InvariantViolation? violation) =>
    AddToLibraryReport(
      sentence: violation == null
          ? 'That could not be done.'
          : 'That could not be done: ${violation.message}.',
    );

Future<String> _collectionName(WidgetRef ref, String collectionId) async {
  final row = await ref
      .read(libraryUiServicesProvider)
      .collections
      .byId(collectionId);
  return row?.name ?? 'your library';
}
