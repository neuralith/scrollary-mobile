import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/device_capacity_provider.dart';
import '../core/device_storage.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'cleanup_dialogs.dart';
import 'library_screen.dart' show LibraryCollection, formatBytes;
import '../library/entry_labels.dart';

const int _bytesPerMb = 1024 * 1024;
const int _bytesPerGb = 1024 * _bytesPerMb;

/// A figure this app is responsible for: the library total, one collection,
/// the staging tree.
///
/// MB until the MB figure would read 1000 — including a value that only
/// *rounds* there, so nothing ever prints `1000.0 MB` — and GB above it.
/// Below that it is [formatBytes] unchanged, because one entry is measured in
/// megabytes and always was.
String formatStorageBytes(int bytes) {
  if (bytes / _bytesPerMb < 999.95) return formatBytes(bytes);
  return _formatGb(bytes, decimals: 1);
}

/// A device reading: space available, and the size of the disk it is
/// available on.
///
/// Whole gigabytes at device scale — the tenth in `173.4 GB` is noise on a
/// disk being written to, and `177542.7 MB` was not a number anyone could
/// read — with one decimal kept below 10 GB, where 1 GB and 1.4 GB are
/// different answers to "will this save finish". Under a gigabyte it falls
/// back to [formatBytes]: `0 GB` free is a different claim from `300 MB`
/// free, and that is exactly the reading that matters most.
String formatDeviceBytes(int bytes) {
  if (bytes < _bytesPerGb) return formatBytes(bytes);
  return _formatGb(bytes, decimals: bytes < 10 * _bytesPerGb ? 1 : 0);
}

/// Gigabytes from the authoritative byte count — never from an already
/// rounded MB figure — and never with a trailing zero: `2 GB`, not `2.0 GB`.
String _formatGb(int bytes, {required int decimals}) {
  final text = (bytes / _bytesPerGb).toStringAsFixed(decimals);
  final trimmed = text.endsWith('.0')
      ? text.substring(0, text.length - 2)
      : text;
  return '$trimmed GB';
}

/// What Storage shows, derived once per library emission rather than per
/// widget rebuild: `byteSize` already lives on every entry row, so the
/// whole screen is arithmetic over data the library stream carries — no file
/// tree is walked here.
class StorageSummary {
  const StorageSummary({
    required this.totalBytes,
    required this.offlineEntries,
    required this.offlineCollection,
    required this.finishedOfflineEntries,
    required this.finishedOfflineBytes,
    required this.collection,
  });

  final int totalBytes;
  final int offlineEntries;
  final int offlineCollection;
  final int finishedOfflineEntries;
  final int finishedOfflineBytes;

  /// Collection holding offline bytes, largest first.
  final List<CollectionStorage> collection;
}

class CollectionStorage {
  const CollectionStorage({
    required this.group,
    required this.bytes,
    required this.offlineEntries,
    required this.partialEntries,
  });

  final LibraryCollection group;
  final int bytes;
  final int offlineEntries;
  final int partialEntries;
}

/// Storage totals, derived from the same library stream everything else uses
/// so the numbers can never disagree with the shelf.
final storageSummaryProvider = Provider<AsyncValue<StorageSummary>>(
  (ref) => ref.watch(allLibraryCollectionsProvider).whenData((groups) {
    final collection = <CollectionStorage>[];
    var total = 0;
    var entries = 0;
    var finished = 0;
    var finishedBytes = 0;

    for (final group in groups) {
      var bytes = 0;
      var offline = 0;
      var partial = 0;
      for (final c in group.entries) {
        if (c.contentPath == null) continue;
        bytes += c.byteSize;
        offline++;
        if (c.saveStatus == 'partial') partial++;
        if (c.readStatus == 'completed') {
          finished++;
          finishedBytes += c.byteSize;
        }
      }
      if (offline == 0) continue;
      total += bytes;
      entries += offline;
      collection.add(
        CollectionStorage(
          group: group,
          bytes: bytes,
          offlineEntries: offline,
          partialEntries: partial,
        ),
      );
    }
    collection.sort((a, b) => b.bytes.compareTo(a.bytes));
    return StorageSummary(
      totalBytes: total,
      offlineEntries: entries,
      offlineCollection: collection.length,
      finishedOfflineEntries: finished,
      finishedOfflineBytes: finishedBytes,
      collection: collection,
    );
  }),
);

