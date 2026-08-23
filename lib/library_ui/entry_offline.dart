/// Getting a copy of an Entry onto this device, and freeing it again
/// (roadmap D5).
///
/// Both verbs are **this device**, and every sentence in this file says so
/// (PRODUCT.md §2.4). Downloading is a per-device capability of an Entry that
/// is already in the library; freeing the bytes leaves the Entry, its
/// Locations, its reading state and every other device exactly as they were.
///
/// The queue's rules are V1's, and they are not restated here — they are
/// *used*:
///
/// * **Nothing starts itself.** Asking for a download writes a `queued` row and
///   stops. The Start is a separate, explicit act, its authorisation lives in
///   memory only, and this lane cannot run the work either way: driving the
///   Browser belongs to whatever is attached to [saveQueueStarterProvider].
/// * **Cancelling preserves the row.** A waiting row goes on a tap with an Undo
///   that restores it *in place* — `restoreQueued` keeps its `order_index` —
///   and a running one gets a dialog and stops at its next safe point, because
///   stopping is cooperative everywhere.
/// * **Only a terminal row can be removed from activity.** A live row is
///   cancelled, never dropped, and dropping a terminal one deletes no Entry, no
///   file and no reading state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../save/entry_capture.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../features/cleanup_dialogs.dart';
import 'collection_models.dart';
import 'library_widgets.dart';
import 'providers.dart';

// ─── the row's queue state ──────────────────────────────────────────────────

/// What the queue is doing about one Entry, on its row — or **null** when the
/// answer is "nothing worth a badge".
///
/// Three states print: waiting, downloading, and failed. A completed row prints
/// nothing, because the row already says *On this device* and two badges for
/// one fact is how a list starts lying about which one is current. A cancelled
/// row prints nothing either — the user was told when they cancelled it, and a
/// permanent badge for a decision they already made is nagging, not honesty.
///
/// Null rather than an empty box: the row spaces its badges, and a spacer for
/// an invisible chip is a gap with no cause.
Widget? entryQueueChip(BuildContext context, SaveTask? task) {
  if (task == null) return null;
  final look = _queueLook(task.state, AppPalette.of(context));
  if (look == null) return null;
  return StatusChip(
    key: ValueKey('queueChip-${task.entryId}'),
    icon: look.icon,
    label: look.label,
    bg: look.bg,
    fg: look.fg,
    border: look.border,
  );
}

({IconData icon, String label, Color bg, Color fg, Color border})? _queueLook(
  SaveTaskState state,
  AppPalette palette,
) => switch (state) {
  SaveTaskState.queued => (
    icon: Icons.schedule,
    label: 'Waiting to start',
    bg: palette.surfaceHigh,
    fg: palette.inkMuted,
    border: palette.border,
  ),
  SaveTaskState.running => (
    icon: Icons.downloading,
    label: 'Downloading',
    bg: palette.primaryContainer,
    fg: palette.onPrimaryContainer,
    border: palette.primaryBorder,
  ),
  SaveTaskState.failed => (
    icon: Icons.error_outline,
    label: 'Download failed',
    bg: palette.dangerContainer,
    fg: palette.onDangerContainer,
    border: palette.dangerBorder,
  ),
  SaveTaskState.completed || SaveTaskState.cancelled => null,
};

/// One line about the queue row, for the sheet that offers to act on it.
///
/// A terminal row prints the outcome the queue recorded rather than a sentence
/// written here: "the site stopped us" and "you stopped it" are different
/// outcomes, and the row is where that difference is kept.
String saveTaskSentence(SaveTask task) => switch (task.state) {
  SaveTaskState.queued =>
    'Waiting in the download queue. Nothing starts until you start it.',
  SaveTaskState.running =>
    'Downloading now. Stopping it takes effect at the next safe point.',
  SaveTaskState.completed => task.outcome ?? 'Downloaded to this device.',
  SaveTaskState.failed =>
    task.outcome ?? task.lastError ?? 'The download did not finish.',
  SaveTaskState.cancelled => task.outcome ?? 'You stopped this download.',
};

// ─── asking for a copy ──────────────────────────────────────────────────────

