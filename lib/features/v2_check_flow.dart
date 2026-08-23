/// The Browser's side of a Collection check: the way in, and the way the
/// result is told.
///
/// **Why this file exists.** [CheckController] is composed into the app, and
/// `recognition/check.dart` decides everything a check decides — but a
/// controller nothing calls is a feature with no way in. Update checking is
/// **Free** and one of the things the app does *for* a user (CLAUDE.md,
/// "Free and Pro"), so it needs a control, and this is it.
///
/// Three rules the flow carries:
///
/// * **A check is content-affecting source automation**, so it is user-started,
///   visible, bounded and cancellable. Started here; visible in
///   `running_operation_panel.dart`; bounded by [kCollectionCheckLimits],
///   which the start sheet states in words before anything opens; cancelled
///   through [CheckController.cancel].
/// * **The gate is about where the user waits, never whether the check runs.**
///   Backing out of the sheet starts nothing and changes nothing.
/// * **Nothing is downloaded.** A check reads a listing and writes rows. The
///   copy says so, in the sheet and again in the panel, because a Browser
///   moving on its own reads as a download to anyone who was not told.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capability/foreground_gate.dart';
import '../providers.dart';
import '../recognition/check.dart';
import 'foreground_gate_sheet.dart';

/// What one check may read, and what it may bring in.
///
/// Constants rather than a config object the user never sees: they are stated
/// verbatim in the start sheet below, which is what makes them *a ceiling the
/// user can see* rather than an internal bound. Raising one means changing the
/// sentence in the same edit.
const kCollectionCheckLimits = SourceCheckLimits(
  maxPages: 3,
  maxNewEntries: 50,
);

/// Ask, then check [collectionId]'s preferred Source.
///
/// Returns the outcome, or null when nothing ran — a dismissed sheet, a check
/// already in flight, a Browser something else owns, or a Source on a service
/// this app does not read from. Every one of those is an ordinary answer, and
/// none of them writes a row.
Future<SourceCheckOutcome?> startCollectionCheck(
  BuildContext context,
  WidgetRef ref,
  String collectionId, {
  required String collectionName,
}) async {
  final check = ref.read(checkControllerProvider);
  if (check.isRunning) {
    _say(context, 'A check is already running.');
    return null;
  }

  final choice = await showStartOptionsSheet(
    context: context,
    ref: ref,
    action: ForegroundGateAction.startCollectionCheck,
    title: 'Check $collectionName for new entries?',
    // What it actually does, not what the limits allow. The production
    // reading takes one page — `BrowserSourceObservationSource` reports no
    // continuation — so promising "up to 3 pages" described a ceiling nothing
    // reaches, and the sentence a user reads before consenting has to be true.
    summary:
        'Scrollary opens this collection\'s site in the Browser and reads its '
        'list of entries — one page, adding at most '
        '${kCollectionCheckLimits.maxNewEntries} new entries. '
        'Nothing is downloaded. You can stop it at any point.',
  );
  if (choice == null || !context.mounted) return null;

  if (choice == StartChoice.enableAndKeepUsingApp) {
    await setKeepWorkingPreference(ref, true);
    if (!context.mounted) return null;
  }

  // Browser first, automation second. `showBrowserSurfaceWith` is the one
  // mechanism the whole app opens the Browser with, and the surface has to be
  // *drawn* before the check opens a page — `CheckController.run` waits for
  // that itself, so this only makes sure there is something to wait for.
  if (choice == StartChoice.inBrowser) {
    ref.read(shellTabRequestProvider).value = 1;
  }

  final outcome = await check.run(collectionId, limits: kCollectionCheckLimits);
  if (!context.mounted) return outcome;
  _say(context, checkOutcomeSentence(outcome));
  return outcome;
}

/// What happened, in one sentence.
///
/// "Finished" and "the check stopped short" are different outcomes and are
/// never folded into one: a reading cut by its own ceiling still found what it
/// found, and saying "up to date" about it would be a claim the check never
/// made.
String checkOutcomeSentence(SourceCheckOutcome? outcome) {
  if (outcome == null) {
    return 'Nothing was checked — this collection has no site to read right '
        'now.';
  }
  final found = outcome.newEntryIds.length;
  final stop = outcome.stopReason;

  // A reading that was cut short still found what it found, and a reading that
  // could not happen at all found nothing — those are different sentences, and
  // the second must never invite the user to repeat an action that cannot
  // succeed. Each stop below says what is actually wrong, and what would fix
  // it where anything would.
  final refusal = switch (stop) {
    SourceCheckStop.preferredSourceNotChosen =>
      'This collection is published on more than one site. Choose which one '
          'to check from its Sources.',
    SourceCheckStop.collectionNotFollowed =>
      'This collection is archived, so it is not being kept current. Follow '
          'it again to check it.',
    SourceCheckStop.sourceNotReadable =>
      'The site this collection was published on is marked as gone, so there '
          'is nothing to read.',
    SourceCheckStop.sourceUnknown =>
      'This collection has no site recorded, so there is nothing to check.',
    // Not [kCaptureRestrictedMessage]: that sentence is about *saving*, and
    // a check saves nothing. Same policy, same posture — the app's own
    // refusal, never something the site did — said about the right act.
    SourceCheckStop.captureRestrictedForSite =>
      'This collection\'s site is one Scrollary does not read from.',
    SourceCheckStop.listingUnreadable =>
      'That page would not load, so nothing could be read from it.',
    SourceCheckStop.listingUnrecognised =>
      'That page did not look like this collection\'s list of entries, so '
          'nothing was read from it.',
    SourceCheckStop.listingTruncated =>
      'Only part of the list could be read, so nothing was concluded from it.',
    SourceCheckStop.listingOrderingAmbiguous =>
      'The list did not run in an order Scrollary could follow, so nothing '
          'was concluded from it.',
    SourceCheckStop.entryIdentityUnsupported =>
      'The list contradicted itself about an entry\'s number, so the reading '
          'was stopped rather than guessed at.',
    _ => null,
  };

  if (stop == SourceCheckStop.cancelledByUser) {
    return found == 0
        ? 'Stopped. Nothing was added, and nothing was removed.'
        : 'Stopped. The $found found so far are in your library.';
  }

  // These end the reading before it can claim anything, so they never carry a
  // count — and they never say "check again", because checking again does the
  // same thing.
  if (refusal != null && found == 0) return refusal;

  final added = found == 1 ? '1 new entry' : '$found new entries';
  // A Source that stops listing something is news, and V2 has always computed
  // it and never said it. Said calmly and with the reassurance attached,
  // because "no longer listed" and "deleted from your device" are different
  // things and only the first happened.
  final retracted = outcome.discovery.retractedLocationIds.length;
  final gone = retracted == 0
      ? ''
      : retracted == 1
      ? ' 1 entry is no longer listed on this site — nothing on this device '
            'was deleted.'
      : ' $retracted entries are no longer listed on this site — nothing on '
            'this device was deleted.';
  // The ceilings are the one case where checking again genuinely continues:
  // the reading stopped because it had taken as much as it is allowed to, not
  // because anything was wrong.
  final hasMore =
      stop == SourceCheckStop.pageLimitReached ||
      stop == SourceCheckStop.newEntryLimitReached;

  if (found == 0) {
    return hasMore
        ? 'Read what it is allowed to in one go and found nothing new — check '
              'again to carry on.$gone'
        : 'Up to date. Nothing new on this collection\'s site.$gone';
  }
  return hasMore
      ? '$added added. There is more of the list to read — check again to '
            'carry on.$gone'
      : '$added added to your library. Nothing was downloaded.$gone';
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
