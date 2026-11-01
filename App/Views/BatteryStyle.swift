import BatteryCore
import SwiftUI

/// Display helpers for charge modes.
enum BatteryStyle {
    static func title(_ mode: ChargeMode) -> String {
        switch mode {
        case .unlimited: return "Charging normally"
        case .onBattery: return "On battery"
        case .charging: return "Charging to limit"
        case .holding: return "Holding at limit"
        case .sailing: return "Sailing"
        case .discharging: return "Discharging"
        case .toppingUp: return "Topping up to 100%"
        case .unsupported: return "Charge control unsupported"
        }
    }

    static func detail(_ status: HelperStatus) -> String {
        let resume = "Charging resumes below \(status.settings.sailingThreshold)%."
        switch status.mode {
        case .unlimited: return "No charge limit in effect."
        case .onBattery: return "Plug in the adapter to control charging."
        case .charging: return "Sleep is held off until the limit is reached."
        case .holding:
            return status.settings.sailingMode
                ? "Charging is paused; the Mac runs on adapter power. \(resume)"
                : "Charging is paused; the Mac runs on adapter power."
        case .sailing: return "Running on adapter power without charging. \(resume)"
        case .discharging: return "Adapter power is cut; the Mac runs on battery while plugged in."
        case .toppingUp: return "Charging to 100% once. The limit returns when you unplug."
        case .unsupported: return "This Mac's firmware blocks charge control."
        }
    }

    static func color(_ status: HelperStatus) -> Color {
        switch status.mode {
        case .charging, .toppingUp: return .orange
        case .holding, .unlimited: return .green
        case .sailing: return .teal
        case .discharging: return .blue
        case .unsupported: return .red
        case .onBattery: return levelColor(status.reading?.percent ?? 100)
        }
    }

    static func levelColor(_ percent: Int) -> Color {
        switch percent {
        case ..<11: return .red
        case ..<21: return .orange
        default: return .green
        }
    }

    /// Colored icon for the mode, shown in the status header.
    static func icon(_ status: HelperStatus) -> String {
        switch status.mode {
        case .charging, .toppingUp: return "bolt.fill"
        case .unlimited: return status.reading?.isCharging == true ? "bolt.fill" : "powerplug.fill"
        case .holding: return "powerplug.fill"
        case .sailing: return "sailboat.fill"
        case .discharging: return "bolt.slash.fill"
        case .unsupported: return "xmark.octagon.fill"
        case .onBattery: return batterySymbol(status.reading?.percent ?? 100)
        }
    }

    /// Whether the mode is actively moving charge, used to animate its icon.
    static func isActive(_ mode: ChargeMode) -> Bool {
        mode == .charging || mode == .toppingUp
    }

    /// Monochrome menu bar symbol.
    static func symbol(for status: HelperStatus) -> String {
        switch status.mode {
        case .charging, .toppingUp:
            return "battery.100percent.bolt"
        case .unlimited where status.reading?.isCharging == true:
            return "battery.100percent.bolt"
        case .holding:
            return "powerplug"
        case .sailing:
            return "sailboat"
        case .discharging:
            return "bolt.slash"
        default:
            return batterySymbol(status.reading?.percent ?? 100)
        }
    }

    private static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Formatting for power values.
enum PowerFormat {
    static func watts(_ value: Double, signed: Bool = false) -> String {
        let magnitude = abs(value)
        let digits = magnitude < 10 ? "%.1f" : "%.0f"
        let number = String(format: digits, magnitude)
        guard signed else { return "\(number) W" }
        if magnitude < 0.05 { return "0 W" }
        return value > 0 ? "+\(number) W" : "−\(number) W"
    }

    static func volts(_ millivolts: Int) -> String { String(format: "%.2f V", Double(millivolts) / 1000) }

    static func amps(_ milliamps: Int) -> String { String(format: "%.2f A", Double(milliamps) / 1000) }
}
