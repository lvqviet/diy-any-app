import Foundation

/// A group of SMC temperature sensors shown as one line on the chart.
public enum ThermalPart: String, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, ssd, battery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ssd: return "SSD"
        case .battery: return "Battery"
        }
    }

    /// Key prefixes on Apple Silicon. Each sensor is the prefix plus one character, and which
    /// characters exist differs per chip, so all are probed once.
    var keyPrefixes: [String] {
        switch self {
        case .cpu: return ["Tp0", "Tp1", "Te0"]   // performance and efficiency cores
        case .gpu: return ["Tg0", "Tg1"]
        case .ssd: return ["TH0"]                  // NAND
        case .battery: return ["TB0", "TB1", "TB2"]
        }
    }

    /// Readings outside this range come from unused or placeholder sensors.
    static let plausible = 5.0...130.0

    /// Highest plausible reading per part; parts without one are left out.
    public static func summarize(_ readings: [String: Double], keys: [ThermalPart: [String]]) -> [ThermalPart: Double] {
        var result: [ThermalPart: Double] = [:]
        for (part, partKeys) in keys {
            let values = partKeys.compactMap { readings[$0] }.filter { plausible.contains($0) }
            if let max = values.max() { result[part] = max }
        }
        return result
    }
}

/// Reads temperatures from the SMC. Read-only: works as a normal user, never writes keys.
public final class ThermalSensors {
    private let smc: SMC
    /// Temperature keys found on this Mac, per part.
    public let keys: [ThermalPart: [String]]

    public init() throws {
        let smc = try SMC()
        self.smc = smc
        let suffixes = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var found: [ThermalPart: [String]] = [:]
        for part in ThermalPart.allCases {
            found[part] = part.keyPrefixes.flatMap { prefix in
                suffixes.map { prefix + String($0) }
            }.filter { key in
                // Temperatures are 4-byte little-endian floats ("flt ").
                (try? smc.info(key)).flatMap { $0 }.map { $0.type == "flt" && $0.size == 4 } ?? false
            }
        }
        keys = found
    }

    public func read() -> [ThermalPart: Double] {
        var readings: [String: Double] = [:]
        for key in keys.values.joined() {
            if let value = float(key) { readings[key] = value }
        }
        return ThermalPart.summarize(readings, keys: keys)
    }

    /// Current speed of each fan in rpm (0 while stopped). Empty on Macs without fans.
    public func fanSpeeds() -> [Double] {
        guard let count = try? smc.read("FNum").first else { return [] }
        return (0..<Int(count)).compactMap { float("F\($0)Ac") }
    }

    private func float(_ key: String) -> Double? {
        guard let bytes = try? smc.read(key), bytes.count == 4 else { return nil }
        return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
    }
}
