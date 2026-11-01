import XCTest
@testable import BatteryCore

final class FailSafeTests: XCTestCase {
    func testTripsOnceAtThreshold() {
        var safe = FailSafe(threshold: 3)
        XCTAssertFalse(safe.recordFailure())
        XCTAssertFalse(safe.recordFailure())
        XCTAssertFalse(safe.isTripped)
        XCTAssertTrue(safe.recordFailure())
        XCTAssertTrue(safe.isTripped)
        // Further failures do not re-apply the fallback.
        XCTAssertFalse(safe.recordFailure())
        XCTAssertTrue(safe.isTripped)
    }

    func testSuccessResetsCount() {
        var safe = FailSafe(threshold: 3)
        _ = safe.recordFailure()
        _ = safe.recordFailure()
        XCTAssertFalse(safe.recordSuccess())
        XCTAssertFalse(safe.recordFailure())
        XCTAssertFalse(safe.recordFailure())
        XCTAssertFalse(safe.isTripped)
    }

    func testRecoveryAfterTrip() {
        var safe = FailSafe(threshold: 2)
        _ = safe.recordFailure()
        XCTAssertTrue(safe.recordFailure())
        XCTAssertTrue(safe.recordSuccess())
        XCTAssertFalse(safe.isTripped)
        XCTAssertFalse(safe.recordSuccess())
    }

    func testThresholdAtLeastOne() {
        var safe = FailSafe(threshold: 0)
        XCTAssertTrue(safe.recordFailure())
    }
}
