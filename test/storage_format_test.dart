import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/device_capacity_provider.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/features/storage_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// How Storage words a size.
///
/// The screen quotes two different kinds of number — what this app is holding,
/// and what the device has — and they do not deserve the same precision. What
/// neither of them deserves is `177542.7 MB`.
const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

class _FakeDeviceStorage implements DeviceStorage {
  _FakeDeviceStorage(this.capacityValue);

  DeviceCapacity capacityValue;

  @override
  Future<DeviceCapacity> capacity() async => capacityValue;

  @override
  Future<int?> freeBytes() async => capacityValue.freeBytes;

  @override
  Future<bool> excludeFromBackup(String absolutePath) async => false;
}

void main() {
  group('what the app holds', () {
    test('stays in MB below 1000 MB', () {
      expect(formatStorageBytes(0), '0 B');
      expect(formatStorageBytes(512), '512 B');
      expect(formatStorageBytes(64 * 1024), '64 KB');
      expect(formatStorageBytes(36 * _mb), '36.0 MB');
      expect(formatStorageBytes(940 * _mb), '940.0 MB');
    });

    test('is still MB just below the switch', () {
      expect(formatStorageBytes(999 * _mb), '999.0 MB');
    });

    test('switches to GB at 1000 MB', () {
      expect(formatStorageBytes(1000 * _mb), '1 GB');
      // …and never prints the four-digit MB figure that only *rounds* to
      // 1000, which would read as a unit the line above just left.
      expect(formatStorageBytes(999 * _mb + 1000 * 1024), '1 GB');
    });

    test('a larger total is GB, to a tenth', () {
      expect(formatStorageBytes(1536 * _mb), '1.5 GB');
      expect(formatStorageBytes(12 * _gb + 400 * _mb), '12.4 GB');
      expect(formatStorageBytes(240 * _gb), '240 GB');
    });

    test('a whole number of GB carries no trailing zero', () {
      expect(formatStorageBytes(2 * _gb), '2 GB');
      expect(formatStorageBytes(2 * _gb), isNot(contains('.0')));
      expect(formatStorageBytes(64 * _gb), '64 GB');
    });
  });

  group('what the device has', () {
    test('a capacity is GB, never a five-figure MB value', () {
      // The reading that started this: 186_164_000_000-odd bytes free, which
      // the old formatter printed as `177542.7 MB`.
      expect(formatDeviceBytes(173 * _gb), '173 GB');
      expect(formatDeviceBytes(256 * _gb), '256 GB');
      expect(formatDeviceBytes(512 * _gb), isNot(contains('MB')));
    });

    test('device scale is whole gigabytes', () {
      expect(formatDeviceBytes(173 * _gb + 400 * _mb), '173 GB');
      expect(formatDeviceBytes(64 * _gb), '64 GB');
      expect(formatDeviceBytes(64 * _gb), isNot(contains('.')));
    });

    test('but a tenth survives below 10 GB, where it decides a save', () {
      expect(formatDeviceBytes(1024 * _mb + 400 * _mb), '1.4 GB');
      expect(formatDeviceBytes(9 * _gb + 512 * _mb), '9.5 GB');
      expect(formatDeviceBytes(2 * _gb), '2 GB');
    });

    test('under a gigabyte it says so rather than rounding to 0 GB', () {
      expect(formatDeviceBytes(300 * _mb), '300.0 MB');
      expect(formatDeviceBytes(0), '0 B');
    });
  });

  group('the Storage screen', () {
    late AppDatabase db;
    late Directory root;
    late _FakeDeviceStorage device;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_storage_format');
      device = _FakeDeviceStorage(
        const DeviceCapacity(totalBytes: 250 * _gb, freeBytes: 173 * _gb),
      );
    });
    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<void> seed(int bytes) async {
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 's1',
          title: 'A collection',
          sourceUrl: 'https://x.example/guide/s1',
          host: 'x.example',
          collectionKey: '/guide/s1',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 's1-c1',
          collectionId: 's1',
          title: 'Entry 1',
          sourceUrl: 'https://x.example/guide/s1/1',
          urlKey: 'https://x.example/guide/s1/1',
          artifactFormat: 'imageSequence',
          saveStatus: 'complete',
          contentPath: 'library/s1/entries/s1-c1',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 3,
          storedAssetCount: 3,
          entryOrder: 1,
          byteSize: bytes,
          entryNumber: 1,
          sourceMarker: 'Entry 1',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }

    Future<void> show(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            fileStoreProvider.overrideWithValue(FileStore(root)),
            deviceStorageProvider.overrideWithValue(device),
          ],
          child: const MaterialApp(home: StorageScreen()),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('WEB READER USES').evaluate().isNotEmpty &&
            find.textContaining('%').evaluate().isNotEmpty) {
          return;
        }
      }
    }

    /// Unmount inside the body so drift's disposal timers run.
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('quotes a gigabyte library in GB, the device in whole GB', (
      tester,
    ) async {
      await seed(1536 * _mb);
      await show(tester);

      expect(find.text('1.5 GB'), findsWidgets, reason: 'web reader uses');
      expect(find.text('173 GB'), findsOneWidget, reason: 'available tile');
      expect(
        find.textContaining('173 GB free of 250 GB'),
        findsOneWidget,
        reason: 'the device meter line',
      );
      expect(find.textContaining('MB'), findsNothing);
      await drain(tester);
    });

    testWidgets('a megabyte-sized library is left in MB', (tester) async {
      await seed(240 * _mb);
      await show(tester);

      expect(find.text('240.0 MB'), findsWidgets);
      expect(find.text('173 GB'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('an empty library and no temporary files still read', (
      tester,
    ) async {
      await show(tester);

      expect(find.text('0 B'), findsWidgets);
      expect(find.text('173 GB'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a device that will not report its size shows no figure', (
      tester,
    ) async {
      device.capacityValue = DeviceCapacity.unknown;
      await seed(240 * _mb);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            fileStoreProvider.overrideWithValue(FileStore(root)),
            deviceStorageProvider.overrideWithValue(device),
          ],
          child: const MaterialApp(home: StorageScreen()),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('240.0 MB').evaluate().isNotEmpty) break;
      }

      expect(
        find.text('—'),
        findsNWidgets(2),
        reason: 'the meter percentage and the available tile',
      );
      expect(find.text('173 GB'), findsNothing);
      expect(find.textContaining("won't report its capacity"), findsOneWidget);
      expect(find.textContaining('free of'), findsNothing);
      await drain(tester);
    });
  });
}
