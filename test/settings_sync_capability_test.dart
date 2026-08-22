/// `Settings → Sync` when the device may not use the service.
///
/// The property under test is a negative one, and it is the whole point of the
/// design: a Free device is not a broken device. It gets one locked door and
/// **no status furniture at all** — no state sentence, no pending count, no
/// *Sync now*, no attention row, no warning colour and no event of any kind.
/// A count of changes waiting for a service the user cannot reach would read
/// as a fault they are supposed to fix, and there is nothing to fix: the
/// library is simply staying where it is (docs/DECISIONS.md V2-D7).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/favicon_service.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/features/foreground_gate_sheet.dart';
import 'package:web_reader/features/settings_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/library_ui/sync_status_section.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/sync/status.dart';
import 'package:web_reader/ui/theme.dart';

/// The closing note's three states, quoted so a rewrite of any of them is a
/// deliberate act rather than a passing edit. The first two must stay exactly
/// as they shipped.
const String _onDeviceNote =
    'Everything is stored on this device. There is no account, no sync and '
    'no background network activity — saves and update checks only run when '
    'you start them.';

const String _freeNote =
    'Saves and update checks only run when you start them. Cloud sync is a '
    'Pro capability, so nothing about your library leaves this device; '
    'downloaded pages, browsing history and saved rules stay here either way.';

/// A stand-in scheduler. Its whole job here is to exist: attaching one is what
/// makes the Sync section a question at all.
class _FakeSource implements SyncStatusSource {
  _FakeSource(this._status);

  final SyncStatusView _status;
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

  Future<void> close() => _views.close();
}

void main() {
  late AppDatabase db;
  late Directory root;
  late _FakeSource source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('scrollary_settings_sync');
    // Three changes waiting and a healthy service: everything the live section
    // would have to say, so a Free device staying silent is a real result.
    source = _FakeSource(
      SyncStatusView(
        phase: SyncPhase.idle,
        pendingCount: 3,
        lastSuccessAt: DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        ),
      ),
    );
  });

  tearDown(() async {
    await source.close();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Settings, with the capability holder and the scheduler seam both under
  /// the test's control.
  Widget host({
    required ForegroundMultitasking capability,
    bool attached = true,
  }) {
    final store = FileStore(root);
    final browser = BrowserController();
    addTearDown(browser.dispose);
    final run = SaveRunController(browser: browser, db: db, fileStore: store);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        saveRunProvider.overrideWithValue(run),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        taskQueueProvider.overrideWithValue(
          TaskQueueController(
            db: db,
            browser: browser,
            saveRun: run,
            checker: UpdateChecker(browser: browser, db: db),
          ),
        ),
        faviconServiceProvider.overrideWithValue(
          FaviconService(db: db, allowNetwork: false),
        ),
        foregroundMultitaskingProvider.overrideWithValue(capability),
        if (attached) syncStatusSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(theme: appTheme(), home: const SettingsScreen()),
    );
  }

  ForegroundMultitasking free() {
    final c = ForegroundMultitasking();
    addTearDown(c.dispose);
    return c;
  }

  ForegroundMultitasking pro() {
    final c = free()..override = EntitlementOverride.forcePro;
    expect(c.cloudSyncAvailable, isTrue, reason: 'the fixture must be Pro');
    return c;
  }

  /// `testWidgets` at a viewport tall enough to hold the whole of Settings, so
  /// a finder that misses means the widget is absent rather than below the
  /// fold — which is exactly the distinction every test here turns on.
  void settingsTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(430, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  group('a Free device with a scheduler attached', () {
    settingsTest('gets one locked door and nothing else', (tester) async {
      await tester.pumpWidget(host(capability: free()));
      await tester.pump();

      expect(find.text('SYNC'), findsOneWidget);
      expect(find.byKey(const ValueKey('settingsCloudSync')), findsOneWidget);
      expect(find.text(kCloudSyncLabel), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(
        find.textContaining('A Pro capability. Without it your library'),
        findsOneWidget,
      );

      // None of the live section, and none of its furniture.
      for (final key in const [
        'syncStatusSection',
        'syncStateSentence',
        'syncDetailLine',
        'syncAttentionRow',
        'syncNowButton',
      ]) {
        expect(
          find.byKey(ValueKey(key)),
          findsNothing,
          reason: '$key describes work that is not going to happen',
        );
      }
      expect(
        find.textContaining('3'),
        findsNothing,
        reason: 'a pending count would read as a fault to fix',
      );
      expect(find.text('Sync now'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        source.refreshes,
        0,
        reason: 'the section never mounts, so nothing is even read',
      );
      expect(source.syncNowCalls, 0);
    });

    settingsTest('the closing note stops claiming sync happens', (
      tester,
    ) async {
      await tester.pumpWidget(host(capability: free()));
      await tester.pump();

      expect(find.text(_freeNote), findsOneWidget);
      expect(
        find.text(kSyncSettingsNote),
        findsNothing,
        reason: 'it promises synchronisation that will not happen',
      );
      expect(find.text(_onDeviceNote), findsNothing);
    });

    settingsTest('the door opens the one sheet, on its cloud face', (
      tester,
    ) async {
      await tester.pumpWidget(host(capability: free()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settingsCloudSync')));
      await tester.pumpAndSettle();

      // One sheet, and it came up wearing the right face. Scoped to the sheet
      // because Settings itself is still behind it, still naming the other
      // capability in its own row.
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text(kCloudSyncLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text(kKeepWorkingLabel)),
        findsNothing,
        reason: 'the sheet is shared; the copy is not',
      );
      expect(find.text('A Pro capability'), findsOneWidget);
      expect(
        find.textContaining('travel between your devices'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Downloaded pages never leave this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('stays fully usable without it'),
        findsOneWidget,
      );

      // The copy ceiling: nothing is for sale and nothing pretends to be.
      expect(
        find.textContaining('Pro is not on sale yet'),
        findsOneWidget,
        reason: 'the upgrade seat is reused verbatim, purchase copy and all',
      );
      expect(find.byKey(const ValueKey('proInfoClose')), findsOneWidget);
    });
  });

  group('a Pro device with a scheduler attached', () {
    settingsTest('gets the live section, exactly as it always was', (
      tester,
    ) async {
      await tester.pumpWidget(host(capability: pro()));
      await tester.pump();

      expect(find.byKey(const ValueKey('syncStatusSection')), findsOneWidget);
      expect(find.text('SYNC'), findsOneWidget);
      expect(find.text('Changes are waiting to sync.'), findsOneWidget);
      expect(find.byKey(const ValueKey('syncNowButton')), findsOneWidget);
      expect(source.refreshes, 1, reason: 'one read when the screen opens');

      expect(find.byKey(const ValueKey('settingsCloudSync')), findsNothing);
      expect(find.text(kSyncSettingsNote), findsOneWidget);
      expect(find.text(_freeNote), findsNothing);
    });
  });

  group('no scheduler attached', () {
    settingsTest('says nothing about sync, entitled or not', (tester) async {
      for (final capability in [free(), pro()]) {
        await tester.pumpWidget(host(capability: capability, attached: false));
        await tester.pump();

        expect(find.text('SYNC'), findsNothing);
        expect(find.byKey(const ValueKey('settingsCloudSync')), findsNothing);
        expect(find.byKey(const ValueKey('syncStatusSection')), findsNothing);
        expect(find.text(_onDeviceNote), findsOneWidget);
        expect(find.text(_freeNote), findsNothing);
        expect(find.text(kSyncSettingsNote), findsNothing);
      }
    });
  });
}
