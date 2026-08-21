import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../save/capture_policy.dart';
import '../save/save_preflight.dart';
import '../save/size_estimate.dart';
import '../library/collection_identity.dart';
import '../library/update_checker.dart';
import '../providers.dart';
import '../queue/task_queue.dart';
import '../reading/reading_repository.dart';
import '../storage/cleanup.dart';
import '../storage/database.dart';
import '../storage/manifest.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'save_queue_ui.dart';
import 'collection_delete_action.dart';
import 'entry_actions.dart';
import 'entry_details_sheet.dart';
import 'cleanup_dialogs.dart';
import '../library/entry_labels.dart';
import 'library_screen.dart'
    show
        LibraryCollection,
        CollectionWarning,
        confirmArchiveCollection,
        formatBytes,
        formatRelative;

/// The entries of one collection, in reading order, each opening the offline
/// reader.
class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    this.startInSelectionMode = false,
  });

  final String collectionId;

  /// Opened from Storage's "Choose entries to remove" — selection mode
  /// lives HERE, never on the Storage screen itself.
  final bool startInSelectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(libraryCollectionProvider(collectionId));

    return group.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
      ),
      data: (data) {
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Collection')),
            body: const Center(
              child: Text('This collection is no longer listed.'),
            ),
          );
        }
        return _CollectionDetail(
          group: data,
          startInSelectionMode: startInSelectionMode,
        );
      },
    );
  }
}

class _CollectionDetail extends ConsumerStatefulWidget {
  const _CollectionDetail({
    required this.group,
    this.startInSelectionMode = false,
  });

  final LibraryCollection group;
  final bool startInSelectionMode;

  @override
  ConsumerState<_CollectionDetail> createState() => _CollectionDetailState();
}

class _CollectionDetailState extends ConsumerState<_CollectionDetail> {
  /// Selected entry ids while in selection mode; null when not selecting.
  Set<String>? _selection;

  /// entryId → why it cannot be removed right now. Computed once when
  /// selection mode opens, not per row build (each lookup consults the
  /// reader lock and the running run).
  Map<String, String> _locks = const {};

  LibraryCollection get group => widget.group;
  bool get _selecting => _selection != null;

