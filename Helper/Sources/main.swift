import Foundation

// Any argument switches to the developer CLI (see DebugCLI).
let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty { exit(DebugCLI.main(arguments)) }

// Privileged helper: launched by launchd as root, registered by the app via SMAppService.
let controller = ChargeController()
let server = XPCServer(controller: controller)
let powerWatcher = PowerWatcher()

powerWatcher.onWillSleep = { controller.systemWillSleep() }
powerWatcher.onWake = { controller.systemDidWake() }
powerWatcher.onPowerSourceChange = { controller.tick() }

controller.start()
powerWatcher.start()
server.start()

// Restore normal charging when launchd stops the helper (unregister, shutdown).
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler {
    controller.shutdown()
    exit(0)
}
sigterm.resume()

CFRunLoopRun()
