/// What a V1 entry row says about its source and its local readability.
///
/// Extracted verbatim from the retired `entry_actions.dart` for the callers
/// that outlive it — "open in Browser" and its tests. Retires with the V1
/// database cutover.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity.dart';
import '../storage/database.dart';

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
