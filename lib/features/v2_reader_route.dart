import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        );
      },
    );
  }

  /// The package, and where the reader's swipe-back goes.
  ///
  /// The Collection is resolved here rather than inside the reader: it is a
  /// library fact and the reader is handed a package, so the one place that
  /// already holds the library services is the one that answers it.
  Future<_ReaderRouteData> _resolve(LibraryUiServices services) async =>
      _ReaderRouteData(
        read: await openOfflineRead(
          entryId: entryId,
          offlineCopies: services.offline,
          reading: services.reading,
          fileStore: services.fileStore,
        ),
        collectionId: (await services.entries.byId(entryId))?.collectionId,
      );
}

class _ReaderRouteData {
  const _ReaderRouteData({required this.read, required this.collectionId});

  final OfflineReaderData read;
  final String? collectionId;
}
