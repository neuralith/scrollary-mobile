import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/device_harness.dart';

/// The harness is test infrastructure, so its own logic gets tests.
///
/// Deliberately **no `testWidgets` in this file**. A widget binding installs a
/// fake clock for the whole file, and a fake clock stops `Future.timeout`
/// firing — which is the very mechanism under test. The bounded `waitFor` needs
/// a tester and is exercised on the device instead.
///
/// Three physical-device runs were lost to a harness that sat inside a generous
/// timeout after a scenario had already failed, producing nothing for ten to
/// fifteen minutes. The fix is not longer timeouts — it is that every wait is
/// bounded, every scenario is capped, and a stall is reported as a *harness*
/// verdict rather than as evidence about the product.
void main() {
  test('a scenario that hangs is capped and reported as stalled', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    final result = await harness.scenario(
      'hangs forever',
      limit: const Duration(milliseconds: 400),
      body: () => Completer<void>().future,
    );
    expect(result.outcome, ScenarioOutcome.stalled);
    expect(
      result.detail,
      contains('ceiling'),
      reason: 'a stall must say it was the harness that ended it',
    );
  });

  test('a failing scenario is failed, not stalled', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    final result = await harness.scenario(
      'asserts something false',
      limit: const Duration(seconds: 5),
      body: () async => expect(1, 2),
    );
    expect(
      result.outcome,
      ScenarioOutcome.failed,
      reason:
          'failed is evidence about the product; stalled is evidence about '
          'the test. Conflating them wastes device time',
    );
  });

  test('teardown runs even when the body throws', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    var torndown = false;
    await harness.scenario(
      'throws',
      limit: const Duration(seconds: 5),
      body: () async => throw StateError('boom'),
      teardown: () async => torndown = true,
    );
    expect(
      torndown,
      isTrue,
      reason: 'the next scenario must start from a known device state',
    );
  });

  test('one failure does not take the matrix down', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    await harness.scenario(
      'first fails',
      limit: const Duration(seconds: 5),
      body: () async => throw StateError('boom'),
    );
    final second = await harness.scenario(
      'second still runs',
      limit: const Duration(seconds: 5),
      body: () async {},
    );
    expect(second.outcome, ScenarioOutcome.passed);
    expect(harness.results, hasLength(2));
  });

  test('a fatal failure abandons the rest rather than lying', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    await harness.scenario(
      'seeds everything after it',
      limit: const Duration(seconds: 5),
      body: () async => throw StateError('no Entry to read'),
      fatalOnFailure: true,
    );
    final later = await harness.scenario(
      'depends on the seed',
      limit: const Duration(seconds: 5),
      body: () async {},
    );
    expect(
      later.outcome,
      ScenarioOutcome.abandoned,
      reason:
          'continuing past a broken precondition produces results that look '
          'like evidence and are not',
    );
  });

  test('an early return is skipped, never passed', () async {
    // The harness committed this exact sin on its first real device run: a
    // six-round soak bailed out on a missing precondition and was recorded as
    // PASSED, which is manufactured evidence.
    final harness = DeviceHarness(fingerprint: 'test');
    final result = await harness.scenario(
      'bails out early',
      limit: const Duration(seconds: 5),
      body: () async {
        harness.skip('no Entry to read');
        return;
      },
    );
    expect(result.outcome, ScenarioOutcome.skipped);
    expect(result.detail, contains('no Entry'));
  });

  test(
    'a scenario that asserts nothing but completes is still passed',
    () async {
      final harness = DeviceHarness(fingerprint: 'test');
      final result = await harness.scenario(
        'runs fully',
        limit: const Duration(seconds: 5),
        body: () async {},
      );
      expect(result.outcome, ScenarioOutcome.passed);
    },
  );

  test('every scenario produces exactly one result', () async {
    final harness = DeviceHarness(fingerprint: 'test');
    for (var i = 0; i < 4; i++) {
      await harness.scenario(
        'scenario $i',
        limit: const Duration(seconds: 5),
        body: () async {
          if (i.isEven) throw StateError('x');
        },
      );
    }
    expect(harness.results, hasLength(4));
    expect(
      harness.results.map((r) => r.name).toSet(),
      hasLength(4),
      reason: 'a matrix that quietly drops a scenario is a shrinking matrix',
    );
  });

  test('the operation state is captured when a scenario ends', () async {
    final harness = DeviceHarness(fingerprint: 'test')
      ..operationState = () => 'scrolling';
    final result = await harness.scenario(
      'records where it was',
      limit: const Duration(seconds: 5),
      body: () async {
        harness.phase = 'inspecting the page';
        throw StateError('x');
      },
    );
    expect(result.lastPhase, 'inspecting the page');
    expect(
      result.lastOperationState,
      'scrolling',
      reason:
          'an application hold and a harness deadlock look identical without '
          'this',
    );
  });
}
