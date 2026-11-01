import BatteryCore
import Foundation
import ServiceManagement

/// Registers the privileged helper with launchd and talks to it over XPC.
final class HelperClient {
    enum ClientError: LocalizedError {
        case helper(String)
        case noProxy
        var errorDescription: String? {
            switch self {
            case .helper(let m): return m
            case .noProxy: return "Cannot reach the helper"
            }
        }
    }

    private let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "com.diyanyapp.me.xpc-client")

    /// Called (on the main queue) whenever the connection to the helper drops.
    var onDisconnect: () -> Void = {}

    var registrationStatus: SMAppService.Status { service.status }

    func register() throws { try service.register() }

    func unregister() async throws {
        disconnect()
        try await service.unregister()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    func disconnect() {
        queue.sync {
            connection?.invalidate()
            connection = nil
        }
    }

    // MARK: Calls

    func status() async throws -> HelperStatus {
        let data: Data = try await call { proxy, done in
            proxy.status { data, error in
                if let data { done(.success(data)) } else { done(.failure(ClientError.helper(error ?? "No status"))) }
            }
        }
        return try JSON.decode(HelperStatus.self, data)
    }

    func apply(_ settings: ChargeSettings) async throws {
        let json = try JSON.encode(settings)
        try await simpleCall { proxy, reply in proxy.applySettings(json, reply: reply) }
    }

    func setDischarge(_ active: Bool) async throws {
        try await simpleCall { proxy, reply in proxy.setDischarge(active, reply: reply) }
    }

    func setTopUp(_ active: Bool) async throws {
        try await simpleCall { proxy, reply in proxy.setTopUp(active, reply: reply) }
    }

    // MARK: Plumbing

    private func simpleCall(_ body: @escaping (HelperXPCProtocol, @escaping (String?) -> Void) -> Void) async throws {
        let _: Bool = try await call { proxy, done in
            body(proxy) { error in
                if let error { done(.failure(ClientError.helper(error))) } else { done(.success(true)) }
            }
        }
    }

    private func call<T>(_ body: @escaping (HelperXPCProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let finish: (Result<T, Error>) -> Void = { result in
                if once.claim() { continuation.resume(with: result) }
            }
            let proxy = currentConnection().remoteObjectProxyWithErrorHandler { error in finish(.failure(error)) }
            guard let helper = proxy as? HelperXPCProtocol else { return finish(.failure(ClientError.noProxy)) }
            body(helper, finish)
        }
    }

    private func currentConnection() -> NSXPCConnection {
        queue.sync {
            if let connection { return connection }
            let c = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
            c.setCodeSigningRequirement(HelperConstants.helperRequirement)
            let drop: () -> Void = { [weak self, weak c] in
                guard let self else { return }
                self.queue.async {
                    if self.connection === c { self.connection = nil }
                }
                DispatchQueue.main.async { self.onDisconnect() }
            }
            c.interruptionHandler = drop
            c.invalidationHandler = drop
            c.resume()
            connection = c
            return c
        }
    }
}

/// Guards a continuation against being resumed twice (reply and error handler can both fire).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
