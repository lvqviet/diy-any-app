import XCTest
@testable import BatteryCore

final class AppEnergyTests: XCTestCase {
    private func s(_ pid: pid_t, _ name: String, app: String? = nil, nj: UInt64, ns: UInt64, start: UInt64 = 1) -> ProcessSample {
        ProcessSample(pid: pid, name: name, appPath: app, energyNJ: nj, cpuNanos: ns, startTime: start)
    }

    func testOutermostApp() {
        XCTAssertEqual(AppEnergy.outermostApp("/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"),
                       "/Applications/Google Chrome.app")
        XCTAssertNil(AppEnergy.outermostApp("/opt/homebrew/bin/node"))
    }

    func testGroupsHelpersUnderApp() {
        let chrome = "/Applications/Google Chrome.app"
        let before: [pid_t: ProcessSample] = [1: s(1, "Google Chrome", app: chrome, nj: 0, ns: 0),
                      2: s(2, "Google Chrome", app: chrome, nj: 0, ns: 0)]
        let after: [pid_t: ProcessSample] = [1: s(1, "Google Chrome", app: chrome, nj: 2_000_000_000, ns: 500_000_000),
                     2: s(2, "Google Chrome", app: chrome, nj: 1_000_000_000, ns: 500_000_000)]
        let top = AppEnergy.top(previous: before, current: after, interval: 1)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top[0].watts, 3, accuracy: 0.001)
        XCTAssertEqual(top[0].cpuPercent, 100, accuracy: 0.001)
        XCTAssertEqual(Set(top[0].processes.keys), [1, 2])
    }

    func testSkipsNewAndReusedPIDs() {
        let before: [pid_t: ProcessSample] = [1: s(1, "old", nj: 0, ns: 0, start: 1)]
        let after: [pid_t: ProcessSample] = [1: s(1, "reused", nj: 9_000_000_000, ns: 0, start: 2),
                     2: s(2, "new", nj: 9_000_000_000, ns: 0)]
        XCTAssertTrue(AppEnergy.top(previous: before, current: after, interval: 1).isEmpty)
    }

    func testSortsLimitsAndExcludes() {
        var before: [pid_t: ProcessSample] = [:]
        var after: [pid_t: ProcessSample] = [:]
        for pid: pid_t in 1...8 {
            before[pid] = s(pid, "p\(pid)", nj: 0, ns: 0)
            after[pid] = s(pid, "p\(pid)", nj: UInt64(pid) * 1_000_000_000, ns: 0)
        }
        after[9] = s(9, "idle", nj: 0, ns: 0)
        before[9] = after[9]
        let top = AppEnergy.top(previous: before, current: after, interval: 2, excluding: "p8")
        XCTAssertEqual(top.map(\.name), ["p7", "p6", "p5", "p4", "p3"])
        XCTAssertEqual(top[0].watts, 3.5, accuracy: 0.001)
    }

    func testCPUDecidesBelowDisplayedWatts() {
        let before: [pid_t: ProcessSample] = [1: s(1, "decoder", nj: 0, ns: 0), 2: s(2, "iTerm", nj: 0, ns: 0)]
        let after: [pid_t: ProcessSample] = [1: s(1, "decoder", nj: 40_000_000, ns: 20_000_000),
                                             2: s(2, "iTerm", nj: 10_000_000, ns: 70_000_000)]
        XCTAssertEqual(AppEnergy.top(previous: before, current: after, interval: 1).map(\.name), ["iTerm", "decoder"])
    }
}
