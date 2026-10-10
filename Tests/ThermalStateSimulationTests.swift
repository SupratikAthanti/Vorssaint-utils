// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ThermalStateSimulationTests {
    static func run(_ suite: TestSuite) {
        let fixture = BatteryTestFixture(); let battery = fixture.manager
        fixture.read(charge: 90); battery.controlEnabled = true
        battery.isDischargeActive = true
        suite.expect(fixture.hardware.discharging, "controlled telemetry starts discharge")
        battery.heatProtectionEnabled = true
        fixture.read(charge: 90, temperature: 36)
        suite.expect(battery.heatProtectionTripped && fixture.hardware.inhibited && !fixture.hardware.discharging,
                     "heat protection stops forced discharge as well as charging")
        battery.isTopUpActive = true
        suite.expect(fixture.hardware.inhibited && !fixture.hardware.discharging,
                     "top up cannot override a verified thermal trip")
        fixture.read(charge: 90, temperature: 34)
        suite.expect(battery.heatProtectionTripped, "hysteresis holds protection above the recovery boundary")
        fixture.read(charge: 90, temperature: 33)
        suite.expect(!battery.heatProtectionTripped, "injected cooling reaches the recovery boundary")
        fixture.read(charge: 90, temperature: nil)
        suite.expect(battery.controlError != nil && !fixture.hardware.discharging,
                     "missing temperature returns control to the system instead of guessing it is cool")
    }
}
