/// The restricted-site policy, asked at every V2 boundary for itself.
///
/// The V1 boundary matrix lived here before the cutovers; the boundaries
/// moved, the rule did not: **browsing is never restricted, only capture is;
/// enforcement is never UI-only; the policy judges pages, never assets; a
/// refusal is a terminal named outcome, never a silent delete.** The engine's
/// own two gates (before probing and again before commit) are pinned in
/// `test/save_v2/entry_capture_test.dart`; this file covers the boundaries
/// around it — the Browser's control, the queue, and the check's navigator.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/source_observation_browser.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/queue_task.dart';

import 'helpers/fake_browser.dart';
import 'save_v2/support/capture_harness.dart';

void main() {
  group('the Browser save control', () {
    test('is absent on a restricted page — not disabled, absent', () {
      expect(v2SaveAvailable(restrictedUrl('/serial/part-1')), isFalse);
      expect(
        v2SaveAvailable('https://reading.example.com/serial-alpha/part-1'),
        isTrue,
      );
    });

    test('non-web schemes never offer capture', () {
      expect(v2SaveAvailable('about:blank'), isFalse);
      expect(v2SaveAvailable('file:///etc/hosts'), isFalse);
    });
  });

  group('the queue', () {
    late CaptureHarness h;
    setUp(() => h = CaptureHarness());
    tearDown(() => h.close());

    test('refuses a restricted address at enqueue, with the one sentence, '
        'and writes no row that could later drive the engine there', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h.queue.enqueue(
        entryId: seeded.entry.id,
        locationUrl: restrictedUrl('/serial/part-2'),
      );
      expect(result.refusedReason, kCaptureRestrictedMessage);
      // A refusal at enqueue writes nothing: there is nothing to start, so
      // there is nothing to record — and nothing to silently delete later.
      expect(await h.queue.all(), isEmpty);
    });

    test('an ordinary address queues and waits for Start', () async {
      final seeded = await h.repos.seedLibrary();
      final result = await h.queue.enqueue(
        entryId: seeded.entry.id,
        locationUrl: seeded.location.url,
      );
      expect(result.refusedReason, isNull);
      expect(result.task!.state, SaveTaskState.queued);
      // Nothing runs without the explicit Start.
      expect(await h.queue.eligible(), isEmpty);
    });
  });

  group('the check\'s navigator owns the landed boundary', () {
    test('a listing that lands on a restricted service is refused with the '
        'named stop, and nothing is read from it', () async {
      final browser = FakeBrowser()..setUrl('about:blank');
      final landed = restrictedUrl('/serial');
      browser.redirects['https://reading.example.com/serial-alpha'] = landed;
      browser.addPage(
        landed,
        PageProbe(
          url: landed,
          title: 'listing',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          viewportWidth: 400,
          atBottom: false,
        ),
      );

      final source = BrowserSourceObservationSource(browser);
      final observation = await source.observe(
        source: SourceRow(
          id: 's1',
          collectionId: 'c1',
          host: 'reading.example.com',
          pathKey: '/serial-alpha',
          language: '',
          lifecycle: 'active',
          firstSeenAt: DateTime(2026),
          lastSeenAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        pageUrl: null,
        shouldContinue: () => true,
      );

      expect(observation.isReadable, isFalse);
      expect(observation.stop, SourceCheckStop.captureRestrictedForSite);
      expect(observation.listings, isEmpty);
    });
  });

  group('the sentence', () {
    test('is the policy\'s own, stating what the app does', () {
      expect(kCaptureRestrictedMessage, 'Saving isn’t available on this site.');
    });
  });
}
