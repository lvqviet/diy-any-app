import XCTest
@testable import BatteryCore

final class ThermalSensorsTests: XCTestCase {
    func testSummarizeAveragesPlausibleReadings() {
        let keys: [ThermalPart: [String]] = [.cpu: ["Tp05", "Tp0D", "Te05", "Te0P"], .gpu: ["Tg05"], .ssd: ["TH0x"], .battery: []]
        let readings = ["Tp05": 50, "Tp0D": 60, "Te05": 40, "Te0P": 0, "Tg05": 0, "TH0x": 33.5]
        let result = ThermalPart.summarize(readings, keys: keys)
        XCTAssertEqual(result[.cpu], ThermalReading(average: 50, hottest: 60), "the 0 °C placeholder is ignored")
        XCTAssertNil(result[.gpu], "a 0 °C placeholder is not a reading")
        XCTAssertEqual(result[.ssd], ThermalReading(average: 33.5, hottest: 33.5))
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
