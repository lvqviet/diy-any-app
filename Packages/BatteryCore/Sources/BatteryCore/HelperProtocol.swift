import Foundation

/// Shared constants between the app and the privileged helper.
public enum HelperConstants {
    public static let machServiceName = "com.diyanyapp.me.helper"
    public static let daemonPlistName = "com.diyanyapp.me.helper.plist"
    /// Bumped whenever the XPC interface changes so the app can ask to re-register.
    public static let protocolVersion = 1

    /// Only the main app signed by this team may talk to the helper.
    public static let clientRequirement =
        #"anchor apple generic and identifier "com.diyanyapp.me" and certificate leaf[subject.OU] = "U8GCXBC6Q3""#
    /// The app only talks to a helper signed by the same team.
    public static let helperRequirement =
        #"anchor apple generic and identifier "com.diyanyapp.me.helper" and certificate leaf[subject.OU] = "U8GCXBC6Q3""#
}

/// Status reported by the helper to the app.
public struct HelperStatus: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var capabilities: ChargeCapabilities
    /// False until the app has pushed settings (e.g. right after the helper restarted).
    public var enforcing: Bool
    public var settings: ChargeSettings
    public var session: SessionState
    public var mode: ChargeMode
    public var chargingEnabled: Bool
    public var adapterEnabled: Bool
    public var reading: BatteryReading?
    public var lastError: String?

    public init(protocolVersion: Int, capabilities: ChargeCapabilities, enforcing: Bool, settings: ChargeSettings,
                session: SessionState, mode: ChargeMode, chargingEnabled: Bool, adapterEnabled: Bool,
                reading: BatteryReading?, lastError: String?) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.enforcing = enforcing
        self.settings = settings
        self.session = session
        self.mode = mode
        self.chargingEnabled = chargingEnabled
        self.adapterEnabled = adapterEnabled
        self.reading = reading
        self.lastError = lastError
    }
}

/// XPC interface exported by the helper. Payloads are JSON so the shared Swift types stay
/// plain Codable structs. Each reply carries an error message, or nil on success.
@objc public protocol HelperXPCProtocol {
    func status(reply: @escaping (Data?, String?) -> Void)
    func applySettings(_ settingsJSON: Data, reply: @escaping (String?) -> Void)
    func setDischarge(_ active: Bool, reply: @escaping (String?) -> Void)
    func setTopUp(_ active: Bool, reply: @escaping (String?) -> Void)
}

public enum JSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
}
