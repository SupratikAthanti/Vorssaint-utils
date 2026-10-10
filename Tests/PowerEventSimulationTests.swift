// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PowerEventSimulationTests {
    static func run(_ suite: TestSuite) {
        let fixture = BatteryTestFixture(); let battery = fixture.manager
        fixture.read(charge: 70); battery.controlEnabled = true
        battery.disableSleepUntilLimit = true
        suite.expect(fixture.hardware.sleepHeld, "below-limit control acquires the fake sleep assertion")
        battery.isTopUpActive = true
        fixture.read(charge: 70, plugged: false)
        suite.expect(!battery.isTopUpActive && !fixture.hardware.sleepHeld && !fixture.hardware.discharging,
                     "actual unplug transition clears transient control and sleep holds")
        fixture.read(charge: 70); battery.stopChargingWhenSleeping = true
        battery.handleSleep()
        suite.expect(fixture.hardware.inhibited && !fixture.hardware.discharging && !fixture.hardware.sleepHeld,
                     "sleep entry point inhibits charging without preserving discharge or assertions")
        battery.handleWake()
        suite.expect(!fixture.hardware.inhibited && battery.isCharging,
                     "wake reads new injected telemetry before resuming")
        battery.shutdown()
        suite.expect(!fixture.hardware.inhibited && !fixture.hardware.discharging && !fixture.hardware.sleepHeld,
                     "ordinary shutdown restores system control")
        let hold = BatteryTestFixture(); hold.read(charge: 70)
        hold.manager.controlEnabled = true; hold.manager.stopChargingWhenAppClosed = true
        hold.manager.shutdown()
        suite.expect(hold.hardware.inhibited && !hold.hardware.discharging && !hold.hardware.sleepHeld
                     && hold.defaults.bool(forKey: BatteryManager.recoveryKey),
                     "explicit quit hold leaves charging inhibited with recovery debt but no discharge")
        let recovering = BatteryManager(hardware: hold.hardware, defaults: hold.defaults, now: { hold.date })
        suite.expect(!hold.hardware.inhibited && !hold.defaults.bool(forKey: BatteryManager.recoveryKey),
                     "next initialization verifies automatic restoration before any fresh control")
        recovering.shutdown()
    }
}
