/// What a Collection says about its last check.
///
/// The regression this pins: `checkLook()` built exactly these chips — *Not
/// checked yet · Checking · 3 new · Checked ‹when› · Check failed* — and every
/// surface that rendered them went out with the V1 library screens. The
/// function survived with no caller, so a Collection could not say whether it
/// had ever been checked or what came of it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/check_state.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/discovery.dart';

void main() {
  late CheckStateStore store;
  final at = DateTime.utc(2026, 8, 24, 12);

  setUp(() => store = CheckStateStore());
  tearDown(() => store.dispose());

  SourceCheckOutcome outcome({
    SourceCheckStop? stop,
    int found = 0,
    SourceCheckState state = SourceCheckState.upToDate,
  }) => SourceCheckOutcome(
    sourceId: 'source-1',
    state: state,
    stopReason: stop,
    pagesRead: 1,
    discovery: DiscoveryOutcome(
      createdEntryIds: [for (var i = 0; i < found; i++) 'entry-$i'],
    ),
  );

  test('a collection nobody has checked says nothing at all', () {
    final state = store.of('alpha');

    expect(state.checking, isFalse);
    expect(state.failed, isFalse);
    expect(state.checkedAt, isNull);
    expect(state.hasNews, isFalse);
  });

  test('a check in flight says so without blanking what it knew', () {
    store.recordCheck('alpha', outcome(found: 3), at: at);
    store.beginCheck('alpha');

    final state = store.of('alpha');
    expect(state.checking, isTrue);
    expect(
      state.newCount,
      3,
      reason: 'the row must not go blank while it reads',
    );
  });

  test('a check that found entries counts them', () {
    store.recordCheck('alpha', outcome(found: 3), at: at);

    expect(store.of('alpha').newCount, 3);
    expect(store.of('alpha').hasNews, isTrue);
    expect(store.of('alpha').checkedAt, at);
  });

  test('a check that found nothing is still a check', () {
    store.recordCheck('alpha', outcome(), at: at);

    // *Up to date* and *Not checked yet* are different answers, and the
    // timestamp is the whole difference.
    expect(store.of('alpha').checkedAt, at);
    expect(store.of('alpha').hasNews, isFalse);
    expect(store.of('alpha').failed, isFalse);
  });

  test('a reading that concluded nothing never stamps a time', () {
    store.recordCheck(
      'alpha',
      outcome(stop: SourceCheckStop.listingUnreadable),
      at: at,
    );

    final state = store.of('alpha');
    expect(state.failed, isTrue);
    expect(
      state.checkedAt,
      isNull,
      reason:
          '"Checked 2 minutes ago" over a site that would not load is the '
          'same lie the single sentence used to tell',
    );
  });

  test('a check that never ran leaves the collection as it was', () {
    store.recordCheck('alpha', outcome(found: 2), at: at);

    // Null outcome: the Browser was busy, or there was no site to read.
    store.recordCheck('alpha', null, at: at.add(const Duration(minutes: 5)));

    expect(store.of('alpha').newCount, 2);
    expect(store.of('alpha').checkedAt, at);
    expect(store.of('alpha').failed, isFalse);
  });

  test('seeing what was found clears the news and keeps the check', () {
    store.recordCheck('alpha', outcome(found: 4), at: at);

    store.clearNews('alpha');

    expect(store.of('alpha').hasNews, isFalse);
    expect(store.of('alpha').checkedAt, at);
  });

  test('collections do not share state', () {
    store.recordCheck('alpha', outcome(found: 1), at: at);

    expect(store.of('beta').checkedAt, isNull);
  });

  group('how long ago it was', () {
    String ago(Duration elapsed) => checkedAgoLabel(at, now: at.add(elapsed));

    test('is coarse, because a row is not a clock', () {
      expect(ago(const Duration(seconds: 20)), 'just now');
      expect(ago(const Duration(minutes: 7)), '7m ago');
      expect(ago(const Duration(hours: 5)), '5h ago');
      expect(ago(const Duration(days: 3)), '3d ago');
    });
  });
}
