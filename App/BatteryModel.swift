import AppKit
import BatteryCore
import Foundation
import Observation
import ServiceManagement

/// App-side state for the battery feature. Settings persist in UserDefaults and are pushed
/// to the helper, which owns the hardware.
@MainActor
@Observable
final class BatteryModel {
    enum HelperState: Equatable {
        case notInstalled
        case requiresApproval
        case connecting
        case connected
        case error(String)

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    private static let limitKey = "battery.limit"
    private static let autoDischargeKey = "battery.automaticDischarge"
    private static let sailingModeKey = "battery.sailingMode"
    private static let competingAppBundleIDs = ["com.apphousekitchen.aldente-pro", "com.apphousekitchen.aldente"]

    private(set) var helperState: HelperState = .connecting
    private(set) var status: HelperStatus?
    private(set) var lastError: String?
    private(set) var competingAppRunning = false
    /// Maximum Capacity as shown in System Settings (computed by macOS).
    private(set) var systemMaximumCapacity: Int?

    /// Limit shown on the slider while dragging; committed with `commitLimit()`.
    var draftLimit: Int
    private(set) var settings: ChargeSettings

    @ObservationIgnored private let client = HelperClient()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastCapacityCheck: Date?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    /// Windows (panel, main window) currently on screen. Polling is fast only while one is.
    @ObservationIgnored private var visibleWindows: Set<String> = []
    @ObservationIgnored private var powerMonitor: PowerSourceMonitor?
    @ObservationIgnored private var powerChangeTask: Task<Void, Never>?
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var pollAgain = false

    /// Status refresh while a window shows live power details. With every window closed only
    /// the menu bar label shows; power source notifications keep it current and the slow
    /// poll is a fallback for changes made by the helper alone (e.g. reaching the limit).
    private static let visiblePollInterval: Duration = .seconds(3)
    private static let hiddenPollInterval: Duration = .seconds(15)
    /// macOS sends several notifications for one plug or unplug; refresh once after them.
    private static let powerChangeDelay: Duration = .milliseconds(300)

    init() {
        let defaults = UserDefaults.standard
        let limit = defaults.object(forKey: Self.limitKey) as? Int ?? 80
        let initial = ChargeSettings(limit: limit,
                                     automaticDischarge: defaults.bool(forKey: Self.autoDischargeKey),
                                     sailingMode: defaults.bool(forKey: Self.sailingModeKey))
        settings = initial
        draftLimit = initial.limit
        client.onDisconnect = { [weak self] in
            Task { @MainActor in self?.handleDisconnect() }
        }
        observeCompetingApps()
        powerMonitor = PowerSourceMonitor { [weak self] in self?.powerSourceChanged() }
        start()
    }

    // MARK: Lifecycle

    func start() {
        refreshRegistration()
        guard pollTask == nil else { return }
        restartPolling()
    }

    /// Called by windows showing battery details; refreshes right away when one appears.
    func setWindowVisible(_ id: String, _ visible: Bool) {
        let wasVisible = !visibleWindows.isEmpty
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        if wasVisible != !visibleWindows.isEmpty { restartPolling() }
    }

