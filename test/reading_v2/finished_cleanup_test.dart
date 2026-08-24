/// Where a Collection's finished-Entry rule is kept, and what null means.
///
/// The behaviour that matters is in `forward_transition_test.dart`, which asks
/// through the orchestration. This is the storage itself: the key it lives
/// under, that it survives the app being closed, and that it is device-local
/// by construction — the schema is frozen at version 1 (CLAUDE.md, "The
/// database has no history") and this deliberately adds no column to it.
///
/// V1 kept the answer on the Collection row, which made a decision about
/// *these* bytes into synced library state: a phone that chose to remove was
/// deciding for a tablet with room to keep. The move to `LocalSettingsStore` is
/// the one intentional semantic change in the restoration, and the key naming
/// is what makes it one row per Collection rather than one per library.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/reading_v2/finished_cleanup.dart';

void main() {
  late LibraryDatabase db;
  late FinishedCleanupPreferenceStore preferences;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    preferences = FinishedCleanupPreferenceStore(LocalSettingsStore(db));
  });
  tearDown(() => db.close());

  test('the key is one row per collection, and it is pinned', () {
    // Spelled out rather than derived: a key that changes silently is a
    // preference that silently vanishes, and this one vanishing means a device
    // quietly stops freeing what the user told it to free.
    expect(finishedCleanupKeyFor('abc'), 'finished_cleanup.abc');
    expect(finishedCleanupKeyFor('def'), 'finished_cleanup.def');
  });

  test('unset is the starting state, and it is a question', () async {
    expect(await preferences.of('abc'), isNull);
  });

  test('an entry with no collection has no rule to inherit', () async {
    await preferences.remember('abc', FinishedCleanupRule.remove);
    // A standalone Entry is a first-class library item, not a collection of
    // one — there is nothing above it to hold a rule.
    expect(await preferences.of(null), isNull);
    expect(await preferences.of(''), isNull);
  });

  test('remembering one collection leaves every other one alone', () async {
    await preferences.remember('one', FinishedCleanupRule.remove);
    await preferences.remember('two', FinishedCleanupRule.keep);

    expect(await preferences.of('one'), FinishedCleanupRule.remove);
    expect(await preferences.of('two'), FinishedCleanupRule.keep);
    expect(await preferences.of('three'), isNull);

    await preferences.forget('one');
    expect(await preferences.of('one'), isNull);
    expect(await preferences.of('two'), FinishedCleanupRule.keep);
  });

  test('a value this build cannot read means ask, never remove', () async {
    await LocalSettingsStore(db).set(finishedCleanupKeyFor('abc'), 'purge');

    expect(
      await preferences.of('abc'),
      isNull,
      reason:
          'an unreadable preference must not resolve to the answer that '
          'deletes something',
    );
  });

  test('it survives the database being closed and opened again', () async {
    final dir = Directory.systemTemp.createTempSync('scrollary_cleanup_pref');
    final file = File('${dir.path}/library.sqlite');
    try {
      final first = LibraryDatabase.forTesting(NativeDatabase(file));
      await FinishedCleanupPreferenceStore(
        LocalSettingsStore(first),
      ).remember('abc', FinishedCleanupRule.remove);
      await first.close();

      final second = LibraryDatabase.forTesting(NativeDatabase(file));
      try {
        expect(
          await FinishedCleanupPreferenceStore(
            LocalSettingsStore(second),
          ).of('abc'),
          FinishedCleanupRule.remove,
        );
      } finally {
        await second.close();
      }
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
