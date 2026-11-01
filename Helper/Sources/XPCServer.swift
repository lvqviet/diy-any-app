import BatteryCore
import Foundation
import os

private let log = Logger(subsystem: HelperConstants.machServiceName, category: "xpc")

/// Accepts connections from the signed app and forwards commands to the controller.
final class XPCServer: NSObject, NSXPCListenerDelegate, HelperXPCProtocol {
    private let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
    private let controller: ChargeController
    /// Connections that passed the code-signing check by sending at least one message.
    private var appConnections = Set<ObjectIdentifier>()

    init(controller: ChargeController) {
        self.controller = controller
        super.init()
        listener.delegate = self
    }

    func start() { listener.resume() }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from processes not matching the requirement are rejected by XPC.
        connection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = self
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connectionClosed(id) }
        }
        connection.resume()
        return true
    }

    // MARK: HelperXPCProtocol (called on XPC queues)

    func status(reply: @escaping (Data?, String?) -> Void) {
        onMain { controller in
            do { reply(try JSON.encode(controller.status()), nil) } catch { reply(nil, "\(error)") }
        }
    }

    func applySettings(_ settingsJSON: Data, reply: @escaping (String?) -> Void) {
        onMain { controller in
            do {
                controller.apply(try JSON.decode(ChargeSettings.self, settingsJSON))
                reply(nil)
            } catch {
                reply("Invalid settings: \(error)")
            }
        }
    }

    func setDischarge(_ active: Bool, reply: @escaping (String?) -> Void) {
        onMain { reply($0.setDischarge(active)) }
    }

    func setTopUp(_ active: Bool, reply: @escaping (String?) -> Void) {
        onMain { reply($0.setTopUp(active)) }
    }

    // MARK: Connection tracking

    private func onMain(_ work: @escaping (ChargeController) -> Void) {
        let id = NSXPCConnection.current().map(ObjectIdentifier.init)
        DispatchQueue.main.async { [self] in
            if let id, appConnections.insert(id).inserted {
                log.info("app connected (\(self.appConnections.count) active)")
            }
            work(controller)
        }
    }

    private func connectionClosed(_ id: ObjectIdentifier) {
        guard appConnections.remove(id) != nil else { return }
        log.info("app connection closed (\(self.appConnections.count) active)")
        if appConnections.isEmpty { controller.appDisconnected() }
    }
}
