import BatteryCore
import Foundation
import Observation

/// Temperatures of the last hour. Samples in the background every 15 s so the chart already
/// has history when opened, and every 5 s while the Sensors page is visible.
@MainActor
@Observable
final class SensorsModel {
    struct Sample: Identifiable {
        let date: Date
        let values: [ThermalPart: Double]
        var id: Date { date }
    }

    static let window: TimeInterval = 3600
    private static let backgroundInterval: Duration = .seconds(15)
    private static let visibleInterval: Duration = .seconds(5)

    private(set) var history: [Sample] = []
    private(set) var fanSpeeds: [Double] = []
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    /// Set when the SMC cannot be opened; nothing is sampled then.
    private(set) var unavailable: String?

    @ObservationIgnored private let sensors: ThermalSensors?
    @ObservationIgnored private var visibleWindows: Set<String> = []
    @ObservationIgnored private var sampleTask: Task<Void, Never>?

    init() {
        do {
            sensors = try ThermalSensors()
        } catch {
            sensors = nil
            unavailable = "Temperature sensors are not readable: \(error)"
            return
        }
        restartLoop()
    }

    var latest: Sample? { history.last }

    func setWindowVisible(_ id: String, _ visible: Bool) {
        let wasVisible = !visibleWindows.isEmpty
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        if wasVisible != !visibleWindows.isEmpty { restartLoop() }
    }

    private func restartLoop() {
        guard sensors != nil else { return }
        sampleTask?.cancel()
        let interval = visibleWindows.isEmpty ? Self.backgroundInterval : Self.visibleInterval
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    private func sample() {
        guard let sensors else { return }
        // About 25 SMC reads, well under a millisecond, so this stays on the main actor.
        let now = Date()
        history.append(Sample(date: now, values: sensors.read()))
        history.removeAll { now.timeIntervalSince($0.date) > Self.window }
        fanSpeeds = sensors.fanSpeeds()
        thermalState = ProcessInfo.processInfo.thermalState
    }
}
