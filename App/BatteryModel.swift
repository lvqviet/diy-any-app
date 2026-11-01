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
        start()
    }

    // MARK: Lifecycle

    func start() {
        refreshRegistration()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
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
            await poll()
        }
    }

    private func poll() async {
        await refreshSystemCapacity()
        competingAppRunning = NSWorkspace.shared.runningApplications.contains {
            Self.competingAppBundleIDs.contains($0.bundleIdentifier ?? "")
        }
        refreshRegistration()
        guard client.registrationStatus == .enabled else { return }
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
            status = current
            helperState = .connected
        } catch {
            helperState = .error(error.localizedDescription)
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
