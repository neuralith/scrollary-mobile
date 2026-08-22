/// H4 — Download to Mobile, end to end, and the invariant it exists to prove:
/// **the backend made no outbound request** (V2_SYNC.md §6.2, §7).
///
/// The scenario is the product one. A browser extension — raw HTTP with a
/// User-Agent of its own and no capture engine at all — records an intent. A
/// phone pulls it, claims it against the real single-winner transition, and
/// turns the win into an ordinary local save task that **waits for Start**. A
/// second phone racing the same request loses and writes nothing. The device
/// that won reports how its save ended, and the service records the outcome.
///
/// Two independent halves of the no-outbound invariant meet here: the
/// simulated source sites in this process count zero requests (below), and
/// `tool/e2e/run.sh` samples every TCP peer the service ever held.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/stop_conditions.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late E2EClient c;
  late RawApi raw;
  late RawApi extension;

  final entryIds = <int, String>{};
  final locationIds = <int, String>{};
  late String requestOne;
  late String requestTwo;
  late String requestThree;
  late String taskOne;

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('h4');
    a = E2EClient.start('phone-A', library);
    c = E2EClient.start('phone-C', library);
    raw = RawApi(library: library);
    // The extension is a client of the same contract with no capture engine.
    // Its User-Agent is its own, and it never asks the service to fetch.
    extension = RawApi(
      library: library,
      userAgent: 'ScrollaryExtension/0.1 (browser; no capture engine)',
    );

    final root = await a.folders.ensureRoot();
    final (collection, _) = await a.collections.create(
      name: 'Fixture multi-source work',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final sourceKeys = RecognitionKeys.of(fixture.partUrl('alpha', 1));
    final (source, _) = await a.collections.addSource(
      collectionId: collection!.id,
      host: sourceKeys.host,
      pathKey: sourceKeys.pathKey!,
      language: 'en',
    );
    for (final part in [1, 2, 3]) {
      final keys = RecognitionKeys.of(fixture.partUrl('alpha', part));
      final (entry, _) = await a.entries.createInCollection(
        collectionId: collection.id,
        ordinal: part.toDouble(),
        title: 'Part $part',
      );
      entryIds[part] = entry!.id;
      final (location, _) = await a.entries.addLocation(
        entryId: entry.id,
        sourceId: source!.id,
        url: fixture.partUrl('alpha', part),
        urlKey: keys.urlKey,
        sourceLabel: 'Part $part',
        sourceNumber: part.toDouble(),
      );
      locationIds[part] = location!.id;
    }
    await a.sync();
    await c.sync();
  });

  tearDownAll(() async {
    raw.close();
    extension.close();
    await a.stop();
    await c.stop();
    fixture.expectNothingFetched('H4 Download to Mobile');
    await fixture.stop();
  });

  test(
    'the extension records one intent however often it is pressed',
    () async {
      final first = await extension.post('/download-requests', {
        'entry_id': entryIds[1],
        'location_id': locationIds[1],
        'idempotency_key': 'extension-press-1',
        'created_by': 'browser extension',
      });
      expect(first.status, 201, reason: first.raw);
      requestOne = first.body['id']! as String;
      expect(first.body['state'], 'pending');
      expect(first.body['claimed_by_device'], '');
      final revisionAfterFirst = await raw.latestRevision();

      final second = await extension.post('/download-requests', {
        'entry_id': entryIds[1],
        'location_id': locationIds[1],
        'idempotency_key': 'extension-press-2',
        'created_by': 'browser extension',
      });
      expect(
        second.status,
        200,
        reason: 'pressing the button twice is not two saves',
      );
      expect(second.body['id'], requestOne);
      expect(second.body['state'], 'pending');
      expect(
        await raw.latestRevision(),
        revisionAfterFirst,
        reason: 'the second press manufactures no change for anyone to pull',
      );
    },
  );

  test('a phone claims the intent, and the save waits for Start', () async {
    await a.sync();
    final mirrored = await a.requests.byId(requestOne);
    expect(
      mirrored,
      isNotNull,
      reason: 'the intent arrived as an ordinary row',
    );
    expect(mirrored!.state, 'pending');
    expect(mirrored.entryId, entryIds[1]);
    expect(mirrored.createdBy, 'browser extension');

    final report = await a.consumer.consume(a.transport);
    expect(report.claimed, 1);
    expect(report.lost, 0);
    expect(report.errors, isEmpty);

    final claimed = await a.requests.byId(requestOne);
    expect(claimed!.state, 'claimed');
    expect(claimed.claimedByDevice, await a.deviceLabel());

    final task = await a.queue.openTaskFor(entryIds[1]!);
    expect(task, isNotNull, reason: 'the win became an ordinary save task');
    taskOne = task!.id;
    expect(task.state, SaveTaskState.queued);
    expect(task.origin, SaveTaskOrigin.queue);
    expect(task.locationUrl, fixture.partUrl('alpha', 1));
    expect(
      a.queue.saveStartAuthorised,
      isFalse,
      reason: 'a synced intent never authorises anything',
    );
    expect(
      await a.queue.eligible(),
      isEmpty,
      reason: 'nothing is eligible to run until the user presses Start',
    );

    // Claiming is a metadata exchange: it fetched no page, and the server
    // still holds only the intent.
    final onServer = (await raw.entities('downloadRequest'))[requestOne]!;
    expect(onServer['state'], 'claimed');
    expect(onServer['claimed_by_device'], await a.deviceLabel());
    expect(onServer['resolved_at'], isNull);
  });

  test('two phones race one claim and exactly one wins', () async {
    final created = await extension.post('/download-requests', {
      'entry_id': entryIds[2],
      'idempotency_key': 'extension-press-3',
      'created_by': 'browser extension',
    });
    expect(created.status, 201, reason: created.raw);
    requestTwo = created.body['id']! as String;

    await a.sync();
    await c.sync();
    expect((await a.requests.byId(requestTwo))!.state, 'pending');
    expect((await c.requests.byId(requestTwo))!.state, 'pending');

    final winner = await c.consumer.consume(c.transport);
    expect(winner.claimed, 1);
    expect(winner.lost, 0);

    final loser = await a.consumer.consume(a.transport);
    expect(loser.claimed, 0);
    expect(
      loser.lost,
      1,
      reason: 'the 409 says another device holds it; this one marks nothing',
    );
    expect(loser.errors, isEmpty);
    expect(
      await a.queue.openTaskFor(entryIds[2]!),
      isNull,
      reason: 'a losing device writes no save task',
    );
    expect(
      (await raw.entities('downloadRequest'))[requestTwo]!['claimed_by_device'],
      await c.deviceLabel(),
    );

    // The loser converges on the next pull rather than on a guess.
    await a.sync();
    final onA = await a.requests.byId(requestTwo);
    expect(onA!.state, 'claimed');
    expect(onA.claimedByDevice, await c.deviceLabel());
  });

  test(
    'a claim whose local write never happened is recovered, not repeated',
    () async {
      final created = await extension.post('/download-requests', {
        'entry_id': entryIds[3],
        'idempotency_key': 'extension-press-4',
        'created_by': 'browser extension',
      });
      expect(created.status, 201, reason: created.raw);
      requestThree = created.body['id']! as String;
      await a.sync();
      expect((await a.requests.byId(requestThree))!.state, 'pending');

      // The claim lands on the service and the device dies before writing it —
      // spelled here as the claim being made out of band under A's own label.
      final device = await a.deviceLabel();
      final claim = await raw.post('/download-requests/$requestThree/claim', {
        'device': device,
      });
      expect(claim.status, 200, reason: claim.raw);

      final report = await a.consumer.consume(a.transport);
      expect(
        report.claimed,
        1,
        reason: 'a 409 naming this device is our own claim, not a second one',
      );
      expect(report.lost, 0);
      final recovered = await a.queue.openTaskFor(entryIds[3]!);
      expect(recovered, isNotNull);
      expect(recovered!.state, SaveTaskState.queued);

      // And a repeat is idempotent: the open-task index refuses a second row.
      final again = await a.consumer.consume(a.transport);
      expect(again.claimed, 0);
      expect(again.requeued, 0);
      expect(
        (await a.queue.all()).where((t) => t.entryId == entryIds[3]).length,
        1,
      );
    },
  );

  test('a terminal save is reported once and shows on the service', () async {
    // The device's own save ran and ended. Driving the queue directly is the
    // whole of what a capture engine would leave behind here.
    expect(await a.queue.claim(taskOne), isNotNull);
    expect(
      await a.queue.finish(
        taskOne,
        state: SaveTaskState.completed,
        outcome: 'saved',
      ),
      isTrue,
    );

    final report = await a.consumer.consume(a.transport);
    expect(report.resolved, 1);
    expect((await a.requests.byId(requestOne))!.state, 'completed');
    expect(
      await a.outbox.pendingCount(),
      1,
      reason:
          'the outcome is one intent, and it is the only one this table '
          'ever produces',
    );

    await a.sync();
    expect(await a.outbox.pendingCount(), 0);
    final onServer = (await raw.entities('downloadRequest'))[requestOne]!;
    expect(onServer['state'], 'completed');
    expect(onServer['resolved_at'], isA<String>());
    expect(onServer['failure_reason'], '');
  });

  test('a failed save changes no library membership (I17)', () async {
    final entriesBefore = jsonEncode(await raw.entities('entry'));
    final locationsBefore = jsonEncode(await raw.entities('location'));

    final task = await c.queue.openTaskFor(entryIds[2]!);
    expect(task, isNotNull);
    expect(await c.queue.claim(task!.id), isNotNull);
    expect(
      await c.queue.finish(
        task.id,
        state: SaveTaskState.failed,
        lastError: 'the source refused the page',
        stopReason: StopReason.accessDenied,
      ),
      isTrue,
    );

    final report = await c.consumer.consume(c.transport);
    expect(report.resolved, 1);
    await c.sync();

    final onServer = (await raw.entities('downloadRequest'))[requestTwo]!;
    expect(onServer['state'], 'failed');
    expect(
      onServer['failure_reason'],
      StopReason.accessDenied.name,
      reason: 'the run own named stop condition, never an invented one',
    );

    expect(
      jsonEncode(await raw.entities('entry')),
      entriesBefore,
      reason: 'I17: a failure leaves the Entry exactly as it was',
    );
    expect(jsonEncode(await raw.entities('location')), locationsBefore);
    expect(await c.entries.byId(entryIds[2]!), isNotNull);
    expect(await c.entries.locationsOf(entryIds[2]!), hasLength(1));

    // Every device converges on the terminal states, and nothing else moved.
    await a.sync();
    expect((await a.requests.byId(requestTwo))!.state, 'failed');
    expect((await a.requests.byId(requestOne))!.state, 'completed');
    expect((await a.requests.byId(requestThree))!.state, 'claimed');
  });
}
