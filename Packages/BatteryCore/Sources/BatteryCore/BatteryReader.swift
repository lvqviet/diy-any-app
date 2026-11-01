import Foundation
import IOKit

/// Snapshot of the battery as reported by the AppleSmartBattery driver.
public struct BatteryReading: Codable, Equatable, Sendable {
    /// State of charge in percent, as shown in the macOS menu bar.
    public var percent: Int
    /// Charger physically connected (hardware view, unaffected by software adapter cut).
    public var adapterConnected: Bool
    /// macOS reports the system is drawing external power.
    public var externalPowerActive: Bool
    /// Battery is currently gaining charge.
    public var isCharging: Bool
    /// Battery current in mA; positive while charging, negative while discharging.
    public var amperage: Int
    public var cycleCount: Int
    /// Full-charge capacity relative to design capacity, in percent.
    public var health: Int

    public init(percent: Int, adapterConnected: Bool, externalPowerActive: Bool, isCharging: Bool,
                amperage: Int, cycleCount: Int, health: Int) {
        self.percent = percent
        self.adapterConnected = adapterConnected
        self.externalPowerActive = externalPowerActive
        self.isCharging = isCharging
        self.amperage = amperage
        self.cycleCount = cycleCount
        self.health = health
    }
}

public enum BatteryReader {
    public enum ReadError: Error { case serviceNotFound, propertiesUnavailable }

    public static func read() throws -> BatteryReading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { throw ReadError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            throw ReadError.propertiesUnavailable
        }

        func int(_ key: String) -> Int { (dict[key] as? NSNumber)?.intValue ?? 0 }
        func bool(_ key: String) -> Bool { (dict[key] as? NSNumber)?.boolValue ?? false }

        let design = int("DesignCapacity")
        let rawMax = int("AppleRawMaxCapacity")
        let raw = dict["AppleRawExternalConnected"] != nil ? bool("AppleRawExternalConnected") : bool("ExternalConnected")
        // Amperage is reported as an unsigned 64-bit value; reinterpret as signed.
        let amperage = Int(Int64(bitPattern: (dict["Amperage"] as? NSNumber)?.uint64Value ?? 0))

        return BatteryReading(
            percent: max(0, min(100, int("CurrentCapacity"))),
            adapterConnected: raw,
            externalPowerActive: bool("ExternalConnected"),
            isCharging: bool("IsCharging"),
            amperage: amperage,
            cycleCount: int("CycleCount"),
            health: design > 0 ? Int((Double(rawMax) / Double(design) * 100).rounded()) : 0
        )
    }
}
