import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One labelled reading of what the device is currently costing.
///
/// Every field may be null: the platform is allowed to not know, and "unknown"
/// must stay distinguishable from zero — the same rule `DeviceCapacity`
/// already follows.
class RuntimeSnapshot {
  const RuntimeSnapshot({
    this.thermalState,
    this.lowPowerMode,
    this.batteryLevel,
    this.batteryState,
    this.memoryFootprintBytes,
    this.availableMemoryBytes,
  });

  static const RuntimeSnapshot unknown = RuntimeSnapshot();

  /// `nominal` · `fair` · `serious` · `critical`.
  final String? thermalState;
  final bool? lowPowerMode;

  /// 0..1, or null when the platform declined (it reports -1 for that).
  final double? batteryLevel;

  /// `unplugged` · `charging` · `full` · `unknown`. A battery comparison taken
  /// while this is `charging` or `full` measures nothing.
  final String? batteryState;

  /// This process's physical footprint — what the jetsam limit is judged
  /// against. **Does not include the web renderer**, which is a separate
  /// process; that has to come from Instruments' Activity Monitor.
  final int? memoryFootprintBytes;
  final int? availableMemoryBytes;

  bool get isKnown => memoryFootprintBytes != null || thermalState != null;

  String get line =>
      'mem=${memoryFootprintBytes == null ? '?' : (memoryFootprintBytes! / 1048576).toStringAsFixed(1)}MB '
      'avail=${availableMemoryBytes == null ? '?' : (availableMemoryBytes! / 1048576).toStringAsFixed(0)}MB '
      'thermal=${thermalState ?? '?'} '
      'battery=${batteryLevel == null || batteryLevel! < 0 ? '?' : (batteryLevel! * 100).toStringAsFixed(0)}% '
      '(${batteryState ?? '?'})'
      '${lowPowerMode == true ? ' lowPower' : ''}';
}

/// Memory, thermal and battery readings for validation runs.
///
/// **Diagnostics only, and never in a release build.** Nothing in `lib/` may
/// branch on any of these values — this measures the app, it does not steer it.
/// [snapshot] returns [RuntimeSnapshot.unknown] in release without touching the
/// platform, which is what keeps iOS battery monitoring switched off for real
/// users; the native handler is documented in `ios/Runner/Diagnostics.swift`.
///
/// It exists because Instruments can measure the process but cannot say which
/// phase of which operation a sample belongs to. Only the app knows that, so
/// the app takes the labelled samples and Instruments corroborates the totals.
/// Android has no handler and fails soft to unknown.
class RuntimeDiagnostics {
  RuntimeDiagnostics({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('webread/diagnostics');

  final MethodChannel _channel;

  Future<RuntimeSnapshot> snapshot() async {
    if (kReleaseMode) return RuntimeSnapshot.unknown;
    try {
      final v = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      if (v == null) return RuntimeSnapshot.unknown;
      final level = v['batteryLevel'];
      final levelValue = level is num ? level.toDouble() : null;
      return RuntimeSnapshot(
        thermalState: v['thermalState'] as String?,
        lowPowerMode: v['lowPowerMode'] as bool?,
        // The platform reports -1 for "would not say"; that is not a battery
        // level and must not be averaged with real ones.
        batteryLevel: levelValue == null || levelValue < 0 ? null : levelValue,
        batteryState: v['batteryState'] as String?,
        memoryFootprintBytes: (v['memoryFootprintBytes'] as num?)?.toInt(),
        availableMemoryBytes: (v['availableMemoryBytes'] as num?)?.toInt(),
      );
    } catch (_) {
      return RuntimeSnapshot.unknown;
    }
  }
}
