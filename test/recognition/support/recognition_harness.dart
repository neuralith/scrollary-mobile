/// Shared furniture for the recognition suites (F1, F2, F3, F6).
///
/// Wraps the repository harness with the four recognition collaborators and a
/// seed built from the *derived* Source key, so the tests exercise the same
/// derivation the app uses rather than a literal that happens to look right.
///
/// Hosts are the reserved `.example` names the multi-source fixture scenarios
/// use (`tool/fixture/multi_source_fixtures.dart`): one work, published on
/// several simulated sites, with one of them numbering half a step below the
/// others.
library;

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/recognition/adopt.dart';
import 'package:web_reader/recognition/discovery.dart';
import 'package:web_reader/recognition/history.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/save/save_scope.dart';

import '../../data/support/repo_harness.dart';

/// The path every simulated site publishes the work under.
const String kWorkPath = '/works/quiet-harbour';

/// The two sites of the clean-merge scenario, the one that numbers half a step
/// low, and the date-ordered one.
const String kHostA = 'alpha.example';
const String kHostB = 'beta.example';
const String kHostShifted = 'shifted.example';
const String kHostJournal = 'journal.example';

/// A part address on one site. The digits in it are the *address's* — nothing
/// here treats them as a number the source printed.
String partUrl(String host, Object part) =>
    'https://$host$kWorkPath/part-$part';

/// A post address with no printed number anywhere.
String postUrl(String host, String slug) => 'https://$host$kWorkPath/$slug';

class RecognitionHarness {
  RecognitionHarness({QueryExecutor? executor})
    : repos = RepoHarness(executor: executor) {
    recogniser = Recogniser(
      index: repos.recognition,
      collections: repos.collections,
      reading: repos.reading,
    );
    discovery = SourceDiscovery(
      entries: repos.entries,
      collections: repos.collections,
      index: repos.recognition,
    );
    history = HistoryStore(repos.db, now: repos.tick);
    promotion = LibraryPromotion(
      folders: repos.folders,
      collections: repos.collections,
      entries: repos.entries,
    );
  }

  final RepoHarness repos;
  late final Recogniser recogniser;

  /// The user-assisted half of recognition, over the same repositories.
  late final LibraryAdoption adoption = LibraryAdoption(
    folders: repos.folders,
    collections: repos.collections,
    entries: repos.entries,
    index: repos.recognition,
    db: repos.db,
    now: repos.tick,
  );

  /// A scope plus a starting Entry, against the library as it stands.
  late final SaveScopePlanner planner = LibrarySaveScopePlanner(
    db: repos.db,
    entries: repos.entries,
  );

  late final SourceDiscovery discovery;
  late final HistoryStore history;
  late final LibraryPromotion promotion;

  Future<FolderRow> root() => repos.folders.ensureRoot();

  /// A Collection in the root Folder.
  Future<CollectionRow> collection({
    String name = 'Quiet Harbour',
    OrderingBasis basis = OrderingBasis.explicitNumericIndex,
  }) async {
    final folder = await root();
    final (row, violation) = await repos.collections.create(
      name: name,
      folderId: folder.id,
      orderingBasis: basis,
    );
    if (violation != null) throw StateError('$violation');
    return row!;
  }

  /// A Source of [collection] on [host], keyed by the derivation under test.
  Future<SourceRow> source({
    required CollectionRow collection,
    required String host,
    String language = 'en',
  }) async {
    final keys = RecognitionKeys.of(partUrl(host, 1));
    final (row, violation) = await repos.collections.addSource(
      collectionId: collection.id,
      host: keys.host,
      pathKey: keys.pathKey!,
      language: language,
    );
    if (violation != null) throw StateError('$violation');
    return row!;
  }

  /// One placed Entry with one Location on [source].
  Future<(EntryRow, LocationRow)> placedEntry({
    required CollectionRow collection,
    required SourceRow source,
    required String host,
    required double number,
  }) async {
    final (entry, entryViolation) = await repos.entries.createInCollection(
      collectionId: collection.id,
      ordinal: number,
      title: 'Part ${_plain(number)}',
    );
    if (entryViolation != null) throw StateError('$entryViolation');
    final url = partUrl(host, _plain(number));
    final (location, locationViolation) = await repos.entries.addLocation(
      entryId: entry!.id,
      url: url,
      urlKey: RecognitionKeys.of(url).urlKey,
      sourceId: source.id,
      sourceLabel: 'Part ${_plain(number)}',
      sourceNumber: number,
    );
    if (locationViolation != null) throw StateError('$locationViolation');
    return (entry, location!);
  }

  /// A window over consecutive numbered parts of one site, as the site prints
  /// them: label `Part <n + offset>` at address `/part-<n>`.
  ObservedEntryWindow window({
    required SourceRow source,
    required String host,
    required Iterable<int> parts,
    double printedOffset = 0,
    bool newestFirst = false,
  }) {
    final (built, concerns) = ObservedEntryWindow.read(
      sourceId: source.id,
      listings: [
        for (final n in parts)
          ObservedEntryListing.read(
            url: partUrl(host, n),
            label: 'Part ${_plain(n + printedOffset)}',
          ),
      ],
      listRecognised: true,
      orderingConfident: true,
      newestFirst: newestFirst,
    );
    if (built == null) {
      throw StateError('no window; concerns: $concerns');
    }
    return built;
  }

  Future<void> close() => repos.close();

  static String _plain(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';
}
