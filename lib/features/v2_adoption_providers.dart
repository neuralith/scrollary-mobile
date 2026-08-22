/// The two collaborators the restored save flow needs, over the one services
/// object the library UX is already composed from.
///
/// Their own file rather than a pair of providers inside the sheet, because
/// both are wanted from more than one surface — the Browser's save sheet
/// establishes Collection context, and the Library's entry actions adopt a
/// standalone Entry into a Collection — and neither of them belongs to a
/// widget.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_ui/providers.dart';
import '../recognition/adopt.dart';
import '../save/save_scope.dart';
import 'v2_save_flow.dart' show RecognitionIndexOf;

/// *This page belongs to that Collection*, or *this page starts a new one*.
final libraryAdoptionProvider = Provider<LibraryAdoption>((ref) {
  final services = ref.watch(libraryUiServicesProvider);
  return LibraryAdoption(
    folders: services.folders,
    collections: services.collections,
    entries: services.entries,
    index: RecognitionIndexOf(services).index,
    db: services.db,
  );
});

/// A scope plus a starting Entry becomes the rows to queue — and nothing else
/// happens until the user presses Start.
final saveScopePlannerProvider = Provider<SaveScopePlanner>((ref) {
  final services = ref.watch(libraryUiServicesProvider);
  return LibrarySaveScopePlanner(db: services.db, entries: services.entries);
});
