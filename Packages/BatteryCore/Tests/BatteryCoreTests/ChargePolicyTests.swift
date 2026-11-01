import XCTest
@testable import BatteryCore

final class ChargePolicyTests: XCTestCase {
    private let full = ChargeCapabilities(chargingControl: true, adapterControl: true)

    private func reading(_ percent: Int, plugged: Bool = true) -> BatteryReading {
        BatteryReading(percent: percent, adapterConnected: plugged, externalPowerActive: plugged,
                       isCharging: false, amperage: 0, cycleCount: 0, health: 100)
    }

    private func decide(limit: Int = 80, auto: Bool = false, sailing: Bool = false, session: SessionState = .init(),
                        percent: Int, plugged: Bool = true, adapterOn: Bool = true,
                        caps: ChargeCapabilities? = nil) -> ChargeDecision {
        ChargePolicy.decide(settings: ChargeSettings(limit: limit, automaticDischarge: auto, sailingMode: sailing),
                            session: session,
                            reading: reading(percent, plugged: plugged), adapterEnabledNow: adapterOn,
                            capabilities: caps ?? full)
    }

    // MARK: Charge Limiter

    func testChargesBelowLimitAndKeepsAwake() {
        let d = decide(percent: 50)
        XCTAssertEqual(d.mode, .charging)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
        XCTAssertTrue(d.preventIdleSleep)
    }

    func testHoldsAtLimit() {
        let d = decide(percent: 80)
        XCTAssertEqual(d.mode, .holding)
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
        XCTAssertFalse(d.preventIdleSleep)
    }

    func testAboveLimitPausesWithoutDischarging() {
        let d = decide(limit: 50, percent: 80)
        XCTAssertEqual(d.mode, .holding)
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
    }

    func testLimit100ChargesNormally() {
        let d = decide(limit: 100, percent: 90)
        XCTAssertEqual(d.mode, .unlimited)
        XCTAssertTrue(d.chargingEnabled)
    }

    func testOnBatteryRestoresDefaults() {
        let d = decide(percent: 90, plugged: false)
        XCTAssertEqual(d.mode, .onBattery)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
    }

    func testSettingsClampLimit() {
        XCTAssertEqual(ChargeSettings(limit: 5).limit, 20)
        XCTAssertEqual(ChargeSettings(limit: 150).limit, 100)
    }

    // MARK: Discharge

    func testManualDischargeCutsAdapterAndPausesCharging() {
        let d = decide(session: .init(dischargeRequested: true), percent: 90)
        XCTAssertEqual(d.mode, .discharging)
        XCTAssertFalse(d.adapterEnabled)
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertTrue(d.preventIdleSleep)
        XCTAssertTrue(d.session.dischargeRequested)
    }

    func testDischargeStaysActiveWhileAdapterCutEvenIfMacOSReportsUnplugged() {
        let d = decide(session: .init(dischargeRequested: true), percent: 85, plugged: false, adapterOn: false)
        XCTAssertEqual(d.mode, .discharging)
    }

    func testManualDischargeEndsAtLimitAndHolds() {
        let d = decide(session: .init(dischargeRequested: true), percent: 80, plugged: false, adapterOn: false)
        XCTAssertEqual(d.mode, .holding)
        XCTAssertTrue(d.adapterEnabled)
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertFalse(d.session.dischargeRequested)
    }

    func testManualDischargeIgnoredWithoutAdapterControl() {
        let caps = ChargeCapabilities(chargingControl: true, adapterControl: false)
        let d = decide(session: .init(dischargeRequested: true), percent: 90, caps: caps)
        XCTAssertEqual(d.mode, .holding)
        XCTAssertFalse(d.session.dischargeRequested)
    }

    func testDischargeUsesPhysicalChargerStateWhenKnown() {
        var r = reading(90, plugged: false)
        r.chargerAttached = true
        let d = ChargePolicy.decide(settings: .init(limit: 80), session: .init(dischargeRequested: true),
                                    reading: r, adapterEnabledNow: false, capabilities: full)
        XCTAssertEqual(d.mode, .discharging)
    }

    func testUnplugDuringDischargeRestoresAdapter() {
        var r = reading(90, plugged: false)
        r.chargerAttached = false
        let d = ChargePolicy.decide(settings: .init(limit: 80, automaticDischarge: true),
                                    session: .init(dischargeRequested: true),
                                    reading: r, adapterEnabledNow: false, capabilities: full)
        XCTAssertEqual(d.mode, .onBattery)
        XCTAssertTrue(d.adapterEnabled)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertFalse(d.session.dischargeRequested)
    }

    func testUnplugDuringTopUpWhenAdapterCutIsDetected() {
        var r = reading(95, plugged: false)
        r.chargerAttached = false
        let d = ChargePolicy.decide(settings: .init(limit: 80), session: .init(topUpActive: true),
                                    reading: r, adapterEnabledNow: true, capabilities: full)
        XCTAssertFalse(d.session.topUpActive)
    }

    func testManualDischargeDroppedWhenUnpluggedWithAdapterOn() {
        let d = decide(session: .init(dischargeRequested: true), percent: 90, plugged: false, adapterOn: true)
        XCTAssertEqual(d.mode, .onBattery)
        XCTAssertFalse(d.session.dischargeRequested)
    }

    // MARK: Automatic Discharge

    func testAutomaticDischargeAboveLimit() {
        let d = decide(auto: true, percent: 92)
        XCTAssertEqual(d.mode, .discharging)
        XCTAssertFalse(d.adapterEnabled)
    }

