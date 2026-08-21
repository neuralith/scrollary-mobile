import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/core/device_capacity_provider.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/features/storage_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/status_style.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// The Library's storage entry: one glyph, one number, and no filesystem walk
/// behind it.
class _FakeDeviceStorage implements DeviceStorage {
  _FakeDeviceStorage(this.capacityValue);

  DeviceCapacity capacityValue;
  int calls = 0;

  @override
  Future<DeviceCapacity> capacity() async {
    calls++;
    return capacityValue;
  }

  @override
  Future<int?> freeBytes() async => capacityValue.freeBytes;

  @override
  Future<bool> excludeFromBackup(String absolutePath) async => false;
}

const _gb = 1024 * 1024 * 1024;

void main() {
  group('percentage', () {
    test('is device usage: (total - free) / total', () {
      const c = DeviceCapacity(totalBytes: 100 * _gb, freeBytes: 28 * _gb);
      expect(c.usedPercent, 72);
      expect(c.usedFraction, closeTo(0.72, 0.0001));
    });

    test('is unknown when either half is missing', () {
      expect(const DeviceCapacity(totalBytes: 100).usedPercent, isNull);
      expect(const DeviceCapacity(freeBytes: 100).usedPercent, isNull);
      expect(DeviceCapacity.unknown.usedPercent, isNull);
    });

    test('never invents a value from a nonsense reading', () {
      // Zero-capacity and free-exceeds-total are both "the platform did not
      // really answer", not 0% and not 100%.
      expect(
        const DeviceCapacity(totalBytes: 0, freeBytes: 0).usedPercent,
        isNull,
      );
      expect(
        const DeviceCapacity(totalBytes: 10, freeBytes: 20).usedPercent,
        isNull,
      );
    });

    test('a full disk is 100%, an empty one 0%', () {
      expect(
        const DeviceCapacity(totalBytes: 100, freeBytes: 0).usedPercent,
        100,
      );
      expect(
        const DeviceCapacity(totalBytes: 100, freeBytes: 100).usedPercent,
        0,
      );
    });
  });

  group('the Library indicator', () {
    late AppDatabase db;
    late Directory root;
    late FileStore store;
    late _FakeDeviceStorage device;
    String? pushed;
    SemanticsHandle? semantics;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_indicator');
      store = FileStore(root);
      device = _FakeDeviceStorage(
        const DeviceCapacity(totalBytes: 100 * _gb, freeBytes: 28 * _gb),
      );
      pushed = null;
    });
    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// The pill inside a header row of the same shape the Library uses, so
    /// the layout assertions mean something.
    Widget harness({double width = 320}) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Row(
                children: [
                  const Expanded(child: Text('Library')),
                  HeaderIconButton(
                    key: const ValueKey('sync'),
                    icon: Icons.sync,
                    tooltip: 'sync',
                    onPressed: () {},
                  ),
                  const StoragePill(),
                  HeaderIconButton(
                    key: const ValueKey('archived'),
                    icon: Icons.inventory_2,
                    tooltip: 'archived',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/storage',
            builder: (context, state) {
              pushed = state.uri.toString();
              return const Scaffold(body: Text('STORAGE SCREEN'));
            },
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          fileStoreProvider.overrideWithValue(store),
          deviceStorageProvider.overrideWithValue(device),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
    }

    Future<void> show(WidgetTester tester, {double width = 320}) async {
      semantics ??= tester.ensureSemantics();
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(width: width));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('72%').evaluate().isNotEmpty) return;
      }
    }

    /// Unmount inside the body so drift's disposal timers run, and release
    /// the semantics handle before the framework checks for leaks.
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      semantics?.dispose();
      semantics = null;
    }

    testWidgets('shows the device percentage and nothing else', (tester) async {
      await show(tester);

      expect(find.text('72%'), findsOneWidget);
      expect(find.byIcon(Icons.storage), findsOneWidget);
      // The things the header must NOT carry any more.
      expect(find.textContaining('free'), findsNothing);
      expect(find.textContaining('MB'), findsNothing);
      expect(find.textContaining('GB'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await drain(tester);
    });

    testWidgets('fits at 320pt without pushing the actions around', (
      tester,
    ) async {
      await show(tester);

      final pill = tester.getRect(find.byType(StoragePill));
      expect(pill.width, StoragePill.width);
      expect(pill.width, lessThanOrEqualTo(60));

      // The buttons on either side keep their places, and nothing overflows.
      final sync = tester.getRect(find.byKey(const ValueKey('sync')));
      final archived = tester.getRect(find.byKey(const ValueKey('archived')));
      expect(sync.right, lessThanOrEqualTo(pill.left + 0.01));
      expect(archived.left, greaterThanOrEqualTo(pill.right - 0.01));
      expect(archived.right, lessThanOrEqualTo(320.01));
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('a device that will not report its size shows no number', (
      tester,
    ) async {
      device.capacityValue = DeviceCapacity.unknown;
      await show(tester);

      expect(find.byIcon(Icons.storage), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.bySemanticsLabel('Device storage — usage unavailable'),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('low space is a colour change, not extra words', (
      tester,
    ) async {
      device.capacityValue = const DeviceCapacity(
        totalBytes: 100 * _gb,
        freeBytes: 300 * 1024 * 1024,
      );
      await show(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('100%').evaluate().isNotEmpty) break;
      }

      // Asserted against the palette, not a literal: what matters is that
      // the critical level wears the critical ink and that it is *different*
      // from the quiet one — not which hex the design happens to use today.
      final icon = tester.widget<Icon>(find.byIcon(Icons.storage));
      expect(
        icon.color,
        storageLook(StorageLevel.critical, AppPalette.light).ink,
        reason: 'critical',
      );
      expect(
        icon.color,
        isNot(storageLook(StorageLevel.normal, AppPalette.light).ink),
        reason: 'critical must not look like healthy',
      );
      // Still just the glyph and the number.
      expect(find.textContaining('low'), findsNothing);
      expect(find.textContaining('Storage'), findsNothing);
      await drain(tester);
    });

    testWidgets('has a semantics label spelling the number out', (
      tester,
    ) async {
      await show(tester);
      // The level word is part of the label: a screen reader hears what the
      // colour says, since it cannot see it.
      expect(
        find.bySemanticsLabel('Device storage 72% used · Healthy'),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('tapping it opens Settings → Storage', (tester) async {
      await show(tester);

      await tester.tap(find.byType(StoragePill));
      await tester.pumpAndSettle();

      expect(pushed, '/storage');
      expect(find.text('STORAGE SCREEN'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('unrelated rebuilds do not re-read the device', (tester) async {
      await show(tester);
      expect(device.calls, 1);

      // Twenty frames of the header rebuilding for its own reasons.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        device.calls,
        1,
        reason: 'the reading is cached, not recomputed per rebuild',
      );
      await drain(tester);
    });

    testWidgets('a refresh after cleanup or save re-reads it', (tester) async {
      await show(tester);
      expect(device.calls, 1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StoragePill)),
      );
      device.capacityValue = const DeviceCapacity(
        totalBytes: 100 * _gb,
        freeBytes: 55 * _gb,
      );

      // Throttled by default: an entry-by-entry save must not fire a
      // platform call per entry.
      await container.read(deviceCapacityProvider.notifier).refresh();
      await tester.pump();
      expect(device.calls, 1);

      // Forced: the disk genuinely changed.
      await container
          .read(deviceCapacityProvider.notifier)
          .refresh(force: true);
      await tester.pump();
      expect(device.calls, 2);
      expect(find.text('45%'), findsOneWidget);
      await drain(tester);
    });
  });
}