/// Queue a download of [view] from the Entry's own address.
///
/// It **waits**. No page is opened, nothing is measured and no WebView is
/// touched by this call — the row exists so that a later, explicit Start has
/// something to run.
///
/// An Entry with no active Location is an ordinary case, not a failure: an
/// Entry is not a URL, and one whose addresses have all been retracted is
/// still in the library.
Future<void> downloadForOffline(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final location = await primaryLocation(
    ref.read(libraryDatabaseProvider),
    view.id,
  );
  if (!context.mounted) return;
  if (location == null) {
    showLibraryMessage(
      context,
      'No address is recorded for this entry, so there is nothing to '
      'download.',
    );
    return;
  }

  // The preflight, in the only two states V2 can actually tell apart: this
  // device holds a complete copy, or it holds one with gaps. V1 classified six
  // and offered eleven choices; most of them described a resume V2's capture
  // does not have, and offering a recovery the engine cannot perform is worse
  // than not offering it.
  final held = await ref
      .read(libraryUiServicesProvider)
      .offline
      .activeCopyOf(view.id);
  if (!context.mounted) return;
  if (held != null) {
    final manifest = await ref
        .read(libraryUiServicesProvider)
        .fileStore
        .readManifest(held.contentPath);
    if (!context.mounted) return;
    final gaps =
        manifest != null &&
        manifest.storedAssetCount < manifest.detectedAssetCount;
    final ok = await showRemovalConfirm(
      context: context,
      summary: RemovalSummary(
        title: gaps
            ? 'This copy is incomplete — download it again?'
            : 'Already downloaded — download it again?',
        body: gaps
            ? 'Some images could not be fetched last time. Downloading again '
                  'reads the page from the start and replaces what is here.'
            : 'This device already holds a complete copy. Downloading again '
                  'reads the page from the start and replaces it.',
        facts: [
          if (gaps)
            (
              'Images',
              '${manifest.storedAssetCount} of '
                  '${manifest.detectedAssetCount}',
            ),
        ],
        cta: 'Download again',
      ),
    );
    if (!ok || !context.mounted) return;
  }

  final result = await ref
      .read(saveQueueRepoProvider)
      .enqueue(
        entryId: view.id,
        locationId: location.id,
        locationUrl: location.url,
      );
  if (!context.mounted) return;
  // Refused by the restricted-site policy, in the policy's own sentence and no
  // other. No row was written, so there is nothing to start or retry.
  final refusal = result.refusedReason;
  if (refusal != null) {
    showLibraryMessage(context, refusal);
    return;
  }
  showLibraryMessage(
    context,
    result.alreadyQueued
        ? 'Already waiting in the download queue.'
        : 'Added to the download queue. Nothing starts until you start it.',
  );
}

/// The explicit Start: authorise the waiting rows, then hand them to whatever
/// runs them.
///
/// [firstTaskId] is V1's *Start this one*, which was never a second kind of
/// start: the row is moved to the front and the same queue runs. One Start, one
/// authorisation, and a count the user can see.
///
/// With no runner attached, **nothing is authorised** and nothing is reordered.
/// Authorising work that nothing will pick up would leave the queue in a state
/// the user was told was running, which is worse than a plain "not here yet".
Future<void> startQueuedDownloads(
  BuildContext context,
  WidgetRef ref, {
  String? firstTaskId,

  /// Where the user already said they would wait, when the flow that got here
  /// asked. Null means nobody has asked yet, and the starter asks — which is
  /// right for Activity, for a row's own menu and for the sheet's Start
  /// button, where this *is* the question. It is not right after a launch
  /// that has just been chosen, and asking again there was the second modal.
  StartWhere? decided,
}) async {
  final queue = ref.read(saveQueueRepoProvider);
  final starter = ref.read(saveQueueStarterProvider);
  final waiting = [
    for (final task in await queue.pending())
      if (task.state == SaveTaskState.queued) task,
  ];
  if (!context.mounted) return;
  if (waiting.isEmpty) {
    showLibraryMessage(context, 'Nothing is waiting to be downloaded.');
    return;
  }
  if (starter == null) {
    showLibraryMessage(
      context,
      'Downloading runs in the browser, which is not available from here '
      'yet. Nothing was started, and your queue is unchanged.',
    );
    return;
  }
  if (firstTaskId != null) await queue.moveToFront(firstTaskId);
  queue.authoriseStart();
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    'Starting ${waiting.length} download${waiting.length == 1 ? '' : 's'}.',
  );
  await starter(decided: decided);
}

// ─── stopping ───────────────────────────────────────────────────────────────

/// Cancel a waiting row and say so, with the way back.
///
/// No dialog: nothing has run and nothing is discarded, so an Undo that puts
/// the row back **where it was** is a better answer to a mis-tap than a modal
/// asking about work that does not exist yet.
Future<void> removeWaitingDownload(
  BuildContext context,
  WidgetRef ref,
  SaveTask task,
) async {
  final queue = ref.read(saveQueueRepoProvider);
  final outcome = await queue.cancel(task.id);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (outcome != SaveCancelOutcome.cancelledBeforeStart) {
    // It started while the finger was moving. Reporting a clean removal would
    // be a lie about work that is currently running.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('downloadRemoveRaced'),
          content: Text(
            outcome == SaveCancelOutcome.stoppingRunning
                ? 'It had already started — stopping it at the next safe '
                      'point.'
                : 'That download is no longer waiting.',
          ),
        ),
      );
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('downloadRemoved'),
        content: const Text(
          'Removed from the download queue · nothing on this device was '
          'deleted',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => queue.restoreQueued(task.id),
        ),
      ),
    );
}

