// STUB — deleted at merge; import v2_add_flow.dart instead
//
// The domain half of the restored save flow is being written in parallel. Its
// signatures are fixed and are reproduced here verbatim so this branch
// compiles, analyses and tests against the shape it will call. Every body
// throws, exactly as the committed `LibraryAdoption` and `SaveScopePlanner`
// bodies do: nothing on this branch may pretend to write a row.
//
// At merge: delete this file and switch the imports listed in the branch
// report to `v2_add_flow.dart` (and `v2_adoption_providers.dart` for the two
// providers at the bottom).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../recognition/adopt.dart';
import '../save/capture_mode.dart';
import '../save/save_scope.dart';

/// What one *add to the library, then queue what was asked for* did.
class AddToLibraryReport {
  const AddToLibraryReport({
    this.sentence,
    this.collectionId,
    this.entryId,
    this.queued = 0,
    this.shortfall = 0,
  });

  /// What to tell the user, in the domain's own words.
  final String? sentence;
  final String? collectionId;
  final String? entryId;

  /// How many `save_queue` rows were written. They wait for an explicit Start.
  final int queued;

  /// How many of the requested downloads the library could not name an address
  /// for. Reported, never padded.
  final int shortfall;

  bool get succeeded => entryId != null || collectionId != null;
}

/// Establish Collection context for [url], then queue what [limits] asked for.
///
/// `limits: null` writes no queue row at all — the case a collection index
/// takes, where there is nothing to download because the listing is not an
/// Entry.
Future<AddToLibraryReport> v2AddAndDownload(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  String? collectionId,
  String? newCollectionName,
  String? folderId,
  SaveLimits? limits,
  CaptureMode? captureMode,
  bool captureModeIsUserSet = false,
}) {
  throw UnimplementedError('ms-domain');
}

/// *Save this page on its own.* A standalone Entry is a first-class library
/// item; it is chosen, never fallen back to.
Future<AddToLibraryReport> v2SaveStandalone(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
  CaptureMode? captureMode,
  bool captureModeIsUserSet = false,
}) {
  throw UnimplementedError('ms-domain');
}

/// *This loose Entry belongs in that Collection after all.*
Future<AddToLibraryReport> v2AdoptStandalone(
  WidgetRef ref, {
  required String entryId,
  required String collectionId,
}) {
  throw UnimplementedError('ms-domain');
}

// Declared in `v2_adoption_providers.dart` on the domain branch; here so the
// declaration set this branch was written against is complete.

final libraryAdoptionProvider = Provider<LibraryAdoption>(
  (ref) => throw UnimplementedError('ms-domain'),
);

final saveScopePlannerProvider = Provider<SaveScopePlanner>(
  (ref) => throw UnimplementedError('ms-domain'),
);
