import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/device_storage.dart';

/// Disk-space policy: preflight floor, rolling per-entry check, the
/// both-copies replacement check, distinct error class, and the platform
/// channel itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceStorage channel', () {
    const channel = MethodChannel('webread/device_storage');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('freeBytes returns the platform value', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'freeBytes');
            return 1234567890;
          });
      expect(await DeviceStorage().freeBytes(), 1234567890);
    });

    test('freeBytes degrades to null on channel errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'nope');
          });
      expect(await DeviceStorage().freeBytes(), isNull);
    });

    test('excludeFromBackup passes the path and returns the result', () async {
      String? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'excludeFromBackup');
            received = (call.arguments as Map)['path'] as String;
            return true;
          });
      expect(await DeviceStorage().excludeFromBackup('/x/webread'), isTrue);
      expect(received, '/x/webread');
    });

    test('excludeFromBackup degrades to false when unsupported', () async {
      // No handler installed: MissingPluginException path (Android today).
      expect(await DeviceStorage().excludeFromBackup('/x'), isFalse);
    });
  });

  // The V1 multi-entry run's rolling disk check retired with
  // `lib/save/save_run.dart` (roadmap §10, after E2 + E3): a V2 queue task is
  // one capture, so there is no between-entries loop left to police. The
  // engine's own per-capture behaviour is pinned in its ported tests.
}
