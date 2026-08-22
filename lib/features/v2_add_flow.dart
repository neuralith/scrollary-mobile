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

  /// How many of the requested downloads the library could not name an
  /// address for. Reported, never quietly dropped.
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
Future<AddToLibraryReport> v2AddAndDownload(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  String? collectionId,
  String? newCollectionName,
  String? folderId,
  SaveLimits? limits,
  bool isListing = false,
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

/// Plan against the library, then enqueue each planned save through the one
/// enqueue there is. **Nothing is started**: `authoriseStart` is not called
/// here, and a queued row waits for the user's explicit Start.
Future<_Queueing> _queue(
  WidgetRef ref, {
  required String startEntryId,
  required String? preferSourceId,
  required SaveLimits limits,
  required CaptureMode? captureMode,
  required bool captureModeIsUserSet,
}) async {
  final queue = ref.read(libraryUiServicesProvider).queue;
  final plan = await ref
      .read(saveScopePlannerProvider)
      .plan(
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
