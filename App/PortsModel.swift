import AppKit
import DevCore
import Foundation
import Observation

/// Listening ports of this user's processes. Scans only while a window showing them is
/// visible; nothing runs in the background otherwise.
@MainActor
@Observable
final class PortsModel {
    private static let showAllKey = "ports.showAll"
    private static let scanInterval: Duration = .seconds(2)
    /// How long a process gets to exit after SIGTERM before Force Kill is offered.
    private static let terminateGrace: Duration = .seconds(3)

    private(set) var ports: [ListeningPort] = []
    private(set) var lastError: String?
    /// Processes that ignored SIGTERM; their rows offer Force Kill.
    private(set) var unresponsive: Set<pid_t> = []
    var showAll: Bool {
        didSet { UserDefaults.standard.set(showAll, forKey: Self.showAllKey) }
    }

    /// Dev servers only, unless `showAll` is on.
    var visiblePorts: [ListeningPort] { showAll ? ports : ports.filter { !$0.isAppOrSystem } }
    var hiddenCount: Int { ports.count - visiblePorts.count }

    @ObservationIgnored private var visibleWindows: Set<String> = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        showAll = UserDefaults.standard.bool(forKey: Self.showAllKey)
    }

    func setWindowVisible(_ id: String, _ visible: Bool) {
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        if visibleWindows.isEmpty {
            scanTask?.cancel()
            scanTask = nil
        } else if scanTask == nil {
            scanTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.scan()
                    do { try await Task.sleep(for: Self.scanInterval) } catch { return }
                }
            }
        }
    }

    /// Sends SIGTERM, so the process can shut down cleanly.
    func stop(_ port: ListeningPort) {
        guard signal(port, SIGTERM) else { return }
        let pid = port.pid
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.scan()
            try? await Task.sleep(for: Self.terminateGrace)
            await self?.scan()
            // Still holding a port after the grace period: offer Force Kill.
            if let self, ports.contains(where: { $0.pid == pid }) { unresponsive.insert(pid) }
        }
    }

    func forceKill(_ port: ListeningPort) {
        guard signal(port, SIGKILL) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.scan()
        }
    }

    private func signal(_ port: ListeningPort, _ sig: Int32) -> Bool {
        // The PID may have been reused since the scan; only signal the same process.
        guard PortScanner.listeningPorts().contains(where: { $0.pid == port.pid && $0.startDate == port.startDate }) else {
            lastError = "\(port.processName) is no longer running."
            Task { await scan() }
            return false
        }
        if Darwin.kill(port.pid, sig) != 0 {
            lastError = "Could not stop \(port.processName): \(String(cString: strerror(errno)))"
            return false
        }
        lastError = nil
        return true
    }

    private func scan() async {
        let found = await Task.detached(priority: .userInitiated) { PortScanner.listeningPorts() }.value
        if found != ports { ports = found }
        let alive = Set(found.map(\.pid))
        if !unresponsive.isSubset(of: alive) { unresponsive.formIntersection(alive) }
    }
}
