import XCTest
@testable import BatteryCore

final class ThermalSensorsTests: XCTestCase {
    func testSummarizeTakesHighestPlausibleReading() {
        let keys: [ThermalPart: [String]] = [.cpu: ["Tp05", "Tp0D", "Te05"], .gpu: ["Tg05"], .ssd: ["TH0x"], .battery: []]
        let readings = ["Tp05": 50.3, "Tp0D": 57.5, "Te05": 44.2, "Tg05": 0, "TH0x": 33.5]
        let result = ThermalPart.summarize(readings, keys: keys)
        XCTAssertEqual(result[.cpu], 57.5)
        XCTAssertNil(result[.gpu], "a 0 °C placeholder is not a reading")
        XCTAssertEqual(result[.ssd], 33.5)
        XCTAssertNil(result[.battery])
    }

    /// Runs on real hardware: every part has sensors on Apple Silicon MacBooks.
    func testReadsThisMac() throws {
        let sensors = try ThermalSensors()
        let values = sensors.read()
        for part in ThermalPart.allCases {
            XCTAssertNotNil(values[part], "\(part.title) keys: \(sensors.keys[part] ?? [])")
        }
    }
}