/// Size of the staging tree, for this screen only.
///
/// This one **does** walk a directory, which is why it is scoped to the
/// Storage screen rather than bundled with the device reading: the Library
/// header must never wait on a recursive listing to draw a percentage.
/// Device capacity comes from [deviceCapacityProvider] instead, so the pill
/// and this screen quote the same number.
final stagingBytesProvider = FutureProvider<int>(
  (ref) => ref.watch(fileStoreProvider).stagingByteSize(),
);

/// Where offline content actually goes, and how to get it back.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  bool _sortBySize = true;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final summary = ref.watch(storageSummaryProvider);
    final capacity = ref.watch(deviceCapacityProvider).value;
    final staging = ref.watch(stagingBytesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          final free = capacity?.freeBytes;
          final temp = staging.value ?? 0;
          final collection = [...s.collection];
          if (!_sortBySize) {
            collection.sort(
              (a, b) => a.group.displayName.toLowerCase().compareTo(
                b.group.displayName.toLowerCase(),
              ),
            );
          }
          final largest = s.collection.isEmpty ? 1 : s.collection.first.bytes;

          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // The device first: it is the number that decides whether a
              // save will finish, and the one the Library pill quotes.
              _DeviceMeter(capacity: capacity),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WEB READER USES',
                      style: monoStyle(color: palette.inkMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatStorageBytes(s.totalBytes),
                      style: serifStyle(size: 34),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${kPlainEntryLabels.count(s.offlineEntries)} across '
                      '${s.offlineCollection} '
                      'collection${s.offlineCollection == 1 ? '' : 's'} · '
                      'reading history not included',
                      style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    _Metric('${s.offlineEntries}', 'entries offline'),
                    _Metric('${s.offlineCollection}', 'collection offline'),
                    // Free space stays as a figure; the *percentage* and its
                    // colour live in the meter above, so this tile does not
                    // carry a second, differently-derived warning.
                    _Metric(
                      free == null ? '—' : formatDeviceBytes(free),
                      'available on device',
                    ),
                    _Metric(formatStorageBytes(temp), 'temporary files'),
                  ],
                ),
              ),
              if (free == null)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    "Available device space can't be read right now. Save "
                    'still works — space is checked as files are written.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              if (temp > 0) _TempFilesCard(bytes: temp),
              SectionLabel(
                'BY COLLECTION',
                trailing: _SortToggle(
                  label: _sortBySize ? 'Largest' : 'Name',
                  onTap: () => setState(() => _sortBySize = !_sortBySize),
                ),
              ),
              const Divider(),
              for (final row in collection) ...[
                _CollectionRow(row: row, largestBytes: largest),
                const Divider(),
              ],
              const SectionLabel('FREE UP SPACE'),
              const Divider(),
              _CleanupRow(
                icon: Icons.auto_delete,
                label: 'Remove finished offline entries',
                sub: s.finishedOfflineEntries == 0
                    ? 'Nothing finished is stored offline right now'
                    : '${s.finishedOfflineEntries} entries read to the end · '
                          'frees ~${formatStorageBytes(s.finishedOfflineBytes)}',
                enabled: s.finishedOfflineEntries > 0,
                onTap: () => _confirmGlobalCleanup(s),
              ),
              _CleanupRow(
                icon: Icons.checklist,
                label: 'Choose entries to remove',
                sub: 'Open a collection and select entries yourself',
                enabled: collection.isNotEmpty,
                onTap: () => context.push(
                  '/collection/${collection.first.group.id}?select=1',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text(
                  'Removing offline files never deletes a collection, read marks '
                  'or reading history. Entries stay listed and can be '
                  'saved again any time.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.55,
                    color: palette.inkFaint,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmGlobalCleanup(StorageSummary s) async {
    final ok = await showRemovalConfirm(
      context: context,
      summary: RemovalSummary(
        title: 'Remove finished offline entries?',
        body:
            "Entries you've read to the end will no longer be stored "
            'offline. They stay in your library with read marks and history, '
            'and you can save any of them again.',
        facts: [
          ('Entries', '${s.finishedOfflineEntries}'),
          ('Space freed', '~${formatStorageBytes(s.finishedOfflineBytes)}'),
        ],
        lockNote:
            'Anything open in the reader or being saved right now is '
            'kept.',
      ),
    );
    if (!ok || !mounted) return;
    await ref.read(taskQueueProvider).enqueueCleanup();
    if (!mounted) return;
    showCleanupToast(
      context,
      text:
          'Removing ${s.finishedOfflineEntries} entries — progress in '
          'Activity',
      icon: Icons.delete_sweep,
    );
  }
}

/// A plain figure. Deliberately never coloured: exactly one thing on this
/// screen carries the warning state, and it is the meter (D51).
class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: monoStyle(size: 15, color: palette.ink)),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// How full the device is: the percentage, a bar, and one line of plain
/// language that changes with the level.
///
/// The percentage is the headline because it is the thing that predicts
/// whether the next save finishes — "12 GB free" means nothing without
/// knowing the size of the disk it is free on.
class _DeviceMeter extends StatelessWidget {
  const _DeviceMeter({required this.capacity});

  final DeviceCapacity? capacity;

  @override
  Widget build(BuildContext context) {
    final level = capacity?.level ?? StorageLevel.unknown;
    final look = storageLook(level, AppPalette.of(context));
    final percent = capacity?.usedPercent;
    final free = capacity?.freeBytes;
    final total = capacity?.totalBytes;

    return Container(
      key: const ValueKey('deviceStorageMeter'),
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 2),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: look.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: look.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.storage, size: 18, color: look.ink),
              const SizedBox(width: 8),
              Text(
                'DEVICE STORAGE',
                style: monoStyle(size: 11, color: look.ink),
              ),
              const Spacer(),
              Text(
                percent == null ? '—' : '$percent%',
                style: serifStyle(size: 30, color: look.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // No bar at all when the platform will not report capacity: an
          // empty track would read as "0% used", which is a claim.
          if (percent != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: look.track,
                valueColor: AlwaysStoppedAnimation<Color>(look.fill),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Text(
            _line(look, level, percent, free, total),
            style: TextStyle(fontSize: 12.5, height: 1.45, color: look.ink),
          ),
        ],
      ),
    );
  }

  /// Says what the colour means, and what to do about it — never just a
  /// restatement of the number above.
  String _line(
    StorageLook look,
    StorageLevel level,
    int? percent,
    int? free,
    int? total,
  ) {
    if (percent == null) {
      return "This device won't report its capacity, so the figure above is "
          'unknown. Saves still check for space as they write.';
    }
    final space = free == null
        ? ''
        : total == null
        ? '${formatDeviceBytes(free)} free. '
        : '${formatDeviceBytes(free)} free of ${formatDeviceBytes(total)}. ';
    return switch (level) {
      StorageLevel.critical =>
        '$space${look.label} — a large entry may not finish. Remove '
            'offline files below, or free space elsewhere on the device.',
      StorageLevel.warning =>
        '$space${look.label} — worth removing entries you have finished '
            'before starting a long save.',
      _ => '${space}Plenty of room for more entries.',
    };
  }
}

