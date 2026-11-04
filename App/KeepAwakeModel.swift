import AppKit
import DevCore
import Foundation
import Observation

/// Keep Awake (like `caffeinate -d`): holds a display sleep assertion until a chosen time.
/// Stops by itself on battery at `KeepAwakePolicy.lowBatteryPercent` or when the Mac is
/// critically hot, so a forgotten session cannot drain the battery or cook the Mac.
@MainActor
@Observable
final class KeepAwakeModel {
    static let durations: [(title: String, minutes: Int?)] = [
        ("15m", 15), ("30m", 30), ("1h", 60), ("2h", 120), ("4h", 240), ("∞", nil),
    ]

    private(set) var isActive = false
    /// nil while active means no time limit.
    private(set) var endDate: Date?
    /// Why Keep Awake cannot run right now (low battery, too hot).
    private(set) var blockReason: String?
    /// Shown after Keep Awake stopped by itself.
    private(set) var autoStopMessage: String?

    @ObservationIgnored private var assertion: DisplaySleepAssertion?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var powerMonitor: PowerSourceMonitor?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        powerMonitor = PowerSourceMonitor { [weak self] in self?.checkSafety() }
        let thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.checkSafety() } }
        // The timer may fire late if the Mac slept through the end time (e.g. lid closed).
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.checkEnd() } }
        observers = [thermal, wake]
        checkSafety()
    }

    func start(minutes: Int?) {
        checkSafety()
        guard blockReason == nil else { return }
        if assertion == nil {
            assertion = DisplaySleepAssertion(reason: "Keep Awake in DIY Any App")
        }
        guard assertion != nil else {
            autoStopMessage = "macOS refused to keep the display awake."
            return
        }
        isActive = true
        autoStopMessage = nil
        endDate = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        timerTask?.cancel()
        timerTask = nil
        if let minutes {
            timerTask = Task { [weak self] in
                // Continuous clock: time asleep counts toward the duration.
                try? await Task.sleep(for: .seconds(minutes * 60), clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.checkEnd()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        assertion = nil
        isActive = false
        endDate = nil
    }

    private func checkEnd() {
        if isActive, let endDate, endDate <= Date() { stop() }
    }

    private func checkSafety() {
        let reason = KeepAwakePolicy.blockReason(power: .current(), thermal: ProcessInfo.processInfo.thermalState)
        if blockReason != reason { blockReason = reason }
        if isActive, let reason {
            stop()
            autoStopMessage = "Stopped automatically: \(reason)."
        }
    }
}
