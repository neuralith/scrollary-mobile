/// Reading on to the next Entry, and what that does to the one left behind.
///
/// **The regression this pins.** V1 asked, once per Collection, what should
/// happen to a finished Entry's downloaded files when the reader moved on, and
/// applied the answer only after the next Entry had genuinely opened.
/// `b1be16d` removed the whole apparatus with the reader's V1 route — the
/// reasoning being that "a reader opened over an OfflineCopy has no neighbour
/// list", which is true of the *screen* and not of the **Collection** — and
/// `60cf4c7` deleted the orphaned dialogs and the stored preference with the
/// V1 database. `3840b48` brought the navigation back and left this behind, so
/// a device that reads a long serialized work now fills up and nothing offers
/// to stop it. `test/finished_transition_test.dart` (1367 lines) went with the
/// implementation; this is its behaviour, ported to V2's model.
///
/// It drives `ForwardTransitionService` — the real orchestration, over real
/// repositories, real packages on a real FileStore — rather than a widget
/// tree: what is under test is the *decision order*, and the two questions are
/// seams the route fills with dialogs.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/reading_v2/finished_cleanup.dart';
import 'package:web_reader/reading_v2/forward_transition.dart';
import 'package:web_reader/reading_v2/offline_read.dart';

import '../helpers/reader_harness.dart';

