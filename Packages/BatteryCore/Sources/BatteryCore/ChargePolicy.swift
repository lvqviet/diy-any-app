import Foundation

/// User-facing settings, owned by the app and pushed to the helper.
public struct ChargeSettings: Codable, Equatable, Sendable {
    public static let limitRange = 20...100
    /// How far below the limit the battery may drift before Sailing Mode charges again.
    public static let sailingGap = 5

    /// Charge limit in percent. 100 means no limit.
    public var limit: Int
    /// Discharge automatically whenever the battery is above the limit while plugged in.
    public var automaticDischarge: Bool
    /// Sailing Mode: below the limit, only start charging once the battery drops more than
    /// `sailingGap` below it. Avoids many tiny charge cycles while plugged in.
    public var sailingMode: Bool

    public init(limit: Int = 80, automaticDischarge: Bool = false, sailingMode: Bool = false) {
        self.limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        self.automaticDischarge = automaticDischarge
        self.sailingMode = sailingMode
    }

    /// Percent below which Sailing Mode starts charging again.
    public var sailingThreshold: Int { limit - Self.sailingGap }

    private enum CodingKeys: String, CodingKey { case limit, automaticDischarge, sailingMode }

    // Tolerates payloads from an older app or helper that lack newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(limit: try c.decode(Int.self, forKey: .limit),
                  automaticDischarge: try c.decodeIfPresent(Bool.self, forKey: .automaticDischarge) ?? false,
                  sailingMode: try c.decodeIfPresent(Bool.self, forKey: .sailingMode) ?? false)
    }
}

/// Short-lived session state owned by the helper.
public struct SessionState: Codable, Equatable, Sendable {
    /// User pressed Discharge; cleared once the battery reaches the limit.
    public var dischargeRequested = false
    /// Top Up is active; cleared when the adapter is unplugged.
    public var topUpActive = false
    /// A charge toward the limit is in progress. Sailing Mode lets it finish instead of
    /// stopping inside the gap. Cleared at the limit and on unplug.
    public var chargingToLimit = false

    public init(dischargeRequested: Bool = false, topUpActive: Bool = false, chargingToLimit: Bool = false) {
        self.dischargeRequested = dischargeRequested
        self.topUpActive = topUpActive
        self.chargingToLimit = chargingToLimit
    }

    private enum CodingKeys: String, CodingKey { case dischargeRequested, topUpActive, chargingToLimit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(dischargeRequested: try c.decodeIfPresent(Bool.self, forKey: .dischargeRequested) ?? false,
                  topUpActive: try c.decodeIfPresent(Bool.self, forKey: .topUpActive) ?? false,
                  chargingToLimit: try c.decodeIfPresent(Bool.self, forKey: .chargingToLimit) ?? false)
    }
}

/// What the controller is currently doing, for display.
public enum ChargeMode: String, Codable, Sendable {
    /// No limit in effect (limit is 100%), charging normally.
    case unlimited
    /// Running on battery, nothing to control.
    case onBattery
    /// Charging toward the limit.
    case charging
    /// At or above the limit, charging paused, running on adapter power.
    case holding
    /// Sailing Mode: below the limit but within the gap, charging paused.
    case sailing
    /// Adapter power cut so the battery drains toward the limit.
    case discharging
    /// Top Up: charging to 100% once.
    case toppingUp
    /// Firmware does not allow charge control.
    case unsupported
}

/// Desired hardware state plus updated session.
public struct ChargeDecision: Equatable, Sendable {
    public var chargingEnabled: Bool
    public var adapterEnabled: Bool
    /// Keep the Mac from idle-sleeping (charging toward the limit or discharging).
    public var preventIdleSleep: Bool
    public var mode: ChargeMode
    public var session: SessionState
}

/// Pure charge-control rules. No I/O, so it can be unit-tested.
public enum ChargePolicy {
    /// Decides the hardware state for a regular control-loop tick.
    ///
    /// - Parameters:
    ///   - adapterEnabledNow: current adapter switch state. Used only when the physical
    ///     charger state is unknown: after we cut the adapter macOS reports it unplugged.
    public static func decide(settings: ChargeSettings,
                              session: SessionState,
                              reading: BatteryReading,
                              adapterEnabledNow: Bool,
                              capabilities: ChargeCapabilities) -> ChargeDecision {
        var session = session
        let pluggedIn = isPluggedIn(reading, adapterEnabledNow: adapterEnabledNow)
        let percent = reading.percent

        // Top Up ends as soon as the adapter is unplugged; the regular limit applies again.
        if !pluggedIn {
            session.topUpActive = false
            session.chargingToLimit = false
        }

        let limit = session.topUpActive ? 100 : settings.limit

        // Manual Discharge finishes at the limit, or is dropped if there is no adapter to cut.
        if session.dischargeRequested && (percent <= limit || !pluggedIn || !capabilities.adapterControl) {
            session.dischargeRequested = false
        }

        let wantsDischarge = capabilities.adapterControl && pluggedIn && percent > limit
            && (session.dischargeRequested || settings.automaticDischarge)

        if wantsDischarge {
            session.chargingToLimit = false
            // Charging is also paused so that restoring the adapter at the target does not charge.
            return ChargeDecision(chargingEnabled: !capabilities.chargingControl, adapterEnabled: false,
                                  preventIdleSleep: true, mode: .discharging, session: session)
        }
        if !pluggedIn {
            return ChargeDecision(chargingEnabled: true, adapterEnabled: true,
                                  preventIdleSleep: false, mode: .onBattery, session: session)
        }
        if limit >= 100 {
            return ChargeDecision(chargingEnabled: true, adapterEnabled: true, preventIdleSleep: false,
                                  mode: session.topUpActive ? .toppingUp : .unlimited, session: session)
        }
        if !capabilities.chargingControl {
            return ChargeDecision(chargingEnabled: true, adapterEnabled: true,
                                  preventIdleSleep: false, mode: .unsupported, session: session)
        }
        if percent >= limit {
            session.chargingToLimit = false
            return ChargeDecision(chargingEnabled: false, adapterEnabled: true,
                                  preventIdleSleep: false, mode: .holding, session: session)
        }
        if settings.sailingMode && !session.chargingToLimit && percent >= settings.sailingThreshold {
            return ChargeDecision(chargingEnabled: false, adapterEnabled: true,
                                  preventIdleSleep: false, mode: .sailing, session: session)
        }
        session.chargingToLimit = true
        return ChargeDecision(chargingEnabled: true, adapterEnabled: true,
                              preventIdleSleep: true, mode: .charging, session: session)
    }

    /// Whether a charger is physically attached, regardless of our adapter switch.
    public static func isPluggedIn(_ reading: BatteryReading, adapterEnabledNow: Bool) -> Bool {
        reading.chargerAttached ?? (reading.adapterConnected || !adapterEnabledNow)
    }

    /// Hardware state to apply right before the system sleeps. Nothing runs while asleep, so
    /// the adapter is always restored (never drain during sleep) and charging is paused
    /// whenever a limit is in effect (never exceed the limit during sleep).
    public static func preSleep(settings: ChargeSettings, session: SessionState,
                                capabilities: ChargeCapabilities) -> (chargingEnabled: Bool, adapterEnabled: Bool) {
        let limit = session.topUpActive ? 100 : settings.limit
        let charging = limit >= 100 || !capabilities.chargingControl
        return (charging, true)
    }
}
