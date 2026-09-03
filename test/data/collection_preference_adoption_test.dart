/// Preferences an older build left in `settings` are moved, not reset.
///
/// The two Collection answers — what it is normally saved as, and what order
/// its Entries are drawn in — used to be key-value rows keyed by a Collection's
/// local id, because the schema was frozen. They are columns now. Nothing has
/// shipped, so this is a development-database concern rather than a user one;
/// it exists anyway because "your collections quietly forgot what you told
/// them" is not an acceptable way to find that out.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_preference_adoption.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/outbox_repository.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/library/entry_sort_preference.dart';
import 'package:web_reader/save/capture_preference.dart';

void main() {
  late LibraryDatabase db;
  late CollectionRepository collections;
  late LocalSettingsStore settings;
  late OutboxRepository outbox;

  setUp(() async {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    collections = CollectionRepository(db);
    settings = LocalSettingsStore(db);
    outbox = OutboxRepository(db);
  });

  tearDown(() => db.close());

  Future<String> aCollection([String name = 'Serial Alpha']) async {
    final root = await FolderRepository(db).ensureRoot();
    final (collection, violation) = await collections.create(
      name: name,
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(violation, isNull);
    return collection!.id;
  }

  test('a legacy answer moves onto the row and is pushed', () async {
    final id = await aCollection();
    await settings.set(legacyCaptureModeKeyFor(id), 'imageSequence');
    await settings.set(legacyEntrySortKeyFor(id), 'publishDate:descending');
    final before = await outbox.pendingCount();

    final moved = await adoptLegacyCollectionPreferences(db);

    expect((moved.captureModes, moved.entrySorts), (1, 1));
    final row = await collections.byId(id);
    expect(row!.captureMode, 'imageSequence');
    expect(row.entrySort, 'publishDate:descending');
    expect(
      await outbox.pendingCount(),
      before + 2,
      reason:
          'an adopted answer is news for the other devices, not just for this '
          'one — a move that wrote no intent would strand it here',
    );
  });

  test('the settings rows are gone, so there is one place to look', () async {
    final id = await aCollection();
    await settings.set(legacyCaptureModeKeyFor(id), 'textOnly');

    await adoptLegacyCollectionPreferences(db);

    expect(await settings.get(legacyCaptureModeKeyFor(id)), isNull);
  });

  test('it is idempotent, and a second run is a no-op', () async {
    final id = await aCollection();
    await settings.set(legacyEntrySortKeyFor(id), 'number:ascending');
    await adoptLegacyCollectionPreferences(db);
    final after = await outbox.pendingCount();

    final again = await adoptLegacyCollectionPreferences(db);

    expect(again.movedAnything, isFalse);
    expect(await outbox.pendingCount(), after);
    expect((await collections.byId(id))!.entrySort, 'number:ascending');
  });

  test('an answer the Collection already has wins', () async {
    // A row that arrived from another device is newer information than a key
    // this build has not looked at since it was written.
    final id = await aCollection();
    await collections.setEntrySort(id, 'addedDate:descending');
    await settings.set(legacyEntrySortKeyFor(id), 'number:ascending');

    final moved = await adoptLegacyCollectionPreferences(db);

    expect(moved.entrySorts, 0);
    expect((await collections.byId(id))!.entrySort, 'addedDate:descending');
    expect(
      await settings.get(legacyEntrySortKeyFor(id)),
      isNull,
      reason: 'the stale copy still goes: two places to look is the bug',
    );
  });

  test('a clean install moves nothing and touches nothing', () async {
    await aCollection();
    final before = await outbox.pendingCount();

    final moved = await adoptLegacyCollectionPreferences(db);

    expect(moved.movedAnything, isFalse);
    expect(await outbox.pendingCount(), before);
  });

  test('one Collection adopting cannot reach another', () async {
    final a = await aCollection('Serial Alpha');
    final b = await aCollection('Serial Beta');
    await settings.set(legacyCaptureModeKeyFor(a), 'textOnly');

    await adoptLegacyCollectionPreferences(db);

    expect((await collections.byId(a))!.captureMode, 'textOnly');
    expect((await collections.byId(b))!.captureMode, '');
  });

  test('and the stores read what was adopted', () async {
    final id = await aCollection();
    await settings.set(legacyCaptureModeKeyFor(id), 'textAndImages');
    await settings.set(legacyEntrySortKeyFor(id), 'publishDate:ascending');

    await adoptLegacyCollectionPreferences(db);

    expect(
      (await CapturePreferenceStore(db).of(id))?.name,
      'textAndImages',
      reason: 'the move is only real if the reader finds it',
    );
    expect(
      (await EntrySortPreferenceStore(db).of(id))?.storedValue,
      'publishDate:ascending',
    );
  });
}
