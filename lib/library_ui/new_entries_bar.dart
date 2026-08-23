/// What the last check brought in, and the one tap that downloads it.
///
/// **The distinction this file exists to keep.** A newly discovered Entry is
/// *in the Collection*. It is not "something waiting to be downloaded" —
/// known, in the library, downloaded and read are four independent facts, and
/// conflating any two of them is a product bug (PRODUCT.md §2.3). So this bar
/// says how many are new and offers to download them; it never presents them
/// as incomplete, pending, or missing.
///
/// V1's equivalent was a whole section — *NEW ON SOURCE — NOT DOWNLOADED* —
/// listing rows a second time beside the ones already on screen. There is one
/// list in V2 (V2-D29 and `collection_test.dart`: "a row with no copy is an
/// ordinary row"), so this is a bar above it rather than a second copy of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/check_state.dart';
import '../ui/palette.dart';
import 'library_widgets.dart';
import 'providers.dart';

/// Shown only while the last check of this Collection has news.
class NewEntriesBar extends ConsumerStatefulWidget {
  const NewEntriesBar({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<NewEntriesBar> createState() => _NewEntriesBarState();
}

class _NewEntriesBarState extends ConsumerState<NewEntriesBar> {
  late final CheckStateStore _store;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(checkStateProvider);
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _store.of(widget.collectionId);
    if (!state.hasNews) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final count = state.newCount;

    return Container(
      key: const ValueKey('newEntriesBar'),
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        border: Border.all(color: palette.primaryBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1
                  ? '1 new entry in this collection.'
                  : '$count new entries in this collection.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: palette.onPrimaryContainer,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('downloadNewEntries'),
            onPressed: _busy ? null : _downloadNew,
            child: const Text('Download'),
          ),
          IconButton(
            key: const ValueKey('dismissNewEntries'),
            tooltip: 'I have seen these',
            iconSize: 18,
            icon: const Icon(Icons.close),
            onPressed: () => _store.clearNews(widget.collectionId),
          ),
        ],
      ),
    );
  }

  /// Queue every new Entry. They wait for Start, like everything else.
  ///
  /// Downloading is an *optional action on* library state, never the reason
  /// the Entries are there — so this leaves the Collection exactly as it was
  /// if the user never taps it.
  Future<void> _downloadNew() async {
    setState(() => _busy = true);
    final ids = _store.of(widget.collectionId).newEntryIds;
    final db = ref.read(libraryDatabaseProvider);
    final queue = ref.read(saveQueueRepoProvider);

    var queued = 0;
    String? refusal;
    for (final entryId in ids) {
      final location = await primaryLocation(db, entryId);
      if (location == null) continue;
      final result = await queue.enqueue(
        entryId: entryId,
        locationId: location.id,
        locationUrl: location.url,
      );
      if (result.refusedReason != null) {
        refusal ??= result.refusedReason;
        continue;
      }
      if (!result.alreadyQueued) queued++;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _store.clearNews(widget.collectionId);
    showLibraryMessage(
      context,
      queued == 0
          ? refusal ?? 'There was nothing new to queue.'
          : '$queued queued. Nothing starts until you start it.'
                '${refusal == null ? '' : ' $refusal'}',
    );
  }
}