    private func restartPolling() {
        pollTask?.cancel()
        let interval = visibleWindows.isEmpty ? Self.hiddenPollInterval : Self.visiblePollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    private func powerSourceChanged() {
        powerChangeTask?.cancel()
        powerChangeTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.powerChangeDelay) } catch { return }
            await self?.refresh()
        }
    }

    /// Refreshes the helper status. A request made while one is in flight runs once more
    /// right after it, so no change is missed and calls never overlap.
    private func refresh() async {
        if polling {
            pollAgain = true
            return
        }
        polling = true
        repeat {
            pollAgain = false
            await poll()
        } while pollAgain
        polling = false
    }

    func refreshRegistration() {
        switch client.registrationStatus {
        case .enabled:
            if helperState == .notInstalled || helperState == .requiresApproval { helperState = .connecting }
        case .requiresApproval:
            helperState = .requiresApproval
        case .notRegistered, .notFound:
            helperState = .notInstalled
        @unknown default:
            helperState = .notInstalled
        }
    }

    func installHelper() {
        do {
            try client.register()
            lastError = nil
        } catch {
            lastError = "Could not register helper: \(error.localizedDescription)"
        }
        refreshRegistration()
        if helperState == .requiresApproval { client.openLoginItemsSettings() }
    }

    func openLoginItemsSettings() { client.openLoginItemsSettings() }

    func uninstallHelper() {
        Task {
            do {
                try await client.unregister()
                status = nil
            } catch {
                lastError = "Could not unregister helper: \(error.localizedDescription)"
            }
            refreshRegistration()
        }
    }

    // MARK: Commands

    func commitLimit() {
        guard draftLimit != settings.limit else { return }
        settings.limit = draftLimit
        persistAndPush()
    }

    func setAutomaticDischarge(_ on: Bool) {
        settings.automaticDischarge = on
        persistAndPush()
    }

    func setSailingMode(_ on: Bool) {
        settings.sailingMode = on
        persistAndPush()
    }

    func toggleDischarge() {
        let active = !(status?.session.dischargeRequested ?? false)
        send { try await $0.setDischarge(active) }
    }

    func toggleTopUp() {
        let active = !(status?.session.topUpActive ?? false)
        send { try await $0.setTopUp(active) }
    }

    // MARK: Derived

    var canStartDischarge: Bool {
        guard let s = status, let r = s.reading else { return false }
        return s.capabilities.adapterControl && r.percent > settings.limit
            && ChargePolicy.isPluggedIn(r, adapterEnabledNow: s.adapterEnabled) && !settings.automaticDischarge
    }

    var canTopUp: Bool {
        guard let s = status, let r = s.reading else { return false }
        return s.capabilities.chargingControl && settings.limit < 100
            && ChargePolicy.isPluggedIn(r, adapterEnabledNow: s.adapterEnabled)
    }

    // MARK: Private

    private func persistAndPush() {
        let defaults = UserDefaults.standard
        defaults.set(settings.limit, forKey: Self.limitKey)
        defaults.set(settings.automaticDischarge, forKey: Self.autoDischargeKey)
        defaults.set(settings.sailingMode, forKey: Self.sailingModeKey)
        let settings = settings
        send { try await $0.apply(settings) }
    }

    private func send(_ action: @escaping (HelperClient) async throws -> Void) {
        Task {
            do {
                try await action(client)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            await refresh()
        }
    }

    private func poll() async {
        await refreshSystemCapacity()
        // Registration status is an XPC round trip to the system; only check it while not
        // connected. A failing status call below falls back to checking it.
        if helperState != .connected {
            refreshRegistration()
            guard helperState == .connecting || helperState.isError else { return }
        }
        do {
            var current = try await client.status()
            if current.protocolVersion != HelperConstants.protocolVersion {
                helperState = .error("Helper is outdated. Reinstall it from Settings.")
                return
            }
            // A fresh helper (first launch, restart, or after reconnect) needs our settings.
            if !current.enforcing || current.settings != settings {
                try await client.apply(settings)
                current = try await client.status()
            }
            if status != current { status = current }
            if helperState != .connected { helperState = .connected }
        } catch {
            helperState = .error(error.localizedDescription)
            refreshRegistration()
        }
    }

    private func observeCompetingApps() {
        let update: @MainActor () -> Void = { [weak self] in
            let running = NSWorkspace.shared.runningApplications.contains {
                Self.competingAppBundleIDs.contains($0.bundleIdentifier ?? "")
            }
            if self?.competingAppRunning != running { self?.competingAppRunning = running }
        }
        update()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification,
                              NSWorkspace.didTerminateApplicationNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { update() }
            }
        }
    }

    /// Maximum Capacity changes slowly; refresh it every 10 minutes.
    private func refreshSystemCapacity() async {
        if let last = lastCapacityCheck, Date().timeIntervalSince(last) < 600 { return }
        lastCapacityCheck = Date()
        systemMaximumCapacity = await Task.detached(priority: .utility) {
            SystemBatteryInfo.maximumCapacity()
        }.value
    }

    private func handleDisconnect() {
        if helperState == .connected { helperState = .connecting }
    }
}
