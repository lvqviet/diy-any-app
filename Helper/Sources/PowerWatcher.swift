import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Delivers system sleep/wake events and power source changes on the main run loop.
final class PowerWatcher {
    // iokit_common_msg() values; the C macros are not imported into Swift.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemWillNotSleep: UInt32 = 0xE000_0290
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    var onWillSleep: () -> Void = {}
    var onWake: () -> Void = {}
    var onPowerSourceChange: () -> Void = {}

    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()

        rootPort = IORegisterForSystemPower(context, &notifyPort, { refcon, _, messageType, argument in
            guard let refcon else { return }
            let watcher = Unmanaged<PowerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(messageType, argument)
        }, &notifier)
        if rootPort != 0, let port = notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        }

        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue().onPowerSourceChange()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func handle(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        let token = Int(bitPattern: argument)
        switch messageType {
        case Self.canSystemSleep:
            // Idle sleep is held off with a power assertion instead of vetoing here.
            IOAllowPowerChange(rootPort, token)
        case Self.systemWillSleep:
            onWillSleep()
            IOAllowPowerChange(rootPort, token)
        case Self.systemWillNotSleep, Self.systemHasPoweredOn:
            onWake()
        default:
            break
        }
    }
}