  @override
  void initState() {
    super.initState();
    if (widget.startInSelectionMode) {
      _selection = <String>{};
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLocks());
    }
  }

  void _enterSelection() {
    setState(() => _selection = <String>{});
    unawaited(_refreshLocks());
  }

  void _exitSelection() => setState(() {
    _selection = null;
    _locks = const {};
  });

  Future<void> _refreshLocks() async {
    final cleanup = ref.read(cleanupProvider);
    final locks = <String, String>{};
    for (final c in group.entries) {
      if (!cleanup.isRemovable(c)) continue;
      final reason = await cleanup.lockReasonFor(c);
      if (reason != null) locks[c.id] = reason;
    }
    if (mounted) setState(() => _locks = locks);
  }

  void _toggle(String id) => setState(() {
    final sel = _selection!;
    sel.contains(id) ? sel.remove(id) : sel.add(id);
  });

  Future<void> _selectAllOffline(List<Entry> entries) async {
    final removable = await _removableOf(entries);
    if (!mounted) return;
    setState(() => _selection = removable.map((c) => c.id).toSet());
  }

  Future<void> _selectFinished(List<Entry> entries) async {
    final removable = await _removableOf(
      entries.where((c) => c.readStatus == 'completed'),
    );
    if (!mounted) return;
    setState(() => _selection = removable.map((c) => c.id).toSet());
  }

  /// Everything this device does not currently hold — the selection a
  /// re-download batch starts from. Includes entries whose files the user
  /// removed AND entries only ever seen on the source (D48).
  void _selectMissing(List<Entry> entries) {
    setState(
      () => _selection = {
        for (final c in entries)
          if (!isReadableOffline(c)) c.id,
      },
    );
  }

  /// Finished entries whose files are gone: the "I read it, I freed the
  /// space, now I want it back" selection.
  void _selectRemovedFinished(List<Entry> entries) {
    setState(
      () => _selection = {
        for (final c in entries)
          if (!isReadableOffline(c) && c.readStatus == 'completed') c.id,
      },
    );
  }

  /// Queue the selection for re-download, oldest first.
  ///
  /// Nothing starts here: the batch joins the save queue and waits for an
  /// explicit start like every other save request (D46).
  Future<void> _confirmQueueSelection(List<Entry> all) async {
    final ids = _selection!;
    if (ids.isEmpty) return;
    final chosen = all.where((c) => ids.contains(c.id)).toList();
    final capturable = chosen.where(entryHasCapturableUrl).toList();
    final missing = chosen.where((c) => !entryHasCapturableUrl(c)).toList();

    // Estimate from what this collection has actually cost so far, not from a
    // constant — and from finished saves only, so a failed or half-written row
    // cannot drag the number around. The entries in this batch contribute
    // nothing by construction: they are the ones with no files.
    final estimate = estimateSaveSize(
      entryCount: capturable.length,
      historyBytes: CollectionSizeHistory.fromEntries(all).forArtifact(null),
    );

    final ok = await showBatchQueueConfirm(
      context: context,
      plan: BatchQueuePlan(
        collectionName: widget.group.displayName,
        capturable: capturable,
        missingSource: missing,
        estimate: estimate,
      ),
    );
    if (!ok || !mounted) return;

    final result = await ref.read(taskQueueProvider).enqueueEntries(chosen);
    if (!mounted) return;
    _exitSelection();
    showBatchQueuedConfirmation(context, result);
  }

  /// Remove the current selection, with the design's confirmation and an
  /// undo toast. Locked entries were filtered out of the selection already,
  /// but the service re-checks — the reader may have opened one meanwhile.
  Future<void> _confirmRemoveSelection(List<Entry> entries) async {
    final ids = _selection!;
    if (ids.isEmpty) return;
    final chosen = entries.where((c) => ids.contains(c.id)).toList();
    final bytes = chosen.fold<int>(0, (sum, c) => sum + c.byteSize);
    final n = chosen.length;

    final ok = await showRemovalConfirm(
      context: context,
      summary: RemovalSummary(
        title: 'Remove offline files?',
        body: n == 1
            ? 'This entry stays in your library — read marks, history and '
                  'source links are kept. It just will not be available '
                  'offline until saved again.'
            : 'These entries stay in your library — read marks, history and '
                  'source links are kept. They just will not be available '
                  'offline until saved again.',
        facts: [('Entries', '$n'), ('Space freed', '~${formatBytes(bytes)}')],
      ),
    );
    if (!ok || !mounted) return;

    final result = await ref
        .read(cleanupProvider)
        .removeOffline(chosen.map((c) => c.id).toList());
    if (!mounted) return;
    _exitSelection();
    showCleanupToast(
      context,
      text:
          '${group.labels.count(result.removed)} removed '
          'offline · ${formatBytes(result.freedBytes)} freed'
          '${result.keptLocked.isEmpty ? '' : ' · ${result.keptLocked.length} kept (in use)'}',
      undo: result.canUndo ? result.undo.undo : null,
    );
  }

  /// Remove every offline entry of this collection, through the queue: a
  /// hundreds-of-entries sweep deserves a visible task, not a frozen sheet.
  Future<void> _confirmRemoveCollection() async {
    final cleanup = ref.read(cleanupProvider);
    final offline = group.entries.where(cleanup.isRemovable).toList();
    if (offline.isEmpty) return;
    final removable = await _removableOf(offline);
    final locked = offline.length - removable.length;
    final bytes = removable.fold<int>(0, (sum, c) => sum + c.byteSize);
    if (!mounted) return;

    final ok = await showRemovalConfirm(
      context: context,
      summary: RemovalSummary(
        title: 'Remove offline files?',
        body:
            'Every stored entry of this collection will no longer be available '
            'offline. The collection, read marks and history stay in your '
            'library — you can save it again later.',
        facts: [
          ('Entries', '${removable.length}'),
          ('Space freed', '~${formatBytes(bytes)}'),
        ],
        lockNote: locked == 0
            ? null
            : '$locked entry${locked == 1 ? ' is' : 's are'} open or being '
                  'saved right now — they will be kept.',
      ),
    );
    if (!ok || !mounted) return;

    // Small collection: inline with undo. Large: a queue task with progress.
    if (removable.length <= 5) {
      final result = await cleanup.removeOffline(
        removable.map((c) => c.id).toList(),
      );
      if (!mounted) return;
      showCleanupToast(
        context,
        text:
            '${group.labels.count(result.removed)} '
            'removed offline · ${formatBytes(result.freedBytes)} freed',
        undo: result.canUndo ? result.undo.undo : null,
      );
      return;
    }
    await ref.read(taskQueueProvider).enqueueCleanup(collectionId: group.id);
    if (!mounted) return;
    showCleanupToast(
      context,
      text: 'Removing offline files — progress in Activity',
    );
  }

  /// Entries whose files can actually go: offline, and not in use.
  Future<List<Entry>> _removableOf(Iterable<Entry> candidates) async {
    final cleanup = ref.read(cleanupProvider);
    final out = <Entry>[];
    for (final c in candidates) {
      if (!cleanup.isRemovable(c)) continue;
      if (await cleanup.lockReasonFor(c) != null) continue;
      out.add(c);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sort = ref.watch(entrySortProvider).value ?? EntrySort.newestFirst;
    // Reading order drives selection helpers and the reading state; the list
    // itself is presented in the user's chosen direction.
    final readingOrder = sortEntriesForReading(group.savedEntries);
    final entries = sortEntries(group.savedEntries, sort);
    final knownRemote = sortEntries(group.knownRemoteEntries, sort);
    final reading = computeCollectionReadingState(group.entries);
    final resume = reading.continueEntry;
    final checker = ref.watch(updateCheckerProvider);
    final warning = group.warningLine(palette);
    final bytes = group.entries.fold<int>(0, (sum, c) => sum + c.byteSize);

    return Scaffold(
      appBar: _selecting
          ? AppBar(
              backgroundColor: palette.primaryContainer,
              foregroundColor: palette.onPrimaryContainer,
              iconTheme: IconThemeData(color: palette.onPrimaryContainer),
              actionsIconTheme: IconThemeData(
                color: palette.onPrimaryContainer,
              ),
              titleTextStyle: TextStyle(
                fontFamily: 'IBM Plex Sans',
                fontSize: 15,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.onPrimaryContainer,
              ),
              leading: IconButton(
                icon: const Icon(Icons.close, size: 24),
                tooltip: 'Cancel selection',
                onPressed: _exitSelection,
              ),
              title: Text('${_selection!.length} selected'),
              actions: [
                // A menu, not four buttons: the quick-selects outgrew the
                // width of a 320pt app bar the moment re-download joined
                // removal.
                PopupMenuButton<String>(
                  icon: const Icon(Icons.checklist, size: 22),
                  tooltip: 'Select…',
                  onSelected: (choice) => switch (choice) {
                    'offline' => _selectAllOffline(readingOrder),
                    'finished' => _selectFinished(readingOrder),
                    'missing' => _selectMissing(readingOrder),
                    'removedFinished' => _selectRemovedFinished(readingOrder),
                    _ => setState(() => _selection = <String>{}),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'offline', child: Text('All offline')),
                    PopupMenuItem(value: 'finished', child: Text('Finished')),
                    PopupMenuItem(
                      value: 'missing',
                      child: Text('Not downloaded'),
                    ),
                    PopupMenuItem(
                      value: 'removedFinished',
                      child: Text('Finished · files removed'),
                    ),
                    PopupMenuItem(value: 'none', child: Text('Clear')),
                  ],
                ),
              ],
            )
          : AppBar(
              title: Text(group.displayName, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 22),
                  tooltip: 'Collection actions',
                  onPressed: () => _showMenu(context, ref),
                ),
              ],
            ),
      bottomNavigationBar: _selecting
          ? _SelectionBar(
              selected: _selection!,
              entries: entries,
              onCancel: _exitSelection,
              onRemove: () => _confirmRemoveSelection(entries),
              onQueue: () => _confirmQueueSelection(entries),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonogramTile(
                  id: group.id,
                  title: group.displayName,
                  size: 56,
                  radius: 14,
                  fontSize: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.displayName, style: serifStyle(size: 22)),
                      const SizedBox(height: 5),
                      Text(
                        group.host,
                        style: monoStyle(color: palette.inkFaint),
                      ),
                      if (group.userTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Renamed by you · source title: ${group.title}',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.inkFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // The accent chip carries a border as well as a tint: under a
                // device warm filter the teal loses most of its blue, so hue
                // alone cannot be what separates it from the neutral ones.
                _MetaChip(
                  icon: Icons.download_for_offline,
                  iconColor: palette.onPrimaryContainer,
                  label: '${group.offlineCount} offline',
                  bg: palette.primaryContainer,
                  border: palette.primaryBorder,
                  fg: palette.onPrimaryContainer,
                ),
                _MetaChip(
                  icon: Icons.circle,
                  iconSize: 9,
                  iconColor: palette.primary,
                  label: '${group.unreadOfflineCount} unread',
                  bg: palette.surfaceHigh,
                  border: palette.border,
                  fg: palette.inkStrong,
                ),
                if (bytes > 0)
                  _MetaChip(
                    icon: Icons.folder,
                    iconColor: palette.inkFaint,
                    label: formatBytes(bytes),
                    bg: palette.surfaceHigh,
                    border: palette.border,
                    fg: palette.inkStrong,
                  ),
              ],
            ),
          ),
          if (warning != null) _WarningCard(group: group, warning: warning),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: resume == null
                        ? null
                        : () => context.push('/reader/${resume.id}'),
                    icon: const Icon(Icons.play_arrow, size: 20),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    label: Text(
                      resume == null
                          ? 'Nothing to read yet'
                          : '${reading.currentEntry != null ? 'Continue' : 'Read'} '
                                '· ${resume.sourceMarker ?? resume.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (group.lifecycle == 'archived')
            _ArchivedBanner(group: group)
          else
            _UpdateCheckCard(group: group, checker: checker),
          if (knownRemote.isNotEmpty)
            _RemoteEntries(
              entries: knownRemote,
              onSave: () => _saveNewEntries(context, ref, knownRemote),
            ),
          SectionLabel(
            // The section label speaks this collection's own vocabulary, from
            // the stored shape — never a noun typed into a screen.
            '${group.labels.Many.toUpperCase()} SAVED · ${entries.length}',
            trailing: _EntrySortToggle(sort: sort),
          ),
          const Divider(),
          for (final entry in entries) ...[
            _EntryRow(
              entry: entry,
              selecting: _selecting,
              selected: _selection?.contains(entry.id) ?? false,
              lockReason: _locks[entry.id],
              onToggle: () => _toggle(entry.id),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        // Seven actions do not fit in the default 9/16-height sheet, and the
        // one that gets clipped is always the last — which is now the
        // destructive one. Same fix, and the same reason, as the entry sheet
        // in `entry_actions.dart`.
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Rename'),
                  subtitle: const Text('Your name, source title kept'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _promptRename(context, ref, group);
                  },
                ),
                if (group.lifecycle != 'archived')
                  ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: const Text('Archive'),
                    subtitle: const Text('Hidden from library · reversible'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final archived = await confirmArchiveCollection(
                        context,
                        ref,
                        group,
                      );
                      // Back to the library: the collection just left it, and
                      // staying here would imply it did not.
                      if (archived && context.mounted) context.pop();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('Manage downloads'),
                  subtitle: const Text('Select entries · remove offline files'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _enterSelection();
                  },
                ),
                ListTile(
                  key: const ValueKey('collectionCleanupPrefEntry'),
                  leading: const Icon(Icons.auto_delete),
                  title: const Text('Downloaded entries'),
                  subtitle: Text(
                    collectionCleanupSummary(
                      collectionCleanupFromName(group.cleanupPreference),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showCollectionCleanupSheet(
                      context: context,
                      ref: ref,
                      collectionId: group.id,
                      collectionName: group.displayName,
                      current: collectionCleanupFromName(
                        group.cleanupPreference,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep),
                  title: const Text('Remove offline files…'),
                  subtitle: const Text(
                    'Whole collection · keeps history and read marks',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmRemoveCollection();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.ads_click),
                  title: const Text('Element rules'),
                  subtitle: Text(group.host),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/rules');
                  },
                ),
                // Everything above leaves the collection in the library. This
                // does not, so it sits below a rule, in the danger colour, at
                // the far end of the sheet — a tap meant for "Element rules"
                // must not be able to land on it.
                if (group.collection != null) ...[
                  const Divider(height: 12),
                  ListTile(
                    key: const ValueKey('deleteCollectionEntry'),
                    leading: Icon(
                      Icons.delete_forever,
                      color: AppPalette.of(context).danger,
                    ),
                    title: Text(
                      'Delete permanently',
                      style: TextStyle(color: AppPalette.of(context).danger),
                    ),
                    subtitle: const Text(
                      'Removes the collection, its entries and their files',
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDeleteCollection();
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );

  /// Permanent deletion, and the way off this screen.
  ///
  /// The router is read before anything is awaited, and the pop runs the
  /// moment the user confirms — see [confirmDeleteCollection] for why leaving
  /// first is the safe order. If there is nothing to pop back to, this
  /// screen's own "no longer listed" state is the landing instead.
  Future<void> _confirmDeleteCollection() async {
    final router = GoRouter.of(context);
    await confirmDeleteCollection(
      context,
      ref,
      group,
      onConfirmed: () {
        if (router.canPop()) router.pop();
      },
    );
  }

  /// Queue a bounded save over the discovered entries' own URLs (M14:
  /// all autonomous work goes through the activity queue, so it shows up in
  /// history and serializes on the shared WebView by construction).
  ///
  /// One single-page task per discovered entry, in **reading order** — which
  /// [TaskQueueController.enqueueEntries] establishes, whatever order this
  /// list was being *shown* in. The list arrives display-sorted, and the
  /// default display sort is newest-first: reading `.first` off it started
  /// the fetch at the newest entry (91 of 74–91) instead of the oldest, so a
  /// partially finished batch left a hole at the front of the collection
  /// rather than a contiguous block.
  ///
  /// `skipComplete`, not `ask`: the user just said "save the new ones", so an
  /// entry that is already held is skipped quietly — that is the request, not
  /// a surprise.
  ///
  /// One that has already been tried and failed is left out, and the section
  /// says how many and why. This app cannot tell a page the source withdrew
  /// from one that timed out, so it does not guess — but re-queueing the same
  /// failing address on every press is a loop with no way out of it, and the
  /// entry is still there to retry on its own.
  Future<void> _saveNewEntries(
    BuildContext context,
    WidgetRef ref,
    List<Entry> knownRemote,
  ) async {
    final queue = ref.read(taskQueueProvider);
    final result = await queue.enqueueEntries(
      knownRemote.where((e) => e.saveError == null).toList(),
      policy: DuplicatePolicy.skipComplete,
    );
    if (!context.mounted) return;
    // Queued, not started. They wait like everything else — the Browser opens
    // when the user starts the queue, not because they tapped "save new" (D46).
    showBatchQueuedConfirmation(context, result);
  }

  Future<void> _promptRename(
    BuildContext context,
    WidgetRef ref,
    LibraryCollection group,
  ) async {
    final controller = TextEditingController(text: group.displayName);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 8),
            Text(
              'Only what is shown here changes. Source URLs, stored files and '
              'how future saves are matched all stay as they are.',
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.of(context).inkMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (group.userTitle != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Reset'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref
        .read(collectionRepositoryProvider)
        .rename(group.id, result.trim().isEmpty ? null : result);
  }
}

/// The docked selection bar: how many, roughly how much space, and the two
/// ways out. Disabled-looking until something is selected.
/// One bar, two opposite actions, each live only when the selection actually
/// contains something it can act on — so "Remove files" cannot be pressed on
/// a selection of entries that have none, and vice versa.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selected,
    required this.entries,
    required this.onCancel,
    required this.onRemove,
    required this.onQueue,
  });

  final Set<String> selected;
  final List<Entry> entries;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final chosen = entries.where((c) => selected.contains(c.id)).toList();
    final bytes = chosen.fold<int>(0, (sum, c) => sum + c.byteSize);
    final any = selected.isNotEmpty;
    final withFiles = chosen.where(isReadableOffline).length;
    final queueable = chosen
        .where((c) => !isReadableOffline(c) && entryHasCapturableUrl(c))
        .length;
    final noSource = chosen
        .where((c) => !isReadableOffline(c) && !entryHasCapturableUrl(c))
        .length;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${selected.length} selected',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !any
                      ? 'select entries below'
                      : [
                          if (withFiles > 0)
                            '$withFiles offline · ~${formatBytes(bytes)}',
                          if (queueable > 0) '$queueable can be queued',
                          if (noSource > 0) '$noSource have no source page',
                        ].join(' · '),
                  maxLines: 2,
                  style: monoStyle(size: 11.5, color: palette.inkMuted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 4),
          // Flexible + scale-down: these labels are the longest strings in
          // the bar, and the counts column beside them is what actually has
          // to stay readable.
          Flexible(
            child: queueable > 0
                ? FilledButton(
                    key: const ValueKey('queueSelectionButton'),
                    onPressed: onQueue,
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Add to queue'),
                    ),
                  )
                : FilledButton(
                    key: const ValueKey('removeSelectionButton'),
                    onPressed: withFiles > 0 ? onRemove : null,
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Remove files'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.border,
    required this.fg,
    required this.iconColor,
    this.iconSize = 15,
  });

  final IconData icon;
  final String label;
  final Color bg, border, fg, iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: fg)),
      ],
    ),
  );
}

