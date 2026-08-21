import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // webread/device_storage: free-space, device capacity, backup exclusion.
    // Kept small on purpose — see lib/core/device_storage.dart (D30).
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "webread.device_storage")!
    let channel = FlutterMethodChannel(
      name: "webread/device_storage",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "freeBytes":
        do {
          let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          if let capacity = values.volumeAvailableCapacityForImportantUsage {
            result(NSNumber(value: capacity))
          } else {
            result(nil)
          }
        } catch {
          result(nil)
        }
      // Total + available for the Library's device-usage indicator. Returns
      // a map so the two values are read in one call and therefore describe
      // the same moment — a percentage assembled from two round-trips can
      // straddle a write and land outside 0...1.
      case "capacity":
        do {
          let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
          ])
          var payload: [String: Any] = [:]
          if let free = values.volumeAvailableCapacityForImportantUsage {
            payload["free"] = NSNumber(value: free)
          }
          if let total = values.volumeTotalCapacity {
            payload["total"] = NSNumber(value: total)
          }
          result(payload)
        } catch {
          result(nil)
        }
      case "excludeFromBackup":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(false)
          return
        }
        var url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
          result(false)
          return
        }
        do {
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    registerDiagnosticsChannel(engineBridge)
  }
}

/// `webread/diagnostics` — one read-only snapshot of what this device is
/// currently costing.
///
/// **Why this exists.** Validating that a save can keep running while somebody
/// reads means proving what it costs in memory, heat and battery *while the
/// operation is in a known phase*. Instruments can measure the process, but it
/// cannot say "this sample was taken during the scroll phase of Entry 3" —
/// only the app knows that. So the app takes the samples and labels them, and
/// Instruments corroborates the totals.
///
/// **Read-only, permission-free, and never wired to product behaviour.** Every
/// value here comes from a public API that needs no entitlement and no consent
/// prompt. Nothing in `lib/` may branch on any of it: this measures the app, it
/// does not steer it. The Dart side (`lib/core/runtime_diagnostics.dart`)
/// refuses to call it in a release build, which is what keeps
/// `isBatteryMonitoringEnabled` off for real users.
///
/// **Memory is `phys_footprint`**, the same number the iOS jetsam limit is
/// judged against and the one Xcode's memory gauge shows — deliberately not
/// `resident_size`, which counts shared pages this app is not charged for.
/// It covers **this process only**: `WKWebView` renders in a separate
/// `com.apple.WebKit.WebContent` process, so the web renderer's own cost has to
/// come from Instruments' Activity Monitor instead. Both halves are needed and
/// neither is a substitute for the other.
func registerDiagnosticsChannel(_ engineBridge: FlutterImplicitEngineBridge) {
  guard
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "webread.diagnostics")
  else { return }

  let channel = FlutterMethodChannel(
    name: "webread/diagnostics",
    binaryMessenger: registrar.messenger()
  )

  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "snapshot":
      // Battery monitoring is a global flag with a cost, so it is turned on
      // by the first diagnostic read rather than at launch. In release the
      // Dart side never gets here, so it is never turned on at all.
      if !UIDevice.current.isBatteryMonitoringEnabled {
        UIDevice.current.isBatteryMonitoringEnabled = true
      }

      var payload: [String: Any] = [:]

      payload["thermalState"] = thermalStateName(ProcessInfo.processInfo.thermalState)
      payload["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled

      // -1 means "the platform would not say" and must stay distinguishable
      // from a flat battery. Reported as-is; the Dart side maps it to null.
      payload["batteryLevel"] = Double(UIDevice.current.batteryLevel)
      payload["batteryState"] = batteryStateName(UIDevice.current.batteryState)

      if let footprint = physFootprintBytes() {
        payload["memoryFootprintBytes"] = NSNumber(value: footprint)
      }
      payload["availableMemoryBytes"] = NSNumber(value: os_proc_available_memory())

      result(payload)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
  switch state {
  case .nominal: return "nominal"
  case .fair: return "fair"
  case .serious: return "serious"
  case .critical: return "critical"
  @unknown default: return "unknown"
  }
}

private func batteryStateName(_ state: UIDevice.BatteryState) -> String {
  switch state {
  case .unplugged: return "unplugged"
  case .charging: return "charging"
  case .full: return "full"
  case .unknown: return "unknown"
  @unknown default: return "unknown"
  }
}

/// This process's physical footprint in bytes, or nil when the kernel declined.
private func physFootprintBytes() -> UInt64? {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
  )
  let kerr = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  guard kerr == KERN_SUCCESS else { return nil }
  return info.phys_footprint
}
