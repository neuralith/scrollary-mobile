import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';

import 'helpers/v2_harness.dart';

/// Leaving the Browser mid-work: what the shell's surface policy reads.
///
/// The V1 run's phase-by-phase pause model retired with
/// `lib/save/save_run.dart` (roadmap §10, after E2 + E3). The V2 engine holds
/// itself when its surface stops painting — its render guards are ported
/// verbatim and pinned in the engine's own tests — so the app level keeps
/// only one contract: while the runner or a check is running, the shell must
/// keep the Browser's surface painted, and it learns that through
/// `needsRenderedBrowser` on a Listenable. This file pins that contract.
void main() {
  late V2Harness v2;

  setUp(() {
    v2 = V2Harness(browser: BrowserController(), fileStore: tempFileStore());
  });
  tearDown(() => v2.close());

  group('the queue runner', () {
    test('needs the Browser exactly while it runs', () {
      expect(v2.runner.needsRenderedBrowser, isFalse);
      v2.runner.debugSetRunning(true);
      expect(v2.runner.needsRenderedBrowser, isTrue);
      v2.runner.debugSetRunning(false);
      expect(v2.runner.needsRenderedBrowser, isFalse);
    });

    test('announces the change, so the shell can recompute its surface', () {
      var notified = 0;
      v2.runner.addListener(() => notified++);
      v2.runner.debugSetRunning(true);
      expect(notified, 1);
    });
  });

  group('a source check', () {
    test('needs the Browser exactly while it runs', () {
      expect(v2.check.needsRenderedBrowser, isFalse);
      v2.check.debugSetRunning(true);
      expect(v2.check.needsRenderedBrowser, isTrue);
      v2.check.debugSetRunning(false);
      expect(v2.check.needsRenderedBrowser, isFalse);
    });

    test('announces the change', () {
      var notified = 0;
      v2.check.addListener(() => notified++);
      v2.check.debugSetRunning(true);
      expect(notified, 1);
    });
  });
}
