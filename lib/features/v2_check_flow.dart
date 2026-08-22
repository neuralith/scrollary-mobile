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
    summary:
        'Scrollary opens this collection\'s site in the Browser and reads its '
        'list — up to ${kCollectionCheckLimits.maxPages} pages, adding at '
        'most ${kCollectionCheckLimits.maxNewEntries} new entries. '
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
  final more = outcome.stopReason != null;
  if (outcome.stopReason == SourceCheckStop.cancelledByUser) {
    return found == 0
        ? 'Stopped. Nothing was added, and nothing was removed.'
        : 'Stopped. The $found found so far are in your library.';
  }
  if (outcome.isCaptureRestricted) {
    return 'This collection\'s site is one Scrollary does not read from.';
  }
  if (found == 0) {
    return more
        ? 'Read ${outcome.pagesRead} page(s) and found nothing new. There is '
              'more of the list to read — check again to continue.'
        : 'Up to date. Nothing new on this collection\'s site.';
  }
  final added = found == 1 ? '1 new entry' : '$found new entries';
  return more
      ? '$added added. There is more of the list to read — check again to '
            'continue.'
      : '$added added to your library. Nothing was downloaded.';
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