class _TempFilesCard extends ConsumerWidget {
  const _TempFilesCard({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: palette.warnContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.warnBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.cleaning_services, size: 20, color: palette.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatStorageBytes(bytes)} of temporary files',
                  style: TextStyle(
                    fontSize: 13,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.onWarnContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Left behind by interrupted saves. Cleaning never touches '
                  'saved entries.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: palette.onWarnContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.warn,
              foregroundColor: palette.isDark
                  ? palette.warnContainer
                  : palette.onPrimary,
            ),
            onPressed: () async {
              final swept = await ref.read(fileStoreProvider).sweepStaging();
              ref.invalidate(stagingBytesProvider);
              unawaited(
                ref.read(deviceCapacityProvider.notifier).refresh(force: true),
              );
              if (!context.mounted) return;
              showCleanupToast(
                context,
                text: swept == 0
                    ? 'Nothing to clean'
                    : 'Temporary files cleaned · '
                          '${formatStorageBytes(bytes)} freed',
                icon: Icons.cleaning_services,
              );
            },
            child: const Text('Clean'),
          ),
        ],
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 16, color: palette.inkStrong),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: palette.inkStrong),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.row, required this.largestBytes});

  final CollectionStorage row;
  final int largestBytes;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = largestBytes == 0
        ? 0.0
        : (row.bytes / largestBytes).clamp(0.0, 1.0);
    return InkWell(
      key: ValueKey('storageRow-${row.group.id}'),
      onTap: () => context.push('/collection/${row.group.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.group.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontVariations: wght(500),
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${row.offlineEntries} entries offline',
                    style: monoStyle(color: palette.inkFaint),
                  ),
                  if (row.partialEntries > 0) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_circle_down,
                          size: 14,
                          color: palette.warn,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${row.partialEntries} partial',
                          style: TextStyle(fontSize: 11.5, color: palette.warn),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatStorageBytes(row.bytes),
                  style: monoStyle(size: 13, color: palette.inkMuted),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor: palette.border,
                      color: palette.primary,
                    ),
                  ),
                ),
              ],
            ),
            Icon(Icons.chevron_right, size: 19, color: palette.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _CleanupRow extends StatelessWidget {
  const _CleanupRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Disabled reads as disabled through the palette's own disabled inks
    // rather than a blanket opacity, which used to take the row's borders and
    // glyphs below the point where they were visible at all on dark.
    final ink = enabled ? palette.ink : palette.inkDisabled;
    final sub2 = enabled ? palette.inkFaint : palette.inkDisabled;
    return ListTile(
      leading: Icon(icon, color: enabled ? palette.inkMuted : sub2),
      title: Text(label, style: TextStyle(fontSize: 14.5, color: ink)),
      subtitle: Text(
        sub,
        style: TextStyle(fontSize: 12, height: 1.4, color: sub2),
      ),
      trailing: Icon(Icons.chevron_right, size: 19, color: sub2),
      onTap: enabled ? onTap : null,
    );
  }
}

