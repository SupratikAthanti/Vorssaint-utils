// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class BatteryTestFixture {
    final class Hardware: BatteryControlHardware {
        var reading: BatteryTelemetry?
        var writes: [String] = []
        var inhibited = false
        var discharging = false
        var sleepHeld = false
        var refusesDischarge = false
        func sample() -> BatteryTelemetry? { reading }
        func setChargingInhibited(_ value: Bool) -> Bool {
            writes.append("charge:\(value)"); inhibited = value; return true
        }
        func setDischargeMode(_ value: Bool) -> Bool {
            writes.append("discharge:\(value)")
            if refusesDischarge { return false }
            discharging = value; return true
        }
        func setMagSafeLED(_ state: BatteryManager.MagSafeState) -> Bool { writes.append("led"); return true }
        func preventSleep(_ value: Bool) -> Bool { writes.append("sleep:\(value)"); sleepHeld = value; return true }
    }
    let name = "com.vorssaint.tests.battery.\(UUID().uuidString)"
    let defaults: UserDefaults
    let hardware = Hardware()
    final class Clock { var date = Date(timeIntervalSince1970: 1_700_000_000) }
    let clock = Clock()
    var date: Date {
        get { clock.date }
        set { clock.date = newValue }
    }
    lazy var manager = BatteryManager(hardware: hardware, defaults: defaults, now: { [clock] in clock.date })
    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }
    func read(charge: Int = 80, plugged: Bool = true, temperature: Double? = 28) {
        hardware.reading = BatteryTelemetry(charge: charge, pluggedIn: plugged,
                                             temperature: temperature, observedAt: date)
        manager.pollTelemetry()
    }
    deinit { manager.shutdown(); defaults.removePersistentDomain(forName: name) }
}

enum BatteryManagerTests {
    static func run(_ suite: TestSuite) {
        let fixture = BatteryTestFixture(); let battery = fixture.manager
        fixture.read()
        suite.expect(fixture.hardware.writes.isEmpty, "battery control is off until explicitly enabled")
        battery.controlEnabled = true
        suite.expect(fixture.hardware.inhibited && !battery.isCharging, "limit inhibits charging through the production engine")
        fixture.read(charge: 70)
        suite.expect(!fixture.hardware.inhibited && battery.isCharging, "fresh below-limit telemetry enables verified charging")
        battery.toggleTopUp(); fixture.read(charge: 90)
        suite.expect(!fixture.hardware.inhibited, "top up permits charging above the ordinary limit")
        battery.toggleTopUp()
        suite.expect(fixture.hardware.inhibited, "ending top up restores the limit")
        battery.startCalibration(); fixture.read(charge: 100)
        suite.expect(battery.calibrationStage == .dischargingTo10 && fixture.hardware.discharging,
                     "calibration reaches its real discharge stage")
        fixture.read(charge: 10)
        suite.expect(battery.calibrationStage == .rechargingTo100 && !fixture.hardware.discharging,
                     "calibration clears discharge in the transition at ten percent")
        battery.stopCalibration()
        suite.expect(!fixture.hardware.discharging && battery.calibrationStage == .inactive,
                     "stopping calibration clears discharge immediately")
        battery.executeTask(.init(name: "limit", actionRaw: "setLimit", timeOfDaySeconds: 0, enabled: true, targetLimit: 75))
        suite.expect(battery.chargeLimit == 75, "valid scheduled task changes the production limit")
        battery.executeTask(.init(name: "invalid", actionRaw: "setLimit", timeOfDaySeconds: 0, enabled: true, targetLimit: Int.min))
        suite.expect(battery.chargeLimit == 75, "invalid scheduled targets never reach hardware")
        battery.sailingHysteresis = Int.min
        suite.expect(battery.controlError != nil && !fixture.hardware.discharging,
                     "extreme hysteresis is refused without integer overflow")
        battery.sailingHysteresis = 5
        fixture.date.addTimeInterval(7); battery.evaluatePowerState()
        suite.expect(battery.controlError != nil && !fixture.hardware.inhibited,
                     "stale telemetry restores automatic control")
        fixture.read(charge: 90); fixture.hardware.refusesDischarge = true
        battery.isDischargeActive = true
        suite.expect(battery.controlError != nil && !battery.isDischarging,
                     "a rejected hardware write is not presented as verified discharge")
        suite.expect(fixture.defaults.bool(forKey: BatteryManager.recoveryKey),
                     "failed restoration keeps recovery debt")
        fixture.hardware.refusesDischarge = false; battery.controlEnabled = false
        suite.expect(!fixture.defaults.bool(forKey: BatteryManager.recoveryKey),
                     "verified restoration retires recovery debt")
    }
}
