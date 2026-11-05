import AppKit
import BatteryCore
import Foundation
import Observation

/// Apps of this user using the most power right now. Samples only while the Battery page is
/// visible; nothing runs in the background otherwise.
@MainActor
@Observable
final class TopAppsModel {
    private static let sampleInterval: Duration = .seconds(3)
    /// How long an app gets to quit before Force Kill is offered.
    private static let terminateGrace: Duration = .seconds(3)

    /// Empty until two samples exist.
    private(set) var apps: [AppUsage] = []
    private(set) var measuring = true
    private(set) var lastError: String?
    /// Apps that did not quit after Quit; their rows offer Force Kill.
    private(set) var unresponsive: Set<String> = []

    @ObservationIgnored private var visibleWindows: Set<String> = []
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var previous: [pid_t: ProcessSample] = [:]
    @ObservationIgnored private var previousAt: ContinuousClock.Instant?
    @ObservationIgnored private let ownApp = Bundle.main.bundlePath

    func setWindowVisible(_ id: String, _ visible: Bool) {
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        if visibleWindows.isEmpty {
            sampleTask?.cancel()
            sampleTask = nil
            // A stale baseline would average over the hidden time.
            previous = [:]
            previousAt = nil
            measuring = true
        } else if sampleTask == nil {
            sampleTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sample()
                    do { try await Task.sleep(for: Self.sampleInterval) } catch { return }
                }
            }
        }
    }

    /// Asks a GUI app to quit (it may ask to save) or sends SIGTERM to a command line tool.
    func quit(_ app: AppUsage) {
        guard let alive = liveProcesses(app) else { return }
        if let running = runningApp(app) {
            running.terminate()
        } else if !signal(app, alive, SIGTERM) {
            return
        }
        let id = app.id
        Task { [weak self] in
            try? await Task.sleep(for: Self.terminateGrace)
            guard let self, liveProcesses(app, reportGone: false) != nil else { return }
            unresponsive.insert(id)
        }
    }

    func forceKill(_ app: AppUsage) {
        guard let alive = liveProcesses(app) else { return }
        if let running = runningApp(app) {
            running.forceTerminate()
            lastError = nil
        } else {
            _ = signal(app, alive, SIGKILL)
        }
        unresponsive.remove(app.id)
    }

    private func runningApp(_ app: AppUsage) -> NSRunningApplication? {
        guard let path = app.appPath else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }
    }

    /// Processes of `app` that are still the sampled ones; a reused PID has another start time.
    private func liveProcesses(_ app: AppUsage, reportGone: Bool = true) -> [pid_t]? {
        let alive = app.processes.filter { AppEnergy.sample(pid: $0.key)?.startTime == $0.value }.map(\.key)
        guard alive.isEmpty else { return alive }
        if reportGone {
            lastError = "\(app.name) is no longer running."
            unresponsive.remove(app.id)
        }
        return nil
    }

    private func signal(_ app: AppUsage, _ pids: [pid_t], _ sig: Int32) -> Bool {
        for pid in pids where Darwin.kill(pid, sig) != 0 && errno != ESRCH {
            lastError = "Could not stop \(app.name): \(String(cString: strerror(errno)))"
            return false
        }
        lastError = nil
        return true
    }

    private func sample() async {
        let current = await Task.detached(priority: .utility) { AppEnergy.sample() }.value
        let now = ContinuousClock.now
        if let previousAt {
            let elapsed = now - previousAt
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let top = AppEnergy.top(previous: previous, current: current, interval: seconds, excluding: ownApp)
            if top != apps { apps = top }
            measuring = false
            let shown = Set(top.map(\.id))
            if !unresponsive.isSubset(of: shown) { unresponsive.formIntersection(shown) }
        }
        previous = current
        previousAt = now
    }
}
