import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_storage.dart';

/// How often a device-capacity reading may be re-taken.
///
/// Free space moves slowly relative to how often a screen rebuilds, and a
/// platform channel round-trip per rebuild is exactly the cost this provider
/// exists to avoid. Explicit refreshes after a save or a cleanup can
/// override it — those are the moments the number actually changed.
const Duration kCapacityRefreshInterval = Duration(minutes: 2);

/// Injectable so widget tests can supply a capacity without a platform
/// channel; overridden wholesale in `main()` only if that ever becomes
/// necessary.
final deviceStorageProvider = Provider<DeviceStorage>((ref) => DeviceStorage());

/// The device's fullness, read at most once per [kCapacityRefreshInterval].
///
/// Deliberately narrow: **one** platform call and nothing else. The Storage
/// screen (Settings → Storage) reads it, and the app root refreshes it after a
/// save or a cleanup; nothing that watches it can pull in a directory
/// traversal — which is what the previous indicator did. The Library no
/// longer shows device storage at all (V2-D43 follow-up).
final deviceCapacityProvider =
    AsyncNotifierProvider<DeviceCapacityController, DeviceCapacity>(
      DeviceCapacityController.new,
    );

class DeviceCapacityController extends AsyncNotifier<DeviceCapacity> {
  DateTime? _lastRead;

  @override
  Future<DeviceCapacity> build() => _read();

  Future<DeviceCapacity> _read() async {
    final capacity = await ref.read(deviceStorageProvider).capacity();
    _lastRead = DateTime.now();
    return capacity;
  }

  /// Re-read the device's capacity.
  ///
  /// Throttled unless [force]: a twenty-entry save would otherwise fire
  /// twenty channel calls for a number that moves by a rounding error each
  /// time. Callers that know the disk just changed materially — a cleanup, a
  /// finished save — pass [force].
  Future<void> refresh({bool force = false}) async {
    final last = _lastRead;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < kCapacityRefreshInterval) {
      return;
    }
    state = await AsyncValue.guard(_read);
  }
}
