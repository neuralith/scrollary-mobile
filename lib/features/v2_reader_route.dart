import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library_ui/providers.dart';
import '../reading_v2/offline_read.dart';
import 'reader_screen.dart';

/// The V2 reader route: resolve the Entry's OfflineCopy first, then open the
/// real reader with its data provided — it never touches a V1 row on this
/// path, and an Entry with no copy renders the reader's honest
/// "not downloaded" state rather than a spinner that cannot end.
class V2ReaderRoute extends ConsumerWidget {
  const V2ReaderRoute({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(libraryUiServicesProvider);
    return FutureBuilder<_ReaderRouteData>(
      future: _resolve(services),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ReaderScreen(
          entryId: entryId,
          offline: resolved.read,
          collectionId: resolved.collectionId,
          previousEntryId: resolved.previousEntryId,
          nextEntryId: resolved.nextEntryId,
          // Replace rather than push: reading on is moving through one
          // collection, not stacking a screen per entry behind you, so the
          // way back stays the Collection however far you read.
          onOpenEntry: (id) => context.pushReplacement('/reader/$id'),
        );
      },
    );
  }

  /// The package, and where the reader's swipe-back goes.
  ///
  /// The Collection is resolved here rather than inside the reader: it is a
  /// library fact and the reader is handed a package, so the one place that
  /// already holds the library services is the one that answers it.
  Future<_ReaderRouteData> _resolve(LibraryUiServices services) async {
    final read = await openOfflineRead(
      entryId: entryId,
      offlineCopies: services.offline,
      reading: services.reading,
      fileStore: services.fileStore,
    );
    final entry = await services.entries.byId(entryId);
    final collectionId = entry?.collectionId;

    // Neighbours by the Collection's own order, which is what "the next
    // entry" means in V2 — not the next URL, and not the next thing this
    // device happens to hold. An entry with no copy is still a neighbour: the
    // route for it renders the reader's honest not-downloaded state, where
    // downloading and opening at the source are already offered.
    String? previous;
    String? next;
    if (collectionId != null && entry?.ordinal != null) {
      final ordered = await services.entries.entriesOf(collectionId);
      final placed = [
        for (final e in ordered)
          if (e.ordinal != null) e,
      ];
      final index = placed.indexWhere((e) => e.id == entryId);
      if (index > 0) previous = placed[index - 1].id;
      if (index >= 0 && index < placed.length - 1) next = placed[index + 1].id;
    }

    return _ReaderRouteData(
      read: read,
      collectionId: collectionId,
      previousEntryId: previous,
      nextEntryId: next,
    );
  }
}

/// The entries either side of one, in its Collection's order.
class ReaderNeighbours {
  const ReaderNeighbours({this.previousEntryId, this.nextEntryId});

  final String? previousEntryId;
  final String? nextEntryId;
}

/// What "the next entry" means in V2: the next one in the **Collection's own
/// order**, not the next URL and not the next thing this device happens to
/// hold.
///
/// An Entry with no copy is still a neighbour — opening one lands on the
/// reader's honest not-downloaded state, where downloading and opening at the
/// source are already offered. A standalone or unplaced Entry has no
/// neighbours by construction, not by omission.
Future<ReaderNeighbours> readerNeighbours(
  LibraryUiServices services,
  String entryId,
) async {
  final entry = await services.entries.byId(entryId);
  final collectionId = entry?.collectionId;
  if (collectionId == null || entry?.ordinal == null) {
    return const ReaderNeighbours();
  }

  final ordered = await services.entries.entriesOf(collectionId);
  final placed = [
    for (final e in ordered)
      if (e.ordinal != null) e,
  ];
  final index = placed.indexWhere((e) => e.id == entryId);
  if (index < 0) return const ReaderNeighbours();
  return ReaderNeighbours(
    previousEntryId: index > 0 ? placed[index - 1].id : null,
    nextEntryId: index < placed.length - 1 ? placed[index + 1].id : null,
  );
}

class _ReaderRouteData {
  const _ReaderRouteData({
    required this.read,
    required this.collectionId,
    this.previousEntryId,
    this.nextEntryId,
  });

  final OfflineReaderData read;
  final String? collectionId;

  /// The entries either side of this one in the Collection's order, when it
  /// has any. Null at the ends, and for a standalone or unplaced Entry — which
  /// has no neighbours by construction, not by omission.
  final String? previousEntryId;
  final String? nextEntryId;
}
