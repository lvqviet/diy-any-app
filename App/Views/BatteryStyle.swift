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
        case .discharging: return "Discharging"
        case .toppingUp: return "Topping up to 100%"
        case .unsupported: return "Charge control unsupported"
        }
    }

    static func detail(_ mode: ChargeMode) -> String {
        switch mode {
        case .unlimited: return "No charge limit in effect."
        case .onBattery: return "Plug in the adapter to control charging."
        case .charging: return "Sleep is held off until the limit is reached."
        case .holding: return "Charging is paused; the Mac runs on adapter power."
        case .discharging: return "Adapter power is cut; the Mac runs on battery while plugged in."
        case .toppingUp: return "Charging to 100% once. The limit returns when you unplug."
        case .unsupported: return "This Mac's firmware blocks charge control."
        }
    }

    static func color(_ mode: ChargeMode) -> Color {
        switch mode {
        case .charging, .toppingUp: return .orange
        case .holding: return .green
        case .discharging: return .blue
        case .unsupported: return .red
        case .unlimited, .onBattery: return .secondary
        }
    }

    static func symbol(for status: HelperStatus) -> String {
        switch status.mode {
        case .charging, .toppingUp:
            return "battery.100percent.bolt"
        case .unlimited where status.reading?.isCharging == true:
            return "battery.100percent.bolt"
        case .holding:
            return "powerplug"
        case .discharging:
            return "arrow.down.circle"
        default:
            let p = status.reading?.percent ?? 100
            switch p {
            case ..<13: return "battery.0percent"
            case ..<38: return "battery.25percent"
            case ..<63: return "battery.50percent"
            case ..<88: return "battery.75percent"
            default: return "battery.100percent"
            }
        }
    }
}
