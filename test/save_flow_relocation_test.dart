/// Browsing straight to a moved address, and saving it.
///
/// **The duplicate this is for.** A provider rewrites part of its URL
/// structure; the user opens the new address and saves it. The library holds
/// the work already, but under the old key — so the picker's *add this site to
/// a Collection I already have* used to write a **second Source**, and
/// starting a new Collection instead wrote a **duplicate of the work**.
/// Neither was ever asked about.
///
/// The rule: the identity answer stays the user's (V2-D45), and the narrower
/// question the flow never asked — *move the Source, or add one beside it?* —
/// is now asked before anything is written.
///
/// Hosts are the reserved `.example` names. No real provider is named.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/features/v2_add_flow.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/library_ui/providers.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/relocation.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';
import 'library_ui/support/ui_harness.dart';

const String kHost = 'reading.example.com';
const String kOldPath = '/serial-alpha-08677664';
const String kNewPath = '/serial-alpha-a728349g';

String movedEntryUrl(int n) => 'https://$kHost$kNewPath/part-$n';
String oldEntryUrl(int n) => 'https://$kHost$kOldPath/part-$n';

void main() {
  // ─── the rule, over the library and nothing else ──────────────────────────

  group('relocationCandidateFor', () {
    late UiHarness h;
    late String collectionId;

    setUp(() async {
      h = UiHarness();
      final root = await h.root();
      collectionId = (await h.collection('Serial Alpha', folderId: root.id)).id;
    });
    tearDown(() => h.close());

    Future<SourceRelocationCandidate?> ask([String? url]) =>
        relocationCandidateFor(
          collections: h.collections,
          index: RecognitionIndex(h.db),
          collectionId: collectionId,
          keys: RecognitionKeys.of(url ?? movedEntryUrl(101)),
        );

    test('names the Collection\'s one Source on this host at another '
        'path', () async {
      final source = await h.source(
        collectionId,
        host: kHost,
        pathKey: kOldPath,
      );

      final candidate = await ask();
      expect(candidate, isNotNull);
      expect(candidate!.sourceId, source.id);
      expect(candidate.previousPathKey, kOldPath);
      expect(candidate.pathKey, kNewPath);
      expect(candidate.listingsSeen, 0, reason: 'no listing was read');
    });

    test('is silent when the Collection has no Source on this host', () async {
      await h.source(collectionId, host: 'other.example', pathKey: kOldPath);
      expect(await ask(), isNull);
    });

    test('is silent when the address is already a Source', () async {
      await h.source(collectionId, host: kHost, pathKey: kOldPath);
      await h.source(collectionId, host: kHost, pathKey: kNewPath);
      expect(await ask(), isNull);
    });

    test('is silent when two Sources on this host could be the one that '
        'moved', () async {
      await h.source(collectionId, host: kHost, pathKey: kOldPath);
      await h.source(collectionId, host: kHost, pathKey: '/serial-alpha-old2');
      expect(
        await ask(),
        isNull,
        reason: 'which of them moved is not a guess to make',
      );
    });

    test('is silent for an address with no stable Source key', () async {
      await h.source(collectionId, host: kHost, pathKey: kOldPath);
      expect(await ask('https://$kHost/'), isNull);
    });

    test('ignores a Source that is already marked gone', () async {
      await h.source(
        collectionId,
        host: kHost,
        pathKey: kOldPath,
        lifecycle: SourceLifecycle.dead,
      );
      expect(await ask(), isNull);
    });
  });

  // ─── the production save flow ─────────────────────────────────────────────

  group('saving a page at a moved address', () {
    late UiHarness h;
    late FakeBrowser browser;
    late ForegroundMultitasking capability;
    late String collectionId;
    late SourceRow source;

    /// Every add the sheet asked for, so a test can say which path it took.
    final adds = <({String? collectionId, String? newCollectionName})>[];

    Future<AddToLibraryReport> recordingAdd(
      WidgetRef ref, {
      required String url,
      required String pageTitle,
      String? collectionId,
      String? newCollectionName,
      String? folderId,
      SaveLimits? limits,
      bool isListing = false,
      bool discoverMissing = false,
      CaptureMode? captureMode,
      bool captureModeIsUserSet = false,
    }) async {
      adds.add((
        collectionId: collectionId,
        newCollectionName: newCollectionName,
      ));
      return AddToLibraryReport(sentence: 'added', collectionId: collectionId);
    }

    // Synchronous, and deliberately: `setUp` runs outside the fake async zone
    // `testWidgets` installs, so seeding the library here leaves the
    // repositories' future chains on the real microtask queue and the awaiting
    // test hangs forever. Everything the library needs is seeded by [seed],
    // inside the test body.
    setUp(() {
      adds.clear();
      h = UiHarness();
      browser = FakeBrowser();
      capability = ForegroundMultitasking();
    });
    tearDown(() {
      capability.dispose();
      return h.close();
    });

    /// The library as it stands before the provider moved: one Collection,
    /// published on one site, at the address that is about to go stale.
    Future<void> seed() async {
      final root = await h.root();
      collectionId = (await h.collection('Serial Alpha', folderId: root.id)).id;
      source = await h.source(collectionId, host: kHost, pathKey: kOldPath);
    }

    Future<void> openPanel(WidgetTester tester, {String? url}) async {
      final address = url ?? movedEntryUrl(101);
      browser
        ..setUrl(address)
        ..addPage(
          address,
          PageProbe(
            url: address,
            title: 'Serial Alpha Part 101',
            readyState: 'complete',
            documentHeight: 2000,
            viewportHeight: 800,
            viewportWidth: 400,
            atBottom: false,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryUiServicesProvider.overrideWithValue(h.services),
            browserProvider.overrideWithValue(browser),
            saveQueueStarterProvider.overrideWithValue(h.starter),
            v2AddAndDownloadProvider.overrideWithValue(recordingAdd),
            foregroundMultitaskingProvider.overrideWithValue(capability),
          ],
          child: MaterialApp(
            theme: appTheme(palette: AppPalette.light),
            home: Scaffold(
              body: V2SavePanel(
                url: address,
                pageTitle: 'Serial Alpha Part 101',
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Open the picker and choose one Collection by id.
    ///
    /// The filter is cleared first: the picker pre-fills it with the detected
    /// title as a *suggestion*, so a Collection whose name does not contain it
    /// is simply not on screen until the user clears it.
    Future<void> pick(WidgetTester tester, String id) async {
      await tapAndPump(tester, find.byKey(const ValueKey('v2AddToCollection')));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('collectionPickerFilter')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('collectionPickerFilter')),
        '',
      );
      await tester.pump();
      await pumpUntil(tester, find.byKey(ValueKey('collectionOption-$id')));
      await tapAndPump(tester, find.byKey(ValueKey('collectionOption-$id')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Choose the Collection the library already holds.
    Future<void> pickExisting(WidgetTester tester) =>
        pick(tester, collectionId);

    Future<void> answer(WidgetTester tester, String key) async {
      await tapAndPump(tester, find.byKey(ValueKey(key)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    screenTest('the user is asked before anything is written', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);

      expect(
        find.text('Is this the same site at a new address?'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sourceMovedUpdate')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sourceMovedAddSource')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sourceMovedDifferent')),
        findsOneWidget,
      );
      expect(adds, isEmpty, reason: 'nothing is saved until it is answered');
      expect((await h.collections.sourcesOf(collectionId)).length, 1);
    });

    screenTest('the third answer says what it really does here — carry on, '
        'not open a browser', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);

      expect(
        find.textContaining('Carry on and save this as a new collection'),
        findsOneWidget,
      );
      expect(find.textContaining('Opens the new address'), findsNothing);
    });

    screenTest('an ordinary save to a Collection with no Source on this host '
        'is never asked', (tester) async {
      final root = await h.root();
      final other = await h.collection('Another Work', folderId: root.id);
      await h.source(other.id, host: 'elsewhere.example', pathKey: '/thing');

      await seed();
      await openPanel(tester);
      await pick(tester, other.id);

      expect(
        find.text('Is this the same site at a new address?'),
        findsNothing,
      );
    });

    // --- the three answers -------------------------------------------------

    screenTest('Update this source moves it, and no second Source is '
        'written', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);
      await answer(tester, 'sourceMovedUpdate');

      final rows = await h.collections.sourcesOf(collectionId);
      final moved = rows.firstWhere((s) => s.id != source.id);
      final left = rows.firstWhere((s) => s.id == source.id);
      expect(left.lifecycle, SourceLifecycle.resolvedInto.name);
      expect(left.resolvedIntoSourceId, moved.id);
      expect(moved.pathKey, kNewPath);
      expect(
        rows.where((s) => s.lifecycle == SourceLifecycle.active.name).length,
        1,
        reason: 'one live Source, at the new address',
      );
    });

    screenTest('Add as another source leaves the old one alone and carries on '
        'with that Collection', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);
      await answer(tester, 'sourceMovedAddSource');

      // The answer itself writes nothing here: the second Source is the
      // adoption's, written when the save goes through. What matters is that
      // the Source already held is untouched — not pointed anywhere, not
      // superseded — which is exactly what *Update this source* would have
      // done instead.
      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 1);
      expect(rows.single.pathKey, kOldPath);
      expect(rows.single.lifecycle, SourceLifecycle.active.name);
      expect(rows.single.resolvedIntoSourceId, isNull);

      // And the sheet carried on with the Collection that was picked rather
      // than a new one: the create path's name field is absent.
      expect(find.byKey(const ValueKey('collectionNameField')), findsNothing);
      expect(adds, isEmpty);
    });

    screenTest('It\'s different content carries on into the create flow, and '
        'leaves the Collection alone', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);
      await answer(tester, 'sourceMovedDifferent');

      // The Collection that was picked is untouched.
      final rows = await h.collections.sourcesOf(collectionId);
      expect(rows.length, 1);
      expect(rows.single.pathKey, kOldPath);
      expect(rows.single.lifecycle, SourceLifecycle.active.name);

      // And the sheet has become the one that *starts* a Collection: the name
      // field is the create path's, and it is only built for a Collection
      // about to exist (V2-D62).
      expect(
        find.byKey(const ValueKey('collectionNameField')),
        findsOneWidget,
        reason: 'the ordinary create flow continues from here',
      );
      expect(adds, isEmpty, reason: 'and nothing is saved until it is asked');
    });

    screenTest('backing out of the question writes nothing and saves '
        'nothing', (tester) async {
      await seed();
      await openPanel(tester);
      await pickExisting(tester);
      await answer(tester, 'sourceMovedNotNow');

      expect((await h.collections.sourcesOf(collectionId)).length, 1);
      expect(adds, isEmpty);
    });

    // --- what a move must not cost -----------------------------------------

    screenTest('Update this source keeps entries, progress and downloads', (
      tester,
    ) async {
      await seed();
      final entry = await h.entryIn(
        collectionId,
        title: 'Part 100',
        ordinal: 100,
      );
      await h.location(
        entry.id,
        oldEntryUrl(100),
        sourceId: source.id,
        sourceNumber: 100,
      );
      await h.reading.recordSourceAccess(entry.id);
      final copy = await h.offline.recordCopy(
        entryId: entry.id,
        locationUrl: oldEntryUrl(100),
        artifactFormat: 'imageSequence',
        contentPath: 'packages/${entry.id}',
        byteSize: 4096,
      );

      await openPanel(tester);
      await pickExisting(tester);
      await answer(tester, 'sourceMovedUpdate');

      expect((await h.entries.entriesOf(collectionId)).length, 1);
      expect((await h.reading.stateOf(entry.id)).lastReadAt, isNotNull);
      final held = await h.offline.activeCopyOf(entry.id);
      expect(held?.id, copy.id);
      expect(held?.byteSize, 4096);
    });
  });
}
