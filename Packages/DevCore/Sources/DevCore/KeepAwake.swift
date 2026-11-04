import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Keeps the display (and so the Mac) from sleeping while idle, like `caffeinate -d`.
/// Released on deinit. macOS also releases it when the process exits or crashes.
/// Closing the lid, choosing Sleep, or a critically low battery still sleeps the Mac.
public final class DisplaySleepAssertion {
    public let id: IOPMAssertionID

    public init?(reason: String) {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &id)
        guard result == kIOReturnSuccess else { return nil }
        self.id = id
    }

    deinit { IOPMAssertionRelease(id) }
}

/// Battery state from IOKit power sources (public API, no helper needed).
public struct PowerState: Equatable, Sendable {
    /// nil on Macs without a battery.
    public var batteryPercent: Int?
    public var onBattery: Bool

    public init(batteryPercent: Int?, onBattery: Bool) {
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
    }

    public static func current() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerState(batteryPercent: nil, onBattery: false)
        }
        let onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?)
            == kIOPSBatteryPowerValue
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return PowerState(batteryPercent: current * 100 / max, onBattery: onBattery)
        }
        return PowerState(batteryPercent: nil, onBattery: onBattery)
    }
}

/// When Keep Awake must not run, so a forgotten session cannot drain or overheat the Mac.
public enum KeepAwakePolicy {
    /// On battery at or below this percent, Keep Awake stops and cannot be started.
    public static let lowBatteryPercent = 20

    /// nil when Keep Awake may run, otherwise the reason it may not.
    public static func blockReason(power: PowerState, thermal: ProcessInfo.ThermalState) -> String? {
        if thermal == .critical { return "Mac is too hot" }
        if power.onBattery, let percent = power.batteryPercent, percent <= lowBatteryPercent {
            return "Battery at \(percent)%"
        }
        return nil
    }
}
