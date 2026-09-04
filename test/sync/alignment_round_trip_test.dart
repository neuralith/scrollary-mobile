/// The three fields this alignment moved onto the wire, each proved to leave
/// one device and arrive at another.
///
/// A round trip is the only honest test for these. Each of them existed before
/// as local state that *looked* synchronised — a column was written, a screen
/// redrew, and nothing said the other device would never hear about it. So the
/// assertions are all of the form "a second device, given only the feed, holds
/// what the first one decided".
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/entry_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/library/entry_sort.dart';
import 'package:web_reader/library/entry_sort_preference.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/capture_preference.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/transport.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  // Two devices over two databases is the whole point here, so drift's warning
  // about a second LibraryDatabase is describing what these tests are for.
  // They never share a QueryExecutor, which is the race it is warning about.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() async => h = await SyncHarness.start());
  tearDown(() => h.stop());

  /// A second device against the same service: its own database, its own
  /// engine, and nothing shared but the feed.
  Future<
    ({
      LibraryDatabase db,
      SyncEngine engine,
      HttpSyncTransport transport,
      CollectionRepository collections,
      EntryRepository entries,
    })
  >
  secondDevice() async {
    final db = LibraryDatabase.forTesting(NativeDatabase.memory());
    final transport = HttpSyncTransport(
      baseUrl: h.backend.baseUrl,
      libraryName: 'test-library',
    );
    await FolderRepository(db).ensureRoot();
    return (
      db: db,
      engine: SyncEngine(db),
      transport: transport,
      collections: CollectionRepository(db),
      entries: EntryRepository(db),
    );
  }

  /// Root, Collection, Source, Entry and Location on the first device.
  ///
  /// The service creates a library's root folder with the library, and a client
  /// maps its own local root onto it at first contact (V2-D21) — so the root is
  /// seeded here and adopted by a first sync, exactly as it happens in life. A
  /// fixture that skipped it would push a Collection whose folder no device but
  /// this one has ever heard of.
  Future<({String collection, String source, String entry, String location})>
  seedLocally() async {
    h.backend.seed('folder', {
      'id': 'srv-root',
      'parent_id': null,
      'kind': 'root',
      'name': 'Library',
      'sort_key': 0,
    }, updatedAt: DateTime.utc(2026, 8, 21, 9));
    await h.folders.ensureRoot();
    await h.engine.syncOnce(h.transport);
    final root = await h.folders.ensureRoot();
    final (collection, _) = await h.collections.create(
      name: 'Serial Alpha',
      folderId: root.id,
      orderingBasis: OrderingBasis.publicationDate,
    );
    final (source, _) = await h.collections.addSource(
      collectionId: collection!.id,
      host: 'reading.example.com',
      pathKey: '/serial-alpha',
    );
    final (entry, _) = await h.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 1,
      placement: Placement.placed,
    );
    const url = 'https://reading.example.com/serial-alpha/part-1';
    final (location, _) = await h.entries.addLocation(
      entryId: entry!.id,
      sourceId: source!.id,
      url: url,
      urlKey: url,
    );
    return (
      collection: collection.id,
      source: source.id,
      entry: entry.id,
      location: location!.id,
    );
  }

  group('a publication date reaches the other device', () {
    test('pushed, fed back, and stored there', () async {
      final seeded = await seedLocally();
      final published = DateTime.utc(2026, 3, 14);
      await h.entries.recordLocationPublishedAt(seeded.location, published);

      expect((await h.engine.syncOnce(h.transport)).succeeded, isTrue);
      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      expect((await other.engine.syncOnce(other.transport)).succeeded, isTrue);

      final there = await other.entries.locationById(seeded.location);
      expect(
        there!.publishedAt!.isAtSameMomentAs(published),
        isTrue,
        reason:
            'ordering_basis publicationDate already crossed; the dates it '
            'orders by have to cross with it',
      );
    });

    test('and a date read here does not blank one read there', () async {
      // Absent means keep. A device that has never opened the page sends no
      // published_at at all, so its ordinary writes cannot erase the date
      // another device read.
      final seeded = await seedLocally();
      await h.entries.recordLocationPublishedAt(
        seeded.location,
        DateTime.utc(2026, 3, 14),
      );
      await h.engine.syncOnce(h.transport);

      await h.entries.updateLocationEvidence(
        seeded.location,
        sourceLabel: 'Part one',
      );
      await h.engine.syncOnce(h.transport);

      final row = h.backend.kindRows('location')[seeded.location]!;
      expect(row['published_at'], isNotNull);
      expect(row['source_label'], 'Part one');
    });
  });

  group("a Collection's own answers reach the other device", () {
    test('capture mode and entry sort both round trip', () async {
      final seeded = await seedLocally();
      await CapturePreferenceStore(
        h.db,
      ).remember(seeded.collection, CaptureMode.imageSequence);
      await EntrySortPreferenceStore(h.db).remember(
        seeded.collection,
        const EntrySort(
          EntrySortField.publishDate,
          EntrySortDirection.descending,
        ),
      );

      expect((await h.engine.syncOnce(h.transport)).succeeded, isTrue);
      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      expect((await other.engine.syncOnce(other.transport)).succeeded, isTrue);

      expect(
        await CapturePreferenceStore(other.db).of(seeded.collection),
        CaptureMode.imageSequence,
        reason: 'someone who said "always images" said it about the work',
      );
      expect(
        await EntrySortPreferenceStore(other.db).of(seeded.collection),
        const EntrySort(
          EntrySortField.publishDate,
          EntrySortDirection.descending,
        ),
        reason: 'a list arranged by hand stays arranged on the next device',
      );
    });

    test('*Ask each time* travels as the answer it is', () async {
      final seeded = await seedLocally();
      await CapturePreferenceStore(h.db).askEachTime(seeded.collection);
      await h.engine.syncOnce(h.transport);

      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      await other.engine.syncOnce(other.transport);

      final there = CapturePreferenceStore(other.db);
      expect(
        await there.of(seeded.collection),
        isNull,
        reason: 'it proposes nothing...',
      );
      expect(
        await there.isAnswered(seeded.collection),
        isTrue,
        reason: '...and is still an answer, so the next save cannot undo it',
      );
    });

    test('clearing one clears it there too', () async {
      final seeded = await seedLocally();
      final here = EntrySortPreferenceStore(h.db);
      await here.remember(
        seeded.collection,
        const EntrySort(EntrySortField.number),
      );
      await h.engine.syncOnce(h.transport);
      await here.forget(seeded.collection);
      await h.engine.syncOnce(h.transport);

      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      await other.engine.syncOnce(other.transport);

      expect(
        await EntrySortPreferenceStore(other.db).of(seeded.collection),
        isNull,
        reason: 'following the data again is a decision, and it travels',
      );
    });

    test('a token this build cannot read is unset, never a value', () async {
      // Forward compatibility on the pull side, which is where it is cheap: a
      // newer device may write a sort field this build has never heard of, and
      // the honest answer is "nobody has said" rather than some other order.
      final seeded = await seedLocally();
      await h.engine.syncOnce(h.transport);
      h.backend.touch(
        'collection',
        seeded.collection,
        updatedAt: DateTime.utc(2026, 9, 1),
        fields: {'entry_sort': 'somethingNewer:ascending'},
      );

      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      expect((await other.engine.syncOnce(other.transport)).succeeded, isTrue);

      expect(
        await EntrySortPreferenceStore(other.db).of(seeded.collection),
        isNull,
      );
    });
  });

  group('the pull stays tolerant', () {
    test('a field this build does not know is ignored, not fatal', () async {
      // Push is strict and pull is lenient, deliberately: a server that learns
      // a field must not stall every older client. The asymmetry is the reason
      // the rollout rule runs service-first (docs/V2_SYNC.md §7).
      final seeded = await seedLocally();
      await h.engine.syncOnce(h.transport);
      h.backend.touch(
        'collection',
        seeded.collection,
        updatedAt: DateTime.utc(2026, 9, 1),
        fields: {'a_field_from_a_later_build': 'whatever it means'},
      );

      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      final outcome = await other.engine.syncOnce(other.transport);

      expect(outcome.succeeded, isTrue);
      expect(
        (await other.collections.byId(seeded.collection))!.name,
        'Serial Alpha',
      );
    });

    test('an entity kind this build does not know is skipped', () async {
      await seedLocally();
      await h.engine.syncOnce(h.transport);
      h.backend.seed('somethingNewer', {
        'id': 'srv-newer',
        'name': 'from a later build',
      }, updatedAt: DateTime.utc(2026, 9, 1));

      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      final outcome = await other.engine.syncOnce(other.transport);

      expect(outcome.succeeded, isTrue);
      expect(
        await other.db.select(other.db.syncState).getSingleOrNull(),
        isNotNull,
      );
    });
  });

  group('Source identity survives the trip', () {
    test('a host is folded here, there, and on the wire', () async {
      final root = await h.folders.ensureRoot();
      final (collection, _) = await h.collections.create(
        name: 'Serial Alpha',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      final (source, _) = await h.collections.addSource(
        collectionId: collection!.id,
        host: 'Reading.Example.COM',
        pathKey: '/Serial-Alpha',
      );

      expect(source!.host, 'reading.example.com');
      expect(
        source.pathKey,
        '/Serial-Alpha',
        reason: 'RFC 3986 paths are case-sensitive and are never folded',
      );
      expect(
        await h.collections.sourceByIdentity(
          'READING.example.com',
          '/Serial-Alpha',
        ),
        isNotNull,
        reason: 'a lookup folds the host it is given, as the writer did',
      );

      await h.engine.syncOnce(h.transport);
      expect(
        h.backend.mutationBatches
            .expand((batch) => batch)
            .firstWhere((e) => e['entity_type'] == 'source')['fields'],
        containsPair('host', 'reading.example.com'),
      );
    });

    test('a Collection still gathers several Sources', () async {
      final seeded = await seedLocally();
      for (final host in ['mirror.example.org', 'mirror.example.net']) {
        final (extra, violation) = await h.collections.addSource(
          collectionId: seeded.collection,
          host: host,
          pathKey: '/serial-alpha',
        );
        expect(violation, isNull);
        expect(extra, isNotNull);
      }
      expect((await h.collections.sourcesOf(seeded.collection)).length, 3);

      expect((await h.engine.syncOnce(h.transport)).succeeded, isTrue);
      final other = await secondDevice();
      addTearDown(() async {
        other.transport.close();
        await other.db.close();
      });
      expect((await other.engine.syncOnce(other.transport)).succeeded, isTrue);
      expect(
        (await other.collections.sourcesOf(seeded.collection)).length,
        3,
        reason: 'multi-Source Collections must survive the identity change',
      );
    });
  });
}
