import Foundation
import IOKit

/// Power adapter and power flow details.
public struct PowerReading: Codable, Equatable, Sendable {
    /// Adapter name, e.g. "96W USB-C Power Adapter". Nil when no adapter is attached.
    public var adapterName: String?
    /// Power the adapter negotiated with the Mac, in watts.
    public var adapterWatts: Int?
    /// Negotiated adapter voltage in mV.
    public var adapterVoltage: Int?
    /// Negotiated maximum adapter current in mA.
    public var adapterCurrent: Int?
    /// Power currently drawn from the adapter, in watts. Real-time from SMC `PDTR` when
    /// available, otherwise the driver's telemetry.
    public var inputPower: Double?
    /// Battery voltage in mV.
    public var batteryVoltage: Int?

    public init(adapterName: String? = nil, adapterWatts: Int? = nil, adapterVoltage: Int? = nil,
                adapterCurrent: Int? = nil, inputPower: Double? = nil, batteryVoltage: Int? = nil) {
        self.adapterName = adapterName
        self.adapterWatts = adapterWatts
        self.adapterVoltage = adapterVoltage
        self.adapterCurrent = adapterCurrent
        self.inputPower = inputPower
        self.batteryVoltage = batteryVoltage
    }
}

/// Snapshot of the battery as reported by the AppleSmartBattery driver.
public struct BatteryReading: Codable, Equatable, Sendable {
    /// State of charge in percent, as shown in the macOS menu bar.
    public var percent: Int
    /// Charger delivering power according to the battery driver. Turns false when the
    /// adapter is cut in software, even though the cable is still attached.
    public var adapterConnected: Bool
    /// Charger cable physically attached, from SMC `AC-W`. Stays true while the adapter is
    /// cut in software. Nil when the key is unavailable.
    public var chargerAttached: Bool?
    /// macOS reports the system is drawing external power.
    public var externalPowerActive: Bool
    /// Battery is currently gaining charge.
    public var isCharging: Bool
    /// Battery current in mA; positive while charging, negative while discharging.
    /// Real-time from SMC `B0AC` when available; the driver's value lags by about a minute.
    public var amperage: Int
    public var cycleCount: Int
    /// Full-charge capacity relative to design capacity, in percent (raw, not the value
    /// macOS shows as Maximum Capacity).
    public var health: Int
    /// Raw full-charge capacity in mAh.
    public var maxCapacity: Int?
    /// Design capacity in mAh.
    public var designCapacity: Int?
    public var power: PowerReading?

    public init(percent: Int, adapterConnected: Bool, chargerAttached: Bool? = nil, externalPowerActive: Bool,
                isCharging: Bool, amperage: Int, cycleCount: Int, health: Int,
                maxCapacity: Int? = nil, designCapacity: Int? = nil, power: PowerReading? = nil) {
        self.percent = percent
        self.adapterConnected = adapterConnected
        self.chargerAttached = chargerAttached
        self.externalPowerActive = externalPowerActive
        self.isCharging = isCharging
        self.amperage = amperage
        self.cycleCount = cycleCount
        self.health = health
        self.maxCapacity = maxCapacity
        self.designCapacity = designCapacity
        self.power = power
    }

    /// Battery power in watts; positive while charging, negative while discharging.
    public var batteryPower: Double? {
        guard let mV = power?.batteryVoltage else { return nil }
        return Double(mV) * Double(amperage) / 1_000_000
    }
}

public enum BatteryReader {
    public enum ReadError: Error { case serviceNotFound, propertiesUnavailable }

    /// Reads the battery driver, refined with real-time SMC values when `smc` is given.
    public static func read(smc: SMC? = nil) throws -> BatteryReading {
        var reading = try readDriver()
        if let smc {
            // AC-W (si8): positive while a charger is attached, -1 when unplugged.
            if let acw = try? smc.read("AC-W"), acw.count == 1 {
                reading.chargerAttached = Int8(bitPattern: acw[0]) > 0
            }
            // B0AC (si16, little-endian on Apple Silicon): battery current in mA.
            if let b0ac = try? smc.read("B0AC"), b0ac.count == 2 {
                reading.amperage = Int(Int16(bitPattern: UInt16(b0ac[0]) | UInt16(b0ac[1]) << 8))
            }
            var power = reading.power ?? PowerReading()
            // B0AV (ui16, little-endian): battery voltage in mV.
            if let b0av = try? smc.read("B0AV"), b0av.count == 2 {
                power.batteryVoltage = Int(UInt16(b0av[0]) | UInt16(b0av[1]) << 8)
            }
            // PDTR (flt, little-endian): DC-in power in watts.
            if let pdtr = try? smc.read("PDTR"), let watts = float(pdtr), watts.isFinite, watts >= 0 {
                power.inputPower = Double(watts)
            }
            reading.power = power
        }
        return reading
    }

    private static func float(_ bytes: [UInt8]) -> Float? {
        guard bytes.count == 4 else { return nil }
        return Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
    }

    private static func readDriver() throws -> BatteryReading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { throw ReadError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            throw ReadError.propertiesUnavailable
        }

        func int(_ key: String, in d: [String: Any] = dict) -> Int? { (d[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool { (dict[key] as? NSNumber)?.boolValue ?? false }

        let design = int("DesignCapacity") ?? 0
        let rawMax = int("AppleRawMaxCapacity") ?? 0
        let raw = dict["AppleRawExternalConnected"] != nil ? bool("AppleRawExternalConnected") : bool("ExternalConnected")
        // Amperage is reported as an unsigned 64-bit value; reinterpret as signed.
        let amperage = Int(Int64(bitPattern: (dict["Amperage"] as? NSNumber)?.uint64Value ?? 0))

        var power = PowerReading(batteryVoltage: int("Voltage"))
        if let adapter = dict["AdapterDetails"] as? [String: Any], let watts = int("Watts", in: adapter), watts > 0 {
            power.adapterName = adapter["Name"] as? String
            power.adapterWatts = watts
            power.adapterVoltage = int("AdapterVoltage", in: adapter)
            power.adapterCurrent = int("Current", in: adapter)
        }
        if let telemetry = dict["PowerTelemetryData"] as? [String: Any], let mW = int("SystemPowerIn", in: telemetry) {
            power.inputPower = Double(mW) / 1000
        }

        return BatteryReading(
            percent: max(0, min(100, int("CurrentCapacity") ?? 0)),
            adapterConnected: raw,
            externalPowerActive: bool("ExternalConnected"),
            isCharging: bool("IsCharging"),
            amperage: amperage,
            cycleCount: int("CycleCount") ?? 0,
            health: design > 0 ? Int((Double(rawMax) / Double(design) * 100).rounded()) : 0,
            maxCapacity: rawMax > 0 ? rawMax : nil,
            designCapacity: design > 0 ? design : nil,
            power: power
        )
    }
}
