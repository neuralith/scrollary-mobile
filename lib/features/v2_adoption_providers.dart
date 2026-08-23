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
import '../providers.dart' show browserProvider;
import '../recognition/adopt.dart';
import '../recognition/walk.dart';
import '../save/page_hint_repository.dart';
import '../save/save_scope.dart';
import 'browser_forward_pages.dart';
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

/// *Download the next N from here* — the second of the two operations a typed
/// count can mean (docs/V2_SAVE_FLOW.md §4).
///
/// Built from the library services and the one Browser, because those are its
/// two halves and neither belongs to a widget: identity is written through the
/// ordinary repositories, and the only thing that touches a WebView is
/// [BrowserForwardPageSource].
final sourceWalkProvider = Provider<SourceWalk>((ref) {
  final services = ref.watch(libraryUiServicesProvider);
  return LibrarySourceWalk(
    entries: services.entries,
    collections: services.collections,
    index: RecognitionIndexOf(services).index,
    pages: BrowserForwardPageSource(
      ref.watch(browserProvider),
      hints: PageHintRepository.forLibrary(services.db),
    ),
  );
});