void main() {
  late ReaderHarness h;
  late FinishedCleanupPreferenceStore preferences;
  late ForwardTransitionService transitions;

  /// Every question the service asked, in order.
  final completionAsked = <CompletionQuestion>[];
  final ruleAsked = <CleanupRuleQuestion>[];

  /// What the seams answer. Null is the dismissal in both cases.
  EntryCompletionChoice? completionAnswer;
  FinishedCleanupRule? ruleAnswer;

  /// Where each seeded Entry's package landed, so a test can ask the disk.
  final packagePath = <String, String>{};

  setUp(() {
    h = ReaderHarness();
    preferences = FinishedCleanupPreferenceStore(LocalSettingsStore(h.db));
    transitions = ForwardTransitionService(
      entries: h.repos.entries,
      collections: h.repos.collections,
      reading: h.repos.reading,
      offlineCopies: h.repos.offline,
      fileStore: h.fileStore,
      preferences: preferences,
    );
    completionAsked.clear();
    ruleAsked.clear();
    completionAnswer = null;
    ruleAnswer = null;
    packagePath.clear();
  });
  tearDown(() => h.close());

  // ─── driving it the way the route does ────────────────────────────────────

  Future<bool> move({
    required String from,
    required String to,
    double fraction = 1,
  }) => transitions.begin(
    fromEntryId: from,
    toEntryId: to,
    fraction: fraction,
    askToComplete: (question) async {
      completionAsked.add(question);
      return completionAnswer;
    },
    askForCleanupRule: (question) async {
      ruleAsked.add(question);
      return ruleAnswer;
    },
  );

  /// Exactly what `V2ReaderRoute` does when the destination's route resolves:
  /// open the copy, and report whether it came to something readable. The
  /// predicate is the real one, not a flag a test made up.
  Future<void> arrive(String entryId) async {
    final read = await h.open(entryId);
    await transitions.arrived(
      entryId: entryId,
      readable: read.read is! OfflineReadUnavailable,
    );
  }

  /// One forward move, start to finish.
  Future<void> readOn({
    required String from,
    required String to,
    double fraction = 1,
  }) async {
    if (await move(from: from, to: to, fraction: fraction)) await arrive(to);
  }

  // ─── seeding ──────────────────────────────────────────────────────────────

  /// [count] Entries in reading order, each downloaded on this device.
  Future<List<String>> serial(int count) async {
    final ids = <String>[];
    for (var i = 1; i <= count; i++) {
      final id = await h.seedEntry(title: 'Part $i', ordinal: i.toDouble());
      packagePath[id] = await h.seedImages(
        entryId: id,
        pages: 2,
        title: 'Part $i',
      );
      ids.add(id);
    }
    return ids;
  }

  Future<String> collectionOfSerial() => h.collectionId();

  bool downloaded(String entryId) =>
      h.fileStore.entryExists(packagePath[entryId]!);

  Future<bool> hasCopyRow(String entryId) async =>
      await h.repos.offline.activeCopyOf(entryId) != null;

  Future<ReadStatus> statusOf(String entryId) async =>
      (await h.repos.reading.stateOf(entryId)).status;

  /// Read [entryId] to the end, the way the reader records it.
  Future<void> finish(String entryId) async {
    final (_, violation) = await h.repos.reading.markRead(entryId);
    expect(
      violation,
      isNull,
      reason: 'seeding a finished entry is not refused',
    );
  }

  // ══ the collection's rule ═══════════════════════════════════════════════

  group('the collection is asked once', () {
    test('a collection with no rule is asked on the first move that '
        'would apply one', () async {
      final ids = await serial(2);
      await finish(ids[0]);

      await readOn(from: ids[0], to: ids[1]);

      expect(ruleAsked, hasLength(1));
      expect(ruleAsked.single.collectionId, await collectionOfSerial());
      expect(ruleAsked.single.collectionName, 'Serial Alpha');
    });

    test('answering Remove stores it on this collection and frees the '
        'entry now', () async {
      final ids = await serial(2);
      await finish(ids[0]);
      ruleAnswer = FinishedCleanupRule.remove;

      await readOn(from: ids[0], to: ids[1]);

      expect(
        await preferences.of(await collectionOfSerial()),
        FinishedCleanupRule.remove,
      );
      expect(downloaded(ids[0]), isFalse);
      expect(await hasCopyRow(ids[0]), isFalse);
      expect(
        downloaded(ids[1]),
        isTrue,
        reason: 'the one being read is not it',
      );
    });

    test('answering Keep stores it and frees nothing', () async {
      final ids = await serial(2);
      await finish(ids[0]);
      ruleAnswer = FinishedCleanupRule.keep;

      await readOn(from: ids[0], to: ids[1]);

      expect(
        await preferences.of(await collectionOfSerial()),
        FinishedCleanupRule.keep,
      );
      expect(downloaded(ids[0]), isTrue);
      expect(await hasCopyRow(ids[0]), isTrue);
    });

    test('dismissing without answering stores nothing and keeps the '
        'files', () async {
      final ids = await serial(3);
      await finish(ids[0]);
      // The seam answers null — the barrier tap, the back gesture.
      ruleAnswer = null;

      await readOn(from: ids[0], to: ids[1]);

      expect(await preferences.of(await collectionOfSerial()), isNull);
      expect(downloaded(ids[0]), isTrue);

      // …and the question comes back on the next eligible move.
      await finish(ids[1]);
      await readOn(from: ids[1], to: ids[2]);
      expect(ruleAsked, hasLength(2));
    });

    test('a collection that has answered is never asked again', () async {
      final ids = await serial(3);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      await finish(ids[0]);
      await finish(ids[1]);

      await readOn(from: ids[0], to: ids[1]);
      await readOn(from: ids[1], to: ids[2]);

      expect(ruleAsked, isEmpty);
      expect(downloaded(ids[0]), isFalse);
      expect(downloaded(ids[1]), isFalse);
    });

    test('*Ask again next time* brings the question back', () async {
      final ids = await serial(2);
      final collection = await collectionOfSerial();
      await preferences.remember(collection, FinishedCleanupRule.keep);
      // The Collection menu's third row.
      await preferences.forget(collection);
      await finish(ids[0]);

      await readOn(from: ids[0], to: ids[1]);

      expect(ruleAsked, hasLength(1));
      expect(
        downloaded(ids[0]),
        isTrue,
        reason: 'clearing a rule removes nothing by itself',
      );
    });

    test('another collection keeps its own answer, and is asked for it '
        'separately', () async {
      final ids = await serial(2);
      final serialAlpha = await collectionOfSerial();
      await preferences.remember(serialAlpha, FinishedCleanupRule.remove);

      final root = await h.repos.folders.ensureRoot();
      final (other, violation) = await h.repos.collections.create(
        name: 'Serial Beta',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      expect(violation, isNull);

      expect(await preferences.of(other!.id), isNull);
      expect(await preferences.of(serialAlpha), FinishedCleanupRule.remove);

      // And forgetting one leaves the other alone.
      await preferences.forget(serialAlpha);
      await preferences.remember(other.id, FinishedCleanupRule.keep);
      expect(await preferences.of(serialAlpha), isNull);
      expect(await preferences.of(other.id), FinishedCleanupRule.keep);

      // The entries are still there and still downloaded: a preference is a
      // rule about what happens next, never a command.
      expect(downloaded(ids[0]), isTrue);
      expect(downloaded(ids[1]), isTrue);
    });

    test('an unreadable stored value means ask, never remove', () async {
      final collection = await collectionOfSerial();
      await LocalSettingsStore(
        h.db,
      ).set(finishedCleanupKeyFor(collection), 'incinerate');

      expect(await preferences.of(collection), isNull);
    });
  });

  // ══ finishing ══════════════════════════════════════════════════════════

  group('moving forward is not evidence of finishing', () {
    test('an entry already finished is not asked about', () async {
      final ids = await serial(2);
      await finish(ids[0]);
      ruleAnswer = FinishedCleanupRule.remove;

      await readOn(from: ids[0], to: ids[1]);

      expect(completionAsked, isEmpty);
      expect(downloaded(ids[0]), isFalse);
    });

    test('near the end and unfinished, it asks', () async {
      final ids = await serial(2);
      completionAnswer = EntryCompletionChoice.continueWithout;

      await readOn(from: ids[0], to: ids[1], fraction: 0.94);

      expect(completionAsked, hasLength(1));
      expect(completionAsked.single.entryName, 'Part 1');
      expect(completionAsked.single.percentRead, 94);
    });

    test('below the near threshold it asks nothing and changes '
        'nothing', () async {
      final ids = await serial(2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      await readOn(from: ids[0], to: ids[1], fraction: 0.5);

      expect(completionAsked, isEmpty);
      expect(ruleAsked, isEmpty);
      expect(await statusOf(ids[0]), isNot(ReadStatus.completed));
      expect(downloaded(ids[0]), isTrue);
    });

    test('*Mark finished and continue* finishes it, then applies the '
        'rule', () async {
      final ids = await serial(2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      completionAnswer = EntryCompletionChoice.completeAndContinue;

      await readOn(from: ids[0], to: ids[1], fraction: 0.93);

      expect(await statusOf(ids[0]), ReadStatus.completed);
      expect(downloaded(ids[0]), isFalse);
    });

    test('the question names the consequence before the tap', () async {
      final ids = await serial(3);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      completionAnswer = EntryCompletionChoice.continueWithout;

      await readOn(from: ids[0], to: ids[1], fraction: 0.95);
      expect(completionAsked.single.willRemoveCopy, isTrue);

      // And it says nothing of the sort where there is no rule yet: that
      // question comes next and explains itself.
      completionAsked.clear();
      await preferences.forget(await collectionOfSerial());
      await readOn(from: ids[1], to: ids[2], fraction: 0.95);
      expect(completionAsked.single.willRemoveCopy, isFalse);
    });

    test('*Continue without finishing* leaves completion, position and '
        'files alone', () async {
      final ids = await serial(2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      completionAnswer = EntryCompletionChoice.continueWithout;

      await readOn(from: ids[0], to: ids[1], fraction: 0.95);

      expect(await statusOf(ids[0]), isNot(ReadStatus.completed));
      expect(
        downloaded(ids[0]),
        isTrue,
        reason: 'the rule is about finished entries, and this one is not one',
      );
      expect(ruleAsked, isEmpty);
    });

    test('Cancel changes nothing at all, and the reader stays put', () async {
      final ids = await serial(2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      completionAnswer = EntryCompletionChoice.cancel;

      final mayMove = await move(from: ids[0], to: ids[1], fraction: 0.98);

      expect(mayMove, isFalse);
      expect(transitions.pending, isNull);
      expect(await statusOf(ids[0]), isNot(ReadStatus.completed));
      expect(downloaded(ids[0]), isTrue);
    });

    test('dismissing the completion question is the same as Cancel', () async {
      final ids = await serial(2);
      completionAnswer = null;

      expect(await move(from: ids[0], to: ids[1], fraction: 0.98), isFalse);
      expect(downloaded(ids[0]), isTrue);
    });
  });

  // ══ which moves this is even about ═════════════════════════════════════

  group('forward, inside one collection, and nothing else', () {
    test('moving backward never finishes or frees anything', () async {
      final ids = await serial(2);
      await finish(ids[1]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      await readOn(from: ids[1], to: ids[0]);

      expect(completionAsked, isEmpty);
      expect(ruleAsked, isEmpty);
      expect(downloaded(ids[1]), isTrue);
      expect(transitions.pending, isNull);
    });

    test('order is the collection\'s, not the order rows were '
        'written', () async {
      // Written last, ordered first: a rule that compared ids or write order
      // would call this a forward move.
      final later = await h.seedEntry(title: 'Part 9', ordinal: 9);
      packagePath[later] = await h.seedImages(entryId: later, pages: 2);
      final earlier = await h.seedEntry(title: 'Part 1', ordinal: 1);
      packagePath[earlier] = await h.seedImages(entryId: earlier, pages: 2);

      await finish(later);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      await readOn(from: later, to: earlier);

      expect(downloaded(later), isTrue, reason: 'that was a move backward');
    });

    test('a move into another collection applies no rule', () async {
      final ids = await serial(1);
      await finish(ids[0]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      final root = await h.repos.folders.ensureRoot();
      final (other, cv) = await h.repos.collections.create(
        name: 'Serial Beta',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      expect(cv, isNull);
      final (elsewhere, ev) = await h.repos.entries.createInCollection(
        collectionId: other!.id,
        ordinal: 1,
        title: 'Something else',
      );
      expect(ev, isNull);

      await readOn(from: ids[0], to: elsewhere!.id);

      expect(downloaded(ids[0]), isTrue);
      expect(ruleAsked, isEmpty);
    });

    test('a standalone entry has no reading order to move through', () async {
      final root = await h.repos.folders.ensureRoot();
      final (alone, av) = await h.repos.entries.createStandalone(
        folderId: root.id,
        title: 'On its own',
      );
      expect(av, isNull);
      final ids = await serial(1);

      await readOn(from: alone!.id, to: ids[0], fraction: 1);

      expect(completionAsked, isEmpty);
      expect(ruleAsked, isEmpty);
    });

    test('an entry this device holds nothing for is not asked about', () async {
      // Downloading is optional: an Entry can be read at its Source and moved
      // on from, and there is nothing to free when that happens.
      final undownloaded = await h.seedEntry(title: 'Part 1', ordinal: 1);
      final next = await h.seedEntry(title: 'Part 2', ordinal: 2);
      packagePath[next] = await h.seedImages(entryId: next, pages: 2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      await finish(undownloaded);

      await readOn(from: undownloaded, to: next);

      expect(completionAsked, isEmpty);
      expect(ruleAsked, isEmpty);
      expect(await statusOf(undownloaded), ReadStatus.completed);
    });
  });

  // ══ nothing happens until the destination opens ════════════════════════

  group('the destination has to open first', () {
    test('a destination whose files vanished changes nothing', () async {
      final ids = await serial(2);
      await finish(ids[0]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      expect(await move(from: ids[0], to: ids[1]), isTrue);
      expect(transitions.pending, isNotNull);

      // Between the tap and the read, the destination's package goes.
      await h.deletePackage(packagePath[ids[1]]!);
      await arrive(ids[1]);

      expect(
        downloaded(ids[0]),
        isTrue,
        reason: 'the entry just left is the only readable thing there is',
      );
      expect(await hasCopyRow(ids[0]), isTrue);
    });

    test('a destination this device never downloaded changes '
        'nothing', () async {
      final first = await h.seedEntry(title: 'Part 1', ordinal: 1);
      packagePath[first] = await h.seedImages(entryId: first, pages: 2);
      final second = await h.seedEntry(title: 'Part 2', ordinal: 2);
      await finish(first);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      await readOn(from: first, to: second);

      expect(downloaded(first), isTrue);
    });

    test('an unfinished entry marked finished on the way is not finished '
        'when the destination fails', () async {
      final ids = await serial(2);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.keep,
      );
      completionAnswer = EntryCompletionChoice.completeAndContinue;

      expect(await move(from: ids[0], to: ids[1], fraction: 0.95), isTrue);
      await h.deletePackage(packagePath[ids[1]]!);
      await arrive(ids[1]);

      expect(
        await statusOf(ids[0]),
        isNot(ReadStatus.completed),
        reason: 'the move it was part of never happened',
      );
    });

    test('an arrival somewhere else is not the arrival that was '
        'planned for', () async {
      final ids = await serial(3);
      await finish(ids[0]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      expect(await move(from: ids[0], to: ids[1]), isTrue);
      // The reader ends up somewhere else entirely.
      await arrive(ids[2]);

      expect(downloaded(ids[0]), isTrue);
      expect(
        transitions.pending,
        isNull,
        reason: 'a plan is due once, and belongs to one transition',
      );

      // And it does not fall due later on the entry it named.
      await arrive(ids[1]);
      expect(downloaded(ids[0]), isTrue);
    });

    test('nothing is owed twice', () async {
      final ids = await serial(2);
      await finish(ids[0]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      await readOn(from: ids[0], to: ids[1]);
      expect(downloaded(ids[0]), isFalse);

      // A second arrival — a rebuild, a re-entry — has nothing left to do.
      await arrive(ids[1]);
      expect(downloaded(ids[1]), isTrue);
    });
  });

  // ══ a burst of taps ════════════════════════════════════════════════════

  group('one question at a time', () {
    test('a second tap while a question is open is refused, and asks '
        'nothing', () async {
      final ids = await serial(3);
      await finish(ids[0]);

      // The seam does not answer until the test lets it, which is what a
      // dialog on screen looks like from here. `onScreen` is what makes this
      // deterministic: the second tap happens once the first question is
      // genuinely up, not merely once a microtask has passed.
      final onScreen = Completer<void>();
      final gate = Completer<FinishedCleanupRule?>();
      final first = transitions.begin(
        fromEntryId: ids[0],
        toEntryId: ids[1],
        fraction: 1,
        askForCleanupRule: (question) {
          ruleAsked.add(question);
          onScreen.complete();
          return gate.future;
        },
      );
      await onScreen.future;

      final second = await transitions.begin(
        fromEntryId: ids[0],
        toEntryId: ids[2],
        fraction: 1,
        askForCleanupRule: (question) async {
          ruleAsked.add(question);
          return FinishedCleanupRule.remove;
        },
      );

      expect(
        second,
        isFalse,
        reason:
            'the reader stays put rather than '
            'planning the same move twice',
      );
      expect(ruleAsked, hasLength(1));

      gate.complete(FinishedCleanupRule.remove);
      expect(await first, isTrue);
      await arrive(ids[1]);
      expect(downloaded(ids[0]), isFalse);
    });

    test('a burst of forward taps finishes and frees exactly once', () async {
      final ids = await serial(3);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );
      completionAnswer = EntryCompletionChoice.completeAndContinue;

      final results = await Future.wait([
        move(from: ids[0], to: ids[1], fraction: 0.95),
        move(from: ids[0], to: ids[1], fraction: 0.95),
        move(from: ids[0], to: ids[1], fraction: 0.95),
      ]);

      expect(results.where((moved) => moved).length, 1);
      expect(completionAsked, hasLength(1));
      await arrive(ids[1]);
      expect(downloaded(ids[0]), isFalse);
      expect(await statusOf(ids[0]), ReadStatus.completed);
    });

    test('a move that never happens owes nothing, ever', () async {
      // `begin` said the reader may move; then it did not — the reader was
      // gone by the time the question was answered, so `V2ReaderRoute` calls
      // `abandon`. Without that, the plan would sit there and fall due the
      // next time this Entry was opened from anywhere at all.
      final ids = await serial(2);
      await finish(ids[0]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      expect(await move(from: ids[0], to: ids[1]), isTrue);
      expect(transitions.pending, isNotNull);
      transitions.abandon();

      // Days later, opening that entry from the library.
      await arrive(ids[1]);

      expect(downloaded(ids[0]), isTrue);
      expect(await hasCopyRow(ids[0]), isTrue);
    });

    test('a second move abandons what the first one was owed', () async {
      final ids = await serial(3);
      await finish(ids[0]);
      await finish(ids[1]);
      await preferences.remember(
        await collectionOfSerial(),
        FinishedCleanupRule.remove,
      );

      expect(await move(from: ids[0], to: ids[1]), isTrue);
      // Without ever arriving, the reader moves on again.
      expect(await move(from: ids[1], to: ids[2]), isTrue);
      await arrive(ids[2]);

      expect(
        downloaded(ids[0]),
        isTrue,
        reason: 'that move never completed, so nothing was owed for it',
      );
      expect(downloaded(ids[1]), isFalse);
    });
  });

  // ══ what survives ══════════════════════════════════════════════════════

  test('freeing a copy takes the bytes and nothing else', () async {
    final ids = await serial(2);
    final collection = await collectionOfSerial();
    final source = (await h.repos.collections.sourcesOf(collection)).first;
    final (location, lv) = await h.repos.entries.addLocation(
      entryId: ids[0],
      sourceId: source.id,
      url: 'https://reading.example.com/serial-alpha/part-1',
      urlKey: 'https://reading.example.com/serial-alpha/part-1',
    );
    expect(lv, isNull);

    final before = await h.repos.entries.byId(ids[0]);
    await finish(ids[0]);
    final finishedAt = await h.repos.reading.stateOf(ids[0]);
    await preferences.remember(collection, FinishedCleanupRule.remove);

    await readOn(from: ids[0], to: ids[1]);

    // The one fact that changed.
    expect(downloaded(ids[0]), isFalse);
    expect(await hasCopyRow(ids[0]), isFalse);

    // Everything else, exactly as it was.
    final after = await h.repos.entries.byId(ids[0]);
    expect(after, isNotNull, reason: 'the entry is still in the library');
    expect(after!.collectionId, before!.collectionId);
    expect(after.ordinal, before.ordinal);
    expect(after.title, before.title);
    expect(after.placement, before.placement);

    final locations = await h.repos.entries.locationsOf(ids[0]);
    expect(locations.map((l) => l.id), contains(location!.id));
    expect(locations.single.url, location.url);

    final reading = await h.repos.reading.stateOf(ids[0]);
    expect(reading.status, ReadStatus.completed);
    expect(reading.firstOpenedAt, finishedAt.firstOpenedAt);
    expect(reading.completedAt, finishedAt.completedAt);
    expect(reading.lastReadAt, finishedAt.lastReadAt);

    // Reopening it says what it is: not downloaded here, and not an error.
    final read = await h.open(ids[0]);
    expect(read.read, isA<OfflineReadUnavailable>());
    expect(
      (read.read as OfflineReadUnavailable).refusal,
      OfflineReadRefusal.noCopy,
    );
  });

  test('only the entry that was left is touched', () async {
    final ids = await serial(3);
    await finish(ids[0]);
    // The third is finished too, and is nowhere near this transition.
    await finish(ids[2]);
    await preferences.remember(
      await collectionOfSerial(),
      FinishedCleanupRule.remove,
    );

    await readOn(from: ids[0], to: ids[1]);

    expect(downloaded(ids[0]), isFalse);
    expect(downloaded(ids[1]), isTrue);
    expect(
      downloaded(ids[2]),
      isTrue,
      reason: 'a rule is applied to the entry being left, never to a set',
    );
  });
}
