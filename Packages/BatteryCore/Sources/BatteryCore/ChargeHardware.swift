import Foundation

/// Which charge-control features the firmware exposes.
public struct ChargeCapabilities: Codable, Equatable, Sendable {
    /// Can pause/resume battery charging while on adapter power (Charge Limiter, Top Up).
    public var chargingControl: Bool
    /// Can cut adapter power so the Mac runs on battery while plugged in (Discharge).
    public var adapterControl: Bool

    public init(chargingControl: Bool, adapterControl: Bool) {
        self.chargingControl = chargingControl
        self.adapterControl = adapterControl
    }
}

/// Hardware switches the controller drives. Abstracted so the policy can be tested.
public protocol ChargeHardware: AnyObject {
    var capabilities: ChargeCapabilities { get }
    func isChargingEnabled() throws -> Bool
    func setChargingEnabled(_ enabled: Bool) throws
    func isAdapterEnabled() throws -> Bool
    func setAdapterEnabled(_ enabled: Bool) throws
}

/// SMC-backed implementation for Apple Silicon. Writes require root.
///
/// Key semantics (from probing and the open-source `batt` project):
/// - `CHTE` (ui32): 00000000 = charging allowed, 01000000 = charging inhibited (macOS 15/26-era firmware).
/// - `CH0B` + `CH0C` (ui8): 00 = allowed, 02 = inhibited (older firmware).
/// - `CH0J` (ui8): 00 = adapter on, 01 = adapter cut.
/// - `CHIE` (hex_): 00 = adapter on, 08 = adapter cut.
public final class SMCChargeHardware: ChargeHardware {
    private enum ChargingKeys { case chte, ch0bc, none }
    private enum AdapterKey: String { case ch0j = "CH0J", chie = "CHIE" }

    private let smc: SMC
    private let chargingKeys: ChargingKeys
    private let adapterKey: AdapterKey?

    public let capabilities: ChargeCapabilities

    public init(smc: SMC) throws {
        self.smc = smc
        if try smc.info("CHTE")?.size == 4 {
            chargingKeys = .chte
        } else if try smc.info("CH0B")?.size == 1, try smc.info("CH0C")?.size == 1 {
            chargingKeys = .ch0bc
        } else {
            chargingKeys = .none
        }
        if try smc.info(AdapterKey.ch0j.rawValue)?.size == 1 {
            adapterKey = .ch0j
        } else if try smc.info(AdapterKey.chie.rawValue)?.size == 1 {
            adapterKey = .chie
        } else {
            adapterKey = nil
        }
        capabilities = ChargeCapabilities(chargingControl: chargingKeys != .none, adapterControl: adapterKey != nil)
    }

    public func isChargingEnabled() throws -> Bool {
        switch chargingKeys {
        case .chte: return try smc.read("CHTE") == [0, 0, 0, 0]
        case .ch0bc: return try smc.read("CH0B") == [0]
        case .none: return true
        }
    }

    public func setChargingEnabled(_ enabled: Bool) throws {
        switch chargingKeys {
        case .chte:
            try smc.write("CHTE", enabled ? [0, 0, 0, 0] : [1, 0, 0, 0])
        case .ch0bc:
            let v: [UInt8] = enabled ? [0] : [2]
            try smc.write("CH0B", v)
            try smc.write("CH0C", v)
        case .none:
            break
        }
    }

    public func isAdapterEnabled() throws -> Bool {
        guard let key = adapterKey else { return true }
        return try smc.read(key.rawValue) == [0]
    }

    public func setAdapterEnabled(_ enabled: Bool) throws {
        guard let key = adapterKey else { return }
        switch key {
        case .ch0j: try smc.write(key.rawValue, enabled ? [0] : [1])
        case .chie: try smc.write(key.rawValue, enabled ? [0] : [8])
        }
    }
}