/// Partial and failed saves get one amber card that says which entries and
/// what it means for reading — not a red banner that implies data loss.
class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.group, required this.warning});

  final LibraryCollection group;
  final CollectionWarning warning;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final failed = group.failedEntries > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: failed ? palette.dangerContainer : palette.warnContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: failed ? palette.dangerBorder : palette.warnBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning.icon, size: 20, color: warning.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warning.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: failed
                        ? palette.onDangerContainer
                        : palette.onWarnContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? 'The source layout may have changed. Save again, '
                            'and point at the content if it fails once more.'
                      : 'Some images are missing. Those entries are still '
                            'readable — save again to fill the gaps.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: failed
                        ? palette.onDangerContainer
                        : palette.onWarnContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An archived collection does not get checked — the card that would offer a
/// check says so and offers the way back instead.
class _ArchivedBanner extends ConsumerWidget {
  const _ArchivedBanner({required this.group});

  final LibraryCollection group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2, size: 21, color: palette.inkMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archived',
                  style: TextStyle(
                    fontSize: 13,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Not checked for updates while archived'
                  '${group.archivedAt != null ? ' · archived ${formatRelative(group.archivedAt)}' : ''}. '
                  'Everything downloaded is still readable.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () =>
                ref.read(collectionRepositoryProvider).restore(group.id),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

/// "Check this collection" plus the state of its last check. Never checked is
/// its own sentence — it is not the same as "no new entries".
///
/// Two things the previous version left to inference. The button said "Check
/// now" beside a sync glyph, which is the vocabulary of refreshing a screen;
/// and nothing said whether it would touch this collection or all of them. The
/// label now names the scope, and the footnote points at the Library screen
/// for the many-collection version of the same operation — one vocabulary, two
/// granularities.
class _UpdateCheckCard extends ConsumerWidget {
  const _UpdateCheckCard({required this.group, required this.checker});

  final LibraryCollection group;
  final UpdateChecker checker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: checker,
      builder: (context, _) {
        final palette = AppPalette.of(context);
        final checking = checker.isRunning && checker.activeItemId == group.id;
        final collection = group.collection;
        // Update checking asks a collection's index page what exists now. A
        // standalone entry has no index and no sequence, so the card is absent
        // rather than showing a check that can never find anything.
        if (collection == null) return const SizedBox.shrink();

        // What the check the user just watched retracted. Session state on the
        // checker, and zero once the app restarts — by then the rows are gone
        // and there is no longer a check they were watching.
        final retracted = checker.staleRemovedFor(collection.id);

        final (icon, iconColor, title, body) = switch (null) {
          _ when checking => (
            Icons.manage_search,
            palette.primary,
            'Checking this collection…',
            checker.state == UpdateCheckState.needsUserInput
                ? 'Waiting for you: select the next-entry control in the '
                      'Browser tab.'
                : (checker.message.isEmpty
                      ? 'Reading the entry list from ${collection.host}. '
                            'Metadata only — nothing is downloaded.'
                      : checker.message),
          ),
          _ when collection.lastCheckError != null => (
            Icons.error_outline,
            palette.danger,
            'Last check needs attention',
            '${collection.lastCheckError}'
                '${collection.lastCheckSuccessAt != null ? ' · last success ${formatRelative(collection.lastCheckSuccessAt)}' : ''}',
          ),
          _ when collection.lastCheckSuccessAt == null => (
            Icons.history_toggle_off,
            palette.inkMuted,
            'Never checked for updates',
            'This is not the same as “no new entries”. Nothing has asked '
                'the source yet.',
          ),
          _ when group.knownRemoteCount > 0 => (
            Icons.cloud,
            palette.primary,
            '${group.labels.count(group.knownRemoteCount)} found at the source',
            'Checked ${formatRelative(collection.lastCheckSuccessAt)} · metadata '
                'only, nothing downloaded yet.',
          ),
          _ => (
            Icons.update,
            palette.inkMuted,
            'Nothing new found',
            'Checked ${formatRelative(collection.lastCheckSuccessAt)}'
                '${collection.lastCheckResult != null ? ' · ${collection.lastCheckResult}' : ''}.',
          ),
        };

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 21, color: iconColor),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontVariations: wght(600),
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: palette.inkMuted,
                          ),
                        ),
                        // Stated as its own line, never folded into the count
                        // above it: what the source has gained and what it has
                        // dropped are two different answers, and only one of
                        // them is something to go and save.
                        if (retracted > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            key: const ValueKey('staleRemovedLine'),
                            '${group.labels.count(retracted)} '
                            '${retracted == 1 ? 'is' : 'are'} no longer at the '
                            'source, so ${retracted == 1 ? 'it has' : 'they have'} '
                            'been taken off this list. '
                            '${retracted == 1 ? 'It was' : 'They were'} never '
                            'downloaded — nothing was deleted from this device.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: palette.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Full width and on its own row: "Check this collection" does
              // not fit beside the status text at 320pt, and the label is what
              // carries the meaning here — the glyph only supports it.
              SizedBox(
                width: double.infinity,
                child: checking
                    ? OutlinedButton(
                        // Through the queue, not straight at the checker: a
                        // queued check that is stopped must leave a `cancelled`
                        // row, not a completed one whose summary says
                        // "cancelled". Same stop the Browser panel offers.
                        onPressed: () =>
                            ref.read(taskQueueProvider).stopRunningCheck(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Stop this check'),
                      )
                    : FilledButton.icon(
                        key: const ValueKey('checkThisCollectionButton'),
                        // Always tappable: the queue serializes on the shared
                        // WebView, so "busy" means "queued", not "refused".
                        onPressed: () async {
                          final id = await ref
                              .read(taskQueueProvider)
                              .enqueueCollectionCheck(collection.id);
                          if (id != null || !context.mounted) return;
                          // Refused by the restricted-site capture policy: a
                          // check discovers entries in order to save them.
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                              content: Text(kCaptureRestrictedMessage),
                            ),
                          );
                        },
                        icon: const Icon(Icons.manage_search, size: 19),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Check this collection'),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                'Checks this collection only — nothing is downloaded. To check '
                'every collection at once, use Library updates on the Library '
                'screen.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: palette.inkFaint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Entries the source has and this device does not. Dashed, deliberately
/// unreadable-looking, and never tappable into the reader — tapping one
/// offers its source page or a save instead.
class _RemoteEntries extends ConsumerWidget {
  const _RemoteEntries({required this.entries, required this.onSave});

  final List<Entry> entries;
  final VoidCallback onSave;

  /// Entries a save has already been tried on and failed. Still listed, still
  /// individually retryable — but left out of the batch below, because a
  /// button that re-queues the same failing address every time it is pressed
  /// is not a way forward.
  static bool _lastAttemptFailed(Entry entry) => entry.saveError != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final untried = entries.where((e) => !_lastAttemptFailed(e)).toList();
    final labels = labelsFromNames(
      contentKind: entries.first.contentKind,
      confidence: entries.first.contentKindConfidence,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('NEW ON SOURCE — NOT DOWNLOADED'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.borderInset),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final entry in entries)
                InkWell(
                  key: ValueKey('remoteRow-${entry.id}'),
                  onTap: () => showUnavailableEntrySheet(context, ref, entry),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: palette.hairline),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _lastAttemptFailed(entry)
                              ? Icons.cloud_off
                              : Icons.cloud,
                          size: 20,
                          color: _lastAttemptFailed(entry)
                              ? palette.warn
                              : palette.inkFaint,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            entryDisplayLabel(
                              labels: labelsFromNames(
                                contentKind: entry.contentKind,
                                confidence: entry.contentKindConfidence,
                              ),
                              number: entry.entryNumber,
                              sourceMarker: entry.sourceMarker,
                              title: entry.title,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(size: 13, color: palette.ink),
                          ),
                        ),
                        Text(
                          _lastAttemptFailed(entry)
                              ? 'last try failed'
                              : 'found ${formatRelative(entry.discoveredAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: _lastAttemptFailed(entry)
                                ? palette.warn
                                : palette.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (untried.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: Text(
                    'Every one of these has been tried and did not finish. '
                    'Open one to try it again on its own, or to forget it.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: palette.inkMuted,
                    ),
                  ),
                )
              else
                Material(
                  color: palette.primaryContainer,
                  child: InkWell(
                    key: const ValueKey('saveNewEntries'),
                    onTap: onSave,
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.download,
                            size: 19,
                            color: palette.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Save ${labels.count(untried.length)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontVariations: wght(600),
                              fontWeight: FontWeight.w600,
                              color: palette.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (untried.length < entries.length && untried.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              '${entries.length - untried.length} left out — the last attempt '
              'did not finish. Open one to try it again on its own.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: palette.inkMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    this.selecting = false,
    this.selected = false,
    this.lockReason,
    this.onToggle,
  });

  final Entry entry;
  final bool selecting;
  final bool selected;

  /// Why this entry cannot be selected (open in the reader, mid-save).
  final String? lockReason;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final status = saveStatusFromName(entry.saveStatus);
    final offline =
        entry.contentPath != null &&
        (status == SaveStatus.complete || status == SaveStatus.partial);
    final look = saveLook(entry, palette);
    // Number-first: "Entry 487", not "487. Bölüm Oku". The raw label is
    // kept on the row and shown in the details sheet.
    final displayLabel = entryDisplayLabel(
      labels: labelsFromNames(
        contentKind: entry.contentKind,
        confidence: entry.contentKindConfidence,
      ),
      number: entry.entryNumber,
      sourceMarker: entry.sourceMarker,
      title: entry.title,
    );
    // Selectable = not locked. Offline entries can be removed; entries
    // without files can be queued for re-download — both are selection work,
    // so both are pickable, and the bar decides what applies (D48). A locked
    // entry stays visible but dimmed, so "why can't I pick that one"
    // answers itself.
    final selectable = selecting && lockReason == null;

    return Opacity(
      opacity: selecting && !selectable ? 0.45 : 1,
      child: Container(
        color: selected ? palette.surfaceSelected : Colors.transparent,
        child: InkWell(
          key: ValueKey('entryRow-${entry.id}'),
          // Offline → the reader, exactly as before. Not offline → the two
          // things that can still be done with it, rather than a dead row.
          onTap: selecting
              ? (selectable ? onToggle : null)
              : offline
              ? () => context.push('/reader/${entry.id}')
              : () => showUnavailableEntrySheet(context, ref, entry),
          // The source page stays reachable for an entry that IS offline,
          // without competing with reading it.
          onLongPress: selecting
              ? null
              : () => showEntryDetailsSheet(context, ref, entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
            child: Row(
              children: [
                // Leading = save state (download vocabulary), trailing = read
                // state (checkmark vocabulary). Two facts, two glyph families —
                // never mixed. In selection mode the leading slot becomes the
                // checkbox (or a lock).
                SizedBox(
                  width: 24,
                  child: selecting
                      ? Icon(
                          lockReason != null
                              ? Icons.lock
                              : (selected
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank),
                          size: 22,
                          color: selected
                              ? palette.primary
                              : (selectable
                                    ? palette.inkMuted
                                    : palette.inkDisabled),
                        )
                      : SaveGlyph(look),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                          size: 13.5,
                          weight: FontWeight.w500,
                          color: look.dimTitle ? palette.inkFaint : palette.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            look.label,
                            style: TextStyle(fontSize: 11.5, color: look.color),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: palette.inkDisabled,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              selecting && lockReason != null
                                  ? '$lockReason — kept'
                                  : _meta(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: monoStyle(
                                size: 11.5,
                                color: palette.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (offline && !selecting) ReadGlyph(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _meta(Entry entry) {
    // A user-removed entry has no content and no size to report; what
    // matters is that it can come back.
    if (entry.contentPath == null && entry.offlineRemovedAt != null) {
      return 'removed ${formatRelative(entry.offlineRemovedAt)} · '
          'save again to read';
    }
    final parts = <String>[
      _contents(entry),
      if (entry.byteSize > 0) formatBytes(entry.byteSize),
      if (entry.savedAt != null) formatRelative(entry.savedAt),
    ];
    return parts.join(' · ');
  }

  /// What this entry holds, in the vocabulary of its **stored artifact**.
  ///
  /// A document's asset counts are its inline images, not its pages, so
  /// reporting "0/0 images" for a text entry would be technically true and
  /// completely useless.
  String _contents(Entry entry) {
    final stored = entry.storedAssetCount;
    final detected = entry.detectedAssetCount;
    return switch (ArtifactFormat.fromName(entry.artifactFormat)) {
      ArtifactFormat.imageSequence => '$stored/$detected images',
      ArtifactFormat.structuredDocument =>
        detected == 0 ? 'text' : 'text · $stored/$detected images',
      ArtifactFormat.unknown => 'saved in an unsupported format',
    };
  }
}

/// Reading order: parsed entry number, then save sequence, then time.
/// Two states, so it is a toggle rather than a panel: tapping flips the list
/// and persists the choice.
class _EntrySortToggle extends ConsumerWidget {
  const _EntrySortToggle({required this.sort});

  final EntrySort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final next = sort == EntrySort.newestFirst
        ? EntrySort.oldestFirst
        : EntrySort.newestFirst;
    return Semantics(
      button: true,
      label: 'Sorted ${sort.label} first. Tap for ${next.label} first.',
      excludeSemantics: true,
      child: Material(
        color: palette.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('entrySortToggle'),
          onTap: () => setEntrySort(ref, next),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sort == EntrySort.newestFirst
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 14,
                  color: palette.inkStrong,
                ),
                const SizedBox(width: 5),
                Text(
                  sort.label,
                  style: TextStyle(fontSize: 12, color: palette.inkStrong),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which way the entry list runs.
enum EntrySort {
  /// Newest first. The default: a reader who is up to date cares about the
  /// end of the list, and a 400-entry collection should not open at entry 1.
  newestFirst,

  /// Oldest first — reading order, for someone starting a collection.
  oldestFirst;

  String get label => this == EntrySort.newestFirst ? 'Newest' : 'Oldest';
}

const String kEntrySortKey = 'collection.entrySort';

EntrySort entrySortFromName(String? name) => name == EntrySort.oldestFirst.name
    ? EntrySort.oldestFirst
    : EntrySort.newestFirst;

/// The persisted entry-list order. One setting for every collection: it is a
/// reading habit, not a per-collection fact.
final entrySortProvider = StreamProvider<EntrySort>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(kEntrySortKey)
      .map(entrySortFromName),
);

Future<void> setEntrySort(WidgetRef ref, EntrySort sort) =>
    ref.read(databaseProvider).setSetting(kEntrySortKey, sort.name);

/// Reading order, then flipped if asked.
///
/// The comparison is always the same one — parsed entry number first
/// (decimal-safe, so `385 < 385.5 < 386`), then save sequence, then
/// save time for entries that have no number at all. Descending reverses
/// that single ordering rather than being a second, subtly different one, so
/// a non-numeric `Extra` keeps the same neighbours either way.
List<Entry> sortEntries(List<Entry> entries, EntrySort sort) {
  final ordered = sortEntriesForReading(entries);
  return sort == EntrySort.newestFirst ? ordered.reversed.toList() : ordered;
}

List<Entry> sortEntriesForReading(List<Entry> entries) {
  final sorted = [...entries];
  sorted.sort(
    (a, b) => compareEntriesForReading(
      (number: a.entryNumber, entryOrder: a.entryOrder, savedAt: a.savedAt),
      (number: b.entryNumber, entryOrder: b.entryOrder, savedAt: b.savedAt),
    ),
  );
  return sorted;
}
