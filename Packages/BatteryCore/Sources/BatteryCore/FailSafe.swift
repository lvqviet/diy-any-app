/// Counts consecutive control-loop failures and decides when to fall back to normal charging.
///
/// A failing loop leaves the hardware in its last state, e.g. adapter power cut during a
/// discharge, which would drain the battery until macOS sleeps. After `threshold` failures in a
/// row the controller restores normal charging and keeps retrying; control resumes on success.
public struct FailSafe: Equatable, Sendable {
    public let threshold: Int
    public private(set) var consecutiveFailures = 0

    public init(threshold: Int = 3) {
        self.threshold = max(1, threshold)
    }

    /// Normal charging has been restored because of repeated failures.
    public var isTripped: Bool { consecutiveFailures >= threshold }

    /// Records a failed tick. Returns true exactly once, when the fallback should be applied.
    public mutating func recordFailure() -> Bool {
        consecutiveFailures += 1
        return consecutiveFailures == threshold
    }

    /// Records a successful tick. Returns true if control recovers from a fallback.
    public mutating func recordSuccess() -> Bool {
        defer { consecutiveFailures = 0 }
        return isTripped
    }
}