/// The Library header's storage entry: a disk glyph and one number.
///
/// Deliberately tiny. It shows **device** usage — not the library's share of
/// the disk, which would be a different and far less useful fact — and it
/// reads that from [deviceCapacityProvider], which is one throttled platform
/// call and nothing else. The previous version watched a provider that also
/// walked the staging tree, so drawing the Library header waited on a
/// recursive directory listing.
///
/// Fixed width, because a variable-width readout ("1.2 GB free" → "834 MB
/// free") nudged the Archive and Settings buttons every time it refreshed.
class StoragePill extends ConsumerWidget {
  const StoragePill({super.key});

  /// Enough for the glyph plus "100%", and never more. Fixed so the number
  /// changing cannot nudge the buttons beside it.
  static const double width = 58;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = ref.watch(deviceCapacityProvider).value;
    final percent = capacity?.usedPercent;
    // The colour is the percentage's run now (D51): one rule, shared with
    // the Storage screen, rather than a second free-bytes threshold here.
    final level = capacity?.level ?? StorageLevel.unknown;
    final look = storageLook(level, AppPalette.of(context));
    final fg = look.ink;

    // Unknown capacity shows the glyph alone. Inventing a percentage from a
    // half-known device is the one thing this must not do.
    final label = percent == null
        ? 'Device storage — usage unavailable'
        : 'Device storage $percent% used · ${look.label}';

    return Semantics(
      button: true,
      label: label,
      // The glyph and the bare "72%" say less than the label does, and a
      // screen reader announcing both says it twice.
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: width,
          // Same height as every other action in the header, so the row has
          // one centre line rather than two.
          height: kHeaderActionSize,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => LeaveBrowserGuard.push(context, '/storage'),
              customBorder: const CircleBorder(),
              // Scale-down rather than clip: the box is fixed, so a wider
              // font (or a text-scale setting) must shrink the number rather
              // than overflow the header.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The same glyph size as its neighbours: at 15pt against
                  // their 22pt it read as a different family of thing.
                  Icon(Icons.storage, size: kHeaderIconSize, color: fg),
                  if (percent != null) ...[
                    const SizedBox(width: 3),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$percent%',
                          maxLines: 1,
                          style: monoStyle(
                            size: 12,
                            color: fg,
                            weight: level.isConcerning
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
