import BatteryCore
import Darwin
import Foundation
import IOKit.pwr_mgt
import os

private let log = Logger(subsystem: HelperConstants.machServiceName, category: "controller")

/// Runs the charge-control loop. All methods must be called on the main queue.
///
/// Charge control is only enforced while the app is connected. When the last app
/// connection goes away (quit or crash) normal charging is restored.
final class ChargeController {
    private static let tickInterval: DispatchTimeInterval = .seconds(5)

    private let smc: SMC?
    private let hardware: ChargeHardware?
    private let capabilities: ChargeCapabilities
    private var settings = ChargeSettings()
    private var session = SessionState()
    private var mode: ChargeMode = .unlimited
    private var enforcing = false
    private var sleeping = false
    private var lastError: String?
    private var idleSleepAssertion: IOPMAssertionID?
    private var timer: DispatchSourceTimer?
    private let executableMTime = ChargeController.currentExecutableMTime()

    init() {
        do {
            let smc = try SMC()
            let hw = try SMCChargeHardware(smc: smc)
            self.smc = smc
            hardware = hw
            capabilities = hw.capabilities
        } catch {
            log.error("SMC unavailable: \(String(describing: error), privacy: .public)")
            smc = nil
            hardware = nil
            capabilities = ChargeCapabilities(chargingControl: false, adapterControl: false)
            lastError = "SMC unavailable: \(error)"
        }
        log.info("capabilities: charging=\(self.capabilities.chargingControl) adapter=\(self.capabilities.adapterControl)")
    }

    func start() {
        // A previous instance may have crashed with the adapter cut or charging paused.
        restoreDefaults()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func shutdown() {
        log.info("shutting down, restoring normal charging")
        restoreDefaults()
    }

    // MARK: App commands

    func apply(_ newSettings: ChargeSettings) {
        settings = newSettings
        enforcing = true
        tick()
    }

    func setDischarge(_ active: Bool) -> String? {
        guard capabilities.adapterControl else { return "Discharge is not supported by this Mac's firmware" }
        session.dischargeRequested = active
        if active { session.topUpActive = false }
        tick()
        return nil
    }

    func setTopUp(_ active: Bool) -> String? {
        guard capabilities.chargingControl else { return "Top Up is not supported by this Mac's firmware" }
        session.topUpActive = active
        if active { session.dischargeRequested = false }
        tick()
        return nil
    }

    /// Called when the last app connection is gone.
    func appDisconnected() {
        log.info("app disconnected, restoring normal charging")
        enforcing = false
        session = SessionState()
        restoreDefaults()
    }

    func status() -> HelperStatus {
        let reading = try? BatteryReader.read(smc: smc)
        return HelperStatus(
            protocolVersion: HelperConstants.protocolVersion,
            capabilities: capabilities,
            enforcing: enforcing,
            settings: settings,
            session: session,
            mode: mode,
            chargingEnabled: (try? hardware?.isChargingEnabled()) ?? true,
            adapterEnabled: (try? hardware?.isAdapterEnabled()) ?? true,
            reading: reading,
            lastError: lastError
        )
    }

    // MARK: Sleep

    /// The system is about to sleep. Nothing runs while asleep, so leave a safe state:
    /// adapter restored and charging paused when a limit is in effect.
    func systemWillSleep() {
        sleeping = true
        guard enforcing, let hw = hardware else { return }
        let state = ChargePolicy.preSleep(settings: settings, session: session, capabilities: capabilities)
        apply(charging: state.chargingEnabled, adapter: state.adapterEnabled, on: hw)
        log.info("pre-sleep: charging=\(state.chargingEnabled) adapter=\(state.adapterEnabled)")
    }

    func systemDidWake() {
        sleeping = false
        tick()
    }

    // MARK: Loop

    func tick() {
        if executableChanged() {
            // The app was rebuilt or updated; exit so launchd starts the new helper binary.
            log.info("helper binary changed on disk, exiting for relaunch")
            restoreDefaults()
            exit(0)
        }
        guard enforcing, !sleeping, let hw = hardware else { return }
        do {
            let reading = try BatteryReader.read(smc: smc)
            let adapterNow = try hw.isAdapterEnabled()
            let decision = ChargePolicy.decide(settings: settings, session: session, reading: reading,
                                               adapterEnabledNow: adapterNow, capabilities: capabilities)
            session = decision.session
            if decision.mode != mode {
                log.info("mode \(self.mode.rawValue, privacy: .public) -> \(decision.mode.rawValue, privacy: .public) at \(reading.percent)%")
            }
            mode = decision.mode
            apply(charging: decision.chargingEnabled, adapter: decision.adapterEnabled, on: hw)
            setIdleSleepPrevented(decision.preventIdleSleep)
        } catch {
            fail("tick failed: \(error)")
        }
    }

    /// Writes only when the hardware differs from the desired state. Charging is set before the
    /// adapter so that restoring the adapter at the limit never starts a charge.
    private func apply(charging: Bool, adapter: Bool, on hw: ChargeHardware) {
        do {
            if capabilities.chargingControl, try hw.isChargingEnabled() != charging {
                try hw.setChargingEnabled(charging)
            }
            if capabilities.adapterControl, try hw.isAdapterEnabled() != adapter {
                try hw.setAdapterEnabled(adapter)
            }
            lastError = nil
        } catch {
            fail("hardware write failed: \(error)")
        }
    }

    private func restoreDefaults() {
        setIdleSleepPrevented(false)
        mode = .unlimited
        guard let hw = hardware else { return }
        apply(charging: true, adapter: true, on: hw)
    }

    private func setIdleSleepPrevented(_ prevent: Bool) {
        if prevent, idleSleepAssertion == nil {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "DIY Any App: reaching charge limit" as CFString, &id)
            if r == kIOReturnSuccess { idleSleepAssertion = id }
        } else if !prevent, let id = idleSleepAssertion {
            IOPMAssertionRelease(id)
            idleSleepAssertion = nil
        }
    }

    private func fail(_ message: String) {
        lastError = message
        log.error("\(message, privacy: .public)")
    }

    private func executableChanged() -> Bool {
        guard let original = executableMTime, let now = Self.currentExecutableMTime() else { return false }
        return original != now
    }

    /// Identity of this process's binary on disk (inode + mtime). Bundle.main points at the
    /// enclosing app bundle, so the path comes from the kernel instead.
    private static let executablePath: String? = {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }()

    private static func currentExecutableMTime() -> String? {
        guard let path = executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let inode = attrs[.systemFileNumber] as? NSNumber else { return nil }
        return "\(inode)-\(mtime.timeIntervalSince1970)"
    }
}
