import Foundation

/// Battery values that macOS computes itself and only exposes through `system_profiler`.
public enum SystemBatteryInfo {
    /// Maximum Capacity as shown in System Settings › Battery › Battery Health, in percent.
    /// Differs from the raw full-charge / design capacity ratio. Takes about 0.1 s; no root needed.
    public static func maximumCapacity() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseMaximumCapacity(data)
    }

    static func parseMaximumCapacity(_ data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let health = item["sppower_battery_health_info"] as? [String: Any],
                  let value = health["sppower_battery_health_maximum_capacity"] else { continue }
            if let number = value as? NSNumber { return number.intValue }
            if let text = value as? String {
                return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
            }
        }
        return nil
    }
}
