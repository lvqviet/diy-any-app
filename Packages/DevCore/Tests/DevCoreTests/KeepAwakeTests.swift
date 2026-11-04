import IOKit.pwr_mgt
import XCTest
@testable import DevCore

final class KeepAwakeTests: XCTestCase {
    func testBlockReason() {
        func reason(_ percent: Int?, onBattery: Bool, _ thermal: ProcessInfo.ThermalState = .nominal) -> String? {
            KeepAwakePolicy.blockReason(power: PowerState(batteryPercent: percent, onBattery: onBattery), thermal: thermal)
        }
        XCTAssertNil(reason(50, onBattery: true))
        XCTAssertNil(reason(21, onBattery: true))
        XCTAssertEqual(reason(20, onBattery: true), "Battery at 20%")
        XCTAssertNil(reason(5, onBattery: false)) // charging: no drain
        XCTAssertNil(reason(nil, onBattery: false)) // desktop Mac
        XCTAssertNil(reason(80, onBattery: true, .serious))
        XCTAssertEqual(reason(80, onBattery: false, .critical), "Mac is too hot")
    }

    func testAssertionIsHeldUntilReleased() throws {
        let name = "DevCore test \(UUID())"
        var assertion = DisplaySleepAssertion(reason: name)
        XCTAssertNotNil(assertion)
        XCTAssertTrue(ownAssertionNames().contains(name))
        assertion = nil
        XCTAssertFalse(ownAssertionNames().contains(name))
    }

    private func ownAssertionNames() -> [String] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return (dict[NSNumber(value: getpid())] ?? []).compactMap { $0[kIOPMAssertionNameKey] as? String }
    }
}
