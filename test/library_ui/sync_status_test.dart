/// `Settings → Sync`: what it derives, what it says, and what it refuses to
/// do anywhere else (roadmap G7, D7).
///
/// The property this file is really about is a negative one. **A healthy sync
/// produces no user-visible event.** Not a snackbar, not a badge, not a row in
/// the Library, not a thing in the reader — one line of calm text on one
/// screen, and only because somebody went looking for it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library_ui/sync_status_section.dart';
import 'package:web_reader/sync/session.dart';
import 'package:web_reader/sync/status.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

import 'support/ui_harness.dart' show screenTest;

SyncStatus _snapshot({
  int pending = 0,
  int rejected = 0,
  DateTime? lastSuccessAt,
  String? lastError,
}) => SyncStatus(
  pendingCount: pending,
  rejectedCount: rejected,
  cursor: 12,
  lastSuccessAt: lastSuccessAt,
  lastAttemptAt: lastSuccessAt,
  lastError: lastError,
);

/// A stand-in for the scheduler. The section is allowed to know exactly this
/// much, which is why it can be tested without a clock or a transport.
class _FakeSource implements SyncStatusSource {
  _FakeSource(this._status);

  SyncStatusView _status;
  final StreamController<SyncStatusView> _views =
      StreamController<SyncStatusView>.broadcast();

  int refreshes = 0;
  int syncNowCalls = 0;

  @override
  SyncStatusView get status => _status;

  @override
  Stream<SyncStatusView> get statusChanges => _views.stream;

  @override
  Future<void> refreshStatus() async => refreshes += 1;

  @override
  Future<void> syncNow() async => syncNowCalls += 1;

  void emit(SyncStatusView view) {
    _status = view;
    _views.add(view);
  }

  Future<void> close() => _views.close();
}