    func testAutomaticDischargeHoldsAtLimit() {
        let d = decide(auto: true, percent: 80, plugged: false, adapterOn: false)
        XCTAssertEqual(d.mode, .holding)
        XCTAssertTrue(d.adapterEnabled)
    }

    func testAutomaticDischargeDoesNothingOnBattery() {
        let d = decide(auto: true, percent: 92, plugged: false)
        XCTAssertEqual(d.mode, .onBattery)
        XCTAssertTrue(d.adapterEnabled)
    }

    // MARK: Top Up

    func testTopUpChargesTo100() {
        let d = decide(session: .init(topUpActive: true), percent: 85)
        XCTAssertEqual(d.mode, .toppingUp)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertTrue(d.session.topUpActive)
    }

    func testTopUpOverridesAutomaticDischarge() {
        let d = decide(auto: true, session: .init(topUpActive: true), percent: 92)
        XCTAssertEqual(d.mode, .toppingUp)
        XCTAssertTrue(d.adapterEnabled)
    }

    func testTopUpEndsOnUnplug() {
        let d = decide(session: .init(topUpActive: true), percent: 100, plugged: false)
        XCTAssertFalse(d.session.topUpActive)
        XCTAssertEqual(d.mode, .onBattery)
        // Plugging back in applies the regular limit again.
        let next = decide(session: d.session, percent: 100)
        XCTAssertEqual(next.mode, .holding)
    }

    // MARK: Sailing Mode

    func testSailingPausesInsideGap() {
        let d = decide(sailing: true, percent: 76)
        XCTAssertEqual(d.mode, .sailing)
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
        XCTAssertFalse(d.preventIdleSleep)
    }

    func testSailingChargesAtThresholdBoundary() {
        XCTAssertEqual(decide(sailing: true, percent: 75).mode, .sailing)
        let d = decide(sailing: true, percent: 74)
        XCTAssertEqual(d.mode, .charging)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertTrue(d.session.chargingToLimit)
    }

    func testSailingFinishesChargeToLimit() {
        var session = decide(sailing: true, percent: 74).session
        for percent in 75...79 {
            let d = decide(sailing: true, session: session, percent: percent)
            XCTAssertEqual(d.mode, .charging, "at \(percent)%")
            session = d.session
        }
        let atLimit = decide(sailing: true, session: session, percent: 80)
        XCTAssertEqual(atLimit.mode, .holding)
        XCTAssertFalse(atLimit.session.chargingToLimit)
        // Drifting back down stays inside the gap without charging.
        XCTAssertEqual(decide(sailing: true, session: atLimit.session, percent: 78).mode, .sailing)
    }

    func testWithoutSailingChargesRightBelowLimit() {
        XCTAssertEqual(decide(percent: 79).mode, .charging)
    }

    func testEnablingSailingMidChargeKeepsCharging() {
        let charging = decide(percent: 77)
        XCTAssertTrue(charging.session.chargingToLimit)
        XCTAssertEqual(decide(sailing: true, session: charging.session, percent: 78).mode, .charging)
    }

    func testUnplugClearsChargeInProgress() {
        let d = decide(sailing: true, session: .init(chargingToLimit: true), percent: 77, plugged: false)
        XCTAssertFalse(d.session.chargingToLimit)
        XCTAssertEqual(decide(sailing: true, session: d.session, percent: 77).mode, .sailing)
    }

    func testTopUpIgnoresSailing() {
        let d = decide(sailing: true, session: .init(topUpActive: true), percent: 90)
        XCTAssertEqual(d.mode, .toppingUp)
        XCTAssertTrue(d.chargingEnabled)
    }

    func testSettingsDecodeWithoutSailingField() throws {
        let old = Data(#"{"limit":70,"automaticDischarge":true}"#.utf8)
        let s = try JSON.decode(ChargeSettings.self, old)
        XCTAssertEqual(s, ChargeSettings(limit: 70, automaticDischarge: true, sailingMode: false))
        XCTAssertEqual(try JSON.decode(SessionState.self, Data(#"{"topUpActive":true}"#.utf8)),
                       SessionState(topUpActive: true))
    }

    // MARK: Sleep and capabilities

    func testPreSleepPausesChargingWithLimitAndRestoresAdapter() {
        let s = ChargePolicy.preSleep(settings: .init(limit: 80), session: .init(dischargeRequested: true), capabilities: full)
        XCTAssertFalse(s.chargingEnabled)
        XCTAssertTrue(s.adapterEnabled)
    }

    func testPreSleepAllowsChargingWithoutLimitOrDuringTopUp() {
        XCTAssertTrue(ChargePolicy.preSleep(settings: .init(limit: 100), session: .init(), capabilities: full).chargingEnabled)
        XCTAssertTrue(ChargePolicy.preSleep(settings: .init(limit: 80), session: .init(topUpActive: true), capabilities: full).chargingEnabled)
    }

    func testUnsupportedFirmware() {
        let none = ChargeCapabilities(chargingControl: false, adapterControl: false)
        let d = decide(auto: true, percent: 90, caps: none)
        XCTAssertEqual(d.mode, .unsupported)
        XCTAssertTrue(d.chargingEnabled)
        XCTAssertTrue(d.adapterEnabled)
    }

    func testFourCC() {
        XCTAssertEqual(SMC.fourCC("CHTE"), 0x4348_5445)
        XCTAssertEqual(SMC.string(0x4348_5445), "CHTE")
    }
}
