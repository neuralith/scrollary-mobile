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
import '../providers.dart' show queueRunnerProvider;
import '../recognition/page_kind.dart';
import '../recognition/recognise.dart';
import '../save/capture_journey.dart';
import '../save/capture_mode.dart';
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

  /// How many of the requested downloads are not queued yet. For a count
  /// answered from the library, what it could not name an address for; for a
  /// sequential capture of a Source, what that journey will go and find.
  /// Reported, never quietly dropped.
  final int shortfall;

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
/// and queues what it holds. True means the count is a claim about the
/// **Source**: this entry is queued and the ones after it are found as the
/// download moves along, one page at a time (V2-D56). Nothing is downloaded
/// either way, and neither opens a page here.
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
  });

  final String sentence;
  final int queued;
  final int shortfall;
}

/// Turn the count into work. **Nothing is started**: `authoriseStart` is not
/// called here, and a queued row waits for the user's explicit Start.
///
/// Two operations answer a count and they are not the same question
/// (docs/V2_SAVE_FLOW.md §4), so this splits in two immediately:
///
/// * **The next N from here** ([discoverMissing]) is a claim about the
///   **Source**, and it is one sequential journey: the entry in front of the
///   user is queued now, and every entry after it is found *while the
///   downloading happens*, one page at a time (V2-D56). Nothing reads the site
///   here — [SourceCaptureJourney] does that when the user starts it, which is
///   what makes *Queue only* a complete answer that opens nothing.
/// * **The ones the library already has** is planned against the library and
///   queued in full, opening nothing, exactly as it always was.
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

  // A count of one asks for the page in front of the user and nothing else:
  // there is no journey to take, and no site is read either way.
  if (discoverMissing && limits.maxEntries > 1) {
    return _queueJourney(
      ref,
      startEntryId: startEntryId,
      preferSourceId: preferSourceId,
      requested: limits.maxEntries,
      captureMode: captureMode,
      captureModeIsUserSet: captureModeIsUserSet,
    );
  }

  final plan = await planner.plan(
    startEntryId: startEntryId,
    limits: limits,
    preferSourceId: preferSourceId,
  );

  var queued = 0;
  var waiting = 0;
  String? refusal;
  for (final save in plan.saves) {
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
  );
}

/// *Download the next N from here*, as the one journey it is.
///
/// What this writes now is a single row — the entry the user is standing on,
/// whose identity is already known and which therefore costs nothing to
/// establish. What it *arranges* is the rest: a [SourceCaptureJourney] the
/// runner takes on the user's Start, which captures that entry, reads the
/// page it is on for the address after it, captures that, and so on until the
/// count is reached or the Source runs out.
///
/// **Why not resolve the range first.** Because that is N page loads before
/// the first byte is kept, and the answer to *give me twenty* is twenty
/// entries on the device — not twenty rows in a queue standing behind a walk
/// that has already read every page it is about to read again (V2-D56).
Future<_Queueing> _queueJourney(
  WidgetRef ref, {
  required String startEntryId,
  required String? preferSourceId,
  required int requested,
  required CaptureMode? captureMode,
  required bool captureModeIsUserSet,
}) async {
  final queue = ref.read(libraryUiServicesProvider).queue;
  // The address this entry will be read at, from the library and nothing
  // else: a plan of one opens no page, and there is no second question to ask
  // about the page already in front of the user.
  final plan = await ref
      .read(saveScopePlannerProvider)
      .plan(
        startEntryId: startEntryId,
        limits: SaveLimits.forScope(SaveScope.currentPageOnly),
        preferSourceId: preferSourceId,
      );
  final start = plan.saves.firstOrNull;
  if (start == null) {
    return const _Queueing(
      sentence:
          'Your library holds no address for this entry, so there is nothing '
          'to download from.',
      queued: 0,
      shortfall: 0,
    );
  }

  final result = await queue.enqueue(
    entryId: start.entryId,
    locationId: start.locationId,
    locationUrl: start.url,
    captureMode: captureMode,
    captureModeIsUserSet: captureModeIsUserSet,
  );
  final refusal = result.refusedReason;
  if (refusal != null) {
    return _Queueing(sentence: refusal, queued: 0, shortfall: 0);
  }

  ref
      .read(queueRunnerProvider)
      .follow(
        SourceCaptureJourney(
          walk: ref.read(sourceWalkProvider),
          queue: queue,
          startEntryId: start.entryId,
          startLocationId: start.locationId,
          startLocationUrl: start.url,
          requested: requested,
          captureMode: captureMode,
          captureModeIsUserSet: captureModeIsUserSet,
        ),
      );

  return _Queueing(
    sentence:
        'Downloading from this page onward, up to $requested entries: each '
        'one is found as the one before it finishes, and it stops when this '
        'site has no next entry. $_startFirst',
    queued: 1,
    shortfall: requested - 1,
  );
}

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
