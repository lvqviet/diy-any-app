import BatteryCore
import Foundation

/// Hardware used by the running self-test, reachable from the signal handler.
nonisolated(unsafe) private var selfTestHardware: SMCChargeHardware?

/// Developer commands for testing on real hardware without the app or launchd:
///
///     DIYAnyAppHelper status
///     sudo DIYAnyAppHelper charging on|off
///     sudo DIYAnyAppHelper adapter on|off
///     sudo DIYAnyAppHelper selftest
///     sudo DIYAnyAppHelper run [--limit 80] [--auto-discharge] [--sailing] [--discharge] [--top-up] [--seconds N]
enum DebugCLI {
    static func main(_ args: [String]) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            switch args.first {
            case "status":
                try printStatus()
            case "charging":
                try setSwitch(args) { try $0.setChargingEnabled($1) }
            case "adapter":
                try setSwitch(args) { try $0.setAdapterEnabled($1) }
            case "selftest":
                return try selfTest()
            case "run":
                try runLoop(Array(args.dropFirst()))
            default:
                print("""
                usage: DIYAnyAppHelper status
                       sudo DIYAnyAppHelper charging on|off
                       sudo DIYAnyAppHelper adapter on|off
                       sudo DIYAnyAppHelper selftest
                       sudo DIYAnyAppHelper run [--limit N] [--auto-discharge] [--sailing] [--discharge] [--top-up] [--seconds N]
                """)
                return 64
            }
            return 0
        } catch {
            print("error: \(error)")
            return 1
        }
    }

    // MARK: status / switches

    private static func printStatus() throws {
        let smc = try SMC()
        let hw = try SMCChargeHardware(smc: smc)
        print("capabilities: charging=\(hw.capabilities.chargingControl) adapter=\(hw.capabilities.adapterControl)")
        print("chargingEnabled=\(try hw.isChargingEnabled()) adapterEnabled=\(try hw.isAdapterEnabled())")
        print(snapshot(smc))
        if let r = try? BatteryReader.read(smc: smc) {
            let p = r.power
            print("adapter=\(p?.adapterName ?? "-") \(p?.adapterWatts.map { "\($0)W" } ?? "-") "
                + "in=\(p?.inputPower.map { String(format: "%.1fW", $0) } ?? "-") "
                + "battery=\(r.batteryPower.map { String(format: "%+.1fW", $0) } ?? "-") "
                + "voltage=\(p?.batteryVoltage.map { "\($0)mV" } ?? "-") "
                + "capacity=\(r.maxCapacity ?? 0)/\(r.designCapacity ?? 0)mAh")
        }
    }

    private static func setSwitch(_ args: [String], _ body: (SMCChargeHardware, Bool) throws -> Void) throws {
        guard args.count == 2, ["on", "off"].contains(args[1]) else {
            print("usage: \(args[0]) on|off")
            return
        }
        try requireRoot()
        let smc = try SMC()
        try body(try SMCChargeHardware(smc: smc), args[1] == "on")
        print(snapshot(smc))
    }

    // MARK: selftest

    /// Toggles each switch and checks that the battery actually reacts. Always restores
    /// normal charging and adapter power at the end.
    private static func selfTest() throws -> Int32 {
        try requireRoot()
        let smc = try SMC()
        let hw = try SMCChargeHardware(smc: smc)
        print("capabilities: charging=\(hw.capabilities.chargingControl) adapter=\(hw.capabilities.adapterControl)")
        let initial = try BatteryReader.read(smc: smc)
        guard initial.chargerAttached ?? initial.adapterConnected else {
            print("FAIL: plug in the charger first")
            return 1
        }
        defer {
            try? hw.setChargingEnabled(true)
            try? hw.setAdapterEnabled(true)
            print("restored: \(snapshot(smc))")
        }
        // The test blocks the main thread, so Ctrl+C is handled by a plain signal handler
        // that restores both switches before exiting.
        selfTestHardware = hw
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { _ in
                try? selfTestHardware?.setChargingEnabled(true)
                try? selfTestHardware?.setAdapterEnabled(true)
                print("\ninterrupted, normal charging restored")
                exit(130)
            }
        }

        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "PASS: \(name)" : "FAIL: \(name)")
            if !ok { failures += 1 }
        }

        // Current comes from SMC B0AC (real time). Thresholds leave room for sensor noise.
        let chargingThreshold = 100, drainingThreshold = -100

        print("baseline: \(snapshot(smc))")
        if initial.amperage <= chargingThreshold {
            print("INFO: battery is not charging at baseline (full, or macOS Optimized Charging is holding it); "
                + "the charging-off check is less meaningful")
        }

        if hw.capabilities.chargingControl {
            try hw.setChargingEnabled(false)
            check("CHTE write reads back as charging disabled", try !hw.isChargingEnabled())
            let r = waitFor(smc, "charging off") { $0.amperage <= chargingThreshold }
            check("battery stops charging", r.amperage <= chargingThreshold)
            check("Mac stays on adapter power", r.externalPowerActive && r.amperage > drainingThreshold)

            try hw.setChargingEnabled(true)
            check("CHTE write reads back as charging enabled", try hw.isChargingEnabled())
            let r2 = waitFor(smc, "charging on") { $0.amperage > chargingThreshold }
            print(r2.amperage > chargingThreshold
                ? "PASS: battery resumes charging"
                : "INFO: battery did not resume charging (full, or macOS Optimized Charging is holding it)")
        }

        if hw.capabilities.adapterControl {
            try hw.setAdapterEnabled(false)
            check("CH0J write reads back as adapter disabled", try !hw.isAdapterEnabled())
            let r = waitFor(smc, "adapter off") { $0.amperage < drainingThreshold }
            check("Mac runs on battery (negative current)", r.amperage < drainingThreshold)
            check("AC-W still reports the charger attached", r.chargerAttached == true)

            try hw.setAdapterEnabled(true)
            check("CH0J write reads back as adapter enabled", try hw.isAdapterEnabled())
            let r2 = waitFor(smc, "adapter on") { $0.externalPowerActive && $0.amperage > drainingThreshold }
            check("adapter power restored", r2.externalPowerActive && r2.amperage > drainingThreshold)
        }

        print(failures == 0 ? "RESULT: all checks passed" : "RESULT: \(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }

    /// Polls the battery until `condition` holds or the timeout expires; the gauge updates slowly.
    private static func waitFor(_ smc: SMC, _ label: String, timeout: TimeInterval = 30,
                                _ condition: (BatteryReading) -> Bool) -> BatteryReading {
        let start = Date()
        var reading = (try? BatteryReader.read(smc: smc))
        while Date().timeIntervalSince(start) < timeout {
            Thread.sleep(forTimeInterval: 3)
            reading = try? BatteryReader.read(smc: smc)
            if let r = reading, condition(r) { break }
        }
        print("\(label) after \(Int(Date().timeIntervalSince(start)))s: \(snapshot(smc))")
        return reading ?? BatteryReading(percent: 0, adapterConnected: false, externalPowerActive: false,
                                         isCharging: false, amperage: 0, cycleCount: 0, health: 0)
    }

    // MARK: run

    /// Runs the real controller in the foreground, printing a status line every 5 seconds.
    private static func runLoop(_ args: [String]) throws -> Never {
        try requireRoot()
        var limit = 80, auto = false, sailing = false, discharge = false, topUp = false
        var seconds: Int?
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--limit": limit = Int(it.next() ?? "") ?? limit
            case "--auto-discharge": auto = true
            case "--sailing": sailing = true
            case "--discharge": discharge = true
            case "--top-up": topUp = true
            case "--seconds": seconds = Int(it.next() ?? "")
            default: print("unknown option \(arg)"); exit(64)
            }
        }

        let controller = ChargeController()
        let watcher = PowerWatcher()
        watcher.onWillSleep = { print("event: will sleep"); controller.systemWillSleep() }
        watcher.onWake = { print("event: wake"); controller.systemDidWake() }
        watcher.onPowerSourceChange = { controller.tick() }
        controller.start()
        watcher.start()
        controller.apply(ChargeSettings(limit: limit, automaticDischarge: auto, sailingMode: sailing))
        if discharge, let error = controller.setDischarge(true) { print("discharge: \(error)") }
        if topUp, let error = controller.setTopUp(true) { print("top up: \(error)") }
        print("running with limit=\(limit) autoDischarge=\(auto) sailing=\(sailing) discharge=\(discharge) topUp=\(topUp)")

        let printer = DispatchSource.makeTimerSource(queue: .main)
        printer.schedule(deadline: .now(), repeating: .seconds(5))
        printer.setEventHandler {
            let s = controller.status()
            let r = s.reading
            print("\(timestamp()) \(r?.percent ?? -1)% mode=\(s.mode.rawValue) charging=\(s.chargingEnabled) "
                + "adapter=\(s.adapterEnabled) current=\(r?.amperage ?? 0)mA "
                + "attached=\(r?.chargerAttached.map(String.init) ?? "?") raw=\(r?.adapterConnected ?? false) "
                + "ext=\(r?.externalPowerActive ?? false) session=\(s.session)"
                + (s.lastError.map { " error=\($0)" } ?? ""))
        }
        printer.resume()

        let stop: () -> Void = {
            controller.shutdown()
            print("stopped, normal charging restored")
            exit(0)
        }
        var signalSources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler(handler: stop)
            source.resume()
            signalSources.append(source)
        }
        if let seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: stop)
        }
        withExtendedLifetime((watcher, printer, signalSources)) { CFRunLoopRun() }
        exit(0)
    }

    // MARK: helpers

    private static func requireRoot() throws {
        struct NotRoot: Error, CustomStringConvertible { var description: String { "this command must run as root (sudo)" } }
        guard getuid() == 0 else { throw NotRoot() }
    }

    private static func snapshot(_ smc: SMC) -> String {
        func hex(_ key: String) -> String {
            (try? smc.read(key))?.map { String(format: "%02x", $0) }.joined() ?? "-"
        }
        guard let r = try? BatteryReader.read(smc: smc) else { return "battery unreadable" }
        return "\(r.percent)% current=\(r.amperage)mA attached=\(r.chargerAttached.map(String.init) ?? "?") "
            + "raw=\(r.adapterConnected) ext=\(r.externalPowerActive) isCharging(lagging)=\(r.isCharging) "
            + "CHTE=\(hex("CHTE")) CH0J=\(hex("CH0J")) AC-W=\(hex("AC-W"))"
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
