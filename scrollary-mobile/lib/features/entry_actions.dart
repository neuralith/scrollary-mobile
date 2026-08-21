import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../save/save_preflight.dart';
import '../core/config.dart';
import '../core/connectivity.dart';
import '../core/url_utils.dart';
import '../providers.dart';
import 'save_queue_ui.dart';
import 'open_in_browser.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// Injectable so a widget test can say "this device is offline" without one.
final connectivityProvider = Provider<Connectivity>(
  (ref) => const Connectivity(),
);

/// Whether an entry still knows where it came from.
///
/// `sourceUrl` is non-null in the schema, but a row written by an older build
/// (or repaired from a manifest that lacked one) can hold an empty string, and
/// a blank URL must disable the action rather than navigate somewhere wrong.
bool hasUsableSourceUrl(Entry entry) {
  final url = entry.sourceUrl.trim();
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}

/// Is this entry readable from local files right now?
bool isReadableOffline(Entry entry) =>
    entry.contentPath != null &&
    (entry.saveStatus == 'complete' || entry.saveStatus == 'partial');

/// Open an entry's own page in the app's Browser.
///
/// Kept as the name every entry surface calls, but the navigation itself
/// lives in [openEntryInBrowser] — one coordinator, because the previous
/// version did half of it (told the controller, switched the shell's tab) and
/// the user, standing on a route pushed *above* the shell, saw nothing
/// change.
///
/// The guarantee that stays here: **the stored URL or nothing.** No fallback
/// to the collection page and no guess from a sibling entry — sending someone
/// to a different entry of a different collection is worse than not moving at
/// all (D42).
///
/// Returns true when the Browser was actually sent somewhere.
Future<bool> openEntryOnWebsite(
  BuildContext context,
  WidgetRef ref,
  Entry entry,
) => openEntryInBrowser(context, ref, entry);

/// What tapping an entry with no offline files offers.
///
/// The reader is deliberately not opened: there is nothing to read, and an
/// "unavailable" screen the user has to back out of is a worse answer than
/// the two things they might actually want.
Future<void> showUnavailableEntrySheet(
  BuildContext context,
  WidgetRef ref,
  Entry entry,
) async {
  final knowsSource = hasUsableSourceUrl(entry);
  final removed = entry.offlineRemovedAt != null;
  // Only app-made metadata may be forgotten, and the predicate that decides
  // that is the database's — the same one automatic reconciliation uses. This
  // asks it rather than restating it as `saveStatus == …`; whether a save is
  // waiting is the queue's half of the answer and is asked on the tap.
  final isDiscovery = isDiscoveredOnlyEntry(entry);
  final lastAttemptFailed = isDiscovery && entry.saveError != null;
  final label = entry.sourceMarker?.trim().isNotEmpty == true
      ? entry.sourceMarker!.trim()
      : entry.title;

  await showModalBottomSheet<void>(
    context: context,
    // A two-line header plus three actions does not fit in the default
    // 9/16-height sheet on a short screen, and the bottom action is the one
    // that gets clipped.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      size: 14,
                      weight: FontWeight.w500,
                      color: AppPalette.of(context).ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    removed
                        ? 'Not available offline — you removed its files. '
                              'Your reading history is still here.'
                        : lastAttemptFailed
                        ? 'The last attempt to save this did not finish, so it '
                              'is left out of “Save new”. Try it on its own, '
                              'or forget it.'
                        : 'Not available offline yet.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppPalette.of(context).inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 18),
            ListTile(
              enabled: knowsSource,
              leading: Icon(
                Icons.public,
                color: knowsSource ? null : AppPalette.of(context).inkDisabled,
              ),
              title: const Text('Open on website'),
              subtitle: Text(
                knowsSource
                    ? hostOf(entry.sourceUrl)
                    : 'The original page is unknown for this entry',
              ),
              onTap: knowsSource
                  ? () {
                      Navigator.of(sheetContext).pop();
                      unawaitedOpen(context, ref, entry);
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(
                lastAttemptFailed ? 'Try saving again' : 'Add to save queue',
              ),
              subtitle: const Text('Waits until you start the queue'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveAgain(context, ref, entry);
              },
            ),
            if (isDiscovery)
              ListTile(
                key: const ValueKey('forgetEntry'),
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Forget this entry'),
                subtitle: const Text(
                  'Removes it from the list of what the source has. Nothing '
                  'was downloaded, so nothing is deleted from this device.',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _forget(context, ref, entry);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Fire-and-forget wrapper: the sheet is already closing, and awaiting inside
/// its `onTap` would hold a dead context.
void unawaitedOpen(BuildContext context, WidgetRef ref, Entry entry) {
  openEntryOnWebsite(context, ref, entry);
}

/// Forget one entry this app only ever *found*.
///
/// The manual counterpart to what a reliable check does on its own, for the
/// entries a check cannot speak for: one below the stretch of the source it
/// could read, one with no number to place, one in a collection with no entry
/// list to read at all.
///
/// The decision is not made here. `forgetDiscoveredEntry` re-reads the row and
/// the queue inside the transaction that deletes it, so an entry that has been
/// saved in the meantime, or that a save is now waiting on, is refused — and
/// the refusal is said, because an action that quietly did nothing would just
/// be tapped again.
Future<void> _forget(BuildContext context, WidgetRef ref, Entry entry) async {
  final result = await ref
      .read(databaseProvider)
      .forgetDiscoveredEntry(entry.id);
  if (!context.mounted) return;
  final refusal = result.refusal;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        refusal ?? 'Forgotten. It will come back if the source lists it again.',
      ),
    ),
  );
}

Future<void> _saveAgain(
  BuildContext context,
  WidgetRef ref,
  Entry entry,
) async {
  if (!hasUsableSourceUrl(entry)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "This entry's original page is unknown, so it can't be saved "
          'again.',
        ),
      ),
    );
    return;
  }
  final result = await ref
      .read(taskQueueProvider)
      .enqueueSave(
        startUrl: entry.sourceUrl,
        entryLimit: 1,
        collectionId: entry.collectionId,
        policy: DuplicatePolicy.replaceAll,
        range: SaveScope.currentPageOnly,
      );
  // Asking for this one again *is* the retry, so the note that kept it out of
  // "save the new entries" goes. A failure this app could not classify should
  // not exile an entry from the batch forever, and the person who just tapped
  // it knows more about whether it was worth another try than any rule here.
  if (isDiscoveredOnlyEntry(entry) && entry.saveError != null) {
    await ref.read(databaseProvider).clearDiscoveryCaptureFailure(entry.id);
  }
  if (!context.mounted) return;
  // Queued, not started: the user stays exactly where they are (D46).
  showQueuedConfirmation(context, result);
}

/// "Open on website" as a row for an *available* entry's overflow sheet.
///
/// Offered, never promoted: tapping an offline entry still opens the
/// reader. This is for going back to the source — comments, a correction, the
/// page as the site renders it.
Widget openOnWebsiteTile(
  BuildContext context,
  WidgetRef ref,
  Entry entry, {
  VoidCallback? beforeOpen,
}) {
  final knowsSource = hasUsableSourceUrl(entry);
  return ListTile(
    enabled: knowsSource,
    leading: Icon(
      Icons.public,
      color: knowsSource ? null : AppPalette.of(context).inkDisabled,
    ),
    title: const Text('Open on website'),
    subtitle: Text(
      knowsSource
          ? hostOf(entry.sourceUrl)
          : 'The original page is unknown for this entry',
    ),
    onTap: knowsSource
        ? () {
            beforeOpen?.call();
            unawaitedOpen(context, ref, entry);
          }
        : null,
  );
}