void main() {
  final now = DateTime.utc(2026, 8, 21, 12);

  group('deriving the state', () {
    test('nothing configured outranks everything else', () {
      final view = deriveSyncStatus(
        snapshot: _snapshot(pending: 4, rejected: 2),
        configured: false,
        running: true,
        nextRetryAt: now.add(const Duration(minutes: 1)),
      );
      expect(view.phase, SyncPhase.neverConfigured);
      expect(
        view.nextRetryAt,
        isNull,
        reason: 'there is nothing to retry against',
      );
      expect(view.isHealthy, isFalse);
    });

    test('a run in flight outranks a scheduled retry', () {
      final view = deriveSyncStatus(
        snapshot: _snapshot(pending: 2),
        configured: true,
        running: true,
        nextRetryAt: now.add(const Duration(minutes: 1)),
      );
      expect(view.phase, SyncPhase.syncing);
      expect(view.isRunning, isTrue);
      expect(view.isHealthy, isFalse);
    });

    test('a scheduled retry outranks a parked rejection', () {
      final view = deriveSyncStatus(
        snapshot: _snapshot(rejected: 3),
        configured: true,
        running: false,
        nextRetryAt: now.add(const Duration(minutes: 2)),
      );
      expect(view.phase, SyncPhase.retrying);
      expect(
        view.problemCount,
        3,
        reason: 'the count is carried whatever the phase says',
      );
    });

    test('attention is exactly and only a parked rejection', () {
      final quiet = deriveSyncStatus(
        snapshot: _snapshot(pending: 9, lastSuccessAt: now),
        configured: true,
        running: false,
      );
      expect(quiet.phase, SyncPhase.idle);
      expect(quiet.isHealthy, isTrue, reason: 'waiting work is not a problem');

      final refused = deriveSyncStatus(
        snapshot: _snapshot(rejected: 1, lastSuccessAt: now),
        configured: true,
        running: false,
      );
      expect(refused.phase, SyncPhase.attention);
      expect(refused.isHealthy, isFalse);
    });

    test('a device that has never synced is idle, not broken', () {
      final view = deriveSyncStatus(
        snapshot: null,
        configured: true,
        running: false,
      );
      expect(view.phase, SyncPhase.idle);
      expect(view.lastSuccessAt, isNull);
      expect(view.pendingCount, 0);
      expect(view.isHealthy, isTrue);
    });
  });

  group('what it says', () {
    SyncStatusView view(
      SyncPhase phase, {
      int pending = 0,
      DateTime? retryAt,
    }) => SyncStatusView(
      phase: phase,
      pendingCount: pending,
      nextRetryAt: retryAt,
      lastSuccessAt: now.subtract(const Duration(minutes: 5)),
    );

    test('quiet when there is nothing to say', () {
      expect(syncStatusSentence(view(SyncPhase.idle), now), 'Up to date.');
      expect(
        syncStatusSentence(view(SyncPhase.idle, pending: 3), now),
        'Changes are waiting to sync.',
      );
    });

    test('an unreachable service says when it will try again', () {
      final sentence = syncStatusSentence(
        view(SyncPhase.retrying, retryAt: now.add(const Duration(minutes: 2))),
        now,
      );
      expect(sentence, contains('could not be reached'));
      expect(sentence, contains('in 2m'));
      // What the app will do, never what the user should do about it.
      expect(sentence, isNot(contains('try')));
      expect(sentence.toLowerCase(), isNot(contains('check your')));
    });

    test('an unset device says so rather than claiming to be up to date', () {
      expect(
        syncStatusSentence(view(SyncPhase.neverConfigured), now),
        'Sync is not set up on this device.',
      );
    });

    test('the detail line carries the last success and the waiting count', () {
      expect(syncDetailLine(view(SyncPhase.idle), now), 'Last synced 5m ago');
      expect(
        syncDetailLine(view(SyncPhase.idle, pending: 1), now),
        'Last synced 5m ago · 1 change waiting',
      );
      expect(
        syncDetailLine(
          const SyncStatusView(phase: SyncPhase.idle, pendingCount: 2),
          now,
        ),
        'Not synced yet · 2 changes waiting',
      );
    });

    test('a rejection is named and counted, singular and plural', () {
      expect(syncProblemHeadline(1), '1 change was not accepted');
      expect(syncProblemHeadline(4), '4 changes were not accepted');
      expect(kSyncProblemNote, contains('nothing was lost'));
    });

    test('relative time reads the way the rest of the app does', () {
      expect(
        syncAgoPhrase(now.subtract(const Duration(seconds: 5)), now),
        'just now',
      );
      expect(
        syncAgoPhrase(now.subtract(const Duration(minutes: 42)), now),
        '42m ago',
      );
      expect(
        syncAgoPhrase(now.subtract(const Duration(hours: 5)), now),
        '5h ago',
      );
      expect(
        syncAgoPhrase(now.subtract(const Duration(days: 9)), now),
        '9d ago',
      );
      // A clock that went backwards is not "eleven years ago".
      expect(syncAgoPhrase(now.add(const Duration(hours: 1)), now), 'just now');

      expect(syncDelayPhrase(null, now), 'shortly');
      expect(syncDelayPhrase(now, now), 'in a moment');
      expect(
        syncDelayPhrase(now.add(const Duration(seconds: 24)), now),
        'in 24s',
      );
      expect(
        syncDelayPhrase(now.add(const Duration(minutes: 16)), now),
        'in 16m',
      );
      expect(syncDelayPhrase(now.add(const Duration(hours: 2)), now), 'in 2h');
    });
  });

  group('the section', () {
    late _FakeSource source;

    tearDown(() => source.close());

    Widget host({SyncStatusSource? attached}) => ProviderScope(
      overrides: [
        if (attached != null)
          syncStatusSourceProvider.overrideWithValue(attached),
      ],
      child: MaterialApp(
        theme: appTheme(palette: AppPalette.light),
        home: Scaffold(body: ListView(children: const [SyncStatusSection()])),
      ),
    );

    SyncStatusView healthy() => SyncStatusView(
      phase: SyncPhase.idle,
      lastSuccessAt: DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      ),
    );

    screenTest('nothing at all when no scheduler is attached', (tester) async {
      source = _FakeSource(healthy());
      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byKey(const ValueKey('syncStatusSection')), findsNothing);
      expect(find.text('SYNC'), findsNothing);
      expect(source.refreshes, 0);
    });

    screenTest('healthy is one calm line and no alarm anywhere', (
      tester,
    ) async {
      source = _FakeSource(healthy());
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      expect(find.text('SYNC'), findsOneWidget);
      expect(find.text('Up to date.'), findsOneWidget);
      expect(find.textContaining('Last synced 5m ago'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('syncAttentionRow')),
        findsNothing,
        reason: 'nothing is wrong, so nothing asks',
      );
      expect(find.byIcon(Icons.report_outlined), findsNothing);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'a healthy sync produces no event',
      );
      expect(source.refreshes, 1, reason: 'one read when the screen opens');
    });

    screenTest('a run in flight disables the button rather than hiding it', (
      tester,
    ) async {
      source = _FakeSource(const SyncStatusView(phase: SyncPhase.syncing));
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      expect(find.text('Syncing now.'), findsOneWidget);
      expect(find.text('Working…'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('syncNowButton')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(source.syncNowCalls, 0, reason: 'disabled means disabled');
    });

    screenTest('an unreachable service says when it will try again', (
      tester,
    ) async {
      source = _FakeSource(
        SyncStatusView(
          phase: SyncPhase.retrying,
          // Two and a half, so the seconds that pass while the widget builds
          // cannot round the sentence down to "in 1m".
          nextRetryAt: DateTime.now().toUtc().add(
            const Duration(minutes: 2, seconds: 30),
          ),
        ),
      );
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      expect(find.textContaining('could not be reached'), findsOneWidget);
      expect(find.textContaining('in 2m'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('syncAttentionRow')),
        findsNothing,
        reason: 'a failure the user cannot act on is not an alert',
      );
    });

    screenTest('a refused change is the one row that speaks up', (
      tester,
    ) async {
      source = _FakeSource(
        SyncStatusView(
          phase: SyncPhase.attention,
          problemCount: 2,
          lastSuccessAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      expect(find.byKey(const ValueKey('syncAttentionRow')), findsOneWidget);
      expect(find.text('2 changes were not accepted'), findsOneWidget);
      expect(find.text(kSyncProblemNote), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    screenTest('an unconfigured device is told, not warned', (tester) async {
      source = _FakeSource(
        const SyncStatusView(phase: SyncPhase.neverConfigured),
      );
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      expect(find.text('Sync is not set up on this device.'), findsOneWidget);
      expect(find.text('Nothing to sync with yet'), findsOneWidget);
      expect(find.text('Not synced yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('syncAttentionRow')), findsNothing);
    });

    screenTest('Sync now asks, once', (tester) async {
      source = _FakeSource(healthy());
      await tester.pumpWidget(host(attached: source));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('syncNowButton')));
      await tester.pump();

      expect(source.syncNowCalls, 1);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'asking for a sync is not an announcement either',
      );
    });

    screenTest('a new state redraws without a rebuild of the screen', (
      tester,
    ) async {
      source = _FakeSource(healthy());
      await tester.pumpWidget(host(attached: source));
      await tester.pump();
      expect(find.text('Up to date.'), findsOneWidget);

      source.emit(const SyncStatusView(phase: SyncPhase.syncing));
      await tester.pump();
      await tester.pump();
      expect(find.text('Syncing now.'), findsOneWidget);

      source.emit(
        SyncStatusView(
          phase: SyncPhase.attention,
          problemCount: 1,
          lastSuccessAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('1 change was not accepted'), findsOneWidget);
    });
  });

  test('nothing outside Settings knows about sync status', () {
    // The surface is one screen. This is the guard that keeps it one screen:
    // a reader, a shelf or a browser that imported the section would put sync
    // where V2_SYNC.md §3 says it must never appear.
    const allowed = <String>{
      'lib/library_ui/sync_status_section.dart',
      'lib/features/settings_screen.dart',
    };
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (allowed.any(path.endsWith)) continue;
      final text = file.readAsStringSync();
      if (text.contains('sync_status_section.dart') ||
          text.contains('SyncStatusSection') ||
          text.contains('syncStatusSourceProvider')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'sync state belongs in Settings and nowhere else — not the library, '
          'not the browser, and above all not the reader',
    );
  });
}