/// Ask before stopping a download that is already under way, then ask it to
/// stop.
///
/// The row is written `cancelled` the moment the user asks — that is what makes
/// a cancellation survive a kill — and the worker stops at its next safe
/// boundary. Nothing here kills anything mid-write, which is why the wording is
/// "at the next safe point" and not "immediately".
Future<void> stopRunningDownload(
  BuildContext context,
  WidgetRef ref,
  SaveTask task,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Stop this download?'),
      content: const Text(
        'It stops at the next safe point. Nothing already on this device is '
        'removed, the entry stays in your library, and it can be downloaded '
        'again later.',
        style: TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep going'),
        ),
        FilledButton(
          key: const ValueKey('confirmStopDownload'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Stop download'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await ref.read(saveQueueRepoProvider).cancel(task.id);
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    outcome == SaveCancelOutcome.stoppingRunning
        ? 'Stopping at the next safe point.'
        : 'That download had already finished.',
  );
}

/// *Retry*: put a failed download back at the end of the queue.
///
/// Recovery is Free and has always been (docs/V2_CAPABILITY_PARITY.md). The
/// repository does the work — a terminal row becomes a fresh `queued` one, and
/// the restricted-site policy refuses it there rather than here, so a history
/// row on a service this app does not capture from cannot be turned back into
/// work that runs.
///
/// Like every other enqueue, this **waits**: nothing navigates and nothing is
/// fetched until the user presses Start.
Future<void> retryDownload(
  BuildContext context,
  WidgetRef ref,
  SaveTask task,
) async {
  final again = await ref.read(saveQueueRepoProvider).retry(task.id);
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    again == null
        ? 'That download cannot be retried.'
        : 'Back in the queue. Nothing starts until you start it.',
  );
}

/// *Run this next*: move one waiting row to the front of the queue.
///
/// Not a second kind of start — the row still waits, and Start still
/// authorises the batch. It is the one piece of queue ordering worth keeping:
/// "I want that one first" is a real intention, and V1's full move-up /
/// move-down pair was queue micromanagement on a phone.
Future<void> runDownloadNext(
  BuildContext context,
  WidgetRef ref,
  SaveTask task,
) async {
  await ref.read(saveQueueRepoProvider).moveToFront(task.id);
  if (!context.mounted) return;
  showLibraryMessage(context, 'Moved to the front of the queue.');
}

/// *Clear waiting*: cancel every row that has not started.
///
/// Each becomes `cancelled`, which is a state the user can see and retry from
/// — never a deletion. A running row is left alone: stopping that one is its
/// own decision, with its own confirmation.
Future<void> clearWaitingDownloads(BuildContext context, WidgetRef ref) async {
  final queue = ref.read(saveQueueRepoProvider);
  final waiting = (await queue.all())
      .where((t) => t.state == SaveTaskState.queued)
      .toList();
  if (waiting.isEmpty) {
    if (!context.mounted) return;
    showLibraryMessage(context, 'Nothing is waiting.');
    return;
  }

  if (!context.mounted) return;
  final ok = await showRemovalConfirm(
    context: context,
    summary: RemovalSummary(
      title: waiting.length == 1
          ? 'Remove the waiting download?'
          : 'Remove ${waiting.length} waiting downloads?',
      body:
          'They stop waiting and can be started again from the entry. '
          'Nothing on this device is deleted, and anything already '
          'downloading carries on.',
      facts: [('Waiting', '${waiting.length}')],
      cta: 'Remove',
    ),
  );
  if (!ok || !context.mounted) return;

  var removed = 0;
  for (final task in waiting) {
    if (await queue.cancel(task.id) == SaveCancelOutcome.cancelledBeforeStart) {
      removed++;
    }
  }
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    removed == 0
        ? 'Those had already started.'
        : '$removed removed from the queue.',
  );
}

/// *Remove from Activity*: drop one finished row.
///
/// Only a terminal row can be reached from here, and the repository refuses
/// anything else. Queue rows are never the content, so this deletes no Entry,
/// no file and no reading state.
Future<void> removeDownloadFromActivity(
  BuildContext context,
  WidgetRef ref,
  SaveTask task,
) async {
  final removed = await ref.read(saveQueueRepoProvider).removeTerminal(task.id);
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    removed
        ? 'Removed from activity. Nothing on this device was deleted.'
        : 'That download is still going — stop it first.',
  );
}

// ─── freeing the bytes ──────────────────────────────────────────────────────

/// Free this device's copy: the package, then the rows.
///
/// Files first and rows second is the capture lane's order and not this
/// screen's to change — rows first would leave a package under `library/` for a
/// later recovery pass to rebuild an Entry from. The confirmation names the one
/// device this affects, and *Remove offline copy* is never offered as a way to
/// remove anything from the library.
Future<void> removeOfflineCopyOf(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove the offline copy?'),
      content: Text(
        'Frees the bytes this device is holding for “${view.label}”. It stays '
        'in your library, your reading state is untouched, and no other '
        'device is affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove copy'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final removed = await removeOfflineCopies(
    entryId: view.id,
    offlineCopies: ref.read(offlineCopyRepoProvider),
    fileStore: ref.read(fileStoreProvider),
  );
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    removed == 0
        ? 'This device was not holding a copy.'
        : 'Copy removed from this device. The entry stays in your library.',
  );
}
