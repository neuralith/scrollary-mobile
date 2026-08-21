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
    return FutureBuilder<OfflineReaderData>(
      future: openOfflineRead(
        entryId: entryId,
        offlineCopies: services.offline,
        reading: services.reading,
        fileStore: services.fileStore,
      ),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ReaderScreen(entryId: entryId, offline: data);
      },
    );
  }
}
