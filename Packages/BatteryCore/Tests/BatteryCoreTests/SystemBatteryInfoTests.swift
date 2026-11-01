import XCTest
@testable import BatteryCore

final class SystemBatteryInfoTests: XCTestCase {
    func testParsesMaximumCapacity() {
        let json = """
        {"SPPowerDataType":[
          {"_name":"spbattery_information","sppower_battery_health_info":{
            "sppower_battery_cycle_count":155,"sppower_battery_health":"Good",
            "sppower_battery_health_maximum_capacity":"92%"}},
          {"_name":"sppower_information"}]}
        """
        XCTAssertEqual(SystemBatteryInfo.parseMaximumCapacity(Data(json.utf8)), 92)
    }

    func testMissingMaximumCapacity() {
        let json = #"{"SPPowerDataType":[{"_name":"sppower_information"}]}"#
        XCTAssertNil(SystemBatteryInfo.parseMaximumCapacity(Data(json.utf8)))
        XCTAssertNil(SystemBatteryInfo.parseMaximumCapacity(Data("not json".utf8)))
    }

    func testBatteryPowerFromVoltageAndCurrent() {
        var r = BatteryReading(percent: 50, adapterConnected: true, externalPowerActive: true,
                               isCharging: true, amperage: 1000, cycleCount: 0, health: 100)
        XCTAssertNil(r.batteryPower)
        r.power = PowerReading(batteryVoltage: 12_000)
        XCTAssertEqual(r.batteryPower ?? 0, 12, accuracy: 0.001)
        r.amperage = -500
        XCTAssertEqual(r.batteryPower ?? 0, -6, accuracy: 0.001)
    }
}
