import 'dart:convert';
import 'dart:io';

import '../data/schema.dart';
import '../library_ui/placement_models.dart';
import '../library_ui/providers.dart';
import '../save/queue_runner.dart';
import 'check_controller.dart';

/// The V1 settings key naming the development sync service, when one is
/// configured. Empty or absent means "no service": every network-dependent
/// affordance then reports its honest refusal instead of erroring.
const kSyncBaseUrlSettingKey = 'sync.devBaseUrl';

/// The V1 settings key naming this library on the development service
/// (the `X-Scrollary-Library` namespace, V2-D28).
const kSyncLibrarySettingKey = 'sync.devLibrary';

/// Everything the V2 stack adds to the app's composition, built once at
/// startup beside the V1 services and torn down with them.
class V2Services {
  V2Services({
    required this.library,
    required this.ui,
    required this.runner,
    required this.check,
    this.syncBaseUrl,
    this.syncLibrary,
  });

  final LibraryDatabase library;
  final LibraryUiServices ui;
  final QueueRunner runner;
  final CheckController check;

  /// Development-only sync endpoint, from settings. Null = unconfigured.
  final String? syncBaseUrl;
  final String? syncLibrary;

  /// Set by the app root once its router exists; consumed by the
  /// entry-opener/source-opener providers. Mutable because navigation cannot
  /// exist before the widget tree does.
  Future<void> Function(String entryId)? openEntry;
  Future<void> Function(String url)? openSource;

  /// Set by the shell: ensure the Browser surface, then start the runner.
  Future<void> Function()? startQueue;

  Future<void> dispose() async {
    runner.dispose();
    check.dispose();
    await library.close();
  }
}

/// Carries one placement submission to the development service.
///
/// Wire shape from `contracts/openapi.yaml` `/entries/{entry_id}/placement`.
/// Unconfigured (no base URL) is a refusal the dialog shows, never a crash.
PlacementSubmit placementSubmitOver(V2Services v2) {
  final base = v2.syncBaseUrl;
  if (base == null || base.isEmpty) {
    return (request) async => const PlacementOutcome.refused(
      'Placement needs the sync service, which is not configured on this '
      'device.',
    );
  }
  final baseUri = Uri.parse(base);
  return (PlacementRequest request) async {
    final client = HttpClient();
    try {
      final uri = baseUri.replace(
        path: '${baseUri.path}/entries/${request.entryId}/placement',
      );
      final http = await client.postUrl(uri);
      http.headers.contentType = ContentType.json;
      final library = v2.syncLibrary;
      if (library != null && library.isNotEmpty) {
        http.headers.set('X-Scrollary-Library', library);
      }
      http.write(jsonEncode({'ordinal': request.ordinal}));
      final response = await http.close();
      final body = await utf8.decodeStream(response);
      switch (response.statusCode) {
        case 200:
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final entry = decoded['entry'] as Map<String, dynamic>? ?? const {};
          final ordinal = (entry['ordinal'] as num?)?.toDouble();
          return PlacementOutcome.applied(ordinal ?? request.ordinal);
        case 409:
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final error = decoded['error'] as Map<String, dynamic>? ?? const {};
          if (error['code'] == 'placement_conflict') {
            final details =
                error['details'] as Map<String, dynamic>? ?? const {};
            return PlacementOutcome.conflict(
              ordinal:
                  (details['current_ordinal'] as num?)?.toDouble() ??
                  request.ordinal,
              occupyingEntryId: details['current_entry_id'] as String?,
            );
          }
          return PlacementOutcome.refused(
            'This collection\'s ordering doesn\'t support placement here.',
          );
        case 404:
          return const PlacementOutcome.refused(
            'The sync service doesn\'t know this entry yet.',
          );
        default:
          return PlacementOutcome.refused(
            'The sync service refused (${response.statusCode}).',
          );
      }
    } on SocketException {
      return const PlacementOutcome.refused(
        'The sync service can\'t be reached right now.',
      );
    } finally {
      client.close(force: true);
    }
  };
}
