import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/check_controller.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/capture_policy.dart'
    show restrictedCaptureDomains;

import 'data/support/repo_harness.dart';
import 'helpers/fake_browser.dart';

/// What a Source check refuses to do before it starts reading.
///
/// Three guards, all of them app-level and none of them in
/// `recognition/check.dart`: the WebView must actually be on screen, exactly
/// one thing may automate it at a time, and a restricted Source is refused
/// before anything opens. V1 asserted the first of these against
/// `UpdateChecker` in `foreground_multitasking_test.dart` and
/// `hidden_webview_test.dart`; the controller that replaced it makes the same
/// promise from `CheckController.run`.
const _limits = SourceCheckLimits(maxPages: 1, maxNewEntries: 5);

/// Reads back whoever holds the Browser, at the moment the reading happens.
typedef BrowserOwnerProbe = String? Function();

/// A listing nobody can read, and a record of every time it was asked.
///
/// The reading itself is not what these tests are about: the question is
/// only whether the check reached this seam at all, and what it was holding
/// when it did.
class _RecordingObservations implements SourceObservationSource {
  /// One entry per `observe` call, holding the page it was asked for — null
  /// for "wherever this Source's listing begins".
  final List<String?> asked = [];

  /// Whoever held the Browser at the moment the reading happened.
  final List<String?> ownerWhileReading = [];

  /// Set to make the reading throw rather than return, which is the failure
  /// path the `finally` in `CheckController.run` exists for.
  Object? failWith;

  BrowserOwnerProbe? owner;

  int get calls => asked.length;

  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) async {
    asked.add(pageUrl);
    ownerWhileReading.add(owner?.call());
    final failure = failWith;
    if (failure != null) throw failure;
    return SourceObservation.unreadable(
      url: pageUrl ?? '',
      stop: SourceCheckStop.listingUnreadable,
    );
  }
}

void main() {
  late RepoHarness repos;
  late FakeBrowser browser;
  late _RecordingObservations observations;
  late CheckController controller;

  setUp(() {
    repos = RepoHarness();
    browser = FakeBrowser();
    observations = _RecordingObservations()
      ..owner = () => browser.automationOwner;
    controller = CheckController(
      browser: browser,
      collections: repos.collections,
      entries: repos.entries,
      index: repos.recognition,
      observations: observations,
    );
  });

  tearDown(() async {
    controller.dispose();
    await repos.close();
  });

  /// A Collection with one preferred Source on a reserved example host.
  Future<String> readableCollection() async {
    final seed = await repos.seedLibrary();
    final violation = await repos.collections.setPreferredSource(
      seed.collection.id,
      seed.source.id,
    );
    expect(violation, isNull);
    return seed.collection.id;
  }

  /// The same, on a host the capture policy refuses. The host is read from the
  /// policy itself — no hostname belongs in this repository.
  Future<String> restrictedCollection() async {
    final root = await repos.folders.ensureRoot();
    final (collection, collectionViolation) = await repos.collections.create(
      name: 'On a restricted service',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(collectionViolation, isNull);
    final (source, sourceViolation) = await repos.collections.addSource(
      collectionId: collection!.id,
      host: restrictedCaptureDomains.first,
      pathKey: 'serial-alpha',
    );
    expect(sourceViolation, isNull);
    expect(
      await repos.collections.setPreferredSource(collection.id, source!.id),
      isNull,
    );
    return collection.id;
  }

  group('the render guard', () {
    testWidgets('a check started while the app is not compositing the WebView '
        'reads nothing until the surface paints', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final collectionId = await readableCollection();
      browser.surfaceIsPainted = false;

      final outcome = controller.run(collectionId, limits: _limits);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The hold, which is the whole point: a document created in a view the
      // app is not drawing is born hidden and stays that way.
      expect(
        observations.calls,
        0,
        reason: 'no page is read while the WebView is not being drawn',
      );
      expect(browser.navigations, isEmpty);
      expect(controller.isRunning, isTrue, reason: 'held, not abandoned');

      browser.surfaceIsPainted = true;
      await tester.pumpAndSettle();

      expect(observations.calls, 1, reason: 'it proceeds once the app draws');
      expect((await outcome)?.stopReason, SourceCheckStop.listingUnreadable);
    });

    testWidgets('a check on a surface the app is already drawing reads '
        'straight away', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final collectionId = await readableCollection();

      final outcome = await controller.run(collectionId, limits: _limits);

      expect(observations.calls, 1);
      expect(observations.asked.single, isNull, reason: 'the first page');
      expect(outcome, isNotNull);
    });
  });

  group('one owner at a time', () {
    test('a check refuses to start while the Browser is already being '
        'automated', () async {
      final collectionId = await readableCollection();
      browser.automationOwner = 'a save run';

      final outcome = await controller.run(collectionId, limits: _limits);

      expect(outcome, isNull, reason: 'refused, and it says so by returning');
      expect(observations.calls, 0, reason: 'nothing was opened');
      expect(controller.isRunning, isFalse);
      expect(
        browser.automationOwner,
        'a save run',
        reason: 'the run that already held it still holds it',
      );
    });

    test(
      'the check holds the Browser for its own run and hands it back',
      () async {
        final collectionId = await readableCollection();
        expect(browser.isAutomating, isFalse);

        await controller.run(collectionId, limits: _limits);

        expect(
          observations.ownerWhileReading.single,
          isNotNull,
          reason: 'the check owned the Browser while it read',
        );
        expect(browser.automationOwner, isNull, reason: 'released at the end');
        expect(controller.isRunning, isFalse);
      },
    );

    test('the ownership is released even when the check fails', () async {
      final collectionId = await readableCollection();
      observations.failWith = StateError('the reading blew up');

      await expectLater(
        controller.run(collectionId, limits: _limits),
        throwsStateError,
      );

      expect(browser.automationOwner, isNull);
      expect(browser.isAutomating, isFalse);
      expect(controller.isRunning, isFalse);

      // The proof that the release is real: the next check can start.
      observations.failWith = null;
      expect(await controller.run(collectionId, limits: _limits), isNotNull);
    });
  });

  group('a Source this app does not capture from', () {
    test('a restricted host is refused before anything opens', () async {
      final collectionId = await restrictedCollection();

      final outcome = await controller.run(collectionId, limits: _limits);

      expect(outcome, isNull);
      expect(observations.calls, 0, reason: 'the listing is never read');
      expect(browser.navigations, isEmpty, reason: 'nothing is navigated');
      expect(
        browser.automationOwner,
        isNull,
        reason: 'the Browser is never claimed for a run that cannot happen',
      );
      expect(controller.isRunning, isFalse);
    });

    test('a readable host in the same library is not refused', () async {
      // The guard above is about this Source, not about checks in general.
      final collectionId = await readableCollection();
      await restrictedCollection();

      expect(await controller.run(collectionId, limits: _limits), isNotNull);
      expect(observations.calls, 1);
    });
  });
}
